import 'package:cloud_firestore/cloud_firestore.dart';

class TaskModel {
  final String? id;
  final String name;
  final DateTime date;
  final String startTime;
  final String endTime;
  final int cognitiveLoadScore;
  final String ratingType;

  TaskModel({
    this.id,
    required this.name,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.cognitiveLoadScore,
    required this.ratingType,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'cognitiveLoadScore': cognitiveLoadScore,
      'ratingType': ratingType,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory TaskModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    return TaskModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      date: _parseDate(data['date']),
      startTime: data['startTime'] as String? ?? '09:00',
      endTime: data['endTime'] as String? ?? '10:00',
      cognitiveLoadScore: (data['cognitiveLoadScore'] as num?)?.toInt() ?? 50,
      ratingType: data['ratingType'] as String? ?? 'Automatic',
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}
