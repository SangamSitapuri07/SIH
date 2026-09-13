import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/cache/staleness.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/widgets/orca_app_bar.dart';
import '../../data/datasources/advisory_remote.dart';
import '../../data/dto/advisory_dto.dart';
import '../../data/repositories/advisory_repo_impl.dart';
import '../../domain/entities/advisory.dart';
import '../../domain/repositories/advisory_repo.dart';
import '../../domain/usecases/get_advisory.dart';

/// Provider for AdvisoryRemoteDataSource.
final advisoryRemoteDataSourceProvider = Provider<AdvisoryRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return AdvisoryRemoteDataSource(dio);
});

/// Provider for AdvisoryRepository.
final advisoryRepositoryProvider = Provider<AdvisoryRepository>((ref) {
  final remote = ref.watch(advisoryRemoteDataSourceProvider);
  final cache = ref.watch(cacheServiceProvider);
  return AdvisoryRepositoryImpl(
    remoteDataSource: remote,
    cacheService: cache,
  );
});

/// Provider for GetAdvisoryUseCase.
final getAdvisoryUseCaseProvider = Provider<GetAdvisoryUseCase>((ref) {
  final repo = ref.watch(advisoryRepositoryProvider);
  return GetAdvisoryUseCase(repo);
});

/// Current advisory location coordinates.
final advisoryLocationProvider = StateProvider<Map<String, double>>((ref) {
  return {'lat': AppConfig.defaultLat, 'lon': AppConfig.defaultLon};
});

/// StateNotifier providing live / cached advisory state.
///
/// Startup sequence (stale-while-revalidate):
/// 1. Emit cached advisory immediately (any age) — no spinner if we have data.
/// 2. If cache was stale/missing, refresh from network in the background.
/// 3. On pull-to-refresh, keep current data on screen and swap in the new
///    advisory only when the fetch succeeds (no destructive spinner).
class AdvisoryNotifier extends StateNotifier<AsyncValue<AdvisoryEntity>> {
  final Ref _ref;
  final GetAdvisoryUseCase _useCase;
  final AdvisoryRepository _repository;

  /// Guards against overlapping refreshes and lost-update races.
  int _generation = 0;

  AdvisoryNotifier(
    this._ref,
    this._useCase,
    this._repository,
  ) : super(const AsyncValue.loading()) {
    _bootstrap();

    // Proactively refresh when SSE pushes data.updated event (§4, §16)
    _ref.listen(dataUpdatedStreamProvider, (prev, next) {
      next.whenData((_) {
        fetch();
      });
    });

    // Re-fetch if demo mode changes
    _ref.listen(demoModeProvider, (prev, next) {
      fetch(forceRefresh: true);
    });
  }

  Future<void> _bootstrap() async {
    final coords = _ref.read(advisoryLocationProvider);
    final lat = coords['lat'] ?? AppConfig.defaultLat;
    final lon = coords['lon'] ?? AppConfig.defaultLon;

    // 1. Instant paint from cache (any age).
    final cached = await _repository.getAdvisoryCached(lat: lat, lon: lon);
    if (!mounted) return;
    if (cached != null) {
      state = AsyncValue.data(cached);
    }

    // 2. Background network refresh.
    await fetch();
  }

  Future<void> fetch({bool forceRefresh = false}) async {
    final isDemo = _ref.read(demoModeProvider);
    final coords = _ref.read(advisoryLocationProvider);
    final lat = coords['lat'] ?? AppConfig.defaultLat;
    final lon = coords['lon'] ?? AppConfig.defaultLon;

    if (isDemo) {
      try {
        final raw = await rootBundle.loadString('assets/fixtures/advisory.json');
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final dto = AdvisoryDto.fromJson(json);
        final staleness = StalenessInfo.fromDateTime(DateTime.now());
        state = AsyncValue.data(dto.toEntity(staleness));
      } catch (e, st) {
        state = AsyncValue.error(e, st);
      }
      return;
    }

    // Only show the blocking spinner when there is nothing on screen yet.
    if (state.valueOrNull == null) {
      state = const AsyncValue.loading();
    }

    final generation = ++_generation;
    final result = await _useCase.execute(
      lat: lat,
      lon: lon,
      forceRefresh: forceRefresh,
    );

    // A newer request completed (or started) meanwhile — drop this result.
    if (generation != _generation) return;

    result.when(
      ok: (advisory) {
        state = AsyncValue.data(advisory);
      },
      err: (failure) {
        // Keep the current data on screen; only surface the error when the
        // screen would otherwise be empty.
        if (state.valueOrNull == null) {
          state = AsyncValue.error(failure.message, StackTrace.current);
        } else {
          debugPrint('Advisory refresh failed (${failure.message}) — keeping cached advisory.');
        }
      },
    );
  }
}

/// Provider managing Advisory state.
final advisoryProvider = StateNotifierProvider<AdvisoryNotifier, AsyncValue<AdvisoryEntity>>((ref) {
  final useCase = ref.watch(getAdvisoryUseCaseProvider);
  final repo = ref.watch(advisoryRepositoryProvider);
  return AdvisoryNotifier(ref, useCase, repo);
});
