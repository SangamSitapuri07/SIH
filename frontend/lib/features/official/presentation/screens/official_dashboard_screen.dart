import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/widgets/orca_app_bar.dart';

class OfficialDashboardScreen extends ConsumerWidget {
  const OfficialDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemo = ref.watch(demoModeProvider);

    if (!isDemo) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'OFFICIAL DASHBOARD',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          backgroundColor: OrcaTheme.surface,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Official dashboard is unavailable in live mode.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: OrcaTheme.textSecondary),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'OFFICIAL DASHBOARD',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        backgroundColor: OrcaTheme.surface,
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 14),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue),
            ),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.blue, size: 16),
                SizedBox(width: 4),
                Text(
                  'FISHERIES DEPT',
                  style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Regional Marine Intelligence Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Real-time overview of fleet safety, active warnings, and ecological telemetry.',
              style: TextStyle(fontSize: 13, color: OrcaTheme.textSecondary),
            ),
            const SizedBox(height: 16),

            // Top Stat Cards
            Row(
              children: [
                _buildStatCard('Active Vessels', '142', Icons.directions_boat, Colors.cyan),
                const SizedBox(width: 10),
                _buildStatCard('Active Alerts', '2', Icons.warning_amber, VerdictColors.caution),
                const SizedBox(width: 10),
                _buildStatCard('Sources Health', '95%', Icons.cloud_done, VerdictColors.go),
              ],
            ),
            const SizedBox(height: 18),

            // Sector Risk Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OrcaTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sector Risk Breakdown',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  _buildSectorRow('Veraval Offshore Sector', 'GOOD', VerdictColors.go),
                  const Divider(color: Colors.white12),
                  _buildSectorRow('Porbandar Sector', 'CAUTION', VerdictColors.caution),
                  const Divider(color: Colors.white12),
                  _buildSectorRow('Jafrabad Coastal Sector', 'GOOD', VerdictColors.go),
                  const Divider(color: Colors.white12),
                  _buildSectorRow('Okha Deep Offshore Sector', 'NO-GO', VerdictColors.noGo),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Aggregated Catch & Livelihood Insights
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OrcaTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aggregated Catch & Ecological Insights',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Reported Catch Today:', style: TextStyle(color: OrcaTheme.textSecondary, fontSize: 13)),
                      Text('3,480 kg', style: TextStyle(color: OrcaTheme.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('Top Species Reported:', style: TextStyle(color: OrcaTheme.textSecondary, fontSize: 13)),
                  SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      Chip(label: Text('Indian Mackerel (45%)'), backgroundColor: Colors.white10),
                      Chip(label: Text('Sardine (30%)'), backgroundColor: Colors.white10),
                      Chip(label: Text('Ribbon Fish (15%)'), backgroundColor: Colors.white10),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OrcaTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: OrcaTheme.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildSectorRow(String name, String status, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(40),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
