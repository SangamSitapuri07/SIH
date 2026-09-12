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
import '../providers/advisory_provider.dart';
import '../widgets/hourly_chart.dart';
import '../widgets/safe_window_bar.dart';
import '../widgets/variables_grid.dart';
import '../widgets/verdict_card.dart';
import '../widgets/voice_advisory_button.dart';

/// Primary Fisher Safety Home Screen (§8, §26A, Phase 2).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final advisoryState = ref.watch(advisoryProvider);
    final isOnline = ref.watch(isOnlineProvider);
    final pendingSyncOps = ref.watch(syncManagerProvider).where((op) => op.status == SyncStatus.pending || op.status == SyncStatus.retrying).length;

    return Scaffold(
      appBar: const OrcaAppBar(
        title: 'ORCA ADVISORY',
        subtitle: 'Marine Safety & Weather Intelligence',
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(advisoryProvider.notifier).fetch(forceRefresh: true);
        },
        color: OrcaTheme.accent,
        backgroundColor: OrcaTheme.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Offline notice banner if disconnected (§14)
              if (!isOnline) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: VerdictColors.cautionBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: VerdictColors.caution, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, color: VerdictColors.caution, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pendingSyncOps > 0
                              ? 'Offline mode active. $pendingSyncOps changes queued for cloud sync.'
                              : 'You are offline. Showing last verified advisory from cache.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Phase 2 Fisher Services Quick Access Grid
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    _buildQuickActionButton(
                      context,
                      label: 'My Places',
                      icon: Icons.place,
                      color: Colors.blue,
                      onTap: () => context.push('/locations'),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionButton(
                      context,
                      label: 'Catch Report',
                      icon: Icons.phishing,
                      color: VerdictColors.go,
                      onTap: () => context.push('/catch-report'),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionButton(
                      context,
                      label: 'History',
                      icon: Icons.history,
                      color: Colors.amber,
                      onTap: () => context.push('/history'),
                    ),
                    const SizedBox(width: 8),
                    _buildQuickActionButton(
                      context,
                      label: 'Profile',
                      icon: Icons.person,
                      color: Colors.purpleAccent,
                      onTap: () => context.push('/profile'),
                    ),
                  ],
                ),
              ),

              // Main advisory state handling
              advisoryState.when(
                data: (advisory) => Column(
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
                      timeLabel: DateFormatter.formatIstTime(advisory.timestamp),
                    ),
                  ],
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: OrcaTheme.accent),
                        SizedBox(height: 16),
                        Text(
                          'ORCA is analyzing the sea...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Checking ocean conditions\nChecking weather hazards\nAnalyzing satellite information\nPreparing your safety advisory',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: OrcaTheme.textSecondary,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                error: (error, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color: OrcaTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: VerdictColors.critical, width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: VerdictColors.critical, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Unable to load advisory',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          ref.read(advisoryProvider.notifier).fetch(forceRefresh: true);
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OrcaTheme.accent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
