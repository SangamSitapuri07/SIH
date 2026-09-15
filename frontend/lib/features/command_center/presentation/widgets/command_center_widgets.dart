import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../data/dto/command_center_dto.dart';

/// Shared card scaffold: white surface, 16 radius, hairline border.
class CcCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const CcCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OrcaTheme.cardBorder, width: 1),
      ),
      child: child,
    );
  }
}

/// Uppercase section header with optional trailing action.
class CcSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CcSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: OrcaTheme.textSecondary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: OrcaTheme.accentDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// System status pill under the ORCA wordmark: derived from real health data.
class CcSystemStatusChip extends StatelessWidget {
  final String overall;
  final bool live;

  const CcSystemStatusChip({
    super.key,
    required this.overall,
    required this.live,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (overall) {
      case 'OPERATIONAL':
        color = VerdictColors.go;
        break;
      case 'OFFLINE':
        color = VerdictColors.noGo;
        break;
      default:
        color = VerdictColors.caution;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: live
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            overall,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// HERO: Marine risk card — deep-teal panel like the reference map card.
/// Verdict from the real advisory; metrics from the real zone snapshot.
class CcHeroRiskCard extends StatelessWidget {
  final String? verdict; // advisory verdict string
  final String locationLabel;
  final double? waveM;
  final double? windKn;
  final double? gustKn;

  const CcHeroRiskCard({
    super.key,
    this.verdict,
    required this.locationLabel,
    this.waveM,
    this.windKn,
    this.gustKn,
  });

  String get _verdictLabel {
    final v = verdict?.toLowerCase() ?? '';
    if (v.contains('go') && !v.contains('no_go') && !v.contains('nogo')) {
      return 'SAFE';
    }
    if (v.contains('caution') || v.contains('mod')) return 'CAUTION';
    if (v.contains('no_go') || v.contains('nogo') || v.contains('danger')) {
      return 'DANGEROUS';
    }
    return 'UNAVAILABLE';
  }

  Color get _verdictColor => VerdictColors.fromVerdict(verdict);

  @override
  Widget build(BuildContext context) {
    final c = _verdictColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OrcaTheme.deepTeal,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'MARINE RISK'.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: OrcaTheme.onDeepTealMuted,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.withValues(alpha: 0.7)),
                ),
                child: Text(
                  _verdictLabel,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: c,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            locationLabel,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: OrcaTheme.onDeepTeal,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _HeroMetric(
                label: 'WAVE',
                value: waveM != null ? waveM!.toStringAsFixed(1) : null,
                unit: 'm',
              ),
              const SizedBox(width: 12),
              _HeroMetric(
                label: 'WIND',
                value: windKn != null ? windKn!.toStringAsFixed(0) : null,
                unit: 'kn',
              ),
              const SizedBox(width: 12),
              _HeroMetric(
                label: 'GUST',
                value: gustKn != null ? gustKn!.toStringAsFixed(0) : null,
                unit: 'kn',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String? value;
  final String unit;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: OrcaTheme.deepTealElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: OrcaTheme.onDeepTealMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value != null ? '$value $unit' : 'Unavailable',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: value != null ? 17 : 13,
                fontWeight: FontWeight.w800,
                color: OrcaTheme.onDeepTeal,
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

/// Weather card: rows of metric chips sourced from the zone snapshot.
class CcWeatherCard extends StatelessWidget {
  final MarineConditionsDto? conditions;

  const CcWeatherCard({super.key, this.conditions});

  @override
  Widget build(BuildContext context) {
    final c = conditions;
    return CcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(
              icon: Icons.air, title: 'Weather', sourceLabel: _sourceOf),
          const SizedBox(height: 12),
          Row(
            children: [
              _MetricCell(
                label: 'Wind',
                value: c?.windKn?.toStringAsFixed(0) != null
                    ? '${c!.windKn!.toStringAsFixed(0)} kn'
                    : null,
                icon: Icons.air,
              ),
              _MetricCell(
                label: 'Gusts',
                value: c?.windGustKn?.toStringAsFixed(0) != null
                    ? '${c!.windGustKn!.toStringAsFixed(0)} kn'
                    : null,
                icon: Icons.storm,
              ),
              _MetricCell(
                label: 'Sea temp',
                value: c?.seaTempC?.toStringAsFixed(1) != null
                    ? '${c!.seaTempC!.toStringAsFixed(1)} °C'
                    : null,
                icon: Icons.thermostat,
              ),
            ],
          ),
          if (c != null && c.sources.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Source: ${c.sources.join(' · ')}',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: OrcaTheme.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static String _sourceOf(MarineConditionsDto? c) =>
      c?.sources.isNotEmpty == true ? c!.sources.first : 'Live providers';
}

/// Fishing intelligence card from real PFZ data (INCOIS) only.
class CcFishingCard extends StatelessWidget {
  final int pfzCount;
  final String? pfzSource;
  final VoidCallback? onOpenMap;

  const CcFishingCard({
    super.key,
    required this.pfzCount,
    this.pfzSource,
    this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = pfzCount > 0;
    return CcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (hasData ? VerdictColors.go : VerdictColors.stale)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.phishing,
                  size: 19,
                  color: hasData ? VerdictColors.go : VerdictColors.stale,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fishing Intelligence',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: OrcaTheme.textPrimary,
                      ),
                    ),
                    Text(
                      hasData
                          ? '${pfzSource ?? 'INCOIS'} · $pfzCount active zone${pfzCount == 1 ? '' : 's'}'
                          : 'PFZ data unavailable right now',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        color: OrcaTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasData && onOpenMap != null)
                TextButton(
                  onPressed: onOpenMap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 36),
                  ),
                  child: const Text(
                    'View map',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: OrcaTheme.accentDark,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cyclone watch card built strictly from official alerts (no invention).
class CcCycloneCard extends StatelessWidget {
  final List<CycloneWatchItem> alerts;

  const CcCycloneCard({super.key, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return CcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (alerts.isNotEmpty
                          ? VerdictColors.caution
                          : VerdictColors.stale)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.cyclone,
                  size: 19,
                  color: alerts.isNotEmpty
                      ? VerdictColors.caution
                      : VerdictColors.stale,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cyclone Watch',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (alerts.isEmpty)
            const Text(
              'No active cyclone data',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: OrcaTheme.textSecondary,
              ),
            )
          else
            ...alerts.take(3).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: VerdictColors.fromVerdict(a.severity),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: OrcaTheme.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${a.source}${a.time != null ? ' · ${_fmt(a.time!)}' : ''}',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: OrcaTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  String _fmt(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('d MMM · HH:mm').format(dt.toLocal());
  }
}

/// Source health rows (Data Sources transparency) from /health.
class CcSourceHealthCard extends StatelessWidget {
  final SystemHealthDto? health;

  const CcSourceHealthCard({super.key, this.health});

  @override
  Widget build(BuildContext context) {
    final h = health;
    return CcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Data Sources',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
              ),
              if (h == null || !h.reachable)
                const Text(
                  'Backend unreachable',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: VerdictColors.noGo,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (h == null || h.sources.isEmpty)
            const Text(
              'Source status unavailable',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                color: OrcaTheme.textSecondary,
              ),
            )
          else
            ...h.sources.take(6).map((s) {
              final ok = s.isUsable;
              final color = ok ? VerdictColors.go : VerdictColors.caution;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.name,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: OrcaTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      s.latencyMs != null ? '${s.latencyMs} ms' : s.status,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ok
                            ? OrcaTheme.textSecondary
                            : VerdictColors.caution,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String Function(MarineConditionsDto?) sourceLabel;

  const _CardHeader({
    required this.icon,
    required this.title,
    required this.sourceLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: OrcaTheme.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: OrcaTheme.accentDark),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: OrcaTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;

  const _MetricCell({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: OrcaTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OrcaTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value ?? 'Unavailable',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: value != null ? 16 : 12.5,
              fontWeight: value != null ? FontWeight.w800 : FontWeight.w500,
              color: value != null
                  ? OrcaTheme.textPrimary
                  : OrcaTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
