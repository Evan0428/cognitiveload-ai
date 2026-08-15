import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';

/// Renders the user's 3D avatar. Always 3D — profile circles, the assistant,
/// and the standing character all show the same live model.
///
/// [circle] clips it into a profile-picture circle; leave false for the
/// free-standing character so it isn't boxed into a window.
class AvatarView extends StatefulWidget {
  final double size;
  final bool circle;
  final Color? background;

  /// Let the user drag to rotate the model (editor preview). Off elsewhere so
  /// taps reach the widget instead of being eaten by the 3D view.
  final bool allowSpin;

  /// Slowly turn the model by itself. Only wanted in the editor preview — on
  /// the dashboard the character should face the user, not rotate.
  final bool autoRotate;

  /// Name of a built-in animation clip to play (models that ship clips, e.g.
  /// Robo's "Wave"/"Dance"). Ignored by models without animations.
  final String? animationName;

  /// Increment to make the character turn a full circle on the spot. The turn
  /// happens inside the 3D scene (the camera orbits the model), because a
  /// Flutter-side 3D transform cannot be applied to the WebView that hosts it.
  final int spinToken;

  /// How long one full turn takes, in milliseconds.
  final int spinDurationMs;

  /// Kept for call-site compatibility; every avatar is 3D now.
  final bool threeD;

  const AvatarView({
    super.key,
    this.size = 56,
    this.circle = true,
    this.background,
    this.allowSpin = false,
    this.autoRotate = false,
    this.animationName,
    this.spinToken = 0,
    this.spinDurationMs = 1100,
    this.threeD = true,
  });

  @override
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView> {
  WebViewController? _web;

  @override
  void didUpdateWidget(covariant AvatarView old) {
    super.didUpdateWidget(old);
    if (widget.animationName != old.animationName) _applyClip();
    if (widget.spinToken != old.spinToken && widget.spinToken > 0) _spin();
  }

  /// Turn the character a full 360° by orbiting the scene camera.
  ///
  /// Rotating on the Flutter side is not an option: the model is rendered in a
  /// WebView, and iOS cannot composite a platform view under a perspective or
  /// otherwise non-affine matrix — the whole avatar simply stops being drawn.
  /// The spin is therefore handed to the page, which owns a real 3D camera.
  /// One JavaScript call drives the entire turn with `requestAnimationFrame`,
  /// so the animation stays smooth without a per-frame bridge crossing.
  Future<void> _spin() async {
    final controller = _web;
    if (controller == null) return;
    try {
      await controller.runJavaScript('''
        (function () {
          var mv = document.querySelector('model-viewer');
          if (!mv || mv.__spinning) return;
          var orbit;
          try { orbit = mv.getCameraOrbit(); } catch (e) { return; }
          var deg = 180 / Math.PI;
          var start = orbit.theta * deg;
          var phi = orbit.phi * deg;
          var duration = ${widget.spinDurationMs};
          mv.__spinning = true;
          var t0 = null;
          function step(now) {
            if (t0 === null) t0 = now;
            var p = Math.min((now - t0) / duration, 1);
            // ease in-out, so the turn starts and settles softly
            var e = p < 0.5
              ? 2 * p * p
              : 1 - Math.pow(-2 * p + 2, 2) / 2;
            mv.cameraOrbit = (start + e * 360) + 'deg ' + phi + 'deg auto';
            if (p < 1) {
              requestAnimationFrame(step);
            } else {
              mv.__spinning = false;
            }
          }
          requestAnimationFrame(step);
        })();
      ''');
    } catch (_) {
      // Page not ready — skip this turn rather than break the reaction.
    }
  }

  /// Switch the playing clip *inside* the viewer that is already on screen.
  ///
  /// `ModelViewer` builds its HTML once in `initState` and has no
  /// `didUpdateWidget`, so the only way to change a prop used to be to change
  /// the widget key — which tore down the local HTTP proxy and the WebView and
  /// re-downloaded the model, blanking the avatar for several seconds every
  /// time it reacted. Driving the live `<model-viewer>` element instead keeps
  /// the character on screen throughout.
  Future<void> _applyClip() async {
    final controller = _web;
    final name = widget.animationName;
    if (controller == null || name == null) return;
    try {
      await controller.runJavaScript('''
        (function () {
          var mv = document.querySelector('model-viewer');
          if (!mv) return;
          mv.setAttribute('animation-name', ${jsonEncode(name)});
          try { mv.play(); } catch (e) {}
        })();
      ''');
    } catch (_) {
      // Page not ready yet — the attribute in the initial HTML still applies.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: RpmService.avatarUrl,
      builder: (context, _, __) {
        final src = RpmService.effectiveUrl;
        final isRpm = src.contains('readyplayer.me');

        final model = ModelViewer(
          // Only a different character forces a reload; clip changes are
          // applied in place by [_applyClip] so the model never blinks out.
          key: ValueKey(src),
          src: src,
          animationName: widget.animationName,
          alt: 'Your 3D avatar',
          autoRotate: widget.autoRotate, // dashboard character faces the user
          cameraControls:
              widget.allowSpin, // drag-to-spin only in the editor preview
          disableZoom: true,
          autoPlay: true, // play the model's built-in animation
          // RPM avatars are full-body → frame head/shoulders for profile pics.
          cameraOrbit: isRpm && widget.circle ? '0deg 78deg 2.2m' : null,
          cameraTarget: isRpm && widget.circle ? '0m 1.5m 0m' : null,
          backgroundColor: const Color(0x00000000),
          onWebViewCreated: (controller) => _web = controller,
        );

        if (!widget.circle) {
          return SizedBox(width: widget.size, height: widget.size, child: model);
        }

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.background ?? AppTheme.surfaceAlt,
          ),
          child: ClipOval(child: model),
        );
      },
    );
  }
}
