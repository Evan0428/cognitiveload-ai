import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/task_model.dart';
import '../models/user_model.dart';
import 'adaptive_threshold.dart';
import 'cognitive_load_engine.dart';
import 'health_service.dart';
import 'notification_service.dart';
import 'ocr_service.dart';
import 'stress_model.dart';
import 'task_weight_learner.dart';

class AppState extends ChangeNotifier {
  final OcrService ocr = OcrService();
  final HealthService health = HealthService();
  final CognitiveLoadEngine engine = CognitiveLoadEngine();
  final NotificationService notifier = NotificationService();

  UserModel? _userProfile;
  final List<ScheduleEvent> _events = [];
  PhysiologicalSnapshot? _snapshot;
  CognitiveLoadResult? _result;
  bool _loading = false;
  double? _lastNotifiedLoad;
  DateTime? _lastCheckedDay;
  final Set<String> _sentPreTaskAlerts = {};
  final Set<String> _sentBreakSuggestions = {};
  Timer? _notificationTimer;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  /// One snapshot per day for up to 14 days — feeds the rolling baseline
  /// (Chua's module, report section 2.4.4).
  final List<PhysiologicalSnapshot> _history = [];

  /// Real-time strain tracking: periodic physiology refresh.
  Timer? _strainTimer;
  static const Duration strainInterval = Duration(minutes: 15);

  // Notification throttling so real alerts don't fire on every recompute.
  LoadLevel? _lastNotifiedLevel;
  DateTime? _lastNotifiedAt;

  /// AI adaptive burnout threshold — learns the level at which THIS user
  /// actually needs warning, instead of a fixed slider value.
  AdaptiveThreshold _threshold = AdaptiveThreshold();
  AdaptiveThreshold get adaptiveThreshold => _threshold;

  /// Focus Lock (report §2.4.5 — JITAI): when on, non-critical alerts are
  /// suppressed so the user is only interrupted when strain is dangerously
  /// high (overload). Preserves deep-focus flow.
  bool _focusLock = false;
  bool get focusLock => _focusLock;

  List<ScheduleEvent> get events {
    final sorted = List<ScheduleEvent>.from(_events)
      ..sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(sorted);
  }

  PhysiologicalSnapshot? get snapshot => _snapshot;
  CognitiveLoadResult? get result => _result;
  bool get loading => _loading;
  UserModel? get userProfile => _userProfile;

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

  /// Chronological physiology history (up to 14 days) for trend charts.
  List<PhysiologicalSnapshot> get history {
    final sorted = List<PhysiologicalSnapshot>.from(_history)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(sorted);
  }

