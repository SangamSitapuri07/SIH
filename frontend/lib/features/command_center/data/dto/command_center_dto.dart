library;

import '../../../../core/design/data_state.dart';
import '../../../../core/utils/date_formatter.dart';

/// DTOs for the Command Center aggregate.
///
/// Every field is nullable on purpose: when the backend cannot supply a
/// value the UI must show "Unavailable", never a fabricated number.

/// Field-level provenance exactly as published by `/api/v1/zone`'s
/// `variable_provenance` block. Nothing here is synthesised client-side — if
/// the backend omits provenance for a variable, the variable is treated as
/// unattributed and rendered without a claimed source.
class VariableProvenanceDto {
  final String? source;
  final String? temporalType;
  final DateTime? validTime;
  final DateTime? retrievedAt;
  final String status;

  const VariableProvenanceDto({
    this.source,
    this.temporalType,
    this.validTime,
    this.retrievedAt,
    this.status = 'UNAVAILABLE',
  });

  static DateTime? _time(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000,
          isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  factory VariableProvenanceDto.fromJson(Map<String, dynamic> json) =>
      VariableProvenanceDto(
        source: json['source']?.toString(),
        temporalType: json['temporal_type']?.toString(),
        validTime: _time(json['valid_time']),
        retrievedAt: _time(json['retrieved_at']),
        status: json['status']?.toString().toUpperCase() ?? 'UNAVAILABLE',
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'temporal_type': temporalType,
        'valid_time': validTime?.toIso8601String(),
        'retrieved_at': retrievedAt?.toIso8601String(),
        'status': status,
      };

  /// Human label for [validTime], using the backend's own temporal vocabulary.
  String? get timeLabel => switch (temporalType) {
        'MODEL_VALID' => 'Model valid',
        'OBSERVATION_TIME' => 'Observed',
        'COVERAGE_PERIOD' => 'Coverage through',
        'RETRIEVED' => 'ORCA retrieved',
        _ => validTime != null ? 'Provider time' : null,
      };

  /// Builds the UI-facing [Provenance] for a value.
  ///
  /// [hasValue] must be true only when the numeric value itself is non-null.
  /// [cached]/[stale] reflect ORCA's own cache, and take precedence over a
  /// provider "FRESH" status, because a cached copy of fresh data is still a
  /// cached copy.
  Provenance toProvenance({
    required bool hasValue,
    bool cached = false,
    bool stale = false,
    bool offline = false,
  }) {
    if (!hasValue) {
      return Provenance(
        state: offline ? DataState.offline : DataState.unavailable,
        source: source,
        reason: offline
            ? 'Offline — no live provider response'
            : 'Provider published no value for this field',
      );
    }
    final DataState state;
    if (stale) {
      state = DataState.stale;
    } else if (cached || status == 'CACHED') {
      state = DataState.cached;
    } else if (temporalType == 'MODEL_VALID') {
      // Open-Meteo marine/forecast fields are model values, not observations.
      state = DataState.forecast;
    } else {
      state = DataState.live;
    }
    return Provenance(
      state: state,
      source: source,
      validAt: validTime,
      validAtLabel: timeLabel,
      retrievedAt: retrievedAt,
    );
  }
}

/// Marine conditions parsed from GET /api/v1/zone (live spot snapshot).
class MarineConditionsDto {
  final double? waveHeightM;
  final double? swellPeriodS;
  final double? windKn;
  final double? windGustKn;
  final String? windDirection;
  final double? seaTempC;
  final double? currentSpeedKn;
  final double? chlorophyllMgM3;
  final List<String> sources;
  final List<String> sourcesFailed;
  final Map<String, VariableProvenanceDto> provenance;
  final DateTime? timestamp;
  final bool isCached;
  final int pfzCount;
  final String? pfzSource;

  /// True when `/api/v1/zone` answered with its `{"error": true}` envelope.
  final bool hasError;
  final String? error;

