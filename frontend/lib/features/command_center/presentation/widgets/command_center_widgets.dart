import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/cache/staleness.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/domain/entities/advisory.dart';
import '../../../advisory/presentation/widgets/variable_provenance.dart';
import '../../../agents/presentation/providers/agents_provider.dart';
import '../../../alerts/domain/entities/alert_item.dart';
import '../../data/dto/command_center_dto.dart';

/// Widgets behind the Command Center (Overview) screen. Every element degrades
/// into an explicit unavailable / cached / stale state instead of a plausible
/// looking placeholder.

/// Morning brief header: real date, time-aware greeting and a subtitle built
/// from the skipper's own saved harbour (when they entered one).
class CommandCenterBrief extends StatelessWidget {
  final String? displayName;
  final String? harbour;
  final bool narrow;
  final VoidCallback onAskOrca;
  final VoidCallback onPlanRoute;

  const CommandCenterBrief({
    super.key,
    this.displayName,
    this.harbour,
    required this.narrow,
    required this.onAskOrca,
    required this.onPlanRoute,
  });

  @override
  Widget build(BuildContext context) {
    final DateTime istNow = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final String greeting = greetingForHour(istNow.hour);
    final String? name = (displayName ?? '').trim().isEmpty ? null : displayName!.trim();
    final String destination = (harbour ?? '').trim();

    final Widget actions = narrow
        ? Row(
            children: <Widget>[
              Expanded(
                child: OrcaPillButton(label: 'Ask ORCA', icon: Icons.forum_outlined, primary: true, onPressed: onAskOrca),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OrcaPillButton(label: 'Plan a trip', icon: Icons.route_outlined, onPressed: onPlanRoute),
              ),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OrcaPillButton(label: 'Ask ORCA', icon: Icons.forum_outlined, primary: true, onPressed: onAskOrca),
              const SizedBox(width: 10),
              OrcaPillButton(label: 'Plan a trip', icon: Icons.route_outlined, onPressed: onPlanRoute),
            ],
          );

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OrcaEyebrow(
          'MORNING BRIEF · ${DateFormat('EEEE, d MMMM yyyy').format(istNow).toUpperCase()}',
          color: OrcaTheme.accentDark,
        ),
        const SizedBox(height: 7),
        Text(
          name == null ? '$greeting.' : '$greeting, $name.',
          style: narrow ? OrcaType.displayCompact : OrcaType.display,
        ),
        const SizedBox(height: 9),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            destination.isEmpty
                ? 'Here is what the sea is telling you before you head out from your working location.'
                : 'Here is what the sea is telling you before you leave $destination.',
            style: OrcaType.body,
          ),
        ),
      ],
    );

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          heading,
          const SizedBox(height: 14),
          actions,
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(child: heading),
          const SizedBox(width: 20),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: actions),
        ],
      ),
    );
  }
}

/// Deep-teal decision panel: the deterministic verdict, its evidence state and
/// the real departure window when the backend published one.
class CommandCenterVerdictPanel extends ConsumerWidget {
  final AdvisoryEntity? advisory;
  final Object? error;
  final bool isLoading;
  final String locationLabel;
  final String coordinateLabel;
  final VoidCallback onOpenAdvisory;
  final bool narrow;

