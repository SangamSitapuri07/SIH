import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/api_paths.dart';
import '../../../../core/network/dio_provider.dart';
import '../../../../core/cache/cache_service.dart';

class SourceHealthItem {
  final String key;
  final String name;
  final String status;
  final int? latencyMs;
  final String? note;
  final int? checkedAt;
  final String? observedAt;

  const SourceHealthItem({
    required this.key,
    required this.name,
    required this.status,
    this.latencyMs,
    this.note,
    this.checkedAt,
    this.observedAt,
  });
}

class SystemHealthSnapshot {
  final String status;
  final int? timestamp;
  final Map<String, SourceHealthItem> dataSources;

  const SystemHealthSnapshot({
    required this.status,
    this.timestamp,
    required this.dataSources,
  });
}

/// Reads actual source observations captured by the ORCA backend. Missing
/// fields remain unknown; nothing in this mapper supplies plausible metrics.
class HealthNotifier extends StateNotifier<AsyncValue<SystemHealthSnapshot>> {
  final Ref _ref;
  HealthNotifier(this._ref) : super(const AsyncValue.loading()) {
    checkHealth();
  }

  Future<void> checkHealth() async {
    state = const AsyncValue.loading();
    try {
      final response = await _ref.read(dioProvider).get<Map<String, dynamic>>(ApiPaths.health);
      final payload = response.data;
      if (payload == null) throw const FormatException('Empty health response');
      state = AsyncValue.data(_parseHealth(payload));
    } catch (_) {
      state = AsyncValue.error('ORCA backend is unreachable. Source status cannot be verified.', StackTrace.current);
    }
  }

  SystemHealthSnapshot _parseHealth(Map<String, dynamic> json) {
    final result = <String, SourceHealthItem>{};
    final sources = json['data_sources'];
    if (sources is Map) {
      sources.forEach((key, raw) {
        if (raw is Map) {
          result[key.toString()] = SourceHealthItem(
            key: key.toString(),
            name: raw['name']?.toString() ?? key.toString(),
            status: raw['status']?.toString() ?? 'UNVERIFIED',
            latencyMs: (raw['latency_ms'] as num?)?.toInt(),
            note: raw['reason']?.toString(),
            checkedAt: (raw['checked_at'] as num?)?.toInt(),
            observedAt: raw['observed_at']?.toString(),
          );
        }
      });
    }
    return SystemHealthSnapshot(
      status: json['status']?.toString() ?? 'UNVERIFIED',
      timestamp: (json['timestamp'] as num?)?.toInt(),
      dataSources: result,
    );
  }
}

final healthProvider = StateNotifierProvider<HealthNotifier, AsyncValue<SystemHealthSnapshot>>((ref) => HealthNotifier(ref));

final selectedLocaleProvider = StateProvider<String>((ref) {
  return ref.watch(cacheServiceProvider).get('settings.locale')?.data['value'] as String? ?? 'en';
});
