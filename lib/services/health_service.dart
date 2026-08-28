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

  /// Sleep as Apple Watch actually records it.
  ///
  /// HealthKit stores sleep as `HKCategoryValueSleepAnalysis`, and the plugin
  /// exposes each raw value as its own type: SLEEP_ASLEEP is value 1
  /// (`asleepUnspecified`), while SLEEP_LIGHT / SLEEP_DEEP / SLEEP_REM are
  /// values 3 / 4 / 5 (`asleepCore` / `asleepDeep` / `asleepREM`).
  ///
  /// An Apple Watch writes only the staged values. Querying SLEEP_ASLEEP alone
  /// therefore returns nothing at all and sleep reads as zero — which is
  /// exactly what happened on device. The stages are summed instead, and
  /// SLEEP_ASLEEP is retained as a fallback for sources that still write the
  /// unspecified value, such as manual entries and some third-party apps.
  static const List<HealthDataType> _sleepStages = [
    HealthDataType.SLEEP_LIGHT, // asleepCore
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  /// The biometric signals the readiness model depends on.
  static const List<HealthDataType> _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthDataType.SLEEP_ASLEEP,
    ..._sleepStages,
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
          ..._sleepStages,
        ],
      );

      // Latest resting/heart-rate reading.
      final heartRate = _latestNumeric(points, HealthDataType.HEART_RATE) ?? 70;
      // Latest HRV (SDNN) reading.
      final hrv = _latestNumeric(
              points, HealthDataType.HEART_RATE_VARIABILITY_SDNN) ??
          50;

      // Sleep: sum the staged values the Watch writes, falling back to the
      // unspecified value for other sources. See [_sleepStages].
      final stageMinutes = _sleepStages.fold<double>(
          0, (sum, type) => sum + _minutesOf(points, type));
      final unspecifiedMinutes =
          _minutesOf(points, HealthDataType.SLEEP_ASLEEP);
      final sleepHours =
          totalSleepHours(stageMinutes, unspecifiedMinutes);

      // Steps since midnight (dedicated aggregate API).
      final steps =
          await _health.getTotalStepsInInterval(dayStart, now) ?? 0;

      return PhysiologicalSnapshot(
        timestamp: now,
        heartRate: heartRate,
        hrv: hrv,
        sleepHours: sleepHours,
        steps: steps,
      );
    } catch (e) {
      debugPrint('HealthKit fetch failed, falling back to demo data: $e');
      return _simulatedSnapshot();
    }
  }

  /// Combine staged and unspecified sleep into a single duration in hours.
  ///
  /// The two are not added together. A device reports one or the other: an
  /// Apple Watch writes stages, other sources write the unspecified value, and
  /// summing both would double-count a night that happened to be recorded
  /// twice. Staged data is preferred because it is the more precise record.
  @visibleForTesting
  static double totalSleepHours(
      double stageMinutes, double unspecifiedMinutes) {
    final minutes = stageMinutes > 0 ? stageMinutes : unspecifiedMinutes;
    return minutes > 0 ? minutes / 60.0 : 0;
  }

  /// Total minutes covered by all points of [type].
  double _minutesOf(List<HealthDataPoint> points, HealthDataType type) =>
      points.where((p) => p.type == type).fold<double>(
          0, (sum, p) => sum + p.dateTo.difference(p.dateFrom).inMinutes);

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
