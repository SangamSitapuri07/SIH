import 'package:flutter_test/flutter_test.dart';
import 'package:orca_app/core/cache/staleness.dart';
import 'package:orca_app/features/map/data/dto/zone_dto.dart';

void main() {
  test('parses zone epoch timestamp from the live map response', () {
    final dto = ZoneDto.fromJson(<String, dynamic>{
      'lat': 18.92,
      'lon': 72.83,
      'timestamp': 1789219312,
    });

    expect(dto.timestamp, DateTime.utc(2026, 9, 12, 13, 21, 52));
    expect(
      dto.toEntity(StalenessInfo.fromDateTime(DateTime.now())).timestamp,
      DateTime.utc(2026, 9, 12, 13, 21, 52),
    );
  });

  test('keeps ISO zone timestamps and tolerates null timestamps', () {
    final isoDto = ZoneDto.fromJson(<String, dynamic>{
      'timestamp': '2026-09-12T08:30:00Z',
    });
    final nullDto = ZoneDto.fromJson(<String, dynamic>{
      'timestamp': null,
    });

    expect(isoDto.timestamp, DateTime.utc(2026, 9, 12, 8, 30));
    expect(nullDto.timestamp, isNull);
  });
}
