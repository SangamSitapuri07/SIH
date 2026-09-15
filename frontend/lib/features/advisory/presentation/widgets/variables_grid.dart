import 'package:flutter/material.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../domain/entities/advisory.dart';
import 'variable_provenance.dart';

/// Grid of the marine variables the backend published for this advisory.
///
/// Each tile carries the provider, the provider time and the value's own state.
/// A variable the deployment did not publish is shown as unavailable rather
/// than being omitted or estimated.
class VariablesGrid extends StatelessWidget {
  final Map<String, VariableItem> variables;
  final int columns;

  const VariablesGrid({
    super.key,
    required this.variables,
    this.columns = 2,
  });

  static const List<_Spec> _specs = <_Spec>[
    _Spec(key: 'wave_height_m', label: 'Wave height', icon: Icons.waves_rounded, decimals: 1),
    _Spec(key: 'wave_period_s', label: 'Swell period', icon: Icons.tsunami_rounded, decimals: 1),
    _Spec(key: 'wind_speed_kn', label: 'Sustained wind', icon: Icons.air_rounded, decimals: 1),
    _Spec(key: 'wind_gust_kn', label: 'Wind gusts', icon: Icons.storm_rounded, decimals: 1),
    _Spec(key: 'sst_celsius', label: 'Sea surface temp', icon: Icons.thermostat_rounded, decimals: 1),
    _Spec(key: 'current_speed_kn', label: 'Surface current', icon: Icons.navigation_rounded, decimals: 2),
    _Spec(key: 'chlorophyll_mg_m3', label: 'Chlorophyll-a', icon: Icons.bubble_chart_outlined, decimals: 2),
    _Spec(key: 'fishing_effort_hours', label: 'Fishing effort', icon: Icons.sailing_outlined, decimals: 1),
  ];

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[
      for (final _Spec spec in _specs)
        _buildTile(spec, variables[spec.key]),
    ];
    return _MetricGrid(columns: columns, children: tiles);
  }

  Widget _buildTile(_Spec spec, VariableItem? variable) {
    final String unit = variable == null ? '' : unitSuffix(variable.unit);
    final OrcaDataState state = variable == null
        ? OrcaDataState.unavailable
        : variableState(variable);
    final String? direction = variable?.direction;

    return OrcaMetricTile(
      label: spec.label,
      icon: spec.icon,
      value: variable?.value == null
          ? kOrcaUnavailableValue
          : formatMeasurement(variable!.value, unit, decimals: spec.decimals),
      unit: variable?.value == null ? null : unit,
      caption: switch (state) {
        OrcaDataState.unavailable => 'Not published by any connected source',
        OrcaDataState.cached => 'Cached provider value',
        OrcaDataState.stale => 'Value may be out of date',
        _ => variableTimeLabel(variable),
      },
      state: state,
      provenance: direction == null || direction.trim().isEmpty
          ? (variable?.source ?? 'Source unavailable')
          : '${variable?.source ?? 'Source unavailable'} · $direction',
    );
  }
}

class _Spec {
  final String key;
  final String label;
  final IconData icon;
  final int decimals;

  const _Spec({required this.key, required this.label, required this.icon, required this.decimals});
}

class _MetricGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;

  const _MetricGrid({required this.columns, required this.children});

  @override
  Widget build(BuildContext context) {
    if (columns <= 1) {
      return Column(
        children: <Widget>[
          for (int i = 0; i < children.length; i++) ...<Widget>[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    final int rows = (children.length / columns).ceil();
    return Column(
      children: <Widget>[
        for (int row = 0; row < rows; row++) ...<Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int col = 0; col < columns; col++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: col == 0 ? 0 : 5,
                        right: col == columns - 1 ? 0 : 5,
                      ),
                      child: row * columns + col < children.length
                          ? children[row * columns + col]
                          : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
          ),
          if (row != rows - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Shared small legend row used by advisory cards.
class OrcaLegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const OrcaLegendDot({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: OrcaType.caption.copyWith(fontSize: 10.5, color: OrcaTheme.textSecondary)),
        ],
      );
}
