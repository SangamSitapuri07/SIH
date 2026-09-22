import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/utils/coordinate_parser.dart';

void main() {
  group('parseCoordinateFromText', () {
    test('parses hemisphere coordinate from an Ask ORCA question', () {
      final result = parseCoordinateFromText('What is the weather at 19.52°N 71.50°E?');
      expect(result, isNotNull);
      expect(result!.latitude, 19.52);
      expect(result.longitude, 71.50);
    });

    test('applies southern and western hemispheres', () {
      final result = parseCoordinateFromText('12.5 S, 44.2 W');
      expect(result, isNotNull);
      expect(result!.latitude, -12.5);
      expect(result.longitude, -44.2);
    });

    test('parses explicit comma and labelled pairs', () {
      final comma = parseCoordinateFromText('check 19.52, 71.50 please');
      final labelled = parseCoordinateFromText('latitude=19.52 longitude=71.50');
      expect(comma?.latitude, 19.52);
      expect(comma?.longitude, 71.50);
      expect(labelled?.latitude, 19.52);
      expect(labelled?.longitude, 71.50);
    });

    test('does not interpret ordinary measurements as a coordinate', () {
      expect(parseCoordinateFromText('waves 2.5 m and wind 15 kn'), isNull);
      expect(parseCoordinateFromText('leave on 16 September at 06:00'), isNull);
    });

    test('rejects out-of-range coordinates', () {
      expect(parseCoordinateFromText('95.0 N, 71.5 E'), isNull);
      expect(parseCoordinateFromText('19.5, 190.0'), isNull);
    });
  });
}
