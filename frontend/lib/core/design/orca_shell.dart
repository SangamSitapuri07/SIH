import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../live/live_channel.dart';
import '../offline/connectivity_watcher.dart';
import '../theme/orca_theme.dart';
import 'breakpoints.dart';
import 'data_state.dart';
import 'orca_widgets.dart';

/// Page scaffold shared by every ORCA screen.
///
/// On desktop the app shell already supplies the navigation rail, so a page
/// renders a slim context bar (location · refresh · connection state) above a
/// width-capped workspace — matching the reference's broad content canvas.
///
/// On mobile the same page gets a real Material app bar with the screen title,
/// so it reads as an app rather than a shrunken desktop layout.
class OrcaPage extends ConsumerWidget {
  /// Screen name, shown in the mobile app bar.
  final String title;

  /// Short context line (e.g. working coordinates).
  final String? contextLabel;

  /// Body content. Supply your own scroll view.
  final Widget child;

  /// Actions shown on the right of the bar on both layouts.
  final List<Widget> actions;

  /// When false the desktop workspace is not width-capped or padded — used by
  /// the map, which wants the entire canvas.
  final bool constrainContent;

  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;
  final Widget? bottomSheetContent;

  const OrcaPage({
    super.key,
    required this.title,
    required this.child,
    this.contextLabel,
    this.actions = const [],
    this.constrainContent = true,
    this.onRefresh,
    this.floatingActionButton,
    this.bottomSheetContent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = OrcaBreakpoints.isDesktop(context);
    final body = constrainContent
        ? Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: OrcaBreakpoints.contentMaxWidth),
              child: child,
            ),
          )
        : child;

    if (desktop) {
      return Scaffold(
        backgroundColor: OrcaTheme.background,
        floatingActionButton: floatingActionButton,
        body: Column(
          children: [
            _DesktopContextBar(
              contextLabel: contextLabel,
              actions: actions,
              onRefresh: onRefresh,
            ),
            const Divider(height: 1, color: OrcaTheme.cardBorder),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: OrcaTheme.background,
      floatingActionButton: floatingActionButton,
      appBar: AppBar(
        backgroundColor: OrcaTheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 16,
        toolbarHeight: 62,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: OrcaTheme.textPrimary,
              ),
            ),
            if (contextLabel != null)
              Text(
                contextLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: OrcaTheme.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          const OrcaConnectionChip(dense: true),
          const SizedBox(width: 4),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => onRefresh!(),
              icon: const Icon(Icons.refresh_rounded, size: 21),
            ),
          ...actions,
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: OrcaTheme.cardBorder),
        ),
      ),
      body: body,
      bottomSheet: bottomSheetContent,
    );
  }
}

class _DesktopContextBar extends StatelessWidget {
  final String? contextLabel;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;

  const _DesktopContextBar({
    this.contextLabel,
    required this.actions,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: 62,
        color: OrcaTheme.background,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Row(
          children: [
            if (contextLabel != null)
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 15, color: OrcaTheme.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        contextLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (onRefresh != null) ...[
              IconButton(
                tooltip: 'Refresh data',
                onPressed: () => onRefresh!(),
                icon: const Icon(Icons.refresh_rounded, size: 19),
                style: IconButton.styleFrom(
                  foregroundColor: OrcaTheme.textSecondary,
                  side: const BorderSide(color: OrcaTheme.cardBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
            ],
            const OrcaConnectionChip(),
            for (final action in actions) ...[
              const SizedBox(width: 10),
              action,
            ],
          ],
        ),
      );
}

/// Connection state chip.
///
/// This is the single place in the app allowed to claim `LIVE`, and it does so
/// only when the SSE channel reports [LiveStreamStatus.connected] *and* the
/// device is online. Reconnecting, syncing and offline all render as
/// themselves.
class OrcaConnectionChip extends ConsumerWidget {
  final bool dense;
  const OrcaConnectionChip({super.key, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(liveChannelProvider);
    final online = ref.watch(isOnlineProvider);

    final DataState state;
    final String label;
    if (!online) {
      state = DataState.offline;
      label = 'OFFLINE';
    } else {
      switch (status) {
        case LiveStreamStatus.connected:
          state = DataState.live;
          label = 'LIVE';
        case LiveStreamStatus.connecting:
          state = DataState.loading;
          label = 'CONNECTING';
        case LiveStreamStatus.reconnecting:
          state = DataState.stale;
          label = 'RECONNECTING';
        case LiveStreamStatus.disconnected:
          state = DataState.unavailable;
          label = 'NOT LIVE';
      }
    }

    return Tooltip(
      message: online
          ? 'ORCA live stream: ${status.name}'
          : 'Device is offline — only cached data can be shown',
      child: OrcaStateBadge(state: state, overrideLabel: label, dense: dense),
    );
  }
}
