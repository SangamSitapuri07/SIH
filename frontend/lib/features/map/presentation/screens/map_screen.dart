import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/domain/entities/advisory.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../../locations/domain/saved_location.dart';
import '../../../locations/presentation/providers/locations_provider.dart';
import '../../../locations/presentation/widgets/working_location_sheet.dart';
import '../../data/datasources/map_remote.dart';
import '../../domain/entities/zone_snapshot.dart';
import '../providers/map_provider.dart';
import '../widgets/layer_selector_dialog.dart';
import '../widgets/probe_inspector.dart';

/// Ocean map workspace.
///
/// The base chart is real OpenStreetMap geography. Overlays only appear when
/// the backend advertises the layer and returns point-sampled values for the
/// area; the forecast timeline only appears when the ORCA Box returned a real
/// hourly series, and each step is sent back to `/api/v1/grid` as an exact
/// `valid_time` so the displayed value matches the selected timestep.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _fieldCenter = const LatLng(AppConfig.defaultLat, AppConfig.defaultLon);
  LatLng? _deviceLocation;
  LatLng? _probedLocation;
  double _fieldSpan = 0.6;
  int _forecastIndex = 0;
  bool _hasSelectedInitialLayer = false;
  String? _searchMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> selectedLayers = ref.watch(mapLayerSelectionProvider);
    final AsyncValue<List<MapLayerEntity>> catalog =
        ref.watch(mapLayerCatalogProvider(MapCenter(_fieldCenter.latitude, _fieldCenter.longitude)));
    final AdvisoryEntity? advisory = ref.watch(advisoryProvider).valueOrNull;
    final AsyncValue<ZoneSnapshot?>? probe = ref.watch(probedZoneProvider);
    final List<MapLayerEntity> layers = catalog.valueOrNull ?? const <MapLayerEntity>[];

    final List<_TimelineEntry> timeline = _buildTimeline(advisory);
    if (_forecastIndex >= timeline.length) _forecastIndex = 0;
    final String? selectedTime = timeline[_forecastIndex].validTime;

    final bool hasGridLayer = layers.any(
      (MapLayerEntity layer) =>
          selectedLayers.contains(layer.id) &&
          layer.isMapRenderable &&
          (layer.visualization == 'vector_grid' || layer.visualization == 'scalar_grid'),
    );
    final MapGridRequest gridRequest = MapGridRequest(
      lat: _fieldCenter.latitude,
      lon: _fieldCenter.longitude,
      span: _fieldSpan,
      validTime: selectedTime,
    );
    final AsyncValue<MapGridDto>? grid = hasGridLayer ? ref.watch(mapGridProvider(gridRequest)) : null;
    final AsyncValue<PfzResponseDto>? pfz = selectedLayers.contains('pfz') ? ref.watch(mapPfzProvider) : null;

    if (catalog.hasValue && !_hasSelectedInitialLayer) {
      final Set<String> initial = layers
          .where((MapLayerEntity layer) => layer.isMapRenderable)
          .map((MapLayerEntity layer) => layer.id)
          .take(1)
          .toSet();
      if (initial.isNotEmpty) {
        _hasSelectedInitialLayer = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(mapLayerSelectionProvider.notifier).state = initial;
        });
      }
    }

    final MapGridDto? gridData = grid?.valueOrNull;

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.tabMap ?? 'Map',
      subtitle: 'Fields, layers and point inspection',
      locationLabel: 'Map centre',
      coordinateLabel: GeoUtils.formatCoordinate(_fieldCenter.latitude, _fieldCenter.longitude),
      updatedAt: gridData?.fetchedAt,
      stateLabel: gridData?.state,
      onLocationTap: () => showWorkingLocationSheet(context),
      onRefresh: _refreshAll,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool desktop = constraints.maxWidth >= 1080;
          final bool online = ref.watch(isOnlineProvider);
          final Widget map = _buildMap(context, gridData, selectedLayers, probe, pfz, online);
          final Widget inspector = _buildInspector(
            context,
            layers,
            grid,
            selectedLayers,
            timeline,
            selectedTime,
            probe,
            pfz,
            online,
          );
          if (desktop) {
            return Row(
              children: <Widget>[
                Expanded(child: map),
                Container(width: 1, color: OrcaTheme.cardBorder),
                SizedBox(width: 380, child: Container(color: OrcaTheme.background, child: inspector)),
              ],
            );
          }
          return Stack(
            children: <Widget>[
              map,
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(400, constraints.maxHeight * 0.62),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: OrcaTheme.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: OrcaTheme.cardBorder),
                      boxShadow: OrcaTheme.floatingShadow,
                    ),
                    child: inspector,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refreshAll() async {
    setState(() {
      _hasSelectedInitialLayer = false;
    });
    ref.invalidate(mapLayerCatalogProvider(MapCenter(_fieldCenter.latitude, _fieldCenter.longitude)));
    ref.invalidate(mapGridProvider(MapGridRequest(
      lat: _fieldCenter.latitude,
      lon: _fieldCenter.longitude,
      span: _fieldSpan,
      validTime: null,
    )));
    if (ref.read(probedZoneProvider)?.valueOrNull != null) {
      await probeCoordinate(ref, _probedLocation?.latitude ?? _fieldCenter.latitude,
          _probedLocation?.longitude ?? _fieldCenter.longitude);
    }
  }

  List<_TimelineEntry> _buildTimeline(AdvisoryEntity? advisory) {
    final List<_TimelineEntry> entries = <_TimelineEntry>[
      const _TimelineEntry(label: 'NOW'),
    ];
    if (advisory == null) return entries;
    final DateTime nowUtc = DateTime.now().toUtc();
    for (final HourlyPoint point in advisory.hourlyChart.take(12)) {
      final DateTime? parsed = DateFormatter.parseIso(point.hour);
      if (parsed == null) continue;
      final int deltaHours = parsed.toUtc().difference(nowUtc).inHours;
      if (deltaHours <= 0) continue;
      entries.add(
        _TimelineEntry(
          label: '+${deltaHours}H',
          validTime: point.hour,
          tooltip: DateFormatter.formatIstTime(parsed),
        ),
      );
      if (entries.length >= 9) break;
    }
    return entries;
  }

  Widget _buildMap(
    BuildContext context,
    MapGridDto? grid,
    Set<String> selected,
    AsyncValue<ZoneSnapshot?>? probe,
    AsyncValue<PfzResponseDto>? pfz,
    bool online,
  ) {
    final List<Marker> markers = <Marker>[
      if (_deviceLocation != null)
        Marker(
          point: _deviceLocation!,
          width: 34,
          height: 34,
          child: Semantics(
            label: 'Your device location',
            child: Container(
              decoration: BoxDecoration(
                color: OrcaTheme.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: OrcaTheme.floatingShadow,
              ),
              child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 16),
            ),
          ),
        ),
      if (_probedLocation != null)
        Marker(
          point: _probedLocation!,
          width: 34,
          height: 34,
          child: Semantics(
            label: 'Inspected point',
            child: const Icon(Icons.place_rounded, color: VerdictColors.noGo, size: 32),
          ),
        ),
      ..._fieldMarkers(grid, selected),
    ];

    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _fieldCenter,
            initialZoom: 8.4,
            minZoom: 3,
            maxZoom: 16,
            backgroundColor: OrcaTheme.mapCanvas,
            onTap: (_, LatLng point) {
              setState(() => _probedLocation = point);
              probeCoordinate(ref, point.latitude, point.longitude);
            },
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.orca.marine_intelligence',
            ),
            if (pfz?.valueOrNull != null)
              PolylineLayer(polylines: _pfzPolylines(pfz!.valueOrNull!)),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: <SourceAttribution>[
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 60,
          child: _SearchPanel(
            controller: _searchController,
            message: _searchMessage,
            onSubmit: _search,
            onFetchHere: _fetchAtMapCenter,
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            children: <Widget>[
              _RoundMapControl(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
              ),
              const SizedBox(height: 8),
              _RoundMapControl(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
              ),
              const SizedBox(height: 8),
              _RoundMapControl(icon: Icons.my_location, tooltip: 'Use device location', onPressed: _locateDevice),
              const SizedBox(height: 8),
              _RoundMapControl(
                icon: Icons.layers_outlined,
                tooltip: 'Map layers',
                onPressed: () => _showLayers(ref.watch(mapLayerCatalogProvider(
                      MapCenter(_fieldCenter.latitude, _fieldCenter.longitude),
                    )).valueOrNull ??
                    const <MapLayerEntity>[], selected),
              ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: _ActiveLayerLegend(selected: selected, grid: grid, online: online),
        ),
        if (probe?.hasError ?? false)
          const Positioned(
            right: 12,
            bottom: 12,
            child: _MapBanner(message: 'Point probe failed for that coordinate.'),
          ),
      ],
    );
  }

  Widget _buildInspector(
    BuildContext context,
    List<MapLayerEntity> layers,
    AsyncValue<MapGridDto>? grid,
    Set<String> selected,
    List<_TimelineEntry> timeline,
    String? validTime,
    AsyncValue<ZoneSnapshot?>? probe,
    AsyncValue<PfzResponseDto>? pfz,
    bool online,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OrcaEyebrow('MAP WORKSPACE', color: OrcaTheme.accentDark),
                    SizedBox(height: 4),
                    Text('Layers & field', style: OrcaType.cardTitle),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showLayers(layers, selected),
                icon: const Icon(Icons.layers_outlined, size: 16),
                label: Text('${selected.length} active'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _LayerChips(layers: layers, selected: selected, onToggle: _toggleLayer),
          const SizedBox(height: 18),
          _TimelineSection(
            entries: timeline,
            selectedIndex: _forecastIndex,
            onSelected: (int index) => setState(() => _forecastIndex = index),
          ),
          const SizedBox(height: 18),
          _FieldProvenance(
            grid: grid,
            pfz: pfz,
            selected: selected,
            layers: layers,
            validTime: validTime,
            online: online,
          ),
          const SizedBox(height: 18),
          const OrcaEyebrow('SELECTED AREA', color: OrcaTheme.textMuted),
          const SizedBox(height: 8),
          if (probe == null)
            const OrcaUnavailable(
              icon: Icons.ads_click_rounded,
              title: 'No point inspected',
              message: 'Tap the chart to inspect the ORCA Box snapshot for that exact coordinate.',
              compact: true,
            )
          else
            probe.when(
              loading: () => const _InspectorLoading(),
              error: (_, __) => const OrcaUnavailable(
                icon: Icons.cloud_off_outlined,
                title: 'Point data unavailable',
                message: 'The ORCA Box could not return a verified snapshot for that coordinate.',
                compact: true,
              ),
              data: (ZoneSnapshot? snapshot) => snapshot == null
                  ? const SizedBox.shrink()
                  : ProbeInspector(
                      snapshot: snapshot,
                      onClear: () {
                        setState(() => _probedLocation = null);
                        ref.read(probedZoneProvider.notifier).state = null;
                      },
                    ),
            ),
          const SizedBox(height: 18),
          const _AttributionNote(),
        ],
      ),
    );
  }

  List<Polyline> _pfzPolylines(PfzResponseDto response) {
    if (response.status.toLowerCase() != 'fresh') return const <Polyline>[];
    final List<Polyline> lines = <Polyline>[];
    for (final Map<String, dynamic> feature in response.features) {
      final Object? geometry = feature['geometry'];
      if (geometry is! Map) continue;
      final String? type = geometry['type']?.toString();
      final Object? coordinates = geometry['coordinates'];
      if (type == 'LineString') {
        final List<LatLng> points = _linePoints(coordinates);
        if (points.length > 1) {
          lines.add(Polyline(points: points, color: const Color(0xFF12A594), strokeWidth: 2.4));
        }
      } else if (type == 'MultiLineString' && coordinates is List) {
        for (final Object? line in coordinates) {
          final List<LatLng> points = _linePoints(line);
          if (points.length > 1) {
            lines.add(Polyline(points: points, color: const Color(0xFF12A594), strokeWidth: 2.4));
          }
        }
      }
    }
    return lines;
  }

  List<LatLng> _linePoints(Object? raw) {
    if (raw is! List) return const <LatLng>[];
    return raw
        .whereType<List<dynamic>>()
        .where((List<dynamic> pair) => pair.length >= 2 && pair[0] is num && pair[1] is num)
        .map((List<dynamic> pair) => LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()))
        .toList();
  }

  List<Marker> _fieldMarkers(MapGridDto? grid, Set<String> selected) {
    if (grid == null) return const <Marker>[];
    final String? mode = selected.contains('wind')
        ? 'wind'
        : selected.contains('waves')
            ? 'waves'
            : selected.contains('sst')
                ? 'sst'
                : null;
    if (mode == null) return const <Marker>[];
    return grid.points
        .where((MapGridPointDto point) => point.status.toLowerCase() == 'fresh')
        .map((MapGridPointDto point) => Marker(
              point: LatLng(point.lat, point.lon),
              width: 62,
              height: 62,
              child: _FieldGlyph(point: point, mode: mode),
            ))
        .toList();
  }

  Future<void> _locateDevice() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return;
      setState(() => _searchMessage = 'Location services are disabled on this device.');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() => _searchMessage = 'Location permission was not granted.');
      return;
    }
    try {
      final Position position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final LatLng location = LatLng(position.latitude, position.longitude);
      setState(() {
        _deviceLocation = location;
        _fieldCenter = location;
        _fieldSpan = 0.6;
        _hasSelectedInitialLayer = false;
        _searchMessage = null;
      });
      _mapController.move(location, 9);
    } catch (error) {
      if (!mounted) return;
      setState(() => _searchMessage = 'Device location could not be read: $error');
    }
  }

  void _fetchAtMapCenter() {
    final MapCamera camera = _mapController.camera;
    setState(() {
      _fieldCenter = camera.center;
      _fieldSpan = camera.zoom >= 9 ? 0.4 : 0.8;
      _hasSelectedInitialLayer = false;
      _searchMessage = null;
    });
    ref.invalidate(mapLayerCatalogProvider(MapCenter(camera.center.latitude, camera.center.longitude)));
  }

  /// Search accepts coordinates and locally saved place names only. There is no
  /// geocoding provider in this deployment, so an unmatched query says so
  /// rather than resolving to an invented location.
  void _search(String raw) {
    final String query = raw.trim();
    if (query.isEmpty) {
      setState(() => _searchMessage = null);
      return;
    }
    final RegExpMatch? match = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$').firstMatch(query);
    if (match != null) {
      final double lat = double.parse(match.group(1)!);
      final double lon = double.parse(match.group(2)!);
      if (lat.abs() <= 90 && lon.abs() <= 180) {
        setState(() {
          _fieldCenter = LatLng(lat, lon);
          _hasSelectedInitialLayer = false;
          _searchMessage = null;
        });
        _mapController.move(LatLng(lat, lon), 9);
        return;
      }
    }
    final List<SavedLocation> saved = ref.read(savedLocationsProvider);
    final List<SavedLocation> matches = saved
        .where((SavedLocation location) => location.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (matches.isEmpty) {
      setState(() => _searchMessage =
          'No saved location or coordinate matched "$query". ORCA has no place-name geocoder in this deployment.');
      return;
    }
    final SavedLocation location = matches.first;
    setState(() {
      _fieldCenter = LatLng(location.latitude, location.longitude);
      _hasSelectedInitialLayer = false;
      _searchMessage = match == null ? 'Showing saved location “${location.name}”.' : null;
    });
    _mapController.move(LatLng(location.latitude, location.longitude), 9.5);
  }

  void _toggleLayer(String layerId, bool enabled) {
    final Set<String> next = <String>{...ref.read(mapLayerSelectionProvider)};
    if (enabled) {
      next.add(layerId);
    } else {
      next.remove(layerId);
    }
    ref.read(mapLayerSelectionProvider.notifier).state = next;
  }

  void _showLayers(List<MapLayerEntity> layers, Set<String> selected) {
    if (layers.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => LayerSelectorDialog(
        layers: layers,
        selectedIds: selected,
        onChanged: (Set<String> value) => ref.read(mapLayerSelectionProvider.notifier).state = value,
      ),
    );
  }
}

