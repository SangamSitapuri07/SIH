import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/localization/language_options.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../../core/widgets/toast.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../widgets/server_config_dialog.dart';

/// System health and data provenance.
///
/// Every row is an observation the ORCA Box actually reported. Providers the
/// deployment did not configure are listed as such instead of being hidden, and
/// cache freshness is read from the stored record rather than assumed.
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  static const List<String> _cachedKeys = <String>[
    'command_center.latest',
    'advisory.latest',
    'alerts.latest',
    'reasoning.latest',
    'health.latest',
    'settings.locale',
    'alerts.reviewed',
    'profile',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String baseUrl = ref.watch(baseUrlProvider);
    final AsyncValue<SystemHealthSnapshot> healthState = ref.watch(healthProvider);
    final CacheService cache = ref.watch(cacheServiceProvider);
    final String language = ref.watch(selectedLocaleProvider);
    final List<SyncOperation> outbox = ref.watch(syncManagerProvider);
    final SystemHealthSnapshot? health = healthState.valueOrNull;

    final int operational = health == null
        ? 0
        : health.dataSources.values
            .where((SourceHealthItem item) => _isUsable(item.status))
            .length;

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.infoTitle ?? 'Data sources',
      subtitle: 'Provider health, cache freshness and recovery',
      locationLabel: 'ORCA Box',
      coordinateLabel: baseUrl,
      updatedAt: health?.timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(health!.timestamp! * 1000, isUtc: true),
      stateLabel: health == null
          ? 'HEALTH UNAVAILABLE'
          : '$operational/${health.dataSources.length} USABLE',
      onRefresh: () => ref.read(healthProvider.notifier).checkHealth(),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;

          final Widget providers = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              OrcaSectionHeader(
                title: 'Provider health',
                subtitle: health == null
                    ? 'The ORCA Box health endpoint did not answer'
                    : 'Status, latency and last observation reported by ${baseUrl}',
                actionLabel: 'Re-check',
                onAction: () => ref.read(healthProvider.notifier).checkHealth(),
              ),
              const SizedBox(height: 12),
              healthState.when(
                data: (SystemHealthSnapshot snapshot) => snapshot.dataSources.isEmpty
                    ? const OrcaUnavailable(
                        icon: Icons.dns_outlined,
                        title: 'No providers reported',
                        message: 'The health response contained no data source entries, so no provider state can be shown.',
                        compact: true,
                      )
                    : Column(
                        children: <Widget>[
                          for (final SourceHealthItem item in snapshot.dataSources.values)
                            _SourceTile(item: item),
                        ],
                      ),
                loading: () => const OrcaCard(
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Requesting provider status from the ORCA Box…',
                          style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: OrcaTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                error: (Object? error, StackTrace? stack) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OrcaUnavailable(
                      icon: Icons.cloud_off_outlined,
                      title: 'System health unavailable',
                      message: '$error\nORCA could not reach the health endpoint, so no provider is reported as working.',
                      actionLabel: 'Retry',
                      onAction: () => ref.read(healthProvider.notifier).checkHealth(),
                    ),
                    const SizedBox(height: 12),
                    const _RecoveryCard(),
                  ],
                ),
              ),
            ],
          );

          final Widget sidebar = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ConnectionCard(baseUrl: baseUrl),
              const SizedBox(height: 16),
              _LanguageCard(
                language: language,
                onChanged: (String value) async {
                  ref.read(selectedLocaleProvider.notifier).state = value;
                  await cache.put('settings.locale', <String, dynamic>{'value': value},
                      ttl: const Duration(days: 3650));
                },
              ),
              const SizedBox(height: 16),
              _CacheCard(
                cache: cache,
                keys: _cachedKeys,
                queued: outbox.length,
                onClear: () async {
                  await cache.clearAll();
                  if (context.mounted) {
                    ToastHelper.show(
                      context,
                      title: 'Cache cleared',
                      message: 'Cached payloads were removed from this device.',
                      severity: 'info',
                    );
                  }
                },
                onRetrySync: () => ref.read(syncManagerProvider.notifier).triggerSync(),
              ),
              const SizedBox(height: 16),
              const _ModelCard(),
            ],
          );

          final Widget body = RefreshIndicator(
            onRefresh: () => ref.read(healthProvider.notifier).checkHealth(),
            color: OrcaTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: orcaContentPadding(wide: twoColumn),
              children: <Widget>[
                if (!twoColumn) ...<Widget>[
                  sidebar,
                  const SizedBox(height: 20),
                  providers,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 6, child: providers),
                      const SizedBox(width: 20),
                      Expanded(flex: 4, child: sidebar),
                    ],
                  ),
                const SizedBox(height: 22),
                const OrcaProvenance(
                  source: 'GET /api/v1/health',
                  timeLabel: 'ORCA — Marine Ecosystem Reasoning with Collaborative Agents',
                ),
              ],
            ),
          );

          return body;
        },
      ),
    );
  }

  static bool _isUsable(String status) {
    final String normal = status.toUpperCase();
    return normal == 'FRESH' || normal == 'CACHED' || normal == 'CONFIGURED' || normal == 'AVAILABLE';
  }
}

