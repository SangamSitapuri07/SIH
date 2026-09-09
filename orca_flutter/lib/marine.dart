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

/// ─────────────────────────────────────────────────────────────────
/// (B5) LIVE NAVIGATION ALERT RULES — the real-time "dimag".
///
/// Ek GPS tick andar jata hai, alerts bahar aate hain. 100% OFFLINE:
/// sirf GPS + route legs chahiye (jo route-check ne diye) — internet
/// ke bina bhi off-course/turn alerts chalte rehte hain (demo USP).
/// PURE DART — koi I/O nahi, isliye har rule synthetic GPS feed se
/// unit-test se pin kiya gaya hai (test/marine_test.dart).
///
/// Anti-flap discipline (real navigation systems jaisi):
///   - off-course tabhi bolo jab confirmTicks lagatar bahar (patla
///     GPS jitter se cross karne pe siren nahi bajega)
///   - wapas andar aaya tabhi re-arm (har tick pe repeat nahi)
///   - turn cue ek waypoint pe sirf ek baar
/// ─────────────────────────────────────────────────────────────────
class NavAlert {
  /// 'offcourse' | 'turn' | 'ontrack'
  final String type;

  /// offcourse/ontrack: current XTE (cross-track error) in NM
  /// turn: distance to the waypoint in NM
  final double nm;

  /// offcourse: bearing BACK towards the next waypoint (deg)
  /// turn: bearing to steer after the turn (deg), else 0
  final double deg;
  const NavAlert(this.type, this.nm, this.deg);
}

class NavRules {
  /// Route legs as [[lat, lon], ...] — routecheck ke arrays hi.
  final List<List<double>> legs;

  /// Off-course siren threshold (NM) — us se zyada hat gaye to bolenge.
  final double offNm;

  /// Turn advisory radius (NM) — waypoint itne kareeb → "ab mudo".
  final double turnNm;

  /// Kitne lagatar ticks condition confirm karti hai (GPS jitter rokne).
  final int confirmTicks;

  int leg = 0; // active leg index
  int _offStreak = 0, _onStreak = 0;
  bool offActive = false;
  final Set<int> _turnFired = {}; // ek waypoint pe ek baar hi turn alert

  NavRules(this.legs, {this.offNm = 0.5, this.turnNm = 0.5, this.confirmTicks = 2});

  double _xteNm(double lat, double lon) {
    final a = legs[leg], b = legs[leg + 1];
    return Marine.kmToNm(
        Marine.crossTrackKm(lat, lon, a[0], a[1], b[0], b[1]));
  }

  double _distToLegEndNm(double lat, double lon) {
    final b = legs[leg + 1];
    return Marine.kmToNm(Marine.haversineKm(lat, lon, b[0], b[1]));
  }

  /// Ek position tick → emitted alerts (0 se zyada bhi ho sakte hain).
  List<NavAlert> tick(double lat, double lon) {
    final out = <NavAlert>[];
    if (legs.length < 2 || leg >= legs.length - 1) return out;

    // — leg advance + TURN cue —
    final dEnd = _distToLegEndNm(lat, lon);
    if (dEnd <= turnNm && leg < legs.length - 2 && !_turnFired.contains(leg)) {
      _turnFired.add(leg);
      leg++;
      final b = legs[leg + 1];
      out.add(NavAlert(
          'turn',
          dEnd,
          Marine.bearingDeg(lat, lon, b[0], b[1])));
    }

    // — OFF-COURSE (active leg se XTE) + recovery —
    final xte = _xteNm(lat, lon);
    final steerBack = Marine.bearingDeg(
        lat, lon, legs[leg + 1][0], legs[leg + 1][1]);
    if (xte > offNm) {
      _offStreak++;
      _onStreak = 0;
      if (!offActive && _offStreak >= confirmTicks) {
        offActive = true;
        out.add(NavAlert('offcourse', xte, steerBack));
      }
    } else {
      _onStreak++;
      _offStreak = 0;
      if (offActive && _onStreak >= confirmTicks) {
        offActive = false;
        out.add(NavAlert('ontrack', xte, 0));
      }
    }
    return out;
  }
}
