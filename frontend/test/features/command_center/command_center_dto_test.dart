import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/design/data_state.dart';
import 'package:orca_app/features/command_center/data/dto/command_center_dto.dart';

/// Pins the honesty contract of the Command Center DTOs.
///
/// These are the guarantees the UI relies on to be unable to print an
/// unattributed number, so they are asserted directly rather than through a
/// widget.
void main() {
  group('MarineConditionsDto error envelope', () {
    test('a 200 {"error": true} body yields no values and a real reason', () {
      // The backend answers 200 (not an HTTP error) when providers are down.
      final dto = MarineConditionsDto.fromJson(const {
        'error': true,
        'reason': 'Live marine data unavailable: TLS handshake failed',
        'latitude': 18.92,
        'longitude': 72.83,
      });

      expect(dto.hasError, isTrue);
      expect(dto.error, contains('TLS handshake failed'));
      expect(dto.waveHeightM, isNull);
      expect(dto.windKn, isNull);
      expect(dto.seaTempC, isNull);
      expect(dto.sources, isEmpty);
    });

    test('an errored payload produces an error provenance, never a value', () {
      final dto = MarineConditionsDto.fromJson(const {
        'error': true,
        'reason': 'Live marine data unavailable',
      });

      final prov = dto.provenanceFor('wave_height_m', hasValue: false);
      expect(prov.state, DataState.error);
      expect(prov.hasValue, isFalse);
      expect(prov.source, isNull, reason: 'no source may be invented');
    });
  });

  group('variable_provenance mapping', () {
    final healthy = MarineConditionsDto.fromJson(const {
      'wave_height_m': 1.4,
      'wind_speed_kn': 12.0,
      'sst_celsius': 28.1,
      'sources': ['Open-Meteo Marine (MFWAM/ECMWF)'],
      'sources_failed': ['INCOIS PFZ GeoServer'],
      'variable_provenance': {
        'wave_height_m': {
          'source': 'Open-Meteo Marine (MFWAM/ECMWF)',
          'temporal_type': 'MODEL_VALID',
          'valid_time': '2026-09-15T06:00:00Z',
          'retrieved_at': '2026-09-15T05:58:00Z',
          'status': 'FRESH',
        },
        'sst_celsius': {
          'source': 'NOAA ERDDAP',
          'temporal_type': 'OBSERVATION_TIME',
          'valid_time': '2026-09-15T04:00:00Z',
          'status': 'FRESH',
        },
      },
    });

    test('MODEL_VALID is reported as a forecast, not as live', () {
      final prov = healthy.provenanceFor('wave_height_m', hasValue: true);
      expect(prov.state, DataState.forecast);
      expect(prov.source, 'Open-Meteo Marine (MFWAM/ECMWF)');
      expect(prov.validAtLabel, 'Model valid');
      expect(prov.validAt, isNotNull);
    });

    test('OBSERVATION_TIME is reported as live with its observed label', () {
      final prov = healthy.provenanceFor('sst_celsius', hasValue: true);
      expect(prov.state, DataState.live);
      expect(prov.source, 'NOAA ERDDAP');
      expect(prov.validAtLabel, 'Observed');
    });

    test('a value with no published provenance claims no source', () {
      // wind_speed_kn has a value but no variable_provenance entry.
      final prov = healthy.provenanceFor('wind_speed_kn', hasValue: true);
      expect(prov.hasValue, isTrue);
      expect(prov.source, isNull,
          reason: 'an unattributed value must not borrow another source');
      expect(prov.validAtLabel, 'ORCA retrieved');
    });

    test('stale wins over the provider FRESH status', () {
      final prov =
          healthy.provenanceFor('wave_height_m', hasValue: true, stale: true);
      expect(prov.state, DataState.stale);
    });

    test('offline wins when there is no value', () {
      final prov = healthy.provenanceFor('chlorophyll_mg_m3',
          hasValue: false, offline: true);
      expect(prov.state, DataState.offline);
      expect(prov.hasValue, isFalse);
    });

    test('failed sources are surfaced verbatim', () {
      expect(healthy.sourcesFailed, ['INCOIS PFZ GeoServer']);
    });
  });

  group('SourceHealthDto status vocabulary', () {
    SourceHealthDto of(String status) => SourceHealthDto(
          key: 'k',
          name: 'n',
          status: status,
        );

    test('classifies the real backend statuses', () {
      expect(of('FRESH').isUsable, isTrue);
      expect(of('UNREACHABLE').isDown, isTrue);
      expect(of('UNAVAILABLE').isDown, isTrue);
      expect(of('UNVERIFIED').isUnverified, isTrue);
      // Credential/token gates are not outages and must not read as "down
      // right now" without qualification.
      expect(of('CREDENTIAL_REQUIRED').isUsable, isFalse);
      expect(of('TOKEN_REQUIRED').isUsable, isFalse);
    });

    test('an unusable source never reports a value-bearing state', () {
      expect(of('UNREACHABLE').dataState.hasValue, isFalse);
      expect(of('CREDENTIAL_REQUIRED').dataState.hasValue, isFalse);
    });
  });

  group('SystemHealthDto', () {
    test('parses the real /api/v1/health shape', () {
      final health = SystemHealthDto.fromJson(const {
        'status': 'PARTIAL_DATA_AVAILABILITY',
        'timestamp': 1789448602,
        'data_sources': {
          'open_meteo_marine': {
            'name': 'Open-Meteo Marine (MFWAM/ECMWF)',
            'status': 'UNREACHABLE',
            'latency_ms': null,
            'checked_at': 1789448274,
            'reason': 'TLS/SSL connection has been closed (EOF)',
          },
          'noaa_erddap': {
            'name': 'NOAA ERDDAP',
            'status': 'UNVERIFIED',
          },
        },
      });

      expect(health.sources, hasLength(2));
      expect(health.overall, 'PARTIAL DATA AVAILABILITY');
      expect(health.downCount, 1);
      expect(health.usableCount, 0);
      expect(health.timestamp, isNotNull);

      final marine =
          health.sources.firstWhere((s) => s.key == 'open_meteo_marine');
      expect(marine.reason, contains('TLS/SSL'));
      expect(marine.latencyMs, isNull);
    });

    test('an unreachable backend reports OFFLINE, not a healthy default', () {
      final health = SystemHealthDto.unreachable();
      expect(health.reachable, isFalse);
      expect(health.overall, 'OFFLINE');
      expect(health.sources, isEmpty);
    });
  });
}
