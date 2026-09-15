import 'package:flutter/material.dart';

import '../theme/orca_theme.dart';
import '../theme/verdict_colors.dart';

/// Honest data-state vocabulary used across every ORCA surface.
///
/// A surface may only claim [live] when the SSE stream is genuinely connected
/// *and* the displayed value arrived during that connection. Cached, stale,
/// forecast, unavailable and error states are first-class, not fallbacks that
/// pretend to be live measurements.
enum OrcaDataState {
  live,
  current,
  forecast,
  cached,
  stale,
  unavailable,
  loading,
  offline,
  error,
}

extension OrcaDataStateX on OrcaDataState {
  String get label => switch (this) {
        OrcaDataState.live => 'LIVE',
        OrcaDataState.current => 'CURRENT',
        OrcaDataState.forecast => 'FORECAST',
        OrcaDataState.cached => 'CACHED',
        OrcaDataState.stale => 'STALE',
        OrcaDataState.unavailable => 'UNAVAILABLE',
        OrcaDataState.loading => 'LOADING',
        OrcaDataState.offline => 'OFFLINE',
        OrcaDataState.error => 'ERROR',
      };

  Color get color => switch (this) {
        OrcaDataState.live => VerdictColors.go,
        OrcaDataState.current => OrcaTheme.accentDark,
        OrcaDataState.forecast => VerdictColors.info,
        OrcaDataState.cached => OrcaTheme.textSecondary,
        OrcaDataState.stale => VerdictColors.caution,
        OrcaDataState.unavailable => OrcaTheme.textMuted,
        OrcaDataState.loading => OrcaTheme.accentDark,
        OrcaDataState.offline => VerdictColors.caution,
        OrcaDataState.error => VerdictColors.critical,
      };

  IconData get icon => switch (this) {
        OrcaDataState.live => Icons.bolt_rounded,
        OrcaDataState.current => Icons.radio_button_checked_rounded,
        OrcaDataState.forecast => Icons.timeline_rounded,
        OrcaDataState.cached => Icons.history_rounded,
        OrcaDataState.stale => Icons.schedule_rounded,
        OrcaDataState.unavailable => Icons.remove_circle_outline_rounded,
        OrcaDataState.loading => Icons.hourglass_top_rounded,
        OrcaDataState.offline => Icons.wifi_off_rounded,
        OrcaDataState.error => Icons.error_outline_rounded,
      };

  bool get isVerified => this == OrcaDataState.live || this == OrcaDataState.current || this == OrcaDataState.forecast;
}

/// Resolves the single honest state for a value from independent signals.
OrcaDataState resolveDataState({
  required bool hasValue,
  bool isLoading = false,
  bool isOffline = false,
  bool isError = false,
  bool isStale = false,
  bool isCached = false,
  bool isLive = false,
  bool isForecast = false,
}) {
  if (!hasValue) {
    if (isLoading) return OrcaDataState.loading;
    if (isOffline) return OrcaDataState.offline;
    if (isError) return OrcaDataState.error;
    return OrcaDataState.unavailable;
  }
  if (isOffline) return OrcaDataState.offline;
  if (isStale) return OrcaDataState.stale;
  if (isCached) return OrcaDataState.cached;
  if (isLive) return OrcaDataState.live;
  if (isForecast) return OrcaDataState.forecast;
  return OrcaDataState.current;
}

/// Base white card of the reference workspace: hairline border, 16px radius,
/// no drop shadow.
class OrcaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const OrcaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? OrcaTheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? OrcaTheme.cardBorder),
        boxShadow: OrcaTheme.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) {
      return margin == null ? decorated : Padding(padding: margin!, child: decorated);
    }
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: decorated,
        ),
      ),
    );
  }
}

