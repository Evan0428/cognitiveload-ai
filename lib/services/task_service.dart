import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/task_model.dart';

class TaskService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _currentUserTasksRef() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    return _firestore.collection('users').doc(user.uid).collection('tasks');
  }

  Future<String> saveTask(TaskModel task) async {
    final docRef = await _currentUserTasksRef().add(task.toMap());
    return docRef.id;
  }

  Future<void> updateTask(TaskModel task) async {
    if (task.id == null) return;
    await _currentUserTasksRef().doc(task.id).update(task.toMap());
  }

  Future<void> deleteTask(String taskId) async {
    await _currentUserTasksRef().doc(taskId).delete();
  }

  Future<List<TaskModel>> getCurrentUserTasks() async {
    final snapshot = await _currentUserTasksRef()
        .orderBy('createdAt', descending: false)
        .get();

    return snapshot.docs.map(TaskModel.fromDoc).toList();
  }

  /// Deletes every task belonging to the currently signed-in user.
  /// Firestore batches are limited to 500 writes, so large task lists are
  /// deleted in multiple batches.
  Future<int> deleteAllCurrentUserTasks() async {
    final tasksRef = _currentUserTasksRef();
    final snapshot = await tasksRef.get();

    for (var start = 0; start < snapshot.docs.length; start += 500) {
      final batch = _firestore.batch();
      final end = (start + 500).clamp(0, snapshot.docs.length);
      for (final task in snapshot.docs.sublist(start, end)) {
        batch.delete(task.reference);
      }
      await batch.commit();
    }

    return snapshot.docs.length;
  }
}
