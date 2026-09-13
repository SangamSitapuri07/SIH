import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../dto/reason_dto.dart';

/// Remote datasource for Agents Reasoning endpoint (/api/v1/reason).
class AgentsRemoteDataSource {
  final Dio _dio;

  AgentsRemoteDataSource(this._dio);

  /// Runs multi-agent reasoning over live observation at [lat], [lon].
  Future<ReasonDto> runReasoning({
    required double lat,
    required double lon,
  }) async {
    // The 11-agent pipeline (including LLM/analytical agents) can take well
    // over the default 15s client timeout, so use the long advisory timeout.
    final response = await _dio.get<Map<String, dynamic>>(
      ApiPaths.reason,
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
      },
      options: Options(
        receiveTimeout: AppConfig.advisoryRequestTimeout,
        sendTimeout: AppConfig.advisoryRequestTimeout,
      ),
    );


    if (response.data == null) {
      throw Exception('Empty response received from reasoner endpoint');
    }

    return ReasonDto.fromJson(response.data!);
  }
}
