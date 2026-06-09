import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'ocr_service.dart';
import 'health_service.dart';
import 'cognitive_load_engine.dart';
import 'notification_service.dart';

/// Central app state shared across screens (Provider).
/// Holds the unified schedule (multi-source aggregation), latest physiology,
/// and the fused cognitive-load analysis.
class AppState extends ChangeNotifier {
  final OcrService ocr = OcrService();
  final HealthService health = HealthService();
  final CognitiveLoadEngine engine = CognitiveLoadEngine();
  final NotificationService notifier = NotificationService();

  final List<ScheduleEvent> _events = [];
  PhysiologicalSnapshot? _snapshot;
  CognitiveLoadResult? _result;
  bool _loading = false;

  List<ScheduleEvent> get events =>
      List.unmodifiable(_events..sort((a, b) => a.start.compareTo(b.start)));
  PhysiologicalSnapshot? get snapshot => _snapshot;
  CognitiveLoadResult? get result => _result;
  bool get loading => _loading;

  Future<void> init() async {
    await notifier.init();
    await _load();
    await refreshPhysiology();
    _recompute();
  }

  // ---------------- Schedule (Lim's module) ----------------

  /// Run the full OCR pipeline on an optional image file and merge results.
  Future<int> scanAndImport(dynamic imageFile) async {
    _loading = true;
    notifyListeners();
    final raw = await ocr.extractRawText(imageFile);
    final parsed = ocr.parseTimetable(raw);
    _events.addAll(parsed);
    await _save();
    _recompute();
    _loading = false;
    notifyListeners();
    return parsed.length;
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
    _result = engine.analyse(_events, _snapshot);
    final r = _result!;
    // Fire a proactive notification on high/overload (haptic on watch).
    if (r.level == LoadLevel.overload || r.level == LoadLevel.high) {
      notifier.show(
        'CognitiveLoad AI — ${r.level.label}',
        r.alerts.isNotEmpty ? r.alerts.first : 'Review your workload.',
      );
    }
  }

  // ---------------- Persistence (offline, on-device) ----------------

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'events', jsonEncode(_events.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveSnapshot() async {
    if (_snapshot == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('snapshot', jsonEncode(_snapshot!.toJson()));
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('events');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((j) => ScheduleEvent.fromJson(j))
          .toList();
      _events
        ..clear()
        ..addAll(list);
    }
    final snap = prefs.getString('snapshot');
    if (snap != null) {
      _snapshot = PhysiologicalSnapshot.fromJson(jsonDecode(snap));
    }
  }
}
