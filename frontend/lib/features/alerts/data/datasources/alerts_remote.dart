import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../dto/alert_dto.dart';

/// Remote datasource for Alerts endpoints (/api/v1/alerts, /api/v1/alerts/simulate).
class AlertsRemoteDataSource {
  final Dio _dio;

  AlertsRemoteDataSource(this._dio);

  /// Fetches active alerts.
  Future<List<AlertDto>> getActiveAlerts() async {
    final response = await _dio.get<dynamic>(ApiPaths.alerts);
    if (response.data == null) {
      return <AlertDto>[];
    }
    final rawList = response.data is Map<String, dynamic>
        ? (response.data['alerts'] as List<dynamic>? ?? <dynamic>[])
        : response.data as List<dynamic>;
    return rawList
        .map((e) => AlertDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Triggers demo alert simulation (§8, demo builds only).
  Future<AlertDto> simulateAlert() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiPaths.alertsSimulate);
    if (response.data == null) {
      throw Exception('Simulation returned empty');
    }
    return AlertDto.fromJson(response.data!);
  }
}
