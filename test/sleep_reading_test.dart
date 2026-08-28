// Sleep duration read zero on a real Apple Watch, and the cause was a data
// type mismatch rather than a missing signal.
//
// HealthKit stores sleep as HKCategoryValueSleepAnalysis. The health plugin
// exposes each raw value as a separate type: SLEEP_ASLEEP is value 1
// (asleepUnspecified), while SLEEP_LIGHT / SLEEP_DEEP / SLEEP_REM are values
// 3 / 4 / 5 (asleepCore / asleepDeep / asleepREM). An Apple Watch writes only
// the staged values, so querying SLEEP_ASLEEP alone returns nothing.
//
// These tests hold the combining rule in place — in particular that staged and
// unspecified sleep are never added together.
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/services/health_service.dart';

void main() {
  group('HealthService.totalSleepHours', () {
    test('uses staged sleep, as written by an Apple Watch', () {
      // 4 h core + 1.5 h deep + 1.5 h REM = 7 h
      expect(HealthService.totalSleepHours(420, 0), 7.0);
    });

    test('falls back to unspecified sleep from other sources', () {
      // No stages recorded, but a third-party app logged 6.5 h.
      expect(HealthService.totalSleepHours(0, 390), 6.5);
    });

    test('does not add staged and unspecified together', () {
      // A night recorded twice must not report thirteen hours of sleep.
      expect(HealthService.totalSleepHours(420, 390), 7.0,
          reason: 'staged data wins; the two are alternatives, not addends');
    });

    test('prefers staged data even when it is the shorter record', () {
      // Staged sleep is the more precise record, so it wins on principle
      // rather than on magnitude.
      expect(HealthService.totalSleepHours(300, 480), 5.0);
    });

    test('reports zero when nothing was recorded', () {
      expect(HealthService.totalSleepHours(0, 0), 0);
    });

    test('never returns a negative duration', () {
      expect(HealthService.totalSleepHours(-30, 0), 0);
      expect(HealthService.totalSleepHours(0, -30), 0);
    });

    test('a short nap still registers', () {
      expect(HealthService.totalSleepHours(25, 0), closeTo(0.4167, 0.001));
    });
  });
}
