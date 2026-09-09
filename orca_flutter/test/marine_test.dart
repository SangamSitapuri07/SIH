import 'package:flutter_test/flutter_test.dart';
import 'package:orca_marine/marine.dart';

/// ORCA marine-math unit tests — values cross-checked against the
/// reviewer-verified web implementation (web/lib/marine-math.ts).
void main() {
  test('haversine + NM: Veraval (20.9,70.37) → hotspot (20.63,70.71)', () {
    final km = Marine.haversineKm(20.9, 70.37, 20.63, 70.71);
    expect(km, closeTo(46.4, 0.6));
    expect(Marine.kmToNm(km), closeTo(25.0, 0.4));
  });

  test('bearing Veraval → hotspot ≈ 130° (SE)', () {
    expect(Marine.bearingDeg(20.9, 70.37, 20.63, 70.71), closeTo(130, 2));
  });

  test('cross-track: 0.5 NM off a straight east line', () {
    final km = Marine.crossTrackKm(20.0083, 70.0, 20.0, 70.0, 20.0, 71.06);
    expect(Marine.kmToNm(km), closeTo(0.5, 0.05));
  });

  test('steerHint: on-course null, 90° right turn detected', () {
    expect(Marine.steerHint(0, 0), isNull);
    final h = Marine.steerHint(0, 90);
    expect(h, isNotNull);
    expect(h!.left, isFalse);
    expect(h.deg, 90.0);
    final l = Marine.steerHint(90, 0);
    expect(l!.left, isTrue);
  });

  test('eta formatting + low-speed guard', () {
    expect(Marine.eta(18.52, 10), '1h 0m');
    expect(Marine.eta(9.26, 10), '30m');
    expect(Marine.eta(18.52, 0.2), '—');
  });

  test('compass16 wraps correctly', () {
    expect(Marine.compass16(0), 'N');
    expect(Marine.compass16(45), 'NE');
    expect(Marine.compass16(130), 'SE');
    expect(Marine.compass16(359), 'N');
  });
  // ── (B5) LIVE ALERT RULES — real-time engine, synthetic GPS feed ──
  NavRules rules3() => NavRules(
        const [
          [20.0, 70.0], // start
          [20.0, 70.5], // waypoint (~51 NM east)
          [20.0, 71.0], // destination
        ],
      );

  test('off-course: debounce → fire once → recover → re-arm', () {
    final r = rules3();
    // ~1 NM north of the E-W line (0.01806° lat ≈ 1.08 NM)
    const offLat = 20.01806;
    expect(r.tick(offLat, 70.1), isEmpty); // tick 1: jitter tolerate
    final a2 = r.tick(offLat, 70.1); // tick 2 confirm → FIRE
    expect(a2.single.type, 'offcourse');
    expect(a2.single.nm, greaterThan(0.9));
    expect(a2.single.deg, closeTo(92.7, 2)); // steer back SOUTH-EAST to waypoint
    expect(r.tick(offLat, 70.1), isEmpty); // har tick repeat nahi
    expect(r.tick(20.0, 70.1), isEmpty); // wapas tick 1
    final a5 = r.tick(20.0, 70.1); // recovery confirm
    expect(a5.single.type, 'ontrack');
  });

  test('turn cue: waypoint ke paas ek baar, sahi bearing ke saath', () {
    final r = rules3();
    final a = r.tick(20.0, 70.498); // ~0.11 NM before waypoint
    expect(a.single.type, 'turn');
    expect(a.single.deg, closeTo(90, 3)); // pure east next leg
    expect(r.tick(20.0, 70.4991), isEmpty); // dobara nahi
  });

  test('short single leg: no crash, pure XTE watch', () {
    final r = NavRules(const [
      [20.0, 70.0],
      [20.0, 71.0],
    ]);
    expect(r.tick(20.0361, 70.5), isEmpty); // ~2 NM off, tick 1
    final a = r.tick(20.0361, 70.5);
    expect(a.single.type, 'offcourse');
  });
}
