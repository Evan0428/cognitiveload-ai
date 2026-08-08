import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/assistant_service.dart';
import '../theme/app_theme.dart';
import 'avatar_view.dart';
import 'typewriter_text.dart';

/// The assistant standing free in the UI — a full-body 3D character with a
/// soft ground shadow, not boxed inside a window. Tap it and it talks: the
/// advice types out word-by-word in a speech bubble while it speaks aloud.
class StandingAvatar extends StatefulWidget {
  final double height;
  const StandingAvatar({super.key, this.height = 190});

  @override
  State<StandingAvatar> createState() => _StandingAvatarState();
}

class _StandingAvatarState extends State<StandingAvatar> {
  final AssistantService _assistant = AssistantService();
  bool _talking = false;

  @override
  void dispose() {
    _assistant.stop();
    super.dispose();
  }

  Future<void> _talk(String message) async {
    setState(() => _talking = true);
    await _assistant.speak(message);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;
    if (r == null) return const SizedBox.shrink();

    final message =
        _assistant.messageFor(r, name: state.userProfile?.name);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Speech bubble appears above the character while it talks.
        if (_talking)
          Container(
            constraints: const BoxConstraints(maxWidth: 240),
            margin: const EdgeInsets.only(bottom: 6, right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: AppTheme.softShadow,
              border: Border.all(color: AppTheme.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: TypewriterText(
                    message,
                    wordDelay: const Duration(milliseconds: 190),
                    style: const TextStyle(
                        fontSize: 13, height: 1.35, color: AppTheme.ink),
                  ),
                ),
                InkWell(
                  onTap: () {
                    _assistant.stop();
                    setState(() => _talking = false);
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6, top: 2),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: AppTheme.inkFaint),
                  ),
                ),
              ],
            ),
          ),

        // The character itself, standing on a soft shadow.
        GestureDetector(
          onTap: () => _talk(message),
          child: SizedBox(
            height: widget.height,
            width: widget.height * 0.85,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Ground shadow so it reads as standing on the screen.
                Positioned(
                  bottom: 6,
                  child: Container(
                    width: widget.height * 0.42,
                    height: widget.height * 0.09,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.all(
                          Radius.elliptical(widget.height * 0.21, widget.height * 0.045)),
                      gradient: RadialGradient(colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
                // Full-body 3D model, transparent, unclipped.
                AvatarView(size: widget.height, circle: false),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
