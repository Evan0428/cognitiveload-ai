import '../models/models.dart';

/// Result of analysing one day's schedule + physiology.
class CognitiveLoadResult {
  final double workloadScore; // from schedule density (Lim)
  final double readinessScore; // 0-100 from physiology (Chua)
  final double combinedLoad; // fused 0-100, higher = more strain
  final LoadLevel level;
  final List<String> alerts; // human-readable warnings / recommendations

  /// Why readiness is what it is (null when no physiology is available).
  final ReadinessBreakdown? breakdown;

  /// Learned probability of acute physiological stress from the on-device
  /// TensorFlow Lite model, or null when that model isn't available.
  final double? stressProbability;

  CognitiveLoadResult({
    required this.workloadScore,
    required this.readinessScore,
    required this.combinedLoad,
    required this.level,
    required this.alerts,
    this.breakdown,
    this.stressProbability,
  });
}

/// One weighted input to the readiness model, with how many of its available
/// points the user actually earned today.
class ReadinessFactor {
  final String name;
  final double weight; // maximum points this factor can contribute
  final double achieved; // points actually earned (0..weight)
  final String actual; // e.g. "4.2 h"
  final String target; // e.g. "7.3 h"

  const ReadinessFactor({
    required this.name,
    required this.weight,
    required this.achieved,
    required this.actual,
    required this.target,
  });

  /// Points lost against this factor's maximum — how much it hurt readiness.
  double get lost => weight - achieved;

  /// 0..1, for progress bars.
  double get fraction => weight == 0 ? 0 : achieved / weight;
}

/// Explainable decomposition of a readiness score.
class ReadinessBreakdown {
  final double readiness;
  final List<ReadinessFactor> factors;

  /// True when personal 14-day targets were used instead of population norms.
  final bool personalised;

  const ReadinessBreakdown({
    required this.readiness,
    required this.factors,
    required this.personalised,
  });

  /// The factor that cost the most points — the main reason readiness is down.
  ReadinessFactor get weakest =>
      factors.reduce((a, b) => a.lost >= b.lost ? a : b);

  /// One sentence a non-technical user can act on.
  String get summary {
    final w = weakest;
    if (w.lost < 3) {
      return 'All your signals are close to target — nothing is holding your '
          'readiness back today.';
    }
    return 'Your readiness is mainly held back by '
        '${_readable(w.name)} (−${w.lost.round()} points): '
        '${w.actual} against a target of ${w.target}.';
  }

  /// Lower-case a factor name for use mid-sentence, but leave acronyms alone —
  /// "held back by hrv" reads as a typo.
  static String _readable(String name) =>
      name == name.toUpperCase() ? name : name.toLowerCase();
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
  ///
  /// When a reliable [baseline] exists (>= 3 days of history), the targets are
  /// dynamic intra-individual thresholds: the midpoint between the population
  /// norm and the user's own 14-day rolling average (report section 2.4.4).
  /// Without history it falls back to the population norms alone.
  double computeReadiness(PhysiologicalSnapshot p,
          {PhysiologicalBaseline? baseline}) =>
      explainReadiness(p, baseline: baseline).readiness;

  /// Same model as [computeReadiness], but keeps each factor's contribution so
  /// the app can explain *why* readiness is what it is instead of showing an
  /// unexplained number (explainable AI).
  ReadinessBreakdown explainReadiness(PhysiologicalSnapshot p,
      {PhysiologicalBaseline? baseline}) {
    final personal = baseline != null && baseline.isReliable;

    // Population norms: 8h sleep, 80ms HRV, 60bpm resting HR.
    final sleepTarget =
        personal ? ((8.0 + baseline.avgSleepHours) / 2).clamp(6.0, 9.0) : 8.0;
    final hrvTarget =
        personal ? ((80.0 + baseline.avgHrv) / 2).clamp(40.0, 100.0) : 80.0;
    final hrAnchor = personal
        ? ((60.0 + baseline.avgHeartRate) / 2).clamp(50.0, 80.0)
        : 60.0;

    final sleepScore = (p.sleepHours / sleepTarget).clamp(0.0, 1.0);
    final hrvScore = (p.hrv / hrvTarget).clamp(0.0, 1.0);
    // Resting HR: at the anchor = strong; anchor + 40bpm = fully strained.
    final hrScore = (1 - ((p.heartRate - hrAnchor) / 40)).clamp(0.0, 1.0);
    // Activity: some movement is good; cap the benefit.
    final stepScore = (p.steps / 8000.0).clamp(0.0, 1.0);

    final factors = <ReadinessFactor>[
      ReadinessFactor(
        name: 'Sleep',
        weight: 40,
        achieved: sleepScore * 40,
        actual: '${p.sleepHours.toStringAsFixed(1)} h',
        target: '${sleepTarget.toStringAsFixed(1)} h',
      ),
      ReadinessFactor(
        name: 'HRV',
        weight: 30,
        achieved: hrvScore * 30,
        actual: '${p.hrv.toStringAsFixed(0)} ms',
        target: '${hrvTarget.toStringAsFixed(0)} ms',
      ),
      ReadinessFactor(
        name: 'Resting HR',
        weight: 20,
        achieved: hrScore * 20,
        actual: '${p.heartRate.toStringAsFixed(0)} bpm',
        target: '${hrAnchor.toStringAsFixed(0)} bpm',
      ),
      ReadinessFactor(
        name: 'Activity',
        weight: 10,
        achieved: stepScore * 10,
        actual: '${p.steps} steps',
        target: '8000 steps',
      ),
    ];

    final readiness =
        factors.fold(0.0, (sum, f) => sum + f.achieved).clamp(0.0, 100.0);

    return ReadinessBreakdown(
      readiness: readiness,
      factors: factors,
      personalised: personal,
    );
  }

