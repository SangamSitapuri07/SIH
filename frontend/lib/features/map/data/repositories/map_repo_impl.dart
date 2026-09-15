import 'package:dio/dio.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/zone_snapshot.dart';
import '../../domain/repositories/map_repo.dart';
import '../datasources/map_remote.dart';
import '../dto/zone_dto.dart';

/// Cache-aware implementation for point probes. It never creates substitute
/// marine values: a cached response is explicitly marked stale by its cache
/// metadata and a response without required coordinates/timestamp is rejected.
class MapRepositoryImpl implements MapRepository {
  final MapRemoteDataSource _remoteDataSource;
  final CacheService _cacheService;

  MapRepositoryImpl({
    required MapRemoteDataSource remoteDataSource,
    required CacheService cacheService,
  })  : _remoteDataSource = remoteDataSource,
        _cacheService = cacheService;

  @override
  Future<Result<ZoneSnapshot>> probeZone({required double lat, required double lon}) async {
    final cacheKey = 'zone_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
    final cached = _cacheService.get(cacheKey);
    try {
      final dto = await _remoteDataSource.getZoneSnapshot(lat: lat, lon: lon);
      await _cacheService.put(cacheKey, {
        'lat': dto.lat,
        'lon': dto.lon,
        'zone_name': dto.zoneName,
        'offshore_dist_km': dto.offshoreDistKm,
        'depth_m': dto.depthM,
        'wave_height_m': dto.waveHeightM,
        'swell_period_s': dto.swellPeriodS,
        'wind_speed_kn': dto.windSpeedKn,
        'wind_direction': dto.windDirection,
        'sea_temp_c': dto.seaTempC,
        'current_speed_kn': dto.currentSpeedKn,
        'current_direction': dto.currentDirection,
        'chlorophyll_mg_m3': dto.chlorophyllMgM3,
        'fishing_effort_hours': dto.fishingEffortHours,
        'nearest_harbour': dto.nearestHarbour,
        'nearest_harbour_dist_km': dto.nearestHarbourDistKm,
        'sources': dto.sources,
        'sources_failed': dto.sourcesFailed,
        'timestamp': dto.timestamp!.toIso8601String(),
        'cached': dto.isCached,
      });
      return Result.ok(dto.toEntity(StalenessInfo.fromDateTime(dto.timestamp!, isCached: dto.isCached)));
    } on DioException catch (error) {
      if (cached != null) {
        try {
          return Result.ok(ZoneDto.fromJson(cached.data).toEntity(cached.staleness));
        } catch (_) {
          // An old/corrupt cache cannot be presented as verified information.
        }
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return const Result.err(AppFailure.timeout());
      }
      return const Result.err(AppFailure.serverDown());
    } catch (error) {
      if (cached != null) {
        try {
          return Result.ok(ZoneDto.fromJson(cached.data).toEntity(cached.staleness));
        } catch (_) {}
      }
      return Result.err(AppFailure.unknown(error.toString()));
    }
  }

  @override
  Future<Result<List<MapLayerEntity>>> getLayers() async {
    try {
      final layers = await _remoteDataSource.getLayers(
        lat: AppConfig.defaultLat,
        lon: AppConfig.defaultLon,
      );
      return Result.ok(layers.map((layer) => layer.toEntity()).toList());
    } catch (error) {
      return Result.err(AppFailure.unknown(error.toString()));
    }
  }
}
