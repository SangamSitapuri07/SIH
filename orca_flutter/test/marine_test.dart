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
}