  const MarineConditionsDto({
    this.waveHeightM,
    this.swellPeriodS,
    this.windKn,
    this.windGustKn,
    this.windDirection,
    this.seaTempC,
    this.currentSpeedKn,
    this.chlorophyllMgM3,
    this.sources = const [],
    this.sourcesFailed = const [],
    this.provenance = const {},
    this.timestamp,
    this.isCached = false,
    this.pfzCount = 0,
    this.pfzSource,
    this.hasError = false,
    this.error,
  });

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000,
          isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  factory MarineConditionsDto.fromJson(Map<String, dynamic> json,
      {bool cached = false}) {
    // `/api/v1/zone` returns HTTP 200 with an error envelope when the upstream
    // marine providers are unreachable. That is a *data unavailable* state,
    // not a set of readings, so nothing numeric is parsed out of it.
    if (json['error'] == true) {
      return MarineConditionsDto(
        hasError: true,
        error: json['reason']?.toString() ??
            'Live marine data is unavailable for this location.',
        isCached: cached,
      );
    }

    int pfzCount = 0;
    String? pfzSource;
    final pfz = json['pfz'];
    if (pfz is List) {
      pfzCount = pfz.length;
      if (pfz.isNotEmpty && pfz.first is Map) {
        pfzSource = (pfz.first as Map)['source']?.toString();
      }
    }
    final sourceNames =
        (json['sources'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    for (final name in sourceNames) {
      if (pfzSource == null && name.toLowerCase().contains('incois')) {
        pfzSource = name;
      }
    }

    final provenance = <String, VariableProvenanceDto>{};
    final rawProvenance = json['variable_provenance'];
    if (rawProvenance is Map) {
      rawProvenance.forEach((key, value) {
        if (value is Map) {
          provenance[key.toString()] = VariableProvenanceDto.fromJson(
              Map<String, dynamic>.from(value));
        }
      });
    }

    return MarineConditionsDto(
      waveHeightM: (json['wave_height_m'] as num?)?.toDouble(),
      swellPeriodS: (json['swell_period_s'] as num?)?.toDouble(),
      windKn: (json['wind_speed_kn'] as num?)?.toDouble(),
      windGustKn: (json['wind_gust_kn'] as num?)?.toDouble(),
      windDirection: json['wind_direction']?.toString(),
      seaTempC: (json['sea_temp_c'] as num?)?.toDouble(),
      currentSpeedKn: (json['current_speed_kn'] as num?)?.toDouble(),
      chlorophyllMgM3: (json['chlorophyll_mg_m3'] as num?)?.toDouble(),
      sources: sourceNames,
      sourcesFailed: (json['sources_failed'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      provenance: provenance,
      timestamp: _parseTimestamp(json['timestamp']),
      isCached: cached || json['cached'] == true,
      pfzCount: pfzCount,
      pfzSource: pfzSource,
    );
  }

  Map<String, dynamic> toJson() => {
        if (hasError) 'error': true,
        if (hasError) 'reason': error,
        'wave_height_m': waveHeightM,
        'swell_period_s': swellPeriodS,
        'wind_speed_kn': windKn,
        'wind_gust_kn': windGustKn,
        'wind_direction': windDirection,
        'sea_temp_c': seaTempC,
        'current_speed_kn': currentSpeedKn,
        'chlorophyll_mg_m3': chlorophyllMgM3,
        'sources': sources,
        'sources_failed': sourcesFailed,
        'variable_provenance': {
          for (final entry in provenance.entries) entry.key: entry.value.toJson(),
        },
        'timestamp': timestamp?.toIso8601String(),
        'cached': isCached,
        'pfz': List<Map<String, dynamic>>.generate(
          pfzCount,
          (_) => {if (pfzSource != null) 'source': pfzSource},
        ),
      };

  factory MarineConditionsDto.fromJsonCached(Map<String, dynamic> json) =>
      MarineConditionsDto.fromJson(json, cached: true);

  /// Provenance for one variable key, honouring cache/stale/offline context.
  Provenance provenanceFor(
    String key, {
    required bool hasValue,
    bool stale = false,
    bool offline = false,
  }) {
    final entry = provenance[key];
    if (entry == null) {
      if (!hasValue) {
        return Provenance(
          state: offline
              ? DataState.offline
              : hasError
                  ? DataState.error
                  : DataState.unavailable,
          reason: error ??
              (offline
                  ? 'Offline — no live provider response'
                  : 'Provider published no value for this field'),
        );
      }
      // A value with no published provenance must not be given a plausible
      // source; it is shown with an explicit gap instead.
      return Provenance(
        state: stale
            ? DataState.stale
            : isCached
                ? DataState.cached
                : DataState.live,
        retrievedAt: timestamp,
        validAtLabel: 'ORCA retrieved',
      );
    }
    return entry.toProvenance(
      hasValue: hasValue,
      cached: isCached,
      stale: stale,
      offline: offline,
    );
  }
}

/// One backend source health entry from GET /api/v1/health.
class SourceHealthDto {
  final String key;
  final String name;
  final String status;
  final int? latencyMs;
  final String? reason;
  final DateTime? checkedAt;

  const SourceHealthDto({
    required this.key,
    required this.name,
    required this.status,
    this.latencyMs,
    this.reason,
    this.checkedAt,
  });

  String get normalizedStatus => status.toUpperCase();

  /// Provider is currently usable as a data source.
  bool get isUsable => const {'FRESH', 'CACHED', 'AVAILABLE', 'CONNECTED'}
      .contains(normalizedStatus);

  /// Provider is definitively down or unconfigured.
  bool get isDown => const {
        'UNREACHABLE',
        'FAILED',
        'UNAVAILABLE',
        'CREDENTIAL_REQUIRED',
        'TOKEN_REQUIRED',
      }.contains(normalizedStatus);

  /// Provider has simply not been probed yet in this backend session.
  bool get isUnverified =>
      const {'UNVERIFIED', 'CONFIGURED', 'IDLE'}.contains(normalizedStatus);

  DataState get dataState {
    if (isUsable) {
      return normalizedStatus == 'CACHED' ? DataState.cached : DataState.live;
    }
    if (isDown) return DataState.error;
    return DataState.unavailable;
  }
}

/// System health parsed from GET /api/v1/health.
class SystemHealthDto {
  final List<SourceHealthDto> sources;
  final DateTime? timestamp;
  final String? backendStatus;
  final bool reachable;

  const SystemHealthDto({
    required this.sources,
    this.timestamp,
    this.backendStatus,
    this.reachable = true,
  });

  static DateTime? _time(dynamic value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000,
          isUtc: true);
    }
    return DateFormatter.parseIso(value);
  }

  factory SystemHealthDto.fromJson(Map<String, dynamic> json) {
    final sources = <SourceHealthDto>[];
    final rawSources = json['data_sources'];
    if (rawSources is Map) {
      rawSources.forEach((key, value) {
        if (value is Map) {
          sources.add(SourceHealthDto(
            key: key.toString(),
            name: value['name']?.toString() ?? key.toString(),
            status: value['status']?.toString() ?? 'UNVERIFIED',
            latencyMs: (value['latency_ms'] as num?)?.toInt(),
            reason: value['reason']?.toString(),
            checkedAt: _time(value['checked_at']),
          ));
        }
      });
    }
    return SystemHealthDto(
      sources: sources,
      timestamp: _time(json['timestamp']),
      backendStatus: json['status']?.toString(),
    );
  }

  factory SystemHealthDto.unreachable() =>
      const SystemHealthDto(sources: [], reachable: false);

  int get usableCount => sources.where((s) => s.isUsable).length;
  int get downCount => sources.where((s) => s.isDown).length;

  /// Derived overall status — computed from real source states only.
  String get overall {
    if (!reachable) return 'OFFLINE';
    return backendStatus?.replaceAll('_', ' ') ?? 'UNVERIFIED';
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
    final title = json['title']?.toString();
    final source = json['source']?.toString();
    if (title == null ||
        title.trim().isEmpty ||
        source == null ||
        source.trim().isEmpty) {
      throw const FormatException('Cyclone alert is missing provider provenance.');
    }
    return CycloneWatchItem(
      title: title,
      source: source,
      severity: json['severity']?.toString() ?? 'UNSPECIFIED',
      time: (json['issued_at'] ?? json['time'])?.toString(),
    );
  }
}

/// Aggregated command-center state served to the UI.
class CommandCenterData {
  final MarineConditionsDto? conditions;
  final SystemHealthDto? health;
  final List<CycloneWatchItem> cycloneWatch;

  /// True only when the official alert endpoint responded for this refresh.
  final bool cycloneFeedAvailable;

  /// True only when `/api/v1/alerts` itself answered (200), regardless of
  /// whether it returned any alerts.
  final bool alertsFeedAvailable;
  final DateTime? updatedAt;
  final bool offline;
  final bool stale;
  final bool cached;

  const CommandCenterData({
    this.conditions,
    this.health,
    this.cycloneWatch = const [],
    this.cycloneFeedAvailable = false,
    this.alertsFeedAvailable = false,
    this.updatedAt,
    this.offline = false,
    this.stale = false,
    this.cached = false,
  });

  CommandCenterData copyWith({
    MarineConditionsDto? conditions,
    SystemHealthDto? health,
    List<CycloneWatchItem>? cycloneWatch,
    bool? cycloneFeedAvailable,
    bool? alertsFeedAvailable,
    DateTime? updatedAt,
    bool? offline,
    bool? stale,
    bool? cached,
  }) {
    return CommandCenterData(
      conditions: conditions ?? this.conditions,
      health: health ?? this.health,
      cycloneWatch: cycloneWatch ?? this.cycloneWatch,
      cycloneFeedAvailable: cycloneFeedAvailable ?? this.cycloneFeedAvailable,
      alertsFeedAvailable: alertsFeedAvailable ?? this.alertsFeedAvailable,
      updatedAt: updatedAt ?? this.updatedAt,
      offline: offline ?? this.offline,
      stale: stale ?? this.stale,
      cached: cached ?? this.cached,
    );
  }
}
