import 'package:flutter/material.dart';

import '../../../../core/design/data_state.dart';
import '../../../../core/design/orca_widgets.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../advisory/domain/entities/advisory.dart';
import '../../data/dto/command_center_dto.dart';

/// ---------------------------------------------------------------------------
/// Overview (Command Center) composition pieces.
///
/// Visual language follows the reference: a large decision-first hero on the
/// left, a "Right now" conditions panel on the right, then paired sections
/// below. Every value routes through [Provenance] so the honest state is
/// structural rather than cosmetic.
/// ---------------------------------------------------------------------------

/// The decision hero: deep-teal panel answering "Can I go fishing today?".
///
/// The verdict word is rendered **only** from a real backend advisory. When
/// the advisory endpoint has not produced a verdict, the hero says so
/// explicitly and offers a retry — it never falls back to an optimistic word.
class OverviewVerdictHero extends StatelessWidget {
  /// Real advisory from `/api/v1/advisory`, or null when unavailable.
  final AdvisoryEntity? advisory;
  final DataState state;

  /// Failure reason reported by the backend/network, when there is one.
  final String? unavailableReason;
  final String locationLabel;
  final VoidCallback? onOpenAdvisory;
  final VoidCallback? onRetry;

  const OverviewVerdictHero({
    super.key,
    required this.advisory,
    required this.state,
    required this.locationLabel,
    this.unavailableReason,
    this.onOpenAdvisory,
    this.onRetry,
  });

  /// Maps the backend's deterministic verdict vocabulary (GOOD / CAUTION /
  /// NO-GO) to the short decision word. Anything unrecognised stays unknown.
  static String? decisionWord(String? verdict) {
    if (verdict == null) return null;
    final v = verdict.toUpperCase().replaceAll('_', '-').trim();
    if (v == 'GOOD' || v == 'GO') return 'GO';
    if (v == 'CAUTION') return 'CAUTION';
    if (v == 'NO-GO' || v == 'DANGER') return 'NO-GO';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final word = decisionWord(advisory?.verdict);
    final hasDecision = advisory != null && word != null;
    final color = hasDecision
        ? VerdictColors.fromVerdict(advisory!.verdict)
        : OrcaTheme.onDeepTealMuted;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OrcaTheme.deepTeal, Color(0xFF125560)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: OrcaEyebrow(
                  'DEPARTURE SAFETY VERDICT',
                  color: OrcaTheme.onDeepTealMuted,
                ),
              ),
              OrcaStateBadge(state: state, dense: true),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Can I go fishing today?',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: OrcaTheme.onDeepTeal,
            ),
          ),
          const SizedBox(height: 10),
          if (hasDecision)
            Text(
              word,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 58,
                height: 1.05,
                letterSpacing: -2.5,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            )
          else
            Row(
              children: [
                Icon(state.icon, color: OrcaTheme.onDeepTealMuted, size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    state == DataState.loading
                        ? 'Checking conditions…'
                        : 'Verdict unavailable',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 27,
                      height: 1.15,
                      letterSpacing: -1,
                      fontWeight: FontWeight.w800,
                      color: OrcaTheme.onDeepTeal,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Text(
            hasDecision
                ? advisory!.localizedHeadline(language)
                : unavailableReason ??
                    'ORCA has not received the verified marine inputs it needs '
                        'to issue a departure verdict for this location.',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              height: 1.55,
              color: OrcaTheme.onDeepTeal,
            ),
          ),
          if (hasDecision && advisory!.localizedPlain(language).isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              advisory!.localizedPlain(language).first,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                height: 1.5,
                color: OrcaTheme.onDeepTealMuted,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              // Source coverage is a real count from `data_coverage`, not a
              // manufactured confidence percentage.
              if (hasDecision)
                _HeroChip(
                  icon: Icons.inventory_2_outlined,
                  label: advisory!.totalSources == 0
                      ? 'Source coverage unavailable'
                      : '${advisory!.knownSources}/${advisory!.totalSources} sources verified',
                ),
              _HeroChip(
                icon: state.icon,
                label: _evidenceLabel(state),
                highlight: state == DataState.live,
              ),
              if (hasDecision)
                _HeroChip(
                  icon: Icons.schedule_rounded,
                  label: _windowLabel(advisory!.safeWindow),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(Icons.near_me_outlined,
                  size: 15, color: OrcaTheme.onDeepTealMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: OrcaTheme.onDeepTealMuted,
                  ),
                ),
              ),
              if (hasDecision && onOpenAdvisory != null)
                TextButton(
                  onPressed: onOpenAdvisory,
                  style: TextButton.styleFrom(
                    foregroundColor: OrcaTheme.accent,
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('See evidence'),
                )
              else if (!hasDecision &&
                  state != DataState.loading &&
                  onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: OrcaTheme.accent,
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _evidenceLabel(DataState state) => switch (state) {
        DataState.live => 'Evidence current',
        DataState.forecast => 'Model forecast evidence',
        DataState.cached => 'Cached evidence',
        DataState.stale => 'Stale evidence',
        DataState.loading => 'Loading evidence',
        DataState.offline => 'Offline — cached only',
        DataState.error => 'Evidence unavailable',
        DataState.unavailable => 'No verified evidence',
      };

  /// Safe-window text comes from the backend's own `safe_window` contract.
  /// When the backend says UNAVAILABLE, so does ORCA.
  static String _windowLabel(SafeWindow? window) {
    if (window == null) return 'Validity window unavailable';
    final status = window.status?.toUpperCase();
    if (status == 'UNAVAILABLE') return 'No safe window published';
    final hours = window.hoursRemaining;
    if (hours != null && hours > 0) {
      return 'Window ${hours.toStringAsFixed(0)} h';
    }
    if (window.from.isNotEmpty && window.to.isNotEmpty) {
      return 'Window ${window.from} – ${window.to}';
    }
    return 'Validity window unavailable';
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;
  const _HeroChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: highlight
              ? OrcaTheme.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlight
                ? OrcaTheme.accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: highlight ? OrcaTheme.accent : OrcaTheme.onDeepTealMuted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: highlight ? OrcaTheme.accent : OrcaTheme.onDeepTeal,
              ),
            ),
          ],
        ),
      );
}

