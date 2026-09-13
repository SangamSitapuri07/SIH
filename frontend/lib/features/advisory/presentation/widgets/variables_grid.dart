import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/stat_tile.dart';
import '../../domain/entities/advisory.dart';

/// Grid of marine variables with source and status badges (§8).
class VariablesGrid extends StatelessWidget {
  final Map<String, VariableItem> variables;

  const VariablesGrid({
    super.key,
    required this.variables,
  });

  /// Looks up a variable by trying each candidate key in order.
  ///
  /// The backend emits keys such as `wave_height_m`, `wind_speed_kn`,
  /// `wind_gust_kn`, `sst_celsius`, `current_speed_kn`, `chlorophyll_mg_m3`,
  /// while older fixtures used short names. Trying both keeps the grid
  /// populated regardless of which shape the server returns.
  VariableItem? _pick(Map<String, VariableItem> vars, List<String> keys) {
    for (final k in keys) {
      final v = vars[k];
      if (v != null) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final wave = _pick(variables, ['wave_height_m', 'wave_height', 'swell_height_m']);
    final wind = _pick(variables, ['wind_speed_kn', 'wind_speed']);
    final gusts = _pick(variables, ['wind_gust_kn', 'wind_gusts', 'wind_gust']);
    final sst = _pick(variables, ['sst_celsius', 'sea_surface_temp', 'sea_temp_c']);
    final current = _pick(variables, ['current_speed_kn', 'ocean_current', 'current_speed']);
    final chl = _pick(variables, ['chlorophyll_mg_m3', 'chlorophyll']);


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            'KEY OCEAN CONDITIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: OrcaTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 4),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            StatTile(
              label: 'Wave Height',
              value: wave?.value != null ? '${wave!.value!.toStringAsFixed(1)}' : '--',
              unit: 'm',
              icon: Icons.waves,
              status: wave?.status,
              source: wave?.source ?? 'Open-Meteo',
              time: wave?.time,
            ),
            StatTile(
              label: 'Sustained Wind',
              value: wind?.value != null ? '${wind!.value!.toStringAsFixed(1)}' : '--',
              unit: 'kn',
              icon: Icons.air,
              status: wind?.status,
              source: wind?.source ?? 'ECMWF IFS',
              time: wind?.time,
            ),
            StatTile(
              label: 'Wind Gusts',
              value: gusts?.value != null ? '${gusts!.value!.toStringAsFixed(1)}' : '--',
              unit: 'kn',
              icon: Icons.storm,
              status: gusts?.status,
              source: gusts?.source ?? 'ECMWF IFS',
              time: gusts?.time,
            ),
            StatTile(
              label: 'Sea Surface Temp',
              value: sst?.value != null ? '${sst!.value!.toStringAsFixed(1)}' : '--',
              unit: '°C',
              icon: Icons.thermostat,
              status: sst?.status,
              source: sst?.source ?? 'Open-Meteo',
              time: sst?.time,
            ),
            StatTile(
              label: 'Surface Current',
              value: current?.value != null ? '${current!.value!.toStringAsFixed(1)}' : '--',
              unit: current?.direction != null ? 'kn ${current!.direction}' : 'kn',
              icon: Icons.navigation,
              status: current?.status,
              source: current?.source ?? 'Open-Meteo',
              time: current?.time,
            ),
            StatTile(
              label: 'Chlorophyll-a',
              value: chl?.value != null ? '${chl!.value!.toStringAsFixed(2)}' : '--',
              unit: 'mg/m³',
              icon: Icons.biotech,
              status: chl?.status,
              source: chl?.source ?? 'NOAA ERDDAP',
              time: chl?.time,
            ),
          ],
        ),
      ],
    );
  }
}
