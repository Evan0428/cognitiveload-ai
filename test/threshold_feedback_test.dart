// The explicit training signal for the adaptive threshold must be collected
// exactly once per alert.
//
// It previously lived as chips under the assistant's speech bubble, which
// reappeared on every tap — so a single alert could be answered repeatedly and
// fed into the learner many times, dragging the threshold far further than one
// event justifies. These tests hold the one-answer-per-alert rule in place.
import 'package:flutter_test/flutter_test.dart';

import 'package:cognitiveload_ai/services/adaptive_threshold.dart';

void main() {
  group('AdaptiveThreshold — repeated answers to one alert', () {
    test('each accepted answer moves the threshold by a shrinking amount', () {
      final t = AdaptiveThreshold(base: 70);
      final start = t.value;

      t.alertDismissed();
      final afterFirst = t.value;
      t.alertDismissed();
      final afterSecond = t.value;

      final step1 = afterFirst - start;
      final step2 = afterSecond - afterFirst;

      expect(step1, greaterThan(0), reason: '"I\'m fine" should warn later');
      expect(step2, greaterThan(0));
      expect(step2, lessThan(step1), reason: 'decaying learning rate');
    });

    test('answering one alert five times moves it much further than once', () {
      // This is precisely the damage the old chips allowed, and the reason the
      // question is now spent as soon as it is answered.
      final once = AdaptiveThreshold(base: 70)..alertDismissed();
      final fiveTimes = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 5; i++) {
        fiveTimes.alertDismissed();
      }

      expect(fiveTimes.value, greaterThan(once.value + 5),
          reason: 'unbounded answering visibly corrupts the estimate');
      expect(fiveTimes.observations, 5);
      expect(once.observations, 1);
    });

    test('opposite answers move the threshold in opposite directions', () {
      final up = AdaptiveThreshold(base: 70)..alertDismissed();
      final down = AdaptiveThreshold(base: 70)..alertAccepted();

      expect(up.value, greaterThan(70));
      expect(down.value, lessThan(70));
    });

    test('the learned value never escapes the band around the user setting',
        () {
      final t = AdaptiveThreshold(base: 70);
      for (var i = 0; i < 200; i++) {
        t.alertDismissed();
      }
      expect(t.value, lessThanOrEqualTo(70 + AdaptiveThreshold.drift));
      expect(t.value, lessThanOrEqualTo(AdaptiveThreshold.maxValue));
    });

    test('confidence only reaches 1.0 after enough separate observations', () {
      final t = AdaptiveThreshold(base: 70);
      expect(t.isPersonalised, isFalse);
      expect(t.confidence, 0);

      t.alertDismissed();
      expect(t.isPersonalised, isTrue);
      expect(t.confidence, lessThan(1.0),
          reason: 'one answer must not read as a confident model');

      for (var i = 1; i < AdaptiveThreshold.confidentAfter; i++) {
        t.alertDismissed();
      }
      expect(t.confidence, 1.0);
    });

    test('explanation names both learning channels before any observation', () {
      final t = AdaptiveThreshold(base: 70);
      final text = t.explanation.toLowerCase();
      expect(text, contains('alert'));
      expect(text, contains('recovery'));
    });
  });
}
