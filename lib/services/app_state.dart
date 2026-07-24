import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/task_model.dart';
import 'cognitive_load_engine.dart';
import 'health_service.dart';
import 'notification_service.dart';
import 'ocr_service.dart';

class AppState extends ChangeNotifier {
  final OcrService ocr = OcrService();
  final HealthService health = HealthService();
  final CognitiveLoadEngine engine = CognitiveLoadEngine();
  final NotificationService notifier = NotificationService();

  final List<ScheduleEvent> _events = [];
  PhysiologicalSnapshot? _snapshot;
  CognitiveLoadResult? _result;
  bool _loading = false;
  StreamSubscription<User?>? _authSubscription;

  /// One snapshot per day for up to 14 days — feeds the rolling baseline
  /// (Chua's module, report section 2.4.4).
  final List<PhysiologicalSnapshot> _history = [];

  /// Real-time strain tracking: periodic physiology refresh.
  Timer? _strainTimer;
  static const Duration strainInterval = Duration(minutes: 15);

  // Notification throttling so real alerts don't fire on every recompute.
  LoadLevel? _lastNotifiedLevel;
  DateTime? _lastNotifiedAt;

  List<ScheduleEvent> get events {
    final sorted = List<ScheduleEvent>.from(_events)
      ..sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(sorted);
  }

  PhysiologicalSnapshot? get snapshot => _snapshot;
  CognitiveLoadResult? get result => _result;
  bool get loading => _loading;

  /// Rolling personal baseline from prior days' snapshots (today excluded so a
  /// bad morning doesn't drag its own reference down).
  PhysiologicalBaseline? get baseline {
    final now = DateTime.now();
    final prior = _history
        .where((s) => !(s.timestamp.year == now.year &&
            s.timestamp.month == now.month &&
            s.timestamp.day == now.day))
        .toList();
    if (prior.isEmpty) return null;
    return PhysiologicalBaseline.fromSnapshots(prior);
  }

  final Map<String, int> _keywordScores = {
    'exam': 95,
    'test': 85,
    'quiz': 75,
    'lab': 65,
    'lecture': 45,
    'gym': 20,
    'workout': 20,
    'rest': 10,
  };

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    await notifier.init();
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((_) {
      syncTasksFromFirestore();
    });

    await _load();
    await syncTasksFromFirestore();
    await refreshPhysiology();
    _recompute();