/// Small uppercase label used above card titles, mirroring the reference.
class OrcaEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const OrcaEyebrow(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = OrcaType.eyebrow.copyWith(color: color ?? OrcaType.eyebrow.color);
    if (icon == null) return Text(text, style: style);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 13, color: style.color),
        const SizedBox(width: 5),
        Flexible(child: Text(text, style: style, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Section heading with optional trailing action, matching the reference's
/// "Signals to keep in mind  ·  View all →" rhythm.
class OrcaSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  const OrcaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: OrcaType.cardTitle),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(subtitle!, style: OrcaType.body),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
        if (actionLabel != null && onAction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: OrcaTheme.accentInk,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    actionLabel!,
                    style: OrcaType.button.copyWith(color: OrcaTheme.accentInk),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 14),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact pill listing a real data state. [onDark] renders the inverted
/// variant used inside deep-teal decision panels.
class OrcaStateChip extends StatelessWidget {
  final OrcaDataState state;
  final bool onDark;
  final String? overrideLabel;
  final bool showIcon;

  const OrcaStateChip({
    super.key,
    required this.state,
    this.onDark = false,
    this.overrideLabel,
    this.showIcon = false,
  });

  /// The reference uses one pill per freshness state:
  /// live `#e2f8f3/#147a65`, cached `#e9f2f7/#427288`,
  /// stale `#fff2d8/#9a6316`, unavailable `#f2e9ea/#914b52`.
  (Color, Color) get _pair => switch (state) {
        OrcaDataState.live => (OrcaTheme.liveBg, OrcaTheme.liveFg),
        OrcaDataState.current => (OrcaTheme.liveBg, OrcaTheme.liveFg),
        OrcaDataState.cached => (OrcaTheme.cachedBg, OrcaTheme.cachedFg),
        OrcaDataState.forecast => (OrcaTheme.cachedBg, OrcaTheme.cachedFg),
        OrcaDataState.stale => (OrcaTheme.staleBg, OrcaTheme.staleFg),
        OrcaDataState.loading => (OrcaTheme.staleBg, OrcaTheme.staleFg),
        OrcaDataState.offline => (OrcaTheme.unavailableBg, OrcaTheme.unavailableFg),
        OrcaDataState.error => (OrcaTheme.unavailableBg, OrcaTheme.unavailableFg),
        OrcaDataState.unavailable => (OrcaTheme.unavailableBg, OrcaTheme.unavailableFg),
      };

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = _pair;
    final Color color = onDark ? OrcaTheme.onDeepTealTitle : foreground;
    return Semantics(
      label: 'Data state: ${overrideLabel ?? state.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: onDark ? Colors.white.withValues(alpha: 0.10) : background,
          borderRadius: BorderRadius.circular(999),
          border: onDark ? Border.all(color: Colors.white.withValues(alpha: 0.17)) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (showIcon)
              Icon(state.icon, size: 11.5, color: color)
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            Text(
              (overrideLabel ?? state.label).toUpperCase(),
              style: OrcaType.statusPill.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class OrcaInfoPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool onDark;
  final Color? tint;

  const OrcaInfoPill({super.key, this.icon, required this.label, this.onDark = false, this.tint});

  @override
  Widget build(BuildContext context) {
    final Color color = tint ?? (onDark ? OrcaTheme.onDeepTeal : OrcaTheme.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.10) : OrcaTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDark ? Colors.white.withValues(alpha: 0.18) : OrcaTheme.cardBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Provenance line: source, observed/valid time and cache state live directly
/// under every major marine value.
class OrcaProvenance extends StatelessWidget {
  final String? source;
  final String? timeLabel;
  final String? stateLabel;
  final bool onDark;
  final int maxLines;

  const OrcaProvenance({
    super.key,
    this.source,
    this.timeLabel,
    this.stateLabel,
    this.onDark = false,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> parts = <String>[
      if (source != null && source!.trim().isNotEmpty) source!.trim(),
      if (timeLabel != null && timeLabel!.trim().isNotEmpty) timeLabel!.trim(),
      if (stateLabel != null && stateLabel!.trim().isNotEmpty) stateLabel!.trim(),
    ];
    if (parts.isEmpty) {
      return Text(
        'Source and time unavailable',
        style: OrcaType.caption.copyWith(color: onDark ? OrcaTheme.onDeepTealMuted : OrcaTheme.textMuted),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.verified_outlined,
          size: 12,
          color: onDark ? OrcaTheme.onDeepTealMuted : OrcaTheme.textMuted,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: OrcaType.caption.copyWith(color: onDark ? OrcaTheme.onDeepTealMuted : OrcaTheme.textMuted),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Metric card in the reference's "Right now" grid: label + icon on the first
/// row, large value with unit, then a small caption that carries either the
/// provider state or the backend's own qualitative note.
class OrcaMetricTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final String? unit;
  final String? caption;
  final OrcaDataState state;
  final String? provenance;
  final bool compact;

  const OrcaMetricTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.unit,
    this.caption,
    required this.state,
    this.provenance,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool available = value.trim().isNotEmpty && value != kOrcaUnavailableValue;
    return Semantics(
      label: '$label ${available ? '$value ${unit ?? ''}'.trim() : 'unavailable'}, ${state.label}',
      child: Container(
        padding: EdgeInsets.all(compact ? 13 : 16),
        decoration: BoxDecoration(
          color: OrcaTheme.surface,
          borderRadius: BorderRadius.circular(OrcaTheme.tileRadius),
          border: Border.all(color: OrcaTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    style: OrcaType.metricLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, size: 17, color: OrcaTheme.accentDark),
              ],
            ),
            SizedBox(height: compact ? 8 : 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: Text(
                    available ? value : kOrcaUnavailableValue,
                    style: available
                        ? OrcaType.metricValue
                        : OrcaType.metricValue.copyWith(
                            fontSize: 15,
                            color: OrcaTheme.textMuted,
                            letterSpacing: 0,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (available && unit != null) ...<Widget>[
                  const SizedBox(width: 4),
                  Text(unit!, style: OrcaType.metricUnit),
                ],
              ],
            ),
            const SizedBox(height: 7),
            if (caption != null)
              Text(
                caption!,
                style: OrcaType.metricFoot.copyWith(
                  color: state.isVerified ? OrcaTheme.metricFootInk : OrcaTheme.textMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            if (provenance != null) ...<Widget>[
              const SizedBox(height: 4),
              OrcaProvenance(source: provenance),
            ],
          ],
        ),
      ),
    );
  }
}


/// `.orca-content` padding: 27/34/46 on desktop, 20/16/32 on phones.
EdgeInsets orcaContentPadding({required bool wide}) => EdgeInsets.fromLTRB(
      wide ? OrcaTheme.contentPadH : 16,
      wide ? OrcaTheme.contentPadV : 20,
      wide ? OrcaTheme.contentPadH : 16,
      wide ? OrcaTheme.contentPadBottom : 32,
    );

/// Centres a workspace body in the reference's 1380px content column while
/// leaving the surrounding canvas visible on wider displays.
class OrcaContentFrame extends StatelessWidget {
  final Widget child;

  const OrcaContentFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double column = OrcaTheme.contentMaxWidth;
        final double gutter = constraints.maxWidth > column + 2 * OrcaTheme.contentPadH
            ? (constraints.maxWidth - column - 2 * OrcaTheme.contentPadH) / 2
            : 0;
        if (gutter == 0) return child;
        return Padding(padding: EdgeInsets.symmetric(horizontal: gutter), child: child);
      },
    );
  }
}


/// `.orca-page-head`: large heading and description on the left, actions on the
/// right, bottom-aligned like the reference workspace.
class OrcaPageHead extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? description;
  final List<Widget> actions;
  final bool narrow;

  const OrcaPageHead({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const <Widget>[],
    this.narrow = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          OrcaEyebrow(eyebrow!),
          const SizedBox(height: 7),
        ],
        Text(title, style: narrow ? OrcaType.displayCompact : OrcaType.display),
        if (description != null) ...<Widget>[
          const SizedBox(height: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(description!, style: OrcaType.body),
          ),
        ],
      ],
    );

    if (actions.isEmpty) return Padding(padding: const EdgeInsets.only(bottom: 24), child: heading);
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            heading,
            const SizedBox(height: 15),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(child: heading),
          const SizedBox(width: 20),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(spacing: 8, runSpacing: 8, children: actions),
          ),
        ],
      ),
    );
  }
}

