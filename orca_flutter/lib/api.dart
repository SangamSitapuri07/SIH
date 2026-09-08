import 'dart:convert';

import 'package:http/http.dart' as http;

/// FastAPI client — SIRF real endpoints (plan §5):
///   GET /api/v1/health · /api/v1/advisory · /api/v1/field · /api/v1/route-check
/// Koi mock/dummy yahan kabhi nahi aayega: fail hua to caller ko exception
/// milta hai aur UI honest reason dikhata hai.
class OrcaApi {
  /// Default = laptop LAN (dev). Info tab se editable, persisted.
  static const defaultBase = '192.168.1.5:8000';

  static Uri _u(String base, String path, [Map<String, String>? q]) {
    // LAN: '192.168.1.137:8000' (http add hota hai) · Cloud/Tunnel:
    // 'https://xyz.ngrok-free.app' (scheme waise hi use hota hai)
    var b = base.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!b.startsWith('http')) b = 'http://$b';
    return Uri.parse('$b$path').replace(queryParameters: q);
  }

  /// GET /api/v1/health → Map on HTTP 200, else throws.
  /// (backend main.py:273 — plain /health exist hi nahi karta, 404 aata)
  static Future<Map<String, dynamic>> health(String base) async {
    final r = await http
        .get(_u(base, '/api/v1/health'))
        .timeout(const Duration(seconds: 6));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${r.statusCode}');
  }

  /// (D2) advisory — waves/wind/SST verdict series.
  static Future<Map<String, dynamic>> advisory(
      String base, double lat, double lon) async {
    final r = await http
        .get(_u(base, '/api/v1/advisory',
            {'lat': '$lat', 'lon': '$lon'}))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${r.statusCode}');
  }

  /// (D3) field — grid + hotspots (+land-mask flags).
  static Future<Map<String, dynamic>> field(
      String base, double lat, double lon) async {
    final r = await http
        .get(_u(base, '/api/v1/field', {'lat': '$lat', 'lon': '$lon'}))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${r.statusCode}');
  }

  /// (D4) route-check — GLOBE-verified sea route.
  static Future<Map<String, dynamic>> routeCheck(String base, double fromLat,
      double fromLon, double toLat, double toLon) async {
    final r = await http
        .get(_u(base, '/api/v1/route-check', {
          'from_lat': '$fromLat',
          'from_lon': '$fromLon',
          'to_lat': '$toLat',
          'to_lon': '$toLon'
        }))
        .timeout(const Duration(seconds: 25));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('HTTP ${r.statusCode}');
  }
}
