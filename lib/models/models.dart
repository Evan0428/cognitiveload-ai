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
