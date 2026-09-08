import 'dart:math' as math;

/// Marine math — 1:1 port of web/lib/marine-math.ts (reviewer-verified formulas).
class Marine {
  static const double kmPerNm = 1.852;
  static const double _r = 6371.0; // earth radius km

  static double deg2rad(double d) => d * math.pi / 180.0;

  /// Great-circle distance in km.
  static double haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = deg2rad(lat2 - lat1);
    final dLon = deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(deg2rad(lat1)) *
            math.cos(deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * _r * math.asin(math.sqrt(a));
  }

  /// Initial bearing A→B in degrees 0..360.
  static double bearingDeg(
      double lat1, double lon1, double lat2, double lon2) {
    final y = math.sin(deg2rad(lon2 - lon1)) * math.cos(deg2rad(lat2));
    final x = math.cos(deg2rad(lat1)) * math.sin(deg2rad(lat2)) -
        math.sin(deg2rad(lat1)) *
            math.cos(deg2rad(lat2)) *
            math.cos(deg2rad(lon2 - lon1));
    var brg = math.atan2(y, x) * 180 / math.pi;
    return (brg + 360) % 360;
  }

  /// Cross-track distance (km): how far point P is off the great-circle A→B.
  static double crossTrackKm(
      double pLat, double pLon, double aLat, double aLon, double bLat, double bLon) {
    final d13 = haversineKm(aLat, aLon, pLat, pLon) / _r; // angular
    final t13 = deg2rad(bearingDeg(aLat, aLon, pLat, pLon));
    final t12 = deg2rad(bearingDeg(aLat, aLon, bLat, bLon));
    return (math.asin(math.sin(d13) * math.sin(t13 - t12)) * _r).abs();
  }

  static double kmToNm(double km) => km / kmPerNm;

  static String fmtNm(double km) => kmToNm(km).toStringAsFixed(1);

  /// Compass 16-point in EN (boat pe degrees hi padhe jaate hain, label chhota).
  static String compass16(double deg) {
    const pts = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ];
    return pts[((deg + 11.25) / 22.5).floor() % 16];
  }

  /// ETA string "3h 20m"; returns '—' if speed too low.
  static String eta(double distKm, double speedKn) {
    if (speedKn < 0.5) return '—';
    final hrs = kmToNm(distKm) / speedKn;
    final h = hrs.floor();
    final m = ((hrs - h) * 60).round();
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// Steering correction hint: (turnDeg, left?) — null if on course.
  /// heading = device course-over-ground (deg), target = bearing (deg).
  static ({double deg, bool left})? steerHint(double heading, double target) {
    var diff = (target - heading + 540) % 360 - 180; // -180..180
    if (diff.abs() < 8) return null;
    return (deg: diff.abs().roundToDouble(), left: diff < 0);
  }
}
