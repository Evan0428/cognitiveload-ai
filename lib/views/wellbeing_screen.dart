import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';

class WellbeingScreen extends StatelessWidget {
  const WellbeingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.snapshot;
    final r = state.result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wellbeing',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Physiological Readiness',
                            style: TextStyle(
                                fontSize: 14, color: Colors.black54)),
                        const SizedBox(height: 16),
                        Text(
                          '${r?.readinessScore.toStringAsFixed(0) ?? '--'}%',
                          style: const TextStyle(
                              fontSize: 56, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Updated ${DateFormat.Hm().format(s.timestamp)} • from Apple Watch / HealthKit',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black38),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SignalRow(
                    label: 'Heart Rate',
                    value: '${s.heartRate.toStringAsFixed(0)} bpm',
                    fraction: ((100 - s.heartRate) / 40).clamp(0.0, 1.0),
                    icon: Icons.monitor_heart),
                _SignalRow(
                    label: 'Heart Rate Variability',
                    value: '${s.hrv.toStringAsFixed(0)} ms',
                    fraction: (s.hrv / 80).clamp(0.0, 1.0),
                    icon: Icons.show_chart),
                _SignalRow(
                    label: 'Sleep Duration',
                    value: '${s.sleepHours.toStringAsFixed(1)} h',
                    fraction: (s.sleepHours / 8).clamp(0.0, 1.0),
                    icon: Icons.bedtime),
                _SignalRow(
                    label: 'Steps',
                    value: '${s.steps}',
                    fraction: (s.steps / 8000).clamp(0.0, 1.0),
                    icon: Icons.directions_walk),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => state.refreshPhysiology(),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync Apple Watch'),
                  ),
                ),
              ],
            ),
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
    final color = Color.lerp(
        const Color(0xFFF44336), const Color(0xFF4CAF50), fraction)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