class _TimelineEntry {
  final String label;
  final String? validTime;
  final String? tooltip;

  const _TimelineEntry({required this.label, this.validTime, this.tooltip});
}

class _SearchPanel extends StatelessWidget {
  final TextEditingController controller;
  final String? message;
  final ValueChanged<String> onSubmit;
  final VoidCallback onFetchHere;

  const _SearchPanel({
    required this.controller,
    required this.message,
    required this.onSubmit,
    required this.onFetchHere,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: OrcaTheme.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OrcaTheme.cardBorder),
        boxShadow: OrcaTheme.floatingShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: controller,
                    onSubmitted: onSubmit,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Coordinates (18.92, 72.20) or saved location',
                      prefixIcon: Icon(Icons.search_rounded, size: 18),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => onSubmit(controller.text),
                  icon: const Icon(Icons.travel_explore_rounded, size: 16),
                  label: const Text('Go'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: onFetchHere,
                  icon: const Icon(Icons.ads_click_rounded, size: 16),
                  label: const Text('Sample here'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
              ),
            ],
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 7),
            Text(message!, style: OrcaType.caption.copyWith(fontSize: 10.5)),
          ],
        ],
      ),
    );
  }
}

class _RoundMapControl extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundMapControl({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: OrcaTheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 19, color: OrcaTheme.textPrimary),
            ),
          ),
        ),
      );
}

