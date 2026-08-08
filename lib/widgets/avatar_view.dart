import 'package:flutter/material.dart';
import 'package:fluttermoji/fluttermoji.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';

/// Unified avatar renderer.
///
/// - If the user has a Ready Player Me 3D avatar: shows its 2D portrait render
///   (cheap) for small circles, or the interactive 3D model when [threeD].
/// - Otherwise falls back to the fluttermoji cartoon, so the app always shows
///   *something* even before an RPM avatar is created.
class AvatarView extends StatelessWidget {
  final double size;
  final bool threeD;
  final Color? background;

  const AvatarView({
    super.key,
    this.size = 56,
    this.threeD = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: RpmService.avatarUrl,
      builder: (context, url, _) {
        // 3D view is ALWAYS 3D: the user's own model if they made one,
        // otherwise a ready-made 3D character (never a flat cartoon).
        if (threeD) {
          final src = (url != null && url.isNotEmpty)
              ? url
              : RpmService.defaultCharacterUrl;
          final isRpm = src.contains('readyplayer.me');
          return SizedBox(
            width: size,
            height: size,
            child: ModelViewer(
              src: src,
              alt: 'Your 3D avatar',
              autoRotate: true,
              cameraControls: true,
              disableZoom: true,
              autoPlay: true, // play the character's built-in animation
              // RPM avatars are full-body → frame the head/upper body.
              cameraOrbit: isRpm ? '0deg 78deg 2.2m' : null,
              cameraTarget: isRpm ? '0m 1.5m 0m' : null,
              backgroundColor: const Color(0x00000000),
            ),
          );
        }

        if (url == null || url.isEmpty) {
          return FluttermojiCircleAvatar(
              radius: size / 2, backgroundColor: background ?? AppTheme.surfaceAlt);
        }
        // Small circle → RPM's free 2D portrait render.
        final portrait = RpmService.portraitUrl(url, size: (size * 2).round());
        return ClipOval(
          child: Container(
            width: size,
            height: size,
            color: background ?? AppTheme.surfaceAlt,
            child: portrait == null
                ? FluttermojiCircleAvatar(radius: size / 2)
                : Image.network(
                    portrait,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, prog) => prog == null
                        ? child
                        : const Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                    errorBuilder: (c, e, s) =>
                        FluttermojiCircleAvatar(radius: size / 2),
                  ),
          ),
        );
      },
    );
  }
}
