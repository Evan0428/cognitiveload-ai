import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import '../models/models.dart';

/// Physiological Monitoring Module — health data service (Chua Yi Zhe).
///
/// On a real iOS/watchOS device this uses the `health` package to read
/// Heart Rate, HRV, Sleep and Steps from Apple HealthKit (data collected by
/// the Apple Watch). In demo mode it generates plausible biometric snapshots
/// so the readiness engine and alerts can be exercised anywhere.
class HealthService {
  /// Demo mode auto-disables on Android/iOS so the real HealthKit pipeline runs
  /// on device, and stays on for web/desktop where no sensors exist.
  static bool demoMode = !(defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS);

  final _rng = Random();
  final Health _health = Health();
  bool _configured = false;

  /// The biometric signals the readiness model depends on.
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.STEPS,
  ];

  /// Request HealthKit (iOS) / Health Connect (Android) read permissions.
  Future<bool> requestPermissions() async {
    if (demoMode) return true;
    try {
      if (!_configured) {
        await _health.configure();
        _configured = true;
      }
      final permissions =
          _types.map((_) => HealthDataAccess.READ).toList();
      return await _health.requestAuthorization(_types,
          permissions: permissions);
    } catch (e) {
      debugPrint('HealthKit authorization failed: $e');
      return false;
    }
  }

  /// Fetch the latest physiological snapshot from HealthKit.
  Future<PhysiologicalSnapshot> fetchLatest() async {
    if (demoMode) {
      await Future.delayed(const Duration(milliseconds: 500));
      return _simulatedSnapshot();
    }

    try {
      if (!_configured) {
        await _health.configure();
        _configured = true;
      }
      final now = DateTime.now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final lookback = now.subtract(const Duration(hours: 24));

      final points = await _health.getHealthDataFromTypes(
        startTime: lookback,
        endTime: now,
        types: const [
          HealthDataType.HEART_RATE,
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          HealthDataType.SLEEP_ASLEEP,
        ],
      );

      // Latest resting/heart-rate reading.
      final heartRate = _latestNumeric(points, HealthDataType.HEART_RATE) ?? 70;
      // Latest HRV (SDNN) reading.
      final hrv = _latestNumeric(
              points, HealthDataType.HEART_RATE_VARIABILITY_SDNN) ??
          50;
      // Total minutes asleep over the lookback window -> hours.
      final sleepMinutes = points
          .where((p) => p.type == HealthDataType.SLEEP_ASLEEP)
          .fold<double>(
              0, (sum, p) => sum + p.dateTo.difference(p.dateFrom).inMinutes);
      final sleepHours = sleepMinutes / 60.0;

      // Steps since midnight (dedicated aggregate API).
      final steps =
          await _health.getTotalStepsInInterval(dayStart, now) ?? 0;

      return PhysiologicalSnapshot(
        timestamp: now,
        heartRate: heartRate,
        hrv: hrv,
        sleepHours: sleepHours > 0 ? sleepHours : 0,
        steps: steps,
      );
    } catch (e) {
      debugPrint('HealthKit fetch failed, falling back to demo data: $e');
      return _simulatedSnapshot();
    }
  }

  /// Most-recent numeric value for [type] from a list of HealthKit points.
  double? _latestNumeric(List<HealthDataPoint> points, HealthDataType type) {
    final filtered = points.where((p) => p.type == type).toList()
      ..sort((a, b) => b.dateTo.compareTo(a.dateTo));
    if (filtered.isEmpty) return null;
    final value = filtered.first.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
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
