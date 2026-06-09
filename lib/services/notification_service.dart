import 'package:flutter/foundation.dart';

/// Wraps local notifications (workload warnings) and haptic feedback
/// (Apple Watch Taptic Engine on device). Kept dependency-light so the
/// project compiles and runs in demo mode without platform channels.
class NotificationService {
  Future<void> init() async {
    // ----- REAL DEVICE IMPLEMENTATION (uncomment on device) -----
    // final plugin = FlutterLocalNotificationsPlugin();
    // const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // const ios = DarwinInitializationSettings();
    // await plugin.initialize(const InitializationSettings(
    //     android: android, iOS: ios));
    // ------------------------------------------------------------
  }

  Future<void> show(String title, String body) async {
    // In demo mode we log; on device this raises a notification + haptic.
    debugPrint('🔔 NOTIFY: $title — $body');

    // ----- REAL DEVICE IMPLEMENTATION (uncomment on device) -----
    // await plugin.show(0, title, body, const NotificationDetails(
    //   android: AndroidNotificationDetails('cogload', 'Cognitive Load Alerts',
    //       importance: Importance.high, priority: Priority.high),
    //   iOS: DarwinNotificationDetails(),
    // ));
    // HapticFeedback.heavyImpact(); // Taptic Engine on Apple Watch
    // ------------------------------------------------------------
  }
}
