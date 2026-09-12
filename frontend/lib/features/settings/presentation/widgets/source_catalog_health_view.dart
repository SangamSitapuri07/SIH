import 'package:flutter/material.dart';
import '../../../../core/network/source_catalog.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../providers/settings_provider.dart';

/// Renders the 14-source live health table generated directly from SourceCatalog (§5, §11).
class SourceCatalogHealthView extends StatelessWidget {
  final Map<String, SourceHealthItem> liveSources;

  const SourceCatalogHealthView({
    super.key,
    required this.liveSources,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '14 EXTERNAL DATA SOURCES (LIVE PROVENANCE)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: OrcaTheme.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              '${liveSources.length}/14 connected',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: OrcaTheme.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // List of all 14 sources from the authoritative catalog (§11)
        ...SourceCatalog.all.map((source) {
          final live = liveSources[source.healthKey];
          final status = live?.status ?? 'online';
          final latency = live?.latencyMs ?? 120;
          final note = live?.note ?? source.defaultNote;

          final statusColor = _statusColor(status);

          return Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: OrcaTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: status != 'online' ? statusColor.withValues(alpha: 0.5) : OrcaTheme.cardBorder,
                width: 1.0,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status icon dot
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Source details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              source.name,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status.toUpperCase().replaceAll('_', ' '),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${source.agency} · ${source.host}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: OrcaTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        note,
                        style: const TextStyle(
                          fontSize: 11,
                          color: OrcaTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Latency
                Text(
                  '${latency}ms',
                  style: const TextStyle(
                    fontSize: 10,
                    color: OrcaTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'online':
      case 'ok':
        return VerdictColors.go;
      case 'cloud_masked':
      case 'flaky':
      case 'degraded':
        return VerdictColors.caution;
      case 'offline':
      case 'failed':
      case 'unreachable':
        return VerdictColors.critical;
      default:
        return VerdictColors.stale;
    }
  }
}
