import '../../../../core/cache/staleness.dart';

/// Variable measurement item with provenance.
class VariableItem {
  final String key;
  final double? value;
  final String unit;
  final double? threshold;
  final String status;
  final String source;
  final String time;
  final String? timeLabel;
  final String? direction;

  const VariableItem({
    required this.key,
    required this.value,
    required this.unit,
    this.threshold,
    required this.status,
    required this.source,
    required this.time,
    this.timeLabel,
    this.direction,
  });
}

/// Hourly point for fl_chart forecast.
class HourlyPoint {
  final String hour;
  final double waveM;
  final double windKn;
  final String state;

  const HourlyPoint({
    required this.hour,
    required this.waveM,
    required this.windKn,
    required this.state,
  });
}

/// Safe departure window computed by the deterministic backend engine.
///
/// Every field is optional: the engine either publishes a window with its own
/// limits, or it publishes no window at all. The client never derives one.
class SafeWindow {
  final String from;
  final String to;
  final bool? isSafe;
  final String? status;
  final double? hoursRemaining;
  final String? quality;
  final double? maxWaveM;
  final double? maxWindKn;
  final double? maxGustKn;
  final String? note;
  final String? recommendationEn;
  final String? recommendationHi;

  const SafeWindow({
    required this.from,
    required this.to,
    required this.isSafe,
    this.status,
    this.hoursRemaining,
    this.quality,
    this.maxWaveM,
    this.maxWindKn,
    this.maxGustKn,
    this.note,
    this.recommendationEn,
    this.recommendationHi,
  });
}

/// Domain entity for Skipper Advisory (§4, §6).
class AdvisoryEntity {
  final String verdict; // go, caution, no_go
  final String colorHex;
  final String headline;
  final String? headlineHi;
  final String? headlineTe;
  final List<String> plainEn;
  final List<String> plainHi;
  final List<String> plainTe;
  final SafeWindow? safeWindow;
  final Map<String, VariableItem> variables;
  final List<HourlyPoint> hourlyChart;
  final List<String> sources;
  final List<String> sourcesFailed;
  final int knownSources;
  final int totalSources;
  final DateTime timestamp;
  final StalenessInfo staleness;

  String localizedHeadline(String languageCode) {
    if (languageCode == 'hi' && (headlineHi ?? '').isNotEmpty) return headlineHi!;
    if (languageCode == 'te' && (headlineTe ?? '').isNotEmpty) return headlineTe!;
    return headline;
  }

  List<String> localizedPlain(String languageCode) {
    if (languageCode == 'hi' && plainHi.isNotEmpty) return plainHi;
    if (languageCode == 'te' && plainTe.isNotEmpty) return plainTe;
    return plainEn;
  }

  const AdvisoryEntity({
    required this.verdict,
    required this.colorHex,
    required this.headline,
    this.headlineHi,
    this.headlineTe,
    required this.plainEn,
    required this.plainHi,
    this.plainTe = const [],
    this.safeWindow,
    required this.variables,
    required this.hourlyChart,
    required this.sources,
    required this.sourcesFailed,
    required this.knownSources,
    required this.totalSources,
    required this.timestamp,
    required this.staleness,
  });
}
