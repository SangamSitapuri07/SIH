library;

/// DTOs for the Command Center aggregate.
///
/// Every field is nullable on purpose: when the backend cannot supply a
/// value the UI must show "Unavailable", never a fabricated number.

/// Marine conditions parsed from GET /api/v1/zone (live spot snapshot).
class MarineConditionsDto {
  final double? waveHeightM;
  final double? swellPeriodS;
  final double? windKn;
  final double? windGustKn;
  final String? windDirection;
  final double? seaTempC;
  final double? chlorophyllMgM3;
  final List<String> sources;
  final List<String> sourcesFailed;
  final String? timestamp;
  final int pfzCount;
  final String? pfzSource;
  final String? error;

  const MarineConditionsDto({
    this.waveHeightM,
    this.swellPeriodS,
    this.windKn,
    this.windGustKn,
    this.windDirection,
    this.seaTempC,
    this.chlorophyllMgM3,
    this.sources = const [],
    this.sourcesFailed = const [],
    this.timestamp,
    this.pfzCount = 0,
    this.pfzSource,
    this.error,
  });

  factory MarineConditionsDto.fromJson(Map<String, dynamic> json) {
    int pfzCount = 0;
    String? pfzSource;
    final pfz = json['pfz'];
    if (pfz is List) {
      pfzCount = pfz.length;
      if (pfz.isNotEmpty && pfz.first is Map) {
        pfzSource = (pfz.first as Map)['source']?.toString();
      }
    }
    return MarineConditionsDto(
      waveHeightM: (json['wave_height_m'] as num?)?.toDouble(),
      swellPeriodS: (json['swell_period_s'] as num?)?.toDouble(),
      windKn: (json['wind_speed_kn'] as num?)?.toDouble(),
      windGustKn: (json['wind_gust_kn'] as num?)?.toDouble(),
      windDirection: json['wind_direction']?.toString(),
      seaTempC: (json['sea_temp_c'] as num?)?.toDouble(),
      chlorophyllMgM3: (json['chlorophyll_mg_m3'] as num?)?.toDouble(),
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      sourcesFailed: (json['sources_failed'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      timestamp: json['timestamp']?.toString(),
      pfzCount: pfzCount,
      pfzSource: pfzSource,
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'wave_height_m': waveHeightM,
        'swell_period_s': swellPeriodS,
        'wind_speed_kn': windKn,
        'wind_gust_kn': windGustKn,
        'wind_direction': windDirection,
        'sea_temp_c': seaTempC,
        'chlorophyll_mg_m3': chlorophyllMgM3,
        'sources': sources,
        'sources_failed': sourcesFailed,
        'timestamp': timestamp,
        'pfz_count': pfzCount,
        'pfz_source': pfzSource,
        'error': error,
      };

  factory MarineConditionsDto.fromJsonCached(Map<String, dynamic> json) {
    return MarineConditionsDto.fromJson(json);
  }
}

/// One backend source health entry from GET /api/v1/health.
class SourceHealthDto {
  final String key;
  final String name;
  final String status;
  final int? latencyMs;

  const SourceHealthDto({
    required this.key,
    required this.name,
    required this.status,
    this.latencyMs,
  });

  bool get isUsable =>
      status.toUpperCase().contains('FRESH') ||
      status.toUpperCase().contains('OK') ||
      status.toUpperCase().contains('AVAILABLE') ||
      status.toUpperCase().contains('CONFIGURED') ||
      status.toUpperCase().contains('CONNECTED');
}

/// System health parsed from GET /api/v1/health.
class SystemHealthDto {
  final List<SourceHealthDto> sources;
  final String? timestamp;
  final bool reachable;

  const SystemHealthDto({
    required this.sources,
    this.timestamp,
    this.reachable = true,
  });

  factory SystemHealthDto.fromJson(Map<String, dynamic> json) {
    final sources = <SourceHealthDto>[];
    json.forEach((key, value) {
      if (value is Map) {
        final name = value['name']?.toString() ?? key;
        final status = value['status']?.toString() ?? 'UNKNOWN';
        final latency = value['latency_ms'] as num?;
        sources.add(SourceHealthDto(
          key: key,
          name: name,
          status: status,
          latencyMs: latency?.toInt(),
        ));
      }
    });
    return SystemHealthDto(
      sources: sources,
      timestamp: json['timestamp']?.toString(),
    );
  }

  factory SystemHealthDto.unreachable() =>
      const SystemHealthDto(sources: [], reachable: false);

  /// Derived overall status — computed from real source states only.
  /// OPERATIONAL: majority of sources usable · PARTIAL: some down ·
  /// OFFLINE: backend unreachable.
  String get overall {
    if (!reachable) return 'OFFLINE';
    if (sources.isEmpty) return 'PARTIAL DATA AVAILABILITY';
    final usable = sources.where((s) => s.isUsable).length;
    if (usable == sources.length) return 'OPERATIONAL';
    if (usable > 0) return 'PARTIAL DATA AVAILABILITY';
    return 'DEGRADED';
  }
}

/// Cyclone watch item derived from real /api/v1/alerts entries only.
class CycloneWatchItem {
  final String title;
  final String source;
  final String severity;
  final String? time;

  const CycloneWatchItem({
    required this.title,
    required this.source,
    required this.severity,
    this.time,
  });

  factory CycloneWatchItem.fromJson(Map<String, dynamic> json) {
    return CycloneWatchItem(
      title: json['title']?.toString() ?? 'Marine alert',
      source: json['source']?.toString() ?? 'Official feed',
      severity: json['severity']?.toString() ?? 'advisory',
      time: json['time']?.toString(),
    );
  }
}

/// Aggregated command-center state served to the UI.
class CommandCenterData {
  final MarineConditionsDto? conditions;
  final SystemHealthDto? health;
  final List<CycloneWatchItem> cycloneWatch;
  final DateTime updatedAt;
  final bool offline;
  final bool stale;

  const CommandCenterData({
    this.conditions,
    this.health,
    this.cycloneWatch = const [],
    required this.updatedAt,
    this.offline = false,
    this.stale = false,
  });

  CommandCenterData copyWith({
    MarineConditionsDto? conditions,
    SystemHealthDto? health,
    List<CycloneWatchItem>? cycloneWatch,
    DateTime? updatedAt,
    bool? offline,
    bool? stale,
  }) {
    return CommandCenterData(
      conditions: conditions ?? this.conditions,
      health: health ?? this.health,
      cycloneWatch: cycloneWatch ?? this.cycloneWatch,
      updatedAt: updatedAt ?? this.updatedAt,
      offline: offline ?? this.offline,
      stale: stale ?? this.stale,
    );
  }
}
