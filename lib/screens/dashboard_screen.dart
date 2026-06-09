import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/cognitive_load_engine.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Color _levelColor(LoadLevel level) => switch (level) {
        LoadLevel.safe => const Color(0xFF4CAF50),
        LoadLevel.elevated => const Color(0xFF2196F3),
        LoadLevel.high => const Color(0xFFFF9800),
        LoadLevel.overload => const Color(0xFFF44336),
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CognitiveLoad AI',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh biometrics',
            onPressed: () => state.refreshPhysiology(),
          ),
        ],
      ),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CombinedGauge(result: r, color: _levelColor(r.level)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ScoreCard(
                        title: 'Workload',
                        subtitle: 'Schedule density',
                        value: r.workloadScore.toStringAsFixed(1),
                        icon: Icons.event_note,
                        color: const Color(0xFF5B5BD6),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ScoreCard(
                        title: 'Readiness',
                        subtitle: 'Physiological',
                        value: '${r.readinessScore.toStringAsFixed(0)}%',
                        icon: Icons.favorite,
                        color: const Color(0xFFE91E63),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _AlertsCard(alerts: r.alerts, color: _levelColor(r.level)),
                const SizedBox(height: 16),
                _BiometricsCard(state: state),
              ],
            ),
    );
  }
}

class _CombinedGauge extends StatelessWidget {
  final CognitiveLoadResult result;
  final Color color;
  const _CombinedGauge({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Combined Cognitive Load',
                style: TextStyle(fontSize: 14, color: Colors.black54)),
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
                      value: result.combinedLoad / 100,
                      strokeWidth: 14,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(result.combinedLoad.toStringAsFixed(0),
                          style: const TextStyle(
                              fontSize: 42, fontWeight: FontWeight.bold)),
                      Text(result.level.label,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String title, subtitle, value;
  final IconData icon;
  final Color color;
  const _ScoreCard(
      {required this.title,
      required this.subtitle,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold)),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  final List<String> alerts;
  final Color color;
  const _AlertsCard({required this.alerts, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.notifications_active, color: color),
              const SizedBox(width: 8),
              const Text('Alerts & Recommendations',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 12),
            ...alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle, size: 8, color: color),
                      const SizedBox(width: 10),
                      Expanded(child: Text(a)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _BiometricsCard extends StatelessWidget {
  final AppState state;
  const _BiometricsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state.snapshot;
    if (s == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Latest Biometrics (HealthKit)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _metric('Heart Rate', '${s.heartRate.toStringAsFixed(0)} bpm'),
                _metric('HRV', '${s.hrv.toStringAsFixed(0)} ms'),
                _metric('Sleep', '${s.sleepHours.toStringAsFixed(1)} h'),
                _metric('Steps', '${s.steps}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ],
      );
}
