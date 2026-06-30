import 'dart:convert'; // 🟢 用于 Base64 编解码图片
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../services/task_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // 备胎/默认值：在 Firebase 数据还没加载完时顶替一下，防止界面崩溃
  String _profileType = 'Student';
  double _burnoutThreshold = 70.0;
  bool _loadThresholdAlert = true;
  bool _preTaskAlert = true;
  bool _breakSuggestion = true;

  File? _avatarFile;        // 用于展示刚刚选中的本地文件
  String? _avatarBase64;    // 🟢 用于暂存从 Firebase 下载下来的头像字符串
  bool _isLoadingData = true;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFirebaseUserData(); // 🟢 启动时，直接去 Firebase 捞包括头像在内的所有数据
  }

  // 📥 从 Firebase Firestore 异步读取用户所有偏好资料（含头像）
  Future<void> _loadFirebaseUserData() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoadingData = false);
      return;
    }

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          // 如果 Firebase 有存数据，就覆盖掉一开始的默认备胎值
          _profileType = data['profileType'] ?? 'Student';
          _burnoutThreshold = (data['burnoutThreshold'] ?? 70.0).toDouble();
          _loadThresholdAlert = data['loadThresholdAlert'] ?? true;
          _preTaskAlert = data['preTaskAlert'] ?? true;
          _breakSuggestion = data['breakSuggestion'] ?? true;
          _avatarBase64 = data['avatarBase64']; // 🟢 读取云端头像字符串
        });
      }
    } catch (e) {
      debugPrint("Error loading from Firebase: $e");
    } finally {
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  // 💾 核心同步函数：将任何设置变动异步悄悄推送到 Firebase 对应 UID 下
  Future<void> _syncToFirebase(String field, dynamic value) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({field: value});
    } catch (e) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({field: value}, SetOptions(merge: true));
    }
  }

  // 🟢 弹出二次确认框，并在成功时同步
  void _confirmAndUpdate({
    required String title,
    required String content,
    required String firebaseField,
    required dynamic newValue,
    required VoidCallback onConfirmState,
    VoidCallback? onCancelState,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        content: Text(content, style: const TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (onCancelState != null) onCancelState();
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A3AFF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              onConfirmState(); // 更新本地 UI
              await _syncToFirebase(firebaseField, newValue); // 同步到云端

              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$title updated successfully!'),
                    backgroundColor: const Color(0xFF00C853),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 📸 头像图片选择与上传处理
  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 200,    // 💡 极其重要：转成字符串存数据库时，尺寸调小（如200x200）可以省流量且速度极快
        maxHeight: 200,
        imageQuality: 60, // 压缩质量降到 60%，保证 Firestore 不超限
      );

      if (pickedFile != null) {
        // 1. 将图片文件读取为字节数组并编码为 Base64 字符串
        final bytes = await pickedFile.readAsBytes();
        final String base64Image = base64Encode(bytes);

        // 2. 更新本地显示状态
        setState(() {
          _avatarFile = File(pickedFile.path);
          _avatarBase64 = base64Image;
        });

        // 3. 🟢 直接同步上传到 Firebase Firestore 存储！
        await _syncToFirebase('avatarBase64', base64Image);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile picture synced to cloud!'),
              backgroundColor: const Color(0xFF4A3AFF),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Upload image error: $e");
    }
  }

  void _showImageSourceBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF4A3AFF)),
              title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF4A3AFF)),
              title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 🟢 智能渲染图像逻辑
  ImageProvider? _getAvatarImage() {
    if (_avatarFile != null) {
      return FileImage(_avatarFile!); // 刚拍好/选好时，优先看本地文件
    }
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(_avatarBase64!)); // 🟢 从 Firebase 下载下来时，解码后渲染到圆圈里
    }
    return null; // 都没有就用默认自带图标
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF4A3AFF))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 👤 1. Profile Settings 卡片
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Profile Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      SizedBox(height: 2),
                      Text('Manage your account preferences', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 上传圆形头像
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: const Color(0xFFF1F5F9),
                            backgroundImage: _getAvatarImage(), // 🟢 智能调取图片方法
                            child: (_avatarFile == null && _avatarBase64 == null)
                                ? const Icon(Icons.person_rounded, size: 50, color: Color(0xFF94A3B8))
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _showImageSourceBottomSheet(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Color(0xFF4A3AFF), shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Text('Profile Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _profileType,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B)),
                        items: ['Student', 'Professional'].map((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)));
                        }).toList(),
                        onChanged: (val) {
                          if (val == _profileType) return;
                          _confirmAndUpdate(
                            title: 'Profile Type',
                            content: 'Are you sure you want to change your profile type to $val?',
                            firebaseField: 'profileType',
                            newValue: val,
                            onConfirmState: () => setState(() => _profileType = val!),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Daily Burnout Threshold', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      Text(_burnoutThreshold.toStringAsFixed(0), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4A3AFF))),
                    ],
                  ),
                  Slider(
                    value: _burnoutThreshold,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    activeColor: const Color(0xFF4A3AFF),
                    inactiveColor: const Color(0xFFE2E8F0),
                    onChanged: (val) {
                      setState(() => _burnoutThreshold = val);
                    },
                    onChangeEnd: (val) {
                      _confirmAndUpdate(
                        title: 'Burnout Threshold',
                        content: 'Are you sure you want to change your daily alert threshold to ${val.toStringAsFixed(0)}?',
                        firebaseField: 'burnoutThreshold',
                        newValue: val.toInt(),
                        onConfirmState: () => setState(() => _burnoutThreshold = val),
                        onCancelState: () => _loadFirebaseUserData(),
                      );
                    },
                  ),
                  const Text('Alerts trigger when daily load exceeds this value', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 🔔 2. Notifications 卡片
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(Icons.notifications_none_rounded, 'Notifications', 'Customize your alert preferences'),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                      'Load Threshold Alert',
                      'Daily load exceeds threshold',
                      _loadThresholdAlert,
                          (val) {
                        _confirmAndUpdate(
                          title: 'Threshold Alert',
                          content: 'Are you sure you want to ${val ? "enable" : "disable"} load threshold notifications?',
                          firebaseField: 'loadThresholdAlert',
                          newValue: val,
                          onConfirmState: () => setState(() => _loadThresholdAlert = val),
                        );
                      }
                  ),
                  _buildSwitchTile(
                      'Pre-Task Alert',
                      '15 min before high-intensity tasks',
                      _preTaskAlert,
                          (val) {
                        _confirmAndUpdate(
                          title: 'Pre-Task Alert',
                          content: 'Are you sure you want to ${val ? "enable" : "disable"} pre-task advance reminders?',
                          firebaseField: 'preTaskAlert',
                          newValue: val,
                          onConfirmState: () => setState(() => _preTaskAlert = val),
                        );
                      }
                  ),
                  _buildSwitchTile(
                      'Break Suggestion',
                      'After consecutive high-load tasks',
                      _breakSuggestion,
                          (val) {
                        _confirmAndUpdate(
                          title: 'Break Suggestion',
                          content: 'Are you sure you want to ${val ? "enable" : "disable"} intelligent fatigue rest tips?',
                          firebaseField: 'breakSuggestion',
                          newValue: val,
                          onConfirmState: () => setState(() => _breakSuggestion = val),
                        );
                      }
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 🗑️ 3. Data Management 卡片
            _buildCardContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(Icons.storage_rounded, 'Data Management', 'Control your local and synced records'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFFE4E6)),
                        backgroundColor: const Color(0xFFFFF1F2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      label: const Text('Clear All Tasks', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      onPressed: _confirmClearAllTasks,
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 🚪 4. Account 卡片
            _buildCardContainer(
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF1F5F9), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFF64748B)),
                  label: const Text('Sign Out', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Center(child: Text('CognitiveLoadAI v1.0.0 • Cognitive Load Management System', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // 🗑️ 二次确认后清空云端所有任务（AppState 的实时流会自动刷新仪表盘）。
  Future<void> _confirmClearAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Tasks', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        content: const Text('This permanently deletes every task synced to your account. This cannot be undone.', style: TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await TaskService().clearAllTasks();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('All tasks cleared.'),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear tasks: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: child,
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: const Color(0xFF4A3AFF), size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: const Color(0xFF4A3AFF),
      inactiveTrackColor: const Color(0xFFE2E8F0),
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }
}