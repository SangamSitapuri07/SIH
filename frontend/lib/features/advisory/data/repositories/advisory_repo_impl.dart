import 'package:dio/dio.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/advisory.dart';
import '../../domain/repositories/advisory_repo.dart';
import '../datasources/advisory_remote.dart';
import '../dto/advisory_dto.dart';

/// Implementation of AdvisoryRepository with cache-first and staleness guarantees (§10, §13).
///
/// Read pattern is stale-while-revalidate: the freshest cached advisory is
/// always available instantly via [getAdvisoryCached] (any age), while
/// [getAdvisory] refreshes from the ORCA Box and falls back to cache on
/// failure so the UI never shows a spinner when cached data exists.
class AdvisoryRepositoryImpl implements AdvisoryRepository {
  final AdvisoryRemoteDataSource _remoteDataSource;
  final CacheService _cacheService;

  AdvisoryRepositoryImpl({
    required AdvisoryRemoteDataSource remoteDataSource,
    required CacheService cacheService,
  })  : _remoteDataSource = remoteDataSource,
        _cacheService = cacheService;

  @override
  Future<Result<AdvisoryEntity>> getAdvisory({
    required double lat,
    required double lon,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _cacheKey(lat, lon);
    final cached = _cacheService.get(cacheKey);

    // 1. If not forcing refresh and cache is fresh, emit cached instantly.
    //    A refresh is scheduled in the background by the provider layer.
    if (!forceRefresh && cached != null && !cached.isExpired) {
      final dto = AdvisoryDto.fromJson(cached.data);
      return Result.ok(dto.toEntity(cached.staleness));
    }

    // 2. Fetch live data.
    try {
      final dto = await _remoteDataSource.getAdvisory(lat: lat, lon: lon);

      // Write-through to cache.
      await _cacheService.put(cacheKey, _dtoToCacheMap(dto));

      final sourceTime = dto.timestamp;
      if (sourceTime == null) {
        return const Result.err(AppFailure.unknown('Advisory source timestamp unavailable.'));
      }
      return Result.ok(dto.toEntity(StalenessInfo.fromDateTime(sourceTime, isCached: dto.isCached)));
    } on DioException catch (dioErr) {
      // 3. Network error -> fall back to cache if present with honest staleness.
      if (cached != null) {
        final dto = AdvisoryDto.fromJson(cached.data);
        return Result.ok(dto.toEntity(cached.staleness));
      }

      if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout) {
        return const Result.err(AppFailure.timeout());
      }
      if (dioErr.type == DioExceptionType.connectionError) {
        return const Result.err(AppFailure.serverDown());
      }
      return Result.err(AppFailure.unknown(dioErr.message ?? 'Network error'));
    } catch (e) {
      if (cached != null) {
        final dto = AdvisoryDto.fromJson(cached.data);
        return Result.ok(dto.toEntity(cached.staleness));
      }
      return Result.err(AppFailure.unknown(e.toString()));
    }
  }

  @override
  Future<AdvisoryEntity?> getAdvisoryCached({
    required double lat,
    required double lon,
  }) async {
    final cached = _cacheService.get(_cacheKey(lat, lon));
    if (cached == null) return null;
    try {
      final dto = AdvisoryDto.fromJson(cached.data);
      return dto.toEntity(cached.staleness);
    } catch (_) {
      return null;
    }
  }

  String _cacheKey(double lat, double lon) =>
      'advisory_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';

  Map<String, dynamic> _dtoToCacheMap(AdvisoryDto dto) => <String, dynamic>{
        'verdict': dto.verdict,
        'color': dto.color,
        'headline': dto.headline,
        'headline_hi': dto.headlineHi,
        'plain_en': dto.plainEn,
        'plain_hi': dto.plainHi,
        'safe_window': dto.safeWindowJson,
        'variables': dto.variablesJson,
        'hourly_chart': dto.hourlyChartJson,
        'sources': dto.sources,
        'data_coverage': {
          'known': dto.knownSources,
          'total': dto.totalSources,
          'sources_failed': dto.sourcesFailed,
        },
        'timestamp': dto.timestamp?.toIso8601String(),
        'cached': dto.isCached,
      };
}
