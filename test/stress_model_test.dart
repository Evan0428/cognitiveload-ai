// Tests for the on-device TensorFlow Lite stress model (Chua) and the way the
// engine fuses its output.
//
// These deliberately do NOT require assets/models/stress_model.tflite to
// exist. The point is that the app is fully functional before the model has
// been trained and keeps working if the interpreter ever fails to start, so
// the fallback path is what most needs covering.
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';
import 'package:cognitiveload_ai/services/stress_model.dart';

void main() {
  final engine = CognitiveLoadEngine();

  final snapshot = PhysiologicalSnapshot(
    timestamp: DateTime.now(),
    heartRate: 82,
    hrv: 34,
    sleepHours: 5.5,
    steps: 3000,
  );

  List<ScheduleEvent> busyDay() => [
        ScheduleEvent(
          id: 'a',
          title: 'Final Exam',
          start: DateTime.now(),
          end: DateTime.now().add(const Duration(hours: 3)),
          intensity: TaskIntensity.critical,
          source: 'manual',
          cognitiveLoadScore: 90,
          ratingType: 'Auto',
        ),
      ];

  group('StressModel (graceful degradation)', () {
    test('reports unavailable until a trained model is loaded', () {
      expect(StressModel.instance.isAvailable, isFalse);
    });

    test('returns null rather than guessing when the model is absent', () {
      expect(StressModel.instance.probability(snapshot), isNull);
    });

    test('describes a probability in plain English', () {
      expect(StressModel.describe(0.9), contains('stressed'));
      expect(StressModel.describe(0.5), contains('strain'));
      expect(StressModel.describe(0.1), contains('calm'));
    });
  });

  group('Engine fusion with the learned stress probability', () {
    test('an unavailable model leaves the analysis unchanged', () {
      final withoutModel = engine.analyse(busyDay(), snapshot);
      expect(withoutModel.stressProbability, isNull);
      expect(
        withoutModel.alerts.any((a) => a.contains('Stress pattern')),
        isFalse,
      );
    });

    test('a high stress probability raises combined load', () {
      final calm =
          engine.analyse(busyDay(), snapshot, stressProbability: 0.0);
      final stressed =
          engine.analyse(busyDay(), snapshot, stressProbability: 1.0);
      expect(stressed.combinedLoad, greaterThan(calm.combinedLoad));
    });

    test('the probability does not change the readiness score itself', () {
      // Readiness stays a transparent, rule-based number; the network only
      // affects how heavily the day's workload lands on top of it.
      final calm =
          engine.analyse(busyDay(), snapshot, stressProbability: 0.0);
      final stressed =
          engine.analyse(busyDay(), snapshot, stressProbability: 1.0);
      expect(stressed.readinessScore, closeTo(calm.readinessScore, 0.001));
    });

    test('warns the user once the model is confident they are stressed', () {
      final r = engine.analyse(busyDay(), snapshot, stressProbability: 0.85);
      expect(r.alerts.any((a) => a.contains('Stress pattern')), isTrue);
      expect(r.alerts.any((a) => a.contains('85%')), isTrue);
    });

    test('stays quiet on a borderline probability', () {
      final r = engine.analyse(busyDay(), snapshot, stressProbability: 0.5);
      expect(r.alerts.any((a) => a.contains('Stress pattern')), isFalse);
    });

    test('the probability is carried on the result for the UI', () {
      final r = engine.analyse(busyDay(), snapshot, stressProbability: 0.42);
      expect(r.stressProbability, closeTo(0.42, 0.001));
    });

    test('a task-free day stays at zero load however stressed the user is', () {
      final r = engine.analyse(const [], snapshot, stressProbability: 1.0);
      expect(r.combinedLoad, 0);
    });
  });
}
