import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SetupProfileView extends StatefulWidget {
  const SetupProfileView({super.key});

  @override
  State<SetupProfileView> createState() => _SetupProfileViewState();
}

class _SetupProfileViewState extends State<SetupProfileView> {
  String _selectedProfileType = 'Student'; // 对应两个精美的大卡片选项
  double _burnoutThreshold = 70.0;         // 根据 mockup 图默认设为 70
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF1F9), // 保持系统标志性浅蓝灰色背景
      body: _isSaving
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4A3AFF)))
          : SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 30),
              // Title Section (Mockup 还原)
              const Text(
                'Setup Your Profile',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Customize your cognitive load tracking',
                style: TextStyle(color: Colors.grey, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // FR 1.4: Profile Type 选择区 (两大精美卡片横向并排)
              Align(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Profile Type',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2D3142)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Student 卡片
                  Expanded(
                    child: _buildSelectableCard(
                      title: 'Student',
                      description: 'Optimized for academic workload',
                      icon: Icons.school_outlined,
                      isSelected: _selectedProfileType == 'Student',
                      onTap: () => setState(() => _selectedProfileType = 'Student'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Professional 卡片
                  Expanded(
                    child: _buildSelectableCard(
                      title: 'Professional',
                      description: 'Optimized for work tasks',
                      icon: Icons.business_center_outlined,
                      isSelected: _selectedProfileType == 'Professional',
                      onTap: () => setState(() => _selectedProfileType = 'Professional'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // FR 1.5: Daily Burnout Threshold 模块 (高品质白卡底色)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Daily Burnout Threshold',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                        ),
                        Text(
                          '${_burnoutThreshold.toInt()}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Color(0xFF4A3AFF)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF007AFF), // 还原 Mockup 中深蓝色的 Slider 轴
                        inactiveTrackColor: const Color(0xFFE2E8F0),
                        thumbColor: const Color(0xFF007AFF),
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _burnoutThreshold,
                        min: 0,
                        max: 100,
                        onChanged: (val) => setState(() => _burnoutThreshold = val),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "You'll receive alerts when your daily cognitive load exceeds this threshold",
                      style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // What's Next 提示卡片面板
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9), // 浅灰蓝色区分
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "What's Next?",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 12),
                    _buildNextStepRow('Scan your timetable or add tasks manually'),
                    const SizedBox(height: 8),
                    _buildNextStepRow('AI will calculate cognitive load scores'),
                    const SizedBox(height: 8),
                    _buildNextStepRow('Get proactive alerts and break suggestions'),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Complete Setup 按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A3AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _saveProfileData,
                  child: const Text(
                    'Complete Setup',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // 辅助函数：构造 Student/Professional 大卡片
  Widget _buildSelectableCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF4A3AFF) : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: isSelected ? const Color(0xFF4A3AFF) : Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSelected ? const Color(0xFF4A3AFF) : const Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // What's Next 的小列表行辅助
  Widget _buildNextStepRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(color: Color(0xFF4A3AFF), fontWeight: FontWeight.bold, fontSize: 16)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }

  // 保存数据到 Firestore 核心方法
  Future<void> _saveProfileData() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 更新刚注册的用户的 Firestore 详细个性化配置数据
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'profileType': _selectedProfileType,
          'burnoutThreshold': _burnoutThreshold,
          'setupCompleted': true, // 额外标记位，证明初始化设置全部做完啦！
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile configured successfully!'), backgroundColor: Colors.green),
        );

        // 🟢 完美跳转：这里可以退回到登录、或者直接去你的主页 (Dashboard)
        // 比如：Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeView()));
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }
}