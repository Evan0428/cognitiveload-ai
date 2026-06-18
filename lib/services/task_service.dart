import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task_model.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 将任务安全地存入：users -> {uid} -> tasks -> {task_id}
  Future<void> saveTask(TaskModel task) async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .add(task.toMap());
  }
}