  const CommandCenterVerdictPanel({
    super.key,
    required this.advisory,
    required this.error,
    required this.isLoading,
    required this.locationLabel,
    required this.coordinateLabel,
    required this.onOpenAdvisory,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String language = Localizations.localeOf(context).languageCode;
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;

    final OrcaDataState state = advisory == null
        ? resolveDataState(hasValue: false, isLoading: isLoading, isOffline: !online, isError: error != null)
        : resolveDataState(
            hasValue: true,
            isOffline: !online,
            isStale: advisory!.staleness.state == StalenessState.stale,
            isCached: advisory!.staleness.isCached,
            isLive: streamLive,
          );

    final String verdict = advisory == null ? 'UNVERIFIED' : verdictDisplay(advisory!.verdict);
    final String headline = advisory?.localizedHeadline(language) ?? (isLoading
        ? 'Checking verified marine inputs…'
        : 'No safety verdict is available from this deployment right now.');
    final List<String> supporting = advisory?.localizedPlain(language).take(2).toList() ?? const <String>[];

    final String evidenceLabel = advisory == null
        ? 'Evidence unavailable'
        : '${advisory!.knownSources}/${advisory!.totalSources} sources verified';
    final String windowLabel = _windowLabel(advisory?.safeWindow);

    return OrcaHeroPanel(
      padding: EdgeInsets.all(narrow ? 20 : 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OrcaEyebrow('DEPARTURE SAFETY VERDICT', color: OrcaTheme.onDeepTealEyebrow),
          const SizedBox(height: 21),
          const Text('Can I go fishing today?', style: OrcaType.heroTitle),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  verdict,
                  style: narrow ? OrcaType.heroVerdictCompact : OrcaType.heroVerdict,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Icon(
                  verdictShapeIcon(advisory?.verdict),
                  color: OrcaTheme.onDeepTealStrong,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Text(headline, style: OrcaType.heroBody),
          ),
          for (final String line in supporting) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 5, color: OrcaTheme.onDeepTealMuted),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    style: OrcaType.heroBody.copyWith(color: OrcaTheme.onDeepTealMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OrcaInfoPill(icon: Icons.fact_check_outlined, label: evidenceLabel, onDark: true),
              OrcaInfoPill(icon: Icons.schedule_outlined, label: windowLabel, onDark: true),
              OrcaStateChip(state: state, onDark: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.place_outlined, size: 14, color: OrcaTheme.onDeepTealMuted),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$locationLabel · $coordinateLabel',
                        style: OrcaType.heroBody.copyWith(fontSize: 12, color: OrcaTheme.onDeepTealMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenAdvisory,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  'Full advisory',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _windowLabel(SafeWindow? window) {
    if (window == null) return 'Departure window unavailable';
    final String from = _shortTime(window.from);
    final String to = _shortTime(window.to);
    if (from.isEmpty || to.isEmpty) {
      return window.status == 'UNAVAILABLE' ? 'No safe window in forecast' : 'Departure window unavailable';
    }
    return 'Window $from–$to';
  }

  String _shortTime(String raw) {
    if (raw.trim().isEmpty) return '';
    final DateTime? parsed = DateFormatter.parseIso(raw);
    if (parsed == null) return raw;
    return DateFormat('HH:mm').format(parsed.toUtc().add(const Duration(hours: 5, minutes: 30)));
  }
}

/// "Right now" card with the real current-condition tiles.
class CommandCenterConditionsCard extends ConsumerWidget {
  final MarineConditionsDto? conditions;
  final AdvisoryEntity? advisory;
  final bool isLoading;
  final String? errorMessage;
  final int columns;

  const CommandCenterConditionsCard({
    super.key,
    required this.conditions,
    required this.advisory,
    required this.isLoading,
    required this.errorMessage,
    this.columns = 2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;
    final Map<String, VariableItem> variables = advisory?.variables ?? const <String, VariableItem>{};

    final OrcaDataState state = conditions == null && variables.isEmpty
        ? resolveDataState(hasValue: false, isLoading: isLoading, isOffline: !online, isError: errorMessage != null)
        : resolveDataState(
            hasValue: true,
            isOffline: !online,
            isCached: conditions?.isCached ?? false,
            isStale: (conditions?.isCached ?? false) && !online,
            isLive: streamLive,
          );

    final List<_TileSpec> specs = <_TileSpec>[
      _TileSpec(
        label: 'Wave height',
        icon: Icons.waves_rounded,
        variable: variables['wave_height_m'],
        fallbackValue: conditions?.waveHeightM,
        fallbackUnit: 'm',
      ),
      _TileSpec(
        label: 'Wind',
        icon: Icons.air_rounded,
        variable: variables['wind_speed_kn'],
        fallbackValue: conditions?.windKn,
        fallbackUnit: 'kn',
      ),
      _TileSpec(
        label: 'Wind gusts',
        icon: Icons.storm_rounded,
        variable: variables['wind_gust_kn'],
        fallbackValue: conditions?.windGustKn,
        fallbackUnit: 'kn',
      ),
      _TileSpec(
        label: 'Swell period',
        icon: Icons.tsunami_rounded,
        variable: variables['wave_period_s'],
        fallbackValue: conditions?.swellPeriodS,
        fallbackUnit: 's',
      ),
      _TileSpec(
        label: 'Sea temp',
        icon: Icons.thermostat_rounded,
        variable: variables['sst_celsius'],
        fallbackValue: conditions?.seaTempC,
        fallbackUnit: '°C',
      ),
      _TileSpec(
        label: 'Chlorophyll',
        icon: Icons.bubble_chart_outlined,
        variable: variables['chlorophyll_mg_m3'],
        fallbackValue: conditions?.chlorophyllMgM3,
        fallbackUnit: 'mg/m³',
      ),
    ];

    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('RIGHT NOW', color: OrcaTheme.textMuted)),
              OrcaStateChip(state: state),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Coastal conditions', style: OrcaType.cardTitle),
          const SizedBox(height: 4),
          Text(
            _subtitle(conditions, variables),
            style: OrcaType.caption,
          ),
          const SizedBox(height: 14),
          _MetricGrid(
            columns: columns,
            children: <Widget>[
              for (final _TileSpec spec in specs)
                _buildTile(context, spec, streamLive, online),
            ],
          ),
        ],
      ),
    );
  }

  String _subtitle(MarineConditionsDto? conditions, Map<String, VariableItem> variables) {
    if (conditions == null && variables.isEmpty) {
      return isLoading
          ? 'Retrieving the current marine snapshot from the ORCA Box…'
          : 'No marine snapshot is available for this location yet.';
    }
    final DateTime? timestamp = conditions?.timestamp;
    final String retrieved = timestamp == null
        ? 'retrieval time unavailable'
        : 'ORCA retrieved ${DateFormatter.formatIstTime(timestamp)}';
    final bool cached = conditions?.isCached ?? false;
    return cached ? 'Last verified snapshot · $retrieved' : 'Point-sampled model field · $retrieved';
  }

  Widget _buildTile(BuildContext context, _TileSpec spec, bool streamLive, bool online) {
    final VariableItem? variable = spec.variable;
    final double? value = variable?.value ?? spec.fallbackValue;
    final String unit = variable != null && variable.unit.isNotEmpty ? unitSuffix(variable.unit) : spec.fallbackUnit;
    final OrcaDataState tileState = variable != null
        ? variableState(variable, isLivePush: streamLive, isOffline: !online)
        : resolveDataState(
            hasValue: value != null,
            isLoading: isLoading,
            isOffline: !online,
            isCached: conditions?.isCached ?? false,
          );
    final String? caption = switch (tileState) {
      OrcaDataState.loading => 'Loading…',
      OrcaDataState.offline => 'Offline — cached value unavailable',
      OrcaDataState.unavailable => 'Not provided by any connected source',
      OrcaDataState.cached => 'Cached value',
      OrcaDataState.stale => 'Value may be out of date',
      _ => variableTimeLabel(variable),
    };
    final String? provenance = variable?.source ?? (conditions?.sources.isNotEmpty == true ? conditions!.sources.first : null);

    return OrcaMetricTile(
      label: spec.label,
      icon: spec.icon,
      value: value == null ? kOrcaUnavailableValue : formatMeasurement(value, unit),
      unit: value == null ? null : unit,
      caption: caption,
      state: tileState,
      provenance: provenance,
    );
  }
}

class _TileSpec {
  final String label;
  final IconData icon;
  final VariableItem? variable;
  final double? fallbackValue;
  final String fallbackUnit;

  const _TileSpec({
    required this.label,
    required this.icon,
    this.variable,
    this.fallbackValue,
    required this.fallbackUnit,
  });
}

class _MetricGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _MetricGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    // IntrinsicHeight resolves the row's height first, so stretch is safe here.
    // A bare CrossAxisAlignment.stretch inside the vertically scrollable
    // workspace would instead force an infinite height on the tiles.
    return Column(
      children: <Widget>[
        for (int row = 0; row < (children.length / columns).ceil(); row++) ...<Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int col = 0; col < columns; col++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: col == 0 ? 0 : 5,
                        right: col == columns - 1 ? 0 : 5,
                      ),
                      child: row * columns + col < children.length
                          ? children[row * columns + col]
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          if (row != (children.length / columns).ceil() - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// "Signals to keep in mind" — real alerts only.
class CommandCenterSignalsCard extends StatelessWidget {
  final List<AlertItem> alerts;
  final bool feedAvailable;
  final bool isLoading;
  final bool narrow;
  final VoidCallback onViewAll;

  const CommandCenterSignalsCard({
    super.key,
    required this.alerts,
    required this.feedAvailable,
    required this.isLoading,
    required this.narrow,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final List<AlertItem> visible = alerts.take(3).toList();
    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OrcaSectionHeader(
            title: 'Signals to keep in mind',
            subtitle: feedAvailable
                ? 'Official provider alerts received by this ORCA Box.'
                : 'Official alert feeds could not be verified in this session.',
            actionLabel: 'View all',
            onAction: onViewAll,
          ),
          const SizedBox(height: 12),
          if (isLoading && alerts.isEmpty)
            const _InlineLoading(label: 'Checking official alert feeds…')
          else if (!feedAvailable)
            const OrcaUnavailable(
              icon: Icons.cloud_off_outlined,
              title: 'Alert feeds unavailable',
              message: 'IMD CAP, GDACS and JTWC did not respond, so no alert state can be verified. This is not a clearance to go to sea.',
              compact: true,
            )
          else if (visible.isEmpty)
            const OrcaUnavailable(
              icon: Icons.notifications_none_rounded,
              title: 'No active alerts returned',
              message: 'The connected official feeds returned no current alerts. Always confirm locally before departure.',
              compact: true,
            )
          else
            Column(
              children: <Widget>[
                for (final AlertItem alert in visible) _SignalRow(alert: alert),
              ],
            ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  final AlertItem alert;

  const _SignalRow({required this.alert});

  @override
  Widget build(BuildContext context) {
    final Color color = VerdictColors.fromVerdict(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(VerdictColors.iconForVerdict(alert.severity), size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  alert.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OrcaTheme.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  alert.message,
                  style: OrcaType.body.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${alert.source ?? 'Source unavailable'} · ${alert.issuedAt == null ? 'Issue time unavailable' : DateFormatter.formatIstTime(alert.issuedAt!)}',
                  style: OrcaType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OrcaStateChip(
            state: alert.issuedAt == null ? OrcaDataState.unavailable : OrcaDataState.current,
            overrideLabel: (alert.severity ?? 'UNSPECIFIED').toUpperCase(),
            showIcon: false,
          ),
        ],
      ),
    );
  }
}

/// Data-trust card: real provider health from `/api/v1/health`.
class CommandCenterSourceHealthCard extends StatelessWidget {
  final SystemHealthDto? health;
  final bool isLoading;

  const CommandCenterSourceHealthCard({super.key, required this.health, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final List<SourceHealthDto> sources = health?.sources ?? const <SourceHealthDto>[];
    final int usable = sources.where((SourceHealthDto s) => s.isUsable).length;

    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('DATA TRUST', color: OrcaTheme.textMuted)),
              if (health != null && health!.timestamp != null)
                Text(
                  'Checked ${DateFormatter.formatIstTime(health!.timestamp!)}',
                  style: OrcaType.caption,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            health == null ? 'Source health unavailable' : (health!.overall.replaceAll('_', ' ')),
            style: OrcaType.cardTitle.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(
            sources.isEmpty
                ? 'The ORCA Box health endpoint did not return provider status.'
                : '$usable of ${sources.length} providers reporting usable data.',
            style: OrcaType.body.copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          if (isLoading && sources.isEmpty)
            const _InlineLoading(label: 'Reading provider health…')
          else if (sources.isEmpty)
            const OrcaUnavailable(
              icon: Icons.storage_outlined,
              title: 'Provider status unavailable',
              message: 'Connect to the ORCA Box to read live provider health. Nothing is assumed about a source that has not reported.',
              compact: true,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final SourceHealthDto source in sources.take(8))
                  OrcaInfoPill(
                    icon: source.isUsable ? Icons.check_circle_outline : Icons.error_outline,
                    label: '${_shortName(source.name)}: ${source.status.replaceAll('_', ' ')}',
                    tint: source.isUsable ? OrcaTheme.accentDark : VerdictColors.caution,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _shortName(String name) {
    final int cut = name.indexOf(' (');
    return cut > 0 ? name.substring(0, cut) : name;
  }

}

/// Agent/service status card backed by the real `/api/v1/agents` registry.
class CommandCenterAgentStatusCard extends ConsumerWidget {
  final VoidCallback onOpenAgents;

  const CommandCenterAgentStatusCard({super.key, required this.onOpenAgents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AgentRuntimeStatus>> runtime = ref.watch(agentRuntimeStatusProvider);

    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OrcaSectionHeader(
            title: 'Agent services',
            subtitle: 'Runtime status reported by the ORCA Box agent registry.',
            actionLabel: 'Inspect',
            onAction: onOpenAgents,
          ),
          const SizedBox(height: 12),
          runtime.when(
            loading: () => const _InlineLoading(label: 'Reading agent registry…'),
            error: (_, __) => const OrcaUnavailable(
              icon: Icons.hub_outlined,
              title: 'Agent registry unavailable',
              message: 'The reasoning service status could not be read. No agent is reported as ready until its real status is returned.',
              compact: true,
            ),
            data: (List<AgentRuntimeStatus> agents) {
              if (agents.isEmpty) {
                return const OrcaUnavailable(
                  icon: Icons.hub_outlined,
                  title: 'No agents reported',
                  message: 'The backend returned an empty agent registry.',
                  compact: true,
                );
              }
              final Map<String, int> counts = <String, int>{};
              for (final AgentRuntimeStatus agent in agents) {
                final String status = agent.status.toUpperCase();
                counts[status] = (counts[status] ?? 0) + 1;
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final MapEntry<String, int> entry in counts.entries)
                    OrcaInfoPill(
                      icon: entry.key == 'IDLE' ? Icons.pause_circle_outline : Icons.error_outline,
                      label: '${entry.value} ${entry.key.toLowerCase()}',
                      tint: entry.key == 'IDLE' ? OrcaTheme.textSecondary : VerdictColors.caution,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          const OrcaProvenance(source: 'GET /api/v1/agents', timeLabel: 'Registry status is reported per request'),
        ],
      ),
    );
  }
}

/// Small route tile used by the agent/route prompt area on the overview.
class CommandCenterGuideCard extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  const CommandCenterGuideCard({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OrcaIconBadge(icon: icon),
          const SizedBox(height: 12),
          Text(title, style: OrcaType.sectionTitle.copyWith(fontSize: 15)),
          const SizedBox(height: 6),
          Text(message, style: OrcaType.body.copyWith(fontSize: 12.5)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OrcaPillButton(label: actionLabel, icon: Icons.arrow_forward_rounded, onPressed: onAction),
          ),
        ],
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  final String label;

  const _InlineLoading({required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: OrcaType.body.copyWith(fontSize: 12.5))),
        ],
      );
}

/// Departure-window card. The window, its limits and its quality are computed
/// by the deterministic engine; when the engine published none, the card says
/// so instead of suggesting a departure time.
class CommandCenterWindowCard extends StatelessWidget {
  final AdvisoryEntity? advisory;
  final bool isLoading;

  const CommandCenterWindowCard({super.key, required this.advisory, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final SafeWindow? window = advisory?.safeWindow;
    final String status = (window?.status ?? '').toUpperCase();
    final bool hasWindow = window != null &&
        window.from.trim().isNotEmpty &&
        window.to.trim().isNotEmpty &&
        status != 'UNAVAILABLE' &&
        status != 'UNKNOWN';
    final bool caution = status == 'CAUTION' || (window?.quality ?? '').toUpperCase() == 'CAUTION';

    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('DEPARTURE WINDOW', color: OrcaTheme.textMuted)),
              OrcaStateChip(
                state: isLoading && window == null
                    ? OrcaDataState.loading
                    : hasWindow
                        ? OrcaDataState.forecast
                        : OrcaDataState.unavailable,
                overrideLabel: hasWindow ? (caution ? 'CAUTION WINDOW' : 'GOOD WINDOW') : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            hasWindow
                ? '${_clock(window!.from)}–${_clock(window!.to)} IST'
                : 'No qualifying departure window',
            style: OrcaType.cardTitle.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 4),
          Text(
            _subtitle(window, hasWindow, advisory),
            style: OrcaType.body.copyWith(fontSize: 12.5),
          ),
          if (hasWindow && (window!.maxWaveM != null || window.maxWindKn != null || window.maxGustKn != null)) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (window.maxWaveM != null)
                  OrcaInfoPill(icon: Icons.waves_rounded, label: 'peak wave ${window.maxWaveM!.toStringAsFixed(1)} m'),
                if (window.maxWindKn != null)
                  OrcaInfoPill(icon: Icons.air_rounded, label: 'peak wind ${window.maxWindKn!.toStringAsFixed(1)} kn'),
                if (window.maxGustKn != null)
                  OrcaInfoPill(icon: Icons.storm_rounded, label: 'peak gust ${window.maxGustKn!.toStringAsFixed(1)} kn'),
              ],
            ),
          ],
          if (window?.recommendationEn != null && window!.recommendationEn!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OrcaTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(window.recommendationEn!, style: OrcaType.body.copyWith(fontSize: 12.5)),
            ),
          ],
          if (window?.note != null && window!.note!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(window.note!, style: OrcaType.caption),
          ],
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'ORCA deterministic safe-window engine',
            timeLabel: 'Good limits wave < 2.0 m, wind < 15 kn, gust < 25 kn · caution limits 2.5 m / 20 kn / 34 kn',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  String _subtitle(SafeWindow? window, bool hasWindow, AdvisoryEntity? advisory) {
    if (advisory == null) {
      return isLoading
          ? 'Waiting for the advisory response that carries the window.'
          : 'The advisory response that carries the window is unavailable.';
    }
    if (window == null) {
      return 'The engine returned no window object for this request, so no departure time is suggested.';
    }
    if (!hasWindow) {
      return 'The engine reported no qualifying window in the returned forecast horizon.';
    }
    final String quality = window.quality == null ? '' : ' · engine quality ${window.quality}';
    if (window.hoursRemaining != null) {
      return '${window.hoursRemaining!.toStringAsFixed(0)} hours of usable conditions${quality}.';
    }
    return 'Computed by the deterministic engine from the returned forecast$quality.';
  }

  static String _clock(String raw) {
    final DateTime? parsed = DateFormatter.parseIso(raw);
    if (parsed == null) return raw;
    return DateFormat('HH:mm').format(parsed.toUtc().add(const Duration(hours: 5, minutes: 30)));
  }
}