class _SourceTile extends StatelessWidget {
  final SourceHealthItem item;

  const _SourceTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final String status = item.status.toUpperCase();
    final Color color = switch (status) {
      'FRESH' || 'CACHED' || 'AVAILABLE' => VerdictColors.go,
      'CONFIGURED' || 'UNVERIFIED' => VerdictColors.caution,
      'UNAVAILABLE' || 'UNREACHABLE' || 'FAILED' => VerdictColors.critical,
      'CREDENTIAL_REQUIRED' || 'TOKEN_REQUIRED' => VerdictColors.stale,
      _ => VerdictColors.stale,
    };
    final OrcaDataState state = switch (status) {
      'FRESH' => OrcaDataState.current,
      'CACHED' => OrcaDataState.cached,
      'CONFIGURED' => OrcaDataState.forecast,
      'UNVERIFIED' => OrcaDataState.loading,
      _ => OrcaDataState.unavailable,
    };

    return OrcaCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.name,
                        style: OrcaType.metricLabel.copyWith(fontSize: 13, color: OrcaTheme.textPrimary),
                      ),
                    ),
                    OrcaStateChip(state: state, overrideLabel: status.replaceAll('_', ' '), showIcon: false),
                  ],
                ),
                if (item.note != null && item.note!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(item.note!, style: OrcaType.body.copyWith(fontSize: 12)),
                ],
                const SizedBox(height: 5),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: <Widget>[
                    Text('key ${item.key}', style: OrcaType.caption.copyWith(fontSize: 10.5)),
                    if (item.latencyMs != null)
                      Text('${item.latencyMs} ms', style: OrcaType.caption.copyWith(fontSize: 10.5)),
                    if (item.checkedAt != null)
                      Text(
                        'observed ${DateFormatter.formatIstTime(DateTime.fromMillisecondsSinceEpoch(item.checkedAt! * 1000, isUtc: true))}',
                        style: OrcaType.caption.copyWith(fontSize: 10.5),
                      )
                    else
                      Text('no observation time reported', style: OrcaType.caption.copyWith(fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final String baseUrl;

  const _ConnectionCard({required this.baseUrl});

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('ORCA BOX', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const OrcaIconBadge(icon: Icons.dns_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    baseUrl,
                    style: OrcaType.metricLabel.copyWith(fontSize: 12.5, color: OrcaTheme.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OrcaPillButton(
              label: 'Change backend address',
              icon: Icons.tune_rounded,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ServerConfigDialog(),
              ),
            ),
            const SizedBox(height: 8),
            const OrcaProvenance(
              source: 'All marine requests are issued to this address',
              timeLabel: 'Timeouts 45 s connect / receive / send; the live stream keeps an open receive window',
              maxLines: 3,
            ),
          ],
        ),
      );
}

class _LanguageCard extends StatelessWidget {
  final String language;
  final ValueChanged<String> onChanged;

  const _LanguageCard({required this.language, required this.onChanged});

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('LANGUAGE', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: language,
              decoration: const InputDecoration(labelText: 'Interface language'),
              items: orcaLanguages
                  .map((OrcaLanguageOption option) => DropdownMenuItem<String>(
                        value: option.code,
                        child: Text(option.label),
                      ))
                  .toList(),
              onChanged: (String? value) {
                if (value != null) onChanged(value);
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'The choice is stored on this device and re-applied at launch.',
              style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: OrcaTheme.textMuted),
            ),
          ],
        ),
      );
}

