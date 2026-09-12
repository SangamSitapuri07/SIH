import 'package:dio/dio.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/agent_reasoning.dart';
import '../../domain/repositories/agents_repo.dart';
import '../datasources/agents_remote.dart';
import '../dto/reason_dto.dart';

/// Implementation of AgentsRepository with cache fallback (§10).
class AgentsRepositoryImpl implements AgentsRepository {
  final AgentsRemoteDataSource _remoteDataSource;
  final CacheService _cacheService;

  AgentsRepositoryImpl({
    required AgentsRemoteDataSource remoteDataSource,
    required CacheService cacheService,
  })  : _remoteDataSource = remoteDataSource,
        _cacheService = cacheService;

  @override
  Future<Result<AgentReasoningResult>> getReasoning({
    required double lat,
    required double lon,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'reason_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
    final cached = _cacheService.get(cacheKey);

    if (!forceRefresh && cached != null && !cached.isExpired) {
      final dto = ReasonDto.fromJson(cached.data);
      return Result.ok(dto.toEntity(cached.staleness));
    }

    try {
      final dto = await _remoteDataSource.runReasoning(lat: lat, lon: lon);

      final jsonMap = <String, dynamic>{
        'overall_risk': dto.overallRisk,
        'verdict': dto.verdict,
        'data_coverage': dto.dataCoverage,
        'agents': dto.agentsList,
        'orchestrator_synthesis': dto.synthesisJson,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await _cacheService.put(cacheKey, jsonMap);

      final staleness = StalenessInfo.fromDateTime(DateTime.now());
      return Result.ok(dto.toEntity(staleness));
    } on DioException catch (dioErr) {
      if (cached != null) {
        final dto = ReasonDto.fromJson(cached.data);
        return Result.ok(dto.toEntity(cached.staleness));
      }
      if (dioErr.type == DioExceptionType.connectionTimeout) {
        return const Result.err(AppFailure.timeout());
      }
      if (dioErr.type == DioExceptionType.receiveTimeout ||
          dioErr.type == DioExceptionType.sendTimeout) {
        return const Result.err(AppFailure.timeout());
      }
      if (dioErr.type == DioExceptionType.connectionError) {
        return const Result.err(AppFailure.serverDown());
      }
      final detail = dioErr.response?.data is Map<String, dynamic>
          ? (dioErr.response!.data['detail'] as String?)
          : null;
      return Result.err(AppFailure.unknown(
        detail ?? 'ORCA Box returned HTTP ${dioErr.response?.statusCode ?? 'an error'} for agent reasoning.',
      ));
    } catch (e) {
      if (cached != null) {
        final dto = ReasonDto.fromJson(cached.data);
        return Result.ok(dto.toEntity(cached.staleness));
      }
      return Result.err(AppFailure.unknown(e.toString()));
    }
  }
}
