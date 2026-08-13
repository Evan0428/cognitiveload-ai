import 'package:flutter/material.dart';

/// Manual cognitive-load rating dialog (FR 4.2 / 4.3).
///
/// Lets the user set the task's cognitive-load score DIRECTLY with a single
/// 0–100 slider — whatever they drag to is the score. The value is returned
/// through [onApply]; [initialScore] seeds the slider from the current
/// (auto-calculated) value so manual rating starts from a sensible point.
Future<void> showManualRatingDialog(
  BuildContext context, {
  required int initialScore,
  required void Function(int score) onApply,
}) {
  double value = initialScore.clamp(0, 100).toDouble();

  // Qualitative band + colour for the current value (matches the app's levels).
  ({String label, Color color}) bandFor(double v) {
    if (v < 35) return (label: 'Low', color: const Color(0xFF00C853));
    if (v < 55) return (label: 'Moderate', color: const Color(0xFF2196F3));
    if (v < 75) return (label: 'High', color: const Color(0xFFFF9800));
    return (label: 'Very High', color: const Color(0xFFF44336));
  }

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final int score = value.round();
          final band = bandFor(value);

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Manual Rating',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Set how mentally demanding this task feels for you.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ),
                const SizedBox(height: 16),

                // Big live score + band
                Text('$score',
                    style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.bold,
                        color: band.color)),
                Text('/ 100  ·  ${band.label}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: band.color)),
                const SizedBox(height: 8),

                // The single slider — drag = score
                SliderTheme(
                  data: SliderTheme.of(ctx).copyWith(
                    activeTrackColor: band.color,
                    thumbColor: band.color,
                    overlayColor: band.color.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 100,
                    // No `divisions` → continuous drag, so every value (e.g. 67)
                    // is selectable instead of snapping to fixed steps.
                    label: score.toString(),
                    onChanged: (v) => setLocal(() => value = v),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      Text('100', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A3AFF),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  onApply(score);
                  Navigator.pop(ctx);
                },
                child: const Text('Apply',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    },
  );
}
