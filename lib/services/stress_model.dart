import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/models.dart';

/// On-device acute-stress classifier (Chua Yi Zhe).
///
/// A small neural network trained offline on **WESAD** (Schmidt et al., ICMI
/// 2018) — 15 subjects wearing research-grade sensors through a protocol of
/// baseline, stress, amusement and meditation conditions — and exported to
/// TensorFlow Lite. Inference runs entirely on the phone: no physiological
/// data leaves the device, and the app works offline.
///
/// See `tools/train_stress_model.py` for the training pipeline and
/// `tools/stress_model_metrics.json` for the leave-one-subject-out scores.
///
/// The four inputs are exactly what Apple HealthKit can supply, in the order
/// the network was trained on:
///
///     [ heart rate, HRV (SDNN), heart rate / baseline, HRV / baseline ]
///
/// The two ratios express each reading against the user's *own* resting level
/// (report section 2.4.4) — a 90 bpm reading means something very different for
/// someone who rests at 55 than for someone who rests at 85.
///
/// Everything here degrades gracefully. If the model file has not been trained
/// yet, or the interpreter fails to start, [probability] returns null and the
/// app falls back to its rule-based readiness scoring.
class StressModel {
  StressModel._();
  static final StressModel instance = StressModel._();

  static const String asset = 'assets/models/stress_model.tflite';

  /// Population anchors, used while the user has no reliable personal
  /// baseline. These match the norms in [CognitiveLoadEngine.explainReadiness]
  /// so the two models describe the same "typical" person.
  static const double _normHeartRate = 60.0;
  static const double _normHrv = 80.0;

  Interpreter? _interpreter;
  bool _loadAttempted = false;

  /// True once the network is loaded and inference can run.
  bool get isAvailable => _interpreter != null;

  /// Load the network. Safe to call more than once; only the first call works.
  Future<void> load() async {
    if (_loadAttempted) return;
    _loadAttempted = true;
    try {
      _interpreter = await Interpreter.fromAsset(asset);
    } catch (e) {
      // Expected until `tools/train_stress_model.py` has been run — the app
      // stays fully functional on its rule-based scoring.
      debugPrint('Stress model unavailable, using rule-based readiness: $e');
    }
  }

  /// Probability (0..1) that the user is under acute physiological stress,
  /// or null when the model is unavailable or the reading is unusable.
  double? probability(
    PhysiologicalSnapshot snapshot, {
    PhysiologicalBaseline? baseline,
  }) {
    final interpreter = _interpreter;
    if (interpreter == null) return null;

    // A missing sensor reads as 0 and would be scored as extreme stress.
    if (snapshot.heartRate <= 0 || snapshot.hrv <= 0) return null;

    final personal = baseline != null && baseline.isReliable;
    final baseHeartRate = personal && baseline.avgHeartRate > 0
        ? baseline.avgHeartRate
        : _normHeartRate;
    final baseHrv =
        personal && baseline.avgHrv > 0 ? baseline.avgHrv : _normHrv;

    final input = [
      [
        snapshot.heartRate,
        snapshot.hrv,
        snapshot.heartRate / baseHeartRate,
        snapshot.hrv / baseHrv,
      ]
    ];
    final output = [List<double>.filled(1, 0)];

    try {
      interpreter.run(input, output);
    } catch (e) {
      debugPrint('Stress inference failed: $e');
      return null;
    }
    return output[0][0].clamp(0.0, 1.0);
  }

  /// Plain-English reading of a probability, for the Wellbeing card.
  static String describe(double p) {
    if (p >= 0.7) {
      return 'Your heart-rate and HRV pattern closely matches the stressed '
          'state in the training data.';
    }
    if (p >= 0.4) {
      return 'Some signs of physiological strain in your heart-rate pattern.';
    }
    return 'Your heart-rate and HRV pattern looks calm.';
  }

  @visibleForTesting
  void resetForTest() {
    _interpreter?.close();
    _interpreter = null;
    _loadAttempted = false;
  }
}
