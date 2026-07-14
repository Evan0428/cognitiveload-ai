import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/add_task_viewmodel.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class AddTaskView extends StatefulWidget {
  const AddTaskView({super.key});

  @override
  State<AddTaskView> createState() => _AddTaskViewState();
}

class _AddTaskViewState extends State<AddTaskView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 日期选择
  Future<void> _pickDate(BuildContext context, AddTaskViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) vm.setDate(picked);
  }

  // 时间选择
  Future<void> _pickTime(BuildContext context, AddTaskViewModel vm, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      if (isStart) {
        vm.setStartTime(picked);
      } else {
        vm.setEndTime(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 ViewModel 状态变化
    final vm = context.watch<AddTaskViewModel>();
    // 🟢 监听全局 AppState
    final globalState = context.read<AppState>();

    String dateText = vm.selectedDate == null
        ? 'Select Date'
        : "${vm.selectedDate!.day.toString().padLeft(2,'0')}/${vm.selectedDate!.month.toString().padLeft(2,'0')}/${vm.selectedDate!.year}";

    String startText = vm.startTime == null ? '09:00 AM' : vm.startTime!.format(context);
    String endText = vm.endTime == null ? '10:00 AM' : vm.endTime!.format(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        ),
        leadingWidth: 80,
        title: const Text('New Task', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Task Name 输入框
              _buildLabel('Task Name'),
              TextFormField(
                controller: _nameController,
                decoration: _inputDecoration('Enter task name'),
                style: const TextStyle(fontWeight: FontWeight.w500),
                onChanged: (val) => vm.updateTaskName(val), // 触发实时核心分数计算
                validator: (v) => v == null || v.isEmpty ? 'Task name is required' : null,
              ),
              const SizedBox(height: 20),

              // 2. Date 字段选择器
              _buildLabel('Date'),
              InkWell(
                onTap: () => _pickDate(context, vm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: _boxDecoration(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateText, style: TextStyle(fontWeight: FontWeight.w500, color: vm.selectedDate == null ? Colors.black38 : Colors.black87)),
                      const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF64748B)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Start Time & End Time 横向分布
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Start Time'),
                        InkWell(
                          onTap: () => _pickTime(context, vm, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: _boxDecoration(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(startText, style: const TextStyle(fontWeight: FontWeight.w500)),
                                const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('End Time'),
                        InkWell(
                          onTap: () => _pickTime(context, vm, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: _boxDecoration(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(endText, style: const TextStyle(fontWeight: FontWeight.w500)),
                                const Icon(Icons.access_time_rounded, size: 18, color: Color(0xFF64748B)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // 4. 认知负载得分展示区域
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cognitive Load Score', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    icon: const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF4A3AFF)),
                    label: const Text('Manual Rating', style: TextStyle(fontSize: 13, color: Color(0xFF4A3AFF), fontWeight: FontWeight.bold)),
                    onPressed: () {
                      vm.setManualScore(90);
                    },
                  )
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(
                      '${vm.ratingType}: ',
                      style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      '${vm.cognitiveLoadScore}',
                      style: const TextStyle(color: Color(0xFFE11D48), fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Auto-calculated based on keywords in task name',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 40),

              // 5. 保存按键
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A3AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: vm.isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.bookmark_border_rounded, color: Colors.white),
                  label: Text(
                    vm.isSaving ? 'Saving Task...' : 'Save Task',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: vm.isSaving ? null : () async {
                    if (_formKey.currentState!.validate()) {
                      // 确保用户选择了日期和时间
                      if (vm.selectedDate == null || vm.startTime == null || vm.endTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select Date and Times first!'), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      // 先保存到本地暂存变量，防止异步清空
                      final taskName = _nameController.text.trim();
                      final taskScore = vm.cognitiveLoadScore;
                      final d = vm.selectedDate!;
                      final st = vm.startTime!;
                      final et = vm.endTime!;

                      // 1. 发起原始的云端上传
                      bool isSuccess = await vm.submitTask();

                      if (isSuccess && mounted) {
                        // 🟢 2. 数据联动闭环：同步注入本地核心状态管理，让主页圆圈分数产生化学反应 (FR 2.4)
                        TaskIntensity mappedIntensity = TaskIntensity.medium;
                        if (taskScore >= 80) {
                          mappedIntensity = TaskIntensity.critical;
                        } else if (taskScore >= 70) {
                          mappedIntensity = TaskIntensity.high;
                        } else if (taskScore <= 20) {
                          mappedIntensity = TaskIntensity.low;
                        }

                        globalState.addEvent(ScheduleEvent(
                          id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
                          title: taskName,
                          start: DateTime(d.year, d.month, d.day, st.hour, st.minute),
                          end: DateTime(d.year, d.month, d.day, et.hour, et.minute),
                          intensity: mappedIntensity,
                          source: 'manual',
                        ));

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Task integrated and dashboard score updated!'),
                            backgroundColor: const Color(0xFF00C853),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );

                        // 成功后连续退出，直接返回主 Dashboard 界面
                        Navigator.pop(context);
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black26, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3AFF), width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    );
  }
}