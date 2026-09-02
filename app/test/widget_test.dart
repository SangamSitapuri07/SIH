import 'package:flutter_test/flutter_test.dart';

import 'package:orca_marine/api/models.dart';

void main() {
  test('MapPoint.fromJson parses lat/lon', () {
    final p = MapPoint.fromJson({
      'lat': 18.9,
      'lon': 72.8,
      'label': 'You',
      'color': '#3B82F6',
    });
    expect(p.lat, 18.9);
    expect(p.lon, 72.8);
    expect(p.label, 'You');
    expect(p.position.latitude, 18.9);
  });

  test('MapPolygon.fromJson parses coordinates', () {
    final pg = MapPolygon.fromJson({
      'name': 'Test PFZ',
      'coordinates': [[19.0, 72.5], [19.0, 73.0], [18.5, 73.0]],
      'color': '#22C55E',
    });
    expect(pg.name, 'Test PFZ');
    expect(pg.coordinates.length, 3);
    expect(pg.coordinates.first.latitude, 19.0);
  });

  test('OrcaResponse.fromJson handles missing fields', () {
    final r = OrcaResponse.fromJson({
      'answer_text': 'hi',
      'map': {
        'points': [],
        'polygons': [],
        'center': [15.0, 73.0],
        'zoom': 5.0,
      },
    });
    expect(r.answerText, 'hi');
    expect(r.intent, 'unknown');
    expect(r.safetyScore, null);
    expect(r.map.center.latitude, 15.0);
  });
}
