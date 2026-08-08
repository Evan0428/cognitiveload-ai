import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/assistant_service.dart';
import '../services/cognitive_load_engine.dart';
import '../theme/app_theme.dart';
import 'avatar_view.dart';

/// The avatar assistant: shows the user's avatar with a speech bubble of
/// rule-based advice, and speaks it (flutter_tts). Auto-speaks when the load
/// escalates to High/Overload, and congratulates when heavy work clears.
class AssistantBubble extends StatefulWidget {
  /// When true, renders on a light card (Home over the gradient header uses
  /// [onGradient] = true for white text).
  final bool onGradient;
  const AssistantBubble({super.key, this.onGradient = false});

  @override
  State<AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<AssistantBubble> {
  final AssistantService _assistant = AssistantService();
  LoadLevel? _lastLevel;

  @override
  void dispose() {
    _assistant.stop();
    super.dispose();
  }

  void _maybeAutoSpeak(CognitiveLoadResult r, String? name) {
    final prev = _lastLevel;
    if (prev == r.level) return;

    // First appearance: the open-app dialog does the greeting, so just record
    // the level without speaking (avoids double audio).
    if (prev == null) {
      _lastLevel = r.level;
      return;
    }

    final escalated =
        (r.level == LoadLevel.high || r.level == LoadLevel.overload) &&
            (prev == null || r.level.index > prev.index);
    final workloadOver =
        (prev == LoadLevel.high || prev == LoadLevel.overload) &&
            r.level == LoadLevel.safe;
    _lastLevel = r.level;

    if (escalated || workloadOver) {
      final text = workloadOver
          ? _assistant.workloadOverMessage(name: name)
          : _assistant.messageFor(r, name: name);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _assistant.speak(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;
    if (r == null) return const SizedBox.shrink();

    final name = state.userProfile?.name;
    _maybeAutoSpeak(r, name);
    final message = _assistant.messageFor(r, name: name);

    final bubbleColor =
        widget.onGradient ? Colors.white.withValues(alpha: 0.18) : AppTheme.surface;
    final textColor = widget.onGradient ? Colors.white : AppTheme.ink;
    final subColor =
        widget.onGradient ? Colors.white70 : AppTheme.inkSoft;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: widget.onGradient ? Colors.white : AppTheme.line,
                width: 2),
          ),
          child: AvatarView(
              size: 48,
              background: widget.onGradient ? Colors.white : AppTheme.surfaceAlt),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: widget.onGradient ? null : AppTheme.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Assistant',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: subColor)),
                      const SizedBox(height: 3),
                      Text(message,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: textColor,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.volume_up_rounded,
                      color: widget.onGradient ? Colors.white : AppTheme.indigo),
                  tooltip: 'Hear advice',
                  onPressed: () =>
                      _assistant.speak(_assistant.messageFor(r, name: name)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
