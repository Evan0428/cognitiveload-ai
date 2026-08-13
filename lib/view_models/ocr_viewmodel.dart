import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/extracted_task_model.dart';
import '../models/models.dart'; // 🟢 引入 ScheduleEvent 模型
import '../services/ocr_service.dart';
import '../services/app_state.dart'; // 🟢 引入全局状态，用来联动主页分数

class OcrViewModel extends ChangeNotifier {
  final OcrService _ocrService = OcrService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isProcessing = false;
  List<ExtractedTaskModel> _extractedTasks = [];

  bool get isProcessing => _isProcessing;
  List<ExtractedTaskModel> get extractedTasks => _extractedTasks;

  /// 🟢 拍照 (保持不变，因为相机只产生图片)
  Future<bool> capturePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (photo == null) return false;
    return await _processFile(File(photo.path));
  }

  /// 🟢 从相册上传 (仅限图片)
  Future<bool> uploadFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (image == null) return false;
    return await _processFile(File(image.path));
  }

  /// 🟢 上传 PDF 文件
  Future<bool> uploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    
    if (result == null || result.files.single.path == null) return false;
    return await _processFile(File(result.files.single.path!));
  }

  /// 🟢 核心桥接修改：处理不同格式的文件
  Future<bool> _processFile(File file) async {
    _isProcessing = true;
    _extractedTasks.clear(); // 每次扫描前先清空旧数据
    notifyListeners();

    try {
      _extractedTasks = await _ocrService.recognizeAndStructureFile(file);
      _isProcessing = false;
      notifyListeners();
      return _extractedTasks.isNotEmpty;
    } catch (e) {
      debugPrint("OCR ViewModel Error: $e");
      _isProcessing = false;
      notifyListeners();
      return false;
    }
  }

  /// 🟢 核心新增：允许用户在卡片输入框里修改文字，并动态重算每一项的 NASA-TLX 认知载荷分
  void updateSubjectAt(int index, String newSubject) {
    if (index >= 0 && index < _extractedTasks.length) {
      _extractedTasks[index].subject = newSubject;
      // 随着用户实时打字修改，重新通过矩阵匹配最新权重分！
      _extractedTasks[index].cognitiveLoadScore = _ocrService.classifyIntensityToScore(newSubject);
      notifyListeners();
    }
  }

  void removeTaskAt(int index) {
    _extractedTasks.removeAt(index);
    notifyListeners();
  }

  /// True when two time intervals intersect (start < otherEnd && end > otherStart).
  /// Used to reject an OCR task that overlaps an already-scheduled commitment.
  bool _overlaps(DateTime aStart, DateTime aEnd, DateTime bStart, DateTime bEnd) {
    return aStart.isBefore(bEnd) && aEnd.isAfter(bStart);
  }

  /// 🟢 终极双流合并保存：云端备份 + 同步刷新本地 AppState 联动主页大圆圈
  /// 现在带查重：已存在（或本批次重复）的任务会被跳过并回报给用户。
  Future<TaskSaveResult> saveAllTasksToFirebase(AppState globalState) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_extractedTasks.isEmpty) {
      return const TaskSaveResult(success: false, savedCount: 0, conflicts: []);
    }

    // Time intervals already occupied — existing schedule + tasks accepted so
    // far in THIS import (so two overlapping OCR rows don't both get in).
    final List<List<DateTime>> occupied = [
      for (final e in globalState.events) [e.start, e.end]
    ];

    try {
      final batch = FirebaseFirestore.instance.batch();
      int index = 0;
      int savedCount = 0;
      final List<String> conflicts = [];

      for (var task in _extractedTasks) {
        // --- 1. Date Parsing (Standardize to DateTime) ---
        DateTime taskDate = DateTime.now();
        try {
          final parts = task.date.split('/');
          if (parts.length == 3) {
            taskDate = DateTime(
              int.parse(parts[2]), // Year
              int.parse(parts[1]), // Month
              int.parse(parts[0]), // Day
            );
          }
        } catch (e) {
          debugPrint("Date parse error for ${task.date}: $e");
        }

        // --- 2. Time Parsing (Robustly handle OCR formats) ---
        int startHour = 9, startMin = 0;
        int endHour = 10, endMin = 30;

        final startMatch = RegExp(r'(\d{1,2})[:.](\d{2})\s*(am|pm)?', caseSensitive: false)
            .firstMatch(task.startTime.toLowerCase());
        if (startMatch != null) {
          startHour = int.parse(startMatch.group(1)!);
          startMin = int.parse(startMatch.group(2)!);
          final p = startMatch.group(3);
          if (p == 'pm' && startHour < 12) startHour += 12;
          if (p == 'am' && startHour == 12) startHour = 0;
        }

        final endMatch = RegExp(r'(\d{1,2})[:.](\d{2})\s*(am|pm)?', caseSensitive: false)
            .firstMatch(task.endTime.toLowerCase());
        if (endMatch != null) {
          endHour = int.parse(endMatch.group(1)!);
          endMin = int.parse(endMatch.group(2)!);
          final p = endMatch.group(3);
          if (p == 'pm' && endHour < 12) endHour += 12;
          if (p == 'am' && endHour == 12) endHour = 0;
        }

        // --- 2b. Time-overlap check (FR 3.1) — skip if this slot clashes ---
        final DateTime newStart =
            DateTime(taskDate.year, taskDate.month, taskDate.day, startHour, startMin);
        final DateTime newEnd =
            DateTime(taskDate.year, taskDate.month, taskDate.day, endHour, endMin);

        // 🟢 结束时间必须晚于开始时间，否则跳过并列入报告
        if (!newEnd.isAfter(newStart)) {
          conflicts.add('${task.subject} — ${task.day} ${task.date} (end time before start time)');
          continue;
        }

        final bool clashes = occupied.any((iv) => _overlaps(newStart, newEnd, iv[0], iv[1]));
        if (clashes) {
          conflicts.add('${task.subject} — ${task.day} ${task.date} ${task.startTime} (time conflict)');
          continue; // skip: this time slot is already occupied
        }
        occupied.add([newStart, newEnd]); // reserve the slot for the rest of the batch

        // --- 3. Normalization (HH:mm format for Firestore consistency) ---
        final String firestoreStart = "${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}";
        final String firestoreEnd = "${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}";

        // --- 4. Firestore Save ---
        if (uid != null) {
          DocumentReference docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc();

          batch.set(docRef, {
            'name': task.subject,
            'date': Timestamp.fromDate(taskDate),
            'startTime': firestoreStart,
            'endTime': firestoreEnd,
            'cognitiveLoadScore': task.cognitiveLoadScore,
            'ratingType': 'Automatic (OCR)',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // --- 5. Local State Sync (AppState) ---
        TaskIntensity mappedIntensity = TaskIntensityX.fromScore(task.cognitiveLoadScore);

        globalState.addEvent(ScheduleEvent(
          id: 'ocr_${taskDate.millisecondsSinceEpoch}_${task.subject.hashCode}_$index',
          title: task.subject,
          start: newStart,
          end: newEnd,
          intensity: mappedIntensity,
          source: 'ocr',
          cognitiveLoadScore: task.cognitiveLoadScore,
          ratingType: 'Automatic (OCR)',
        ));
        index++;
        savedCount++;
      }

      if (uid != null && savedCount > 0) await batch.commit();
      _extractedTasks.clear();
      notifyListeners();
      return TaskSaveResult(
        success: true,
        savedCount: savedCount,
        conflicts: conflicts,
      );
    } catch (e) {
      debugPrint("Batch save & sync error: $e");
      return const TaskSaveResult(success: false, savedCount: 0, conflicts: []);
    }
  }
}

/// Outcome of a save: how many new tasks were stored and which were skipped
/// because their time slot overlapped an existing (or already-accepted) task.
class TaskSaveResult {
  final bool success;
  final int savedCount;
  final List<String> conflicts;

  const TaskSaveResult({
    required this.success,
    required this.savedCount,
    required this.conflicts,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}
