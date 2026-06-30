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

  /// Live stream of the signed-in user's tasks (newest first). Drives the
  /// cognitive-load engine in real time so the dashboard reacts instantly.
  Stream<List<TaskModel>> streamUserTasks() {
    final User? user = _auth.currentUser;
    if (user == null) return Stream.value(const []);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(TaskModel.fromDoc).toList());
  }

  /// Delete a single task by document id.
  Future<void> deleteTask(String taskId) async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .doc(taskId)
        .delete();
  }

  /// Delete every task for the signed-in user (wires the Settings "Clear All
  /// Tasks" button to real data).
  Future<void> clearAllTasks() async {
    final User? user = _auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final tasks = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tasks')
        .get();

    final batch = _firestore.batch();
    for (final doc in tasks.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}