/// Canonical wording for a value the backend did not supply.
const String kOrcaUnavailableValue = 'Unavailable';

/// Unavailable / empty state that keeps the real surface (map, card) intact
/// while explaining precisely what is missing.
class OrcaUnavailable extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  const OrcaUnavailable({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.cloud_off_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  /// `.orca-empty`: quiet, centred, no decorated panel — the reference never
  /// dresses an absence up as a card full of data.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 20 : 35),
      decoration: BoxDecoration(
        color: OrcaTheme.accentWash,
        borderRadius: BorderRadius.circular(OrcaTheme.tileRadius),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: OrcaTheme.textFaint),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: OrcaType.cardBody.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: OrcaTheme.textMuted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: OrcaType.cardBody.copyWith(color: OrcaTheme.textFaint),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 14),
            OrcaPillButton(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}

/// Top-of-screen notice used for offline / cached / degraded states. Replaces
/// the reference's "preview workspace" strip with a truthful operational note.
class OrcaNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final String? trailingLabel;

  const OrcaNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color = VerdictColors.caution,
    this.trailingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: OrcaTheme.accentWash,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCCE8E8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Flexible(
            child: RichText(
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: kOrcaSans,
                  fontSize: 10,
                  height: 1.5,
                  color: Color(0xFF426C74),
                ),
                children: <InlineSpan>[
                  TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: '  $message'),
                ],
              ),
            ),
          ),
          if (trailingLabel != null) ...<Widget>[
            const SizedBox(width: 10),
            Text(
              trailingLabel!,
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Deep-teal decision panel with the reference's concentric-ring motif.
class OrcaHeroPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const OrcaHeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.radius = OrcaTheme.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: OrcaTheme.heroGradient),
        child: Stack(
          children: <Widget>[
            Positioned(
              right: -75,
              top: -85,
              child: IgnorePointer(
                child: CustomPaint(
                  size: const Size(260, 260),
                  painter: _RipplePainter(),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The reference verdict panel's corner rings: a 260 px circle with two mint
/// glows at 24 px and 49 px spread (`#85ebe7` at 3.5% and 2.5%). Painted as
/// stacked discs so the inner band reads as layered alpha, like the CSS.
class _RipplePainter extends CustomPainter {
  static const Color _mint = Color(0xFF85EBE7);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;
    canvas.drawCircle(
      center,
      radius + 49,
      Paint()..color = _mint.withValues(alpha: 0.025),
    );
    canvas.drawCircle(
      center,
      radius + 24,
      Paint()..color = _mint.withValues(alpha: 0.035),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _mint.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small circular icon badge used in headers and list rows.
class OrcaIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const OrcaIconBadge({super.key, required this.icon, this.color = OrcaTheme.accentDark, this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.52, color: color),
    );
  }
}

/// Compact pill button (dark filled / outlined) used in the brief header.
class OrcaPillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  const OrcaPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
  });

  /// `.orca-button` metrics: radius 9, padding 10/14, 12px/800 label.
  /// Primary = `.orca-button-primary` (#153e53 on white), secondary =
  /// `.orca-button-outline` (white on #cfe2e5 hairline).
  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null;
    final Color foreground = primary ? Colors.white : const Color(0xFF315F6D);
    final Color background = primary ? OrcaTheme.primary : OrcaTheme.surface;
    final Color border = primary ? OrcaTheme.primary : OrcaTheme.cardBorderStrong;

    return Opacity(
      opacity: disabled ? 0.52 : 1,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 15, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OrcaType.button.copyWith(color: foreground),
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
