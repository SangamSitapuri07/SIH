import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/widgets/orca_navigation.dart';
import '../../../../core/widgets/orca_ui.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../../locations/domain/saved_location.dart';
import '../../../locations/presentation/providers/locations_provider.dart';
import '../providers/navigate_provider.dart';
import '../providers/offline_navigation_provider.dart';
import '../providers/trip_plan_provider.dart';
import '../widgets/route_verdict_card.dart';
import '../widgets/transit_points_strip.dart';

/// Route planner and transit verifier.
///
/// The planner only accepts real coordinates (typed, picked from the working
/// location or from a saved location). Results come from `/api/v1/route-check`
/// and `/api/v1/route-advisory`; the screen starts empty and never prefills a
/// harbour, a detour or a verdict.
class NavigateScreen extends ConsumerStatefulWidget {
  const NavigateScreen({super.key});

  @override
  ConsumerState<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends ConsumerState<NavigateScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _fromLat = TextEditingController();
  final TextEditingController _fromLon = TextEditingController();
  final TextEditingController _toLat = TextEditingController();
  final TextEditingController _toLon = TextEditingController();
  String? _formMessage;

  @override
  void initState() {
    super.initState();
    // The departure defaults to the working location because that is the real
    // coordinate this device is already watching — the fields stay editable and
    // the result is only produced when the skipper asks for it.
    final Map<String, double> coords = ref.read(advisoryLocationProvider);
    _fromLat.text = (coords['lat'] ?? AppConfig.defaultLat).toStringAsFixed(4);
    _fromLon.text = (coords['lon'] ?? AppConfig.defaultLon).toStringAsFixed(4);
    final savedRoute = ref.read(offlineNavigationProvider).package;
    if (savedRoute != null && savedRoute.geometry.length >= 2) {
      _fromLat.text = savedRoute.geometry.first[0].toStringAsFixed(4);
      _fromLon.text = savedRoute.geometry.first[1].toStringAsFixed(4);
      _toLat.text = savedRoute.geometry.last[0].toStringAsFixed(4);
      _toLon.text = savedRoute.geometry.last[1].toStringAsFixed(4);
    }
  }

  @override
  void dispose() {
    _fromLat.dispose();
    _fromLon.dispose();
    _toLat.dispose();
    _toLon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<RouteAnalysisState> state = ref.watch(navigateProvider);
    final OfflineNavigationState offlineNavigation = ref.watch(offlineNavigationProvider);
    final Map<String, dynamic>? offlineTripPlan = ref.watch(tripPlanProvider).valueOrNull;
    final bool isOnline = ref.watch(isOnlineProvider);

    return OrcaWorkspaceScaffold(
      title: AppLocalizations.of(context)?.navigateTitle ?? 'Route planner',
      subtitle: 'Course verification and sampled transit',
      locationLabel: 'Departure',
      coordinateLabel: _departureLabel(),
      stateLabel: state.hasValue && state.valueOrNull?.advisory != null ? 'RESULT READY' : null,
      onRefresh: () async {
        // The refresh control re-runs the check when the form is valid, so the
        // button always performs a real backend request rather than a no-op.
        if (_formKey.currentState?.validate() ?? false) _checkRoute();
      },
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool twoColumn = constraints.maxWidth > OrcaTheme.compactBreakpoint;
          final Widget planner = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const OrcaEyebrow('TRIP PLANNING', color: OrcaTheme.accentDark),
              const SizedBox(height: 6),
              Text('Know the route before you cast off.', style: OrcaType.displayCompact),
              const SizedBox(height: 8),
              Text(
                'Enter departure and destination coordinates. ORCA samples the real marine inputs along the leg and reports land clearance only when a verified land-mask source answers.',
                style: OrcaType.body.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),
              _RoutePickerMap(
                departure: _coordinate(_fromLat, _fromLon),
                destination: _coordinate(_toLat, _toLon),
                route: state.valueOrNull?.check?.legs ??
                    offlineNavigation.package?.geometry ?? const <List<double>>[],
                vesselPosition: offlineNavigation.progress == null
                    ? null
                    : LatLng(offlineNavigation.progress!.latitude, offlineNavigation.progress!.longitude),
                isOnline: isOnline,
                onPointPicked: _setPickedPoint,
              ),
              const SizedBox(height: 14),
              _RouteForm(
                formKey: _formKey,
                fromLat: _fromLat,
                fromLon: _fromLon,
                toLat: _toLat,
                toLon: _toLon,
                message: _formMessage,
                onUseWorkingLocation: _useWorkingLocation,
                onPickSaved: _pickSavedLocation,
                onCheck: _checkRoute,
              ),
              const SizedBox(height: 14),
              _OfflineTripPlanner(
                departure: _coordinate(_fromLat, _fromLon),
                area: _coordinate(_toLat, _toLon) ?? _coordinate(_fromLat, _fromLon),
              ),
              const SizedBox(height: 14),
              const _TimeContractNote(),
            ],
          );

