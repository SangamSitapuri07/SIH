import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../domain/advisory_history_item.dart';

final historyItemsProvider = Provider<List<AdvisoryHistoryItem>>((ref) {
  final now = DateTime.now();
  return [
    AdvisoryHistoryItem(
      id: 'h-1',
      advisoryId: 'adv-0830',
      locationName: 'Veraval Offshore Shelf',
      latitude: 20.9,
      longitude: 70.37,
      verdict: 'CAUTION',
      headline: 'CAUTION ADVISED — MODERATE SEA',
      majorHazards: const ['Waves 2.8 m', 'Gusts up to 24 kn'],
      timestamp: now.subtract(const Duration(minutes: 42)),
      freshnessLabel: 'Recent',
    ),
    AdvisoryHistoryItem(
      id: 'h-2',
      advisoryId: 'adv-yesterday',
      locationName: 'Veraval Offshore Shelf',
      latitude: 20.9,
      longitude: 70.37,
      verdict: 'GOOD',
      headline: 'SAFE TO SAIL TODAY',
      majorHazards: const [],
      timestamp: now.subtract(const Duration(days: 1, hours: 3)),
      freshnessLabel: 'Archived',
    ),
    AdvisoryHistoryItem(
      id: 'h-3',
      advisoryId: 'adv-12sep',
      locationName: 'Porbandar Marine Sector',
      latitude: 21.63,
      longitude: 69.6,
      verdict: 'NO-GO',
      headline: 'DANGER — ROUGH SEA WARNING',
      majorHazards: const ['High Waves 4.2 m', 'Gale wind 36 kn'],
      timestamp: now.subtract(const Duration(days: 2, hours: 5)),
      freshnessLabel: 'Archived',
    ),
  ];
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ADVISORY HISTORY',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        backgroundColor: OrcaTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Past Advisory Archive',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cloud-synced advisory history for safety audit & trend inspection.',
              style: TextStyle(fontSize: 13, color: OrcaTheme.textSecondary),
            ),
            const SizedBox(height: 16),

            for (final item in history) ...[
              _buildHistoryCard(item),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(AdvisoryHistoryItem item) {
    Color verdictColor;
    IconData icon;

    switch (item.verdict) {
      case 'GOOD':
        verdictColor = VerdictColors.go;
        icon = Icons.check_circle_outline;
        break;
      case 'CAUTION':
        verdictColor = VerdictColors.caution;
        icon = Icons.warning_amber_rounded;
        break;
      default:
        verdictColor = VerdictColors.noGo;
        icon = Icons.cancel_outlined;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: verdictColor.withAlpha(120), width: 1.2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: verdictColor.withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: verdictColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      item.verdict,
                      style: TextStyle(
                        color: verdictColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                DateFormatter.formatIstTime(item.timestamp),
                style: const TextStyle(color: OrcaTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.headline,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.locationName} (${item.latitude}° N, ${item.longitude}° E)',
            style: const TextStyle(color: OrcaTheme.textSecondary, fontSize: 12),
          ),
          if (item.majorHazards.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: item.majorHazards.map((String h) => Chip(
                label: Text(h, style: const TextStyle(fontSize: 11, color: Colors.white)),
                backgroundColor: VerdictColors.noGoBg,
                side: BorderSide(color: VerdictColors.noGo.withAlpha(100)),
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
