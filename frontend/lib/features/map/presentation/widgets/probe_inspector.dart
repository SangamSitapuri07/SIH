import 'package:flutter/material.dart';

import '../../../../core/cache/staleness.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/zone_snapshot.dart';

/// Selected-area inspector for a real `/api/v1/zone` response.
///
/// Missing measurements stay "Unavailable" with their provenance preserved;
/// the panel never substitutes a plausible number for a silent provider.
class ProbeInspector extends StatelessWidget {
  final ZoneSnapshot snapshot;
  final VoidCallback? onClear;

  const ProbeInspector({super.key, required this.snapshot, this.onClear});

  @override
  Widget build(BuildContext context) {
    final bool cached = snapshot.staleness.isCached;

    return OrcaCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const OrcaEyebrow('INSPECTED POINT', color: OrcaTheme.accentDark),
                    const SizedBox(height: 4),
                    Text(
                      GeoUtils.formatCoordinate(snapshot.lat, snapshot.lon),
                      style: OrcaType.sectionTitle.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'ORCA retrieved ${DateFormatter.formatIstTime(snapshot.timestamp)}',
                      style: OrcaType.caption,
                    ),
                  ],
                ),
              ),
              OrcaStateChip(
                state: resolveDataState(
                  hasValue: true,
                  isCached: cached,
                  isStale: snapshot.staleness.state == StalenessState.stale,
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear inspected point',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _ProbeGrid(
            children: <Widget>[
              _ProbeMetric(
                label: 'Wave height',
                icon: Icons.waves_rounded,
                value: snapshot.waveHeightM,
                unit: 'm',
                decimals: 1,
              ),
              _ProbeMetric(
                label: 'Wind',
                icon: Icons.air_rounded,
                value: snapshot.windSpeedKn,
                unit: 'kn',
                decimals: 1,
                note: snapshot.windDirection,
              ),
              _ProbeMetric(
                label: 'Swell period',
                icon: Icons.tsunami_rounded,
                value: snapshot.swellPeriodS,
                unit: 's',
                decimals: 1,
              ),
              _ProbeMetric(
                label: 'Sea temp',
                icon: Icons.thermostat_rounded,
                value: snapshot.seaTempC,
                unit: '°C',
                decimals: 1,
              ),
              _ProbeMetric(
                label: 'Surface current',
                icon: Icons.navigation_rounded,
                value: snapshot.currentSpeedKn,
                unit: 'kn',
                decimals: 2,
                note: snapshot.currentDirection,
              ),
              _ProbeMetric(
                label: 'Chlorophyll-a',
                icon: Icons.bubble_chart_outlined,
                value: snapshot.chlorophyllMgM3,
                unit: 'mg/m³',
                decimals: 2,
              ),
            ],
          ),
          if (snapshot.fishingEffortHours != null) ...<Widget>[
            const SizedBox(height: 10),
            OrcaInfoPill(
              icon: Icons.sailing_outlined,
              label: 'Fishing effort ${snapshot.fishingEffortHours!.toStringAsFixed(1)} h · Global Fishing Watch',
              tint: OrcaTheme.textSecondary,
            ),
          ],
          const SizedBox(height: 10),
          OrcaProvenance(
            source: snapshot.sources.isEmpty ? 'No verified source' : snapshot.sources.join(' · '),
            stateLabel: snapshot.sourcesFailed.isEmpty
                ? null
                : 'Unavailable: ${snapshot.sourcesFailed.join(', ')}',
            maxLines: 3,
          ),
          if (snapshot.sourcesFailed.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.error_outline_rounded, size: 14, color: VerdictColors.caution),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Missing values above are not estimates: the provider did not return them.',
                    style: OrcaType.caption,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProbeGrid extends StatelessWidget {
  final List<Widget> children;

  const _ProbeGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int index = 0; index < children.length; index += 2) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: children[index]),
              const SizedBox(width: 8),
              Expanded(
                child: index + 1 < children.length ? children[index + 1] : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      if (index + 2 < children.length) rows.add(const SizedBox(height: 8));
    }
    return Column(children: rows);
  }
}

class _ProbeMetric extends StatelessWidget {
  final String label;
  final IconData icon;
  final double? value;
  final String unit;
  final int decimals;
  final String? note;

  const _ProbeMetric({
    required this.label,
    required this.icon,
    required this.value,
    required this.unit,
    required this.decimals,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final bool available = value != null;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: OrcaTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: OrcaType.metricLabel.copyWith(fontSize: 11.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 14, color: OrcaTheme.accentDark),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Flexible(
                child: Text(
                  available ? value!.toStringAsFixed(decimals) : kOrcaUnavailableValue,
                  style: available
                      ? OrcaType.metricValue.copyWith(fontSize: 19)
                      : OrcaType.metricValue.copyWith(fontSize: 12.5, color: OrcaTheme.textMuted, letterSpacing: 0),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (available) ...<Widget>[
                const SizedBox(width: 3),
                Text(unit, style: OrcaType.metricUnit.copyWith(fontSize: 11)),
              ],
            ],
          ),
          if (available && note != null && note!.trim().isNotEmpty)
            Text(note!.trim(), style: OrcaType.caption.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
