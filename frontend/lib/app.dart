import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'main.dart' show appAlertTapHandler;
import 'core/cache/cache_service.dart';
import 'core/theme/orca_theme.dart';
import 'core/widgets/orca_navigation.dart';
import 'features/advisory/presentation/screens/home_screen.dart';
import 'features/advisory/presentation/screens/marine_advisory_screen.dart';
import 'features/agents/presentation/screens/ai_screen.dart';
import 'features/alerts/presentation/providers/alerts_provider.dart';
import 'features/alerts/presentation/screens/alerts_screen.dart';
import 'features/auth/presentation/screens/profile_screen.dart';
import 'features/catch_reports/presentation/screens/catch_report_screen.dart';
import 'features/history/presentation/screens/history_screen.dart';
import 'features/locations/presentation/screens/saved_locations_screen.dart';
import 'features/map/presentation/screens/map_screen.dart';
import 'features/navigate/presentation/screens/navigate_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/settings/presentation/screens/info_screen.dart';
import 'l10n/app_localizations.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final onboarding = ref.watch(cacheServiceProvider).get('app.onboarding')?.data['complete'] == true;
  final router = GoRouter(
    initialLocation: onboarding ? '/home' : '/onboarding',
    routes: [
      ShellRoute(
        builder: (context, state, child) => OrcaNavigationScaffold(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
          GoRoute(path: '/advisory', builder: (_, __) => const MarineAdvisoryScreen()),
          GoRoute(path: '/ai', builder: (_, __) => const AiScreen()),
          GoRoute(path: '/alerts', builder: (_, __) => const AlertsScreen()),
          GoRoute(path: '/navigate', builder: (_, __) => const NavigateScreen()),
          GoRoute(path: '/info', builder: (_, __) => const InfoScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/locations', builder: (_, __) => const SavedLocationsScreen()),
          GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
          GoRoute(path: '/catch-report', builder: (_, __) => const CatchReportScreen()),
        ],
      ),
      GoRoute(path: '/onboarding', builder: (context, _) => OnboardingScreen(onFinish: () => context.go('/home'))),
    ],
  );
  appAlertTapHandler = (_) => router.go('/alerts');
  return router;
});

class OrcaApp extends ConsumerWidget {
  const OrcaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'ORCA Marine Intelligence',
    debugShowCheckedModeBanner: false,
    theme: OrcaTheme.theme,
    routerConfig: ref.watch(routerProvider),
    locale: Locale(ref.watch(selectedLocaleProvider)),
    supportedLocales: const [Locale('en'), Locale('hi'), Locale('te')],
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
  );
}

/// Adaptive shell: a compact sidebar with a broad workspace on desktop, and a
/// focused four-tab bottom bar plus a workspace sheet on mobile. The mobile
/// layout is deliberately not a shrunken sidebar.
class OrcaNavigationScaffold extends ConsumerWidget {
  final Widget child;
  const OrcaNavigationScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final alertCount = ref.watch(alertsProvider).valueOrNull?.length ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > OrcaTheme.mobileBreakpoint) {
          return Scaffold(
            backgroundColor: OrcaTheme.background,
            body: Row(
              children: <Widget>[
                OrcaSidebar(location: location, alertCount: alertCount),
                const VerticalDivider(width: 1, color: OrcaTheme.cardBorder),
                Expanded(child: child),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: OrcaTheme.background,
          body: child,
          bottomNavigationBar: OrcaMobileNavBar(
            location: location,
            alertCount: alertCount,
            onMore: () => showOrcaWorkspaceSheet(context, location),
          ),
        );
      },
    );
  }
}
