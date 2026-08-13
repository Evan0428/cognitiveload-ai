// Unit tests for the CognitiveLoad AI analytical core (Chua's physiological
// module + the schedule/physiology fusion). Pure logic, no Firebase, so they
// run fast and deterministically.

import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/adaptive_threshold.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';

void main() {
  _adaptiveThresholdTests();
  final engine = CognitiveLoadEngine();

  ScheduleEvent event(String title, int startHour, int endHour) {
    final now = DateTime.now();
    return ScheduleEvent(
      id: title,
      title: title,
      start: DateTime(now.year, now.month, now.day, startHour),
      end: DateTime(now.year, now.month, now.day, endHour),
      intensity: IntensityClassifier.fromTitle(title),
    );
  }

  PhysiologicalSnapshot snap({
    required double hr,
    required double hrv,
    required double sleep,
    required int steps,
  }) =>
      PhysiologicalSnapshot(
        timestamp: DateTime.now(),
        heartRate: hr,
        hrv: hrv,
        sleepHours: sleep,
        steps: steps,
      );

  group('IntensityClassifier (modified NASA-TLX weighting)', () {
    test('exam > assignment > lecture > break', () {
      expect(
          IntensityClassifier.fromTitle('Final Exam'), TaskIntensity.critical);
      expect(IntensityClassifier.fromTitle('Database Assignment'),
          TaskIntensity.high);
      expect(IntensityClassifier.fromTitle('Calculus Lecture'),
          TaskIntensity.medium);
      expect(IntensityClassifier.fromTitle('Lunch Break'), TaskIntensity.low);
    });

    test('scores are monotonic and exam is highest', () {
      // Assert ordering, not exact magic numbers, so either partner can retune
      // the NASA-TLX weights without breaking the test.
      final exam = IntensityClassifier.scoreFromTitle('Exam');
      final assignment = IntensityClassifier.scoreFromTitle('Assignment');
      final lecture = IntensityClassifier.scoreFromTitle('Lecture');
      final rest = IntensityClassifier.scoreFromTitle('Rest');
      expect(exam, greaterThan(assignment));
      expect(assignment, greaterThan(lecture));
      expect(lecture, greaterThan(rest));
    });
  });

  group('Readiness model (Chua)', () {
    test('good physiology scores higher than poor physiology', () {
      final rested = snap(hr: 58, hrv: 80, sleep: 8, steps: 8000);
      final strained = snap(hr: 98, hrv: 20, sleep: 4, steps: 500);
      expect(engine.computeReadiness(rested),
          greaterThan(engine.computeReadiness(strained)));
    });

    test('personal baseline lifts readiness for a natural short sleeper', () {
      final today = snap(hr: 64, hrv: 55, sleep: 6.5, steps: 6000);
      const personal = PhysiologicalBaseline(
          avgSleepHours: 6.5, avgHrv: 55, avgHeartRate: 64, days: 14);
      expect(engine.computeReadiness(today, baseline: personal),
          greaterThan(engine.computeReadiness(today)));
    });

    test('baseline below minDays is ignored', () {
      final today = snap(hr: 64, hrv: 55, sleep: 6.5, steps: 6000);
      const tooFew = PhysiologicalBaseline(
          avgSleepHours: 6.5, avgHrv: 55, avgHeartRate: 64, days: 2);
      expect(engine.computeReadiness(today, baseline: tooFew),
          engine.computeReadiness(today));
    });
  });

  group('Schedule + physiology fusion', () {
    test('same schedule weighs more when the user is depleted', () {
      final events = [event('Database Assignment', 9, 12)];
      final rested = engine.analyse(
          events, snap(hr: 58, hrv: 80, sleep: 8, steps: 8000));
      final depleted = engine.analyse(
          events, snap(hr: 98, hrv: 20, sleep: 4, steps: 500));
      expect(depleted.combinedLoad, greaterThan(rested.combinedLoad));
    });

    test('no tasks -> zero combined load but readiness still reported', () {
      final result =
          engine.analyse(const [], snap(hr: 60, hrv: 70, sleep: 7.5, steps: 7000));
      expect(result.combinedLoad, 0);
      expect(result.readinessScore, greaterThan(0));
    });

    test('acute HR spike vs personal baseline raises a strain alert', () {
      const restingBaseline = PhysiologicalBaseline(
          avgSleepHours: 7.5, avgHrv: 60, avgHeartRate: 60, days: 10);
      final spiking = snap(hr: 85, hrv: 60, sleep: 7.5, steps: 5000);
      final result =
          engine.analyse(const [], spiking, baseline: restingBaseline);
      expect(result.alerts.any((a) => a.contains('Heart-rate spike')), isTrue);
    });

    test('high workload + low readiness escalates the load level', () {
      final events = [
        event('Final Exam', 9, 12),
        event('Midterm Exam', 13, 16),
        event('Project Deadline', 17, 20),
      ];
      final result =
          engine.analyse(events, snap(hr: 99, hrv: 18, sleep: 3.5, steps: 300));
      expect(result.combinedLoad, greaterThan(55));
      expect(result.alerts, isNotEmpty);
    });
  });
}

