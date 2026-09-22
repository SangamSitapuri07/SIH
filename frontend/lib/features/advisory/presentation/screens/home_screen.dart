import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/supabase_auth_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../alerts/domain/entities/alert_item.dart';
import '../../../alerts/presentation/providers/alerts_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../locations/presentation/widgets/working_location_sheet.dart';
import '../../../map/presentation/providers/map_provider.dart';
import '../../../command_center/data/datasources/command_center_remote.dart';
import '../../../command_center/data/dto/command_center_dto.dart';
import '../../domain/entities/advisory.dart';
import '../providers/advisory_provider.dart';
import '../../../command_center/presentation/widgets/command_center_widgets.dart';
import '../../../command_center/presentation/widgets/map_preview_card.dart';

/// Command Center (Overview): the decision-first morning brief.
///
/// Every value on this screen comes from `/api/v1/advisory`, `/api/v1/zone`,
/// `/api/v1/health`, `/api/v1/alerts` or `/api/v1/grid`. When a request fails,
/// or a provider is silent, the screen states that explicitly — there are no
/// fixture values and no invented confidence score.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CommandCenterData> command = ref.watch(commandCenterProvider);
    final AsyncValue<AdvisoryEntity> advisoryState = ref.watch(advisoryProvider);
    final AsyncValue<List<AlertItem>> alertsState = ref.watch(alertsProvider);
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;
    final UserProfile profile = ref.watch(userProfileProvider);
    final Map<String, double> coords = ref.watch(advisoryLocationProvider);

    final double lat = coords['lat'] ?? AppConfig.defaultLat;
    final double lon = coords['lon'] ?? AppConfig.defaultLon;
    final MapCenter center = MapCenter(lat, lon);

    final CommandCenterData? data = command.valueOrNull;
    final AdvisoryEntity? advisory = advisoryState.valueOrNull;
    final List<AlertItem> alerts = alertsState.valueOrNull ?? const <AlertItem>[];

    final String coordinateLabel = GeoUtils.formatCoordinate(lat, lon);
    final String locationLabel = _locationLabel(profile);

    Future<void> refresh() async {
      await Future.wait(<Future<void>>[
        ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
        ref.read(commandCenterProvider.notifier).refresh(),
        ref.read(alertsProvider.notifier).fetch(forceRefresh: true),
      ]);
    }

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.tabHome ?? 'Home',
      subtitle: 'Morning brief',
      locationLabel: locationLabel,
      coordinateLabel: coordinateLabel,
      updatedAt: data?.updatedAt ?? advisory?.timestamp,
      stateLabel: data?.health?.overall.replaceAll('_', ' '),
      onRefresh: refresh,
      onLocationTap: () => showWorkingLocationSheet(context),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;

          final Widget verdictPanel = CommandCenterVerdictPanel(
            advisory: advisory,
            error: advisoryState.error,
            isLoading: advisoryState.isLoading,
            locationLabel: locationLabel,
            coordinateLabel: coordinateLabel,
            onOpenAdvisory: () => context.go('/advisory'),
            narrow: !twoColumn,
          );
          final Widget conditionsCard = CommandCenterConditionsCard(
            conditions: data?.conditions,
            advisory: advisory,
            isLoading: command.isLoading,
            errorMessage: command.error?.toString(),
            columns: 2,
          );
          final Widget signalsCard = CommandCenterSignalsCard(
            alerts: alerts,
            feedAvailable: data?.cycloneFeedAvailable ?? alertsState.hasValue,
            isLoading: alertsState.isLoading,
            narrow: !twoColumn,
            onViewAll: () => context.go('/alerts'),
          );
          final Widget mapPreview = CommandCenterMapPreview(
            lat: center.lat,
            lon: center.lon,
            onOpenMap: () => context.go('/map'),
          );
          final Widget windowCard = CommandCenterWindowCard(
            advisory: advisory,
            isLoading: advisoryState.isLoading,
          );
          final Widget trustCard = CommandCenterSourceHealthCard(
            health: data?.health,
            isLoading: command.isLoading,
          );
          final Widget agentCard = CommandCenterAgentStatusCard(onOpenAgents: () => context.go('/ai'));
          final Widget guideCard = CommandCenterGuideCard(
            title: 'Plan with the evidence',
            message:
                'Route safety samples real marine inputs along the leg and clears land only when a verified land-mask source answers. The reasoning workspace shows the per-agent trace behind this brief.',
            icon: Icons.route_outlined,
            actionLabel: 'Plan a trip',
            onAction: () => context.go('/navigate'),
          );

          Widget pair(Widget left, Widget right, {int leftFlex = 6, int rightFlex = 5}) {
            if (!twoColumn) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  left,
                  const SizedBox(height: 14),
                  right,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: leftFlex, child: left),
                const SizedBox(width: 18),
                Expanded(flex: rightFlex, child: right),
              ],
            );
          }

          return RefreshIndicator(
            onRefresh: refresh,
            color: OrcaTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: orcaContentPadding(wide: twoColumn),
              children: <Widget>[
                _StateNotices(
                  online: online,
                  streamLive: streamLive,
                  cached: data?.cached ?? false,
                  stale: data?.stale ?? false,
                  advisoryStale: advisory?.staleness.state == StalenessState.stale,
                ),
                CommandCenterBrief(
                  displayName: profile.displayName,
                  harbour: profile.homeHarbour,
                  narrow: !twoColumn,
                  onAskOrca: () => context.go('/ai'),
                  onPlanRoute: () => context.go('/navigate'),
                ),
                const SizedBox(height: 22),
                pair(verdictPanel, conditionsCard),
                const SizedBox(height: 22),
                pair(signalsCard, mapPreview),
                const SizedBox(height: 22),
                pair(trustCard, windowCard),
                const SizedBox(height: 22),
                pair(agentCard, guideCard),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _locationLabel(UserProfile profile) {
    final String harbour = profile.homeHarbour.trim();
    if (harbour.isNotEmpty) return harbour;
    return 'Working location';
  }
}

class _StateNotices extends StatelessWidget {
  final bool online;
  final bool streamLive;
  final bool cached;
  final bool stale;
  final bool advisoryStale;

  const _StateNotices({
    required this.online,
    required this.streamLive,
    required this.cached,
    required this.stale,
    required this.advisoryStale,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> notices = <Widget>[
      if (!online)
        const OrcaNotice(
          icon: Icons.wifi_off_rounded,
          title: 'Offline.',
          message: 'ORCA is showing the last payload stored on this device. Check the retrieval time before relying on it.',
          color: VerdictColors.caution,
          trailingLabel: 'OFFLINE',
        )
      else if (stale || advisoryStale)
        const OrcaNotice(
          icon: Icons.schedule_rounded,
          title: 'Stale data.',
          message: 'The last refresh did not complete, so these values may be out of date.',
          color: VerdictColors.caution,
          trailingLabel: 'STALE',
        )
      else if (cached)
        const OrcaNotice(
          icon: Icons.history_rounded,
          title: 'Cached payload.',
          message: 'Showing the last ORCA Box snapshot while a fresh request completes.',
          color: OrcaTheme.accentDark,
          trailingLabel: 'CACHED',
        )
      else if (!streamLive)
        const OrcaNotice(
          icon: Icons.cloud_sync_outlined,
          title: 'Live channel not connected.',
          message: 'Values below come from direct ORCA Box requests; the SSE live channel is not open, so nothing here is presented as live.',
          color: OrcaTheme.accentDark,
          trailingLabel: 'NO LIVE CHANNEL',
        ),
    ];

    if (notices.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        children: <Widget>[
          for (int index = 0; index < notices.length; index++) ...<Widget>[
            notices[index],
            if (index != notices.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