    // Real-time workload strain tracking: re-sample physiology periodically so
    // HR spikes during a work session are caught, not just on manual sync.
    _strainTimer ??=
        Timer.periodic(strainInterval, (_) => refreshPhysiology());

    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _strainTimer?.cancel();
    super.dispose();
  }

  Future<void> syncTasksFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _events.clear();
      _recompute();
      notifyListeners();
      return;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .get()
          .timeout(const Duration(seconds: 5));

      _events
        ..clear()
        ..addAll(querySnapshot.docs.map(_taskDocToScheduleEvent));

      await _save();
      _recompute();
      notifyListeners();
    } catch (e) {
      debugPrint('Firebase task sync unavailable, using local user cache: $e');
      await _load();
      _recompute();
      notifyListeners();
    }
  }

  Future<int> scanAndImport(dynamic imageFile) async {
    _loading = true;
    notifyListeners();

    final file = imageFile is File ? imageFile : null;
    final extracted = await ocr.recognizeAndStructureImage(file);

    var counter = 0;
    for (final task in extracted) {
      final now = DateTime.now();
      final startParts = _dateTimeFromDateAndTime(now, task.startTime);
      final endParts = _dateTimeFromDateAndTime(
        now,
        task.endTime,
        fallback: startParts.add(const Duration(hours: 1, minutes: 30)),
      );
      final customScore = _getScoreByKeyword(task.subject);

      _events.add(ScheduleEvent(
        id: 'ocr_${DateTime.now().microsecondsSinceEpoch}_$counter',
        title: task.subject,
        start: startParts,
        end: endParts.isAfter(startParts)
            ? endParts
            : startParts.add(const Duration(hours: 1, minutes: 30)),
        intensity: _getIntensityByScore(customScore),
        source: 'ocr',
        cognitiveLoadScore: customScore,
        ratingType: 'Automatic (OCR)',
      ));
      counter++;
    }

    await _save();
    _recompute();
    _loading = false;
    notifyListeners();
    return extracted.length;
  }

  Future<String> extractRawText(dynamic imageFile) async {
    final file = imageFile is File ? imageFile : null;
    final tasks = await ocr.recognizeAndStructureImage(file);
    return tasks
        .map((e) => '${e.startTime}-${e.endTime} ${e.subject}')
        .join('\n');
  }

  void addEvent(ScheduleEvent e) {
    _events.add(e);
    _save();
    _recompute();
    notifyListeners();
  }

  void removeEvent(String id) {
    _events.removeWhere((e) => e.id == id);
    _save();
    _recompute();
    notifyListeners();
  }

  void updateIntensity(String id, TaskIntensity intensity) {
    final e = _events.firstWhere((e) => e.id == id);
    e.intensity = intensity;
    _save();
    _recompute();
    notifyListeners();
  }

  void clearAll() {
    _events.clear();
    _save();
    _recompute();
    notifyListeners();
  }

  Future<void> refreshPhysiology() async {
    await health.requestPermissions();
    _snapshot = await health.fetchLatest();
    await _saveSnapshot();
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final today = DateTime.now();
    final todayEvents = _events
        .where((event) =>
            event.start.year == today.year &&
            event.start.month == today.month &&
            event.start.day == today.day)
        .toList();

    // Always analyse — the engine still computes physiological readiness with
    // no tasks, so the Wellbeing screen shows a live score on a rest day.
    _result = engine.analyse(todayEvents, _snapshot, baseline: baseline);
    final r = _result!;

    if (r.level == LoadLevel.overload || r.level == LoadLevel.high) {
      // Throttle: notify only when the level escalates, or after a 30-minute
      // cooldown — otherwise every task edit / periodic refresh would buzz.
      final escalated = _lastNotifiedLevel == null ||
          r.level.index > _lastNotifiedLevel!.index;
      final cooledDown = _lastNotifiedAt == null ||
          DateTime.now().difference(_lastNotifiedAt!) >
              const Duration(minutes: 30);
      if (escalated || cooledDown) {
        _lastNotifiedLevel = r.level;
        _lastNotifiedAt = DateTime.now();
        notifier.show(
          'CognitiveLoad AI - ${r.level.label}',
          r.alerts.isNotEmpty ? r.alerts.first : 'Review your workload.',
        );
      }
    } else {
      // Back in the safe zone: allow the next escalation to notify again.
      _lastNotifiedLevel = null;
    }
  }

  ScheduleEvent _taskDocToScheduleEvent(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final task = TaskModel.fromDoc(doc);
    final start = _dateTimeFromDateAndTime(task.date, task.startTime);
    final parsedEnd = _dateTimeFromDateAndTime(
      task.date,
      task.endTime,
      fallback: start.add(const Duration(hours: 1)),
    );
    final end = parsedEnd.isAfter(start)
        ? parsedEnd
        : start.add(const Duration(hours: 1));

    return ScheduleEvent(
      id: task.id ?? doc.id,
      title: task.name.isEmpty ? 'Untitled Task' : task.name,
      start: start,
      end: end,
      intensity: _getIntensityByScore(task.cognitiveLoadScore),
      source: task.ratingType == 'Automatic (OCR)' ? 'ocr' : 'manual',
      cognitiveLoadScore: task.cognitiveLoadScore,
      ratingType: task.ratingType,
    );
  }

  int _getScoreByKeyword(String title) {
    final lowerTitle = title.toLowerCase();
    for (final entry in _keywordScores.entries) {
      if (lowerTitle.contains(entry.key)) return entry.value;
    }
    return 50;
  }

  TaskIntensity _getIntensityByScore(int score) {
    if (score >= 85) return TaskIntensity.critical;
    if (score >= 70) return TaskIntensity.high;
    if (score <= 30) return TaskIntensity.low;
    return TaskIntensity.medium;
  }

  DateTime _dateTimeFromDateAndTime(
    DateTime date,
    String timeText, {
    DateTime? fallback,
  }) {
    final parsed = _parseTime(timeText);
    if (parsed == null) {
      return fallback ?? DateTime(date.year, date.month, date.day, 9);
    }

    return DateTime(
      date.year,
      date.month,
      date.day,
      parsed.hour,
      parsed.minute,
    );
  }

  TimeOfDay? _parseTime(String value) {
    final normalized = value.trim().toLowerCase();
    final match =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)?$').firstMatch(normalized);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    final period = match.group(3);
    if (hour == null || minute == null || minute > 59) return null;

    if (period == 'pm' && hour < 12) hour += 12;
    if (period == 'am' && hour == 12) hour = 0;
    if (hour > 23) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String? get _eventsPrefsKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : 'events_$uid';
  }

  Future<void> _save() async {
    final key = _eventsPrefsKey;
    if (key == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(_events.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveSnapshot() async {
    if (_snapshot == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snapshot', jsonEncode(_snapshot!.toJson()));

    // Upsert today's entry into the rolling history (one per day, latest wins)
    // and prune anything older than 14 days.
    final s = _snapshot!;
    _history.removeWhere((h) =>
        h.timestamp.year == s.timestamp.year &&
        h.timestamp.month == s.timestamp.month &&
        h.timestamp.day == s.timestamp.day);
    _history.add(s);
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    _history.removeWhere((h) => h.timestamp.isBefore(cutoff));
    await prefs.setString('snapshotHistory',
        jsonEncode(_history.map((h) => h.toJson()).toList()));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _eventsPrefsKey;

    if (key == null) {
      _events.clear();
    } else {
      final raw = prefs.getString(key);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((j) => ScheduleEvent.fromJson(j as Map<String, dynamic>))
            .toList();
        _events
          ..clear()
          ..addAll(list);
      } else {
        _events.clear();
      }
    }

    final snap = prefs.getString('snapshot');
    if (snap != null) {
      _snapshot = PhysiologicalSnapshot.fromJson(jsonDecode(snap));
    }
    final hist = prefs.getString('snapshotHistory');
    if (hist != null) {
      _history
        ..clear()
        ..addAll((jsonDecode(hist) as List)
            .map((j) => PhysiologicalSnapshot.fromJson(j)));
    }
  }
}
