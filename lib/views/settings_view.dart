import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/task_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String _profileType = 'Student';
  double _burnoutThreshold = 70.0;
  bool _loadThresholdAlert = true;
  bool _preTaskAlert = true;
  bool _breakSuggestion = true;
  bool _isClearingTasks = false;

  File? _avatarFile;
  String? _avatarBase64;
  bool _isLoadingData = true;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadFirebaseUserData();
  }

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
          _profileType = data['profileType'] ?? 'Student';
          _burnoutThreshold = (data['burnoutThreshold'] ?? 70.0).toDouble();
          _loadThresholdAlert = data['loadThresholdAlert'] ?? true;
          _preTaskAlert = data['preTaskAlert'] ?? true;
          _breakSuggestion = data['breakSuggestion'] ?? true;
          _avatarBase64 = data['avatarBase64'];
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
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              onConfirmState();
              await _syncToFirebase(firebaseField, newValue);

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

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 200,
        maxHeight: 200,
        imageQuality: 60,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final String base64Image = base64Encode(bytes);

        setState(() {
          _avatarFile = File(pickedFile.path);
          _avatarBase64 = base64Image;
        });

        await _syncToFirebase('avatarBase64', base64Image);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Profile picture synced to cloud!'),
              backgroundColor: const Color(0xFF6366F1),
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
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF6366F1)),
              title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF6366F1)),
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

  Future<void> _confirmAndClearAllTasks() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete all tasks?',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        content: const Text(
          'Are you sure you want to permanently delete all your tasks? This action cannot be undone.',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearingTasks = true);
    try {
      final deletedCount = await TaskService().deleteAllCurrentUserTasks();
      if (!mounted) return;

      context.read<AppState>().clearAll();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deletedCount == 0
              ? 'There were no tasks to delete.'
              : 'All $deletedCount tasks were deleted.'),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not delete tasks. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isClearingTasks = false);
    }
  }

  ImageProvider? _getAvatarImage() {
    if (_avatarFile != null) {
      return FileImage(_avatarFile!);
    }
    if (_avatarBase64 != null && _avatarBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(_avatarBase64!));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // 🟢 Removed AppBar to eliminate title text as requested
      appBar: null,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 20),
              
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

                    Center(
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2E8F0), width: 4),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                            ),
                            child: CircleAvatar(
                              radius: 50,
                              backgroundColor: const Color(0xFFF1F5F9),
                              backgroundImage: _getAvatarImage(),
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
                                decoration: const BoxDecoration(color: Color(0xFF6366F1), shape: BoxShape.circle),
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
                        Text('${_burnoutThreshold.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                      ],
                    ),
                    Slider(
                      value: _burnoutThreshold,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      activeColor: const Color(0xFF6366F1),
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
                        label: Text(
                          _isClearingTasks ? 'Deleting Tasks...' : 'Clear All Tasks',
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _isClearingTasks ? null : _confirmAndClearAllTasks,
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

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
      ),
    );
  }

  Widget _buildCardContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
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
          child: Icon(icon, color: const Color(0xFF6366F1), size: 22),
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
      activeColor: Colors.white,
      activeTrackColor: const Color(0xFF6366F1),
      inactiveTrackColor: const Color(0xFFE2E8F0),
      contentPadding: EdgeInsets.zero,
      onChanged: onChanged,
    );
  }
}
