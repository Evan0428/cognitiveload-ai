// Tests for the two personalisation features (Chua):
//   1. TaskWeightLearner  - learns NASA-TLX weights from manual ratings
//   3. ReadinessBreakdown - explains which factor holds readiness back
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';
import 'package:cognitiveload_ai/services/task_weight_learner.dart';

void main() {
  final learner = TaskWeightLearner.instance;
  final engine = CognitiveLoadEngine();

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

  group('TaskWeightLearner (personalised NASA-TLX weights)', () {
    setUp(learner.reset);

    test('falls back to the shared model before anything is learned', () {
      expect(learner.predict('Physics Lab'), isNull);
      expect(learner.scoreFor('Physics Lab'),
          IntensityClassifier.scoreFromTitle('Physics Lab'));
    });

    test('tokenises a title into meaningful terms only', () {
      final terms = TaskWeightLearner.tokenise('The Physics Lab at 3pm');
      expect(terms, contains('physics'));
      expect(terms, contains('lab'));
      expect(terms, isNot(contains('the'))); // stop word
      expect(terms, isNot(contains('at')));  // stop word
    });

    test('learns that a term is heavier for this user than the global model',
        () {
      final before = learner.scoreFor('Physics Lab');
      // The user repeatedly says lab work is brutal.
      for (var i = 0; i < 6; i++) {
        learner.learn('Physics Lab', 95);
      }
      final after = learner.scoreFor('Physics Lab');
      expect(after, greaterThan(before));
      expect(after, greaterThan(80));
    });

    test('learns that a term is lighter for this user', () {
      final before = learner.scoreFor('Final Exam');
      for (var i = 0; i < 6; i++) {
        learner.learn('Final Exam', 30); // this user finds exams easy
      }
      expect(learner.scoreFor('Final Exam'), lessThan(before));
    });

    test('generalises a learned term to a new task title', () {
      for (var i = 0; i < 6; i++) {
        learner.learn('Calculus Tutorial', 90);
      }
      // "tutorial" was learned as heavy, so a different tutorial inherits it.
      final unseen = learner.predict('Statistics Tutorial');
      expect(unseen, isNotNull);
      expect(unseen!, greaterThan(IntensityClassifier.scoreFromTitle('Statistics Tutorial')));
    });

    test('a single rating does not swing the score wildly (blended prior)', () {
      final global = IntensityClassifier.scoreFromTitle('Group Meeting');
      learner.learn('Group Meeting', 100); // one extreme label
      final after = learner.scoreFor('Group Meeting');
      expect(after, greaterThan(global));  // it did move
      expect(after, lessThan(100));        // but not all the way
    });

    test('the learning rate decays so estimates settle', () {
      // First rating seeds the term exactly; later ratings move it by a
      // shrinking amount, which is what makes the estimate converge.
      learner.learn('Lab', 100);
      expect(learner.weights['lab']!.score, 100);

      final beforeStep1 = learner.weights['lab']!.score;
      learner.learn('Lab', 0);
      final step1 = (beforeStep1 - learner.weights['lab']!.score).abs();

      final beforeStep2 = learner.weights['lab']!.score;
      learner.learn('Lab', 0);
      final step2 = (beforeStep2 - learner.weights['lab']!.score).abs();

      expect(step2, lessThan(step1)); // decaying learning rate
      expect(learner.weights['lab']!.observations, 3);
    });

    test('explains where a score came from', () {
      expect(learner.explain('Unknown Thing'), contains('shared keyword model'));
      learner.learn('Physics Lab', 88);
      expect(learner.explain('Physics Lab'), contains('Personalised'));
    });
  });

  group('ReadinessBreakdown (explainable readiness)', () {
    test('factor points sum to the readiness score', () {
      final b = engine.explainReadiness(
          snap(hr: 70, hrv: 50, sleep: 6, steps: 4000));
      final sum = b.factors.fold(0.0, (s, f) => s + f.achieved);
      expect(sum, closeTo(b.readiness, 0.001));
    });

    test('identifies sleep as the weakest factor when sleep is short', () {
      final b = engine.explainReadiness(
          snap(hr: 60, hrv: 80, sleep: 3, steps: 8000));
      expect(b.weakest.name, 'Sleep');
      expect(b.summary, contains('sleep'));
    });

    test('identifies HRV as the weakest factor when HRV is suppressed', () {
      final b = engine.explainReadiness(
          snap(hr: 60, hrv: 10, sleep: 8, steps: 8000));
      expect(b.weakest.name, 'HRV');
    });

    test('reports nothing holding readiness back when all signals are good',
        () {
      final b = engine.explainReadiness(
          snap(hr: 55, hrv: 90, sleep: 9, steps: 9000));
      expect(b.summary, contains('nothing is holding'));
    });

    test('flags when personal targets were used', () {
      final s = snap(hr: 64, hrv: 55, sleep: 6.5, steps: 6000);
      const personal = PhysiologicalBaseline(
          avgSleepHours: 6.5, avgHrv: 55, avgHeartRate: 64, days: 14);
      expect(engine.explainReadiness(s).personalised, isFalse);
      expect(engine.explainReadiness(s, baseline: personal).personalised,
          isTrue);
    });

    test('the breakdown is attached to the analysis result', () {
      final r = engine.analyse(
          const [], snap(hr: 70, hrv: 40, sleep: 5, steps: 3000));
      expect(r.breakdown, isNotNull);
      expect(r.breakdown!.readiness, closeTo(r.readinessScore, 0.001));
    });
  });
}
