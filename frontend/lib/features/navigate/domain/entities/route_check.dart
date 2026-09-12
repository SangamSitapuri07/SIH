/// Detour waypoint computed to avoid land hit (§4, §6).
class DetourWaypoint {
  final double lat;
  final double lon;
  final String name;
  final double clearanceKm;

  const DetourWaypoint({
    required this.lat,
    required this.lon,
    required this.name,
    required this.clearanceKm,
  });
}

/// Course land verification entity (/api/v1/route-check).
class RouteCheckEntity {
  final bool ok;
  final bool detour;
  final bool landHit;
  final String reason;
  final double distanceKm;
  final double distanceNm;
  final double bearingDeg;
  final List<List<double>> legs;
  final DetourWaypoint? detourWaypoint;
  final List<String> sources;

  const RouteCheckEntity({
    required this.ok,
    required this.detour,
    required this.landHit,
    required this.reason,
    required this.distanceKm,
    required this.distanceNm,
    required this.bearingDeg,
    required this.legs,
    this.detourWaypoint,
    required this.sources,
  });
}

/// Single sampling point along route (sampled every ~30 km).
class TransitPoint {
  final double sailKm;
  final double lat;
  final double lon;
  final double waveM;
  final double windKn;
  final String state; // good, caution, danger
  final String why;

  const TransitPoint({
    required this.sailKm,
    required this.lat,
    required this.lon,
    required this.waveM,
    required this.windKn,
    required this.state,
    required this.why,
  });
}

/// Transit safety verdict across full route (/api/v1/route-advisory).
class RouteAdvisoryEntity {
  final String level; // go, caution, nogo, unknown
  final int pointsKnown;
  final int totalPoints;
  final bool landVerified;
  final String headline;
  final List<TransitPoint> points;
  final String safeWindowFrom;
  final String safeWindowTo;
  final bool isSafeStart;
  final List<String> sources;

  const RouteAdvisoryEntity({
    required this.level,
    required this.pointsKnown,
    required this.totalPoints,
    required this.landVerified,
    required this.headline,
    required this.points,
    required this.safeWindowFrom,
    required this.safeWindowTo,
    required this.isSafeStart,
    required this.sources,
  });
}
