/// Data classes matching the ORCA backend's Pydantic schemas.
///
/// Keep these in sync with `backend/app/models.py`. The backend is the
/// source of truth; this file is a hand-written mirror.
library;

import 'package:latlong2/latlong.dart';

/// A point to render on the map.
class MapPoint {
  final double lat;
  final double lon;
  final String? label;
  final String? color; // hex
  final Map<String, dynamic> metadata;

  const MapPoint({
    required this.lat,
    required this.lon,
    this.label,
    this.color,
    this.metadata = const {},
  });

  factory MapPoint.fromJson(Map<String, dynamic> j) => MapPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        label: j['label'] as String?,
        color: j['color'] as String?,
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  LatLng get position => LatLng(lat, lon);
}

/// A polygon to render on the map (PFZ zone, geofence, etc.).
class MapPolygon {
  final String name;
  final List<LatLng> coordinates;
  final String color; // hex
  final bool fill;
  final Map<String, dynamic> metadata;

  const MapPolygon({
    required this.name,
    required this.coordinates,
    this.color = '#22C55E',
    this.fill = true,
    this.metadata = const {},
  });

  factory MapPolygon.fromJson(Map<String, dynamic> j) => MapPolygon(
        name: j['name'] as String? ?? 'zone',
        coordinates: ((j['coordinates'] as List?) ?? const [])
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList(),
        color: (j['color'] as String?) ?? '#22C55E',
        fill: (j['fill'] as bool?) ?? true,
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Payload of polygons + points + viewport for the map.
class MapPayload {
  final List<MapPoint> points;
  final List<MapPolygon> polygons;
  final LatLng center;
  final double zoom;

  const MapPayload({
    this.points = const [],
    this.polygons = const [],
    required this.center,
    this.zoom = 6.0,
  });

  factory MapPayload.fromJson(Map<String, dynamic> j) {
    final centerList = (j['center'] as List?) ?? const [15.5, 73.8];
    return MapPayload(
      points: ((j['points'] as List?) ?? const [])
          .map((e) => MapPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      polygons: ((j['polygons'] as List?) ?? const [])
          .map((e) => MapPolygon.fromJson(e as Map<String, dynamic>))
          .toList(),
      center: LatLng(
        (centerList[0] as num).toDouble(),
        (centerList[1] as num).toDouble(),
      ),
      zoom: (j['zoom'] as num?)?.toDouble() ?? 6.0,
    );
  }

  factory MapPayload.empty() => const MapPayload(center: LatLng(15.5, 73.8));
}

/// One step in the agent reasoning chain — the "explainability" payload.
class AgentStep {
  final String agent;
  final String summary;
  final List<String> dataSources;
  final int durationMs;

  const AgentStep({
    required this.agent,
    required this.summary,
    this.dataSources = const [],
    this.durationMs = 0,
  });

  factory AgentStep.fromJson(Map<String, dynamic> j) => AgentStep(
        agent: j['agent'] as String? ?? '?',
        summary: j['summary'] as String? ?? '',
        dataSources: ((j['data_sources'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        durationMs: (j['duration_ms'] as num?)?.toInt() ?? 0,
      );
}

/// The final ORCA response.
class OrcaResponse {
  final String answerText;
  final String language;
  final String intent;
  final double confidence;
  final MapPayload map;
  final List<String> alerts;
  final List<AgentStep> reasoning;
  final double? safetyScore;

  const OrcaResponse({
    required this.answerText,
    this.language = 'en',
    this.intent = 'unknown',
    this.confidence = 0.5,
    required this.map,
    this.alerts = const [],
    this.reasoning = const [],
    this.safetyScore,
  });

  factory OrcaResponse.fromJson(Map<String, dynamic> j) => OrcaResponse(
        answerText: j['answer_text'] as String? ?? '',
        language: j['language'] as String? ?? 'en',
        intent: j['intent'] as String? ?? 'unknown',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
        map: j['map'] != null
            ? MapPayload.fromJson(j['map'] as Map<String, dynamic>)
            : MapPayload.empty(),
        alerts: ((j['alerts'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        reasoning: ((j['reasoning'] as List?) ?? const [])
            .map((e) => AgentStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        safetyScore: (j['safety_score'] as num?)?.toDouble(),
      );

  bool get hasMap => map.polygons.isNotEmpty || map.points.isNotEmpty;
}