          final Widget results = state.when(
            data: (RouteAnalysisState data) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _OfflineNavigationCard(state: offlineNavigation, isOnline: isOnline, tripPlan: offlineTripPlan),
                const SizedBox(height: 16),
                if (data.advisory == null)
                  (data.check == null ? const _RouteEmpty() : const _RouteLoading())
                else ...<Widget>[
                  const OrcaEyebrow('ROUTE SAFETY RESULT', color: OrcaTheme.textMuted),
                  const SizedBox(height: 10),
                  RouteVerdictCard(advisory: data.advisory!, check: data.check),
                  const SizedBox(height: 16),
                  TransitPointsStrip(points: data.advisory!.points),
                ],
              ],
            ),
            loading: () => Column(
              children: <Widget>[
                _OfflineNavigationCard(state: offlineNavigation, isOnline: isOnline, tripPlan: offlineTripPlan),
                const SizedBox(height: 16),
                const _RouteLoading(),
              ],
            ),
            error: (Object? error, StackTrace? stack) => Column(
              children: <Widget>[
                _OfflineNavigationCard(state: offlineNavigation, isOnline: isOnline, tripPlan: offlineTripPlan),
                const SizedBox(height: 16),
                OrcaUnavailable(
                  icon: Icons.cloud_off_outlined,
                  title: 'Online route refresh unavailable',
                  message: 'The saved offline route remains usable. Live route inputs could not be refreshed. $error',
                  actionLabel: 'Retry when connected',
                  onAction: _checkRoute,
                ),
              ],
            ),
          );

          final Widget body = ListView(
            padding: orcaContentPadding(wide: twoColumn),
            children: <Widget>[
              if (twoColumn)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 5, child: planner),
                    const SizedBox(width: 20),
                    Expanded(flex: 6, child: results),
                  ],
                )
              else ...<Widget>[
                planner,
                const SizedBox(height: 20),
                results,
              ],
            ],
          );

          return body;
        },
      ),
    );
  }

  String _departureLabel() {
    final double? lat = double.tryParse(_fromLat.text.trim());
    final double? lon = double.tryParse(_fromLon.text.trim());
    if (lat == null || lon == null) return 'Coordinates not set';
    return GeoUtils.formatCoordinate(lat, lon);
  }

  void _useWorkingLocation() {
    final Map<String, double> coords = ref.read(advisoryLocationProvider);
    setState(() {
      _fromLat.text = (coords['lat'] ?? AppConfig.defaultLat).toStringAsFixed(4);
      _fromLon.text = (coords['lon'] ?? AppConfig.defaultLon).toStringAsFixed(4);
      _formMessage = 'Departure set to the working location.';
    });
  }

  Future<void> _pickSavedLocation({required bool asDeparture}) async {
    final List<SavedLocation> saved = ref.read(savedLocationsProvider);
    if (saved.isEmpty) {
      setState(() => _formMessage =
          'No saved locations yet. Save a harbour or fishing area first, or enter coordinates directly.');
      return;
    }
    final SavedLocation? picked = await showModalBottomSheet<SavedLocation>(
      context: context,
      backgroundColor: OrcaTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: <Widget>[
            const OrcaEyebrow('SAVED LOCATIONS', color: OrcaTheme.accentDark),
            const SizedBox(height: 8),
            for (final SavedLocation location in saved)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const OrcaIconBadge(icon: Icons.place_outlined),
                title: Text(location.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                subtitle: Text(
                  '${location.latitude.toStringAsFixed(3)}, ${location.longitude.toStringAsFixed(3)}',
                  style: OrcaType.caption,
                ),
                onTap: () => Navigator.pop(sheetContext, location),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (asDeparture) {
        _fromLat.text = picked.latitude.toStringAsFixed(4);
        _fromLon.text = picked.longitude.toStringAsFixed(4);
      } else {
        _toLat.text = picked.latitude.toStringAsFixed(4);
        _toLon.text = picked.longitude.toStringAsFixed(4);
      }
      _formMessage = null;
    });
  }

  LatLng? _coordinate(TextEditingController lat, TextEditingController lon) {
    final double? latitude = double.tryParse(lat.text.trim());
    final double? longitude = double.tryParse(lon.text.trim());
    return latitude == null || longitude == null ? null : LatLng(latitude, longitude);
  }

  void _setPickedPoint(LatLng point) {
    setState(() {
      if (_coordinate(_fromLat, _fromLon) == null || _coordinate(_toLat, _toLon) != null) {
        _fromLat.text = point.latitude.toStringAsFixed(5);
        _fromLon.text = point.longitude.toStringAsFixed(5);
        _toLat.clear();
        _toLon.clear();
        _formMessage = 'Departure selected. Tap the map again for destination.';
      } else {
        _toLat.text = point.latitude.toStringAsFixed(5);
        _toLon.text = point.longitude.toStringAsFixed(5);
        _formMessage = 'Destination selected. Check route to run verified planning.';
      }
    });
  }

  void _checkRoute() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _formMessage = null);
    ref.read(navigateProvider.notifier).evaluateRoute(
          fromLat: double.parse(_fromLat.text.trim()),
          fromLon: double.parse(_fromLon.text.trim()),
          toLat: double.parse(_toLat.text.trim()),
          toLon: double.parse(_toLon.text.trim()),
        );
  }
}

