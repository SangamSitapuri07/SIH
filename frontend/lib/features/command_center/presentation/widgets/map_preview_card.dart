import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../map/data/datasources/map_remote.dart';
import '../../../map/domain/entities/zone_snapshot.dart';
import '../../../map/presentation/providers/map_provider.dart';

/// Real map preview for the overview: OpenStreetMap base geography plus the
/// backend's point-sampled model field around the working location.
///
/// The base map is always shown. When no verified field sample exists for the
/// area, the preview says so instead of drawing an invented overlay.
class CommandCenterMapPreview extends ConsumerWidget {
  final double lat;
  final double lon;
  final VoidCallback onOpenMap;
  final double height;

  const CommandCenterMapPreview({
    super.key,
    required this.lat,
    required this.lon,
    required this.onOpenMap,
    this.height = 214,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LatLng center = LatLng(lat, lon);
    final AsyncValue<List<MapLayerEntity>> catalog =
        ref.watch(mapLayerCatalogProvider(MapCenter(lat, lon)));
    final List<MapLayerEntity> layers = catalog.valueOrNull ?? const <MapLayerEntity>[];
    final MapLayerEntity fieldLayer = layers.firstWhere(
      (MapLayerEntity layer) =>
          layer.isMapRenderable &&
          (layer.visualization == 'vector_grid' || layer.visualization == 'scalar_grid'),
      orElse: () => const MapLayerEntity(
        id: '',
        name: '',
        unit: '',
        source: '',
        visualization: '',
        state: '',
        available: false,
      ),
    );

    final AsyncValue<MapGridDto>? grid = fieldLayer.id.isEmpty
        ? null
        : ref.watch(
            mapGridProvider(
              MapGridRequest(lat: lat, lon: lon, span: 0.6, validTime: null),
            ),
          );

    return OrcaCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OrcaSectionHeader(
            title: 'Your water, at a glance',
            subtitle: 'OpenStreetMap base chart with the ORCA Box field sample around your working location.',
            actionLabel: 'Open map',
            onAction: onOpenMap,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: height,
              child: Stack(
                children: <Widget>[
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 8.2,
                      minZoom: 3,
                      maxZoom: 14,
                      backgroundColor: OrcaTheme.mapCanvas,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                    ),
                    children: <Widget>[
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'in.orca.marine_intelligence',
                      ),
                      if (grid?.valueOrNull != null)
                        MarkerLayer(markers: _markers(grid!.valueOrNull!, fieldLayer)),
                      MarkerLayer(
                        markers: <Marker>[
                          Marker(
                            point: center,
                            width: 26,
                            height: 26,
                            child: Semantics(
                              label: 'Working location',
                              child: Container(
                                decoration: BoxDecoration(
                                  color: OrcaTheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: OrcaTheme.deepTeal, width: 2.5),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 8,
                                    height: 8,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: OrcaTheme.deepTeal,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: <SourceAttribution>[
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                  if (fieldLayer.id.isEmpty)
                    const Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: _PreviewNotice(
                        message: 'No verified field layer is published — base chart only.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PreviewFooter(
            catalog: catalog,
            fieldLayer: fieldLayer.id.isEmpty ? null : fieldLayer,
            grid: grid,
            center: center,
          ),
        ],
      ),
    );
  }

  List<Marker> _markers(MapGridDto grid, MapLayerEntity layer) {
    final List<Marker> markers = <Marker>[];
    for (final MapGridPointDto point in grid.points) {
      if (point.status.toLowerCase() != 'fresh') continue;
      final (double? value, String unit) = switch (layer.id) {
        'wind' => (point.windKn, 'kn'),
        'waves' => (point.waveHeightM, 'm'),
        'sst' => (point.seaTempC, '°C'),
        _ => (null, ''),
      };
      if (value == null) continue;
      final Color color = _valueColor(layer.id, value);
      markers.add(
        Marker(
          point: LatLng(point.lat, point.lon),
          width: 52,
          height: 30,
          child: Semantics(
            label: '${layer.name} ${value.toStringAsFixed(1)} $unit at '
                '${point.lat.toStringAsFixed(2)}, ${point.lon.toStringAsFixed(2)}',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: OrcaTheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color, width: 1.4),
              ),
              child: Center(
                child: Text(
                  '${value.toStringAsFixed(value.abs() < 10 ? 1 : 0)}$unit',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: OrcaTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Color _valueColor(String layerId, double value) {
    switch (layerId) {
      case 'wind':
        // Thresholds match the deterministic route/advisory engine (20 kn
        // caution, 34 kn danger).
        if (value >= 34) return VerdictColors.noGo;
        if (value >= 20) return VerdictColors.caution;
        return VerdictColors.go;
      case 'waves':
        // Safe-window spec: 2.0 m good ceiling, 2.5 m caution ceiling.
        if (value >= 2.5) return VerdictColors.noGo;
        if (value >= 2.0) return VerdictColors.caution;
        return VerdictColors.go;
      default:
        // Sea-surface temperature is shown as measured; no threshold is
        // published for it, so no risk colour is implied.
        return OrcaTheme.accentDark;
    }
  }
}

class _PreviewNotice extends StatelessWidget {
  final String message;

  const _PreviewNotice({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: OrcaTheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: OrcaTheme.cardBorder),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.layers_clear_outlined, size: 15, color: OrcaTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: OrcaType.caption.copyWith(fontSize: 11))),
          ],
        ),
      );
}

class _PreviewFooter extends StatelessWidget {
  final AsyncValue<List<MapLayerEntity>> catalog;
  final MapLayerEntity? fieldLayer;
  final AsyncValue<MapGridDto>? grid;
  final LatLng center;

  const _PreviewFooter({
    required this.catalog,
    required this.fieldLayer,
    required this.grid,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    final MapGridDto? field = grid?.valueOrNull;
    final int fresh = field?.points.where((MapGridPointDto p) => p.status.toLowerCase() == 'fresh').length ?? 0;
    final int total = field?.points.length ?? 0;

    final OrcaDataState state;
    if (catalog.hasError || (grid?.hasError ?? false)) {
      state = OrcaDataState.error;
    } else if (fieldLayer == null) {
      state = catalog.isLoading ? OrcaDataState.loading : OrcaDataState.unavailable;
    } else if (fresh == 0) {
      state = OrcaDataState.unavailable;
    } else {
      state = OrcaDataState.current;
    }

    final String headline = switch (state) {
      OrcaDataState.error => 'Map field unavailable — the layer catalogue request failed.',
      OrcaDataState.loading => 'Reading available map layers from the ORCA Box…',
      OrcaDataState.unavailable => fieldLayer == null
          ? 'No verified field layer is available for this deployment.'
          : 'No verified samples in this area — the base chart is shown without an overlay.',
      _ => '${fieldLayer!.name} · $fresh of $total samples verified',
    };

    final String? source = field?.sources.isNotEmpty == true
        ? field!.sources.join(' · ')
        : fieldLayer?.source;
    final String? time = field?.fetchedAt == null
        ? null
        : 'ORCA retrieved ${DateFormatter.formatIstTime(field!.fetchedAt!)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(headline, style: OrcaType.body.copyWith(fontSize: 12))),
            const SizedBox(width: 8),
            OrcaStateChip(state: state),
          ],
        ),
        const SizedBox(height: 5),
        OrcaProvenance(
          source: source,
          timeLabel: time,
          stateLabel: geoLabel(center),
          maxLines: 1,
        ),
      ],
    );
  }

  static String geoLabel(LatLng center) =>
      GeoUtils.formatCoordinate(center.latitude, center.longitude);
}
