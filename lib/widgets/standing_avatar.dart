import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/assistant_service.dart';
import '../services/cognitive_load_engine.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';
import 'avatar_view.dart';
import 'typewriter_text.dart';

/// The assistant standing free in the UI — a full-body 3D character with a
/// soft ground shadow, not boxed inside a window.
///
/// It feels alive: it breathes while idle, hops and waves when you tap it,
/// bobs while talking, and shakes when your workload hits overload.
class StandingAvatar extends StatefulWidget {
  final double height;
  const StandingAvatar({super.key, this.height = 190});

  @override
  State<StandingAvatar> createState() => _StandingAvatarState();
}

class _StandingAvatarState extends State<StandingAvatar>
    with TickerProviderStateMixin {
  final AssistantService _assistant = AssistantService();

  late final AnimationController _idle;   // continuous breathing / sway
  late final AnimationController _react;  // one-shot tap reaction

  bool _talking = false;
  bool _greeted = false;
  bool _interacted = false; // hides the "tap me" hint once they engage
  Timer? _idleTimer;
  final math.Random _rng = math.Random();
  String _clip = 'idle';        // animation clip for models that have them
  _Reaction _reaction = _Reaction.hop;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _react = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _startIdleActions();
  }

  @override
  void dispose() {
    _assistant.stop();
    _idleTimer?.cancel();
    _idle.dispose();
    _react.dispose();
    super.dispose();
  }

  /// Play a physical reaction + (for models that support it) a real clip.
  void _playReaction(_Reaction r, String mood) {
    // Each action has its own natural tempo.
    _react.duration = switch (r) {
      _Reaction.twirl => const Duration(milliseconds: 1100),
      _Reaction.stretch => const Duration(milliseconds: 1200),
      _Reaction.look => const Duration(milliseconds: 1600),
      _Reaction.wave => const Duration(milliseconds: 1200),
      _Reaction.cheer => const Duration(milliseconds: 1000),
      _ => const Duration(milliseconds: 850),
    };
    setState(() {
      _reaction = r;
      _clip = mood;
    });
    _react.forward(from: 0).then((_) {
      // Settle back to the idle clip once the reaction finishes.
      if (mounted) setState(() => _clip = 'idle');
    });
  }

  /// Every so often the character does something on its own so it never feels
  /// static — glancing around, stretching, waving, a little twirl.
  void _startIdleActions() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _talking || _react.isAnimating) return;
      // Only act sometimes, so it feels spontaneous rather than clockwork.
      if (_rng.nextDouble() > 0.55) return;

      const pool = [
        _Reaction.look,
        _Reaction.stretch,
        _Reaction.wave,
        _Reaction.hop,
        _Reaction.twirl,
        _Reaction.cheer,
      ];
      final r = pool[_rng.nextInt(pool.length)];
      final mood = switch (r) {
        _Reaction.wave => 'greet',
        _Reaction.cheer => 'happy',
        _Reaction.hop || _Reaction.twirl => 'jump',
        _ => 'idle',
      };
      _playReaction(r, mood);
    });
  }

  Future<void> _onTap(String message, LoadLevel level) async {
    // React in a way that matches how the day is going.
    final r = switch (level) {
      LoadLevel.overload => _Reaction.shake,
      LoadLevel.high => _Reaction.nod,
      _ => _Reaction.hop,
    };
    final mood = switch (level) {
      LoadLevel.overload || LoadLevel.high => 'alert',
      _ => 'greet',
    };
    _playReaction(r, mood);
    setState(() {
      _talking = true;
      _interacted = true;
    });
    await _assistant.speak(message);
  }

  void _greetOnce(String message, LoadLevel level) {
    if (_greeted) return;
    _greeted = true;
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) _onTap(message, level);
    });
  }

  /// Combined idle + reaction transform.
  Widget _animated(Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _react]),
      builder: (context, _) {
        // --- idle: gentle breathing + tiny sway (skip if the model animates
        //     itself, so we don't fight its own clip) ---
        final breathe = RpmService.hasOwnAnimation ? 0.0 : _idle.value;
        final idleLift = math.sin(breathe * math.pi) * 3.0;
        final idleScaleY = 1 + math.sin(breathe * math.pi) * 0.02;
        final idleTilt = (breathe - 0.5) * 0.05;

        // --- reaction ---
        final t = _react.value;
        double dx = 0, dy = 0, rot = 0, sx = 1, sy = 1, turn = 0;
        if (_react.isAnimating || t > 0) {
          switch (_reaction) {
            case _Reaction.hop:
              // two bounces with squash & stretch
              final b = math.sin(t * math.pi * 2).abs();
              dy = -b * 26;
              sy = 1 + b * 0.10 - (t < 0.12 ? 0.12 : 0);
              sx = 1 - b * 0.06;
              rot = math.sin(t * math.pi * 4) * 0.06;
            case _Reaction.nod:
              rot = math.sin(t * math.pi * 3) * 0.14;
              dy = -math.sin(t * math.pi) * 8;
            case _Reaction.shake:
              dx = math.sin(t * math.pi * 8) * 7 * (1 - t);
              rot = math.sin(t * math.pi * 8) * 0.05 * (1 - t);
            case _Reaction.wave:
              // lean over and rock, like waving an arm
              rot = math.sin(t * math.pi) * 0.10 +
                  math.sin(t * math.pi * 6) * 0.07;
              dy = -math.sin(t * math.pi) * 6;
            case _Reaction.stretch:
              // reach up tall, then settle back
              final s = math.sin(t * math.pi);
              sy = 1 + s * 0.14;
              sx = 1 - s * 0.05;
              dy = -s * 10;
            case _Reaction.look:
              // glance left, then right, then back to centre
              dx = math.sin(t * math.pi * 2) * 10;
              rot = math.sin(t * math.pi * 2) * 0.07;
            case _Reaction.twirl:
              // full turn on the spot
              turn = t * math.pi * 2;
              dy = -math.sin(t * math.pi) * 10;
            case _Reaction.cheer:
              // excited double bounce with a happy wiggle
              final b = math.sin(t * math.pi * 3).abs();
              dy = -b * 20;
              rot = math.sin(t * math.pi * 6) * 0.10;
              sy = 1 + b * 0.08;
          }
        }

        Widget content = Transform.scale(
          scaleX: sx,
          scaleY: sy * idleScaleY,
          alignment: Alignment.bottomCenter,
          child: child,
        );

        // Y-axis turn for the twirl (perspective keeps it from looking flat).
        if (turn != 0) {
          content = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(turn),
            child: content,
          );
        }

        return Transform.translate(
          offset: Offset(dx, dy + idleLift),
          child: Transform.rotate(
            angle: rot + idleTilt,
            alignment: Alignment.bottomCenter,
            child: content,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final r = state.result;
    if (r == null) return const SizedBox.shrink();

    final message = _assistant.messageFor(r, name: state.userProfile?.name);
    _greetOnce(message, r.level);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Speech bubble pops out of the character, anime-style.
        if (_talking)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, t, child) => Transform.scale(
              scale: 0.6 + t * 0.4,
              alignment: Alignment.bottomRight,
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
            ),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 240),
              margin: const EdgeInsets.only(bottom: 6, right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          ),

        // The character: tap to make it react and talk.
        // NOTE: the 3D view is a WebView and swallows touches, so the model is
        // wrapped in IgnorePointer below and this detector owns the gestures.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(message, r.level),
          onLongPress: () => _playReaction(_Reaction.hop, 'jump'),
          child: SizedBox(
            height: widget.height,
            width: widget.height * 0.85,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Ground shadow squashes / fades as the character hops.
                Positioned(
                  bottom: 6,
                  child: AnimatedBuilder(
                    animation: _react,
                    builder: (context, _) {
                      final lift = _react.isAnimating
                          ? math.sin(_react.value * math.pi * 2).abs()
                          : 0.0;
                      return Opacity(
                        opacity: 1 - lift * 0.45,
                        child: Container(
                          width: widget.height * (0.42 - lift * 0.08),
                          height: widget.height * 0.09,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.elliptical(
                                widget.height * 0.21, widget.height * 0.045)),
                            gradient: RadialGradient(colors: [
                              Colors.black.withValues(alpha: 0.22),
                              Colors.black.withValues(alpha: 0.0),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // IgnorePointer lets taps pass through the WebView-backed 3D
                // view to the GestureDetector above.
                _animated(
                  IgnorePointer(
                    child: AvatarView(
                      size: widget.height,
                      circle: false,
                      animationName: RpmService.clipFor(_clip),
                    ),
                  ),
                ),

                // "Tap me" affordance until the user interacts once.
                if (!_interacted && !_talking)
                  Positioned(
                    bottom: 0,
                    child: AnimatedBuilder(
                      animation: _idle,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, -3 * math.sin(_idle.value * math.pi)),
                        child: child,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.indigo,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: AppTheme.softShadow,
                        ),
                        child: const Text('Tap me',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The character's repertoire of physical actions.
enum _Reaction { hop, nod, shake, wave, stretch, look, twirl, cheer }