class _RoutePickerMap extends StatelessWidget {
  final LatLng? departure;
  final LatLng? destination;
  final List<List<double>> route;
  final LatLng? vesselPosition;
  final bool isOnline;
  final ValueChanged<LatLng> onPointPicked;

  const _RoutePickerMap({
    required this.departure,
    required this.destination,
    required this.route,
    required this.vesselPosition,
    required this.isOnline,
    required this.onPointPicked,
  });

  @override
  Widget build(BuildContext context) {
    final LatLng centre = departure ?? const LatLng(AppConfig.defaultLat, AppConfig.defaultLon);
    final List<LatLng> line = route
        .where((List<double> point) => point.length >= 2)
        .map((List<double> point) => LatLng(point[0], point[1]))
        .toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 300,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: centre,
            initialZoom: 8,
            onTap: (_, LatLng point) => onPointPicked(point),
          ),
          children: <Widget>[
            if (isOnline)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.orca.marine',
              )
            else
              const SizedBox.expand(child: ColoredBox(color: Color(0xFFE8F4F4))),
            if (line.length >= 2)
              PolylineLayer(
                polylines: <Polyline>[
                  Polyline(points: line, strokeWidth: 5, color: OrcaTheme.accent),
                ],
              ),
            MarkerLayer(
              markers: <Marker>[
                if (departure != null)
                  Marker(
                    point: departure!,
                    width: 42,
                    height: 42,
                    child: const OrcaIconBadge(icon: Icons.trip_origin_rounded),
                  ),
                if (destination != null)
                  Marker(
                    point: destination!,
                    width: 42,
                    height: 42,
                    child: const OrcaIconBadge(icon: Icons.flag_rounded),
                  ),
                if (vesselPosition != null)
                  Marker(
                    point: vesselPosition!,
                    width: 46,
                    height: 46,
                    child: const OrcaIconBadge(icon: Icons.navigation_rounded),
                  ),
              ],
            ),
            Positioned(
              left: 10,
              top: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(color: OrcaTheme.surface, borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    isOnline
                        ? 'Tap destination · tap again to restart'
                        : 'OFFLINE · saved vector route · base tiles unavailable',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteForm extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController fromLat;
  final TextEditingController fromLon;
  final TextEditingController toLat;
  final TextEditingController toLon;
  final String? message;
  final VoidCallback onUseWorkingLocation;
  final void Function({required bool asDeparture}) onPickSaved;
  final VoidCallback onCheck;

  const _RouteForm({
    required this.formKey,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.message,
    required this.onUseWorkingLocation,
    required this.onPickSaved,
    required this.onCheck,
  });

  @override
  Widget build(BuildContext context) {
    return OrcaCard(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OrcaEyebrow('DEPARTURE', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            _CoordinateRow(lat: fromLat, lon: fromLon),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: onUseWorkingLocation,
                  icon: const Icon(Icons.my_location_rounded, size: 15),
                  label: const Text('Working location'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
                TextButton.icon(
                  onPressed: () => onPickSaved(asDeparture: true),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 15),
                  label: const Text('Saved place'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: OrcaTheme.cardBorder),
            ),
            const OrcaEyebrow('DESTINATION', color: OrcaTheme.textMuted),
            const SizedBox(height: 8),
            _CoordinateRow(lat: toLat, lon: toLon),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => onPickSaved(asDeparture: false),
                  icon: const Icon(Icons.bookmark_border_rounded, size: 15),
                  label: const Text('Saved place'),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ],
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(message!, style: OrcaType.caption.copyWith(fontSize: 11.5)),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onCheck,
              icon: const Icon(Icons.route_outlined, size: 18),
              label: const Text('Check route safety'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateRow extends StatelessWidget {
  final TextEditingController lat;
  final TextEditingController lon;

  const _CoordinateRow({required this.lat, required this.lon});

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: TextFormField(
              controller: lat,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude'),
              validator: _validateLatitude,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: lon,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitude'),
              validator: _validateLongitude,
            ),
          ),
        ],
      );

  static String? _validateLatitude(String? value) {
    final double? parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return 'Enter a latitude';
    if (parsed.abs() > 90) return 'Latitude must be within ±90°';
    return null;
  }

  static String? _validateLongitude(String? value) {
    final double? parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || !parsed.isFinite) return 'Enter a longitude';
    if (parsed.abs() > 180) return 'Longitude must be within ±180°';
    return null;
  }
}

class _OfflineNavigationCard extends ConsumerWidget {
  final OfflineNavigationState state;
  final bool isOnline;
  final Map<String, dynamic>? tripPlan;

  const _OfflineNavigationCard({
    required this.state, required this.isOnline, required this.tripPlan,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final package = state.package;
    final progress = state.progress;
    final weatherUsable = package != null && !package.weatherExpired;
    final timelineNow = _timelineAt(DateTime.now().toUtc(), tripPlan);
    return OrcaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Expanded(child: OrcaEyebrow('OFFLINE GPS NAVIGATION', color: OrcaTheme.accentDark)),
          OrcaInfoPill(
            icon: isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            label: isOnline ? 'ONLINE' : 'OFFLINE',
          ),
        ]),
        const SizedBox(height: 7),
        Text(
          package == null
              ? 'No route is stored on this device.'
              : '${package.distanceKm.toStringAsFixed(1)} km route saved · ${package.geometry.length} geometry points',
          style: OrcaType.cardTitle,
        ),
        const SizedBox(height: 5),
        Text(
          package == null
              ? 'Check a verified route while connected. ORCA will automatically store its geometry and sampled evidence for GPS use at sea.'
              : 'GPS progress and off-route detection run entirely on this device. Internet is not required.',
          style: OrcaType.caption,
        ),
        if (package != null) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: weatherUsable ? const Color(0xFFE8F7F3) : const Color(0xFFFFF3E4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              weatherUsable
                  ? 'Downloaded safety evidence: ${package.advisoryLevel} · valid until ${_shortUtc(package.weatherValidUntil)}'
                  : 'WEATHER EXPIRED · Geometry/GPS remains available, but cached conditions must not be treated as current. Re-check when connected.',
              style: OrcaType.caption.copyWith(
                color: weatherUsable ? OrcaTheme.accentDark : VerdictColors.caution,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (weatherUsable && timelineNow != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Downloaded forecast now · ${timelineNow['state'] ?? 'UNVERIFIED'} · '
              'Wave ${timelineNow['worst_wave_m'] ?? '?'} m · Wind ${timelineNow['worst_wind_kn'] ?? '?'} kn · '
              'Gust ${timelineNow['worst_gust_kn'] ?? '?'} kn',
              style: OrcaType.caption.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Valid at ${timelineNow['valid_at'] ?? 'unknown'} · area-wide worst sampled values, not live sensor readings.',
              style: OrcaType.caption.copyWith(fontSize: 10.5),
            ),
          ],
          if (progress != null) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
              _OfflineMetric(label: 'REMAINING', value: '${progress.remainingKm.toStringAsFixed(1)} km'),
              _OfflineMetric(label: 'COMPLETED', value: '${progress.completedKm.toStringAsFixed(1)} km'),
              _OfflineMetric(label: 'OFF ROUTE', value: '${progress.offRouteKm.toStringAsFixed(2)} km'),
              _OfflineMetric(label: 'RETURN TO START', value: '${progress.distanceToDepartureKm.toStringAsFixed(1)} km'),
              _OfflineMetric(label: 'DESTINATION BEARING', value: '${progress.bearingToDestination.toStringAsFixed(0)}°'),
              _OfflineMetric(label: 'GPS ACCURACY', value: '±${progress.accuracyM.toStringAsFixed(0)} m'),
            ]),
            if (progress.isOffRoute) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                'OFF-ROUTE WARNING · Vessel is more than 2 km from the downloaded route. Slow down, verify position/chart and return to the saved route only when safe.',
                style: TextStyle(color: VerdictColors.danger, fontWeight: FontWeight.w800, fontSize: 11.5, height: 1.4),
              ),
            ],
          ],
          if (state.error != null) ...<Widget>[
            const SizedBox(height: 9),
            Text(state.error!, style: OrcaType.caption.copyWith(color: VerdictColors.danger)),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: state.tracking
                ? () => ref.read(offlineNavigationProvider.notifier).stopTracking()
                : () => ref.read(offlineNavigationProvider.notifier).startTracking(),
            icon: Icon(state.tracking ? Icons.stop_circle_outlined : Icons.gps_fixed_rounded, size: 18),
            label: Text(state.tracking ? 'Stop offline GPS' : 'Start offline GPS navigation'),
          ),
          const SizedBox(height: 8),
          Text(
            'Saved ${_shortUtc(package.savedAt)} · ${package.weatherPoints.length} weather samples · no position is uploaded by this feature.',
            style: OrcaType.caption.copyWith(fontSize: 10.5),
          ),
        ],
      ]),
    );
  }

  static Map<String, dynamic>? _timelineAt(
    DateTime now, Map<String, dynamic>? plan,
  ) {
    final raw = plan?['timeline'];
    if (raw is! List) return null;
    Map<String, dynamic>? firstFuture;
    Map<String, dynamic>? latestPast;
    for (final item in raw.whereType<Map>()) {
      final mapped = Map<String, dynamic>.from(item);
      final validAt = DateTime.tryParse(mapped['valid_at']?.toString() ?? '')?.toUtc();
      if (validAt == null) continue;
      if (validAt.isAfter(now)) {
        firstFuture ??= mapped;
        break;
      }
      latestPast = mapped;
    }
    return latestPast ?? firstFuture;
  }

  static String _shortUtc(DateTime value) =>
      '${value.toUtc().day.toString().padLeft(2, '0')}/${value.toUtc().month.toString().padLeft(2, '0')} '
      '${value.toUtc().hour.toString().padLeft(2, '0')}:${value.toUtc().minute.toString().padLeft(2, '0')} UTC';
}

