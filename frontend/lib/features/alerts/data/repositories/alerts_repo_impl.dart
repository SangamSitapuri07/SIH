import 'package:dio/dio.dart';
import '../../../../core/result/app_failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/alert_item.dart';
import '../../domain/repositories/alerts_repo.dart';
import '../datasources/alerts_remote.dart';

/// Implementation of AlertsRepository (§10).
class AlertsRepositoryImpl implements AlertsRepository {
  final AlertsRemoteDataSource _remoteDataSource;

  AlertsRepositoryImpl({required AlertsRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  @override
  Future<Result<List<AlertItem>>> getActiveAlerts({bool forceRefresh = false}) async {
    try {
      final dtos = await _remoteDataSource.getActiveAlerts();
      return Result.ok(dtos.map((d) => d.toEntity()).toList());
    } on DioException catch (dioErr) {
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
