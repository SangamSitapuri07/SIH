import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/route_check.dart';

/// Sampled route points returned by `/api/v1/route-advisory`.
///
/// A point whose marine inputs were unavailable is listed as
/// `unverified` with the backend's own reason — it is never shown as safe.
class TransitPointsStrip extends StatelessWidget {
  final List<TransitPoint> points;

  const TransitPointsStrip({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const OrcaUnavailable(
        icon: Icons.timeline_rounded,
        title: 'No route samples returned',
        message: 'The backend returned no sampled points for this leg, so no transit evidence can be shown.',
        compact: true,
      );
    }

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OrcaEyebrow('SAMPLED TRANSIT POINTS', color: OrcaTheme.textMuted),
          const SizedBox(height: 8),
          const Text('Conditions along the leg', style: OrcaType.cardTitle),
          const SizedBox(height: 4),
          Text(
            '${points.length} sample${points.length == 1 ? '' : 's'} requested from the ORCA Box along this course.',
            style: OrcaType.caption,
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < points.length; index++)
            _PointRow(point: points[index], isLast: index == points.length - 1),
        ],
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final TransitPoint point;
  final bool isLast;

  const _PointRow({required this.point, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final bool unverified = point.state.toLowerCase() == 'unverified';
    final Color color = unverified ? OrcaTheme.textMuted : VerdictColors.fromVerdict(point.state);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: unverified ? OrcaTheme.surface : color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: OrcaTheme.cardBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        point.sailKm == null
                            ? 'Distance along course unavailable'
                            : '${point.sailKm!.toStringAsFixed(0)} km from departure',
                        style: OrcaType.metricLabel.copyWith(
                          fontSize: 12,
                          color: OrcaTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      OrcaStateChip(
                        state: unverified ? OrcaDataState.unavailable : OrcaDataState.current,
                        overrideLabel: point.state.toUpperCase(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    point.waveM == null || point.windKn == null
                        ? 'Marine inputs unavailable at this point'
                        : 'Wave ${point.waveM!.toStringAsFixed(1)} m · Wind ${point.windKn!.toStringAsFixed(1)} kn',
                    style: OrcaType.body.copyWith(
                      fontSize: 12.5,
                      color: OrcaTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(point.why, style: OrcaType.caption),
                  if (point.lat != null && point.lon != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '${point.lat!.toStringAsFixed(3)}, ${point.lon!.toStringAsFixed(3)}',
                      style: OrcaType.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