class _OfflineMetric extends StatelessWidget {
  final String label;
  final String value;
  const _OfflineMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: 142,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: OrcaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: OrcaTheme.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(label, style: OrcaType.caption.copyWith(fontSize: 9, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value, style: OrcaType.metricLabel.copyWith(fontWeight: FontWeight.w800)),
        ]),
      );
}

class _OfflineTripPlanner extends ConsumerStatefulWidget {
  final LatLng? departure;
  final LatLng? area;
  const _OfflineTripPlanner({required this.departure, required this.area});

  @override
  ConsumerState<_OfflineTripPlanner> createState() => _OfflineTripPlannerState();
}

class _OfflineTripPlannerState extends ConsumerState<_OfflineTripPlanner> {
  int _days = 3;
  int _departureOffsetHours = 0;
  final _radius = TextEditingController(text: '75');
  final _fish = TextEditingController();
  final _fuel = TextEditingController(text: '200');
  final _burn = TextEditingController();
  final _crew = TextEditingController(text: '4');
  final _capacity = TextEditingController(text: '500');
  final _speed = TextEditingController(text: '8');
  String _experience = 'unspecified';

  @override
  void dispose() {
    _radius.dispose(); _fish.dispose(); _fuel.dispose(); _burn.dispose();
    _crew.dispose(); _capacity.dispose(); _speed.dispose();
    super.dispose();
  }

