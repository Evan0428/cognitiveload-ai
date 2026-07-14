import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DigitalScheduleView extends StatefulWidget {
  const DigitalScheduleView({Key? key}) : super(key: key);

  @override
  State<DigitalScheduleView> createState() => _DigitalScheduleViewState();
}

class _DigitalScheduleViewState extends State<DigitalScheduleView> {
  final _formKey = GlobalKey<FormState>();

  // 表单输入暂存变量
  String _taskName = '';
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 30);

  // 🟢 核心算法：检测某个任务是否与当前现有的其他任务存在时间重叠 (FR 3.7)
  bool _checkIsOverlapping(ScheduleEvent currentEvent, List<ScheduleEvent> allEvents) {
    for (var e in allEvents) {
      if (e.id == currentEvent.id) continue; // 跳过自身比对（用于编辑时）

      // 判断两个时间区间是否有交集：StartA < EndB 并且 EndA > StartB
      if (currentEvent.start.isBefore(e.end) && currentEvent.end.isAfter(e.start)) {
        return true; // 存在冲突
      }
    }
    return false;
  }

  // 弹出添加/编辑弹窗 (FR 3.1 & FR 3.2)
  void _showTaskDialog({ScheduleEvent? existingEvent}) {
    if (existingEvent != null) {
      _taskName = existingEvent.title;
      _startTime = TimeOfDay(hour: existingEvent.start.hour, minute: existingEvent.start.minute);
      _endTime = TimeOfDay(hour: existingEvent.end.hour, minute: existingEvent.end.minute);
    } else {
      _taskName = '';
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 30);
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final appState = Provider.of<AppState>(context, listen: false);

            // 预先组装一个临时事件用来实时检测输入是否冲突
            final now = DateTime.now();
            final tempStart = DateTime(now.year, now.month, now.day, _startTime.hour, _startTime.minute);
            final tempEnd = DateTime(now.year, now.month, now.day, _endTime.hour, _endTime.minute);
            final tempEvent = ScheduleEvent(
              id: existingEvent?.id ?? 'temp',
              title: _taskName,
              start: tempStart,
              end: tempEnd,
              intensity: TaskIntensity.medium,
            );

            bool hasConflict = _checkIsOverlapping(tempEvent, appState.events);

            return AlertDialog(
              title: Text(existingEvent == null ? 'Add Manual Task' : 'Edit Task'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. 任务名称输入与非空校验 (FR 3.4)
                      TextFormField(
                        initialValue: _taskName,
                        decoration: const InputDecoration(
                          labelText: 'Task Name *',
                          hintText: 'e.g., Software Exam, Gym, Lecture',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Task name cannot be empty!'; // FR 3.4
                          }
                          return null;
                        },
                        onChanged: (value) {
                          setDialogState(() => _taskName = value);
                        },
                      ),
                      const SizedBox(height: 16),

                      // 2. 开始时间选择
                      ListTile(
                        title: Text("Start Time: ${_startTime.format(context)}"),
                        trailing: const Icon(Icons.access_time),
                        onTap: () async {
                          final time = await showTimePicker(context: context, initialTime: _startTime);
                          if (time != null) {
                            setDialogState(() => _startTime = time);
                          }
                        },
                      ),

                      // 3. 结束时间选择
                      ListTile(
                        title: Text("End Time: ${_endTime.format(context)}"),
                        trailing: const Icon(Icons.access_time),
                        onTap: () async {
                          final time = await showTimePicker(context: context, initialTime: _endTime);
                          if (time != null) {
                            setDialogState(() => _endTime = time);
                          }
                        },
                      ),

                      // 4. 冲突实时警告 UI (FR 3.7)
                      if (hasConflict)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.warning, color: Colors.red),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Time conflict detected with another task!",
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // 触发表单验证 (FR 3.4)
                    if (_formKey.currentState!.validate()) {
                      final now = DateTime.now();
                      final startDateTime = DateTime(now.year, now.month, now.day, _startTime.hour, _startTime.minute);
                      final endDateTime = DateTime(now.year, now.month, now.day, _endTime.hour, _endTime.minute);

                      // 时间合法性基本校验
                      if (endDateTime.isBefore(startDateTime)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("End time must be after start time!")),
                        );
                        return;
                      }

                      if (existingEvent == null) {
                        // 新增逻辑 (FR 3.1)：利用之前写好的智能关键字算分
                        // 动态获取分数（内部自动走 _getScoreByKeyword 逻辑）
                        final appState = Provider.of<AppState>(context, listen: false);

                        // 由于 AppState 里原生的 addEvent 接收标准 ScheduleEvent，
                        // 我们直接在创建事件时动态丢进去：
                        // 这里通过调用我们植入在 AppState 的映射方法来获取强度
                        // 如果在外面拿不到内部私有方法，我们可以直接在下面手动写个临时映射，或将其在AppState里暴露。
                        // 为了确保 100% 运行成功，我们在这里也配置一下映射：
                        final String lowerTitle = _taskName.toLowerCase();
                        TaskIntensity intensity = TaskIntensity.medium;
                        if (lowerTitle.contains('exam') || lowerTitle.contains('test')) {
                          intensity = TaskIntensity.critical;
                        } else if (lowerTitle.contains('gym') || lowerTitle.contains('workout')) {
                          intensity = TaskIntensity.low;
                        }

                        final newEvent = ScheduleEvent(
                          id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                          title: _taskName,
                          start: startDateTime,
                          end: endDateTime,
                          intensity: intensity,
                          source: 'manual',
                        );
                        appState.addEvent(newEvent);
                      } else {
                        // 编辑逻辑 (FR 3.2)
                        existingEvent.title = _taskName;
                        existingEvent.start = startDateTime;
                        existingEvent.end = endDateTime;
                        // 触发 AppState 刷新并存盘
                        Provider.of<AppState>(context, listen: false).updateIntensity(existingEvent.id, existingEvent.intensity);
                      }
                      Navigator.pop(context);
                    }
                  },
                  child: Text(existingEvent == null ? 'Save' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Consolidated Calendar & Schedule"),
      ),
      body: Consumer<AppState>(
        builder: (context, appState, child) {
          final allTasks = appState.events; // 🟢 FR 3.5 & FR 3.6 自动混合并按时间正序排列的列表

          if (allTasks.isEmpty) {
            return const Center(
              child: Text("No tasks for today. Scan a timetable or add manually!"),
            );
          }

          return Column(
            children: [
              // 简易顶部日历看板
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Commitments (${allTasks.length})",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.calendar_today, color: Colors.blue.shade700),
                  ],
                ),
              ),

              // 统一渲染的顺序列表 (FR 3.3, FR 3.5, FR 3.6)
              Expanded(
                child: ListView.builder(
                  itemCount: allTasks.length,
                  itemBuilder: (context, index) {
                    final task = allTasks[index];

                    // 再次检查此任务在列表中是否与其他任务发生了冲突 (FR 3.7 UI 呈现)
                    bool isConflicting = _checkIsOverlapping(task, allTasks);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 2,
                      // 如果冲突，卡片侧边闪烁红条警告
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: isConflicting ? Colors.red.shade400 : Colors.transparent,
                            width: isConflicting ? 2 : 0
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: task.source == 'ocr' ? Colors.purple.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          // 区分来源标签：OCR 导入还是手动创建 (FR 3.5)
                          child: Text(
                            task.source == 'ocr' ? "OCR" : "MANUAL",
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: task.source == 'ocr' ? Colors.purple : Colors.orange.shade800
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (isConflicting)
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          ],
                        ),
                        subtitle: Text(
                          "${task.start.hour.toString().padLeft(2, '0')}:${task.start.minute.toString().padLeft(2, '0')} - "
                              "${task.end.hour.toString().padLeft(2, '0')}:${task.end.minute.toString().padLeft(2, '0')}\n"
                              "Intensity: ${task.intensity.name.toUpperCase()}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 编辑按钮 (FR 3.2)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _showTaskDialog(existingEvent: task),
                            ),
                            // 删除按钮 (FR 3.2)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                appState.removeEvent(task.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Deleted '${task.title}'")),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // 右下角浮动添加按钮 (FR 3.1)
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}