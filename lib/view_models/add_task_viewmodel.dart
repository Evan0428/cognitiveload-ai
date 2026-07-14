import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';

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

    String lowerName = name.toLowerCase();

    if (lowerName.contains('exam')) {
      _cognitiveLoadScore = 95;
    } else if (lowerName.contains('test')) {
      _cognitiveLoadScore = 80;
    } else if (lowerName.contains('quiz')) {
      _cognitiveLoadScore = 75;
    } else if (lowerName.contains('lab')) {
      _cognitiveLoadScore = 65;
    } else if (lowerName.contains('presentation') || lowerName.contains('assignment')) {
      _cognitiveLoadScore = 60;
    } else if (lowerName.contains('lecture') || lowerName.contains('study')) {
      _cognitiveLoadScore = 45;
    } else if (lowerName.contains('gym') || lowerName.contains('workout')) {
      _cognitiveLoadScore = 20;
    } else if (lowerName.contains('rest') || lowerName.contains('break')) {
      _cognitiveLoadScore = 15;
    } else {
      _cognitiveLoadScore = 50;
    }

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
  Future<bool> submitTask() async {
    if (_taskName.isEmpty || _selectedDate == null || _startTime == null || _endTime == null) {
      return false;
    }

    _isSaving = true;
    notifyListeners();

    try {
      final String startStr = "${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}";
      final String endStr = "${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}";

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
      return true;
    } catch (e) {
      debugPrint("Failed to save task: $e");
      return false;
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
