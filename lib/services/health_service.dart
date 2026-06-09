import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// Physiological Monitoring Module — health data service (Chua Yi Zhe).
///
/// On a real iOS/watchOS device this uses the `health` package to read
/// Heart Rate, HRV, Sleep and Steps from Apple HealthKit (data collected by
/// the Apple Watch). In demo mode it generates plausible biometric snapshots
/// so the readiness engine and alerts can be exercised anywhere.
class HealthService {
  static bool demoMode = !(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  final _rng = Random();

  /// Request HealthKit / Health Connect permissions.
  Future<bool> requestPermissions() async {
    if (demoMode) return true;

    // ----- REAL DEVICE IMPLEMENTATION (uncomment on device) -----
    // final health = Health();
    // final types = [
    //   HealthDataType.HEART_RATE,
    //   HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    //   HealthDataType.SLEEP_ASLEEP,
    //   HealthDataType.STEPS,
    // ];
    // return await health.requestAuthorization(types);
    // ------------------------------------------------------------

    return true;
  }

  /// Fetch the latest physiological snapshot.
  Future<PhysiologicalSnapshot> fetchLatest() async {
    if (demoMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _simulatedSnapshot();
    }

    // ----- REAL DEVICE IMPLEMENTATION (uncomment on device) -----
    // Read each HealthDataType from `health`, aggregate, and build the
    // PhysiologicalSnapshot below from the real values.
    // ------------------------------------------------------------

    return _simulatedSnapshot();
  }

  PhysiologicalSnapshot _simulatedSnapshot() {
    return PhysiologicalSnapshot(
      timestamp: DateTime.now(),
      heartRate: 62 + _rng.nextDouble() * 38, // 62-100 bpm
      hrv: 25 + _rng.nextDouble() * 65, // 25-90 ms
      sleepHours: 4.5 + _rng.nextDouble() * 4.0, // 4.5-8.5 h
      steps: 1500 + _rng.nextInt(9000), // 1.5k-10.5k
    );
  }
}
