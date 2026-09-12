import '../../../../core/cache/staleness.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../domain/entities/zone_snapshot.dart';
import '../../domain/entities/map_layer.dart';

/// DTO for /api/v1/zone probe response.
class ZoneDto {
  final double lat;
  final double lon;
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
  final String? timestampStr;

  ZoneDto({
    required this.lat,
    required this.lon,
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
    this.timestampStr,
  });

  factory ZoneDto.fromJson(Map<String, dynamic> json) {
    final sourcesList = (json['sources'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final failedList = (json['sources_failed'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    return ZoneDto(
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      zoneName: json['zone_name'] as String? ?? 'Probed Ocean Spot',
      offshoreDistKm: (json['offshore_dist_km'] as num?)?.toDouble() ?? 0.0,
      depthM: (json['depth_m'] as num?)?.toDouble(),
      waveHeightM: (json['wave_height_m'] as num?)?.toDouble() ?? 1.5,
      swellPeriodS: (json['swell_period_s'] as num?)?.toDouble(),
      windSpeedKn: (json['wind_speed_kn'] as num?)?.toDouble() ?? 12.0,
      windDirection: json['wind_direction'] as String?,
      seaTempC: (json['sea_temp_c'] as num?)?.toDouble() ?? 28.0,
      currentSpeedKn: (json['current_speed_kn'] as num?)?.toDouble() ?? 1.0,
      currentDirection: json['current_direction'] as String?,
      chlorophyllMgM3: (json['chlorophyll_mg_m3'] as num?)?.toDouble(),
      fishingEffortHours: (json['fishing_effort_hours'] as num?)?.toDouble(),
      nearestHarbour: json['nearest_harbour'] as String?,
      nearestHarbourDistKm: (json['nearest_harbour_dist_km'] as num?)?.toDouble(),
      sources: sourcesList,
      sourcesFailed: failedList,
      timestampStr: json['timestamp'] as String?,
    );
  }

  ZoneSnapshot toEntity(StalenessInfo staleness) {
    return ZoneSnapshot(
      lat: lat,
      lon: lon,
      zoneName: zoneName ?? 'Probed Ocean Spot',
      offshoreDistKm: offshoreDistKm ?? 0.0,
      depthM: depthM,
      waveHeightM: waveHeightM ?? 1.5,
      swellPeriodS: swellPeriodS,
      windSpeedKn: windSpeedKn ?? 12.0,
      windDirection: windDirection,
      seaTempC: seaTempC ?? 28.0,
      currentSpeedKn: currentSpeedKn ?? 1.0,
      currentDirection: currentDirection,
      chlorophyllMgM3: chlorophyllMgM3,
      fishingEffortHours: fishingEffortHours,
      nearestHarbour: nearestHarbour,
      nearestHarbourDistKm: nearestHarbourDistKm,
      sources: sources,
      sourcesFailed: sourcesFailed,
      timestamp: DateFormatter.parseIso(timestampStr) ?? DateTime.now(),
      staleness: staleness,
    );
  }
}

/// DTO for /api/v1/layers.
class LayerDto {
  final String id;
  final String name;
  final String? unit;
  final String? source;
  final String? tileUrl;
  final bool? enabled;

  LayerDto({
    required this.id,
    required this.name,
    this.unit,
    this.source,
    this.tileUrl,
    this.enabled,
  });

  factory LayerDto.fromJson(Map<String, dynamic> json) {
    return LayerDto(
      id: json['id'] as String? ?? 'layer',
      name: json['name'] as String? ?? 'Layer',
      unit: json['unit'] as String?,
      source: json['source'] as String?,
      tileUrl: json['tile_url'] as String?,
      enabled: json['enabled'] as bool?,
    );
  }

  MapLayerEntity toEntity() {
    return MapLayerEntity(
      id: id,
      name: name,
      unit: unit ?? '',
      source: source ?? 'Backend Map Tile',
      tileUrl: tileUrl ?? '/api/v1/tiles/$id/{z}/{x}/{y}.png',
      isEnabled: enabled ?? false,
    );
  }
}
