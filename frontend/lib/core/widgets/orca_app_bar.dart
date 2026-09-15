import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../live/live_channel.dart';
import '../offline/connectivity_watcher.dart';
import '../theme/orca_theme.dart';
import 'orca_navigation.dart';
import 'orca_ui.dart';

/// Shared ORCA page header.
///
/// The stream chip only reads LIVE while the SSE connection to
/// `/api/live/stream` is genuinely open; connecting, reconnecting and offline
/// states are labelled as themselves.
class OrcaAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showStreamChip;
  final bool showMenuButton;
  final Widget? leading;

  const OrcaAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.showStreamChip = true,
    this.showMenuButton = true,
    this.leading,
  });

  @override
  Size get preferredSize => Size.fromHeight(subtitle == null ? kToolbarHeight : kToolbarHeight + 12);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LiveStreamStatus streamStatus = ref.watch(liveChannelProvider);
    final bool online = ref.watch(isOnlineProvider);
    final bool narrow = MediaQuery.sizeOf(context).width < 980;
    final String location = GoRouterState.of(context).matchedLocation;

    final OrcaDataState streamState = !online
        ? OrcaDataState.offline
        : switch (streamStatus) {
            LiveStreamStatus.connected => OrcaDataState.live,
            LiveStreamStatus.connecting => OrcaDataState.loading,
            LiveStreamStatus.reconnecting => OrcaDataState.stale,
            LiveStreamStatus.disconnected => OrcaDataState.unavailable,
          };
    final String streamLabel = !online
        ? 'OFFLINE'
        : switch (streamStatus) {
            LiveStreamStatus.connected => 'LIVE',
            LiveStreamStatus.connecting => 'CONNECTING',
            LiveStreamStatus.reconnecting => 'RECONNECTING',
            LiveStreamStatus.disconnected => 'STREAM CLOSED',
          };

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: subtitle == null ? kToolbarHeight : kToolbarHeight + 12,
      backgroundColor: OrcaTheme.sidebarSurface,
      surfaceTintColor: Colors.transparent,
      shape: const Border(bottom: BorderSide(color: OrcaTheme.shellBorder)),
      leadingWidth: leading != null ? 52 : 0,
      leading: leading,
      titleSpacing: leading != null ? 0 : 18,
      title: Row(
        children: <Widget>[
          const OrcaBrandMark(size: 30),
          const SizedBox(width: 10),
          const Text.rich(
            TextSpan(
              text: 'ORCA',
              children: <InlineSpan>[
                TextSpan(text: '.', style: TextStyle(color: OrcaTheme.accent)),
              ],
            ),
            style: TextStyle(
              fontFamily: kOrcaSans,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.55,
              color: OrcaTheme.textPrimary,
            ),
          ),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 11),
            color: OrcaTheme.cardBorder,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: kOrcaSans,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrcaType.caption.copyWith(fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        if (showStreamChip)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(
              message: 'Live channel to the ORCA Box: ${streamStatus.name}',
              child: OrcaStateChip(state: streamState, overrideLabel: streamLabel),
            ),
          ),
        if (actions != null) ...actions!,
        if (narrow && showMenuButton)
          IconButton(
            tooltip: 'All ORCA workspaces',
            onPressed: () => showOrcaWorkspaceSheet(context, location),
            icon: const Icon(Icons.apps_rounded, size: 20),
          ),
        const SizedBox(width: 6),
      ],
    );
  }
}
