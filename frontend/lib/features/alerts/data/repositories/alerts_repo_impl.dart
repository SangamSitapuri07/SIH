import 'package:dio/dio.dart';
import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../dto/alert_dto.dart';
import '../../domain/entities/alert_item.dart';
import '../../domain/repositories/alerts_repo.dart';
import '../datasources/alerts_remote.dart';

/// Implementation of AlertsRepository (§10).
class AlertsRepositoryImpl implements AlertsRepository {
  final AlertsRemoteDataSource _remoteDataSource;
  final CacheService _cacheService;

  AlertsRepositoryImpl({required AlertsRemoteDataSource remoteDataSource, required CacheService cacheService})
      : _remoteDataSource = remoteDataSource,
        _cacheService = cacheService;

  @override
  Future<Result<List<AlertItem>>> getActiveAlerts({bool forceRefresh = false}) async {
    try {
      final dtos = await _remoteDataSource.getActiveAlerts();
      await _cacheService.put('alerts_active', <String, dynamic>{
        'alerts': dtos.map((d) => <String, dynamic>{
          'id': d.id,
          'severity': d.severity,
          'title': d.title,
          'title_hi': d.titleHi,
          'message': d.message,
          'message_hi': d.messageHi,
          'source': d.source,
          'issued_at': d.issuedAt?.toIso8601String(),
          'expires_at': d.expiresAt?.toIso8601String(),
          'affected_area': d.affectedArea,
          'is_active': d.isActive,
        }).toList(),
      });
      return Result.ok(dtos.map((d) => d.toEntity()).toList());
    } on DioException catch (dioErr) {
      final cached = _cacheService.get('alerts_active');
      if (cached != null) {
        final raw = cached.data['alerts'] as List<dynamic>? ?? <dynamic>[];
        return Result.ok(raw.map((e) => AlertDto.fromJson(e as Map<String, dynamic>).toEntity()).toList());
      }
      if (dioErr.type == DioExceptionType.connectionTimeout) {
        return const Result.err(AppFailure.timeout());
      }
      return const Result.err(AppFailure.serverDown());
    } catch (e) {
      return Result.err(AppFailure.unknown(e.toString()));
    }
  }

  @override
  Future<Result<AlertItem>> simulateAlert() async {
    try {
      final dto = await _remoteDataSource.simulateAlert();
      return Result.ok(dto.toEntity());
    } catch (e) {
      return Result.err(AppFailure.unknown(e.toString()));
    }
  }
}
