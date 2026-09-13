import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'bootstrap.dart';
import 'core/notifications/notification_service.dart';

/// Global hook set by [OrcaApp] once the GoRouter is available, so a
/// notification tap can deep-link to the alerts screen.
void Function(String payload)? appAlertTapHandler;

/// Application bootstrap entry point (§10).
Future<void> main() async {
  final container = await bootstrap();

  // Proactive alert notifications (Phase B): initialized before the first
  // frame so an alert arriving during startup is never missed.
  await NotificationService.instance.init();
  onAlertNotificationTap = (payload) => appAlertTapHandler?.call(payload);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OrcaApp(),
    ),
  );
}
