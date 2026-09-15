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
  final bool isCached;

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
    this.isCached = false,
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

  static List<String> _sourceNames(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((entry) {
      if (entry is Map) return entry['name'] ?? entry['source'];
      return entry;
    }).whereType<Object>().map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty).toList();
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
    final sourcesList = _sourceNames(json['sources']);

    final coverage = json['data_coverage'] as Map<String, dynamic>?;
    final failedList = _sourceNames(coverage?['sources_failed']);

    return AdvisoryDto(
      verdict: json['verdict'] as String? ?? 'unknown',
      color: json['color'] as String?,
      headline: json['headline'] as String? ?? 'Advisory verdict unavailable.',
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
      isCached: json['cached'] == true,
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
            status: val['status'] as String? ?? 'UNAVAILABLE',
            source: val['source'] as String? ?? 'Source unavailable',
            time: val['time']?.toString() ?? 'Time unavailable',
            timeLabel: val['time_label']?.toString(),
            direction: val['direction'] as String?,
          );
        }
      });
    }

    final parsedHourly = <HourlyPoint>[];
    if (hourlyChartJson != null) {
      for (final item in hourlyChartJson!) {
        if (item is Map<String, dynamic>) {
          final wave = (item['wave_m'] as num?)?.toDouble();
          final wind = (item['wind_kn'] as num?)?.toDouble();
          final hour = item['hour']?.toString();
          if (wave != null && wind != null && hour != null) {
            parsedHourly.add(HourlyPoint(
              hour: hour,
              waveM: wave,
              windKn: wind,
              state: item['state']?.toString() ?? 'UNAVAILABLE',
            ));
          }
        }
      }
    }

    SafeWindow? parsedSafeWindow;
    if (safeWindowJson != null) {
      final Map<String, dynamic> window = safeWindowJson!;
      parsedSafeWindow = SafeWindow(
        from: (window['from'] ?? window['start'] ?? window['start_time'])?.toString() ?? '',
        to: (window['to'] ?? window['end'] ?? window['end_time'])?.toString() ?? '',
        isSafe: (window['is_safe'] ?? window['currently_safe']) as bool?,
        status: window['status']?.toString(),
        hoursRemaining: ((window['hours_remaining'] ?? window['duration_hours']) as num?)?.toDouble(),
        quality: window['window_quality']?.toString(),
        maxWaveM: (window['max_wave_m'] as num?)?.toDouble(),
        maxWindKn: (window['max_wind_kn'] as num?)?.toDouble(),
        maxGustKn: (window['max_gust_kn'] as num?)?.toDouble(),
        note: window['note']?.toString(),
        recommendationEn: window['recommendation_en']?.toString(),
        recommendationHi: window['recommendation_hi']?.toString(),
      );
    }

    final ts = timestamp;
    if (ts == null) {
      throw const FormatException('Advisory response is missing its source timestamp.');
    }

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
