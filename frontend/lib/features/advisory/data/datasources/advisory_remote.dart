import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../dto/advisory_dto.dart';

/// Remote datasource communicating with /api/v1/advisory (§4).
class AdvisoryRemoteDataSource {
  final Dio _dio;

  AdvisoryRemoteDataSource(this._dio);

  /// Fetches advisory snapshot for given lat/lon.
  Future<AdvisoryDto> getAdvisory({
    required double lat,
    required double lon,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiPaths.advisory,
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
      },
      options: Options(
        // Connecting to a reachable ORCA Box should fail fast; only the
        // response window is long because advisory generation can take up to
        // ~2 minutes when all upstream marine sources respond slowly.
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.advisoryRequestTimeout,
        sendTimeout: AppConfig.advisoryRequestTimeout,
      ),
    );

    if (response.data == null) {
      throw Exception('Empty response received for advisory');
    }

    return AdvisoryDto.fromJson(response.data!);
  }
}
