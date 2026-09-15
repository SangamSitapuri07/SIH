import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/source_footer.dart';
import '../../../../core/widgets/staleness_badge.dart';
import '../../domain/entities/zone_snapshot.dart';

/// Compact data inspector for an actual map point response.
class ProbeBottomSheet extends StatelessWidget {
  final ZoneSnapshot snapshot;
  final VoidCallback onClose;

  const ProbeBottomSheet({super.key, required this.snapshot, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OrcaTheme.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MARINE CONDITIONS', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800, color: OrcaTheme.accentDark)),
            const SizedBox(height: 3),
            Text(GeoUtils.formatCoordinate(snapshot.lat, snapshot.lon), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: OrcaTheme.textPrimary)),
          ])),
          StalenessBadge(staleness: snapshot.staleness),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: 'Close point inspector'),
        ]),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.55,
          children: [
            _Metric(label: 'Wind', value: Formatters.windKnots(snapshot.windSpeedKn), available: snapshot.windSpeedKn != null, icon: Icons.air),
            _Metric(label: 'Wave', value: Formatters.waveHeight(snapshot.waveHeightM), available: snapshot.waveHeightM != null, icon: Icons.waves_rounded),
            _Metric(label: 'Sea surface temp', value: Formatters.temperature(snapshot.seaTempC), available: snapshot.seaTempC != null, icon: Icons.thermostat_outlined),
            _Metric(label: 'Chlorophyll', value: Formatters.chlorophyll(snapshot.chlorophyllMgM3), available: snapshot.chlorophyllMgM3 != null, icon: Icons.blur_on_outlined),
          ],
        ),
        const SizedBox(height: 10),
        SourceFooter(
          sources: snapshot.sources,
          timeLabel: 'Updated ${DateFormatter.formatIstTime(snapshot.timestamp)}',
        ),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final bool available;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.available, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: OrcaTheme.surfaceElevated, borderRadius: BorderRadius.circular(9)),
    child: Row(children: [
      Icon(icon, size: 16, color: OrcaTheme.accentDark), const SizedBox(width: 6),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(fontSize: 9.5, color: OrcaTheme.textSecondary, fontWeight: FontWeight.w700)),
        Text(available ? value : 'Unavailable', style: TextStyle(fontSize: available ? 12.5 : 11, color: available ? OrcaTheme.textPrimary : OrcaTheme.textMuted, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}
