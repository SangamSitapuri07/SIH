import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../domain/catch_report.dart';

final catchReportsProvider = StateNotifierProvider<CatchReportsNotifier, List<CatchReport>>((ref) {
  final syncManager = ref.watch(syncManagerProvider.notifier);
  return CatchReportsNotifier(syncManager);
});

class CatchReportsNotifier extends StateNotifier<List<CatchReport>> {
  final SyncManager _syncManager;

  CatchReportsNotifier(this._syncManager) : super(const <CatchReport>[]);

  void addReport(String location, double lat, double lon, String species, double quantityKg, String? note) {
    final report = CatchReport(
      id: 'rep-${DateTime.now().millisecondsSinceEpoch}',
      locationName: location,
      latitude: lat,
      longitude: lon,
      species: species,
      quantityKg: quantityKg,
      catchDate: DateTime.now().toIso8601String().split('T')[0],
      notes: note,
      isSynced: false,
    );
    state = [report, ...state];
    _syncManager.enqueue('catch_reports', 'CREATE', report.toJson());
  }
}

class CatchReportScreen extends ConsumerStatefulWidget {
  const CatchReportScreen({super.key});

  @override
  ConsumerState<CatchReportScreen> createState() => _CatchReportScreenState();
}

class _CatchReportScreenState extends ConsumerState<CatchReportScreen> {
  String _selectedSpecies = 'Indian Mackerel';
  double _quantityKg = 50.0;
  final TextEditingController _noteCtrl = TextEditingController();

  final List<String> _commonSpecies = [
    'Indian Mackerel',
    'Sardine',
    'Ribbon Fish',
    'Tuna',
    'Pomfret',
    'Prawn / Shrimp',
  ];

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(catchReportsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CATCH REPORT',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        backgroundColor: OrcaTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OrcaTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OrcaTheme.accent.withAlpha(100), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.phishing, color: OrcaTheme.accent, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Log Today\'s Catch',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text('Select Fish Species:', style: TextStyle(color: OrcaTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _commonSpecies.map((s) {
                      final selected = _selectedSpecies == s;
                      return ChoiceChip(
                        label: Text(s),
                        selected: selected,
                        onSelected: (val) {
                          if (val) setState(() => _selectedSpecies = s);
                        },
                        selectedColor: OrcaTheme.accent,
                        labelStyle: TextStyle(
                          color: selected ? Colors.black : Colors.white,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: Colors.white10,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Approximate Quantity (kg):', style: TextStyle(color: OrcaTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () {
                          if (_quantityKg >= 10) setState(() => _quantityKg -= 10);
                        },
                        icon: const Icon(Icons.remove, size: 28),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: OrcaTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OrcaTheme.accent),
                        ),
                        child: Text(
                          '${_quantityKg.toInt()} kg',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: OrcaTheme.accent,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () {
                          setState(() => _quantityKg += 10);
                        },
                        icon: const Icon(Icons.add, size: 28),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white12,
                          padding: const EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ref.read(catchReportsProvider.notifier).addReport(
                          'Veraval Offshore Shelf',
                          20.9,
                          70.37,
                          _selectedSpecies,
                          _quantityKg,
                          _noteCtrl.text.isNotEmpty ? _noteCtrl.text : null,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Catch report saved locally & queued for cloud sync!'),
                            backgroundColor: VerdictColors.go,
                          ),
                        );
                      },
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OrcaTheme.accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (reports.isEmpty) ...[
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'No catch reports yet.',
                  style: TextStyle(fontSize: 15, color: OrcaTheme.textSecondary),
                ),
              ),
            ] else ...[
              const Text(
                'My Submitted Catch Reports',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              for (final r in reports) ...[
                Card(
                  color: OrcaTheme.surface,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.amber,
                      child: Icon(Icons.phishing, color: Colors.black),
                    ),
                    title: Text(
                      '${r.species} — ${r.quantityKg.toInt()} kg',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      '${r.locationName} • Date: ${r.catchDate}',
                      style: const TextStyle(color: OrcaTheme.textSecondary, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: r.isSynced ? VerdictColors.goBg : VerdictColors.cautionBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.isSynced ? 'SYNCED' : 'QUEUED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: r.isSynced ? VerdictColors.go : VerdictColors.caution,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
