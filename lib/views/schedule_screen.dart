import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../models/task_model.dart';
import '../view_models/add_task_viewmodel.dart';
import '../services/task_service.dart';
import 'task_manager_view.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final DateTime _today = DateTime.now();
  late DateTime _focusedMonth = DateTime(_today.year, _today.month, 1);
  late DateTime _selectedDate = DateTime(_today.year, _today.month, _today.day);

  int _getIntValueByIntensity(TaskIntensity intensity) {
    return switch (intensity) {
      TaskIntensity.low => 20,
      TaskIntensity.medium => 50,
      TaskIntensity.high => 75,
      TaskIntensity.critical => 95,
    };
  }

  Color _getColorByIntensity(TaskIntensity intensity) {
    return switch (intensity) {
      TaskIntensity.low => const Color(0xFF00C853),
      TaskIntensity.medium => const Color(0xFFFFB300),
      TaskIntensity.high => const Color(0xFFFF9800),
      TaskIntensity.critical => const Color(0xFFF44336),
    };
  }

  void _editTask(ScheduleEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => AddTaskViewModel()..loadTask(TaskModel(
            id: event.id,
            name: event.title,
            date: event.start,
            startTime: "${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}",
            endTime: "${event.end.hour.toString().padLeft(2, '0')}:${event.end.minute.toString().padLeft(2, '0')}",
            cognitiveLoadScore: event.cognitiveLoadScore,
            ratingType: event.ratingType,
          )),
          child: const TaskManagerView(),
        ),
      ),
    );
  }

  // 🟢 弹出删除确认框并同步 Firebase
  void _confirmDelete(BuildContext context, AppState state, ScheduleEvent event) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Task?', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text("Are you sure you want to delete '${event.title}'? This will also remove it from the cloud."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext); // 关闭对话框
              
              try {
                // 1. 只有非 OCR 临时生成的 ID 才去 Firebase 删除 (OCR任务未入库前 ID 以 ocr_ 开头)
                if (!event.id.startsWith('ocr_')) {
                  await TaskService().deleteTask(event.id);
                }
                
                // 2. 从本地 AppState 内存及缓存中删除
                state.removeEvent(event.id);
                
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Successfully deleted '${event.title}'"),
                      backgroundColor: Colors.black87,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error deleting task: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final filteredEvents = state.events.where((e) =>
    e.start.year == _selectedDate.year &&
        e.start.month == _selectedDate.month &&
        e.start.day == _selectedDate.day
    ).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: null,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // 📅 日历卡片区域
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(_focusedMonth),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        Row(
                          children: [
                            _buildCalendarNavBtn(Icons.remove, () {
                              setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
                            }),
                            const SizedBox(width: 8),
                            _buildCalendarNavBtn(Icons.arrow_forward, () {
                              setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
                            }),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                          .map((w) => Text(w, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    _buildCalendarGrid(state),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  children: [
                    Text(
                      DateFormat('MMM d').format(_selectedDate),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${filteredEvents.length} tasks)',
                      style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 🚀 任务列表区域
              filteredEvents.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40.0),
                  child: Column(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text("No commitments for this day.", style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredEvents.length,
                itemBuilder: (context, index) {
                  final event = filteredEvents[index];
                  final int score = _getIntValueByIntensity(event.intensity);
                  final Color scoreColor = _getColorByIntensity(event.intensity);

                  return InkWell(
                    onTap: () => _editTask(event),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: score / 100,
                                  strokeWidth: 4,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                                ),
                                Text(
                                  '$score',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.title,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')} - "
                                      "${event.end.hour.toString().padLeft(2, '0')}:${event.end.minute.toString().padLeft(2, '0')}",
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          // 🟢 这里应用了新的 _confirmDelete 方法
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                            onPressed: () => _confirmDelete(context, state, event),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarNavBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: const Color(0xFF1E293B)),
      ),
    );
  }

  Widget _buildCalendarGrid(AppState state) {
    final int daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final int firstDayOffset = DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;

    List<Widget> dayCells = [];

    for (int i = 0; i < firstDayOffset; i++) {
      dayCells.add(const SizedBox());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final currentDate = DateTime(_focusedMonth.year, _focusedMonth.month, day);
      final bool isSelected = currentDate.year == _selectedDate.year &&
          currentDate.month == _selectedDate.month &&
          currentDate.day == _selectedDate.day;

      final bool hasTasks = state.events.any((e) =>
      e.start.year == currentDate.year &&
          e.start.month == currentDate.month &&
          e.start.day == currentDate.day);

      dayCells.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = currentDate;
            });
          },
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? Colors.transparent : Colors.transparent,
              border: isSelected ? Border.all(color: const Color(0xFF6723F5), width: 1.5) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? const Color(0xFF6723F5) : const Color(0xFF334155),
                  ),
                ),
                if (hasTasks)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.redAccent : const Color(0xFFFFB300),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: dayCells,
    );
  }
}
