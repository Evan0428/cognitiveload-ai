import 'package:flutter/material.dart';
import 'add_task_view.dart';

class TaskManagerView extends StatelessWidget {
  const TaskManagerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Task Manager', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(),
            // ➕ 标志性的大加号圆形按钮
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAEAFF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, size: 40, color: Color(0xFF4A3AFF)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add Manual Task',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create tasks that weren\'t on your scanned\ntimetable',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A3AFF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddTaskView()),
                  );
                },
                child: const Text('Create New Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const Spacer(),
            // 底部 Feature 卡片
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
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

  Widget _buildFeatureRow(String text) {
    return Padding(
      // 🟢 将 .only 改为 .symmetric，这样就能完美识别 vertical 参数了
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Text(text, style: const TextStyle(color: Color(0xFF1E40AF), fontSize: 12)),
    );
  }
}