  double? _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripPlanProvider);
    final plan = state.valueOrNull;
    return OrcaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const OrcaEyebrow('OFFLINE TRIP PACKAGE', color: OrcaTheme.accentDark),
        const SizedBox(height: 6),
        const Text('Pre-analyse the full fishing area', style: OrcaType.cardTitle),
        const SizedBox(height: 5),
        Text('Downloads an hour-by-hour area forecast before departure and saves it on this device.', style: OrcaType.caption),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: DropdownButtonFormField<int>(
            value: _days,
            decoration: const InputDecoration(labelText: 'Trip duration'),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem(value: 1, child: Text('1 day')),
              DropdownMenuItem(value: 2, child: Text('2 days')),
              DropdownMenuItem(value: 3, child: Text('3 days')),
            ],
            onChanged: (value) => setState(() => _days = value ?? 3),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Area radius (km)'))),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: _departureOffsetHours,
          decoration: const InputDecoration(labelText: 'Planned departure'),
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem(value: 0, child: Text('Now')),
            DropdownMenuItem(value: 2, child: Text('In 2 hours')),
            DropdownMenuItem(value: 6, child: Text('In 6 hours')),
            DropdownMenuItem(value: 12, child: Text('In 12 hours')),
            DropdownMenuItem(value: 24, child: Text('Tomorrow')),
          ],
          onChanged: (value) => setState(() => _departureOffsetHours = value ?? 0),
        ),
        const SizedBox(height: 10),
        TextField(controller: _fish, decoration: const InputDecoration(labelText: 'Target fish (comma separated)')),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: TextField(controller: _crew, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Crew size'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fish storage (kg)'))),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: TextField(controller: _speed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cruise speed (kn)'))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(
            value: _experience,
            decoration: const InputDecoration(labelText: 'Experience'),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem(value: 'unspecified', child: Text('Not specified')),
              DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
              DropdownMenuItem(value: 'experienced', child: Text('Experienced')),
              DropdownMenuItem(value: 'expert', child: Text('Expert')),
            ],
            onChanged: (value) => setState(() => _experience = value ?? 'unspecified'),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: TextField(controller: _fuel, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fuel available (L)'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _burn, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fuel burn (L/hour)'))),
        ]),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: state.isLoading || widget.area == null ? null : () {
            final radius = _value(_radius), fuel = _value(_fuel), burn = _value(_burn);
            final crew = int.tryParse(_crew.text.trim());
            final capacity = _value(_capacity), speed = _value(_speed);
            if (radius == null || fuel == null || crew == null || capacity == null || speed == null ||
                radius < 5 || radius > 200 || fuel < 0 || crew < 1 || capacity <= 0 || speed <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Enter valid radius, crew, storage, speed and fuel values.'),
              ));
              return;
            }
            ref.read(tripPlanProvider.notifier).generate(TripPlanInput(
              areaLat: widget.area!.latitude, areaLon: widget.area!.longitude,
              departureLat: widget.departure?.latitude,
              departureLon: widget.departure?.longitude,
              departureAt: DateTime.now().toUtc().add(Duration(hours: _departureOffsetHours)),
              durationDays: _days, radiusKm: radius, fuelLiters: fuel,
              fuelBurnLph: burn ?? 0, crewSize: crew, capacityKg: capacity,
              cruiseSpeedKn: speed, experienceLevel: _experience,
              targetFish: _fish.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
            ));
          },
          icon: state.isLoading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.offline_pin_outlined),
          label: Text(state.isLoading ? 'Analysing 7-day data…' : 'Build offline trip package'),
        ),
        if (widget.area == null) ...<Widget>[
          const SizedBox(height: 8),
          Text('Select a planned area on the map first.', style: OrcaType.caption),
        ],
        if (plan != null) ...<Widget>[
          const SizedBox(height: 14),
          _TripPlanSummary(plan: plan),
        ],
      ]),
    );
  }
}

