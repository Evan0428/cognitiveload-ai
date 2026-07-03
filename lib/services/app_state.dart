import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../models/task_model.dart';
import 'ocr_service.dart';
import 'health_service.dart';
import 'cognitive_load_engine.dart';
import 'notification_service.dart';
import 'task_service.dart';

/// Central app state shared across screens (Provider).
/// Holds the unified schedule (multi-source aggregation), latest physiology,
/// and the fused cognitive-load analysis.
class AppState extends ChangeNotifier {
  final OcrService ocr = OcrService();
  final HealthService health = HealthService();
  final CognitiveLoadEngine engine = CognitiveLoadEngine();
  final NotificationService notifier = NotificationService();
  final TaskService taskService = TaskService();

  /// OCR-scanned + locally-added events (persisted on-device, offline).
  final List<ScheduleEvent> _localEvents = [];

  /// Events synced live from Firestore (the manual "Add Task" flow).
  final List<ScheduleEvent> _remoteEvents = [];

  PhysiologicalSnapshot? _snapshot;
  CognitiveLoadResult? _result;
  bool _loading = false;

  /// One snapshot per day for up to 14 days — feeds the rolling baseline.
  final List<PhysiologicalSnapshot> _history = [];

  /// Real-time strain tracking: periodic physiology refresh (Chua's module).
  Timer? _strainTimer;
  static const Duration strainInterval = Duration(minutes: 15);

  // Notification throttling so real alerts don't fire on every recompute.
  LoadLevel? _lastNotifiedLevel;
  DateTime? _lastNotifiedAt;

  /// User's daily burnout threshold (0-100) from their profile; alerts fire
  /// when the combined load exceeds it.
  double _burnoutThreshold = 100;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<TaskModel>>? _taskSub;

  /// Unified, time-ordered view across every source (multi-source aggregation).
  List<ScheduleEvent> get events {
    final merged = [..._localEvents, ..._remoteEvents]
      ..sort((a, b) => a.start.compareTo(b.start));
    return List.unmodifiable(merged);
  }

  PhysiologicalSnapshot? get snapshot => _snapshot;
  CognitiveLoadResult? get result => _result;
  bool get loading => _loading;
  double get burnoutThreshold => _burnoutThreshold;

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

  Future<void> init() async {
    await notifier.init();
    await _load();
    await refreshPhysiology();
    _listenToAuth();
    _recompute();
    // Real-time workload strain tracking: re-sample physiology periodically
    // so HR spikes during a work session are caught, not just on manual sync.
    _strainTimer =
        Timer.periodic(strainInterval, (_) => refreshPhysiology());
  }

  // ---------------- Firestore task sync (the bridge) ----------------

  /// Re-subscribe the task stream whenever the signed-in user changes.
  void _listenToAuth() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _taskSub?.cancel();
      if (user == null) {
        _remoteEvents.clear();
        _burnoutThreshold = 100;
        _recompute();
        notifyListeners();
        return;
      }
      _loadUserProfile(user.uid);
      _taskSub = taskService.streamUserTasks().listen((tasks) {
        _remoteEvents
          ..clear()
          ..addAll(tasks.map((t) => t.toScheduleEvent()));
        _recompute();
        notifyListeners();
      });
    });
  }

  Future<void> _loadUserProfile(String uid) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null && data['burnoutThreshold'] != null) {
        _burnoutThreshold = (data['burnoutThreshold'] as num).toDouble();
        _recompute();
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal: keep the default threshold.
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _taskSub?.cancel();
    _strainTimer?.cancel();
    super.dispose();
  }

  // ---------------- Schedule (Lim's module) ----------------

  /// Run the full OCR pipeline on an optional image file and merge results.
  Future<int> scanAndImport(dynamic imageFile) async {
    _loading = true;
    notifyListeners();
    final raw = await ocr.extractRawText(imageFile);
    final parsed = ocr.parseTimetable(raw);
    _localEvents.addAll(parsed);
    await _save();
    _recompute();
    _loading = false;
    notifyListeners();
    return parsed.length;
  }

  void addEvent(ScheduleEvent e) {
    _localEvents.add(e);
    _save();
    _recompute();
    notifyListeners();
  }

  void removeEvent(String id) {
    // Local (OCR/manual) events are removed in place; Firestore-synced events
    // are deleted at the source so the stream updates the engine.
    final wasLocal = _localEvents.any((e) => e.id == id);
    _localEvents.removeWhere((e) => e.id == id);
    if (wasLocal) {
      _save();
      _recompute();
      notifyListeners();
    } else {
      taskService.deleteTask(id);
    }
  }

  void updateIntensity(String id, TaskIntensity intensity) {
    final idx = _localEvents.indexWhere((e) => e.id == id);
    if (idx == -1) return; // remote events derive intensity from their score
    _localEvents[idx].intensity = intensity;
    _save();
    _recompute();
    notifyListeners();
  }

  void clearAll() {
    _localEvents.clear();
    _save();
    _recompute();
    notifyListeners();
  }

  // ---------------- Physiology (Chua's module) ----------------

  Future<void> refreshPhysiology() async {
    await health.requestPermissions();
    _snapshot = await health.fetchLatest();
    await _saveSnapshot();
    _recompute();
    notifyListeners();
  }

  // ---------------- Fusion + alerts ----------------

  void _recompute() {
    _result = engine.analyse(events, _snapshot, baseline: baseline);
    final r = _result!;
    // Fire a proactive notification on high/overload OR when the combined load
    // crosses the user's personal burnout threshold (haptic on Apple Watch).
    final overThreshold = r.combinedLoad >= _burnoutThreshold;
    if (r.level == LoadLevel.overload ||
        r.level == LoadLevel.high ||
        overThreshold) {
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
          'CognitiveLoad AI — ${r.level.label}',
          r.alerts.isNotEmpty ? r.alerts.first : 'Review your workload.',
        );
      }
    } else {
      // Back in the safe zone: allow the next escalation to notify again.
      _lastNotifiedLevel = null;
    }
  }

  // ---------------- Persistence (offline, on-device) ----------------

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'events', jsonEncode(_localEvents.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveSnapshot() async {
    if (_snapshot == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snapshot', jsonEncode(_snapshot!.toJson()));

    // Upsert today's entry into the rolling history (one per day, latest
    // wins) and prune anything older than 14 days.
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
    final raw = prefs.getString('events');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((j) => ScheduleEvent.fromJson(j))
          .toList();
      _localEvents
        ..clear()
        ..addAll(list);
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
