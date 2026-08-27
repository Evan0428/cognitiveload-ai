import '../models/models.dart';

/// Reproducible demonstration data (Chua Yi Zhe).
///
/// The personalisation features in this module are history-dependent: the
/// rolling baseline needs at least [PhysiologicalBaseline.minDays] days before
/// it is treated as reliable, and the trend chart needs a fortnight before it
/// shows a shape. That history cannot be manufactured on the day of a
/// demonstration, so this class provides a fixed, realistic fortnight that can
/// be loaded on demand while rehearsing or testing.
///
/// The values are a hand-written table rather than random numbers so that every
/// run produces exactly the same screen — a rehearsal is only useful if what
/// you practised is what appears.
///
/// **This is test data, not measured data.** It is only reachable from a debug
/// build, and anything it writes is removed again by
/// `AppState.clearDemoData()`. Never present it as a real recording.
class DemoSeeder {
  DemoSeeder._();

  /// Marks every record this class creates, so it can be withdrawn cleanly.
  static const String tag = 'demo_';

  /// Fourteen days telling a deliberate story: a settled fortnight, an
  /// assignment week that erodes sleep and suppresses HRV, a recovery, and a
  /// strained day today so that there is something to explain on screen.
  ///
  /// Each row is (days ago, resting HR bpm, HRV SDNN ms, sleep hours, steps).
  static const List<(int, double, double, double, int)> _fortnight = [
    (13, 61, 58, 7.4, 8200), // settled
    (12, 60, 60, 7.6, 7600),
    (11, 62, 56, 7.1, 6900),
    (10, 63, 54, 6.8, 7400),
    (9, 66, 48, 6.0, 5200), // workload begins to bite
    (8, 70, 41, 5.2, 4100),
    (7, 73, 36, 4.6, 3300), // worst night of the assignment week
    (6, 71, 39, 5.1, 3800),
    (5, 67, 45, 6.2, 5600), // recovering
    (4, 64, 51, 6.9, 6800),
    (3, 62, 55, 7.3, 7700),
    (2, 61, 57, 7.5, 8100),
    (1, 63, 53, 6.7, 7200),
    (0, 74, 33, 4.8, 3100), // today: strained, so the demo has a story
  ];

  /// The fortnight as snapshots, anchored to the current date. Timestamps are
  /// set to 08:00 so each lands unambiguously inside its own day.
  static List<PhysiologicalSnapshot> fortnight() {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day, 8);
    return [
      for (final (daysAgo, hr, hrv, sleep, steps) in _fortnight)
        PhysiologicalSnapshot(
          timestamp: midnight.subtract(Duration(days: daysAgo)),
          heartRate: hr,
          hrv: hrv,
          sleepHours: sleep,
          steps: steps,
        )
    ];
  }

  /// The most recent snapshot — today's reading.
  static PhysiologicalSnapshot today() => fortnight().last;

  /// A realistically full student day. The intensities are chosen so the fused
  /// load lands in the overload band against today's reduced readiness, which
  /// is what makes the alert and Focus Lock demonstrable.
  ///
  /// Total raw workload is roughly 25, above the warning threshold of 18.
  static List<ScheduleEvent> todayTasks() {
    final now = DateTime.now();
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(now.year, now.month, now.day, hour, minute);

    final rows = <(String, DateTime, DateTime, TaskIntensity)>[
      ('Software Engineering Lecture', at(9), at(11), TaskIntensity.medium),
      ('Physics Lab Report', at(13), at(15), TaskIntensity.high),
      ('FYP Presentation Rehearsal', at(15, 30), at(17), TaskIntensity.critical),
      ('Database Assignment', at(20), at(22), TaskIntensity.high),
    ];

    var i = 0;
    return [
      for (final (title, start, end, intensity) in rows)
        ScheduleEvent(
          id: '$tag${i++}',
          title: title,
          start: start,
          end: end,
          intensity: intensity,
          source: 'demo',
          cognitiveLoadScore: intensity.score,
          ratingType: 'Auto (demo data)',
        )
    ];
  }

  /// Titles used to demonstrate that personalised task weighting generalises:
  /// rate the first manually, then add the second and watch its automatic
  /// score move toward your rating because both share the word "tutorial".
  static const List<String> weightLearningPair = [
    'Calculus Tutorial',
    'Statistics Tutorial',
  ];
}
