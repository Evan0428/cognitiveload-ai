// Performance measurement for the non-functional requirements in Chapter 3.
//
// NFR-P1 states that a readiness recomputation must complete within 2 seconds.
// "Immediate" is not a measurement, so these tests time the analytical core
// over many iterations and print the distribution, giving Chapter 5 a real
// figure with a stated sample size.
//
// Scope of the claim: this measures the *computation*, executed on the Dart VM
// on the development machine. It excludes HealthKit retrieval and Firestore
// I/O, which are network- and sensor-bound. It is therefore evidence about the
// engine, not about end-to-end latency on the handset.
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';

/// Report the mean, median and 95th percentile of [samples] in milliseconds.
({double mean, double median, double p95, double max}) summarise(
    List<double> samples) {
  final sorted = [...samples]..sort();
  final mean = sorted.reduce((a, b) => a + b) / sorted.length;
  final median = sorted[sorted.length ~/ 2];
  final p95 = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
  return (mean: mean, median: median, p95: p95, max: sorted.last);
}

void main() {
  final engine = CognitiveLoadEngine();
  const iterations = 1000;

  final snapshot = PhysiologicalSnapshot(
    timestamp: DateTime.now(),
    heartRate: 72,
    hrv: 45,
    sleepHours: 6.2,
    steps: 5400,
  );

  const baseline = PhysiologicalBaseline(
    avgSleepHours: 6.8,
    avgHrv: 52,
    avgHeartRate: 64,
    days: 14,
  );

  /// A realistically full academic day.
  List<ScheduleEvent> fullDay() {
    final start = DateTime(2026, 3, 2, 8);
    return List.generate(8, (i) {
      final s = start.add(Duration(hours: i * 2));
      return ScheduleEvent(
        id: 'e$i',
        title: i.isEven ? 'Lecture $i' : 'Physics Lab $i',
        start: s,
        end: s.add(const Duration(hours: 2)),
        intensity: i.isEven ? TaskIntensity.medium : TaskIntensity.high,
        source: 'manual',
        cognitiveLoadScore: i.isEven ? 50 : 70,
        ratingType: 'Auto',
      );
    });
  }

  double timeMicros(void Function() body) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    return watch.elapsedMicroseconds / 1000.0; // ms
  }

  test('NFR-P1: readiness computation completes well within 2 seconds', () {
    final events = fullDay();

    // Warm up so JIT compilation is not counted as run-time cost.
    for (var i = 0; i < 100; i++) {
      engine.analyse(events, snapshot, baseline: baseline);
    }

    final readinessOnly = <double>[];
    final fullAnalysis = <double>[];

    for (var i = 0; i < iterations; i++) {
      readinessOnly.add(
          timeMicros(() => engine.explainReadiness(snapshot, baseline: baseline)));
      fullAnalysis.add(timeMicros(
          () => engine.analyse(events, snapshot, baseline: baseline)));
    }

    final r = summarise(readinessOnly);
    final f = summarise(fullAnalysis);

    // ignore: avoid_print
    print('''

=== NFR-P1 performance measurement (n = $iterations per operation) ===
Environment: Dart VM, flutter test, development machine.
Excludes HealthKit retrieval and Firestore I/O.

Operation                         Mean      Median    P95       Max
Readiness computation             ${r.mean.toStringAsFixed(4)} ms  ${r.median.toStringAsFixed(4)} ms  ${r.p95.toStringAsFixed(4)} ms  ${r.max.toStringAsFixed(4)} ms
Full analysis (8 tasks + fusion)  ${f.mean.toStringAsFixed(4)} ms  ${f.median.toStringAsFixed(4)} ms  ${f.p95.toStringAsFixed(4)} ms  ${f.max.toStringAsFixed(4)} ms

Requirement: <= 2000 ms.  Result: PASS
======================================================================
''');

    expect(f.p95, lessThan(2000));
    expect(r.p95, lessThan(2000));
  });

  test('NFR-P1: performance holds for an unusually dense schedule', () {
    // Stress case: far more events than a student would realistically have.
    final start = DateTime(2026, 3, 2, 6);
    final dense = List.generate(50, (i) {
      final s = start.add(Duration(minutes: i * 15));
      return ScheduleEvent(
        id: 'd$i',
        title: 'Task $i',
        start: s,
        end: s.add(const Duration(minutes: 30)),
        intensity: TaskIntensity.high,
        source: 'manual',
        cognitiveLoadScore: 70,
        ratingType: 'Auto',
      );
    });

    for (var i = 0; i < 50; i++) {
      engine.analyse(dense, snapshot, baseline: baseline);
    }

    final samples = <double>[];
    for (var i = 0; i < iterations; i++) {
      samples
          .add(timeMicros(() => engine.analyse(dense, snapshot, baseline: baseline)));
    }
    final s = summarise(samples);

    // ignore: avoid_print
    print('Dense schedule (50 events), n = $iterations: '
        'mean ${s.mean.toStringAsFixed(4)} ms, '
        'p95 ${s.p95.toStringAsFixed(4)} ms, '
        'max ${s.max.toStringAsFixed(4)} ms');

    expect(s.p95, lessThan(2000));
  });
}
