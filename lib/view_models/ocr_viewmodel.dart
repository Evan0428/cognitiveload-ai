import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  /// 🟢 拍照
  Future<bool> capturePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (photo == null) return false;
    return await _processImageFile(File(photo.path));
  }

  /// 🟢 从相册上传
  Future<bool> uploadFromGallery() async {
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (image == null) return false;
    return await _processImageFile(File(image.path));
  }

  /// 🟢 核心桥接修改：调用融合版新服务函数
  Future<bool> _processImageFile(File file) async {
    _isProcessing = true;
    _extractedTasks.clear(); // 每次扫描前先清空旧数据
    notifyListeners();

    try {
      _extractedTasks = await _ocrService.recognizeAndStructureImage(file);
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
      _extractedTasks[index].cognitiveLoadScore = OcrService.classifyIntensityToScore(newSubject);
      notifyListeners();
    }
  }

  void removeTaskAt(int index) {
    _extractedTasks.removeAt(index);
    notifyListeners();
  }

  /// 🟢 终极双流合并保存：云端备份 + 同步刷新本地 AppState 联动主页大圆圈
  Future<bool> saveAllTasksToFirebase(AppState globalState) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_extractedTasks.isEmpty) return false;

    try {
      final batch = FirebaseFirestore.instance.batch();
      DateTime now = DateTime.now();

      for (var task in _extractedTasks) {
        // --- 1. 同步推送至云端 Firestore ---
        if (uid != null) {
          DocumentReference docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('tasks')
              .doc();

          batch.set(docRef, {
            'name': task.subject,
            'date': Timestamp.fromDate(now),
            'startTime': task.startTime,
            'endTime': task.endTime,
            'cognitiveLoadScore': task.cognitiveLoadScore,
            'ratingType': 'Automatic (OCR)',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // --- 2. 完美联动：同步注入本地核心数据流，立即刷新 Dashboard 总分数 (FR 2.4) ---
        // 解析小时和分钟
        int startHour = 9;
        int startMin = 0;
        if (task.startTime.contains(':')) {
          var parts = task.startTime.replaceAll(RegExp(r'[a-zA-Z\s]'), '').split(':');
          startHour = int.tryParse(parts[0]) ?? 9;
          startMin = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        }

        // 映射认知负荷分数到原本的旧架构枚举，确保分析引擎不出错
        TaskIntensity mappedIntensity = TaskIntensity.medium;
        if (task.cognitiveLoadScore >= 80) {
          mappedIntensity = TaskIntensity.critical;
        } else if (task.cognitiveLoadScore >= 70) {
          mappedIntensity = TaskIntensity.high;
        } else if (task.cognitiveLoadScore <= 20) {
          mappedIntensity = TaskIntensity.low;
        }

        // 呼叫全局 AppState 的机制，直接注入并重算总分！
        globalState.addEvent(ScheduleEvent(
          id: 'ocr_${DateTime.now().microsecondsSinceEpoch}_${task.subject.hashCode}',
          title: task.subject,
          start: DateTime(now.year, now.month, now.day, startHour, startMin),
          end: DateTime(now.year, now.month, now.day, startHour + 1, startMin + 30),
          intensity: mappedIntensity,
          source: 'ocr',
        ));
      }

      // 提交云端 Batch 异步事务
      if (uid != null) {
        await batch.commit();
      }

      // 清空当前处理队列，防止重复提交
      _extractedTasks.clear();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Batch save & sync error: $e");
      return false;
    }
  }
}