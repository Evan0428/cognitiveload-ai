import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Learned cognitive-load weight for a single word.
class TermWeight {
  double score; // learned 0-100 load for this term
  int observations; // how many manual ratings taught it

  TermWeight(this.score, [this.observations = 1]);

  Map<String, dynamic> toJson() => {'s': score, 'n': observations};
  factory TermWeight.fromJson(Map<String, dynamic> j) =>
      TermWeight((j['s'] as num).toDouble(), (j['n'] as num).toInt());
}

/// Personalised NASA-TLX weight learner (Chua Yi Zhe).
///
/// The global [IntensityClassifier] applies the same keyword weights to every
/// user. In reality "Lab" may be gruelling for one student and routine for
/// another. Whenever the user overrides a task's score with the manual
/// NASA-TLX rating, that override is a **labelled training example**
/// (task title -> true perceived load). This class learns from those labels so
/// future tasks are scored with *this* user's weights.
///
/// Model: an incremental (online) mean per term, updated with the
/// Widrow-Hoff / LMS rule
///
///     w <- w + alpha * (target - w),   alpha = 1 / (1 + n * decay)
///
/// The learning rate decays with the number of observations, so early labels
/// move a term quickly and it converges as evidence accumulates. A task's
/// predicted score is the mean of its known terms; unseen tasks fall back to
/// the global keyword classifier, so the system degrades gracefully.
class TaskWeightLearner {
  TaskWeightLearner._();
  static final TaskWeightLearner instance = TaskWeightLearner._();

  static const _prefsKey = 'taskWeights';
  static const double _decay = 0.5;

  /// A term needs this many observations before it is trusted on its own.
  static const int confidentAfter = 3;

  /// Words carrying no workload meaning.
  static const _stopWords = {
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'about', 'into',
    'my', 'our', 'your', 'a', 'an', 'of', 'to', 'in', 'on', 'at', 'is',
    'new', 'am', 'pm', 'class', 'session', 'time',
  };

  final Map<String, TermWeight> _weights = {};

  /// Read-only view for the UI / report evidence.
  Map<String, TermWeight> get weights => Map.unmodifiable(_weights);

  bool get hasLearned => _weights.isNotEmpty;
  int get termsLearned => _weights.length;

  int get totalObservations =>
      _weights.values.fold(0, (sum, w) => sum + w.observations);

  // ------------------------------------------------------------ tokenising

  /// Split a title into meaningful lower-case terms.
  static List<String> tokenise(String title) {
    return title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();
  }

  // ------------------------------------------------------------ prediction

  /// Personalised score for [title], or null when nothing relevant is known
  /// yet (the caller then falls back to the global classifier).
  int? predict(String title) {
    final terms = tokenise(title);
    if (terms.isEmpty) return null;

    // Weight each known term by how much evidence backs it.
    double weighted = 0, confidence = 0;
    for (final t in terms) {
      final w = _weights[t];
      if (w == null) continue;
      final c = math.min(w.observations, confidentAfter) / confidentAfter;
      weighted += w.score * c;
      confidence += c;
    }
    if (confidence == 0) return null;

    final personal = weighted / confidence;

    // Blend with the global prior until the terms are well evidenced, so a
    // single rating cannot swing the score wildly.
    final trust = (confidence / terms.length).clamp(0.0, 1.0);
    final global = IntensityClassifier.scoreFromTitle(title).toDouble();
    return (global * (1 - trust) + personal * trust).round().clamp(0, 100);
  }

  /// Score to show for [title]: the personalised value when available,
  /// otherwise the shared keyword model.
  int scoreFor(String title) =>
      predict(title) ?? IntensityClassifier.scoreFromTitle(title);

  // -------------------------------------------------------------- learning

  /// Learn from a manual NASA-TLX override: [title] was really worth [score].
  ///
  /// The update itself is pure and synchronous — it depends on no plugins, so
  /// the model is unit-testable in isolation. Saving is a fire-and-forget side
  /// effect that can never break the caller.
  void learn(String title, int score) {
    final terms = tokenise(title);
    if (terms.isEmpty) return;

    for (final t in terms) {
      final existing = _weights[t];
      if (existing == null) {
        _weights[t] = TermWeight(score.toDouble());
      } else {
        // LMS update with a decaying learning rate.
        final alpha = 1.0 / (1.0 + existing.observations * _decay);
        existing.score += alpha * (score - existing.score);
        existing.observations++;
      }
    }
    save(); // persisted in the background; failures are swallowed
  }

  /// Plain-English account of how a score was reached (explainable AI).
  String explain(String title) {
    final terms = tokenise(title);
    final known = <String>[];
    for (final t in terms) {
      final w = _weights[t];
      if (w != null) {
        known.add('"$t" ≈ ${w.score.round()} (${w.observations}×)');
      }
    }
    if (known.isEmpty) {
      return 'Scored with the shared keyword model — rate this task manually '
          'to teach the app your own weighting.';
    }
    return 'Personalised from your past ratings: ${known.join(', ')}.';
  }

  // ----------------------------------------------------------- persistence

  Future<void> save() async {
    final data = jsonEncode(_weights.map((k, v) => MapEntry(k, v.toJson())));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, data);
    } catch (e) {
      // No platform bindings (e.g. unit tests) — learning still works in memory.
      debugPrint('Task weight local save skipped: $e');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'taskWeights': data}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Task weight cloud save failed (kept local): $e');
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_prefsKey);

    if (raw == null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          raw = doc.data()?['taskWeights'] as String?;
        } catch (e) {
          debugPrint('Task weight cloud load failed: $e');
        }
      }
    }
    if (raw == null) return;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _weights
        ..clear()
        ..addAll(map.map((k, v) =>
            MapEntry(k, TermWeight.fromJson(v as Map<String, dynamic>))));
    } catch (_) {
      // Corrupt cache — start fresh rather than crash.
    }
  }

  @visibleForTesting
  void reset() => _weights.clear();
}
