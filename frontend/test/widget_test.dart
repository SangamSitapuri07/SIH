import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/app.dart';
import 'package:orca_app/core/cache/cache_service.dart';
import 'package:orca_app/features/advisory/presentation/screens/marine_advisory_screen.dart';

/// Shell-level smoke test for the redesigned ORCA workspace.
///
/// The app boots without any backend, so every screen has to render its honest
/// unavailable state instead of throwing or inventing data.
void main() {
  testWidgets('OrcaApp boots into the Command Center with the redesigned shell', (WidgetTester tester) async {
    final CacheService cache = CacheService();
    await cache.set('app.onboarding', <String, dynamic>{'complete': true});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cacheServiceProvider.overrideWithValue(cache),
        ],
        child: const OrcaApp(),
      ),
    );

    // Let providers start their requests and fail safely.
    await tester.pump(const Duration(milliseconds: 100));

    // Brand mark in the mobile header.
    expect(find.text('ORCA'), findsOneWidget);

    // Mobile navigation: Overview · Ask ORCA · Ocean map · Alerts · More.
    // 'Overview' and 'Ask ORCA' also appear as the screen title and as a hero
    // action, so each label is asserted to be present rather than unique.
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Ask ORCA'), findsWidgets);
    expect(find.text('Ocean map'), findsWidgets);
    expect(find.text('Alerts'), findsWidgets);
    expect(find.text('More'), findsWidgets);

    // The shell must not claim a live stream while nothing is connected.
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('Workspace sheet opens the safety advisory screen', (WidgetTester tester) async {
    final CacheService cache = CacheService();
    await cache.set('app.onboarding', <String, dynamic>{'complete': true});

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          cacheServiceProvider.overrideWithValue(cache),
        ],
        child: const OrcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('More'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ALL ORCA WORKSPACES'), findsOneWidget);

    await tester.tap(find.text('Safety advisory').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MarineAdvisoryScreen), findsOneWidget);
  });
}