/// "Right now — Coastal conditions" panel: a 2×N grid of real readings.
class OverviewConditionsPanel extends StatelessWidget {
  final MarineConditionsDto? conditions;
  final bool stale;
  final bool offline;
  final bool loading;
  final VoidCallback? onRetry;

  const OverviewConditionsPanel({
    super.key,
    required this.conditions,
    this.stale = false,
    this.offline = false,
    this.loading = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = conditions;

    // Panel-level state: the badge above the grid must describe the whole
    // panel truthfully, so it reflects the weakest real state present.
    final DataState panelState;
    if (loading && c == null) {
      panelState = DataState.loading;
    } else if (offline) {
      panelState = DataState.offline;
    } else if (c == null || c.hasError) {
      panelState = DataState.error;
    } else if (stale) {
      panelState = DataState.stale;
    } else if (c.isCached) {
      panelState = DataState.cached;
    } else if (_anyValue(c)) {
      // Open-Meteo marine/forecast values are model fields, so the honest
      // panel word is FORECAST rather than LIVE.
      panelState = DataState.forecast;
    } else {
      panelState = DataState.unavailable;
    }

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: OrcaEyebrow('RIGHT NOW')),
              OrcaStateBadge(state: panelState, dense: true),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Coastal conditions',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 21,
              letterSpacing: -0.4,
              fontWeight: FontWeight.w800,
              color: OrcaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          if (c != null && c.hasError)
            OrcaEmptyState(
              dense: true,
              state: DataState.error,
              icon: Icons.cloud_off_rounded,
              title: 'Marine readings unavailable',
              message: c.error ??
                  'The marine providers did not return conditions for this '
                      'location. No values are shown rather than estimated ones.',
              actionLabel: onRetry == null ? null : 'Retry',
              onAction: onRetry,
            )
          else
            _grid(c),
          if (c != null && c.sourcesFailed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: VerdictColors.cautionBg,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 15, color: VerdictColors.caution),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Source unavailable: ${c.sourcesFailed.join(', ')}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        height: 1.4,
                        color: OrcaTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static bool _anyValue(MarineConditionsDto c) =>
      c.waveHeightM != null ||
      c.windKn != null ||
      c.swellPeriodS != null ||
      c.seaTempC != null ||
      c.chlorophyllMgM3 != null ||
      c.currentSpeedKn != null;

  Widget _grid(MarineConditionsDto? c) {
    Provenance prov(String key, bool hasValue) => c == null
        ? Provenance(
            state: loading
                ? DataState.loading
                : offline
                    ? DataState.offline
                    : DataState.unavailable,
          )
        : c.provenanceFor(key, hasValue: hasValue, stale: stale, offline: offline);

    final tiles = <Widget>[
      OrcaMetricTile(
        icon: Icons.waves_rounded,
        label: 'Wave height',
        value: c?.waveHeightM?.toStringAsFixed(1),
        unit: 'm',
        provenance: prov('wave_height_m', c?.waveHeightM != null),
        compact: true,
      ),
      OrcaMetricTile(
        icon: Icons.air_rounded,
        label: 'Wind',
        value: c?.windKn?.toStringAsFixed(0),
        unit: 'kn',
        // Direction is only shown when the provider supplied it.
        note: c?.windDirection == null ? null : '${c!.windDirection}°',
        provenance: prov('wind_speed_kn', c?.windKn != null),
        compact: true,
      ),
      OrcaMetricTile(
        icon: Icons.speed_rounded,
        label: 'Gust',
        value: c?.windGustKn?.toStringAsFixed(0),
        unit: 'kn',
        provenance: prov('wind_gust_kn', c?.windGustKn != null),
        compact: true,
      ),
      OrcaMetricTile(
        icon: Icons.swap_calls_rounded,
        label: 'Swell period',
        value: c?.swellPeriodS?.toStringAsFixed(1),
        unit: 's',
        provenance: prov('wave_period_s', c?.swellPeriodS != null),
        compact: true,
      ),
      OrcaMetricTile(
        icon: Icons.thermostat_rounded,
        label: 'Sea temp',
        value: c?.seaTempC?.toStringAsFixed(1),
        unit: '°C',
        provenance: prov('sst_celsius', c?.seaTempC != null),
        compact: true,
      ),
      OrcaMetricTile(
        icon: Icons.eco_outlined,
        label: 'Chlorophyll',
        value: c?.chlorophyllMgM3?.toStringAsFixed(2),
        unit: 'mg/m³',
        provenance: prov('chlorophyll_mg_m3', c?.chlorophyllMgM3 != null),
        compact: true,
      ),
    ];

    return OrcaCardGrid(
      desktopColumns: 2,
      spacing: 11,
      breakpoint: 380,
      children: tiles,
    );
  }
}

/// Compact signal row used by "Signals to keep in mind".
class OverviewSignalTile extends StatelessWidget {
  final String title;
  final String detail;
  final String severity;
  final String? source;
  final String? time;
  final VoidCallback? onTap;

