import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// Physiological monitoring dashboard (Chua Yi Zhe's module).
class WellbeingScreen extends StatelessWidget {
  const WellbeingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.snapshot;
    final readiness = state.result?.readinessScore ?? 0;
    final baseline = state.baseline;

    return Scaffold(
      appBar: AppBar(title: const Text('Wellbeing')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ReadinessHeader(
                  readiness: readiness,
                  updated: s.timestamp,
                  baselineDays: baseline?.days ?? 0,
                  baselineReliable: baseline?.isReliable ?? false,
                ),
                const SizedBox(height: 16),
                _FocusLockCard(
                  enabled: state.focusLock,
                  onChanged: (_) => state.toggleFocusLock(),
                ),
                const SizedBox(height: 20),
                _TrendChart(trend: state.readinessTrend),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text('Biometric Signals',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.ink)),
                ),
                _SignalRow(
                  label: 'Heart Rate',
                  value: '${s.heartRate.toStringAsFixed(0)} bpm',
                  fraction: ((100 - s.heartRate) / 40).clamp(0.0, 1.0),
                  icon: Icons.monitor_heart_rounded,
                ),
                _SignalRow(
                  label: 'Heart Rate Variability',
                  value: '${s.hrv.toStringAsFixed(0)} ms',
                  fraction: (s.hrv / 80).clamp(0.0, 1.0),
                  icon: Icons.show_chart_rounded,
                ),
                _SignalRow(
                  label: 'Sleep Duration',
                  value: '${s.sleepHours.toStringAsFixed(1)} h',
                  fraction: (s.sleepHours / 8).clamp(0.0, 1.0),
                  icon: Icons.bedtime_rounded,
                ),
                _SignalRow(
                  label: 'Steps',
                  value: '${s.steps}',
                  fraction: (s.steps / 8000).clamp(0.0, 1.0),
                  icon: Icons.directions_walk_rounded,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => state.refreshPhysiology(),
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Sync Apple Watch'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

class _ReadinessHeader extends StatelessWidget {
  final double readiness;
  final DateTime updated;
  final int baselineDays;
  final bool baselineReliable;

  const _ReadinessHeader({
    required this.readiness,
    required this.updated,
    required this.baselineDays,
    required this.baselineReliable,
  });

  String get _status {
    if (readiness >= 70) return 'Well Recovered';
    if (readiness >= 45) return 'Moderate';
    return 'Low Recovery';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.indigo.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('Physiological Readiness',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            width: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 160,
                  width: 160,
                  child: CircularProgressIndicator(
                    value: readiness / 100,
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor:
                        const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(readiness.toStringAsFixed(0),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.bold,
                            height: 1)),
                    const Text('READY',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 2)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(_status,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          const SizedBox(height: 14),
          Text(
            'Updated ${DateFormat.Hm().format(updated)} • Apple Watch / HealthKit',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            baselineReliable
                ? 'Personalised to your $baselineDays-day baseline'
                : 'Building your baseline · $baselineDays/3 days',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }
}

/// Focus Lock toggle (report §2.4.5 — JITAI): mutes non-critical alerts so
/// deep-focus work isn't interrupted; only a dangerous overload breaks through.
class _FocusLockCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _FocusLockCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: enabled ? AppTheme.indigo.withValues(alpha: 0.08) : AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: enabled ? AppTheme.indigo : AppTheme.line,
            width: enabled ? 1.4 : 1),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: enabled,
        activeThumbColor: Colors.white,
        activeTrackColor: AppTheme.indigo,
        onChanged: onChanged,
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (enabled ? AppTheme.indigo : AppTheme.inkFaint)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(enabled ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: enabled ? AppTheme.indigo : AppTheme.inkFaint),
        ),
        title: const Text('Focus Lock',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink)),
        subtitle: Text(
          enabled
              ? 'On · only overload alerts break through'
              : 'Off · all workload alerts active',
          style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
        ),
      ),
    );
  }
}

/// 14-day physiological readiness trend (report — visualise invisible strain).
class _TrendChart extends StatelessWidget {
  final List<MapEntry<DateTime, double>> trend;
  const _TrendChart({required this.trend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Readiness Trend',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.ink)),
          const Text('Last 14 days',
              style: TextStyle(fontSize: 12, color: AppTheme.inkFaint)),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: trend.length < 2
                ? const Center(
                    child: Text(
                        'Sync a few days to build your trend',
                        style: TextStyle(
                            color: AppTheme.inkFaint, fontSize: 13)),
                  )
                : LineChart(_chartData()),
          ),
        ],
      ),
    );
  }

  LineChartData _chartData() {
    final spots = <FlSpot>[
      for (var i = 0; i < trend.length; i++)
        FlSpot(i.toDouble(), trend[i].value),
    ];
    return LineChartData(
      minY: 0,
      maxY: 100,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: AppTheme.surfaceAlt, strokeWidth: 1),
      ),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            reservedSize: 28,
            getTitlesWidget: (v, _) => Text('${v.toInt()}',
                style: const TextStyle(
                    color: AppTheme.inkFaint, fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (trend.length / 4).ceilToDouble().clamp(1, 999),
            reservedSize: 22,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= trend.length) return const SizedBox.shrink();
              return Text(DateFormat.Md().format(trend[i].key),
                  style: const TextStyle(
                      color: AppTheme.inkFaint, fontSize: 10));
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 3,
          color: AppTheme.indigo,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: AppTheme.violet,
                strokeWidth: 0,
                strokeColor: AppTheme.violet),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.indigo.withValues(alpha: 0.25),
                AppTheme.indigo.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  final String label, value;
  final double fraction;
  final IconData icon;
  const _SignalRow(
      {required this.label,
      required this.value,
      required this.fraction,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    final color =
        Color.lerp(AppTheme.danger, AppTheme.success, fraction)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: AppTheme.ink)),
              const Spacer(),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppTheme.ink)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppTheme.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}
