import 'package:flutter/material.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../domain/entities/zone_snapshot.dart';

/// Compact capability-aware layer selector. It displays unavailable backend
/// products transparently instead of rendering a blank or invented overlay.
class LayerSelectorDialog extends StatelessWidget {
  final List<MapLayerEntity> layers;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  const LayerSelectorDialog({
    super.key,
    required this.layers,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OrcaTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OrcaTheme.cardRadius),
        side: const BorderSide(color: OrcaTheme.cardBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      title: const Row(
        children: <Widget>[
          Icon(Icons.layers_outlined, color: OrcaTheme.accentInk, size: 18),
          SizedBox(width: 10),
          Text('Map layers', style: OrcaType.sectionTitle),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: layers.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: OrcaTheme.cardBorder),
          itemBuilder: (context, index) {
            final layer = layers[index];
            final enabled = selectedIds.contains(layer.id);
            final interactive = layer.isMapRenderable;
            return Semantics(
              label: '${layer.name}: ${interactive ? layer.state : 'Unavailable'}',
              child: SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.symmetric(vertical: 5),
                title: Text(layer.name, style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: interactive ? OrcaTheme.textPrimary : OrcaTheme.textMuted,
                )),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${layer.source}${layer.resolution != null ? ' · ${layer.resolution}' : ''}',
                      style: const TextStyle(fontSize: 11, color: OrcaTheme.textSecondary)),
                    if (!interactive && layer.reason != null) ...[
                      const SizedBox(height: 3),
                      Text(layer.reason!, style: const TextStyle(fontSize: 10.5, color: VerdictColors.caution)),
                    ],
                  ],
                ),
                value: enabled && interactive,
                activeColor: OrcaTheme.accent,
                onChanged: interactive
                    ? (value) {
                        final next = {...selectedIds};
                        value ? next.add(layer.id) : next.remove(layer.id);
                        onChanged(next);
                      }
                    : null,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
