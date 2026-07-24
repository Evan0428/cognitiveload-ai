// Unit tests for the CognitiveLoad AI analytical core (Chua's physiological
// module + the schedule/physiology fusion). Pure logic, no Firebase, so they
// run fast and deterministically.

import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';

void main() {
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
      expect(IntensityClassifier.scoreFromTitle('Exam'), 90);
      expect(IntensityClassifier.scoreFromTitle('Assignment'), 70);
      expect(IntensityClassifier.scoreFromTitle('Lecture'), 50);
      expect(IntensityClassifier.scoreFromTitle('Rest'), 20);
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