// ---------------------------------------------------------------------------
// Adaptive AI threshold (Chua) — the model must actually learn from feedback.
// ---------------------------------------------------------------------------
void _adaptiveThresholdTests() {
  group('AdaptiveThreshold (on-device learning)', () {
    test('starts at the user preference and is not yet personalised', () {
      final t = AdaptiveThreshold(base: 70);
      expect(t.value, 70);
      expect(t.isPersonalised, isFalse);
      expect(t.confidence, 0);
    });

    test('dismissing alerts raises the threshold (warn later)', () {
      final t = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 5; i++) {
        t.alertDismissed();
      }
      expect(t.value, greaterThan(70));
      expect(t.isPersonalised, isTrue);
    });

    test('accepting alerts nudges the threshold down (warn earlier)', () {
      final t = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 5; i++) {
        t.alertAccepted();
      }
      expect(t.value, lessThan(70));
    });

    test('a missed burnout (strain without warning) lowers the threshold', () {
      final t = AdaptiveThreshold(base: 70);
      t.observeOutcome(
          peakLoad: 60, readinessBefore: 80, readinessAfter: 60);
      expect(t.value, lessThan(70));
    });

    test('a false alarm (warned but coped) raises the threshold', () {
      final t = AdaptiveThreshold(base: 70);
      t.observeOutcome(
          peakLoad: 90, readinessBefore: 80, readinessAfter: 79);
      expect(t.value, greaterThan(70));
    });

    test('learning is bounded around the user preference', () {
      final t = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 200; i++) {
        t.alertDismissed();
      }
      expect(t.value, lessThanOrEqualTo(70 + AdaptiveThreshold.drift));
      expect(t.value, lessThanOrEqualTo(AdaptiveThreshold.maxValue));
    });

    test('learning rate decays so the value settles', () {
      final a = AdaptiveThreshold(base: 70);
      a.alertDismissed();
      final firstStep = a.value - 70;

      final b = AdaptiveThreshold(base: 70, observations: 30, learned: 70);
      b.alertDismissed();
      final laterStep = b.value - 70;

      expect(laterStep, lessThan(firstStep));
    });

    test('survives a save/load round trip', () {
      final t = AdaptiveThreshold(base: 65)..alertDismissed();
      final restored = AdaptiveThreshold.decode(t.encode());
      expect(restored.value, t.value);
      expect(restored.observations, t.observations);
      expect(restored.base, 65);
    });

    test('moving the slider re-centres the model', () {
      final t = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 5; i++) {
        t.alertDismissed();
      }
      t.setBase(50);
      expect(t.value, 50);
      expect(t.observations, 0);
    });
  });
}
