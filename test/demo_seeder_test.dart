// Verifies that the demonstration data actually produces the situation it is
// meant to demonstrate. Hand-picked numbers are easy to get wrong, and a
// rehearsal built on data that quietly lands in the "Balanced" band teaches the
// wrong demo.
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/models/models.dart';
import 'package:cognitiveload_ai/services/cognitive_load_engine.dart';
import 'package:cognitiveload_ai/services/demo_seeder.dart';

void main() {
  final engine = CognitiveLoadEngine();

  group('DemoSeeder physiological history', () {
    test('provides a full fortnight, one reading per day', () {
      final days = DemoSeeder.fortnight();
      expect(days.length, 14);

      final dayKeys = days
          .map((s) => '${s.timestamp.year}-${s.timestamp.month}-${s.timestamp.day}')
          .toSet();
      expect(dayKeys.length, 14, reason: 'one reading per distinct day');
    });

    test('is ordered oldest first and ends today', () {
      final days = DemoSeeder.fortnight();
      for (var i = 1; i < days.length; i++) {
        expect(days[i].timestamp.isAfter(days[i - 1].timestamp), isTrue);
      }
      final now = DateTime.now();
      expect(days.last.timestamp.day, now.day);
    });

    test('yields a baseline the engine will treat as reliable', () {
      final baseline = PhysiologicalBaseline.fromSnapshots(DemoSeeder.fortnight());
      expect(baseline, isNotNull);
      expect(baseline.isReliable, isTrue);
      expect(baseline.days, greaterThanOrEqualTo(PhysiologicalBaseline.minDays));
    });

    test('personal targets differ from the population norms', () {
      // The whole point of the fortnight is to make personalisation visible.
      final baseline = PhysiologicalBaseline.fromSnapshots(DemoSeeder.fortnight());
      final generic = engine.explainReadiness(DemoSeeder.today());
      final personal =
          engine.explainReadiness(DemoSeeder.today(), baseline: baseline);

      expect(generic.personalised, isFalse);
      expect(personal.personalised, isTrue);
      expect(personal.readiness, isNot(closeTo(generic.readiness, 0.5)),
          reason: 'personal targets should move the score noticeably');
    });

    test('the assignment week is visibly worse than the settled days', () {
      final days = DemoSeeder.fortnight();
      final settled = engine.computeReadiness(days[1]);   // 12 days ago
      final worst = engine.computeReadiness(days[6]);     // 7 days ago
      expect(worst, lessThan(settled - 15),
          reason: 'the dip must be obvious on the trend chart');
    });
  });

  group('DemoSeeder today', () {
    final baseline = PhysiologicalBaseline.fromSnapshots(DemoSeeder.fortnight());

    test('today is strained, so there is something to explain', () {
      final b = engine.explainReadiness(DemoSeeder.today(), baseline: baseline);
      expect(b.readiness, lessThan(70),
          reason: 'a healthy score gives the demo nothing to talk about');
      expect(b.weakest.lost, greaterThan(3),
          reason: 'the "Why this score?" card needs a real weakest factor');
      expect(b.summary, contains('held back by'));
    });

    test('a full task list plus low readiness reaches the overload band', () {
      final result = engine.analyse(
        DemoSeeder.todayTasks(),
        DemoSeeder.today(),
        baseline: baseline,
      );
      expect(result.level, LoadLevel.overload,
          reason: 'the alert and Focus Lock demo depend on this');
      expect(result.alerts, isNotEmpty);
    });

    test('the workload alone already exceeds the warning threshold', () {
      final workload = engine.computeWorkloadScore(DemoSeeder.todayTasks());
      expect(workload,
          greaterThan(CognitiveLoadEngine.workloadWarningThreshold));
    });

    test('removing the tasks returns the day to a calm state', () {
      // So the presenter can show both ends of the scale.
      final result =
          engine.analyse(const [], DemoSeeder.today(), baseline: baseline);
      expect(result.level, LoadLevel.safe);
      expect(result.combinedLoad, 0);
    });
  });

  group('DemoSeeder tasks', () {
    test('every task is scheduled for today and tagged for cleanup', () {
      final now = DateTime.now();
      for (final e in DemoSeeder.todayTasks()) {
        expect(e.start.day, now.day);
        expect(e.end.isAfter(e.start), isTrue);
        expect(e.id.startsWith(DemoSeeder.tag), isTrue,
            reason: 'clearDemoData() removes tasks by this prefix');
      }
    });

    test('the weight-learning pair shares a term so learning generalises', () {
      final a = TaskWeightLearnerTokens.of(DemoSeeder.weightLearningPair[0]);
      final b = TaskWeightLearnerTokens.of(DemoSeeder.weightLearningPair[1]);
      expect(a.toSet().intersection(b.toSet()), isNotEmpty);
    });
  });
}

/// Small indirection so this test does not depend on the learner's singleton.
class TaskWeightLearnerTokens {
  static List<String> of(String title) => title
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 2)
      .toList();
}
