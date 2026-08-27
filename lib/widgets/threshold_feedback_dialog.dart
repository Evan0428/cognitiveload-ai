import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/cognitive_load_engine.dart';
import '../theme/app_theme.dart';

/// Asks the user, once per alert, whether the warning was useful.
///
/// The answer is the explicit training signal for the adaptive threshold, so
/// it must be collected exactly once per alert episode. It used to be offered
/// as chips beneath the assistant's speech bubble, which had two faults: the
/// chips were tied to whatever load level had been captured when the assistant
/// first greeted the user, so a warning that arrived later showed no chips at
/// all; and because they reappeared on every tap of the assistant, one alert
/// could be answered any number of times and fed into the learner repeatedly.
///
/// Presenting it as a modal driven by [AppState.awaitingThresholdFeedback]
/// fixes both: it appears the moment the alert fires, and the flag is spent as
/// soon as it is answered or dismissed.
///
/// Wrap the application shell in this widget; it renders [child] unchanged and
/// shows the question over the top when one is outstanding.
class ThresholdFeedbackHost extends StatefulWidget {
  final Widget child;
  const ThresholdFeedbackHost({super.key, required this.child});

  @override
  State<ThresholdFeedbackHost> createState() => _ThresholdFeedbackHostState();
}

class _ThresholdFeedbackHostState extends State<ThresholdFeedbackHost> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    // Watch only the flag, so unrelated state changes do not re-trigger this.
    final pending =
        context.select<AppState, bool>((s) => s.awaitingThresholdFeedback);

    if (pending && !_showing) {
      _showing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
    return widget.child;
  }

  Future<void> _ask() async {
    if (!mounted) {
      _showing = false;
      return;
    }
    final state = context.read<AppState>();
    final level = state.feedbackLevel ?? LoadLevel.high;
    final threshold = state.adaptiveThreshold;

    final answer = await showDialog<_Answer>(
      context: context,
      barrierDismissible: false, // a stray tap should not spend the question
      builder: (dialogContext) => _FeedbackDialog(
        level: level,
        currentValue: threshold.value,
        observations: threshold.observations,
      ),
    );

    if (!mounted) {
      _showing = false;
      return;
    }
    switch (answer) {
      case _Answer.fine:
        await state.thresholdFeedbackDismissed();
      case _Answer.rest:
        await state.thresholdFeedbackAccepted();
      case _Answer.ignored:
      case null:
        state.thresholdFeedbackIgnored();
    }
    _showing = false;
  }
}

enum _Answer { fine, rest, ignored }

class _FeedbackDialog extends StatelessWidget {
  final LoadLevel level;
  final double currentValue;
  final int observations;

  const _FeedbackDialog({
    required this.level,
    required this.currentValue,
    required this.observations,
  });

  @override
  Widget build(BuildContext context) {
    final overload = level == LoadLevel.overload;
    final accent =
        overload ? const Color(0xFFF44336) : const Color(0xFFFF9800);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              overload
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              overload ? 'Overload risk' : 'High load',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppTheme.ink),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You were warned at a load of ${currentValue.toStringAsFixed(0)}. '
            'Was that the right moment?',
            style: const TextStyle(
                fontSize: 14, height: 1.4, color: AppTheme.ink),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology_outlined,
                    size: 18, color: AppTheme.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    observations == 0
                        ? 'Your answer teaches the app when to warn you. This '
                            'is its first lesson.'
                        : 'Your answer teaches the app when to warn you — '
                            '$observations ${observations == 1 ? "lesson" : "lessons"} so far.',
                    style: const TextStyle(
                        fontSize: 12, height: 1.3, color: AppTheme.inkSoft),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _Answer.ignored),
          child: const Text('Not now',
              style: TextStyle(color: AppTheme.inkFaint)),
        ),
        TextButton.icon(
          onPressed: () => Navigator.pop(context, _Answer.fine),
          icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
          label: const Text("I'm fine"),
          style: TextButton.styleFrom(foregroundColor: AppTheme.inkSoft),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _Answer.rest),
          icon: const Icon(Icons.self_improvement_rounded, size: 16),
          label: const Text("I'll rest"),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.indigo),
        ),
      ],
    );
  }
}
