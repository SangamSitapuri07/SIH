import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';
import '../providers/advisory_provider.dart';
import '../widgets/advisory_audio_notice.dart';
import '../widgets/advisory_provenance_card.dart';
import '../widgets/hourly_chart.dart';
import '../widgets/safe_window_bar.dart';
import '../widgets/variables_grid.dart';
import '../widgets/verdict_card.dart';

/// Safety advisory workspace.
///
/// The deterministic verdict and its evidence come first; provenance, cache
/// state and the unavailable-provider list sit beside them so the decision can
/// be audited. No recommendation is written by the client.
class MarineAdvisoryScreen extends ConsumerWidget {
  const MarineAdvisoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AdvisoryEntity> advisoryState = ref.watch(advisoryProvider);
    final AdvisoryEntity? advisory = advisoryState.valueOrNull;
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;
    final Map<String, double> coords = ref.watch(advisoryLocationProvider);
    final double lat = coords['lat'] ?? AppConfig.defaultLat;
    final double lon = coords['lon'] ?? AppConfig.defaultLon;

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.canIGoTitle ?? 'Safety advisory',
      subtitle: 'Deterministic verdict and evidence',
      locationLabel: 'Working location',
      coordinateLabel: GeoUtils.formatCoordinate(lat, lon),
      updatedAt: advisory?.timestamp,
      stateLabel: advisory == null ? null : (advisory.staleness.isCached ? 'CACHED' : 'CURRENT'),
      onRefresh: () => ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;

          final Widget body = RefreshIndicator(
            onRefresh: () => ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
            color: OrcaTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: orcaContentPadding(wide: twoColumn),
              children: <Widget>[
                if (!online)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: OrcaNotice(
                      icon: Icons.wifi_off_rounded,
                      title: 'Offline.',
                      message: 'The advisory below is the last payload stored on this device.',
                      color: VerdictColors.caution,
                      trailingLabel: 'OFFLINE',
                    ),
                  ),
                ...advisoryState.when(
                  loading: () => <Widget>[const _LoadingState()],
                  error: (Object? error, StackTrace? stack) => <Widget>[
                    OrcaUnavailable(
                      icon: Icons.cloud_off_outlined,
                      title: 'Marine advisory unavailable',
                      message: '$error\nThe ORCA Box could not assemble the safety inputs needed for a verdict. No verdict is shown.',
                      actionLabel: 'Retry',
                      onAction: () => ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
                    ),
                  ],
                  data: (AdvisoryEntity data) {
                    final Widget left = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const OrcaEyebrow('SAFETY DECISION', color: OrcaTheme.accentDark),
                        const SizedBox(height: 10),
                        VerdictCard(advisory: data),
                        const SizedBox(height: 22),
                        const OrcaSectionHeader(
                          title: 'Verified risk factors',
                          subtitle: 'Each value carries the provider and provider time it came from.',
                        ),
                        const SizedBox(height: 12),
                        VariablesGrid(variables: data.variables, columns: twoColumn ? 2 : 2),
                        const SizedBox(height: 22),
                        HourlyChart(hourlyPoints: data.hourlyChart),
                      ],
                    );

                    final Widget right = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SafeWindowBar(safeWindow: data.safeWindow),
                        const SizedBox(height: 16),
                        AdvisoryProvenanceCard(
                          advisory: data,
                          offline: !online,
                          streamLive: streamLive,
                        ),
                        const SizedBox(height: 16),
                        AdvisoryAudioNotice(advisory: data),
                        const SizedBox(height: 16),
                        OrcaCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const OrcaEyebrow('NEXT ACTIONS', color: OrcaTheme.textMuted),
                              const SizedBox(height: 10),
                              OrcaPillButton(
                                label: 'Check a route',
                                icon: Icons.route_outlined,
                                onPressed: () => context.go('/navigate'),
                              ),
                              const SizedBox(height: 8),
                              OrcaPillButton(
                                label: 'Inspect on the ocean map',
                                icon: Icons.map_outlined,
                                onPressed: () => context.go('/map'),
                              ),
                              const SizedBox(height: 8),
                              OrcaPillButton(
                                label: 'See the agent evidence',
                                icon: Icons.forum_outlined,
                                primary: true,
                                onPressed: () => context.go('/ai'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );

                    if (!twoColumn) {
                      return <Widget>[left, const SizedBox(height: 22), right];
                    }
                    return <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 6, child: left),
                          const SizedBox(width: 20),
                          Expanded(flex: 4, child: right),
                        ],
                      ),
                    ];
                  },
                ),
              ],
            ),
          );

          return body;
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'ORCA is assembling verified marine inputs for this coordinate…',
                style: OrcaType.body.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
}