class _ActiveLayerLegend extends StatelessWidget {
  final Set<String> selected;
  final MapGridDto? grid;
  final bool online;

  const _ActiveLayerLegend({required this.selected, required this.grid, required this.online});

  @override
  Widget build(BuildContext context) {
    final String label;
    if (!online) {
      label = 'OFFLINE · BASE CHART ONLY';
    } else if (selected.isEmpty) {
      label = 'NO FIELD LAYER ACTIVE';
    } else if (selected.contains('pfz') && grid == null) {
      label = 'PFZ GEOMETRY · PROVIDER RESPONSE';
    } else {
      final String name = selected.contains('wind')
          ? 'WIND'
          : selected.contains('waves')
              ? 'WAVES'
              : selected.contains('sst')
                  ? 'SST'
                  : 'PFZ';
      label = '$name · ${grid?.state ?? 'FETCHING'}';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: OrcaTheme.deepTeal.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.layers_rounded, size: 13, color: OrcaTheme.onDeepTealStrong),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapBanner extends StatelessWidget {
  final String message;

  const _MapBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: VerdictColors.noGoBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VerdictColors.noGo.withValues(alpha: 0.35)),
        ),
        child: Text(
          message,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: OrcaTheme.textPrimary),
        ),
      );
}

class _LayerChips extends StatelessWidget {
  final List<MapLayerEntity> layers;
  final Set<String> selected;
  final void Function(String layerId, bool enabled) onToggle;

