import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/design/data_state.dart';

/// [DataState.hasValue] is the single gate the metric widgets use before they
/// are allowed to print a number, so its behaviour is pinned here.
void main() {
  group('DataState.hasValue', () {
    test('only real-value states may render a number', () {
      expect(DataState.live.hasValue, isTrue);
      expect(DataState.forecast.hasValue, isTrue);
      expect(DataState.cached.hasValue, isTrue);
      expect(DataState.stale.hasValue, isTrue);
    });

    test('gap states must never render a number', () {
      expect(DataState.loading.hasValue, isFalse);
      expect(DataState.unavailable.hasValue, isFalse);
      expect(DataState.error.hasValue, isFalse);
      expect(DataState.offline.hasValue, isFalse);
    });

    test('every state has a distinct, non-empty token and label', () {
      final tokens = DataState.values.map((s) => s.token).toSet();
      expect(tokens, hasLength(DataState.values.length));
      for (final state in DataState.values) {
        expect(state.token, isNotEmpty);
        expect(state.label, isNotEmpty);
      }
    });

    test('only DataState.live carries the LIVE token', () {
      final live =
          DataState.values.where((s) => s.token == 'LIVE').toList();
      expect(live, [DataState.live]);
    });
  });

  group('Provenance', () {
    test('summary states the gap when source and time are missing', () {
      const prov = Provenance(state: DataState.unavailable);
      expect(prov.summary(), 'Source unavailable · Time unavailable');
    });

    test('summary names the real source and its valid time in IST', () {
      final prov = Provenance(
        state: DataState.forecast,
        source: 'Open-Meteo Marine (MFWAM/ECMWF)',
        validAt: DateTime.utc(2026, 9, 15, 4, 12),
        validAtLabel: 'Model valid',
      );
      // 04:12 UTC == 09:42 IST
      expect(prov.summary(),
          'Open-Meteo Marine (MFWAM/ECMWF) · Model valid 09:42 IST');
    });

    test('falls back to the retrieval time, labelled as such', () {
      final prov = Provenance(
        state: DataState.cached,
        source: 'NOAA ERDDAP',
        retrievedAt: DateTime.utc(2026, 9, 15, 0, 0),
      );
      expect(prov.summary(), 'NOAA ERDDAP · Retrieved 05:30 IST');
    });

    test('no validity window is implied when none was published', () {
      const prov = Provenance(state: DataState.live, source: 'X');
      expect(prov.validityWindow(), isNull);
    });

    test('a published window is rendered as a real range', () {
      final prov = Provenance(
        state: DataState.forecast,
        validAt: DateTime.utc(2026, 9, 15, 4, 0),
        validUntil: DateTime.utc(2026, 9, 15, 10, 0),
      );
      expect(prov.validityWindow(), 'Valid 09:30 IST – 15:30 IST');
    });

    test('convenience constructors carry no value', () {
      expect(const Provenance.loading().hasValue, isFalse);
      expect(const Provenance.unavailable().hasValue, isFalse);
      expect(const Provenance.error().hasValue, isFalse);
      expect(const Provenance.offline().hasValue, isFalse);
    });
  });
}
