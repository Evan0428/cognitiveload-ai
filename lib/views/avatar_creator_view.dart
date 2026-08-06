import 'package:flutter/material.dart';
import 'package:fluttermoji/fluttermoji.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';

/// Create / edit the user's virtual avatar (Chua Yi Zhe).
///
/// Shown as a required step during onboarding ([onboarding] = true) and again
/// from Settings for edits. The user builds a cartoon avatar with the
/// fluttermoji customizer; the choice is saved locally + to Firestore.
class AvatarCreatorView extends StatefulWidget {
  final bool onboarding;
  const AvatarCreatorView({super.key, this.onboarding = false});

  @override
  State<AvatarCreatorView> createState() => _AvatarCreatorViewState();
}

class _AvatarCreatorViewState extends State<AvatarCreatorView> {
  final AvatarService _service = AvatarService();
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await _service.saveToCloud(); // customizer autosaves locally; mirror to cloud
    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.onboarding) {
      // Reveal the dashboard underneath (onboarding was pushed on top of it).
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Avatar saved!'),
            backgroundColor: AppTheme.success),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No back button during onboarding — creating an avatar is required.
      appBar: AppBar(
        automaticallyImplyLeading: !widget.onboarding,
        title: Text(widget.onboarding ? 'Create Your Avatar' : 'My Avatar'),
        actions: [
          if (!widget.onboarding)
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: AppTheme.indigo, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.onboarding)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                'Meet your assistant! Design a character that feels like you — '
                'it will greet you and share workload advice.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.inkSoft, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          // Big live preview
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.indigo.withValues(alpha: 0.18),
                AppTheme.indigo.withValues(alpha: 0.0),
              ]),
            ),
            child: FluttermojiCircleAvatar(
                radius: 54, backgroundColor: AppTheme.surfaceAlt),
          ),
          const SizedBox(height: 4),
          // Customizer (its own selectors + autosave to local storage)
          Expanded(
            child: FluttermojiCustomizer(
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
          // Onboarding: a clear "start" button that saves + enters the app.
          if (widget.onboarding)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Saving…' : 'Start My Journey'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
