import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/alert_item.dart';

/// One provider alert. Source, issue time and severity come straight from the
/// feed; a missing field stays missing.
class AlertCard extends StatelessWidget {
  final AlertItem alert;
  final bool reviewed;
  final VoidCallback? onReviewed;

  const AlertCard({super.key, required this.alert, this.reviewed = false, this.onReviewed});

  /// `.orca-feed-severity` fills: high #fde5e2/#c2453b, medium #fff1d7/#b77817,
  /// low #e2f4f3/#168b8c. UNSPECIFIED keeps the neutral low pair because the
  /// official feeds do not publish a severity for it.
  static Color _severityFill(String? severity) {
    switch ((severity ?? '').toUpperCase()) {
      case 'CRITICAL':
      case 'HIGH':
        return OrcaTheme.dangerBg;
      case 'WARNING':
      case 'MEDIUM':
        return OrcaTheme.warnBg;
      case 'INFO':
      case 'LOW':
        return OrcaTheme.liveBg;
      default:
        return OrcaTheme.infoBg;
    }
  }

  static Color _severityInk(String? severity) {
    switch ((severity ?? '').toUpperCase()) {
      case 'CRITICAL':
      case 'HIGH':
        return OrcaTheme.dangerFg;
      case 'WARNING':
      case 'MEDIUM':
        return OrcaTheme.warnFg;
      case 'INFO':
      case 'LOW':
        return OrcaTheme.liveFg;
      default:
        return OrcaTheme.infoFg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String severity = (alert.severity ?? 'UNSPECIFIED').toUpperCase();

    return OrcaCard(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: _severityFill(alert.severity),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  VerdictColors.iconForVerdict(alert.severity),
                  size: 17,
                  color: _severityInk(alert.severity),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        OrcaStateChip(
                          state: OrcaDataState.current,
                          overrideLabel: severity,
                          showIcon: false,
                        ),
                        if (!reviewed) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: OrcaTheme.deepTeal,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'NEW ON THIS DEVICE',
                              style: TextStyle(
                                fontSize: 8.5,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      alert.title,
                      style: OrcaType.sectionTitle.copyWith(fontSize: 15),
                    ),
                    if (alert.titleHi != null && alert.titleHi!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(alert.titleHi!, style: OrcaType.body.copyWith(fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(alert.message, style: OrcaType.body.copyWith(fontSize: 12.5, color: OrcaTheme.textPrimary)),
          if (alert.messageHi != null && alert.messageHi!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(alert.messageHi!, style: OrcaType.body.copyWith(fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OrcaInfoPill(icon: Icons.verified_outlined, label: alert.source ?? 'Source unavailable'),
              OrcaInfoPill(
                icon: Icons.schedule_rounded,
                label: alert.issuedAt == null
                    ? 'Issue time unavailable'
                    : 'Issued ${DateFormatter.formatIstTime(alert.issuedAt!)}',
              ),
              if (alert.expiresAt != null)
                OrcaInfoPill(
                  icon: Icons.event_busy_outlined,
                  label: 'Expires ${DateFormatter.formatIstTime(alert.expiresAt!)}',
                ),
              if (alert.affectedArea != null)
                OrcaInfoPill(icon: Icons.place_outlined, label: alert.affectedArea!),
              if (alert.isActive != null)
                OrcaInfoPill(
                  icon: alert.isActive! ? Icons.check_circle_outline : Icons.pause_circle_outline,
                  label: alert.isActive! ? 'Feed marks it active' : 'Feed marks it inactive',
                ),
            ],
          ),
          if (onReviewed != null && !reviewed) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onReviewed,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                child: const Text('Mark as reviewed', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
