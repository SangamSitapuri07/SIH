import '../../domain/entities/advisory.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/utils/date_formatter.dart';

/// DTO for /api/v1/advisory response.
class AdvisoryDto {
  final String verdict;
  final String? color;
  final String headline;
  final String? headlineHi;
  final List<String> plainEn;
  final List<String> plainHi;
  final Map<String, dynamic>? safeWindowJson;
  final Map<String, dynamic>? variablesJson;
  final List<dynamic>? hourlyChartJson;
  final List<String> sources;
  final List<String> sourcesFailed;
  final int knownSources;
  final int totalSources;
  final DateTime? timestamp;

  AdvisoryDto({
    required this.verdict,
    this.color,
    required this.headline,
    this.headlineHi,
    required this.plainEn,
    required this.plainHi,
    this.safeWindowJson,
    this.variablesJson,
    this.hourlyChartJson,
    required this.sources,
    required this.sourcesFailed,
    required this.knownSources,
    required this.totalSources,
    this.timestamp,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  factory AdvisoryDto.fromJson(Map<String, dynamic> json) {
    final plainEnList = (json['plain_en'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final plainHiList = (json['plain_hi'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final sourcesList = (json['sources'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final coverage = json['data_coverage'] as Map<String, dynamic>?;
    final failedList = (coverage?['sources_failed'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    return AdvisoryDto(
      verdict: json['verdict'] as String? ?? 'unknown',
      color: json['color'] as String?,
      headline: json['headline'] as String? ?? 'Advisory data loaded.',
      headlineHi: json['headline_hi'] as String?,
      plainEn: plainEnList,
      plainHi: plainHiList,
      safeWindowJson: json['safe_window'] as Map<String, dynamic>?,
      variablesJson: json['variables'] as Map<String, dynamic>?,
      hourlyChartJson: json['hourly_chart'] as List<dynamic>?,
      sources: sourcesList,
      sourcesFailed: failedList,
      knownSources: coverage?['known'] as int? ?? sourcesList.length,
      totalSources: coverage?['total'] as int? ?? (sourcesList.length + failedList.length),
      timestamp: _parseTimestamp(json['timestamp']),
    );
  }

  /// Named constructor mapper from DTO to domain Entity (§10).
  AdvisoryEntity toEntity(StalenessInfo staleness) {
    final parsedVariables = <String, VariableItem>{};
    if (variablesJson != null) {
      variablesJson!.forEach((key, val) {
        if (val is Map<String, dynamic>) {
          parsedVariables[key] = VariableItem(
            key: key,
            value: (val['value'] as num?)?.toDouble(),
            unit: val['unit'] as String? ?? '',
            threshold: (val['threshold'] as num?)?.toDouble(),
            status: val['status'] as String? ?? 'good',
            source: val['source'] as String? ?? 'External Model',
            time: val['time'] as String? ?? 'Now',
            direction: val['direction'] as String?,
          );
        } else if (val is num) {
          final unit = switch (key) {
            'wave_height_m' || 'swell_height_m' => 'm',
            'wave_period_s' => 's',
            'wind_speed_kn' || 'wind_gust_kn' || 'current_speed_kn' => 'kn',
            'sst_celsius' => 'C',
            'chlorophyll_mg_m3' => 'mg/m3',
            _ => '',
          };
          parsedVariables[key] = VariableItem(
            key: key,
            value: val.toDouble(),
            unit: unit,
            status: 'good',
            source: 'ORCA Box',
            time: 'Live',
          );
        }
      });
    }

    final parsedHourly = <HourlyPoint>[];
    if (hourlyChartJson != null) {
      for (final item in hourlyChartJson!) {
        if (item is Map<String, dynamic>) {
          parsedHourly.add(
            HourlyPoint(
              hour: item['hour'] as String? ?? '--',
              waveM: (item['wave_m'] as num?)?.toDouble() ?? 0.0,
              windKn: (item['wind_kn'] as num?)?.toDouble() ?? 0.0,
              state: item['state'] as String? ?? 'good',
            ),
          );
        }
      }
    }

    SafeWindow? parsedSafeWindow;
    if (safeWindowJson != null) {
      parsedSafeWindow = SafeWindow(
        from: safeWindowJson!['from'] as String? ?? safeWindowJson!['start'] as String? ?? '',
        to: safeWindowJson!['to'] as String? ?? safeWindowJson!['end'] as String? ?? '',
        isSafe: safeWindowJson!['is_safe'] as bool? ?? true,
        hoursRemaining: (safeWindowJson!['hours_remaining'] as num?)?.toDouble(),
      );
    }

    final ts = timestamp ?? DateTime.now();

    return AdvisoryEntity(
      verdict: verdict,
      colorHex: color ?? '#94a3b8',
      headline: headline,
      headlineHi: headlineHi,
      plainEn: plainEn,
      plainHi: plainHi,
      safeWindow: parsedSafeWindow,
      variables: parsedVariables,
      hourlyChart: parsedHourly,
      sources: sources,
      sourcesFailed: sourcesFailed,
      knownSources: knownSources,
      totalSources: totalSources,
      timestamp: ts,
      staleness: staleness,
    );
  }
}
