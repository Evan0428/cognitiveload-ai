import 'package:flutter/material.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';

class AddTaskViewModel extends ChangeNotifier {
  final TaskService _taskService = TaskService();

  // 表单响应状态
  String _taskName = '';
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  int _cognitiveLoadScore = 50; // 默认基准分
  String _ratingType = 'Automatic';
  bool _isSaving = false;

  // Getters
  int get cognitiveLoadScore => _cognitiveLoadScore;
  String get ratingType => _ratingType;
  bool get isSaving => _isSaving;
  DateTime? get selectedDate => _selectedDate;
  TimeOfDay? get startTime => _startTime;
  TimeOfDay? get endTime => _endTime;

  // 🟢 真实业务功能 1：基于 Task Name 关键字自动实时测算认知负载得分 (NLP 算法核心占位)
  void updateTaskName(String name) {
    _taskName = name;
    String lowerName = name.toLowerCase();

    // 根据你图里的 MPU test 算出了高分 80，我们这里做真实的关键词匹配功能：
    if (lowerName.contains('test') || lowerName.contains('exam') || lowerName.contains('quiz')) {
      _cognitiveLoadScore = 50;
    } else if (lowerName.contains('presentation') || lowerName.contains('assignment')) {
      _cognitiveLoadScore = 30;
    } else if (lowerName.contains('lecture') || lowerName.contains('study')) {
      _cognitiveLoadScore = 20;
    } else if (lowerName.contains('rest') || lowerName.contains('break')) {
      _cognitiveLoadScore = 15;
    } else {
      _cognitiveLoadScore = 50; // 无法识别的默认中等负载
    }
    notifyListeners();
  }

  void setDate(DateTime date) { _selectedDate = date; notifyListeners(); }
  void setStartTime(TimeOfDay time) { _startTime = time; notifyListeners(); }
  void setEndTime(TimeOfDay time) { _endTime = time; notifyListeners(); }

  // 功能 2：未来留给 NASA-TLX 弹窗手动微调分数的接口
  void setManualScore(int score) {
    _cognitiveLoadScore = score;
    _ratingType = 'Manual (NASA-TLX)';
    notifyListeners();
  }

  // 🟢 真实业务功能 3：表单验证并提交到 Firebase
  Future<bool> submitTask() async {
    if (_taskName.isEmpty || _selectedDate == null || _startTime == null || _endTime == null) {
      return false;
    }

    _isSaving = true;
    notifyListeners();

    try {
      // 格式化时间段展示字符串
      final String startStr = "${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')} ${_startTime!.period == DayPeriod.am ? 'AM' : 'PM'}";
      final String endStr = "${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')} ${_endTime!.period == DayPeriod.am ? 'AM' : 'PM'}";

      final newTask = TaskModel(
        name: _taskName,
        date: _selectedDate!,
        startTime: startStr,
        endTime: endStr,
        cognitiveLoadScore: _cognitiveLoadScore,
        ratingType: _ratingType,
      );

      await _taskService.saveTask(newTask);
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
    _taskName = '';
    _selectedDate = null;
    _startTime = null;
    _endTime = null;
    _cognitiveLoadScore = 50;
    _ratingType = 'Automatic';
  }
}