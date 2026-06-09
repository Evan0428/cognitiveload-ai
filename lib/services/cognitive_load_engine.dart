import '../models/models.dart';

/// Result of analysing one day's schedule + physiology.
class CognitiveLoadResult {
  final double workloadScore; // from schedule density (Lim)
  final double readinessScore; // 0-100 from physiology (Chua)
  final double combinedLoad; // fused 0-100, higher = more strain
  final LoadLevel level;
  final List<String> alerts; // human-readable warnings / recommendations

  CognitiveLoadResult({
    required this.workloadScore,
    required this.readinessScore,
    required this.combinedLoad,
    required this.level,
    required this.alerts,
  });
}

enum LoadLevel { safe, elevated, high, overload }

extension LoadLevelX on LoadLevel {
  String get label => switch (this) {
        LoadLevel.safe => 'Balanced',
        LoadLevel.elevated => 'Elevated',
        LoadLevel.high => 'High Load',
        LoadLevel.overload => 'Overload Risk',
      };
}

/// The analytical core that implements both objectives:
///  - Task-density / workload scoring (NASA-TLX inspired) — Lim Kah Jun
///  - Physiological readiness scoring — Chua Yi Zhe
///  - Fusion of the two into one proactive cognitive-load signal.
class CognitiveLoadEngine {
  // Threshold above which a workload warning fires (PS3).
  static const double workloadWarningThreshold = 18.0;

  /// Sum of every event's weight x duration = the day's raw workload score.
  /// This is the "Task Density" / "Workload Score" from the report.
  double computeWorkloadScore(List<ScheduleEvent> events) {
    return events.fold(0.0, (sum, e) => sum + e.loadContribution);
  }

  /// Density = workload concentrated into the active window of the day.
  /// Measures how packed high-intensity tasks are, not just total hours.
  double computeDensity(List<ScheduleEvent> events) {
    if (events.isEmpty) return 0;
    final earliest =
        events.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b);
    final latest =
        events.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);
    final spanHours = latest.difference(earliest).inMinutes / 60.0;
    if (spanHours <= 0) return 0;
    return computeWorkloadScore(events) / spanHours;
  }

  /// Physiological Readiness (0-100). Higher = more biologically prepared.
  /// Correlates recovery (sleep) with active stress signals (HR, HRV) —
  /// Chua's cognitive-capacity model.
  double computeReadiness(PhysiologicalSnapshot p) {
    // Sleep: 8h ideal. Scaled 0-1.
    final sleepScore = (p.sleepHours / 8.0).clamp(0.0, 1.0);
    // HRV: higher is better recovery. ~80ms treated as strong.
    final hrvScore = (p.hrv / 80.0).clamp(0.0, 1.0);
    // Resting HR: lower is better. 60bpm strong, 100bpm strained.
    final hrScore = (1 - ((p.heartRate - 60) / 40)).clamp(0.0, 1.0);
    // Activity: some movement is good; cap the benefit.
    final stepScore = (p.steps / 8000.0).clamp(0.0, 1.0);

    final readiness = (sleepScore * 0.40 +
            hrvScore * 0.30 +
            hrScore * 0.20 +
            stepScore * 0.10) *
        100;
    return readiness.clamp(0.0, 100.0);
  }

  /// Fuse schedule demand and physiological readiness into one 0-100 signal.
  /// High workload + low readiness = high combined cognitive load.
  CognitiveLoadResult analyse(
    List<ScheduleEvent> events,
    PhysiologicalSnapshot? snapshot,
  ) {
    final workload = computeWorkloadScore(events);
    final readiness = snapshot != null ? computeReadiness(snapshot) : 100.0;

    // Normalise workload to 0-100 (cap raw score at 40 for a full bar).
    final workloadNorm = (workload / 40.0 * 100).clamp(0.0, 100.0);

    // Demand pressure rises with workload AND with low readiness.
    final readinessPressure = 100 - readiness;
    final combined =
        (workloadNorm * 0.6 + readinessPressure * 0.4).clamp(0.0, 100.0);

    final level = switch (combined) {
      < 35 => LoadLevel.safe,
      < 55 => LoadLevel.elevated,
      < 75 => LoadLevel.high,
      _ => LoadLevel.overload,
    };

    final alerts = _buildAlerts(events, workload, readiness, snapshot, level);

    return CognitiveLoadResult(
      workloadScore: workload,
      readinessScore: readiness,
      combinedLoad: combined,
      level: level,
      alerts: alerts,
    );
  }

  List<String> _buildAlerts(
    List<ScheduleEvent> events,
    double workload,
    double readiness,
    PhysiologicalSnapshot? p,
    LoadLevel level,
  ) {
    final alerts = <String>[];

    if (workload > workloadWarningThreshold) {
      alerts.add(
          'Workload warning: your schedule density (${workload.toStringAsFixed(1)}) exceeds the safe threshold. Consider redistributing tasks.');
    }

    final criticalCount =
        events.where((e) => e.intensity == TaskIntensity.critical).length;
    if (criticalCount >= 2) {
      alerts.add(
          '$criticalCount critical tasks scheduled today. Space them out to avoid cognitive overload.');
    }

    if (p != null) {
      if (p.sleepHours < 6) {
        alerts.add(
            'Low recovery: only ${p.sleepHours.toStringAsFixed(1)}h sleep. A recovery break is recommended before high-intensity work.');
      }
      if (p.hrv < 35) {
        alerts.add(
            'Elevated stress signal: HRV is low (${p.hrv.toStringAsFixed(0)} ms). Your body shows reduced readiness.');
      }
    }

    if (level == LoadLevel.overload) {
      alerts.add(
          'Overload risk detected — high schedule demand combined with low physiological readiness. Activate a Focus Lock or take a break.');
    } else if (level == LoadLevel.safe && alerts.isEmpty) {
      alerts.add('You are well balanced today. Good time for demanding tasks.');
    }

    return alerts;
  }
}
