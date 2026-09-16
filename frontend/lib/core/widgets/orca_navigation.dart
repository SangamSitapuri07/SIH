import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../cache/cache_service.dart';
import '../live/live_channel.dart';
import '../localization/language_options.dart';
import '../offline/connectivity_watcher.dart';
import '../theme/orca_theme.dart';
import '../theme/verdict_colors.dart';
import '../utils/date_formatter.dart';
import '../../features/settings/presentation/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import 'orca_app_bar.dart';
import 'orca_ui.dart';

/// One navigable ORCA workspace surface.
class OrcaDestination {
  final String path;
  final String label;
  final String description;
  final IconData icon;
  final IconData selectedIcon;

  const OrcaDestination({
    required this.path,
    required this.label,
    required this.description,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Primary workspace navigation, mirroring the reference's sidebar order:
/// Overview · Ask ORCA · Ocean map · Alerts · Route planner · About ORCA.
const List<OrcaDestination> orcaPrimaryDestinations = <OrcaDestination>[
  OrcaDestination(
    path: '/home',
    label: 'Overview',
    description: 'Morning brief and live conditions',
    icon: Icons.grid_view_outlined,
    selectedIcon: Icons.grid_view_rounded,
  ),
  OrcaDestination(
    path: '/ai',
    label: 'Ask ORCA',
    description: 'Reasoning, evidence and service status',
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum_rounded,
  ),
  OrcaDestination(
    path: '/map',
    label: 'Ocean map',
    description: 'Verified fields and point inspection',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map_rounded,
  ),
  OrcaDestination(
    path: '/alerts',
    label: 'Alerts',
    description: 'Official provider warnings',
    icon: Icons.notifications_none_rounded,
    selectedIcon: Icons.notifications_rounded,
  ),
  OrcaDestination(
    path: '/navigate',
    label: 'Route planner',
    description: 'Course verification and sampled transit',
    icon: Icons.route_outlined,
    selectedIcon: Icons.route_rounded,
  ),
  OrcaDestination(
    path: '/info',
    label: 'About ORCA',
    description: 'Sources, health and cache',
    icon: Icons.info_outline_rounded,
    selectedIcon: Icons.info_rounded,
  ),
];

/// Secondary surfaces reachable from the sidebar footer and the mobile sheet.
const List<OrcaDestination> orcaUtilityDestinations = <OrcaDestination>[
  OrcaDestination(
    path: '/advisory',
    label: 'Safety advisory',
    description: 'Deterministic verdict and evidence',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
  ),
  OrcaDestination(
    path: '/locations',
    label: 'Saved locations',
    description: 'Harbours and fishing areas',
    icon: Icons.bookmark_border_rounded,
    selectedIcon: Icons.bookmark_rounded,
  ),
  OrcaDestination(
    path: '/history',
    label: 'Advisory history',
    description: 'Previously issued advisories',
    icon: Icons.history_rounded,
    selectedIcon: Icons.history_rounded,
  ),
  OrcaDestination(
    path: '/catch-report',
    label: 'Catch reports',
    description: 'Log catch observations',
    icon: Icons.set_meal_outlined,
    selectedIcon: Icons.set_meal_rounded,
  ),
  OrcaDestination(
    path: '/profile',
    label: 'Profile & settings',
    description: 'Language, vessel and preferences',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

String localizedDestinationLabel(BuildContext context, OrcaDestination destination) {
  final AppLocalizations? strings = AppLocalizations.of(context);
  if (strings == null) return destination.label;
  return switch (destination.path) {
    '/home' => strings.tabHome,
    '/ai' => strings.tabAi,
    '/map' => strings.tabMap,
    '/alerts' => strings.tabAlerts,
    '/navigate' => strings.tabNavigate,
    '/info' => strings.tabInfo,
    '/advisory' => strings.canIGoTitle,
    _ => destination.label,
  };
}

OrcaDestination? orcaDestinationFor(String location) {
  for (final OrcaDestination destination in <OrcaDestination>[
    ...orcaPrimaryDestinations,
    ...orcaUtilityDestinations,
  ]) {
    if (location.startsWith(destination.path)) return destination;
  }
  return null;
}

/// Brand mark drawn from generic nautical geometry — original artwork, not a
/// reproduction of any supplied logo asset.
class OrcaBrandMark extends StatelessWidget {
  final double size;

  const OrcaBrandMark({super.key, this.size = 34});

  /// `.orca-mark`: 34x34, radius 11, #143d52 fill, #7de8e5 glyph.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OrcaTheme.deepTeal,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: OrcaTheme.markShadow,
      ),
      child: CustomPaint(
        painter: _CompassRoserPainter(),
        size: Size(size, size),
      ),
    );
  }
}

class _CompassRoserPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width * 0.3;
    final Paint needle = Paint()..style = PaintingStyle.fill;

    needle.color = OrcaTheme.onDeepTealStrong;
    final Path north = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.34, center.dy)
      ..lineTo(center.dx - radius * 0.34, center.dy)
      ..close();
    canvas.drawPath(north, needle);

