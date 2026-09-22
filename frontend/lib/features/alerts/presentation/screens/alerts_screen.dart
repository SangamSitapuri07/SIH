import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/live/live_channel.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/alert_item.dart';
import '../providers/alerts_provider.dart';
import '../providers/alerts_read_provider.dart';
import '../widgets/alert_card.dart';

/// Official provider alerts with priority filters.
///
/// The empty state says only what the returned feeds establish — it never
/// implies a clear passage, and the screen never labels an alert as read
/// unless this device has actually shown it.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String _filter = 'ALL';

  static const List<String> _filters = <String>['ALL', 'CRITICAL', 'WARNING', 'INFO', 'UNSPECIFIED'];

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<AlertItem>> alertsState = ref.watch(alertsProvider);
    final DateTime? checkedAt = ref.watch(alertsFetchTimeProvider);
    final bool online = ref.watch(isOnlineProvider);
    final bool streamLive = ref.watch(liveChannelProvider) == LiveStreamStatus.connected;
    final Set<String> reviewed = ref.watch(alertsReadProvider);

    final List<AlertItem> all = alertsState.valueOrNull ?? const <AlertItem>[];
    final List<AlertItem> visible = _filter == 'ALL'
        ? all
        : all
            .where((AlertItem alert) => (alert.severity ?? 'UNSPECIFIED').toUpperCase() == _filter)
            .toList();
    final int unreviewed = all.where((AlertItem alert) => !reviewed.contains(alert.id)).length;

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.alertsTitle ?? 'Alerts',
      subtitle: 'Official provider warnings',
      locationLabel: 'Feed coverage',
      coordinateLabel: all.isEmpty ? 'No active alerts' : '${all.length} active alert${all.length == 1 ? '' : 's'}',
      updatedAt: checkedAt,
      stateLabel: !online
          ? 'OFFLINE'
          : streamLive
              ? 'LIVE CHANNEL OPEN'
              : 'DIRECT REQUESTS',
      onRefresh: () => ref.read(alertsProvider.notifier).fetch(forceRefresh: true),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;
          return RefreshIndicator(
            onRefresh: () => ref.read(alertsProvider.notifier).fetch(forceRefresh: true),
            color: OrcaTheme.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: orcaContentPadding(wide: twoColumn),
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const OrcaEyebrow('PROACTIVE WATCH', color: OrcaTheme.accentDark),
                          const SizedBox(height: 6),
                          Text(
                            all.isEmpty
                                ? 'Official alert feed'
                                : '${all.length} verified alert${all.length == 1 ? '' : 's'}',
                            style: OrcaType.displayCompact,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            checkedAt == null
                                ? 'The feeds have not been read successfully in this session.'
                                : 'Feeds last read ${DateFormatter.formatIstTime(checkedAt)}. IMD CAP, GDACS and JTWC entries appear here exactly as published.',
                            style: OrcaType.body.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    OrcaStateChip(
                      state: !online
                          ? OrcaDataState.offline
                          : streamLive
                              ? OrcaDataState.live
                              : OrcaDataState.current,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _FilterBar(
                  filters: _filters,
                  selected: _filter,
                  counts: <String, int>{
                    'ALL': all.length,
                    for (final String filter in _filters.skip(1))
                      filter: all
                          .where((AlertItem alert) => (alert.severity ?? 'UNSPECIFIED').toUpperCase() == filter)
                          .length,
                  },
                  onSelected: (String value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        unreviewed == 0
                            ? 'Read state is device-local: the official feeds do not publish one.'
                            : '$unreviewed alert${unreviewed == 1 ? '' : 's'} not yet reviewed on this device.',
                        style: OrcaType.caption,
                      ),
                    ),
                    if (all.isNotEmpty && unreviewed > 0)
                      TextButton(
                        onPressed: () => ref
                            .read(alertsReadProvider.notifier)
                            .markAllReviewed(all.map((AlertItem alert) => alert.id)),
                        child: const Text('Mark all reviewed'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                ...alertsState.when(
                  loading: () => <Widget>[_loading()],
                  error: (Object? error, StackTrace? stack) => <Widget>[
                    OrcaUnavailable(
                      icon: Icons.cloud_off_outlined,
                      title: 'Alert feeds unavailable',
                      message: '$error\nNo alert state can be verified, so none is shown. This is not a clearance to go to sea.',
                      actionLabel: 'Retry',
                      onAction: () => ref.read(alertsProvider.notifier).fetch(forceRefresh: true),
                    ),
                  ],
                  data: (List<AlertItem> alerts) {
                    if (alerts.isEmpty) {
                      return <Widget>[
                        OrcaUnavailable(
                          icon: Icons.notifications_none_rounded,
                          title: 'No active alerts returned',
                          message: 'The connected official feeds are reachable and returned no current alerts. Continue to check local authority guidance before departure.',
                          actionLabel: 'Re-check feeds',
                          onAction: () => ref.read(alertsProvider.notifier).fetch(forceRefresh: true),
                        ),
                      ];
                    }
                    if (visible.isEmpty) {
                      return <Widget>[
                        OrcaUnavailable(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'No $_filter alerts',
                          message: 'No returned alert carries this priority. Switch the filter to see the ${alerts.length} alert${alerts.length == 1 ? '' : 's'} the feeds published.',
                          actionLabel: 'Show all',
                          onAction: () => setState(() => _filter = 'ALL'),
                        ),
                      ];
                    }
                    if (!twoColumn) {
                      return <Widget>[
                        for (final AlertItem alert in visible)
                          AlertCard(
                            alert: alert,
                            reviewed: reviewed.contains(alert.id),
                            onReviewed: () => ref.read(alertsReadProvider.notifier).markReviewed(alert.id),
                          ),
                      ];
                    }
                    final int mid = (visible.length / 2).ceil();
                    final List<AlertItem> left = visible.sublist(0, mid);
                    final List<AlertItem> right = visible.sublist(mid);
                    return <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                for (final AlertItem alert in left)
                                  AlertCard(
                                    alert: alert,
                                    reviewed: reviewed.contains(alert.id),
                                    onReviewed: () => ref.read(alertsReadProvider.notifier).markReviewed(alert.id),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                for (final AlertItem alert in right)
                                  AlertCard(
                                    alert: alert,
                                    reviewed: reviewed.contains(alert.id),
                                    onReviewed: () => ref.read(alertsReadProvider.notifier).markReviewed(alert.id),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ];
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _loading() => OrcaCard(
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Reading official alert feeds…', style: OrcaType.body.copyWith(fontSize: 12.5))),
          ],
        ),
      );
}

class _FilterBar extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String filter in filters)
            _FilterChip(
              label: filter,
              count: counts[filter] ?? 0,
              selected: filter == selected,
              onTap: () => onSelected(filter),
            ),
        ],
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent = VerdictColors.fromVerdict(label == 'ALL' ? null : label);
    return Semantics(
      selected: selected,
      button: true,
      label: '$label filter, $count alerts',
      child: Material(
        color: selected ? OrcaTheme.deepTeal : OrcaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? OrcaTheme.deepTeal : OrcaTheme.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (label != 'ALL') ...<Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: selected ? Colors.white : OrcaTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.18)
                        : OrcaTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : OrcaTheme.textSecondary,
                    ),
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
