import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart';

class TaskModel {
  final String? id;
  final String name;
  final DateTime date;
  final String startTime;
  final String endTime;
  final int cognitiveLoadScore;
  final String ratingType; // 'Automatic' 或 'Manual (NASA-TLX)'

  TaskModel({
    this.id,
    required this.name,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.cognitiveLoadScore,
    required this.ratingType,
  });

  // 转为 Firestore 所需的 Map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'date': Timestamp.fromDate(date), // Firestore 官方时间戳格式
      'startTime': startTime,
      'endTime': endTime,
      'cognitiveLoadScore': cognitiveLoadScore,
      'ratingType': ratingType,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  // 从 Firestore 读取时解析
  factory TaskModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskModel(
      id: doc.id,
      name: data['name'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      cognitiveLoadScore: data['cognitiveLoadScore'] ?? 0,
      ratingType: data['ratingType'] ?? 'Automatic',
    );
  }

  /// Bridge a Firestore task into the analytical engine's [ScheduleEvent] so
  /// manually-added tasks actually feed the dashboard cognitive-load gauge.
  /// Intensity comes from the stored 0-100 score (so manual NASA-TLX overrides
  /// are respected) and falls back to keyword classification.
  ScheduleEvent toScheduleEvent() {
    final start = _combine(date, startTime);
    var end = _combine(date, endTime);
    // Guard against an end time that parsed earlier than the start.
    if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));

    final intensity = cognitiveLoadScore > 0
        ? TaskIntensityX.fromScore(cognitiveLoadScore)
        : IntensityClassifier.fromTitle(name);

    return ScheduleEvent(
      id: id ?? 'task_${start.microsecondsSinceEpoch}',
      title: name,
      start: start,
      end: end,
      intensity: intensity,
      source: 'digital', // synced from Firestore (multi-source aggregation)
    );
  }

  /// Parse a stored time string ("09:05 AM" / "14:30" / "2:30 PM") onto [day].
  static DateTime _combine(DateTime day, String time) {
    final t = time.trim().toUpperCase();
    final isPm = t.contains('PM');
    final isAm = t.contains('AM');
    final digits = t.replaceAll(RegExp(r'[^0-9:]'), '');
    final parts = digits.split(':');
    int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;
    hour = hour.clamp(0, 23);

    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}