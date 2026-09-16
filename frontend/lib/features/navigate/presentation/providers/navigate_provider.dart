import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_provider.dart';
import '../../data/datasources/navigate_remote.dart';
import '../../data/repositories/navigate_repo_impl.dart';
import '../../domain/entities/route_check.dart';
import '../../domain/repositories/navigate_repo.dart';
import '../../domain/usecases/get_route_advisory.dart';
import 'offline_navigation_provider.dart';

/// Provider for NavigateRemoteDataSource.
final navigateRemoteDataSourceProvider = Provider<NavigateRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return NavigateRemoteDataSource(dio);
});

/// Provider for NavigateRepository.
final navigateRepositoryProvider = Provider<NavigateRepository>((ref) {
  final remote = ref.watch(navigateRemoteDataSourceProvider);
  return NavigateRepositoryImpl(remoteDataSource: remote);
});

/// Provider for GetRouteAdvisoryUseCase.
final getRouteAdvisoryUseCaseProvider = Provider<GetRouteAdvisoryUseCase>((ref) {
  final repo = ref.watch(navigateRepositoryProvider);
  return GetRouteAdvisoryUseCase(repo);
});

/// Container holding route analysis output.
class RouteAnalysisState {
  final RouteCheckEntity? check;
  final RouteAdvisoryEntity? advisory;
  final bool advisoryLoading;
  final String? advisoryError;

  const RouteAnalysisState({
    this.check,
    this.advisory,
    this.advisoryLoading = false,
    this.advisoryError,
  });
}

/// StateNotifier evaluating route transit safety.
class NavigateNotifier extends StateNotifier<AsyncValue<RouteAnalysisState>> {
  final Ref _ref;
  final GetRouteAdvisoryUseCase _useCase;

  NavigateNotifier(this._ref, this._useCase)
      : super(const AsyncValue.data(RouteAnalysisState()));

  Future<void> evaluateRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    state = const AsyncValue.loading();
    final checkResult = await _useCase.checkRoute(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );

    // Paint verified/rejected geometry immediately; weather scoring continues
    // independently instead of leaving the whole workspace behind a spinner.
    if (checkResult.isOk) {
      final check = checkResult.valueOrNull;
      state = AsyncValue.data(RouteAnalysisState(
        check: check,
        advisoryLoading: check?.ok == true,
      ));
      if (check != null && check.ok == true) {
        // Geometry is operationally useful offline even if the independent
        // weather request later times out. Its weather state remains explicit.
        await _ref.read(offlineNavigationProvider.notifier).saveVerifiedGeometry(check);
      } else {
        // A rejected or reference-only route has no transit geometry to score;
        // do not trigger a second backend verification/weather request.
        return;
      }
    } else {
      state = AsyncValue.error(
        checkResult.failureOrNull?.message ?? 'Route geometry could not be planned.',
        StackTrace.current,
      );
      return;
    }

    final advisoryResult = await _useCase.getRouteAdvisory(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );

    if (checkResult.isOk && advisoryResult.isOk) {
      final check = checkResult.valueOrNull;
      final advisory = advisoryResult.valueOrNull;
      state = AsyncValue.data(RouteAnalysisState(check: check, advisory: advisory));
      if (check != null && advisory != null && check.ok == true) {
        // Persist verified geometry and its explicitly expiring weather
        // evidence. GPS progress can then run with no server connection.
        await _ref.read(offlineNavigationProvider.notifier).saveRoute(check, advisory);
      }
    } else {
      // Do not erase valid geometry merely because live weather is slow or
      // unavailable. The UI keeps the route and marks weather UNVERIFIED.
      state = AsyncValue.data(RouteAnalysisState(
        check: checkResult.valueOrNull,
        advisoryError: advisoryResult.failureOrNull?.message ??
            'Live route weather is unavailable. Saved geometry remains usable.',
      ));
    }
  }
}

/// Provider managing route analysis state.
final navigateProvider = StateNotifierProvider<NavigateNotifier, AsyncValue<RouteAnalysisState>>((ref) {
  final useCase = ref.watch(getRouteAdvisoryUseCaseProvider);
  return NavigateNotifier(ref, useCase);
});
