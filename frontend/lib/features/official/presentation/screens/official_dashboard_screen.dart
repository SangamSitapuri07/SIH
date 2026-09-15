import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';

/// Reserved for a future verified aggregate-data contract. ORCA deliberately
/// does not render the old synthetic overview as official marine information.
class OfficialDashboardScreen extends StatelessWidget {
  const OfficialDashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('OFFICIAL OVERVIEW')),
    body: const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.cloud_off_outlined, size: 42, color: OrcaTheme.textMuted), SizedBox(height: 12),
      Text('Official aggregate data unavailable', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: OrcaTheme.textPrimary)), SizedBox(height: 6),
      Text('No verified official aggregate telemetry contract is connected to this ORCA deployment.', textAlign: TextAlign.center, style: TextStyle(color: OrcaTheme.textSecondary, height: 1.35)),
    ]))),
  );
}