  const OverviewSignalTile({
    super.key,
    required this.title,
    required this.detail,
    required this.severity,
    this.source,
    this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unspecified = severity.toUpperCase() == 'UNSPECIFIED';
    final color =
        unspecified ? OrcaTheme.textMuted : VerdictColors.fromVerdict(severity);
    return OrcaCard(
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              unspecified
                  ? Icons.campaign_outlined
                  : VerdictColors.iconForVerdict(severity),
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
                if (detail.isNotEmpty && detail != title) ...[
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      height: 1.4,
                      color: OrcaTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  // Source and time are printed verbatim or declared missing.
                  '${source ?? 'Source unavailable'} · ${time ?? 'Time unavailable'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    color: OrcaTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OrcaSeverityPill(severity: severity),
        ],
      ),
    );
  }
}

/// Service / agent status row used in "ORCA services".
class OverviewServiceRow extends StatelessWidget {
  final String name;
  final String statusLabel;
  final DataState state;
  final String? detail;

  const OverviewServiceRow({
    super.key,
    required this.name,
    required this.statusLabel,
    required this.state,
    this.detail,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$name: $statusLabel',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: state.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: OrcaTheme.textPrimary,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          color: OrcaTheme.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: state.color,
                ),
              ),
            ],
          ),
        ),
      );
}
