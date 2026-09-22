import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/route_check.dart';

/// Route result surface driven strictly by the backend response.
///
/// Distance and bearing are deterministic calculations of the submitted
/// coordinates; land clearance is shown as unverified whenever the land-mask
/// provider did not answer. No detour is ever drawn by the client.
class RouteVerdictCard extends StatelessWidget {
  final RouteAdvisoryEntity advisory;
  final RouteCheckEntity? check;

  const RouteVerdictCard({super.key, required this.advisory, this.check});

  /// Reference `.orca-result-verdict`: GO/clear = #e1f5f2/#bfe8e2/#147b6a,
  /// caution = #fff4dc/#f2dfae/#9d6915, no-go = danger pair.
  static Color _resultFill(String level) {
    switch (level.toUpperCase()) {
      case 'GO':
      case 'CLEAR':
        return OrcaTheme.liveBg;
      case 'CAUTION':
        return OrcaTheme.warnBg;
      case 'NO_GO':
      case 'NO-GO':
      case 'DANGER':
        return OrcaTheme.dangerBg;
      default:
        return OrcaTheme.infoBg;
    }
  }

  static Color _resultBorder(String level) {
    switch (level.toUpperCase()) {
      case 'GO':
      case 'CLEAR':
        return const Color(0xFFBFE8E2);
      case 'CAUTION':
        return const Color(0xFFF2DFAE);
      case 'NO_GO':
      case 'NO-GO':
      case 'DANGER':
        return OrcaTheme.dangerBorder;
      default:
        return OrcaTheme.cardBorder;
    }
  }

  static Color _resultInk(String level) {
    switch (level.toUpperCase()) {
      case 'GO':
      case 'CLEAR':
        return OrcaTheme.accentDeep;
      case 'CAUTION':
        return const Color(0xFF9D6915);
      case 'NO_GO':
      case 'NO-GO':
      case 'DANGER':
        return OrcaTheme.dangerFg;
      default:
        return OrcaTheme.infoFg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool verified = advisory.landVerified;
    final OrcaDataState state = verified
        ? (advisory.pointsKnown == 0 ? OrcaDataState.unavailable : OrcaDataState.current)
        : OrcaDataState.unavailable;
    final Color tint = verified ? _resultInk(advisory.level) : VerdictColors.caution;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _resultFill(advisory.level),
        borderRadius: BorderRadius.circular(OrcaTheme.tileRadius),
        border: Border.all(color: _resultBorder(advisory.level)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: OrcaEyebrow('TRANSIT VERDICT', color: OrcaTheme.textMuted)),
              OrcaStateChip(state: state, overrideLabel: verified ? null : 'UNVERIFIED'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Icon(VerdictColors.iconForVerdict(advisory.level), size: 26, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _label(advisory.level),
                  style: TextStyle(
                    fontFamily: kOrcaSans,
                    fontSize: 30,
                    height: 1.05,
                    letterSpacing: -1.5,
                    fontWeight: FontWeight.w800,
                    color: verified ? tint : OrcaTheme.textPrimary,
                  ),
                ),
              ),
              OrcaInfoPill(
                icon: Icons.place_outlined,
                label: advisory.totalPoints == 0
                    ? 'No samples'
                    : '${advisory.pointsKnown}/${advisory.totalPoints} points',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(advisory.headline, style: OrcaType.cardBody.copyWith(color: OrcaTheme.headingSoft)),
          if (!verified) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VerdictColors.cautionBg,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: VerdictColors.caution.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.gpp_maybe_outlined, size: 17, color: VerdictColors.caution),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      check?.reason ??
                          'Land-clearance verification is unavailable: no verified land-mask dataset is configured on this ORCA Box. This route is not safety-certified.',
                      style: OrcaType.body.copyWith(fontSize: 12, color: OrcaTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (check != null) ...<Widget>[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OrcaInfoPill(
                  icon: Icons.straighten_rounded,
                  label: check!.distanceKm == null
                      ? 'Distance unavailable'
                      : '${check!.distanceKm!.toStringAsFixed(1)} km'
                          '${check!.distanceNm == null ? '' : ' · ${check!.distanceNm!.toStringAsFixed(1)} NM'}',
                ),
                OrcaInfoPill(
                  icon: Icons.explore_outlined,
                  label: check!.bearingDeg == null
                      ? 'Bearing unavailable'
                      : 'Bearing ${check!.bearingDeg!.toStringAsFixed(0)}°',
                ),
                OrcaInfoPill(
                  icon: verified ? Icons.verified_outlined : Icons.gpp_maybe_outlined,
                  label: verified ? 'Land check cleared' : 'Land check unverified',
                  tint: verified ? VerdictColors.go : VerdictColors.caution,
                ),
              ],
            ),
          ],
          if (advisory.safeWindowFrom.isNotEmpty || advisory.safeWindowTo.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            OrcaProvenance(
              source: 'Backend safe window at departure',
              timeLabel: '${advisory.safeWindowFrom} → ${advisory.safeWindowTo}',
            ),
          ],
          const SizedBox(height: 12),
          OrcaProvenance(
            source: advisory.sources.isEmpty ? 'Source unavailable' : advisory.sources.join(' · '),
            stateLabel: 'GET /api/v1/route-advisory',
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  String _label(String level) {
    final String normal = level.toUpperCase().replaceAll('_', '-');
    if (normal == 'GOOD' || normal == 'GO') return 'SAFE';
    if (normal == 'NO-GO' || normal == 'DANGER' || normal == 'NOGO') return 'DANGEROUS';
    if (normal == 'CAUTION') return 'CAUTION';
    return 'UNVERIFIED';
  }
}
