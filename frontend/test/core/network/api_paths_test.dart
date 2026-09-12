import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/config/api_paths.dart';

void main() {
  group('ApiPaths Tests', () {
    test('Canonical endpoints use /api/v1 prefix', () {
      expect(ApiPaths.health, equals('/api/v1/health'));
      expect(ApiPaths.advisory, equals('/api/v1/advisory'));
      expect(ApiPaths.reason, equals('/api/v1/reason'));
      expect(ApiPaths.routeCheck, equals('/api/v1/route-check'));
      expect(ApiPaths.routeAdvisory, equals('/api/v1/route-advisory'));
      expect(ApiPaths.liveStream, equals('/api/live/stream'));
    });

    test('Legacy fallbacks map correctly for backward compatibility', () {
      expect(ApiPaths.legacyFallbacks[ApiPaths.advisory], equals('/api/advisory'));
      expect(ApiPaths.legacyFallbacks[ApiPaths.agents], equals('/api/agents'));
      expect(ApiPaths.legacyFallbacks[ApiPaths.alerts], equals('/api/alerts'));
    });
  });
}
