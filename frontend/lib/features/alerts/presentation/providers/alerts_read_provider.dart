import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/cache_service.dart';

/// Device-local review state for alerts.
///
/// The official feeds do not publish a read flag, so ORCA never claims one.
/// What it can honestly track is whether *this device* has already shown an
/// alert to the skipper — that set is persisted locally and labelled as such
/// in the UI.
class AlertsReadNotifier extends StateNotifier<Set<String>> {
  AlertsReadNotifier(this._cache) : super(<String>{}) {
    _load();
  }

  static const String _key = 'alerts.reviewed';
  final CacheService _cache;

  void _load() {
    final CachedRecord? record = _cache.get(_key);
    final Object? raw = record?.data['ids'];
    if (raw is List) {
      state = raw.map((Object? id) => id.toString()).toSet();
    }
  }

  bool isReviewed(String id) => state.contains(id);

  Future<void> markReviewed(String id) async {
    if (state.contains(id)) return;
    final Set<String> next = <String>{...state, id};
    state = next;
    await _persist(next);
  }

  Future<void> markAllReviewed(Iterable<String> ids) async {
    final Set<String> next = <String>{...state, ...ids};
    state = next;
    await _persist(next);
  }

  Future<void> clearReviewed() async {
    state = <String>{};
    await _persist(<String>{});
  }

  Future<void> _persist(Set<String> ids) async {
    try {
      await _cache.put(
        _key,
        <String, dynamic>{'ids': ids.toList()},
        ttl: const Duration(days: 3650),
      );
    } catch (error) {
      debugPrint('[AlertsRead] Could not persist reviewed alert ids: $error');
    }
  }
}

final alertsReadProvider = StateNotifierProvider<AlertsReadNotifier, Set<String>>((ref) {
  return AlertsReadNotifier(ref.watch(cacheServiceProvider));
});
