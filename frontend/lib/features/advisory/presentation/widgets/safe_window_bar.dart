import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';

/// Departure-window card.
///
/// The window, its limits and its quality are computed by the deterministic
/// backend engine. If the engine published no window, this card says exactly
/// that — it never shortens or invents a departure time.
class SafeWindowBar extends StatelessWidget {
  final SafeWindow? safeWindow;

  const SafeWindowBar({super.key, required this.safeWindow});

  @override
  Widget build(BuildContext context) {
    if (safeWindow == null) {
      return const OrcaUnavailable(
        icon: Icons.timer_off_outlined,
        title: 'Departure window unavailable',
        message: 'The ORCA Box did not return a safe-departure-window calculation for this request, so no window is shown.',
      );
    }

    final SafeWindow window = safeWindow!;
    final String status = (window.status ?? '').toUpperCase();
    final bool hasWindow = window.from.isNotEmpty &&
        window.to.isNotEmpty &&
        (status.isEmpty || status == 'AVAILABLE' || status == 'CAUTION');
    final bool caution = status == 'CAUTION' || (window.quality ?? '').toUpperCase() == 'CAUTION';
    final Color color = !hasWindow
        ? OrcaTheme.textMuted
        : caution
            ? VerdictColors.caution
            : VerdictColors.go;

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('DEPARTURE WINDOW', color: OrcaTheme.textMuted)),
              OrcaStateChip(
                state: hasWindow ? OrcaDataState.forecast : OrcaDataState.unavailable,
                overrideLabel: hasWindow
                    ? (caution ? 'CAUTION WINDOW' : 'VERIFIED WINDOW')
                    : 'UNAVAILABLE',
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasWindow) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  caution ? Icons.warning_amber_rounded : Icons.access_time_filled_rounded,
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_format(window.from)} → ${_format(window.to)}',
                    style: OrcaType.cardTitle.copyWith(fontSize: 18),
                  ),
                ),
              ],
            ),
            if (window.hoursRemaining != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '${window.hoursRemaining!.toStringAsFixed(0)} hour window${window.quality == null ? '' : ' · engine quality ${window.quality}'}',
                style: OrcaType.caption,
              ),
            ],
          ] else
            Text(
              status == 'UNAVAILABLE'
                  ? 'No qualifying departure window in the returned forecast horizon.'
                  : 'Departure window status could not be verified.',
              style: OrcaType.body.copyWith(fontSize: 12.5),
            ),
          if (hasWindow && (window.maxWaveM != null || window.maxWindKn != null)) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (window.maxWaveM != null)
                  OrcaInfoPill(icon: Icons.waves_rounded, label: 'peak wave ${window.maxWaveM!.toStringAsFixed(1)} m'),
                if (window.maxWindKn != null)
                  OrcaInfoPill(icon: Icons.air_rounded, label: 'peak wind ${window.maxWindKn!.toStringAsFixed(1)} kn'),
                if (window.maxGustKn != null)
                  OrcaInfoPill(icon: Icons.storm_rounded, label: 'peak gust ${window.maxGustKn!.toStringAsFixed(1)} kn'),
              ],
            ),
          ],
          if (window.recommendationEn != null && window.recommendationEn!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: OrcaTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                window.recommendationEn!,
                style: OrcaType.body.copyWith(fontSize: 12.5, color: OrcaTheme.textPrimary, height: 1.5),
              ),
            ),
          ],
          if (window.note != null && window.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline_rounded, size: 14, color: VerdictColors.caution),
                const SizedBox(width: 6),
                Expanded(child: Text(window.note!, style: OrcaType.caption)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'ORCA deterministic safe-window engine',
            timeLabel: 'GOOD limits: wave < 2.0 m, wind < 15 kn, gust < 25 kn · caution limits 2.5 m / 20 kn / 34 kn',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  static String _format(String raw) {
    final DateTime? parsed = DateFormatter.parseIso(raw);
    if (parsed == null) return raw;
    return DateFormatter.formatIstTime(parsed);
  }
}
