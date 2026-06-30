// Unit tests for the CognitiveLoad AI analytical core.
//
// These exercise the pure logic (NASA-TLX keyword weighting + readiness fusion)
// without Firebase, so they run fast and deterministically in CI.

import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';

void main() {
  group('IntensityClassifier (modified NASA-TLX weighting)', () {
    test('an exam outranks an assignment outranks a lecture outranks a break',
        () {
      expect(IntensityClassifier.fromTitle('Final Exam'),
          TaskIntensity.critical);
      expect(IntensityClassifier.fromTitle('Database Assignment'),
          TaskIntensity.high);
      expect(IntensityClassifier.fromTitle('Calculus Lecture'),
          TaskIntensity.medium);
      expect(
          IntensityClassifier.fromTitle('Lunch Break'), TaskIntensity.low);
    });

    test('score is monotonic with intensity and exam is the highest', () {
      expect(IntensityClassifier.scoreFromTitle('Exam'), 90);
      expect(IntensityClassifier.scoreFromTitle('Assignment'), 70);
      expect(IntensityClassifier.scoreFromTitle('Lecture'), 50);
      expect(IntensityClassifier.scoreFromTitle('Rest'), 20);
    });

    test('score round-trips back to the same intensity band', () {
      for (final i in TaskIntensity.values) {
        expect(TaskIntensityX.fromScore(i.score), i);
      }
    });
  });

  group('CognitiveLoadEngine', () {
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

    test('workload score grows with more high-intensity tasks', () {
      final light = [event('Lunch Break', 12, 13)];
      final heavy = [
        event('Final Exam', 9, 11),
        event('Project Submission', 14, 17),
      ];
      expect(engine.computeWorkloadScore(heavy),
          greaterThan(engine.computeWorkloadScore(light)));
    });

    test('good physiology yields high readiness, poor physiology yields low',
        () {
      final rested = PhysiologicalSnapshot(
        timestamp: DateTime.now(),
        heartRate: 58,
        hrv: 80,
        sleepHours: 8,
        steps: 8000,
      );
      final strained = PhysiologicalSnapshot(
        timestamp: DateTime.now(),
        heartRate: 98,
        hrv: 20,
        sleepHours: 4,
        steps: 500,
      );
      expect(engine.computeReadiness(rested),
          greaterThan(engine.computeReadiness(strained)));
    });

    test('high workload + low readiness escalates the load level', () {
      final events = [
        event('Final Exam', 9, 12),
        event('Midterm Exam', 13, 16),
        event('Project Deadline', 17, 20),
      ];
      final strained = PhysiologicalSnapshot(
        timestamp: DateTime.now(),
        heartRate: 99,
        hrv: 18,
        sleepHours: 3.5,
        steps: 300,
      );
      final result = engine.analyse(events, strained);
      expect(result.combinedLoad, greaterThan(55));
      expect(result.alerts, isNotEmpty);
    });
  });
}