class _CacheCard extends StatelessWidget {
  final CacheService cache;
  final List<String> keys;
  final int queued;
  final Future<void> Function() onClear;
  final VoidCallback onRetrySync;

  const _CacheCard({
    required this.cache,
    required this.keys,
    required this.queued,
    required this.onClear,
    required this.onRetrySync,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (final String key in keys) {
      final CachedRecord? record = cache.get(key);
      if (record == null) continue;
      final StalenessInfo staleness = record.staleness;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(key, style: OrcaType.caption.copyWith(fontSize: 11.5, color: OrcaTheme.textPrimary)),
                    Text(
                      '${DateFormatter.formatIstTime(record.fetchedAt)} · ttl ${record.ttl.inMinutes} min',
                      style: OrcaType.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
              OrcaStateChip(
                state: record.isExpired ? OrcaDataState.stale : OrcaDataState.cached,
                overrideLabel: record.isExpired ? staleness.label : 'CACHED',
                showIcon: false,
              ),
            ],
          ),
        ),
      );
    }

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('OFFLINE CACHE', color: OrcaTheme.textMuted)),
              OrcaStateChip(
                state: cache.keyCount == 0 ? OrcaDataState.unavailable : OrcaDataState.cached,
                overrideLabel: '${cache.keyCount} KEYS',
                showIcon: false,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'No ORCA payload is stored on this device yet, so offline surfaces will show unavailable states rather than stale numbers.',
              style: OrcaType.body.copyWith(fontSize: 12.5),
            )
          else
            ...rows,
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: OrcaTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.cloud_upload_outlined, size: 16, color: OrcaTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    queued == 0
                        ? 'Offline outbox empty — nothing is waiting to sync.'
                        : '$queued queued operation${queued == 1 ? '' : 's'} awaiting the ORCA Box.',
                    style: OrcaType.body.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OrcaPillButton(
                  label: queued == 0 ? 'Clear cache' : 'Retry sync',
                  icon: queued == 0 ? Icons.delete_outline_rounded : Icons.sync_rounded,
                  onPressed: queued == 0 ? () => onClear() : onRetrySync,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard();

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('AI EXPLANATION LAYER', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                const OrcaIconBadge(icon: Icons.memory_rounded, color: VerdictColors.caution),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Optional local model',
                    style: OrcaType.metricLabel.copyWith(fontSize: 13, color: OrcaTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Narrative explanations are produced by a local model when one is running. If it is not, the deterministic engine still produces the verdict and the trace marks the affected agents as degraded. Verdicts are never model-generated.',
              style: OrcaType.body.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard();

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('RECOVERY STEPS', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            for (final String step in <String>[
              'Confirm the ORCA Box address above is reachable from this device.',
              'Re-run the check; provider status is only trusted from a fresh health response.',
              'If providers answer but report CREDENTIAL_REQUIRED or TOKEN_REQUIRED, the deployment is missing that provider credential — ORCA will keep those values unavailable until it is configured.',
              'Offline surfaces continue to show stored payloads with their retrieval time; nothing is upgraded to live.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 5, color: OrcaTheme.accentDark),
                    ),
                    Expanded(child: Text(step, style: OrcaType.body.copyWith(fontSize: 12))),
                  ],
                ),
              ),
          ],
        ),
      );
}
