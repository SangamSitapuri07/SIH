import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_app_bar.dart';
import '../../../../core/widgets/source_footer.dart';
import '../../../../core/live/live_channel.dart';
import '../../domain/entities/advisory.dart';
import '../providers/advisory_provider.dart';
import '../widgets/hourly_chart.dart';
import '../widgets/safe_window_bar.dart';
import '../widgets/variables_grid.dart';
import '../widgets/verdict_card.dart';
import '../widgets/voice_advisory_button.dart';
import '../../../command_center/data/datasources/command_center_remote.dart';
import '../../../command_center/data/dto/command_center_dto.dart';
import '../../../command_center/presentation/widgets/command_center_widgets.dart';

/// Home = Command Center. Answers "what is happening in the marine
/// environment right now?" using only real backend data, then keeps the
/// full advisory detail below.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advisoryState = ref.watch(advisoryProvider);
    final ccState = ref.watch(commandCenterProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final liveStatus = ref.watch(liveChannelProvider);
    final pendingSyncOps = ref.watch(syncManagerProvider)
        .where((op) =>
            op.status == SyncStatus.pending ||
            op.status == SyncStatus.retrying)
        .length;

    final cc = ccState.valueOrNull;
    final advisory = advisoryState.valueOrNull;

    return Scaffold(
      appBar: OrcaAppBar(
        title: 'ORCA',
        subtitle: 'Marine Intelligence · Command Center',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CcSystemStatusChip(
              overall: _overallStatus(cc, isOnline),
              live: liveStatus == LiveStreamStatus.connected,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(commandCenterProvider.notifier).refresh(),
            ref.read(advisoryProvider.notifier).fetch(forceRefresh: true),
          ]);
        },
        color: OrcaTheme.accent,
        backgroundColor: OrcaTheme.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Offline notice banner (§14) — honest cached-data labeling.
              if (!isOnline || (cc?.offline ?? false)) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: VerdictColors.cautionBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: VerdictColors.caution.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off,
                          color: VerdictColors.caution, size: 17),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pendingSyncOps > 0
                              ? 'Offline — showing last available data. $pendingSyncOps change${pendingSyncOps == 1 ? '' : 's'} queued for sync.'
                              : 'Offline — showing last available data.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: OrcaTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // HERO: marine risk, from the real advisory verdict + zone data.
              CcHeroRiskCard(
                verdict: advisory?.verdict,
                locationLabel: _locationLabel(ref),
                waveM: cc?.conditions?.waveHeightM,
                windKn: cc?.conditions?.windKn,
                gustKn: cc?.conditions?.windGustKn,
              ),

              // Fishing intelligence (real PFZ).
              const CcSectionHeader(title: 'Right now'),
              CcFishingCard(
                pfzCount: cc?.conditions?.pfzCount ?? 0,
                pfzSource: cc?.conditions?.pfzSource,
                onOpenMap: () => context.go('/map'),
              ),
              const SizedBox(height: 10),
              CcWeatherCard(conditions: cc?.conditions),
              const SizedBox(height: 10),
              CcCycloneCard(alerts: cc?.cycloneWatch ?? const []),

              // Data provenance (§22/§23) — real source health.
              const CcSectionHeader(title: 'Data sources'),
              CcSourceHealthCard(health: cc?.health),

              // Advisory detail (deterministic engine result + reasoning).
              const CcSectionHeader(title: 'Your advisory'),
              advisoryState.when(
                data: (AdvisoryEntity advisory) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerdictCard(advisory: advisory),
                    const SizedBox(height: 12),
                    VoiceAdvisoryButton(advisory: advisory),
                    const SizedBox(height: 12),
                    SafeWindowBar(safeWindow: advisory.safeWindow),
                    const SizedBox(height: 14),
                    VariablesGrid(variables: advisory.variables),
                    const SizedBox(height: 14),
                    HourlyChart(hourlyPoints: advisory.hourlyChart),
                    const SizedBox(height: 14),
                    SourceFooter(
                      sources: advisory.sources,
                      timeLabel:
                          DateFormatter.formatIstTime(advisory.timestamp),
                    ),
                  ],
                ),
                loading: () => _AdvisoryLoadingPlaceholder(
                    hasData: advisory != null),
                error: (error, _) => _AdvisoryErrorCard(
                  message: error.toString(),
                  onRetry: () => ref
                      .read(advisoryProvider.notifier)
                      .fetch(forceRefresh: true),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _overallStatus(CommandCenterData? cc, bool isOnline) {
    if (!isOnline) return 'OFFLINE';
    final h = cc?.health;
    if (h == null) return 'CHECKING';
    return h.overall;
  }

  String _locationLabel(WidgetRef ref) {
    final coords = ref.read(advisoryLocationProvider);
    final lat = coords['lat'] ?? 0.0;
    final lon = coords['lon'] ?? 0.0;
    final ns = lat >= 0 ? 'N' : 'S';
    final ew = lon >= 0 ? 'E' : 'W';
    return '${lat.abs().toStringAsFixed(2)}°$ns · ${lon.abs().toStringAsFixed(2)}°$ew';
  }
}

class _AdvisoryLoadingPlaceholder extends StatelessWidget {
  final bool hasData;
  const _AdvisoryLoadingPlaceholder({required this.hasData});

  @override
  Widget build(BuildContext context) {
    if (hasData) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: const Column(
        children: [
          CircularProgressIndicator(color: OrcaTheme.accent),
          SizedBox(height: 14),
          Text(
            'ORCA is analyzing the sea...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: OrcaTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvisoryErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AdvisoryErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VerdictColors.critical.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: VerdictColors.critical, size: 34),
          const SizedBox(height: 10),
          const Text(
            'Marine data temporarily unavailable',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: OrcaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message.length > 140 ? '${message.substring(0, 140)}…' : message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: OrcaTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
