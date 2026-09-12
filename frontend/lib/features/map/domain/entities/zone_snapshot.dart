import '../../../../core/cache/staleness.dart';

/// Single ocean spot snapshot probed by the skipper (§4, §8).
class ZoneSnapshot {
  final double lat;
  final double lon;
  final String zoneName;
  final double offshoreDistKm;
  final double? depthM;
  final double waveHeightM;
  final double? swellPeriodS;
  final double windSpeedKn;
  final String? windDirection;
  final double seaTempC;
  final double currentSpeedKn;
  final String? currentDirection;
  final double? chlorophyllMgM3;
  final double? fishingEffortHours;
  final String? nearestHarbour;
  final double? nearestHarbourDistKm;
  final List<String> sources;
  final List<String> sourcesFailed;
  final DateTime timestamp;
  final StalenessInfo staleness;

  const ZoneSnapshot({
    required this.lat,
    required this.lon,
    required this.zoneName,
    required this.offshoreDistKm,
    this.depthM,
    required this.waveHeightM,
    this.swellPeriodS,
    required this.windSpeedKn,
    this.windDirection,
    required this.seaTempC,
    required this.currentSpeedKn,
    this.currentDirection,
    this.chlorophyllMgM3,
    this.fishingEffortHours,
    this.nearestHarbour,
    this.nearestHarbourDistKm,
    required this.sources,
    required this.sourcesFailed,
    required this.timestamp,
    required this.staleness,
  });
}

/// Metadata describing a map layer toggle.
class MapLayerEntity {
  final String id;
  final String name;
  final String unit;
  final String source;
  final String tileUrl;
  final bool isEnabled;

  const MapLayerEntity({
    required this.id,
    required this.name,
    required this.unit,
    required this.source,
    required this.tileUrl,
    this.isEnabled = false,
  });

  MapLayerEntity copyWith({bool? isEnabled}) {
    return MapLayerEntity(
      id: id,
      name: name,
      unit: unit,
      source: source,
      tileUrl: tileUrl,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
