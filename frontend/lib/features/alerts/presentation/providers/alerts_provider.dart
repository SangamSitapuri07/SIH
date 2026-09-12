import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/live/live_channel.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/result/result.dart';
import '../../../../core/widgets/orca_app_bar.dart';
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
  return AlertsRepositoryImpl(remoteDataSource: remote);
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

    // Listen to live SSE alert.push events (§4, §16)
    _ref.listen(alertPushStreamProvider, (prev, next) {
      next.whenData((event) {
        final data = event.jsonData;
        if (data is Map<String, dynamic>) {
          final dto = AlertDto.fromJson(data);
          final current = state.valueOrNull ?? <AlertItem>[];
          state = AsyncValue.data(<AlertItem>[dto.toEntity(), ...current]);
        }
      });
    });

    // Re-fetch if demo mode changes
    _ref.listen(demoModeProvider, (prev, next) {
      fetch(forceRefresh: true);
    });
  }

  Future<void> fetch({bool forceRefresh = false}) async {
    state = const AsyncValue.loading();
    final isDemo = _ref.read(demoModeProvider);

    if (isDemo) {
      try {
        final raw = await rootBundle.loadString('assets/fixtures/alerts.json');
        final list = jsonDecode(raw) as List<dynamic>;
        final dtos = list.map((e) => AlertDto.fromJson(e as Map<String, dynamic>)).toList();
        state = AsyncValue.data(dtos.map((d) => d.toEntity()).toList());
        return;
      } catch (e, st) {
        state = AsyncValue.error(e, st);
        return;
      }
    }

    final result = await _useCase.execute(forceRefresh: forceRefresh);
    result.when(
      ok: (alerts) {
        state = AsyncValue.data(alerts);
      },
      err: (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
      },
    );
  }

  /// Injects simulated alert for judge demonstrations (§8).
  void simulateDemoAlert() {
    final simulated = AlertItem(
      id: 'sim_${DateTime.now().millisecondsSinceEpoch}',
      severity: 'critical',
      title: '🚨 SIMULATED: Severe Squall Line Approaching',
      titleHi: '🚨 सिमुलेशन: तेज तूफानी हवाओं की चेतावनी',
      message: 'Squall line with gusts exceeding 38 kn and 3.5m waves advancing 25 km West. Small crafts return to nearest harbour immediately.',
      messageHi: '38 समुद्री मील से तेज हवाएं और 3.5 मीटर ऊंची लहरें आ रही हैं। तुरंत निकटतम बंदरगाह लौटें।',
      source: 'ORCA Simulator (Demo)',
      issuedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
      affectedArea: 'Mumbai & Konkan Coast',
      isActive: true,
    );

    final current = state.valueOrNull ?? <AlertItem>[];
    state = AsyncValue.data(<AlertItem>[simulated, ...current]);
  }
}

/// Provider managing active marine alerts list.
final alertsProvider = StateNotifierProvider<AlertsNotifier, AsyncValue<List<AlertItem>>>((ref) {
  final useCase = ref.watch(getAlertsUseCaseProvider);
  return AlertsNotifier(ref, useCase);
});
