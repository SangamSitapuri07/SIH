import 'package:dio/dio.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/utils/date_formatter.dart';
import '../dto/zone_dto.dart';


DateTime? _parseTimestamp(dynamic value) {
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
  return DateFormatter.parseIso(value);
}

/// Exact field sample returned by ORCA's real Open-Meteo map grid contract.
class MapGridPointDto {
  final double lat;
  final double lon;
  final String status;
  final double? windKn;
  final double? windGustKn;
  final double? windDirectionDeg;
  final double? waveHeightM;
  final double? seaTempC;

  const MapGridPointDto({
    required this.lat,
    required this.lon,
    required this.status,
    this.windKn,
    this.windGustKn,
    this.windDirectionDeg,
    this.waveHeightM,
    this.seaTempC,
  });

  factory MapGridPointDto.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw const FormatException('A map field sample has no coordinates.');
    }
    return MapGridPointDto(
        lat: lat,
        lon: lon,
        status: json['status']?.toString() ?? 'unavailable',
        windKn: (json['wind_kn'] as num?)?.toDouble(),
        windGustKn: (json['wind_gust_kn'] as num?)?.toDouble(),
        windDirectionDeg: (json['wind_direction_deg'] as num?)?.toDouble(),
        waveHeightM: (json['wave_h'] as num?)?.toDouble(),
        seaTempC: (json['sst_c'] as num?)?.toDouble(),
      );
  }
}

class PfzResponseDto {
  final String status;
  final String? source;
  final DateTime? fetchedAt;
  final List<Map<String, dynamic>> features;

  const PfzResponseDto({required this.status, this.source, this.fetchedAt, required this.features});

  factory PfzResponseDto.fromJson(Map<String, dynamic> json) => PfzResponseDto(
        status: json['status']?.toString() ?? 'unavailable',
        source: json['source']?.toString(),
        fetchedAt: _parseTimestamp(json['fetched_at']),
        features: (json['features'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
      );
}

class MapGridDto {
  final String state;
  final String? validTime;
  final String? resolution;
  final DateTime? fetchedAt;
  final List<String> sources;
  final List<MapGridPointDto> points;

  const MapGridDto({
    required this.state,
    this.validTime,
    this.resolution,
    this.fetchedAt,
    required this.sources,
    required this.points,
  });

  factory MapGridDto.fromJson(Map<String, dynamic> json) => MapGridDto(
        state: json['state']?.toString() ?? 'UNAVAILABLE',
        validTime: json['valid_time']?.toString(),
        resolution: json['resolution']?.toString(),
        fetchedAt: _parseTimestamp(json['fetched_at']),
        sources: (json['sources'] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList(),
        points: (json['points'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MapGridPointDto.fromJson)
            .toList(),
      );
}

/// Remote data source for real ORCA map endpoints.
class MapRemoteDataSource {
  final Dio _dio;

  MapRemoteDataSource(this._dio);

  Future<ZoneDto> getZoneSnapshot({required double lat, required double lon}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiPaths.zone,
      queryParameters: {'lat': lat, 'lon': lon},
    );
    if (response.data == null) {
      throw const FormatException('ORCA returned an empty marine point response.');
    }
    return ZoneDto.fromJson(response.data!);
  }

  Future<List<LayerDto>> getLayers({required double lat, required double lon}) async {
    final response = await _dio.get<dynamic>(
      ApiPaths.layers,
      queryParameters: {'lat': lat, 'lon': lon},
    );
    final data = response.data;
    final raw = data is Map<String, dynamic>
        ? data['layers'] as List<dynamic>? ?? const []
        : data as List<dynamic>? ?? const [];
    return raw.whereType<Map<String, dynamic>>().map(LayerDto.fromJson).toList();
  }

  Future<PfzResponseDto> getPfz() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/pfz');
    if (response.data == null) {
      throw const FormatException('ORCA returned an empty PFZ response.');
    }
    return PfzResponseDto.fromJson(response.data!);
  }

  Future<MapGridDto> getGrid({
    required double lat,
    required double lon,
    required double span,
    String? validTime,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiPaths.grid,
      queryParameters: {
        'lat': lat,
        'lon': lon,
        'span': span,
        if (validTime != null) 'valid_time': validTime,
      },
    );
    if (response.data == null) {
      throw const FormatException('ORCA returned an empty map field response.');
    }
    return MapGridDto.fromJson(response.data!);
  }
}
