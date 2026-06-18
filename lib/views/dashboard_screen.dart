import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // 🟢 引入 Firestore 用来读取真实姓名
import '../services/app_state.dart';
import '../services/cognitive_load_engine.dart';
import 'settings_view.dart';
import 'task_manager_view.dart';

class SchedulePlaceholder extends StatelessWidget { const SchedulePlaceholder({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Schedule Page'))); }
class AnalyticsPlaceholder extends StatelessWidget { const AnalyticsPlaceholder({super.key}); @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Analytics Page'))); }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String _realName = '...'; // 🟢 默认先显示加载状态的三个点，避免写死兜底名字尴尬

  @override
  void initState() {
    super.initState();
    _fetchUserNameFromFirestore(); // 🟢 页面一诞生就去云端捞名字
  }

  // 📥 核心功能：直接去 Firestore 拿注册时填写的名字
  Future<void> _fetchUserNameFromFirestore() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          // 💡 这里的 'name' 必须和你注册时存在 Firestore 的字段大小写一模一样
          _realName = data['name'] ?? 'User';
        });
      }
    } catch (e) {
      debugPrint("Error fetching user name: $e");
    }
  }

  Color _levelColor(LoadLevel level) => switch (level) {
    LoadLevel.safe => const Color(0xFF00C853),
    LoadLevel.elevated => const Color(0xFF2196F3),
    LoadLevel.high => const Color(0xFFFF9800),
    LoadLevel.overload => const Color(0xFFF44336),
  };

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFF4A3AFF)),
            SizedBox(width: 8),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;

    if (r == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4A3AFF))),
      );
    }

    final List<Widget> _tabs = [
      _buildHomeContent(r, state),
      const SchedulePlaceholder(),
      const AnalyticsPlaceholder(),
      const SettingsView(),
    ];

    return Scaffold(
      appBar: null,
      backgroundColor: const Color(0xFFF8FAFC),
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, -4)),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF6723F5),
          unselectedItemColor: Colors.grey.shade400,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Schedule'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Analytics'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent(CognitiveLoadResult r, AppState state) {
    return Stack(
      children: [
        // 🌌 1. 顶部渐变大底板
        Container(
          width: double.infinity,
          height: 240,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF007AFF), Color(0xFF6723F5)],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
        ),

        // 2. 内容滑动区域
        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      alignment: Alignment.centerRight,
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
                      onPressed: () => _showLogoutDialog(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 👋 Welcome 欢迎区域
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Welcome back,', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 2),
                      // 🟢 这里直接塞入我们从 Firestore 异步抓到的真实名字
                      Text(_realName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 圆形仪表盘白卡
                _buildGaugeCard(r),
                const SizedBox(height: 32),

                // 空日程状态提示
                _buildEmptyTasksSection(),
                const SizedBox(height: 32),

                // ⚡ 捷径网格按键
                Row(
                  children: [
                    Expanded(
                      child: _buildShortcutButton(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Scan Timetable',
                        iconColor: const Color(0xFF4A3AFF),
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildShortcutButton(
                        icon: Icons.playlist_add_rounded,
                        title: 'Add Task',
                        iconColor: const Color(0xFF4A3AFF),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const TaskManagerView()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGaugeCard(CognitiveLoadResult result) {
    final mainColor = _levelColor(result.level);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 140,
            width: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 140,
                  width: 140,
                  child: CircularProgressIndicator(
                    value: result.combinedLoad / 100,
                    strokeWidth: 10,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(mainColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(result.combinedLoad.toStringAsFixed(0), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                    const Text('/ 100', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: BoxDecoration(color: mainColor.withOpacity(0.12), borderRadius: BorderRadius.circular(100)),
            child: Text(result.level == LoadLevel.safe ? "Low Load" : result.level.label, style: TextStyle(color: mainColor, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 14),
          const Text("Today's Cognitive Load", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildEmptyTasksSection() {
    return Column(
      children: [
        const Icon(Icons.calendar_today_outlined, size: 54, color: Color(0xFFCBD5E1)),
        const SizedBox(height: 14),
        const Text('No tasks scheduled for today', style: TextStyle(color: Color(0xFF64748B), fontSize: 15, fontWeight: FontWeight.w500)),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A3AFF),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: () {},
          child: const Text('Add Your First Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildShortcutButton({required IconData icon, required String title, required Color iconColor, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          ],
        ),
      ),
    );
  }
}