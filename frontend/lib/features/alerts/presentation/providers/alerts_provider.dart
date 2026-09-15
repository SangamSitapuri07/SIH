import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/notifications/notification_service.dart';
import '../../data/datasources/alerts_remote.dart';
import '../../data/dto/alert_dto.dart';
import '../../data/repositories/alerts_repo_impl.dart';
import '../../domain/entities/alert_item.dart';
import '../../domain/repositories/alerts_repo.dart';
import '../../domain/usecases/get_alerts.dart';

/// Provider for AlertsRemoteDataSource.
final alertsRemoteDataSourceProvider = Provider<AlertsRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return AlertsRemoteDataSource(dio);
});

/// Provider for AlertsRepository.
final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  final remote = ref.watch(alertsRemoteDataSourceProvider);
  return AlertsRepositoryImpl(remoteDataSource: remote, cacheService: ref.watch(cacheServiceProvider));
});

/// Provider for GetAlertsUseCase.
final getAlertsUseCaseProvider = Provider<GetAlertsUseCase>((ref) {
  final repo = ref.watch(alertsRepositoryProvider);
  return GetAlertsUseCase(repo);
});

/// StateNotifier managing active marine alerts with SSE subscription.
class AlertsNotifier extends StateNotifier<AsyncValue<List<AlertItem>>> {
  final Ref _ref;
  final GetAlertsUseCase _useCase;

  AlertsNotifier(this._ref, this._useCase) : super(const AsyncValue.loading()) {
    fetch();

    // Listen to live SSE alert.push events (§4, §16) — render in the feed
    // AND surface as an OS notification (Phase B proactive alerting).
    _ref.listen(alertPushStreamProvider, (prev, next) {
      next.whenData((event) {
        final data = event.jsonData;
        if (data is Map<String, dynamic>) {
          final dto = AlertDto.fromJson(data);
          final item = dto.toEntity();

          // Dedupe: the SSE stream may redeliver the same alert id after a
          // reconnect (the replay/keepalive path) — show it once.
          final current = state.valueOrNull ?? <AlertItem>[];
          final alreadyKnown = current.any((a) => a.id == item.id);
          if (!alreadyKnown) {
            state = AsyncValue.data(<AlertItem>[item, ...current]);
            NotificationService.instance.showAlertNotification(
              id: item.id,
              title: item.title,
              body: item.message,
              severity: item.severity ?? 'warning',
            );
          }
        }
      });
    });

  }

  Future<void> fetch({bool forceRefresh = false}) async {
    state = const AsyncValue.loading();
    final result = await _useCase.execute(forceRefresh: forceRefresh);
    result.when(
      ok: (alerts) {
        state = AsyncValue.data(alerts);
        // Records the real completion time of the last feed read so screens can
        // state when the official feeds were actually last checked.
        _ref.read(alertsFetchTimeProvider.notifier).state = DateTime.now();
      },
      err: (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
      },
    );
  }


}

/// Real completion time of the last successful `/api/v1/alerts` read.
final alertsFetchTimeProvider = StateProvider<DateTime?>((ref) => null);

/// Provider managing active marine alerts list.
final alertsProvider = StateNotifierProvider<AlertsNotifier, AsyncValue<List<AlertItem>>>((ref) {
  final useCase = ref.watch(getAlertsUseCaseProvider);
  return AlertsNotifier(ref, useCase);
});
