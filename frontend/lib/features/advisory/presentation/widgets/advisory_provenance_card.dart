import 'package:flutter/material.dart';

import '../../../../core/cache/staleness.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';

/// Provenance, coverage and cache state for the advisory currently on screen.
class AdvisoryProvenanceCard extends StatelessWidget {
  final AdvisoryEntity advisory;
  final bool offline;
  final bool streamLive;

  const AdvisoryProvenanceCard({
    super.key,
    required this.advisory,
    required this.offline,
    required this.streamLive,
  });

  @override
  Widget build(BuildContext context) {
    final OrcaDataState state = resolveDataState(
      hasValue: true,
      isOffline: offline,
      isStale: advisory.staleness.state == StalenessState.stale,
      isCached: advisory.staleness.isCached,
      isLive: streamLive,
    );

    return OrcaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('PROVENANCE & COVERAGE', color: OrcaTheme.textMuted)),
              OrcaStateChip(state: state),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _Fact(
                  label: 'Sources verified',
                  value: '${advisory.knownSources}/${advisory.totalSources}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Fact(
                  label: 'Retrieved',
                  value: DateFormatter.formatIstTime(advisory.timestamp),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Fact(
                  label: 'Cache state',
                  value: advisory.staleness.isCached ? 'Cached' : 'Live response',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const OrcaEyebrow('SOURCES CONTRIBUTING EVIDENCE', color: OrcaTheme.textMuted),
          const SizedBox(height: 6),
          if (advisory.sources.isEmpty)
            Text('No provider reported usable data for this request.', style: OrcaType.body.copyWith(fontSize: 12.5))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String source in advisory.sources)
                  OrcaInfoPill(icon: Icons.check_circle_outline, label: source, tint: OrcaTheme.accentDark),
              ],
            ),
          if (advisory.sourcesFailed.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const OrcaEyebrow('SOURCES NOT AVAILABLE', color: OrcaTheme.textMuted),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String source in advisory.sourcesFailed)
                  OrcaInfoPill(icon: Icons.error_outline_rounded, label: source, tint: VerdictColors.caution),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Values these sources own are shown as unavailable — ORCA does not substitute estimates.',
              style: OrcaType.caption,
            ),
          ],
          const SizedBox(height: 12),
          OrcaProvenance(
            source: 'GET /api/v1/advisory',
            timeLabel: 'Snapshot retrieved ${DateFormatter.formatIstTime(advisory.timestamp)}',
            stateLabel: state.label,
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: OrcaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label.toUpperCase(), style: OrcaType.eyebrowMuted.copyWith(fontSize: 9, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text(value, style: OrcaType.sectionTitle.copyWith(fontSize: 13.5)),
          ],
        ),
      );
}
