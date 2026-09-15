import '../../domain/entities/route_check.dart';

/// DTO for /api/v1/route-check response.
class RouteCheckDto {
  final bool? ok;
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
        <String>[];

    return RouteCheckDto(
      ok: json['ok'] as bool?,
      detour: json['detour'] as bool?,
      landHit: json['land_hit'] as bool?,
      reason: json['reason'] as String? ?? 'Route check response unavailable.',
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      distanceNm: (json['distance_nm'] as num?)?.toDouble(),
      bearingDeg: (json['bearing_deg'] as num?)?.toDouble(),
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
      final lat = (detourWpJson!['lat'] as num?)?.toDouble();
      final lon = (detourWpJson!['lon'] as num?)?.toDouble();
      final name = detourWpJson!['name']?.toString();
      final clearance = (detourWpJson!['clearance_km'] as num?)?.toDouble();
      if (lat != null && lon != null && name != null && clearance != null) {
        wp = DetourWaypoint(lat: lat, lon: lon, name: name, clearanceKm: clearance);
      }
    }

    return RouteCheckEntity(
      ok: ok,
      detour: detour,
      landHit: landHit,
      reason: reason ?? 'Route check response unavailable.',
      distanceKm: distanceKm,
      distanceNm: distanceNm,
      bearingDeg: bearingDeg,
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
        <String>[];

    return RouteAdvisoryDto(
      verdictJson: json['verdict'] as Map<String, dynamic>?,
      pointsList: json['points'] as List<dynamic>?,
      safeWindowJson: json['safe_window_at_start'] as Map<String, dynamic>?,
      sources: sourcesList,
    );
  }

  RouteAdvisoryEntity toEntity() {
    final level = verdictJson?['level'] as String? ?? 'UNVERIFIED';
    final known = verdictJson?['points_known'] as int? ?? 0;
    final total = verdictJson?['total'] as int? ?? 0;
    final verified = verdictJson?['land_verified'] as bool? ?? false;
    final headline = verdictJson?['headline'] as String? ?? 'Route safety verdict unavailable.';

    final parsedPoints = <TransitPoint>[];
    if (pointsList != null) {
      for (final p in pointsList!) {
        if (p is Map<String, dynamic>) {
          parsedPoints.add(
            TransitPoint(
              sailKm: (p['sail_km'] as num?)?.toDouble(),
              lat: (p['lat'] as num?)?.toDouble(),
              lon: (p['lon'] as num?)?.toDouble(),
              waveM: (p['wave_m'] as num?)?.toDouble(),
              windKn: (p['wind_kn'] as num?)?.toDouble(),
              state: p['state'] as String? ?? 'unverified',
              why: p['why'] as String? ?? 'Marine inputs unavailable for this route point.',
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
      safeWindowFrom: safeWindowJson?['from'] as String? ?? '',
      safeWindowTo: safeWindowJson?['to'] as String? ?? '',
      isSafeStart: safeWindowJson?['is_safe'] as bool? ?? false,
      sources: sources,
    );
  }
}