  const _LayerChips({required this.layers, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    if (layers.isEmpty) {
      return const OrcaUnavailable(
        icon: Icons.layers_clear_outlined,
        title: 'Layer catalogue unavailable',
        message: 'The ORCA Box did not return its map layer capabilities, so no overlay can be enabled.',
        compact: true,
      );
    }
    final List<MapLayerEntity> ordered = <MapLayerEntity>[
      ...layers.where((MapLayerEntity layer) => layer.isMapRenderable),
      ...layers.where((MapLayerEntity layer) => !layer.isMapRenderable),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final MapLayerEntity layer in ordered)
          _LayerChip(
            layer: layer,
            enabled: selected.contains(layer.id),
            onToggle: onToggle,
          ),
      ],
    );
  }
}

class _LayerChip extends StatelessWidget {
  final MapLayerEntity layer;
  final bool enabled;
  final void Function(String layerId, bool enabled) onToggle;

  const _LayerChip({required this.layer, required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final bool interactive = layer.isMapRenderable;
    final Color border = !interactive
        ? OrcaTheme.cardBorder
        : enabled
            ? OrcaTheme.deepTeal
            : OrcaTheme.cardBorderStrong;
    final Color background = !interactive
        ? OrcaTheme.surfaceElevated
        : enabled
            ? OrcaTheme.deepTeal
            : OrcaTheme.surface;
    final Color ink = !interactive
        ? OrcaTheme.textMuted
        : enabled
            ? Colors.white
            : OrcaTheme.textPrimary;

    return Tooltip(
      message: interactive
          ? '${layer.source} · ${layer.state}${layer.resolution == null ? '' : ' · ${layer.resolution}'}'
          : (layer.reason ?? 'Not published by this backend'),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: interactive ? () => onToggle(layer.id, !enabled) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  interactive ? (enabled ? Icons.check_circle : Icons.circle_outlined) : Icons.lock_outline_rounded,
                  size: 13,
                  color: ink,
                ),
                const SizedBox(width: 6),
                Text(
                  layer.name,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineSection extends StatelessWidget {
  final List<_TimelineEntry> entries;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _TimelineSection({
    required this.entries,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.length <= 1) {
      return const OrcaUnavailable(
        icon: Icons.timeline_rounded,
        title: 'Forecast timeline unavailable',
        message: 'The ORCA Box returned no hourly series for this location, so no forecast timestep can be selected. The map shows the current field only.',
        compact: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const OrcaEyebrow('FORECAST TIMELINE', color: OrcaTheme.textMuted),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (BuildContext context, int index) {
              final bool selected = index == selectedIndex;
              final _TimelineEntry entry = entries[index];
              return Tooltip(
                message: entry.validTime == null
                    ? 'Current model response'
                    : 'Valid ${entry.tooltip ?? entry.validTime!}',
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: 'Forecast step ${entry.label}',
                  child: Material(
                    color: selected ? OrcaTheme.deepTeal : OrcaTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelected(index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? OrcaTheme.deepTeal : OrcaTheme.cardBorder,
                          ),
                        ),
                        child: Text(
                          entry.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: selected ? Colors.white : OrcaTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FieldProvenance extends StatelessWidget {
  final AsyncValue<MapGridDto>? grid;
  final AsyncValue<PfzResponseDto>? pfz;
  final Set<String> selected;
  final List<MapLayerEntity> layers;
  final String? validTime;
  final bool online;

  const _FieldProvenance({
    required this.grid,
    required this.pfz,
    required this.selected,
    required this.layers,
    required this.validTime,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final List<MapLayerEntity> active =
        layers.where((MapLayerEntity layer) => selected.contains(layer.id)).toList();

    if (active.isEmpty) {
      return const OrcaUnavailable(
        icon: Icons.layers_clear_outlined,
        title: 'No field displayed',
        message: 'Choose a published layer to display verified marine samples over the base chart.',
        compact: true,
      );
    }

    if (grid == null) {
      final AsyncValue<PfzResponseDto>? pfzState = pfz;
      if (pfzState == null) return const SizedBox.shrink();
      return pfzState.when(
        loading: () => const _InspectorLoading(label: 'Fetching official PFZ geometry…'),
        error: (_, __) => const OrcaUnavailable(
          icon: Icons.cloud_off_outlined,
          title: 'PFZ geometry unavailable',
          message: 'The official INCOIS WFS did not respond. No substitute geometry is drawn.',
          compact: true,
        ),
        data: (PfzResponseDto data) => data.status.toLowerCase() == 'fresh'
            ? OrcaCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Row(
                      children: <Widget>[
                        Expanded(child: OrcaEyebrow('PFZ GEOMETRY', color: OrcaTheme.textMuted)),
                        OrcaStateChip(state: OrcaDataState.current),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${data.features.length} official WFS feature${data.features.length == 1 ? '' : 's'} rendered',
                      style: OrcaType.body.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    OrcaProvenance(
                      source: data.source,
                      timeLabel: data.fetchedAt == null
                          ? 'Fetch time unavailable'
                          : 'ORCA retrieved ${DateFormatter.formatIstTime(data.fetchedAt!)}',
                    ),
                  ],
                ),
              )
            : const OrcaUnavailable(
                icon: Icons.cloud_off_outlined,
                title: 'PFZ geometry unavailable',
                message: 'The official INCOIS WFS returned no usable features for this deployment.',
                compact: true,
              ),
      );
    }

    return grid!.when(
      loading: () => const _InspectorLoading(label: 'Sampling the model field…'),
      error: (_, __) => const OrcaUnavailable(
        icon: Icons.cloud_off_outlined,
        title: 'Field samples unavailable',
        message: 'The selected layer was not drawn because the ORCA Box could not return verified samples.',
        compact: true,
      ),
      data: (MapGridDto field) {
        final int fresh = field.points
            .where((MapGridPointDto point) => point.status.toLowerCase() == 'fresh')
            .length;
        final OrcaDataState state = fresh == 0
            ? OrcaDataState.unavailable
            : (field.validTime == null ? OrcaDataState.current : OrcaDataState.forecast);
        return OrcaCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OrcaEyebrow(
                      active.map((MapLayerEntity layer) => layer.name).join(' + ').toUpperCase(),
                      color: OrcaTheme.textMuted,
                    ),
                  ),
                  OrcaStateChip(state: state),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                fresh == 0
                    ? 'No verified sample in this area — the base chart is shown without an overlay.'
                    : '$fresh of ${field.points.length} samples verified',
                style: OrcaType.body.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 6),
              OrcaProvenance(
                source: field.sources.isEmpty ? 'Source unavailable' : field.sources.join(' · '),
                timeLabel: field.validTime == null
                    ? 'Current model response'
                    : 'Model valid ${DateFormatter.formatIstTime(DateTime.tryParse(field.validTime!) ?? DateTime.now().toUtc())}',
              ),
              const SizedBox(height: 2),
              OrcaProvenance(
                timeLabel: field.fetchedAt == null
                    ? 'Retrieval time unavailable'
                    : 'ORCA retrieved ${DateFormatter.formatIstTime(field.fetchedAt!)}',
              ),
              if (field.resolution != null) ...<Widget>[
                const SizedBox(height: 2),
                OrcaProvenance(timeLabel: field.resolution),
              ],
              const SizedBox(height: 2),
              const OrcaProvenance(timeLabel: 'Wind threshold colouring follows ORCA limits: 20 kn caution, 34 kn danger.'),
            ],
          ),
        );
      },
    );
  }
}

class _InspectorLoading extends StatelessWidget {
  final String label;

  const _InspectorLoading({this.label = 'Inspecting verified marine conditions…'});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OrcaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: OrcaType.body.copyWith(fontSize: 12))),
          ],
        ),
      );
}

class _FieldGlyph extends StatelessWidget {
  final MapGridPointDto point;
  final String mode;