  /// Fuse schedule demand and physiological readiness into one 0-100 signal.
  /// The same schedule feels heavier when the user is biologically depleted:
  /// combined load = normalised workload scaled by a capacity factor derived
  /// from physiological readiness ("energy management", not just time
  /// management — Chua's Objective 2). Readiness is always reported so the
  /// Wellbeing screen shows it even on a task-free day.
  /// [stressProbability] is the on-device TensorFlow Lite model's estimate
  /// (0..1) that the user is acutely stressed. It is optional: when the model
  /// has not been trained or fails to load, the engine falls back to its
  /// rule-based scoring alone and behaves exactly as before.
  CognitiveLoadResult analyse(
    List<ScheduleEvent> events,
    PhysiologicalSnapshot? snapshot, {
    PhysiologicalBaseline? baseline,
    double? stressProbability,
  }) {
    final breakdown = snapshot != null
        ? explainReadiness(snapshot, baseline: baseline)
        : null;
    final readiness = breakdown?.readiness ?? 100.0;

    final workload = computeWorkloadScore(events);

    // Normalise workload to 0-100 (cap raw score at 40 for a full bar).
    final workloadNorm = (workload / 40.0 * 100).clamp(0.0, 100.0);

    // Capacity factor: 1.0 when fully recovered (readiness 100), up to 1.6 when
    // fully depleted (readiness 0). No tasks -> workloadNorm 0 -> combined 0.
    //
    // The learned stress probability adds up to a further 0.25. The readiness
    // score reads HR and HRV through weights we chose by hand; the network
    // reads the same two signals through weights learned from labelled data,
    // so it can recognise a stressed pattern that the linear rules miss.
    final learnedStrain = (stressProbability ?? 0.0).clamp(0.0, 1.0) * 0.25;
    final capacityFactor = 1 + (1 - readiness / 100) * 0.6 + learnedStrain;
    final combined = (workloadNorm * capacityFactor).clamp(0.0, 100.0);

    final level = switch (combined) {
      < 35 => LoadLevel.safe,
      < 55 => LoadLevel.elevated,
      < 75 => LoadLevel.high,
      _ => LoadLevel.overload,
    };

    final alerts =
        _buildAlerts(events, workload, readiness, snapshot, baseline, level);

    if (stressProbability != null && stressProbability >= 0.7) {
      alerts.add(
          'Stress pattern detected: the on-device model puts your heart-rate and HRV pattern at ${(stressProbability * 100).round()}% match to a stressed state. Consider a recovery break.');
    }

    return CognitiveLoadResult(
      workloadScore: workload,
      readinessScore: readiness,
      combinedLoad: combined,
      level: level,
      alerts: alerts,
      breakdown: breakdown,
      stressProbability: stressProbability,
    );
  }

  List<String> _buildAlerts(
    List<ScheduleEvent> events,
    double workload,
    double readiness,
    PhysiologicalSnapshot? p,
    PhysiologicalBaseline? baseline,
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
      // Real-time strain: acute HR spike vs the user's own rolling baseline.
      if (baseline != null &&
          baseline.isReliable &&
          p.heartRate > baseline.avgHeartRate * 1.25) {
        alerts.add(
            'Heart-rate spike: ${p.heartRate.toStringAsFixed(0)} bpm vs your ${baseline.days}-day average of ${baseline.avgHeartRate.toStringAsFixed(0)} bpm. Acute strain detected — take a short recovery break.');
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