class _TripPlanSummary extends StatelessWidget {
  final Map<String, dynamic> plan;
  const _TripPlanSummary({required this.plan});

  @override
  Widget build(BuildContext context) {
    final verdict = plan['verdict']?.toString() ?? 'UNVERIFIED';
    final timeline = plan['timeline'] as List<dynamic>? ?? const <dynamic>[];
    final alerts = plan['alerts'] as List<dynamic>? ?? const <dynamic>[];
    final coverage = plan['coverage'] as Map? ?? const <dynamic, dynamic>{};
    final target = plan['targets'] as Map? ?? const <dynamic, dynamic>{};
    final navigation = plan['offline_navigation'] as Map?;
    final engine = plan['decision_engine'] as Map? ?? const <dynamic, dynamic>{};
    final travel = plan['travel_assessment'] as Map? ?? const <dynamic, dynamic>{};
    final fuel = plan['fuel_assessment'] as Map? ?? const <dynamic, dynamic>{};
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: OrcaTheme.surfaceElevated, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('Saved offline · $verdict', style: OrcaType.metricLabel.copyWith(fontWeight: FontWeight.w800))),
          OrcaInfoPill(icon: Icons.schedule, label: '${timeline.length} hours'),
        ]),
        const SizedBox(height: 7),
        Text(
          engine['name']?.toString() ?? 'ORCA Deterministic Offline Safety Engine',
          style: OrcaType.caption.copyWith(fontWeight: FontWeight.w800, color: OrcaTheme.accentDark),
        ),
        Text('Rule-based decision support—not a catch/storm probability ML model.', style: OrcaType.caption.copyWith(fontSize: 10.5)),
        const SizedBox(height: 7),
        Text('Coverage ${(100 * ((coverage['ratio'] as num?)?.toDouble() ?? 0)).toStringAsFixed(0)}% · ${alerts.length} safety alert${alerts.length == 1 ? '' : 's'}', style: OrcaType.body.copyWith(fontSize: 12)),
        const SizedBox(height: 5),
        Text(
          navigation == null
              ? 'Offline route not bundled—set both departure and destination.'
              : 'Offline route ${(navigation['distance_km'] as num?)?.toStringAsFixed(1) ?? '?'} km · GPS projection enabled · regulatory clearance ${navigation['regulatory_verified'] == true ? 'verified' : 'unverified'}',
          style: OrcaType.caption.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text('Travel: ${travel['status'] ?? 'UNVERIFIED'}${travel['direct_round_trip_hours'] == null ? '' : ' · return ${travel['direct_round_trip_hours']} h'}', style: OrcaType.caption),
        const SizedBox(height: 5),
        Text('Fuel: ${fuel['status'] ?? 'UNVERIFIED'}${fuel['estimated_direct_round_trip_liters'] == null ? '' : ' · direct return ${fuel['estimated_direct_round_trip_liters']} L'}', style: OrcaType.caption),
        const SizedBox(height: 5),
        Text(plan['return_decision'] is Map ? ((plan['return_decision'] as Map)['reason']?.toString() ?? '') : '', style: OrcaType.caption),
        const SizedBox(height: 5),
        Text(target['reason']?.toString() ?? '', style: OrcaType.caption),
        const SizedBox(height: 7),
        Text('Package ID ${plan['trip_id'] ?? 'unknown'} · SHA-256 verified ${plan['package_sha256']?.toString().substring(0, 12) ?? 'unavailable'}…', style: OrcaType.caption.copyWith(fontSize: 9.5)),
      ]),
    );
  }
}

class _TimeContractNote extends StatelessWidget {
  const _TimeContractNote();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: OrcaTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 16, color: OrcaTheme.accentDark),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Offline trip packages use downloaded 7-day Open-Meteo model timelines. They are forecast decision support—not live conditions, an official GRIB/ENC carriage product, or a promise of fish catch. Re-check immediately before departure.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  height: 1.45,
                  color: OrcaTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
}

class _RouteEmpty extends StatelessWidget {
  const _RouteEmpty();

  @override
  Widget build(BuildContext context) => const OrcaUnavailable(
        icon: Icons.route_outlined,
        title: 'No route checked yet',
        message: 'Enter both coordinates and run the check. ORCA reports the sampled marine conditions and the land-verification state of this exact response — nothing is prefilled or assumed.',
      );
}

class _RouteLoading extends StatelessWidget {
  const _RouteLoading();

  @override
  Widget build(BuildContext context) => OrcaCard(
        child: Row(
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: OrcaTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sampling marine inputs along the leg and verifying land clearance…',
                style: OrcaType.body.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
}
