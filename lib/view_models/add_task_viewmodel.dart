import 'package:flutter/material.dart';
import '../models/models.dart';
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

  // 🟢 真实业务功能 1：基于 Task Name 关键字自动实时测算认知负载得分。
  // 统一调用共享的 NASA-TLX 关键词分类器，确保和 OCR 模块评分完全一致：
  //   exam/test/deadline -> 90 (Critical) ，assignment/lab/project -> 70 (High)，
  //   lecture/meeting -> 50 (Medium)，break/rest -> 20 (Low)。
  void updateTaskName(String name) {
    _taskName = name;
    _cognitiveLoadScore = IntensityClassifier.scoreFromTitle(name);
    _ratingType = 'Automatic';
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
      // 格式化时间段展示字符串（修正：之前用 24 小时制的 hour 拼接 AM/PM，会产生
      // 像 "14:30 PM" 这种错误格式。这里用 12 小时制的 hourOfPeriod 正确换算。）
      final String startStr = _format12h(_startTime!);
      final String endStr = _format12h(_endTime!);

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

  // 12 小时制格式化，例如 09:05 AM / 02:30 PM。
  String _format12h(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${h.toString().padLeft(2, '0')}:$m $period';
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