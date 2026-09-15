import '../../../../core/cache/staleness.dart';

/// Single ocean spot snapshot returned by the ORCA backend.
///
/// Measurements are nullable by design. A missing upstream measurement is not
/// converted into a plausible looking fallback number: consumers must display
/// “Unavailable” and retain the provided provenance instead.
class ZoneSnapshot {
  final double lat;
  final double lon;
  final String zoneName;
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
  final DateTime timestamp;
  final StalenessInfo staleness;

  const ZoneSnapshot({
    required this.lat,
    required this.lon,
    required this.zoneName,
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
    required this.timestamp,
    required this.staleness,
  });
}

/// Backend-advertised map capability. Only an available layer with a supported
/// visualization can be activated in the map UI.
class MapLayerEntity {
  final String id;
  final String name;
  final String unit;
  final String source;
  final String visualization;
  final String? endpoint;
  final String state;
  final String? resolution;
  final String? reason;
  final bool available;

  const MapLayerEntity({
    required this.id,
    required this.name,
    required this.unit,
    required this.source,
    required this.visualization,
    this.endpoint,
    required this.state,
    this.resolution,
    this.reason,
    required this.available,
  });

  bool get isMapRenderable => available &&
      (visualization == 'vector_grid' || visualization == 'scalar_grid' || visualization == 'geojson');
}
