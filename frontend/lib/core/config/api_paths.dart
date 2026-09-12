/// Centralized API endpoint paths with legacy fallback mappings (§4).
class ApiPaths {
  // Canonical v1 paths
  static const String health = '/api/v1/health';
  static const String advisory = '/api/v1/advisory';
  static const String zone = '/api/v1/zone';
  static const String grid = '/api/v1/grid';
  static const String reason = '/api/v1/reason';
  static const String field = '/api/v1/field';
  static const String routeCheck = '/api/v1/route-check';
  static const String routeAdvisory = '/api/v1/route-advisory';
  static const String layers = '/api/v1/layers';
  static const String datasets = '/api/v1/datasets';
  static const String zones = '/api/v1/zones';
  static const String alerts = '/api/v1/alerts';
  static const String alertsSimulate = '/api/v1/alerts/simulate';
  static const String agents = '/api/v1/agents';
  static const String chat = '/api/v1/chat';
  static const String feedback = '/api/v1/feedback';
  static const String liveStream = '/api/live/stream';
  static const String mapSynoptic = '/api/map/synoptic';

  /// Legacy fallback mapping if v1 endpoints return 404.
  static const Map<String, String> legacyFallbacks = {
    advisory: '/api/advisory',
    agents: '/api/agents',
    alerts: '/api/alerts',
    layers: '/api/layers',
    chat: '/api/chat',
  };

  /// Returns tile URL template for flutter_map.
  static String tileUrl(String baseUrl, String layerType) {
    return '$baseUrl/api/v1/tiles/$layerType/{z}/{x}/{y}.png';
  }
}
