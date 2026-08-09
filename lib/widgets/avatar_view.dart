import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../services/rpm_service.dart';
import '../theme/app_theme.dart';

/// Renders the user's 3D avatar. Always 3D — profile circles, the assistant,
/// and the standing character all show the same live model.
///
/// [circle] clips it into a profile-picture circle; leave false for the
/// free-standing character so it isn't boxed into a window.
class AvatarView extends StatelessWidget {
  final double size;
  final bool circle;
  final Color? background;

  /// Let the user drag to rotate the model (editor preview). Off elsewhere so
  /// taps reach the widget instead of being eaten by the 3D view.
  final bool allowSpin;

  /// Kept for call-site compatibility; every avatar is 3D now.
  final bool threeD;

  const AvatarView({
    super.key,
    this.size = 56,
    this.circle = true,
    this.background,
    this.allowSpin = false,
    this.threeD = true,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: RpmService.avatarUrl,
      builder: (context, _, __) {
        final src = RpmService.effectiveUrl;
        final isRpm = src.contains('readyplayer.me');

        final model = ModelViewer(
          key: ValueKey(src), // reload when the user picks another character
          src: src,
          alt: 'Your 3D avatar',
          autoRotate: !circle, // free-standing character slowly turns
          cameraControls: allowSpin, // drag-to-spin only in the editor preview
          disableZoom: true,
          autoPlay: true, // play the model's built-in animation
          // RPM avatars are full-body → frame head/shoulders for profile pics.
          cameraOrbit: isRpm && circle ? '0deg 78deg 2.2m' : null,
          cameraTarget: isRpm && circle ? '0m 1.5m 0m' : null,
          backgroundColor: const Color(0x00000000),
        );

        if (!circle) {
          return SizedBox(width: size, height: size, child: model);
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background ?? AppTheme.surfaceAlt,
          ),
          child: ClipOval(child: model),
        );
      },
    );
  }
}