  /// Readiness score per day, computed against the rolling baseline — the
  /// series plotted on the Wellbeing trend chart.
  List<MapEntry<DateTime, double>> get readinessTrend {
    final b = baseline;
    return history
        .map((s) => MapEntry(
            s.timestamp, engine.computeReadiness(s, baseline: b)))
        .toList();
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
    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      syncTasksFromFirestore();
      _listenToUserProfile(user?.uid);
      syncPhysiologyFromFirestore();
    });

    await _load();
    await TaskWeightLearner.instance.load(); // personalised task weights
    await StressModel.instance.load(); // TFLite stress model (no-op if absent)
    await syncTasksFromFirestore();
    _listenToUserProfile(FirebaseAuth.instance.currentUser?.uid);
    await syncPhysiologyFromFirestore();
    await refreshPhysiology();
    _recompute();

    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkScheduledNotifications();
    });

    // Real-time workload strain tracking: re-sample physiology periodically so
    // HR spikes during a work session are caught, not just on manual sync.
    _strainTimer ??=
        Timer.periodic(strainInterval, (_) => refreshPhysiology());

    _loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _authSubscription?.cancel();
    _strainTimer?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToUserProfile(String? uid) {
    _userSubscription?.cancel();
    if (uid == null) {
      _userProfile = null;
      return;
    }

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        _userProfile = UserModel.fromMap(doc.data() as Map<String, dynamic>);
        // A slider change is a fresh preference -> re-centre the learner.
        if ((_userProfile!.burnoutThreshold - _threshold.base).abs() > 0.5) {
          _threshold.setBase(_userProfile!.burnoutThreshold);
          _saveThreshold();
        }
        _recompute();
        notifyListeners();
      }
    });
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
    final extracted = await ocr.recognizeAndStructureFile(file);

    var counter = 0;
    for (final task in extracted) {
      final taskDate = _parseDate(task.date) ?? DateTime.now();
      final startParts = _dateTimeFromDateAndTime(taskDate, task.startTime);
      final endParts = _dateTimeFromDateAndTime(
        taskDate,
        task.endTime,
        fallback: startParts.add(const Duration(hours: 1, minutes: 30)),
      );
      final customScore = IntensityClassifier.scoreFromTitle(task.subject);

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
    final tasks = await ocr.recognizeAndStructureFile(file);
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

  /// Wall-clock duration of the most recent [refreshPhysiology] cycle.
  ///
  /// NFR-P1 requires a readiness update within 2 seconds. Timing it here
  /// captures the figure that actually matters — HealthKit retrieval plus
  /// persistence plus recomputation on a real handset — rather than the
  /// computation alone, which unit tests already measure in microseconds.
  Duration? lastRefreshDuration;

  Future<void> refreshPhysiology() async {
    final watch = Stopwatch()..start();
    await health.requestPermissions();
    _snapshot = await health.fetchLatest();
    await _saveSnapshot();
    _recompute();
    _learnFromHistory();
    watch.stop();
    lastRefreshDuration = watch.elapsed;
    debugPrint('[NFR-P1] Physiology refresh cycle: '
        '${watch.elapsedMilliseconds} ms');
    notifyListeners();
  }

  void _recompute() {
    _clearNotificationsIfNewDay();
    final today = DateTime.now();
    final todayEvents = _events
        .where((event) =>
    event.start.year == today.year &&
        event.start.month == today.month &&
        event.start.day == today.day)
        .toList();

    // Always analyse — the engine still computes physiological readiness with
    // no tasks, so the Wellbeing screen shows a live score on a rest day.
    //
    // The TFLite stress model is consulted when it is loaded; until it has been
    // trained this is null and the engine uses its rule-based scoring alone.
    final stress = _snapshot == null
        ? null
        : StressModel.instance.probability(_snapshot!, baseline: baseline);
    _result = engine.analyse(todayEvents, _snapshot,
        baseline: baseline, stressProbability: stress);
    final r = _result!;

    // Focus Lock suppresses non-critical (high) alerts — only a dangerously
    // high overload breaks through, so deep-focus flow isn't interrupted.
    final notifiable = _focusLock
        ? r.level == LoadLevel.overload
        : (r.level == LoadLevel.overload || r.level == LoadLevel.high);

    if (notifiable) {
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

      // 🔴 Build the Real Load Threat Alert function
      _checkAndNotifyLoadThreat(r);
  }

  void _checkAndNotifyLoadThreat(CognitiveLoadResult r) {
    if (_userProfile == null) return;

    // 1. Check if user enabled the notification
    if (!_userProfile!.loadThresholdAlert) {
      _lastNotifiedLoad = null; // Reset so if they re-enable, they can be notified
      return;
    }

    // 2. Check if combined score exceeds user's threshold
    final currentLoad = r.combinedLoad;
    // AI: the personalised, learned threshold (not the raw slider value).
    final threshold = _threshold.value;

    if (currentLoad >= threshold) {
      // Only notify if we haven't notified for this "over-threshold" event yet,
      // or if the load has increased significantly since last alert (e.g., by 5 points)
      if (_lastNotifiedLoad == null || currentLoad > _lastNotifiedLoad! + 5) {
        notifier.show(
          'Load Threat Alert!',
          'Your daily load score (${currentLoad.toStringAsFixed(1)}) has exceeded your threshold of ${threshold.toStringAsFixed(0)}.',
          id: 1,
        );
        _lastNotifiedLoad = currentLoad;
      }
    } else {
      // If we are below threshold, reset the last notified load
      _lastNotifiedLoad = null;
    }
  }

  void _checkScheduledNotifications() {
    if (_userProfile == null) return;
    final now = DateTime.now();
    _clearNotificationsIfNewDay();

    // 1. Pre-Task Alert: 15 min before high-intensity tasks
    if (_userProfile!.preTaskAlert) {
      for (final event in _events) {
        final isHighIntensity = event.intensity == TaskIntensity.high ||
            event.intensity == TaskIntensity.critical;

        if (isHighIntensity) {
          // Check if task starts today
          if (event.start.year == now.year &&
              event.start.month == now.month &&
              event.start.day == now.day) {
            final diff = event.start.difference(now).inMinutes;
            // Trigger if task starts in 10-15 minutes
            if (diff <= 15 && diff >= 10) {
              final alertId = 'pre_${event.id}';
              if (!_sentPreTaskAlerts.contains(alertId)) {
                notifier.show(
                  'High Intensity Task Ahead',
                  '"${event.title}" starts in $diff mins. Prepare for high cognitive demand.',
                  id: 2,
                );
                _sentPreTaskAlerts.add(alertId);
              }
            }
          }
        }
      }
    }

    // 2. Break Suggestion: After consecutive high-load tasks
    if (_userProfile!.breakSuggestion) {
      final sortedToday = events
          .where((e) =>
              e.start.year == now.year &&
              e.start.month == now.month &&
              e.start.day == now.day)
          .toList();

      for (int i = 1; i < sortedToday.length; i++) {
        final prev = sortedToday[i - 1];
        final curr = sortedToday[i];

        final isPrevHigh = prev.intensity == TaskIntensity.high ||
            prev.intensity == TaskIntensity.critical;
        final isCurrHigh = curr.intensity == TaskIntensity.high ||
            curr.intensity == TaskIntensity.critical;

        if (isPrevHigh && isCurrHigh) {
          final gap = curr.start.difference(prev.end).inMinutes;
          // Consecutive if gap is less than 15 mins
          if (gap <= 15) {
            final diffSinceEnd = now.difference(curr.end).inMinutes;
            // Notify if current task ended within the last 5 minutes
            if (diffSinceEnd >= 0 && diffSinceEnd < 5) {
              final alertId = 'break_${curr.id}';
              if (!_sentBreakSuggestions.contains(alertId)) {
                notifier.show(
                  'Time for a Break!',
                  'You\'ve completed consecutive high-load tasks. A 15-minute recovery break is recommended.',
                  id: 3,
                );
                _sentBreakSuggestions.add(alertId);
              }
            }
          }
        }
      }
    }
  }

  void _clearNotificationsIfNewDay() {
    final now = DateTime.now();
    if (_lastCheckedDay == null || _lastCheckedDay!.day != now.day) {
      _sentPreTaskAlerts.clear();
      _sentBreakSuggestions.clear();
      _lastNotifiedLoad = null;
      _lastCheckedDay = now;
    }
  }

  // ---------------- AI adaptive threshold ----------------

  /// User answered an alert: "I'm fine" — the warning was too eager.
  Future<void> thresholdFeedbackDismissed() async {
    _threshold.alertDismissed();
    await _saveThreshold();
    _recompute();
    notifyListeners();
  }

  /// User answered an alert: "I'll rest" — the warning was useful.
  Future<void> thresholdFeedbackAccepted() async {
    _threshold.alertAccepted();
    await _saveThreshold();
    _recompute();
    notifyListeners();
  }

  /// Implicit learning: compare each day's peak load against how recovery
  /// actually held up the next day, and let the model correct itself.
  void _learnFromHistory() {
    final trend = readinessTrend;
    if (trend.length < 2) return;
    final before = trend[trend.length - 2].value;
    final after = trend.last.value;
    final peak = _result?.combinedLoad ?? 0;
    if (peak <= 0) return;
    _threshold.observeOutcome(
      peakLoad: peak,
      readinessBefore: before,
      readinessAfter: after,
    );
    _saveThreshold();
  }

  Future<void> _saveThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adaptiveThreshold', _threshold.encode());
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {'adaptiveThreshold': _threshold.toJson()}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Adaptive threshold cloud save failed (kept local): $e');
    }
  }

  /// Toggle Focus Lock and persist the choice.
  Future<void> toggleFocusLock() async {
    _focusLock = !_focusLock;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focusLock', _focusLock);
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
      intensity: TaskIntensityX.fromScore(task.cognitiveLoadScore),
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
    return TaskIntensityX.fromScore(score);
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

  DateTime? _parseDate(String value) {
    try {
      final parts = value.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]), // Year
        int.parse(parts[1]), // Month
        int.parse(parts[0]), // Day
      );
    } catch (e) {
      return null;
    }
  }

  TimeOfDay? _parseTime(String value) {
    final normalized = value.trim().toLowerCase();

    // Support HH:mm, H:mm, HH.mm, H.mm with optional am/pm
    final match =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)?$').firstMatch(normalized);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    final period = match.group(3);
    if (hour == null || minute == null || minute > 59) return null;

    if (period == 'pm' && hour < 12) hour += 12;
    if (period == 'am' && hour == 12) hour = 0;

    // Safety check for 24h conversion
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

    // Cloud persistence (report Ch.4 data design): one document per day under
    // users/{uid}/physiology, with the computed readiness. Local cache above
    // stays the offline source of truth.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final readiness = engine.computeReadiness(s, baseline: baseline);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('physiology')
            .doc(_dayKey(s.timestamp))
            .set({
          ...s.toJson(),
          'readiness': readiness,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Physiology cloud save failed (kept local): $e');
      }
    }
  }

  /// Pull up to 14 days of physiology from Firestore so the baseline and trend
  /// survive across devices / reinstalls. Cloud entries fill gaps in the local
  /// history; failures are non-fatal (offline cache remains).
  Future<void> syncPhysiologyFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('physiology')
          .get()
          .timeout(const Duration(seconds: 5));
      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      for (final doc in snap.docs) {
        final s = PhysiologicalSnapshot.fromJson(doc.data());
        if (s.timestamp.isBefore(cutoff)) continue;
        final exists =
            _history.any((h) => _sameDay(h.timestamp, s.timestamp));
        if (!exists) _history.add(s);
      }
      _recompute();
      notifyListeners();
    } catch (e) {
      debugPrint('Physiology cloud sync unavailable, using local cache: $e');
    }
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    _focusLock = prefs.getBool('focusLock') ?? false;
    final th = prefs.getString('adaptiveThreshold');
    if (th != null) {
      try {
        _threshold = AdaptiveThreshold.decode(th);
      } catch (_) {/* keep default */}
    }
  }
}