    needle.color = Colors.white.withValues(alpha: 0.82);
    final Path south = Path()
      ..moveTo(center.dx, center.dy + radius)
      ..lineTo(center.dx + radius * 0.34, center.dy)
      ..lineTo(center.dx - radius * 0.34, center.dy)
      ..close();
    canvas.drawPath(south, needle);

    canvas.drawCircle(
      center,
      radius * 0.16,
      Paint()..color = const Color(0xFF0B2C35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Desktop sidebar: compact brand block, uppercase group label, pill-selected
/// destinations and an honest backend connectivity footer.
class OrcaSidebar extends ConsumerWidget {
  final String location;
  final int alertCount;

  const OrcaSidebar({super.key, required this.location, required this.alertCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider);

    final bool compact = MediaQuery.sizeOf(context).width < OrcaTheme.compactBreakpoint;
    return Container(
      width: compact ? OrcaTheme.sidebarWidthCompact : OrcaTheme.sidebarWidth,
      decoration: const BoxDecoration(
        color: OrcaTheme.sidebarSurface,
        border: Border(right: BorderSide(color: OrcaTheme.shellBorder)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 26, 16, 22),
              child: Row(
                children: <Widget>[
                  OrcaBrandMark(),
                  SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      text: 'ORCA',
                      children: <InlineSpan>[
                        TextSpan(text: '.', style: TextStyle(color: OrcaTheme.accent)),
                      ],
                    ),
                    style: TextStyle(
                      fontFamily: kOrcaSans,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.63,
                      color: OrcaTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 13),
              child: OrcaEyebrow('YOUR SEA COMPANION', color: OrcaTheme.accentDark),
            ),
            const SizedBox(height: 9),
            for (final OrcaDestination destination in orcaPrimaryDestinations)
              _SideDestination(
                destination: destination,
                selected: location.startsWith(destination.path),
                count: destination.path == '/alerts' ? alertCount : 0,
              ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Divider(height: 1, color: OrcaTheme.cardBorder),
            ),
            for (final OrcaDestination destination in orcaUtilityDestinations)
              _SideDestination(
                destination: destination,
                selected: location.startsWith(destination.path),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 15, 13, 15),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: online ? VerdictColors.go : VerdictColors.caution,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      online ? 'ORCA Box reachable' : 'Device offline',
                      style: OrcaType.caption.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideDestination extends StatelessWidget {
  final OrcaDestination destination;
  final bool selected;
  final int count;

  const _SideDestination({required this.destination, required this.selected, this.count = 0});

  @override
  Widget build(BuildContext context) {
    final String label = localizedDestinationLabel(context, destination);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Material(
          color: selected ? OrcaTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.go(destination.path),
            child: Container(
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: selected
                    ? const Border(left: BorderSide(color: OrcaTheme.accent, width: 3))
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                children: <Widget>[
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 16,
                      color: selected ? const Color(0xFF0D4D61) : OrcaTheme.navInk,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: OrcaType.navLink.copyWith(
                          color: selected ? const Color(0xFF0D4D61) : OrcaTheme.navInk,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: OrcaTheme.badge,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            fontFamily: kOrcaSans,
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }
}

/// Mobile bottom navigation: four frequent destinations plus a "More" sheet
/// entry for the remaining workspaces.
class OrcaMobileNavBar extends ConsumerWidget {
  final String location;
  final int alertCount;
  final VoidCallback onMore;

  const OrcaMobileNavBar({
    super.key,
    required this.location,
    required this.alertCount,
    required this.onMore,
  });

  // Indexing into a const list isn't itself a const expression, so this
  // can't be `const` — it's still only ever evaluated once.
  static final List<OrcaDestination> _tabs = <OrcaDestination>[
    orcaPrimaryDestinations[0], // Overview
    orcaPrimaryDestinations[1], // Ask ORCA
    orcaPrimaryDestinations[2], // Ocean map
    orcaPrimaryDestinations[3], // Alerts
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int selectedIndex = _tabs.indexWhere((OrcaDestination d) => location.startsWith(d.path));
    final bool moreSelected = selectedIndex < 0;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF5FAFEFE),
        border: Border(top: BorderSide(color: Color(0xFFD7E8E9))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 67,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < _tabs.length; i++)
                Expanded(
                  child: _MobileTab(
                    destination: _tabs[i],
                    selected: i == selectedIndex,
                    badge: _tabs[i].path == '/alerts' ? alertCount : 0,
                    onTap: () => context.go(_tabs[i].path),
                  ),
                ),
              Expanded(
                child: _MobileTab(
                  destination: const OrcaDestination(
                    path: '/more',
                    label: 'More',
                    description: 'All ORCA workspaces',
                    icon: Icons.more_horiz_rounded,
                    selectedIcon: Icons.more_horiz_rounded,
                  ),
                  selected: moreSelected,
                  badge: 0,
                  onTap: onMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTab extends StatelessWidget {
  final OrcaDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _MobileTab({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected ? const Color(0xFF138F91) : OrcaTheme.textMuted;
    final String label = localizedDestinationLabel(context, destination);
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 19,
                  color: color,
                ),
                if (badge > 0)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: VerdictColors.noGo,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: kOrcaSans,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full workspace list for narrow screens, opened from the app bar.
Future<void> showOrcaWorkspaceSheet(BuildContext context, String location) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: OrcaTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: OrcaTheme.cardBorderStrong,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const OrcaEyebrow('ALL ORCA WORKSPACES', color: OrcaTheme.accentDark),
            const SizedBox(height: 8),
            for (final OrcaDestination destination in <OrcaDestination>[
              ...orcaPrimaryDestinations,
              ...orcaUtilityDestinations,
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: OrcaIconBadge(icon: destination.icon),
                title: Text(
                  localizedDestinationLabel(context, destination),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(destination.description, style: OrcaType.caption),
                trailing: location.startsWith(destination.path)
                    ? const Icon(Icons.check_circle, size: 18, color: OrcaTheme.accentDark)
                    : const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.go(destination.path);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Workspace frame shared by every screen.
///
/// Desktop: no app bar — the reference workspace puts the working location,
/// retrieval time and language control in a slim context bar above a broad
/// body. Mobile: a real top app bar with the same actions, plus the shell's
/// bottom navigation.
class OrcaWorkspaceScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final String locationLabel;
  final String coordinateLabel;
  final DateTime? updatedAt;
  final String? stateLabel;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLocationTap;

  const OrcaWorkspaceScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.locationLabel,
    required this.coordinateLabel,
    this.subtitle,
    this.actions,
    this.updatedAt,
    this.stateLabel,
    this.onRefresh,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth > OrcaTheme.mobileBreakpoint) {
          return Column(
            children: <Widget>[
              OrcaContextBar(
                locationLabel: locationLabel,
                coordinateLabel: coordinateLabel,
                updatedAt: updatedAt,
                stateLabel: stateLabel,
                onRefresh: onRefresh ?? () async {},
              ),
              Expanded(child: OrcaContentFrame(child: body)),
            ],
          );
        }
        return Scaffold(
          backgroundColor: OrcaTheme.background,
          appBar: OrcaAppBar(
            title: title,
            subtitle: subtitle,
            actions: <Widget>[
              if (onLocationTap != null)
                IconButton(
                  tooltip: 'Working location',
                  onPressed: onLocationTap,
                  icon: const Icon(Icons.place_outlined, size: 19),
                ),
              if (onRefresh != null)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => onRefresh!(),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ...?actions,
            ],
          ),
          body: OrcaContentFrame(child: body),
        );
      },
    );
  }
}

/// Desktop context bar shown above the workspace body: working location,
/// last refresh time (real fetch time), refresh action and language selector.
class OrcaContextBar extends ConsumerWidget {
  final String locationLabel;
  final String coordinateLabel;
  final DateTime? updatedAt;
  final String? stateLabel;
  final Color stateColor;
  final Future<void> Function() onRefresh;

  const OrcaContextBar({
    super.key,
    required this.locationLabel,
    required this.coordinateLabel,
    required this.updatedAt,
    required this.onRefresh,
    this.stateLabel,
    this.stateColor = OrcaTheme.accentDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: OrcaTheme.topBarHeight,
      decoration: const BoxDecoration(
        color: Color(0xE6F8FCFC),
        border: Border(bottom: BorderSide(color: OrcaTheme.shellBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: OrcaTheme.contentPadH),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              locationLabel,
              style: const TextStyle(
                fontFamily: kOrcaSans,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: OrcaTheme.headingSoft,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 9),
          Text('·', style: OrcaType.caption.copyWith(fontSize: 12)),
          const SizedBox(width: 9),
          Text(
            coordinateLabel,
            style: OrcaType.caption.copyWith(fontSize: 12, color: OrcaTheme.textSecondary),
          ),
          if (stateLabel != null) ...<Widget>[
            const SizedBox(width: 10),
            const Text('·', style: OrcaType.caption),
            const SizedBox(width: 10),
            Text(
              stateLabel!,
              style: OrcaType.caption.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ],
          const Spacer(),
          const _StreamStateChip(),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Refresh marine data',
            onPressed: () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            style: IconButton.styleFrom(
              backgroundColor: OrcaTheme.surface,
              foregroundColor: OrcaTheme.navInk,
              side: const BorderSide(color: OrcaTheme.chipBorder),
              minimumSize: const Size(33, 33),
              maximumSize: const Size(33, 33),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 10),
          OrcaUpdatedChip(updatedAt: updatedAt),
          const SizedBox(width: 10),
          const OrcaLanguageSelector(),
        ],
      ),
    );
  }
}

/// Stream state chip used by the desktop context bar. LIVE requires an open
/// SSE connection to `/api/live/stream`.
class _StreamStateChip extends ConsumerWidget {
  const _StreamStateChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LiveStreamStatus status = ref.watch(liveChannelProvider);
    final bool online = ref.watch(isOnlineProvider);
    final OrcaDataState state = !online
        ? OrcaDataState.offline
        : switch (status) {
            LiveStreamStatus.connected => OrcaDataState.live,
            LiveStreamStatus.connecting => OrcaDataState.loading,
            LiveStreamStatus.reconnecting => OrcaDataState.stale,
            LiveStreamStatus.disconnected => OrcaDataState.unavailable,
          };
    final String label = !online
        ? 'OFFLINE'
        : switch (status) {
            LiveStreamStatus.connected => 'LIVE',
            LiveStreamStatus.connecting => 'CONNECTING',
            LiveStreamStatus.reconnecting => 'RECONNECTING',
            LiveStreamStatus.disconnected => 'STREAM CLOSED',
          };
    return OrcaStateChip(state: state, overrideLabel: label);
  }
}

/// Renders the exact retrieval time of the payload behind the screen. When no
/// payload arrived, it says so rather than showing a plausible clock time.
class OrcaUpdatedChip extends StatelessWidget {
  final DateTime? updatedAt;

  const OrcaUpdatedChip({super.key, required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    final String label = updatedAt == null
        ? 'Update time unavailable'
        : 'Updated ${DateFormatter.formatIstTime(updatedAt!)}';
    return Text(
      label,
      style: OrcaType.caption.copyWith(fontSize: 10, color: OrcaTheme.textFaint),
    );
  }
}

/// Language switcher wired to the existing settings architecture
/// ([selectedLocaleProvider] + the persisted Hive preference).
class OrcaLanguageSelector extends ConsumerWidget {
  const OrcaLanguageSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String language = ref.watch(selectedLocaleProvider);
    return Semantics(
      label: 'Interface language',
      child: Container(
        height: 33,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: OrcaTheme.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: OrcaTheme.chipBorder),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: language,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: OrcaTheme.headingSoft,
              fontFamily: kOrcaSans,
            ),
            items: orcaLanguages
                .map((OrcaLanguageOption option) => DropdownMenuItem<String>(
                      value: option.code,
                      child: Text(option.nativeName),
                    ))
                .toList(),
            onChanged: (String? value) async {
              if (value == null) return;
              ref.read(selectedLocaleProvider.notifier).state = value;
              await ref.read(cacheServiceProvider).put(
                    'settings.locale',
                    <String, dynamic>{'value': value},
                    ttl: const Duration(days: 3650),
                  );
            },
          ),
        ),
      ),
    );
  }
}
