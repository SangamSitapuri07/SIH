import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/widgets/orca_app_bar.dart';
import '../../data/datasources/navigate_remote.dart';
import '../../data/dto/route_check_dto.dart';
import '../../data/repositories/navigate_repo_impl.dart';
import '../../domain/entities/route_check.dart';
import '../../domain/repositories/navigate_repo.dart';
import '../../domain/usecases/get_route_advisory.dart';

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

  const RouteAnalysisState({this.check, this.advisory});
}

/// StateNotifier evaluating route transit safety.
class NavigateNotifier extends StateNotifier<AsyncValue<RouteAnalysisState>> {
  final Ref _ref;
  final GetRouteAdvisoryUseCase _useCase;

  NavigateNotifier(this._ref, this._useCase) : super(const AsyncValue.loading()) {
    evaluateRoute(
      fromLat: 18.92,
      fromLon: 72.83,
      toLat: 18.75,
      toLon: 72.55,
    );

    _ref.listen(demoModeProvider, (prev, next) {
      evaluateRoute(
        fromLat: 18.92,
        fromLon: 72.83,
        toLat: 18.75,
        toLon: 72.55,
      );
    });
  }

  Future<void> evaluateRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    state = const AsyncValue.loading();
    final isDemo = _ref.read(demoModeProvider);

    if (isDemo) {
      try {
        final checkRaw = await rootBundle.loadString('assets/fixtures/route_check.json');
        final checkJson = jsonDecode(checkRaw) as Map<String, dynamic>;
        final checkDto = RouteCheckDto.fromJson(checkJson);

        final advRaw = await rootBundle.loadString('assets/fixtures/route_advisory.json');
        final advJson = jsonDecode(advRaw) as Map<String, dynamic>;
        final advDto = RouteAdvisoryDto.fromJson(advJson);

        state = AsyncValue.data(
          RouteAnalysisState(
            check: checkDto.toEntity(),
            advisory: advDto.toEntity(),
          ),
        );
        return;
      } catch (e, st) {
        state = AsyncValue.error(e, st);
        return;
      }
    }

    final checkResult = await _useCase.checkRoute(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );

    final advisoryResult = await _useCase.getRouteAdvisory(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );

    if (checkResult.isOk && advisoryResult.isOk) {
      state = AsyncValue.data(
        RouteAnalysisState(
          check: checkResult.valueOrNull,
          advisory: advisoryResult.valueOrNull,
        ),
      );
    } else {
      final failureMsg = checkResult.failureOrNull?.message ??
          advisoryResult.failureOrNull?.message ??
          'Route evaluation failed.';
      state = AsyncValue.error(failureMsg, StackTrace.current);
    }
  }
}

/// Provider managing route analysis state.
final navigateProvider = StateNotifierProvider<NavigateNotifier, AsyncValue<RouteAnalysisState>>((ref) {
  final useCase = ref.watch(getRouteAdvisoryUseCaseProvider);
  return NavigateNotifier(ref, useCase);
});
