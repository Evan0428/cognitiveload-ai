import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttermoji/fluttermoji.dart';
import 'package:image_picker/image_picker.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';

/// Create / edit the user's virtual avatar (Chua Yi Zhe).
/// A selfie seeds skin tone via on-device ML Kit; the user refines the rest.
class AvatarCreatorView extends StatefulWidget {
  const AvatarCreatorView({super.key});

  @override
  State<AvatarCreatorView> createState() => _AvatarCreatorViewState();
}

class _AvatarCreatorViewState extends State<AvatarCreatorView> {
  final AvatarService _service = AvatarService();
  bool _scanning = false;
  int _rebuildKey = 0; // bumped after a scan to refresh the customizer

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _scanFace() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 600,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _scanning = true);
    final ok = await _service.seedFromSelfie(File(picked.path));
    if (!mounted) return;
    // Bump the key so the customizer rebuilds and shows the seeded avatar.
    setState(() {
      _scanning = false;
      if (ok) _rebuildKey++;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Face scanned — skin, hair & expression matched. Tweak the rest!'
            : "Couldn't read the photo. Try again in better lighting, or build manually."),
        backgroundColor: ok ? AppTheme.success : AppTheme.warning,
      ),
    );
  }

  Future<void> _save() async {
    await _service.saveToCloud();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Avatar saved!'), backgroundColor: AppTheme.success),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Avatar'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(
                    color: AppTheme.indigo, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Scan-to-seed banner
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Look like you',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      SizedBox(height: 4),
                      Text(
                          'Scan your face and we\'ll match your skin tone — then customise the rest.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _scanning ? null : _scanFace,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.indigo,
                  ),
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.indigo))
                      : const Icon(Icons.face_retouching_natural, size: 18),
                  label: Text(_scanning ? 'Scanning' : 'Scan face'),
                ),
              ],
            ),
          ),
          // Big standing preview — updates live as you scan / customise.
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.indigo.withValues(alpha: 0.18),
                AppTheme.indigo.withValues(alpha: 0.0),
              ]),
            ),
            child: FluttermojiCircleAvatar(
              key: ValueKey('preview_$_rebuildKey'),
              radius: 52,
              backgroundColor: AppTheme.surfaceAlt,
            ),
          ),
          // fluttermoji customizer (includes its own live preview + selectors)
          Expanded(
            child: FluttermojiCustomizer(
              key: ValueKey('customizer_$_rebuildKey'),
              scaffoldWidth: MediaQuery.of(context).size.width,
              autosave: true,
              theme: FluttermojiThemeData(
                boxDecoration: const BoxDecoration(),
                primaryBgColor: AppTheme.surfaceAlt,
                secondaryBgColor: AppTheme.surface,
                selectedIconColor: AppTheme.indigo,
                iconColor: AppTheme.inkFaint,
                labelTextStyle: const TextStyle(
                    color: AppTheme.ink, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
