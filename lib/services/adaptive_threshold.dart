import 'dart:convert';
import 'dart:math' as math;

/// Adaptive burnout-threshold learner (Chua Yi Zhe).
///
/// Instead of a fixed slider value, the system **learns** the cognitive-load
/// level at which THIS user actually needs to be warned. It is an on-device
/// online (incremental) learner: every observation nudges the threshold with a
/// decaying learning rate, so early evidence moves it quickly and it settles
/// as confidence grows.
///
/// Two feedback channels drive it:
///  1. **Explicit** — how the user answers an alert ("I'm fine" = too
///     sensitive, raise it; "I'll rest" = useful, warn slightly earlier).
///  2. **Implicit / physiological** — what actually happened afterwards. If a
///     heavy day was followed by a real drop in recovery, the warning came too
///     late (lower it). If a warning fired but recovery held up, it was a
///     false alarm (raise it).
///
/// The learned value is clamped to a sensible band around the user's own
/// starting preference so it personalises without running away.
class AdaptiveThreshold {
  /// The user's own starting preference (the Settings slider) — used as the
  /// prior and the centre of the allowed band.
  double base;

  double _learned;
  int _observations;

  /// How far the model may drift from the user's preference.
  static const double drift = 25.0;
  static const double minValue = 25.0;
  static const double maxValue = 95.0;

  /// Observations needed before the model is considered confident.
  static const int confidentAfter = 20;

  AdaptiveThreshold({this.base = 70.0, double? learned, int observations = 0})
      : _learned = learned ?? base,
        _observations = observations;

  /// The threshold the app should use right now.
  double get value => _learned;

  int get observations => _observations;

  /// 0..1 — how much evidence the model has gathered.
  double get confidence =>
      (_observations / confidentAfter).clamp(0.0, 1.0).toDouble();

  bool get isPersonalised => _observations > 0;

  /// How far it has moved from the user's original preference (+ = warns later).
  double get shift => _learned - base;

  /// Learning rate decays as evidence accumulates (Robbins–Monro style), so
  /// the threshold stabilises instead of oscillating forever.
  double get _rate => 1.0 / (1.0 + _observations * 0.35);

  void _apply(double signal) {
    // signal > 0 → warn later (less sensitive); < 0 → warn earlier.
    final lo = math.max(minValue, base - drift);
    final hi = math.min(maxValue, base + drift);
    _learned = (_learned + signal * 6.0 * _rate).clamp(lo, hi);
    _observations++;
  }

  // ---------------- explicit feedback ----------------

  /// User dismissed the warning ("I'm fine") → it was too eager.
  void alertDismissed() => _apply(1.0);

  /// User accepted the warning ("I'll rest") → it was useful; nudge a little
  /// earlier so they get more runway next time.
  void alertAccepted() => _apply(-0.5);

  // ---------------- implicit physiological feedback ----------------

  /// Learn from what actually happened to recovery after a day's peak load.
  ///
  /// [peakLoad] — the highest combined load reached that day.
  /// [readinessBefore] / [readinessAfter] — readiness that day vs the next.
  void observeOutcome({
    required double peakLoad,
    required double readinessBefore,
    required double readinessAfter,
  }) {
    final recoveryDrop = readinessBefore - readinessAfter;
    final warned = peakLoad >= value;
    final strained = recoveryDrop >= 8.0; // meaningful loss of recovery

    if (warned && !strained) {
      _apply(0.8); // false alarm — they coped fine, so warn later
    } else if (!warned && strained) {
      _apply(-1.0); // missed it — they burned out unwarned, so warn earlier
    } else if (warned && strained) {
      _apply(-0.2); // correct call, but a touch earlier wouldn't hurt
    } else {
      _observations++; // correct silence: evidence, but no change needed
    }
  }

  /// User moved the slider themselves — treat it as a fresh preference.
  void setBase(double newBase) {
    base = newBase;
    _learned = newBase;
    _observations = 0;
  }

  // ---------------- persistence ----------------

  Map<String, dynamic> toJson() =>
      {'base': base, 'learned': _learned, 'observations': _observations};

  factory AdaptiveThreshold.fromJson(Map<String, dynamic> j) =>
      AdaptiveThreshold(
        base: (j['base'] as num?)?.toDouble() ?? 70.0,
        learned: (j['learned'] as num?)?.toDouble(),
        observations: (j['observations'] as num?)?.toInt() ?? 0,
      );

  String encode() => jsonEncode(toJson());

  factory AdaptiveThreshold.decode(String s) =>
      AdaptiveThreshold.fromJson(jsonDecode(s) as Map<String, dynamic>);

  /// Plain-English explanation for the UI (explainable AI).
  String get explanation {
    if (!isPersonalised) {
      return 'Learning starts once you respond to alerts — for now it uses '
          'your chosen level of ${base.toStringAsFixed(0)}.';
    }
    final dir = shift.abs() < 0.5
        ? 'matches'
        : (shift > 0 ? 'is ${shift.toStringAsFixed(0)} above' : 'is ${(-shift).toStringAsFixed(0)} below');
    final pct = (confidence * 100).toStringAsFixed(0);
    return 'Learned from $_observations observations ($pct% confidence). '
        'Your personal alert level $dir your original setting.';
  }
}
