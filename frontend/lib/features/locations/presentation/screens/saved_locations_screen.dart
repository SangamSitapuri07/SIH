import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../domain/saved_location.dart';
import '../providers/locations_provider.dart';

/// Saved harbours and fishing areas.
///
/// Every place here was entered by the skipper. Nothing is pre-seeded, and the
/// add form starts from the real working location rather than a placeholder
/// coordinate.
class SavedLocationsScreen extends ConsumerWidget {
  const SavedLocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SavedLocation> locations = ref.watch(savedLocationsProvider);
    final Map<String, double> working = ref.watch(advisoryLocationProvider);

    return OrcaWorkspaceScaffold(
      title: 'Saved locations',
      subtitle: 'Your own harbours and fishing areas',
      locationLabel: 'Working location',
      coordinateLabel: GeoUtils.formatCoordinate(
        working['lat'] ?? AppConfig.defaultLat,
        working['lon'] ?? AppConfig.defaultLon,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 96),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const OrcaEyebrow('MY PLACES', color: OrcaTheme.accentDark),
                    const SizedBox(height: 6),
                    Text(
                      locations.isEmpty
                          ? 'No saved places yet'
                          : '${locations.length} saved place${locations.length == 1 ? '' : 's'}',
                      style: OrcaType.displayCompact,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Saved places feed the advisory location and the route planner. They are stored on this device only.',
                      style: OrcaType.body.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (locations.isEmpty)
            OrcaUnavailable(
              icon: Icons.bookmark_border_rounded,
              title: 'Nothing saved on this device',
              message:
                  'ORCA does not ship with any harbour or fishing-area list. Add the places you actually work from, or keep using the working location.',
              actionLabel: 'Add a place',
              onAction: () => _showAddLocationDialog(context, ref, working),
            )
          else
            for (final SavedLocation location in locations) _LocationCard(location: location),
          const SizedBox(height: 10),
          const OrcaProvenance(
            source: 'Local device storage — saved locations',
            timeLabel: 'Coordinates are exactly what you entered; ORCA does not snap them to a built-in list',
            maxLines: 3,
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Add a place',
          onPressed: () => _showAddLocationDialog(context, ref, working),
          icon: const Icon(Icons.add_location_alt_outlined, size: 19),
        ),
      ],
    );
  }

  void _showAddLocationDialog(BuildContext context, WidgetRef ref, Map<String, double> working) {
    final TextEditingController nameController = TextEditingController();
    // Prefilled with the real working location so the skipper edits a value
    // ORCA is actually watching instead of a placeholder coordinate.
    final TextEditingController latController =
        TextEditingController(text: (working['lat'] ?? AppConfig.defaultLat).toStringAsFixed(4));
    final TextEditingController lonController =
        TextEditingController(text: (working['lon'] ?? AppConfig.defaultLon).toStringAsFixed(4));

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: OrcaTheme.surface,
        title: const Text('Save a place'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: latController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lonController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Values start from your working location and stay editable. ORCA never replaces them with a built-in coordinate.',
              style: OrcaType.caption,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final double? lat = double.tryParse(latController.text.trim());
              final double? lon = double.tryParse(lonController.text.trim());
              if (nameController.text.trim().isEmpty ||
                  lat == null ||
                  lon == null ||
                  !lat.isFinite ||
                  !lon.isFinite ||
                  lat.abs() > 90 ||
                  lon.abs() > 180) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a name and a latitude within ±90° and longitude within ±180°.'),
                  ),
                );
                return;
              }
              ref
                  .read(savedLocationsProvider.notifier)
                  .addLocation(nameController.text.trim(), lat, lon, 'Fishing Area');
              Navigator.pop(dialogContext);
            },
            child: const Text('Save place'),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends ConsumerWidget {
  final SavedLocation location;

  const _LocationCard({required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool harbour = location.category.toLowerCase().contains('harbour');
    return OrcaCard(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OrcaIconBadge(icon: harbour ? Icons.anchor_rounded : Icons.phishing_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        location.name,
                        style: OrcaType.metricLabel.copyWith(fontSize: 13.5, color: OrcaTheme.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (location.isFavourite) ...<Widget>[
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, color: VerdictColors.caution, size: 15),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${GeoUtils.formatCoordinate(location.latitude, location.longitude)} · ${location.category}',
                  style: OrcaType.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: location.isFavourite ? 'Remove from favourites' : 'Add to favourites',
            onPressed: () => ref.read(savedLocationsProvider.notifier).toggleFavourite(location.id),
            icon: Icon(
              location.isFavourite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 19,
              color: location.isFavourite ? VerdictColors.caution : OrcaTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
