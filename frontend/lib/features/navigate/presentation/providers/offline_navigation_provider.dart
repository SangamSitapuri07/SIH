import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/cache/cache_service.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../domain/entities/route_check.dart';

/// Device-resident route evidence used when the ORCA Box/internet is absent.
/// Geometry remains useful after weather expiry; cached weather never becomes
/// "live" merely because GPS tracking is active.
class OfflineRoutePackage {
  final List<List<double>> geometry;
  final double distanceKm;
  final String boundaryReason;
  final String advisoryLevel;
  final List<Map<String, dynamic>> weatherPoints;
  final List<String> sources;
  final DateTime savedAt;
  final DateTime weatherValidUntil;

  const OfflineRoutePackage({
    required this.geometry,
    required this.distanceKm,
    required this.boundaryReason,
    required this.advisoryLevel,
    required this.weatherPoints,
    required this.sources,
    required this.savedAt,
    required this.weatherValidUntil,
  });

  bool get weatherExpired => DateTime.now().toUtc().isAfter(weatherValidUntil);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema_version': '1.0',
        'geometry': geometry,
        'distance_km': distanceKm,
        'boundary_reason': boundaryReason,
        'advisory_level': advisoryLevel,
        'weather_points': weatherPoints,
        'sources': sources,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'weather_valid_until': weatherValidUntil.toUtc().toIso8601String(),
      };

  factory OfflineRoutePackage.fromJson(Map<String, dynamic> json) {
    final rawGeometry = json['geometry'] as List<dynamic>? ?? const <dynamic>[];
    return OfflineRoutePackage(
      geometry: rawGeometry
          .whereType<List<dynamic>>()
          .map((point) => point.map((value) => (value as num).toDouble()).toList())
          .where((point) => point.length >= 2)
          .toList(),
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      boundaryReason: json['boundary_reason']?.toString() ?? 'Boundary evidence unavailable.',
      advisoryLevel: json['advisory_level']?.toString() ?? 'UNVERIFIED',
      weatherPoints: (json['weather_points'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
      sources: (json['sources'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(),
      savedAt: DateTime.parse(json['saved_at'] as String).toUtc(),
      weatherValidUntil: DateTime.parse(json['weather_valid_until'] as String).toUtc(),
    );
  }
}

class OfflineNavigationProgress {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final DateTime observedAt;
  final double completedKm;
  final double remainingKm;
  final double offRouteKm;
  final double distanceToDepartureKm;
  final double bearingToDestination;

  const OfflineNavigationProgress({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.observedAt,
    required this.completedKm,
    required this.remainingKm,
    required this.offRouteKm,
    required this.distanceToDepartureKm,
    required this.bearingToDestination,
  });

  bool get isOffRoute => offRouteKm > 2.0;

  /// Projects a GPS fix onto each saved polyline segment using a local
  /// equirectangular plane, then chooses the nearest projection. This is fully
  /// deterministic and requires no network or remote model.
  static OfflineNavigationProgress calculate({
    required double latitude,
    required double longitude,
    required double accuracyM,
    required DateTime observedAt,
    required List<List<double>> geometry,
  }) {
    if (geometry.length < 2) {
      throw const FormatException('Saved route geometry is incomplete.');
    }
    final cumulative = <double>[0];
    for (var i = 1; i < geometry.length; i++) {
      cumulative.add(cumulative.last + GeoUtils.distanceKm(
        geometry[i - 1][0], geometry[i - 1][1], geometry[i][0], geometry[i][1],
      ));
    }

    var nearestKm = double.infinity;
    var completedKm = 0.0;
    for (var i = 0; i < geometry.length - 1; i++) {
      final a = geometry[i], b = geometry[i + 1];
      final referenceLat = (a[0] + b[0] + latitude) / 3;
      final double lonScale = math
          .cos(referenceLat * math.pi / 180)
          .abs()
          .clamp(0.01, 1.0)
          .toDouble();
      final ax = (a[1] - longitude) * 111.32 * lonScale;
      final ay = (a[0] - latitude) * 110.57;
      final bx = (b[1] - longitude) * 111.32 * lonScale;
      final by = (b[0] - latitude) * 110.57;
      final dx = bx - ax, dy = by - ay;
      final denominator = dx * dx + dy * dy;
      final fraction = denominator == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / denominator).clamp(0.0, 1.0).toDouble();
      final projectedX = ax + fraction * dx;
      final projectedY = ay + fraction * dy;
      final distance = math.sqrt(projectedX * projectedX + projectedY * projectedY);
      if (distance < nearestKm) {
        nearestKm = distance;
        completedKm = cumulative[i] +
            fraction * GeoUtils.distanceKm(a[0], a[1], b[0], b[1]);
      }
    }

    final destination = geometry.last;
    final departure = geometry.first;
    return OfflineNavigationProgress(
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      observedAt: observedAt.toUtc(),
      completedKm: completedKm,
      remainingKm: math.max(0.0, cumulative.last - completedKm),
      offRouteKm: nearestKm,
      distanceToDepartureKm: GeoUtils.distanceKm(
        latitude, longitude, departure[0], departure[1],
      ),
      bearingToDestination: GeoUtils.bearingDegrees(
        latitude, longitude, destination[0], destination[1],
      ),
    );
  }
}

class OfflineNavigationState {
  final OfflineRoutePackage? package;
  final OfflineNavigationProgress? progress;
  final bool tracking;
  final String? error;

  const OfflineNavigationState({this.package, this.progress, this.tracking = false, this.error});

  OfflineNavigationState copyWith({
    OfflineRoutePackage? package,
    OfflineNavigationProgress? progress,
    bool? tracking,
    String? error,
    bool clearError = false,
  }) => OfflineNavigationState(
        package: package ?? this.package,
        progress: progress ?? this.progress,
        tracking: tracking ?? this.tracking,
        error: clearError ? null : error ?? this.error,
      );
}

class OfflineNavigationNotifier extends StateNotifier<OfflineNavigationState> {
  static const _cacheKey = 'navigation.offline_route';
  final CacheService _cache;
  StreamSubscription<Position>? _positionSubscription;

  OfflineNavigationNotifier(this._cache) : super(const OfflineNavigationState()) {
    final cached = _cache.get(_cacheKey)?.data;
    if (cached != null) {
      try {
        state = OfflineNavigationState(package: OfflineRoutePackage.fromJson(cached));
      } catch (_) {
        state = const OfflineNavigationState(error: 'Saved offline route is unreadable. Rebuild it online.');
      }
    }
  }

  Future<void> saveRoute(RouteCheckEntity check, RouteAdvisoryEntity advisory) async {
    if (check.ok != true || check.legs.length < 2) return;
    final now = DateTime.now().toUtc();
    final package = OfflineRoutePackage(
      geometry: check.legs.map((point) => List<double>.from(point)).toList(),
      distanceKm: check.distanceKm ?? 0,
      boundaryReason: check.reason,
      advisoryLevel: advisory.level,
      weatherPoints: advisory.points.map((point) => <String, dynamic>{
        'sail_km': point.sailKm,
        'lat': point.lat,
        'lon': point.lon,
        'wave_m': point.waveM,
        'wind_kn': point.windKn,
        'gust_kn': point.gustKn,
        'state': point.state,
        'why': point.why,
      }).toList(),
      sources: <String>{...check.sources, ...advisory.sources}.toList(),
      savedAt: now,
      // Route-advisory currently contains current model conditions, not an
      // ETA-indexed route forecast. Expire this evidence conservatively.
      weatherValidUntil: now.add(const Duration(hours: 3)),
    );
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _cache.put(_cacheKey, package.toJson(), ttl: const Duration(days: 30));
    state = OfflineNavigationState(package: package);
  }

  Future<void> saveTripPackage(Map<String, dynamic> plan) async {
    final navigation = plan['offline_navigation'];
    if (navigation is! Map || navigation['ok'] != true) return;
    final geometry = (navigation['geometry'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<List<dynamic>>()
        .map((point) => point.map((value) => (value as num).toDouble()).toList())
        .where((point) => point.length >= 2)
        .toList();
    if (geometry.length < 2) return;
    final now = DateTime.now().toUtc();
    final forecastExpiry = DateTime.tryParse(plan['forecast_valid_until']?.toString() ?? '')?.toUtc();
    final package = OfflineRoutePackage(
      geometry: geometry,
      distanceKm: (navigation['distance_km'] as num?)?.toDouble() ?? 0,
      boundaryReason: navigation['boundary_reason']?.toString() ?? 'Boundary evidence unavailable.',
      advisoryLevel: plan['verdict']?.toString() ?? 'UNVERIFIED',
      weatherPoints: const <Map<String, dynamic>>[],
      sources: (plan['sources'] as List<dynamic>? ?? const <dynamic>[])
          .map((source) => source.toString())
          .toList(),
      savedAt: now,
      weatherValidUntil: forecastExpiry ?? now,
    );
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _cache.put(_cacheKey, package.toJson(), ttl: const Duration(days: 30));
    state = OfflineNavigationState(package: package);
  }

  Future<void> startTracking() async {
    final package = state.package;
    if (package == null || package.geometry.length < 2) {
      state = state.copyWith(error: 'Check and save a route online before starting offline navigation.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      state = state.copyWith(error: 'Device location is disabled. Turn on GPS; internet is not required.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      state = state.copyWith(error: 'Location permission is required for offline navigation.');
      return;
    }

    await _positionSubscription?.cancel();
    state = state.copyWith(tracking: true, clearError: true);
    const settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 50);
    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        try {
          final progress = OfflineNavigationProgress.calculate(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracyM: position.accuracy,
            observedAt: position.timestamp,
            geometry: package.geometry,
          );
          state = state.copyWith(progress: progress, tracking: true, clearError: true);
        } catch (error) {
          state = state.copyWith(error: 'GPS progress could not be calculated: $error', tracking: false);
        }
      },
      onError: (Object error) {
        state = state.copyWith(error: 'GPS stream unavailable: $error', tracking: false);
      },
    );
  }

  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    state = state.copyWith(tracking: false, clearError: true);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}

final offlineNavigationProvider = StateNotifierProvider<OfflineNavigationNotifier, OfflineNavigationState>((ref) {
  return OfflineNavigationNotifier(ref.watch(cacheServiceProvider));
});
