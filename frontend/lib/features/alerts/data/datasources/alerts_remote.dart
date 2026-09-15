import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../dto/alert_dto.dart';

/// Remote source for verified `/api/v1/alerts` provider alerts.
class AlertsRemoteDataSource {
  final Dio _dio;
  AlertsRemoteDataSource(this._dio);

  Future<List<AlertDto>> getActiveAlerts() async {
    final response = await _dio.get<dynamic>(ApiPaths.alerts);
    final data = response.data;
    if (data == null) throw const FormatException('Empty alerts response');
    final raw = data is Map<String, dynamic>
        ? data['alerts'] as List<dynamic>? ?? const []
        : data is List<dynamic> ? data : const [];
    return raw.whereType<Map<String, dynamic>>().map(AlertDto.fromJson).toList();
  }
}
