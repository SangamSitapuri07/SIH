import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback invoked when the user taps a marine alert notification.
/// Wired by the app shell to navigate to the alerts screen.
void Function(String payload)? onAlertNotificationTap;

/// Local notification service for proactive marine safety alerts.
///
/// Phase B: the app already renders live `alert.push` SSE events in the
/// alerts feed while foregrounded; this service additionally surfaces them
/// as OS notifications so a fisherman sees a NO-GO / cyclone warning even
/// when the app is in the background.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        debugPrint('[Notifications] Tapped: $payload');
        if (payload != null && payload.isNotEmpty) {
          onAlertNotificationTap?.call(payload);
        }
      },
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android 13+ requires a runtime permission grant for notifications.
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  /// Shows a marine alert notification. [id] keeps one notification per
  /// alert id; higher-severity alerts use max importance with heads-up.
  Future<void> showAlertNotification({
    required String id,
    required String title,
    required String body,
    String severity = 'warning',
  }) async {
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'orca_alerts',
      'Marine Safety Alerts',
      channelDescription: 'ORCA proactive verdict-change and cyclone warnings',
      importance: Importance.max,
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);

    try {
      await _plugin.show(id.hashCode, title, body, details, payload: id);
    } catch (e) {
      debugPrint('[Notifications] Show failed: $e');
    }
  }
}
