import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Proactive alert delivery (Chua Yi Zhe — Objective 3).
///
/// Raises a local notification plus a haptic nudge. On an iPhone paired with
/// an Apple Watch, iOS mirrors the notification to the watch, which delivers
/// it through the Taptic Engine — the non-intrusive wrist-based intervention
/// described in the report. On web/desktop (demo mode) it logs to the console.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> init() async {
    if (!_supported) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(const InitializationSettings(
          android: android, iOS: darwin, macOS: darwin));
      // Android 13+ needs a runtime permission on top of the manifest entry.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed (continuing without): $e');
    }
  }

  Future<void> show(String title, String body) async {
    debugPrint('🔔 NOTIFY: $title — $body');
    if (!_supported) return;

    // Haptic nudge on the phone; the paired Apple Watch delivers its own
    // Taptic tap when the mirrored notification arrives.
    HapticFeedback.heavyImpact();

    if (!_ready) return;
    await _plugin.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'cogload',
          'Cognitive Load Alerts',
          channelDescription:
              'Workload warnings and physiological readiness interventions',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
        ),
      ),
    );
  }
}
