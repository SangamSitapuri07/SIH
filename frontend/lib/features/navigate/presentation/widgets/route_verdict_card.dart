import 'package:flutter/material.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../domain/entities/route_advisory.dart';
import '../../domain/entities/route_check.dart';

/// Card rendering transit safety verdict & 2km land verification badge (§4, §6).
class RouteVerdictCard extends StatelessWidget {
  final RouteAdvisoryEntity advisory;
  final RouteCheckEntity? check;

  const RouteVerdictCard({
    super.key,
    required this.advisory,
    this.check,
  });

  @override
  Widget build(BuildContext context) {
    final verdictColor = VerdictColors.fromVerdict(advisory.level);
    final verdictBg = VerdictColors.backgroundFromVerdict(advisory.level);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: verdictBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: verdictColor, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: verdictColor.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Transit Verdict Level + Sample Points
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    VerdictColors.iconForVerdict(advisory.level),
                    color: verdictColor,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TRANSIT: ${advisory.level.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: verdictColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${advisory.pointsKnown}/${advisory.totalPoints} pts live',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Headline
          Text(
            advisory.headline,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),

          // Land Clearance Badge (§6)
          if (check != null) ...[
            Row(
              children: [
                Icon(
                  check!.landHit ? Icons.alt_route : Icons.check_circle_outline,
                  color: check!.landHit ? VerdictColors.caution : VerdictColors.go,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    check!.landHit
                        ? 'Detour active: Waypoint (${check!.detourWaypoint?.name ?? "WP1"}) added to avoid coastal land.'
                        : 'GLOBE 2km land mask: Direct transit verified clear of land.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: check!.landHit ? VerdictColors.caution : VerdictColors.go,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Safe departure window at start
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Text(
                'Safe Departure: ${advisory.safeWindowFrom} to ${advisory.safeWindowTo}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
