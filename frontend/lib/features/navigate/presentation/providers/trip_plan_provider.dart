import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/cache_service.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/dio_provider.dart';

class TripPlanInput {
  final double areaLat;
  final double areaLon;
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

  const TripPlanInput({
    required this.areaLat, required this.areaLon, this.departureAt,
    this.durationDays = 3, this.radiusKm = 75,
    this.targetFish = const <String>[], this.crewSize = 4,
    this.capacityKg = 500, this.fuelLiters = 200,
    this.fuelBurnLph = 0, this.cruiseSpeedKn = 8,
    this.maxWaveM = 2.5, this.maxWindKn = 20,
    this.maxGustKn = 34,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'area_lat': areaLat, 'area_lon': areaLon,
    'departure_at': departureAt?.toUtc().toIso8601String(),
    'duration_days': durationDays, 'area_radius_km': radiusKm,
    'target_fish': targetFish, 'crew_size': crewSize,
    'boat_capacity_kg': capacityKg, 'fuel_liters': fuelLiters,
    'fuel_burn_lph': fuelBurnLph, 'fuel_reserve_percent': 30,
    'cruise_speed_kn': cruiseSpeedKn, 'max_wave_m': maxWaveM,
    'max_wind_kn': maxWindKn, 'max_gust_kn': maxGustKn,
    'experience_level': 'unspecified',
  };
}

class TripPlanNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>?>> {
  final Dio _dio;
  final CacheService _cache;
  static const String _cacheKey = 'trip_plan.latest';

  TripPlanNotifier(this._dio, this._cache)
      : super(AsyncValue.data(_cache.get(_cacheKey)?.data));

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
      await _cache.put(_cacheKey, plan, ttl: const Duration(days: 7));
      state = AsyncValue.data(plan);
    } catch (error, stack) {
      final cached = _cache.get(_cacheKey)?.data;
      state = cached != null ? AsyncValue.data(cached) : AsyncValue.error(error, stack);
    }
  }
}

final tripPlanProvider = StateNotifierProvider<TripPlanNotifier,
    AsyncValue<Map<String, dynamic>?>>((ref) {
  return TripPlanNotifier(ref.watch(dioProvider), ref.watch(cacheServiceProvider));
});
