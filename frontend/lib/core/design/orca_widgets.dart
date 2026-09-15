import 'package:flutter/material.dart';

import '../theme/orca_theme.dart';
import '../theme/verdict_colors.dart';
import 'data_state.dart';

/// ---------------------------------------------------------------------------
/// ORCA shared surface & provenance widgets.
///
/// These implement the reference's visual language — calm white cards on a
/// pale marine canvas, a small uppercase eyebrow above every section, large
/// numerals with a quiet unit, and a provenance line under every value — while
/// making data honesty structural: a value slot cannot render a number unless
/// its [Provenance] says a real value exists.
/// ---------------------------------------------------------------------------

/// Small uppercase eyebrow label ("RIGHT NOW", "MORNING BRIEF · …").
class OrcaEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const OrcaEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: color ?? OrcaTheme.accentDark,
        ),
      );
}

/// White card with hairline border and generous padding — the base surface of
/// the whole product.
class OrcaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;

  const OrcaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.borderColor,
    this.onTap,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? OrcaTheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? OrcaTheme.cardBorder),
      ),
      child: child,
    );
    if (onTap == null) return surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: surface,
      ),
    );
  }
}

/// Section header: title on the left, optional "View all →" action right.
class OrcaSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const OrcaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 21,
                    height: 1.2,
                    letterSpacing: -0.4,
                    fontWeight: FontWeight.w800,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: OrcaTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: OrcaTheme.accentDark,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!),
                  const SizedBox(width: 5),
                  const Icon(Icons.arrow_forward, size: 15),
                ],
              ),
            ),
        ],
      );
}

/// Pill badge announcing the truth state of a card or value.
///
/// A `LIVE` badge is only ever produced by passing [DataState.live], and
/// callers may only do that when the SSE channel is genuinely connected *and*
/// the underlying value came from a live response.
class OrcaStateBadge extends StatelessWidget {
  final DataState state;
  final String? overrideLabel;
  final bool dense;

  const OrcaStateBadge({
    super.key,
    required this.state,
    this.overrideLabel,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = state.color;
    final label = overrideLabel ?? state.token;
    return Semantics(
      label: 'Data state: $label',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 7 : 9,
          vertical: dense ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: dense ? 5 : 6,
              height: dense ? 5 : 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: dense ? 5 : 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: dense ? 9.5 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single marine reading tile: icon + label, then a large numeral with a
/// small unit, then a provenance line.
///
/// When the provenance says no real value exists, the numeral slot renders the
/// honest state word ("Unavailable", "Loading…", "Error") instead — there is
/// no code path that prints a number without backing data.
class OrcaMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Already-formatted value, e.g. "0.8". Pass null when there is no value.
  final String? value;
  final String? unit;

  /// Optional qualitative note published by the backend (never invented).
  final String? note;
  final Provenance provenance;
  final bool compact;

  const OrcaMetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.provenance,
    this.unit,
    this.note,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final showValue = provenance.hasValue && value != null;
    final semantics = showValue
        ? '$label: $value ${unit ?? ''}. ${provenance.summary()}'
        : '$label: ${provenance.state.label}. ${provenance.reason ?? ''}';

    return Semantics(
      label: semantics,
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: OrcaTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OrcaTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: OrcaTheme.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
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
            SizedBox(height: compact ? 8 : 10),
            if (showValue)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: compact ? 24 : 28,
                        height: 1.05,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w800,
                        color: OrcaTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        unit!,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: OrcaTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Icon(provenance.state.icon,
                      size: 15, color: provenance.state.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      provenance.state.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: provenance.state.color,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 7),
            if (showValue && note != null)
              Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  color: OrcaTheme.textSecondary,
                ),
              ),
            OrcaProvenanceLine(provenance: provenance),
          ],
        ),
      ),
    );
  }
}

/// One-or-two line provenance caption shown under a value, overlay or panel:
/// source · valid time · validity window · cache state.
class OrcaProvenanceLine extends StatelessWidget {
  final Provenance provenance;
  final bool showStateWord;

  const OrcaProvenanceLine({
    super.key,
    required this.provenance,
    this.showStateWord = true,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (provenance.hasValue) {
      parts.add(provenance.summary());
      final window = provenance.validityWindow();
      if (window != null) parts.add(window);
      if (showStateWord &&
          (provenance.state == DataState.cached ||
              provenance.state == DataState.stale ||
              provenance.state == DataState.forecast)) {
        parts.add(provenance.state.label);
      }
    } else {
      parts.add(provenance.reason ??
          switch (provenance.state) {
            DataState.loading => 'Requesting value from provider…',
            DataState.offline => 'Offline — no live provider response',
            DataState.error => 'Provider request failed',
            _ => 'No value published by the provider',
          });
    }
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 10.5,
        height: 1.35,
        color: OrcaTheme.textMuted,
      ),
    );
  }
}

/// Neutral, explicit empty / unavailable panel. Used instead of hiding a
/// failure or filling the space with a decorative card.
class OrcaEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final DataState state;
  final bool dense;

  const OrcaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.state = DataState.unavailable,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = state.color;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 16 : 24,
        vertical: dense ? 18 : 30,
      ),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 42 : 52,
            height: dense ? 42 : 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: dense ? 21 : 26),
          ),
          SizedBox(height: dense ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: dense ? 15 : 17,
              fontWeight: FontWeight.w800,
              color: OrcaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              height: 1.45,
              color: OrcaTheme.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 180,
              child: OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline banner used for offline / cached / degraded notices at the top of a
/// screen.
class OrcaNoticeBanner extends StatelessWidget {
  final DataState state;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const OrcaNoticeBanner({
    super.key,
    required this.state,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = state.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(state.icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: OrcaTheme.textPrimary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Responsive card grid: N columns on desktop, one column on mobile, with no
/// intrinsic-height tricks (so it is safe inside scroll views).
class OrcaCardGrid extends StatelessWidget {
  final List<Widget> children;
  final int desktopColumns;
  final double spacing;
  final double breakpoint;

  const OrcaCardGrid({
    super.key,
    required this.children,
    this.desktopColumns = 2,
    this.spacing = 14,
    this.breakpoint = 760,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth >= breakpoint ? desktopColumns : 1;
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          final rowChildren = <Widget>[];
          for (var c = 0; c < columns; c++) {
            final index = i + c;
            if (c > 0) rowChildren.add(SizedBox(width: spacing));
            rowChildren.add(
              Expanded(
                child: index < children.length
                    ? children[index]
                    : const SizedBox.shrink(),
              ),
            );
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
          rows.add(
            // start, never stretch: this grid is used inside vertically
            // scrollable pages where stretch would demand infinite height.
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: rowChildren),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// Severity pill used by alerts and advisories.
class OrcaSeverityPill extends StatelessWidget {
  final String severity;
  const OrcaSeverityPill({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    final normalized = severity.trim().isEmpty ? 'UNSPECIFIED' : severity.trim();
    final unspecified = normalized.toUpperCase() == 'UNSPECIFIED';
    final color =
        unspecified ? OrcaTheme.textMuted : VerdictColors.fromVerdict(normalized);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        normalized.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: color,
        ),
      ),
    );
  }
}
