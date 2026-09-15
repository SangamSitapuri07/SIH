import '../../../../core/cache/staleness.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../domain/entities/zone_snapshot.dart';

/// DTO for the real `/api/v1/zone` point-probe response.
class ZoneDto {
  final double? lat;
  final double? lon;
  final String? zoneName;
  final double? offshoreDistKm;
  final double? depthM;
  final double? waveHeightM;
  final double? swellPeriodS;
  final double? windSpeedKn;
  final String? windDirection;
  final double? seaTempC;
  final double? currentSpeedKn;
  final String? currentDirection;
  final double? chlorophyllMgM3;
  final double? fishingEffortHours;
  final String? nearestHarbour;
  final double? nearestHarbourDistKm;
  final List<String> sources;
  final List<String> sourcesFailed;
  final DateTime? timestamp;
  final bool isCached;

  const ZoneDto({
    this.lat,
    this.lon,
    this.zoneName,
    this.offshoreDistKm,
    this.depthM,
    this.waveHeightM,
    this.swellPeriodS,
    this.windSpeedKn,
    this.windDirection,
    this.seaTempC,
    this.currentSpeedKn,
    this.currentDirection,
    this.chlorophyllMgM3,
    this.fishingEffortHours,
    this.nearestHarbour,
    this.nearestHarbourDistKm,
    required this.sources,
    required this.sourcesFailed,
    this.timestamp,
    this.isCached = false,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  static String? _asString(dynamic value) => value?.toString();

  factory ZoneDto.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    final timestamp = _parseTimestamp(json['timestamp']);
    return ZoneDto(
      lat: lat,
      lon: lon,
      zoneName: json['zone_name']?.toString(),
      offshoreDistKm: (json['offshore_dist_km'] as num?)?.toDouble(),
      depthM: (json['depth_m'] as num?)?.toDouble(),
      waveHeightM: (json['wave_height_m'] as num?)?.toDouble(),
      swellPeriodS: (json['swell_period_s'] as num?)?.toDouble(),
      windSpeedKn: (json['wind_speed_kn'] as num?)?.toDouble(),
      windDirection: _asString(json['wind_direction']),
      seaTempC: (json['sea_temp_c'] as num?)?.toDouble(),
      currentSpeedKn: (json['current_speed_kn'] as num?)?.toDouble(),
      currentDirection: _asString(json['current_direction']),
      chlorophyllMgM3: (json['chlorophyll_mg_m3'] as num?)?.toDouble(),
      fishingEffortHours: (json['fishing_effort_hours'] as num?)?.toDouble(),
      nearestHarbour: json['nearest_harbour']?.toString(),
      nearestHarbourDistKm: (json['nearest_harbour_dist_km'] as num?)?.toDouble(),
      sources: (json['sources'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      sourcesFailed: (json['sources_failed'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      timestamp: timestamp,
      isCached: json['cached'] == true,
    );
  }

  ZoneSnapshot toEntity(StalenessInfo staleness) {
    if (lat == null || lon == null || timestamp == null) {
      throw const FormatException('ORCA point data has no verified coordinates or timestamp.');
    }
    return ZoneSnapshot(
        lat: lat!,
        lon: lon!,
        zoneName: zoneName ?? 'Marine point probe',
        offshoreDistKm: offshoreDistKm,
        depthM: depthM,
        waveHeightM: waveHeightM,
        swellPeriodS: swellPeriodS,
        windSpeedKn: windSpeedKn,
        windDirection: windDirection,
        seaTempC: seaTempC,
        currentSpeedKn: currentSpeedKn,
        currentDirection: currentDirection,
        chlorophyllMgM3: chlorophyllMgM3,
        fishingEffortHours: fishingEffortHours,
        nearestHarbour: nearestHarbour,
        nearestHarbourDistKm: nearestHarbourDistKm,
        sources: sources,
        sourcesFailed: sourcesFailed,
        timestamp: timestamp!,
        staleness: staleness,
      );
  }
}

/// DTO for a backend-advertised map capability, not a presumed tile URL.
class LayerDto {
  final String id;
  final String name;
  final String? unit;
  final String? source;
  final String? visualization;
  final String? endpoint;
  final String? state;
  final String? resolution;
  final String? reason;
  final bool available;

  const LayerDto({
    required this.id,
    required this.name,
    this.unit,
    this.source,
    this.visualization,
    this.endpoint,
    this.state,
    this.resolution,
    this.reason,
    required this.available,
  });

  factory LayerDto.fromJson(Map<String, dynamic> json) => LayerDto(
        id: json['id']?.toString() ?? 'unknown',
        name: json['name']?.toString() ?? 'Unavailable layer',
        unit: json['unit']?.toString(),
        source: json['source']?.toString(),
        visualization: json['visualization']?.toString(),
        endpoint: json['endpoint']?.toString(),
        state: json['state']?.toString(),
        resolution: json['resolution']?.toString(),
        reason: json['reason']?.toString(),
        available: json['available'] == true,
      );

  MapLayerEntity toEntity() => MapLayerEntity(
        id: id,
        name: name,
        unit: unit ?? '',
        source: source ?? 'Source unavailable',
        visualization: visualization ?? 'unavailable',
        endpoint: endpoint,
        state: state ?? 'UNAVAILABLE',
        resolution: resolution,
        reason: reason,
        available: available,
      );
}
