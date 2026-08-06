import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';

/// Outcome of a manual task submission.
enum SubmitResult { success, duplicate, invalid, error }

class AddTaskViewModel extends ChangeNotifier {
  final TaskService _taskService = TaskService();

  // 表单响应状态
  String? _editingTaskId;
  String _taskName = '';
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  int _cognitiveLoadScore = 50; // 默认基准分
  String _ratingType = 'Automatic';
  bool _isSaving = false;

  // Getters
  String? get editingTaskId => _editingTaskId;
  String get taskName => _taskName;
  int get cognitiveLoadScore => _cognitiveLoadScore;
  String get ratingType => _ratingType;
  bool get isSaving => _isSaving;
  DateTime? get selectedDate => _selectedDate;
  TimeOfDay? get startTime => _startTime;
  TimeOfDay? get endTime => _endTime;

  // 🟢 加载已有任务进入编辑模式
  void loadTask(TaskModel task) {
    _editingTaskId = task.id;
    _taskName = task.name;
    _selectedDate = task.date;
    
    // 解析时间字符串 (HH:mm)
    final startParts = task.startTime.split(':');
    if (startParts.length == 2) {
      _startTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
    }
    
    final endParts = task.endTime.split(':');
    if (endParts.length == 2) {
      _endTime = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));
    }

    _cognitiveLoadScore = task.cognitiveLoadScore;
    _ratingType = task.ratingType;
    notifyListeners();
  }

  // 🟢 核心统一：全系统最高指挥官级别的关键字 NLP 测算分值字典
  void updateTaskName(String name) {
    _taskName = name;
    
    // 如果是手动评分模式，不再自动更新分数
    if (_ratingType.contains('Manual')) {
      notifyListeners();
      return;
    }

    _cognitiveLoadScore = IntensityClassifier.scoreFromTitle(name);
    notifyListeners();
  }

  void setDate(DateTime date) { _selectedDate = date; notifyListeners(); }
  void setStartTime(TimeOfDay time) { _startTime = time; notifyListeners(); }
  void setEndTime(TimeOfDay time) { _endTime = time; notifyListeners(); }

  void setManualScore(int score) {
    _cognitiveLoadScore = score;
    _ratingType = 'Manual (NASA-TLX)';
    notifyListeners();
  }

  // 表单验证并提交到 Firebase
  Future<SubmitResult> submitTask() async {
    if (_taskName.isEmpty || _selectedDate == null || _startTime == null || _endTime == null) {
      return SubmitResult.invalid;
    }

    _isSaving = true;
    notifyListeners();

    try {
      final String startStr = "${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}";
      final String endStr = "${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}";

      // 🟢 查重：同名 + 同日期 + 同开始时间 = 完全相同的任务，拒绝重复添加。
      // 只在“新增”时检查（编辑现有任务时跳过）。查询失败（如离线）则放行。
      if (_editingTaskId == null) {
        try {
          final existing = await _taskService.getCurrentUserTasks();
          final bool isDuplicate = existing.any((t) =>
              t.name.trim().toLowerCase() == _taskName.trim().toLowerCase() &&
              t.date.year == _selectedDate!.year &&
              t.date.month == _selectedDate!.month &&
              t.date.day == _selectedDate!.day &&
              t.startTime == startStr);
          if (isDuplicate) return SubmitResult.duplicate;
        } catch (e) {
          debugPrint("Duplicate check skipped (fetch failed): $e");
        }
      }

      final taskData = TaskModel(
        id: _editingTaskId,
        name: _taskName,
        date: _selectedDate!,
        startTime: startStr,
        endTime: endStr,
        cognitiveLoadScore: _cognitiveLoadScore,
        ratingType: _ratingType,
      );

      if (_editingTaskId != null) {
        await _taskService.updateTask(taskData);
      } else {
        await _taskService.saveTask(taskData);
      }

      _resetForm();
      return SubmitResult.success;
    } catch (e) {
      debugPrint("Failed to save task: $e");
      return SubmitResult.error;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void _resetForm() {
    _editingTaskId = null;
    _taskName = '';
    _selectedDate = null;
    _startTime = null;
    _endTime = null;
    _cognitiveLoadScore = 50;
    _ratingType = 'Automatic';
    notifyListeners();
  }
}