  const _FieldGlyph({required this.point, required this.mode});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String? value, double rotation) = switch (mode) {
      'wind' => (
          Icons.navigation_rounded,
          point.windKn == null ? null : '${point.windKn!.toStringAsFixed(0)} kn',
          point.windDirectionDeg == null ? 0 : point.windDirectionDeg! * math.pi / 180,
        ),
      'waves' => (
          Icons.waves_rounded,
          point.waveHeightM == null ? null : '${point.waveHeightM!.toStringAsFixed(1)} m',
          0,
        ),
      _ => (
          Icons.thermostat_rounded,
          point.seaTempC == null ? null : '${point.seaTempC!.toStringAsFixed(1)}°',
          0,
        ),
    };
    if (value == null) return const SizedBox.shrink();
    return Semantics(
      label: '$mode $value at ${point.lat.toStringAsFixed(2)}, ${point.lon.toStringAsFixed(2)}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Transform.rotate(
            angle: rotation,
            child: Icon(
              icon,
              color: OrcaTheme.deepTeal,
              size: 20,
              shadows: const <Shadow>[Shadow(color: Colors.white, blurRadius: 4)],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: OrcaTheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: OrcaTheme.cardBorderStrong),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: OrcaTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributionNote extends StatelessWidget {
  const _AttributionNote();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.copyright_rounded, size: 13, color: OrcaTheme.textMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Base chart data © OpenStreetMap contributors. Marine values are point-sampled model fields returned by this ORCA Box — never interpolated or substituted.',
              style: OrcaType.caption,
            ),
          ),
        ],
      );
}
