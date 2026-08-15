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
