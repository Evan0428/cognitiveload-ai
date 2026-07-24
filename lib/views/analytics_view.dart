import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final now = DateTime.now();

    // 1. 🟢 Calculate Weekly Data (Last 7 Days)
    final last7Days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final weeklyScores = last7Days.map((date) {
      final dayEvents = state.events.where((e) =>
          e.start.year == date.year &&
          e.start.month == date.month &&
          e.start.day == date.day).toList();

      double dayLoad = 0;
      for (var e in dayEvents) {
        final durationHours = e.end.difference(e.start).inMinutes / 60.0;
        dayLoad += e.cognitiveLoadScore * durationHours;
      }
      return dayLoad;
    }).toList();

    // 2. 🟢 Calculate Hourly Data for Heatmap (Today)
    final hourlyLoad = List.generate(24, (hour) {
      final hourEvents = state.events.where((e) =>
          e.start.year == now.year &&
          e.start.month == now.month &&
          e.start.day == now.day &&
          e.start.hour <= hour &&
          e.end.hour > hour).toList();

      if (hourEvents.isEmpty) return 0.0;
      return hourEvents.map((e) => e.cognitiveLoadScore.toDouble()).reduce((a, b) => a + b) / hourEvents.length;
    });

    // 3. 🟢 Summary Stats
    double avgWeeklyLoad = weeklyScores.reduce((a, b) => a + b) / 7;

    int peakHour = -1;
    double maxHourLoad = -1;
    for (int h = 0; h < 24; h++) {
      if (hourlyLoad[h] > maxHourLoad) {
        maxHourLoad = hourlyLoad[h];
        peakHour = h;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Analytics',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B))),
              const SizedBox(height: 24),

              // 📈 Card 1: Weekly Load Comparison
              _buildCard(
                title: 'Weekly Load Comparison',
                subtitle: 'Track your cognitive load trends over the past 7 days',
                child: Column(
                  children: [
                    SizedBox(
                      height: 220,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: 120,
                          barGroups: List.generate(
                              7,
                              (i) => BarChartGroupData(
                                    x: i,
                                    barRods: [
                                      BarChartRodData(
                                        toY: weeklyScores[i] > 120 ? 120 : weeklyScores[i],
                                        color: _getBarColor(weeklyScores[i]),
                                        width: 18,
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(6),
                                            topRight: Radius.circular(6)),
                                        backDrawRodData: BackgroundBarChartRodData(
                                            show: true,
                                            toY: 120,
                                            color: const Color(0xFFF1F5F9)),
                                      )
                                    ],
                                  )),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (val, _) => Text(val.toInt().toString(),
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFF94A3B8))),
                                reservedSize: 28,
                              ),
                              axisNameWidget: const Text('Load Score',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w500)),
                              axisNameSize: 24,
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (i, _) => Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(DateFormat('E').format(last7Days[i.toInt()]),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval: 30,
                              getDrawingHorizontalLine: (v) => FlLine(
                                  color: Colors.grey.withOpacity(0.1),
                                  strokeWidth: 1,
                                  dashArray: [5, 5])),
                          borderData: FlBorderData(show: false),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegendItem('Low', const Color(0xFF00C853)),
                        const SizedBox(width: 16),
                        _buildLegendItem('Moderate', const Color(0xFFFFB300)),
                        const SizedBox(width: 16),
                        _buildLegendItem('High', const Color(0xFFF44336)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 🔥 Card 2: Daily Heatmap
              _buildCard(
                title: 'Daily Heatmap',
                subtitle: 'Time blocks are shaded based on average task intensity',
                child: Column(
                  children: List.generate(8, (rowIndex) {
                    final startHour = rowIndex * 3;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${startHour.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          Row(
                            children: List.generate(3, (colIndex) {
                              final hour = startHour + colIndex;
                              return Expanded(
                                child: Container(
                                  height: 45,
                                  margin: EdgeInsets.only(
                                      right: colIndex == 2 ? 0 : 8),
                                  decoration: BoxDecoration(
                                    color: _getHeatmapColor(hourlyLoad[hour]),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24),

              // 📊 Stats Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      label: 'Peak Hours',
                      value: peakHour == -1
                          ? '--:--'
                          : '${peakHour.toString().padLeft(2, '0')}:00',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildStatTile(
                      label: 'Avg Weekly Load',
                      value: avgWeeklyLoad.toStringAsFixed(0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 🤖 AI Insights
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF0F4FF), Color(0xFFF9F0FF)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Insights',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B))),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6.0),
                          child: Icon(Icons.circle, size: 6, color: Color(0xFF6366F1)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _getAIInsight(avgWeeklyLoad),
                            style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF475569),
                                height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B))),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
            width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildStatTile({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        ],
      ),
    );
  }

  Color _getBarColor(double score) {
    if (score < 40) return const Color(0xFF00C853);
    if (score < 85) return const Color(0xFFFFB300);
    return const Color(0xFFF44336);
  }

  Color _getHeatmapColor(double score) {
    if (score == 0) return const Color(0xFFF1F5F9);
    if (score < 30) return const Color(0xFFE8F5E9);
    if (score < 60) return const Color(0xFFFFF3E0);
    if (score < 85) return const Color(0xFFFFB300).withOpacity(0.8);
    return const Color(0xFFF44336).withOpacity(0.8);
  }

  String _getAIInsight(double avgLoad) {
    if (avgLoad == 0) return 'Add some tasks to see personalized insights about your mental workload.';
    if (avgLoad < 50) return 'Your average weekly load is below your threshold. You have excellent mental capacity this week!';
    if (avgLoad < 80) return 'Your workload is moderate. You are handling tasks well, but consider taking short breaks between intense sessions.';
    return 'Your weekly load is high. AI suggests scheduling more "Rest" blocks and practicing mindfulness to avoid potential burnout.';
  }
}
