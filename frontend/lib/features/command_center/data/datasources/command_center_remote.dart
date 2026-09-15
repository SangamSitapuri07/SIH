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

  Future<SystemHealthDto> getHealth() async {
    final res = await _dio.get<dynamic>(ApiPaths.health);
    if (res.data is! Map<String, dynamic>) {
      throw const FormatException('health: unexpected response shape');
    }
    return SystemHealthDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<CycloneWatchItem>> getCycloneWatch() async {
    final res = await _dio.get<dynamic>(ApiPaths.alerts);
    final rawList = res.data is Map<String, dynamic>
        ? (res.data['alerts'] as List<dynamic>? ?? <dynamic>[])
        : res.data as List<dynamic>? ?? <dynamic>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(CycloneWatchItem.fromJson)
        .toList();
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
          data.copyWith(stale: cached.isExpired, offline: !_isOnline),
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
      final results = await Future.wait([
        ds.getConditions(lat, lon),
        ds.getHealth(),
        ds.getCycloneWatch(),
      ]);
      final data = CommandCenterData(
        conditions: results[0] as MarineConditionsDto,
        health: results[1] as SystemHealthDto,
        cycloneWatch: results[2] as List<CycloneWatchItem>,
        updatedAt: DateTime.now().toUtc(),
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
                  })
              .toList(),
          'timestamp': d.health?.timestamp,
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
        'updated_at': d.updatedAt.toIso8601String(),
      };

  CommandCenterData _fromCachedJson(Map<String, dynamic> j) {
    final healthJson = j['health'] as Map<String, dynamic>? ?? {};
    return CommandCenterData(
      conditions: j['conditions'] is Map<String, dynamic>
          ? MarineConditionsDto.fromJsonCached(
              j['conditions'] as Map<String, dynamic>)
          : null,
      health: SystemHealthDto.fromJson(healthJson),
      cycloneWatch: (j['cyclone'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CycloneWatchItem.fromJson)
          .toList(),
      updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ??
          DateTime.now().toUtc(),
    );
  }
}

final commandCenterProvider = StateNotifierProvider<CommandCenterNotifier,
    AsyncValue<CommandCenterData>>((ref) {
  return CommandCenterNotifier(ref);
});
