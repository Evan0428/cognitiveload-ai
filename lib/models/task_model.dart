import 'package:cloud_firestore/cloud_firestore.dart';

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
}