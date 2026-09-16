import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/cache_service.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/dio_provider.dart';
import 'offline_navigation_provider.dart';

class TripPlanInput {
  final double areaLat;
  final double areaLon;
  final String? tripName;
  final String? vesselName;
  final String? shoreContact;
  final double? departureLat;
  final double? departureLon;
  final DateTime? departureAt;
  final int durationDays;
  final double radiusKm;
  final List<String> targetFish;
  final int crewSize;
  final double capacityKg;
  final double fuelLiters;
  final double fuelBurnLph;
  final double cruiseSpeedKn;
  final double maxWaveM;
  final double maxWindKn;
  final double maxGustKn;
  final String experienceLevel;

  const TripPlanInput({
    required this.areaLat, required this.areaLon,
    this.tripName, this.vesselName, this.shoreContact,
    this.departureLat, this.departureLon, this.departureAt,
    this.durationDays = 3, this.radiusKm = 75,
    this.targetFish = const <String>[], this.crewSize = 4,
    this.capacityKg = 500, this.fuelLiters = 200,
    this.fuelBurnLph = 0, this.cruiseSpeedKn = 8,
    this.maxWaveM = 2.5, this.maxWindKn = 20,
    this.maxGustKn = 34, this.experienceLevel = 'unspecified',
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'area_lat': areaLat, 'area_lon': areaLon,
    'trip_name': tripName, 'vessel_name': vesselName,
    'shore_contact': shoreContact,
    'departure_lat': departureLat, 'departure_lon': departureLon,
    'departure_at': departureAt?.toUtc().toIso8601String(),
    'duration_days': durationDays, 'area_radius_km': radiusKm,
    'target_fish': targetFish, 'crew_size': crewSize,
    'boat_capacity_kg': capacityKg, 'fuel_liters': fuelLiters,
    'fuel_burn_lph': fuelBurnLph, 'fuel_reserve_percent': 30,
    'cruise_speed_kn': cruiseSpeedKn, 'max_wave_m': maxWaveM,
    'max_wind_kn': maxWindKn, 'max_gust_kn': maxGustKn,
    'experience_level': experienceLevel,
  };
}

class TripPlanNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  final Ref _ref;
  final Dio _dio;
  final CacheService _cache;
  static const String _cacheKey = 'trip_plan.latest';

  TripPlanNotifier(this._ref, this._dio, this._cache)
      : super(const AsyncValue.data(null)) {
    final cached = _cache.get(_cacheKey)?.data;
    if (cached != null) {
      state = _hasValidChecksum(cached)
          ? AsyncValue.data(cached)
          : AsyncValue.error(
              'Saved trip package failed its SHA-256 integrity check. Rebuild it online.',
              StackTrace.current,
            );
    }
  }

  static dynamic _canonicalize(dynamic value) {
    if (value is Map<String, dynamic>) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List<dynamic>) return value.map(_canonicalize).toList();
    return value;
  }

  static bool _hasValidChecksum(Map<String, dynamic> plan) {
    final expected = plan['package_sha256']?.toString();
    if (expected == null || expected.length != 64) return false;
    final unsigned = Map<String, dynamic>.from(plan)..remove('package_sha256');
    final canonical = jsonEncode(_canonicalize(unsigned));
    return sha256.convert(utf8.encode(canonical)).toString() == expected.toLowerCase();
  }

  Future<void> generate(TripPlanInput input) async {
    state = const AsyncValue.loading();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiPaths.tripPlan,
        data: input.toJson(),
        options: Options(
          receiveTimeout: AppConfig.advisoryRequestTimeout,
          sendTimeout: AppConfig.advisoryRequestTimeout,
        ),
      );
      final plan = response.data;
      if (plan == null) throw const FormatException('Empty trip-plan response');
      if (!_hasValidChecksum(plan)) {
        throw const FormatException('Trip package SHA-256 integrity check failed');
      }
      await _cache.put(_cacheKey, plan, ttl: const Duration(days: 7));
      await _ref.read(offlineNavigationProvider.notifier).saveTripPackage(plan);
      state = AsyncValue.data(plan);
    } catch (error, stack) {
      final cached = _cache.get(_cacheKey)?.data;
      state = cached != null && _hasValidChecksum(cached)
          ? AsyncValue.data(cached)
          : AsyncValue.error(error, stack);
    }
  }
}

final tripPlanProvider = StateNotifierProvider<TripPlanNotifier,
    AsyncValue<Map<String, dynamic>?>>((ref) {
  return TripPlanNotifier(ref, ref.watch(dioProvider), ref.watch(cacheServiceProvider));
});
