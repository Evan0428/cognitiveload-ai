import 'package:flutter/material.dart';
import 'package:fluttermoji/fluttermoji.dart';
import '../services/assistant_service.dart';
import '../services/cognitive_load_engine.dart';
import '../theme/app_theme.dart';
import 'typewriter_text.dart';

/// Pops the avatar assistant into view with an entrance animation and speaks
/// the advice immediately, with the text shown in a readable dialog.
Future<void> showAssistantDialog(
  BuildContext context, {
  required CognitiveLoadResult result,
  String? name,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Assistant',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) =>
        _AssistantDialog(result: result, name: name),
    transitionBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.elasticOut);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + curved.value * 0.4, child: child),
      );
    },
  );
}

class _AssistantDialog extends StatefulWidget {
  final CognitiveLoadResult result;
  final String? name;
  const _AssistantDialog({required this.result, this.name});

  @override
  State<_AssistantDialog> createState() => _AssistantDialogState();
}

class _AssistantDialogState extends State<_AssistantDialog>
    with SingleTickerProviderStateMixin {
  final AssistantService _assistant = AssistantService();
  late final AnimationController _pulse;
  late final String _message;

  @override
  void initState() {
    super.initState();
    _message = _assistant.messageFor(widget.result, name: widget.name);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    // Speak immediately on appearance.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _assistant.speak(_message));
  }

  @override
  void dispose() {
    _assistant.stop();
    _pulse.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.result.level) {
      case LoadLevel.overload:
        return AppTheme.danger;
      case LoadLevel.high:
        return AppTheme.warning;
      case LoadLevel.elevated:
        return AppTheme.indigo;
      case LoadLevel.safe:
        return AppTheme.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 40,
                    offset: const Offset(0, 20)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Standing avatar that playfully bobs + wobbles while talking.
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) {
                    final t = _pulse.value; // 0..1..0 (repeat reverse)
                    return Transform.translate(
                      offset: Offset(0, -10 * t), // bob up/down
                      child: Transform.rotate(
                        angle: (t - 0.5) * 0.16, // cheeky left/right wobble
                        child: Transform.scale(scale: 1 + t * 0.05, child: child),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _accent.withValues(alpha: 0.22),
                        _accent.withValues(alpha: 0.0),
                      ]),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _accent, width: 3),
                      ),
                      child: FluttermojiCircleAvatar(
                          radius: 58, backgroundColor: AppTheme.surfaceAlt),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.graphic_eq_rounded, size: 16, color: _accent),
                    const SizedBox(width: 6),
                    Text('Your Assistant',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _accent)),
                  ],
                ),
                const SizedBox(height: 12),
                // The advice, revealed word-by-word like a chat message.
                TypewriterText(
                  _message,
                  textAlign: TextAlign.center,
                  wordDelay: const Duration(milliseconds: 190),
                  style: const TextStyle(
                      fontSize: 16,
                      height: 1.45,
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _assistant.speak(_message),
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Replay'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
