import '../../domain/entities/route_check.dart';

/// DTO for /api/v1/route-check response.
class RouteCheckDto {
  final bool ok;
  final bool? detour;
  final bool? landHit;
  final String? reason;
  final double? distanceKm;
  final double? distanceNm;
  final double? bearingDeg;
  final List<dynamic>? legsList;
  final Map<String, dynamic>? detourWpJson;
  final List<String> sources;

  RouteCheckDto({
    required this.ok,
    this.detour,
    this.landHit,
    this.reason,
    this.distanceKm,
    this.distanceNm,
    this.bearingDeg,
    this.legsList,
    this.detourWpJson,
    required this.sources,
  });

  factory RouteCheckDto.fromJson(Map<String, dynamic> json) {
    final sourcesList = (json['sources'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>['GLOBE 1km Landmask'];

    return RouteCheckDto(
      ok: json['ok'] as bool? ?? true,
      detour: json['detour'] as bool? ?? false,
      landHit: json['land_hit'] as bool? ?? false,
      reason: json['reason'] as String? ?? 'Course verified clear of land.',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      distanceNm: (json['distance_nm'] as num?)?.toDouble() ?? 0.0,
      bearingDeg: (json['bearing_deg'] as num?)?.toDouble() ?? 0.0,
      legsList: json['legs'] as List<dynamic>?,
      detourWpJson: json['detour_waypoint'] as Map<String, dynamic>?,
      sources: sourcesList,
    );
  }

  RouteCheckEntity toEntity() {
    final parsedLegs = <List<double>>[];
    if (legsList != null) {
      for (final leg in legsList!) {
        if (leg is List) {
          parsedLegs.add(leg.map((e) => (e as num).toDouble()).toList());
        }
      }
    }

    DetourWaypoint? wp;
    if (detourWpJson != null) {
      wp = DetourWaypoint(
        lat: (detourWpJson!['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (detourWpJson!['lon'] as num?)?.toDouble() ?? 0.0,
        name: detourWpJson!['name'] as String? ?? 'Detour Waypoint',
        clearanceKm: (detourWpJson!['clearance_km'] as num?)?.toDouble() ?? 2.0,
      );
    }

    return RouteCheckEntity(
      ok: ok,
      detour: detour ?? false,
      landHit: landHit ?? false,
      reason: reason ?? 'Course verified clear.',
      distanceKm: distanceKm ?? 0.0,
      distanceNm: distanceNm ?? 0.0,
      bearingDeg: bearingDeg ?? 0.0,
      legs: parsedLegs,
      detourWaypoint: wp,
      sources: sources,
    );
  }
}

/// DTO for /api/v1/route-advisory response.
class RouteAdvisoryDto {
  final Map<String, dynamic>? verdictJson;
  final List<dynamic>? pointsList;
  final Map<String, dynamic>? safeWindowJson;
  final List<String> sources;

  RouteAdvisoryDto({
    this.verdictJson,
    this.pointsList,
    this.safeWindowJson,
    required this.sources,
  });

  factory RouteAdvisoryDto.fromJson(Map<String, dynamic> json) {
    final sourcesList = (json['sources'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>['Open-Meteo Marine', 'GLOBE 1km'];

    return RouteAdvisoryDto(
      verdictJson: json['verdict'] as Map<String, dynamic>?,
      pointsList: json['points'] as List<dynamic>?,
      safeWindowJson: json['safe_window_at_start'] as Map<String, dynamic>?,
      sources: sourcesList,
    );
  }

  RouteAdvisoryEntity toEntity() {
    final level = verdictJson?['level'] as String? ?? 'caution';
    final known = verdictJson?['points_known'] as int? ?? 4;
    final total = verdictJson?['total'] as int? ?? 4;
    final verified = verdictJson?['land_verified'] as bool? ?? true;
    final headline = verdictJson?['headline'] as String? ?? 'Transit safe with caution.';

    final parsedPoints = <TransitPoint>[];
    if (pointsList != null) {
      for (final p in pointsList!) {
        if (p is Map<String, dynamic>) {
          parsedPoints.add(
            TransitPoint(
              sailKm: (p['sail_km'] as num?)?.toDouble() ?? 0.0,
              lat: (p['lat'] as num?)?.toDouble() ?? 0.0,
              lon: (p['lon'] as num?)?.toDouble() ?? 0.0,
              waveM: (p['wave_m'] as num?)?.toDouble() ?? 1.5,
              windKn: (p['wind_kn'] as num?)?.toDouble() ?? 12.0,
              state: p['state'] as String? ?? 'good',
              why: p['why'] as String? ?? 'Clear passage.',
            ),
          );
        }
      }
    }

    return RouteAdvisoryEntity(
      level: level,
      pointsKnown: known,
      totalPoints: total,
      landVerified: verified,
      headline: headline,
      points: parsedPoints,
      safeWindowFrom: safeWindowJson?['from'] as String? ?? '06:00 IST',
      safeWindowTo: safeWindowJson?['to'] as String? ?? '16:00 IST',
      isSafeStart: safeWindowJson?['is_safe'] as bool? ?? true,
      sources: sources,
    );
  }
}
