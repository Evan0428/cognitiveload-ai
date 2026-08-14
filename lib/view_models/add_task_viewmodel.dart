import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../services/task_weight_learner.dart';

/// Outcome of a manual task submission.
/// `conflict`    = the chosen time slot overlaps an existing task.
/// `invalidTime` = end time is not after start time.
enum SubmitResult { success, conflict, invalidTime, invalid, error }

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

    // 🧠 Personalised score: uses the weights learned from this user's own
    // manual NASA-TLX ratings, falling back to the shared keyword model.
    _cognitiveLoadScore = TaskWeightLearner.instance.scoreFor(name);
    notifyListeners();
  }

  /// Why the current score was given (explainable AI, shown under the score).
  String get scoreExplanation =>
      TaskWeightLearner.instance.explain(_taskName);

  void setDate(DateTime date) { _selectedDate = date; notifyListeners(); }
  void setStartTime(TimeOfDay time) { _startTime = time; notifyListeners(); }
  void setEndTime(TimeOfDay time) { _endTime = time; notifyListeners(); }

  void setManualScore(int score) {
    _cognitiveLoadScore = score;
    _ratingType = 'Manual (NASA-TLX)';
    // 🧠 Every manual rating is a labelled training example: this title was
    // really worth this load. Teach the personal model so future tasks with
    // the same words are scored the way THIS user experiences them.
    TaskWeightLearner.instance.learn(_taskName, score);
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

      // 🟢 结束时间必须晚于开始时间（新增和编辑都检查）。否则添加/保存失败。
      final int startMins = _startTime!.hour * 60 + _startTime!.minute;
      final int endMins = _endTime!.hour * 60 + _endTime!.minute;
      if (endMins <= startMins) return SubmitResult.invalidTime;

      // 🟢 时段重叠拦截 (FR 3.1)：同一天里，只要新任务的时间区间和已有任务相交
      // （新开始 < 旧结束 且 新结束 > 旧开始）就拒绝——不看名字，同一时段不能再放任务。
      // 只在“新增”时检查（编辑现有任务时跳过）；查询失败（如离线）则放行。
      if (_editingTaskId == null) {
        try {
          final existing = await _taskService.getCurrentUserTasks();
          final int newStart = _startTime!.hour * 60 + _startTime!.minute;
          final int newEnd = _endTime!.hour * 60 + _endTime!.minute;
          final bool hasConflict = existing.any((t) {
            if (t.date.year != _selectedDate!.year ||
                t.date.month != _selectedDate!.month ||
                t.date.day != _selectedDate!.day) {
              return false; // different day → no conflict
            }
            final int s = _minutesOf(t.startTime);
            final int e = _minutesOf(t.endTime);
            return newStart < e && newEnd > s; // interval intersection
          });
          if (hasConflict) return SubmitResult.conflict;
        } catch (e) {
          debugPrint("Conflict check skipped (fetch failed): $e");
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

  /// Parses a stored "HH:mm" time string into minutes-of-day.
  int _minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
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
