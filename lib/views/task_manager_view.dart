import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import '../view_models/add_task_viewmodel.dart';

class TaskManagerView extends StatefulWidget {
  const TaskManagerView({super.key});

  @override
  State<TaskManagerView> createState() => _TaskManagerViewState();
}

class _TaskManagerViewState extends State<TaskManagerView> {
  bool _showForm = false;
  bool _isInitialized = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();

  late DateTime _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final vm = Provider.of<AddTaskViewModel>(context, listen: false);
      if (vm.editingTaskId != null) {
        // 🟢 编辑模式：从 ViewModel 同步数据到本地控制器
        _showForm = true; 
        _nameController.text = vm.taskName;
        if (vm.selectedDate != null) _selectedDate = vm.selectedDate!;
        if (vm.startTime != null) _startTime = vm.startTime!;
        if (vm.endTime != null) _endTime = vm.endTime!;
      }
      _isInitialized = true;
    }
  }

  TaskIntensity _getIntensityByScore(int score) {
    if (score >= 85) return TaskIntensity.critical;
    if (score >= 70) return TaskIntensity.high;
    if (score <= 30) return TaskIntensity.low;
    return TaskIntensity.medium;
  }

  @override
  Widget build(BuildContext context) {
    return _showForm ? _buildNewTaskFormView() : _buildTaskManagerMainView();
  }

  Widget _buildTaskManagerMainView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leadingWidth: 90,
        leading: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.only(left: 12.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios, color: Color(0xFF1E293B), size: 14),
                SizedBox(width: 4),
                Text('Back', style: TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        title: const Text('Task Manager', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(color: Color(0xFFEAEAFF), shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, size: 40, color: Color(0xFF6366F1)),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Add Manual Task', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 8),
            const Text('Create tasks that weren\'t on your scanned\ntimetable', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5)),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: () => setState(() => _showForm = true),
                child: const Text('Create New Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cognitive Load Features:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 13)),
                  const SizedBox(height: 8),
                  _buildFeatureRow('•  Automatic keyword-based load calculation'),
                  _buildFeatureRow('•  Manual NASA-TLX rating option'),
                  _buildFeatureRow('•  Profile-based weight adjustment'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewTaskFormView() {
    final addTaskVM = context.watch<AddTaskViewModel>();
    final isEditing = addTaskVM.editingTaskId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 12), alignment: Alignment.centerLeft),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        title: Text(isEditing ? 'Edit Task' : 'New Task', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldTitle('Task Name *'),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Color(0xFF1E293B), fontSize: 15),
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  hintText: 'e.g., MPU test',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.normal, fontSize: 15),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                ),
                onChanged: (value) => context.read<AddTaskViewModel>().updateTaskName(value),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Task name is required' : null,
              ),
              const SizedBox(height: 20),

              _buildFieldTitle('Date *'),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2024), lastDate: DateTime(2030));
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd/MM/yyyy').format(_selectedDate), style: const TextStyle(fontSize: 15)),
                      const Icon(Icons.calendar_today_outlined, color: Colors.grey, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldTitle('Start Time *'),
                        InkWell(
                          onTap: () async {
                            final time = await showTimePicker(context: context, initialTime: _startTime);
                            if (time != null) setState(() => _startTime = time);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_startTime.format(context), style: const TextStyle(fontSize: 14)),
                                const Icon(Icons.access_time_rounded, color: Colors.grey, size: 18),
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
                        _buildFieldTitle('End Time *'),
                        InkWell(
                          onTap: () async {
                            final time = await showTimePicker(context: context, initialTime: _endTime);
                            if (time != null) setState(() => _endTime = time);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_endTime.format(context), style: const TextStyle(fontSize: 14)),
                                const Icon(Icons.access_time_rounded, color: Colors.grey, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cognitive Load Score', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                        TextButton(
                          onPressed: () {},
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          child: const Text('⚡ Manual Rating', style: TextStyle(fontSize: 12, color: Color(0xFF6366F1), fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFFFECEF), borderRadius: BorderRadius.circular(20)),
                      child: Text('Automatic: ${addTaskVM.cognitiveLoadScore}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    const SizedBox(height: 10),
                    const Text('Auto-calculated based on keywords in task name', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.save_rounded, color: Colors.white),
                label: Text(addTaskVM.isSaving ? 'Saving...' : 'Save Task', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: addTaskVM.isSaving ? null : () async {
                  if (_formKey.currentState!.validate()) {
                    final appState = Provider.of<AppState>(context, listen: false);
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);

                    // 同步到 VM
                    addTaskVM.setDate(_selectedDate);
                    addTaskVM.setStartTime(_startTime);
                    addTaskVM.setEndTime(_endTime);

                    final success = await addTaskVM.submitTask();
                    if (success) {
                      await appState.syncTasksFromFirestore();
                      messenger.showSnackBar(const SnackBar(content: Text("Task successfully saved!")));
                      navigator.pop();
                    } else {
                      messenger.showSnackBar(const SnackBar(content: Text('Could not save task. Please try again.')));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155))),
    );
  }

  Widget _buildFeatureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text(text, style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 12)),
    );
  }
}
