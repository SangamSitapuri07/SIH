import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';

/// Forecast evidence chart.
///
/// Both series are the provider's own hourly values. Wind is drawn on the same
/// axis divided by ten (labelled as such) so the two series stay comparable;
/// values are never interpolated or replaced. The horizontal caution line is
/// the backend's 2.5 m small-craft limit.
class HourlyChart extends StatelessWidget {
  final List<HourlyPoint> hourlyPoints;

  const HourlyChart({super.key, required this.hourlyPoints});

  @override
  Widget build(BuildContext context) {
    if (hourlyPoints.isEmpty) {
      return const OrcaUnavailable(
        icon: Icons.timeline_rounded,
        title: 'No forecast series returned',
        message: 'The ORCA Box did not return an hourly wave and wind series, so no trend can be plotted.',
      );
    }

    final List<FlSpot> waveSpots = <FlSpot>[];
    final List<FlSpot> windSpots = <FlSpot>[];
    for (int index = 0; index < hourlyPoints.length; index++) {
      waveSpots.add(FlSpot(index.toDouble(), hourlyPoints[index].waveM));
      windSpots.add(FlSpot(index.toDouble(), hourlyPoints[index].windKn / 10.0));
    }

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('FORECAST EVIDENCE', color: OrcaTheme.textMuted)),
              const OrcaStateChip(state: OrcaDataState.forecast),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Wave and wind trend', style: OrcaType.cardTitle),
          const SizedBox(height: 4),
          Text(
            '${hourlyPoints.length} hourly model steps returned by the prediction providers.',
            style: OrcaType.caption,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1.0,
                  getDrawingHorizontalLine: (double value) {
                    if (value == 2.5) {
                      return const FlLine(
                        color: VerdictColors.caution,
                        strokeWidth: 1.4,
                        dashArray: <int>[4, 4],
                      );
                    }
                    return FlLine(color: OrcaTheme.cardBorder, strokeWidth: 1);
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1.0,
                      getTitlesWidget: (double value, TitleMeta meta) => Text(
                        '${value.toInt()}m',
                        style: const TextStyle(fontSize: 9.5, color: OrcaTheme.textMuted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (hourlyPoints.length / 4).ceilToDouble().clamp(1, 24),
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final int index = value.toInt();
                        if (index < 0 || index >= hourlyPoints.length) return const SizedBox.shrink();
                        final DateTime? parsed = DateFormatter.parseIso(hourlyPoints[index].hour);
                        final String label = parsed == null
                            ? hourlyPoints[index].hour
                            : DateFormat('HH:mm').format(
                                parsed.toUtc().add(const Duration(hours: 5, minutes: 30)),
                              );
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            label,
                            style: const TextStyle(fontSize: 9, color: OrcaTheme.textMuted),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (hourlyPoints.length - 1).toDouble(),
                minY: 0,
                maxY: 4.5,
                lineBarsData: <LineChartBarData>[
                  LineChartBarData(
                    spots: waveSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: VerdictColors.info,
                    barWidth: 2.4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: VerdictColors.info.withValues(alpha: 0.10),
                    ),
                  ),
                  LineChartBarData(
                    spots: windSpots,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: VerdictColors.caution,
                    barWidth: 1.8,
                    dashArray: <int>[3, 3],
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: const <Widget>[
              _LegendDot(label: 'Wave height (m)', color: VerdictColors.info),
              _LegendDot(label: 'Wind (kn ÷ 10)', color: VerdictColors.caution),
              _LegendDot(label: '2.5 m caution limit', color: VerdictColors.caution),
            ],
          ),
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'Open-Meteo Marine (MFWAM/ECMWF) · Open-Meteo Forecast (ECMWF IFS)',
            timeLabel: 'Hourly model valid times in IST; values are provider forecasts, not observations',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: OrcaType.caption.copyWith(fontSize: 10.5, color: OrcaTheme.textSecondary)),
        ],
      );
}
