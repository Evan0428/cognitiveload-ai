import 'package:flutter/material.dart';

/// Categories used to weight a task's mental demand.
/// Derived from the modified NASA-TLX weighting model (Lim Kah Jun's report).
enum TaskIntensity { low, medium, high, critical }

extension TaskIntensityX on TaskIntensity {
  /// Numeric weight used in the workload-density calculation.
  /// Higher = more cognitively demanding.
  double get weight {
    switch (this) {
      case TaskIntensity.low:
        return 1.0; // e.g. break, easy meeting
      case TaskIntensity.medium:
        return 2.0; // e.g. lecture, normal task
      case TaskIntensity.high:
        return 3.5; // e.g. assignment, lab
      case TaskIntensity.critical:
        return 5.0; // e.g. exam, deadline
    }
  }

  String get label {
    switch (this) {
      case TaskIntensity.low:
        return 'Low';
      case TaskIntensity.medium:
        return 'Medium';
      case TaskIntensity.high:
        return 'High';
      case TaskIntensity.critical:
        return 'Critical';
    }
  }

  /// 0-100 cognitive-load score used by the manual "Add Task" flow and the
  /// dashboard. Mapped 1:1 from the NASA-TLX intensity band so the keyword
  /// engine and the Firestore task list always agree.
  int get score {
    switch (this) {
      case TaskIntensity.low:
        return 20; // break, rest
      case TaskIntensity.medium:
        return 50; // lecture, meeting
      case TaskIntensity.high:
        return 70; // assignment, lab, project
      case TaskIntensity.critical:
        return 90; // exam, deadline, viva
    }
  }

  /// Reverse mapping: classify a 0-100 score back into an intensity band so a
  /// Firestore task (which stores a flat score) can drive the engine.
  static TaskIntensity fromScore(int score) {
    if (score >= 80) return TaskIntensity.critical;
    if (score >= 60) return TaskIntensity.high;
    if (score >= 35) return TaskIntensity.medium;
    return TaskIntensity.low;
  }

  Color get color {
    switch (this) {
      case TaskIntensity.low:
        return const Color(0xFF4CAF50);
      case TaskIntensity.medium:
        return const Color(0xFF2196F3);
      case TaskIntensity.high:
        return const Color(0xFFFF9800);
      case TaskIntensity.critical:
        return const Color(0xFFF44336);
    }
  }
}

/// Canonical keyword-based classifier — the single source of truth for the
/// "modified NASA-TLX weighting logic" from the report. Both the OCR pipeline
/// (Lim) and the manual Add-Task flow call this so they never disagree.
class IntensityClassifier {
  static const _critical = [
    'exam', 'final', 'test', 'quiz', 'deadline', 'viva', 'defense', 'midterm'
  ];
  static const _high = [
    'assignment', 'project', 'lab', 'report', 'presentation', 'submission',
    'tutorial'
  ];
  static const _low = [
    'break', 'lunch', 'rest', 'free', 'recess', 'gym', 'nap', 'sleep'
  ];

  /// Classify a task title into its NASA-TLX intensity band.
  /// Order matters: highest-demand keywords win.
  static TaskIntensity fromTitle(String title) {
    final t = title.toLowerCase();
    if (_critical.any(t.contains)) return TaskIntensity.critical;
    if (_high.any(t.contains)) return TaskIntensity.high;
    if (_low.any(t.contains)) return TaskIntensity.low;
    return TaskIntensity.medium; // lectures / meetings default
  }

  /// Convenience: 0-100 score straight from a title.
  static int scoreFromTitle(String title) => fromTitle(title).score;
}

/// A single schedule event, whether OCR-extracted or manually added.
class ScheduleEvent {
  final String id;
  String title;
  DateTime start;
  DateTime end;
  TaskIntensity intensity;

  /// Where this event came from: 'ocr' (scanned) or 'manual' / 'digital'.
  /// Supports multi-source aggregation (PS2 - Lack of Centralization).
  String source;

  /// 🟢 Added for edit support
  int cognitiveLoadScore;
  String ratingType;

  ScheduleEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    required this.intensity,
    this.source = 'manual',
    this.cognitiveLoadScore = 50,
    this.ratingType = 'Automatic',
  });

  double get durationHours => end.difference(start).inMinutes / 60.0;

  /// Contribution of this single event to the daily workload score.
  double get loadContribution => intensity.weight * durationHours;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'intensity': intensity.index,
        'source': source,
        'cognitiveLoadScore': cognitiveLoadScore,
        'ratingType': ratingType,
      };

  factory ScheduleEvent.fromJson(Map<String, dynamic> j) => ScheduleEvent(
        id: j['id'],
        title: j['title'],
        start: DateTime.parse(j['start']),
        end: DateTime.parse(j['end']),
        intensity: TaskIntensity.values[j['intensity']],
        source: j['source'] ?? 'manual',
        cognitiveLoadScore: j['cognitiveLoadScore'] ?? 50,
        ratingType: j['ratingType'] ?? 'Automatic',
      );
}

/// A snapshot of biometric data from Apple HealthKit / Health Connect
/// (Chua Yi Zhe's Physiological Monitoring module).
class PhysiologicalSnapshot {
  final DateTime timestamp;
  final double heartRate; // bpm
  final double hrv; // ms (heart rate variability)
  final double sleepHours; // last night's sleep
  final int steps; // today's step count

  PhysiologicalSnapshot({
    required this.timestamp,
    required this.heartRate,
    required this.hrv,
    required this.sleepHours,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'heartRate': heartRate,
        'hrv': hrv,
        'sleepHours': sleepHours,
        'steps': steps,
      };

  factory PhysiologicalSnapshot.fromJson(Map<String, dynamic> j) =>
      PhysiologicalSnapshot(
        timestamp: DateTime.parse(j['timestamp']),
        heartRate: (j['heartRate'] as num).toDouble(),
        hrv: (j['hrv'] as num).toDouble(),
        sleepHours: (j['sleepHours'] as num).toDouble(),
        steps: (j['steps'] as num).toInt(),
      );
}

/// Rolling personal baseline built from up to 14 days of snapshots
/// (report section 2.4.4 — dynamic intra-individual thresholding).
/// The readiness model compares today's readings against this instead of
/// one-size-fits-all population norms.
class PhysiologicalBaseline {
  final double avgSleepHours;
  final double avgHrv;
  final double avgHeartRate;
  final int days; // how many days of history back this baseline

  const PhysiologicalBaseline({
    required this.avgSleepHours,
    required this.avgHrv,
    required this.avgHeartRate,
    required this.days,
  });

  /// Baselines need at least this many days before they influence scoring.
  static const int minDays = 3;

  bool get isReliable => days >= minDays;

  factory PhysiologicalBaseline.fromSnapshots(
      List<PhysiologicalSnapshot> history) {
    final n = history.length;
    double sumSleep = 0, sumHrv = 0, sumHr = 0;
    for (final s in history) {
      sumSleep += s.sleepHours;
      sumHrv += s.hrv;
      sumHr += s.heartRate;
    }
    return PhysiologicalBaseline(
      avgSleepHours: n > 0 ? sumSleep / n : 0,
      avgHrv: n > 0 ? sumHrv / n : 0,
      avgHeartRate: n > 0 ? sumHr / n : 0,
      days: n,
    );
  }
}
