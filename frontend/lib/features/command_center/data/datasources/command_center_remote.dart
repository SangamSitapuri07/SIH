import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/cache_service.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/offline/connectivity_watcher.dart';
import '../../../../core/live/live_channel.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart'
    show advisoryLocationProvider;
import '../dto/command_center_dto.dart';

/// Alert-feed availability is separate from the visible cyclone list: an
/// empty list is meaningful only when a cyclone provider answered.
class CycloneWatchResponse {
  final List<CycloneWatchItem> alerts;

  /// True only when a *cyclone* provider (GDACS/JTWC) reported `fresh`.
  final bool feedAvailable;

  /// True when `/api/v1/alerts` itself answered. The endpoint returns 503 when
  /// no official feed could be verified, so a 200 is the only evidence that
  /// "no alerts" is a real answer rather than an outage.
  final bool endpointAvailable;

  const CycloneWatchResponse({
    required this.alerts,
    required this.feedAvailable,
    this.endpointAvailable = true,
  });

  const CycloneWatchResponse.unavailable()
      : alerts = const [],
        feedAvailable = false,
        endpointAvailable = false;
}

/// Data source for the Command Center aggregate.
///
/// Endpoints (all real ORCA backend):
///   GET /api/v1/zone    — live marine conditions at the working location
///   GET /api/v1/health  — per-source system health
///   GET /api/v1/alerts  — official alerts (cyclone watch derives from these)
class CommandCenterRemoteDataSource {
  final Dio _dio;

  CommandCenterRemoteDataSource(this._dio);

