import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/network/dio_provider.dart';

void main() {
  group('normalizeOrcaBoxUrl', () {
    test('turns a bare LAN IP into the ORCA Box HTTP endpoint', () {
      expect(normalizeOrcaBoxUrl('192.168.1.15'), 'http://192.168.1.15:8000');
    });

    test('preserves an explicit port', () {
      expect(
        normalizeOrcaBoxUrl('http://192.168.1.15:9000/'),
        'http://192.168.1.15:9000',
      );
    });

    test('rejects malformed and incomplete server addresses', () {
      expect(normalizeOrcaBoxUrl(''), isNull);
      expect(normalizeOrcaBoxUrl('http://'), isNull);
      expect(normalizeOrcaBoxUrl('ftp://192.168.1.15'), isNull);
    });
  });
}
