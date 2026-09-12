// ignore: unused_import
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/app.dart';
import 'package:orca_app/core/cache/cache_service.dart';
import 'package:orca_app/core/widgets/orca_app_bar.dart';

void main() {
  testWidgets('OrcaApp boots successfully with 6 tabs and Home as initial screen', (tester) async {
    final cache = CacheService();
    await cache.set('app.onboarding', <String, dynamic>{'complete': true});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheServiceProvider.overrideWithValue(cache),
          demoModeProvider.overrideWith((ref) => true),
        ],
        child: const OrcaApp(),
      ),
    );

    // Allow mock fixtures and providers to resolve
    await tester.pumpAndSettle();

    // Verify AppBar Title
    expect(find.text('ORCA ADVISORY'), findsOneWidget);

    // Verify 6 Bottom Navigation destinations exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    expect(find.text('AI Trace'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Navigate'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);

    // Tap on AI Trace Tab
    await tester.tap(find.text('AI Trace'));
    await tester.pumpAndSettle();
    expect(find.text('ORCA AI AGENTS'), findsOneWidget);

    // Tap on Alerts Tab
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('MARINE ALERTS'), findsOneWidget);

    // Tap on Navigate Tab
    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE NAVIGATION'), findsOneWidget);

    // Tap on Info Tab
    await tester.tap(find.text('Info'));
    await tester.pumpAndSettle();
    expect(find.text('SYSTEM & DATA HEALTH'), findsOneWidget);
  });
}
