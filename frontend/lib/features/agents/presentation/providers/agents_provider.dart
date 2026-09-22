import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/cache/cache_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../advisory/presentation/providers/advisory_provider.dart';
import '../../data/datasources/agents_remote.dart';
import '../../data/repositories/agents_repo_impl.dart';
import '../../domain/entities/agent_reasoning.dart';
import '../../domain/repositories/agents_repo.dart';
import '../../domain/usecases/get_agent_reasoning.dart';

/// Provider for AgentsRemoteDataSource.
final agentsRemoteDataSourceProvider = Provider<AgentsRemoteDataSource>((ref) {
  final dio = ref.watch(dioProvider);
  return AgentsRemoteDataSource(dio);
});

/// Provider for AgentsRepository.
final agentsRepositoryProvider = Provider<AgentsRepository>((ref) {
  final remote = ref.watch(agentsRemoteDataSourceProvider);
  final cache = ref.watch(cacheServiceProvider);
  return AgentsRepositoryImpl(
    remoteDataSource: remote,
    cacheService: cache,
  );
});

/// Provider for GetAgentReasoningUseCase.
final getAgentReasoningUseCaseProvider = Provider<GetAgentReasoningUseCase>((ref) {
  final repo = ref.watch(agentsRepositoryProvider);
  return GetAgentReasoningUseCase(repo);
});

/// Runtime entry advertised by the actual `/api/v1/agents` backend registry.
///
/// The registry reports IDLE until a reasoning request runs, and PROCESSING,
/// FALLBACK or FAILED while and after one does. IDLE therefore means "not
/// currently running", not "healthy" — the UI must not present it as readiness.
class AgentRuntimeStatus {
  final String id;
  final String status;
  final String name;
  final String type;
  final String? role;
  final String? providerState;

  const AgentRuntimeStatus({
    required this.id,
    required this.status,
    required this.name,
    required this.type,
    this.role,
    this.providerState,
  });

  bool get isRunning => status.toUpperCase() == 'PROCESSING';
  bool get hasProblem {
    final String normal = status.toUpperCase();
    return normal == 'FAILED' || normal == 'DEGRADED';
  }

  bool get isIdle => status.toUpperCase() == 'IDLE';
  bool get isFallback => status.toUpperCase() == 'FALLBACK';
  String? get providerLabel => providerState
      ?.replaceFirst('OLLAMA_', 'OLLAMA ')
      .replaceAll('_', ' ');
}

final agentRuntimeStatusProvider = FutureProvider<List<AgentRuntimeStatus>>((ref) async {
  final response = await ref.watch(dioProvider).get<dynamic>(ApiPaths.agents);
  final data = response.data;
  final List<dynamic> list = data is Map<String, dynamic>
      ? data['agents'] as List<dynamic>? ?? const <dynamic>[]
      : const <dynamic>[];
  return list.whereType<Map<String, dynamic>>().map((agent) {
    final id = agent['id']?.toString();
    if (id == null) throw const FormatException('Agent registry entry missing id.');
    return AgentRuntimeStatus(
      id: id,
      status: agent['status']?.toString() ?? 'UNAVAILABLE',
      name: agent['name']?.toString() ?? id,
      type: agent['type']?.toString() ?? 'Unspecified',
      role: agent['role']?.toString(),
      providerState: agent['provider_state']?.toString(),
    );
  }).toList();
});

/// StateNotifier providing live / cached multi-agent reasoning state.
class AgentsNotifier extends StateNotifier<AsyncValue<AgentReasoningResult>> {
  final Ref _ref;
  final GetAgentReasoningUseCase _useCase;

  AgentsNotifier(this._ref, this._useCase)
      : super(const AsyncValue.error(
          'Reasoning has not been run for this session. Use Run reasoning pass when needed.',
          StackTrace.empty,
        ));

  void resetForLocationChange() {
    state = const AsyncValue.error(
      'Reasoning has not been run for this working location.',
      StackTrace.empty,
    );
  }

  Future<void> fetch({bool forceRefresh = false}) async {
    state = const AsyncValue.loading();
    // `/reason` and `/agents` are independent requests. Refresh the registry
    // shortly after the reasoning request starts so PROCESSING is visible,
    // then refresh it again when the trace completes.
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) _ref.invalidate(agentRuntimeStatusProvider);
    });
    final coordinates = _ref.read(advisoryLocationProvider);
    final result = await _useCase.execute(
      lat: coordinates['lat'] ?? AppConfig.defaultLat,
      lon: coordinates['lon'] ?? AppConfig.defaultLon,
      forceRefresh: forceRefresh,
    );

    result.when(
      ok: (reasoning) {
        state = AsyncValue.data(reasoning);
      },
      err: (failure) {
        state = AsyncValue.error(failure.message, StackTrace.current);
      },
    );
    _ref.invalidate(agentRuntimeStatusProvider);
  }
}

/// Provider managing multi-agent reasoning state.
final agentsProvider = StateNotifierProvider<AgentsNotifier, AsyncValue<AgentReasoningResult>>((ref) {
  final useCase = ref.watch(getAgentReasoningUseCaseProvider);
  return AgentsNotifier(ref, useCase);
});
