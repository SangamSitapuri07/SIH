import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../dto/layer_dto.dart';
import '../dto/zone_dto.dart';

/// Remote datasource for Map endpoints (/api/v1/zone, /api/v1/layers).
class MapRemoteDataSource {
  final Dio _dio;

  MapRemoteDataSource(this._dio);

  /// Probes single spot snapshot at given lat/lon.
  Future<ZoneDto> getZoneSnapshot({
    required double lat,
    required double lon,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiPaths.zone,
      queryParameters: <String, dynamic>{
        'lat': lat,
        'lon': lon,
      },
    );

    if (response.data == null) {
      throw Exception('Empty response received for zone probe');
    }

    return ZoneDto.fromJson(response.data!);
  }

  /// Fetches available map layers catalog.
  Future<List<LayerDto>> getLayers() async {
    final response = await _dio.get<List<dynamic>>(ApiPaths.layers);
    if (response.data == null) {
      return <LayerDto>[];
    }
    return response.data!
        .map((e) => LayerDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