  Future<MarineConditionsDto> getConditions(double lat, double lon) async {
    final res = await _dio.get<dynamic>(
      ApiPaths.zone,
      queryParameters: {'lat': lat, 'lon': lon},
    );
    if (res.data is! Map<String, dynamic>) {
      throw const FormatException('zone: unexpected response shape');
    }
    return MarineConditionsDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SystemHealthDto> getHealth({bool probe = false}) async {
    final res = await _dio.get<dynamic>(
      ApiPaths.health,
      queryParameters: <String, dynamic>{if (probe) 'probe': true},
    );
    if (res.data is! Map<String, dynamic>) {
      throw const FormatException('health: unexpected response shape');
    }
    return SystemHealthDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CycloneWatchResponse> getCycloneWatch() async {
    final res = await _dio.get<dynamic>(ApiPaths.alerts);
    final body = res.data;
    final rawList = body is Map<String, dynamic>
        ? (body['alerts'] as List<dynamic>? ?? <dynamic>[])
        : body as List<dynamic>? ?? <dynamic>[];
    final sourceStatus = body is Map<String, dynamic>
        ? body['source_status'] as Map<String, dynamic>?
        : null;
    final cycloneFeedAvailable = sourceStatus?['GDACS']?.toString() == 'fresh' ||
        sourceStatus?['JTWC']?.toString() == 'fresh';
    final alerts = rawList
        .whereType<Map<String, dynamic>>()
        .where((item) {
          final source = item['source']?.toString().toLowerCase() ?? '';
          final title = item['title']?.toString().toLowerCase() ?? '';
          return source.contains('gdacs') ||
              source.contains('jtwc') ||
              title.contains('cyclone') ||
              title.contains('tropical storm') ||
              title.contains('tropical cyclone');
        })
        .map(CycloneWatchItem.fromJson)
        .toList();
    return CycloneWatchResponse(
      alerts: alerts,
      feedAvailable: cycloneFeedAvailable,
      endpointAvailable: true,
    );
  }
}

final commandCenterRemoteDataSourceProvider =
    Provider<CommandCenterRemoteDataSource>((ref) {
  return CommandCenterRemoteDataSource(ref.watch(dioProvider));
});

/// Notifier powering the Command Center (Home) screen.
///
/// Caching contract:
///  - serves the last good cached payload instantly (Hive, TTL 10 min)
///  - refreshes from the network in the background
///  - keeps old data visible on refresh failure, marks it stale instead —
///    never fabricates, never shows stale as fresh
class CommandCenterNotifier
    extends StateNotifier<AsyncValue<CommandCenterData>> {
  final Ref _ref;
  static const _cacheKey = 'command_center.latest';
  static const _ttl = Duration(minutes: 10);

  CommandCenterNotifier(this._ref) : super(const AsyncValue.loading()) {
    _bootstrap();
    _ref.listen(advisoryLocationProvider, (prev, next) {
      if (prev != next) _refresh(fromPull: false);
    });
    _ref.listen(dataUpdatedStreamProvider, (prev, next) {
      next.whenData((_) => _refresh(fromPull: false));
    });
  }

  Future<void> refresh() => _refresh(fromPull: true);

  Future<void> _bootstrap() async {
    // 1. Instant paint from cache (any age).
    final cached = _ref.read(cacheServiceProvider).get(_cacheKey);
    if (cached != null) {
      try {
        final data = _fromCachedJson(cached.data);
        state = AsyncValue.data(
          data.copyWith(stale: cached.isExpired, offline: !_isOnline, cached: true),
        );
      } catch (_) {
        // Corrupt cache — fall through to network.
      }
    }
    // 2. Background refresh.
    await _refresh(fromPull: false);
  }

  bool get _isOnline => _ref.read(isOnlineProvider);

  Future<void> _refresh({required bool fromPull}) async {
    // Keep current data on screen; only show a spinner when empty.
    if (state.valueOrNull == null && !_isOnline) {
      state = AsyncValue.error('offline', StackTrace.current);
      return;
    }

    final coords = _ref.read(advisoryLocationProvider);
    final lat = coords['lat'] ?? AppConfig.defaultLat;
    final lon = coords['lon'] ?? AppConfig.defaultLon;

    try {
      final ds = _ref.read(commandCenterRemoteDataSourceProvider);
      // The alert feed is an independent, optional source. Its outage must
      // not hide otherwise verified conditions or source-health data.
      final conditionsFuture = ds.getConditions(lat, lon);
      // Pull-to-refresh explicitly probes authenticated/remote providers;
      // background refreshes remain fast and report the latest observed state.
      final healthFuture = ds.getHealth(probe: fromPull);
      final cycloneFuture = ds.getCycloneWatch()
          .catchError((_) => const CycloneWatchResponse.unavailable());
      final core = await Future.wait([conditionsFuture, healthFuture]);
      final cyclone = await cycloneFuture;
      final conditions = core[0] as MarineConditionsDto;
      final data = CommandCenterData(
        conditions: conditions,
        health: core[1] as SystemHealthDto,
        cycloneWatch: cyclone.alerts,
        cycloneFeedAvailable: cyclone.feedAvailable,
        alertsFeedAvailable: cyclone.endpointAvailable,
        updatedAt: conditions.timestamp,
        offline: !_isOnline,
        cached: conditions.isCached,
      );
      state = AsyncValue.data(data);
      await _ref.read(cacheServiceProvider).put(_cacheKey, _toCacheJson(data),
          ttl: _ttl);
    } catch (e) {
      // Failure: keep last good data on screen, flag staleness honestly.
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(
          current.copyWith(
            stale: true,
            offline: !_isOnline,
          ),
        );
      } else if (state is AsyncLoading || state.valueOrNull == null) {
        state = AsyncValue.error(
          _isOnline ? 'Data source temporarily unavailable' : 'Offline',
          StackTrace.current,
        );
      }
      debugPrint('CommandCenter refresh failed: $e');
    }
  }

  Map<String, dynamic> _toCacheJson(CommandCenterData d) => {
        'conditions': d.conditions?.toJson(),
        'health': {
          'sources': d.health?.sources
              .map((s) => {
                    'key': s.key,
                    'name': s.name,
                    'status': s.status,
                    'latency_ms': s.latencyMs,
                    'reason': s.reason,
                    'checked_at': s.checkedAt?.toIso8601String(),
                  })
              .toList(),
          'timestamp': d.health?.timestamp?.toIso8601String(),
          'status': d.health?.backendStatus,
          'reachable': d.health?.reachable,
        },
        'cyclone': d.cycloneWatch
            .map((c) => {
                  'title': c.title,
                  'source': c.source,
                  'severity': c.severity,
                  'time': c.time,
                })
            .toList(),
        'cyclone_feed_available': d.cycloneFeedAvailable,
        'alerts_feed_available': d.alertsFeedAvailable,
        'updated_at': d.updatedAt?.toIso8601String(),
      };

  CommandCenterData _fromCachedJson(Map<String, dynamic> j) {
    final healthJson = j['health'] as Map<String, dynamic>? ?? {};
    return CommandCenterData(
      conditions: j['conditions'] is Map<String, dynamic>
          ? MarineConditionsDto.fromJsonCached(
              j['conditions'] as Map<String, dynamic>)
          : null,
      health: SystemHealthDto.fromJson({
        'status': healthJson['status'],
        'timestamp': healthJson['timestamp'],
        'data_sources': {
          for (final source in healthJson['sources'] as List<dynamic>? ?? const <dynamic>[])
            if (source is Map) source['key']?.toString() ?? 'unknown': source,
        },
      }),
      cycloneWatch: (j['cyclone'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CycloneWatchItem.fromJson)
          .toList(),
      cycloneFeedAvailable: j['cyclone_feed_available'] == true,
      alertsFeedAvailable: j['alerts_feed_available'] == true,
      updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? ''),
    );
  }
}

final commandCenterProvider = StateNotifierProvider<CommandCenterNotifier,
    AsyncValue<CommandCenterData>>((ref) {
  return CommandCenterNotifier(ref);
});
