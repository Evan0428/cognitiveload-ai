import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state.dart';
import '../services/cognitive_load_engine.dart';
import '../view_models/add_task_viewmodel.dart'; 
import '../models/task_model.dart';
import '../models/models.dart';
import '../services/avatar_service.dart';
import '../services/rpm_service.dart';
import '../widgets/assistant_bubble.dart';
import '../widgets/standing_avatar.dart';
import 'settings_view.dart';
import 'task_manager_view.dart';
import 'schedule_screen.dart';
import 'scan_timetable_view.dart';
import 'analytics_view.dart';
import 'wellbeing_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String _realName = '...';
  String? _avatarBase64; // user's uploaded profile photo
  Offset? _avatarPos;    // where the user parked the 3D assistant
  static const double _assistantHeight = 190;

  @override
  void initState() {
    super.initState();
    _fetchUserNameFromFirestore();
    // Restore the user's saved avatars (3D RPM primary, cartoon fallback).
    RpmService().load();
    AvatarService().loadFromCloud();
    _loadAvatarPos();
  }

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
          _realName = data['name'] ?? 'User';
          _avatarBase64 = data['avatarBase64'] as String?;
        });
      }
    } catch (e) {
      debugPrint("Error fetching user name: $e");
    }
  }

  /// The assistant, freely draggable. Its spot is remembered, so if it ever
  /// covers a button the user just drags it somewhere better.
  Widget _buildDraggableAssistant(BuildContext context) {
    const w = _assistantHeight * 0.85; // character width
    const h = _assistantHeight + 90; // + room for the speech bubble
    final media = MediaQuery.of(context);
    final maxX = media.size.width - w;
    // Keep it clear of the bottom navigation bar.
    final maxY = media.size.height - h - media.padding.bottom - 70;

    final pos = _avatarPos ?? Offset(maxX - 6, maxY);

    return Positioned(
      left: pos.dx.clamp(0.0, maxX > 0 ? maxX : 0.0),
      top: pos.dy.clamp(media.padding.top, maxY > 0 ? maxY : 0.0),
      child: GestureDetector(
        // Drag to reposition; taps still reach the character underneath.
        onPanUpdate: (d) {
          setState(() {
            final next = (_avatarPos ?? Offset(maxX - 6, maxY)) + d.delta;
            _avatarPos = Offset(
              next.dx.clamp(0.0, maxX > 0 ? maxX : 0.0),
              next.dy.clamp(media.padding.top, maxY > 0 ? maxY : 0.0),
            );
          });
        },
        onPanEnd: (_) => _saveAvatarPos(),
        child: const StandingAvatar(height: _assistantHeight),
      ),
    );
  }

  Future<void> _saveAvatarPos() async {
    if (_avatarPos == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('assistantX', _avatarPos!.dx);
    await prefs.setDouble('assistantY', _avatarPos!.dy);
  }

  Future<void> _loadAvatarPos() async {
    final prefs = await SharedPreferences.getInstance();
    final x = prefs.getDouble('assistantX');
    final y = prefs.getDouble('assistantY');
    if (x != null && y != null && mounted) {
      setState(() => _avatarPos = Offset(x, y));
    }
  }

  /// Top-right = the USER's profile picture (photo they uploaded in Settings),
  /// not the 3D assistant character. Falls back to their initial.
  Widget _buildProfilePicture() {
    ImageProvider? image;
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(_avatarBase64!));
      } catch (_) {
        image = null;
      }
    }
    final initial =
        (_realName.isNotEmpty && _realName != '...') ? _realName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.white,
      backgroundImage: image,
      child: image == null
          ? Text(initial,
              style: const TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.bold,
                  fontSize: 20))
          : null,
    );
  }

  Color _levelColor(LoadLevel level) => switch (level) {
    LoadLevel.safe => const Color(0xFF00C853),
    LoadLevel.elevated => const Color(0xFF2196F3),
    LoadLevel.high => const Color(0xFFFF9800),
    LoadLevel.overload => const Color(0xFFF44336),
  };

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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;

    if (r == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
      );
    }

    final List<Widget> _tabs = [
      _buildHomeContent(r, state),
      const ScheduleScreen(),
      const AnalyticsView(),
      const WellbeingScreen(), // Chua — HealthKit / Apple Watch readiness
      const SettingsView(),
    ];

    return Scaffold(
      appBar: null,
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          IndexedStack(index: _currentIndex, children: _tabs),
          // 🧍 The 3D assistant stands free over the UI on every tab, and can
          // be dragged anywhere so it never blocks a button.
          _buildDraggableAssistant(context),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -4)),
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
          selectedItemColor: const Color(0xFF8B5CF6),
          unselectedItemColor: Colors.grey.shade400,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), activeIcon: Icon(Icons.calendar_today), label: 'Schedule'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Analytics'),
            BottomNavigationBarItem(icon: Icon(Icons.favorite_border), activeIcon: Icon(Icons.favorite), label: 'Wellbeing'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), activeIcon: Icon(Icons.settings), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent(CognitiveLoadResult r, AppState state) {
    final today = DateTime.now();
    final todayTasks = state.events.where((e) =>
    e.start.year == today.year &&
        e.start.month == today.month &&
        e.start.day == today.day
    ).toList();

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 240,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
          ),
        ),

        SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Greeting on the left, profile picture on the right.
                // Signing out lives in Settings only, so the header stays calm.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Welcome back,', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(
                            _realName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 🧑‍🎨 Virtual avatar (Chua) — tap to create / edit.
                    GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsView()),
                        );
                        if (mounted) _fetchUserNameFromFirestore();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _buildProfilePicture(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildGaugeCard(r),
                const SizedBox(height: 16),

                // ❤️ Chua — physiological readiness; taps through to Wellbeing.
                _buildReadinessCard(r),
                const SizedBox(height: 16),

                // 🗣️ Avatar assistant — speaks rule-based advice from the load.
                const AssistantBubble(),
                const SizedBox(height: 32),

                todayTasks.isEmpty
                    ? _buildEmptyTasksSection()
                    : _buildActiveTasksSection(todayTasks),

                const SizedBox(height: 32),

                Row(
                  children: [
                    Expanded(
                      child: _buildShortcutButton(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Scan Timetable',
                        iconColor: const Color(0xFF6366F1),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScanTimetableView()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildShortcutButton(
                        icon: Icons.playlist_add_rounded,
                        title: 'Add Task',
                        iconColor: const Color(0xFF6366F1),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChangeNotifierProvider(
                                create: (_) => AddTaskViewModel(),
                                child: const TaskManagerView(),
                              ),
                            ),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10))],
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
            decoration: BoxDecoration(color: mainColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
            child: Text(result.level == LoadLevel.safe ? "Low Load" : result.level.label, style: TextStyle(color: mainColor, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 14),
          const Text("Today's Cognitive Load", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }

  // ❤️ Physiological readiness mini-card (Chua's module). Tapping opens the
  // Wellbeing tab with the full HR / HRV / sleep / steps breakdown.
  Widget _buildReadinessCard(CognitiveLoadResult r) {
    final readiness = r.readinessScore;
    final color = readiness >= 70
        ? const Color(0xFF00C853)
        : readiness >= 45
            ? const Color(0xFFFF9800)
            : const Color(0xFFF44336);
    return InkWell(
      onTap: () => setState(() => _currentIndex = 3),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.favorite_rounded, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Physiological Readiness', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  SizedBox(height: 2),
                  Text('From Apple Watch / HealthKit', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            Text('${readiness.toStringAsFixed(0)}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
          ],
        ),
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
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChangeNotifierProvider(
                  create: (_) => AddTaskViewModel(),
                  child: const TaskManagerView(),
                ),
              ),
            );
          },
          child: const Text('Add Your First Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildActiveTasksSection(List<ScheduleEvent> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _currentIndex = 1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Today's Schedule", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              TextContainer(text: '${tasks.length} Tasks', color: const Color(0xFF6366F1)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tasks.length > 3 ? 3 : tasks.length,
          itemBuilder: (context, index) {
            final e = tasks[index];
            return InkWell(
              onTap: () => _editTask(e),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                          const SizedBox(height: 2),
                          Text(
                            "${e.start.hour.toString().padLeft(2,'0')}:${e.start.minute.toString().padLeft(2,'0')} - ${e.end.hour.toString().padLeft(2,'0')}:${e.end.minute.toString().padLeft(2,'0')}",
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.bolt, color: Colors.amber.shade600, size: 18),
                  ],
                ),
              ),
            );
          },
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
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
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

class TextContainer extends StatelessWidget {
  final String text;
  final Color color;
  const TextContainer({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}
