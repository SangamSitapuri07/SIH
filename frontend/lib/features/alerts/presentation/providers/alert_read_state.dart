import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/cache/cache_service.dart';

/// Read/unread tracking for alerts.
///
/// Read state is a purely local, user-generated fact — it is *not* provider
/// data, so it is stored in the ORCA cache box rather than being invented from
/// an alert field the backend never sends. Alert ids come straight from the
/// official feed, so marking one read survives restarts and SSE redelivery.
class AlertReadStateNotifier extends StateNotifier<Set<String>> {
  static const _cacheKey = 'alerts_read_ids';

  /// Cap on remembered ids so the box cannot grow without bound.
  static const _maxRemembered = 400;

  final CacheService _cache;

  AlertReadStateNotifier(this._cache) : super(const <String>{}) {
    _restore();
  }

  void _restore() {
    final record = _cache.get(_cacheKey);
    final raw = record?.data['ids'];
    if (raw is List) {
      state = raw.map((e) => e.toString()).toSet();
    }
  }

  Future<void> _persist() async {
    // Keep only the most recent ids; Set preserves insertion order in Dart.
    final ids = state.length <= _maxRemembered
        ? state.toList()
        : state.toList().sublist(state.length - _maxRemembered);
    await _cache.set(_cacheKey, {'ids': ids});
  }

  bool isRead(String id) => state.contains(id);

  Future<void> markRead(String id) async {
    if (state.contains(id)) return;
    state = {...state, id};
    await _persist();
  }

  Future<void> markUnread(String id) async {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
    await _persist();
  }

  Future<void> toggle(String id) =>
      state.contains(id) ? markUnread(id) : markRead(id);

  Future<void> markAllRead(Iterable<String> ids) async {
    state = {...state, ...ids};
    await _persist();
  }
}

final alertReadStateProvider =
    StateNotifierProvider<AlertReadStateNotifier, Set<String>>((ref) {
  return AlertReadStateNotifier(ref.watch(cacheServiceProvider));
});

/// Severity buckets offered as filter chips.
///
/// These map onto the severity vocabulary the official feeds actually publish;
/// an alert whose severity the provider omitted lands in [unspecified] rather
/// than being assigned a plausible level.
enum AlertPriority {
  all('All'),
  critical('Critical'),
  warning('Warning'),
  advisory('Advisory'),
  unspecified('Unspecified');

  final String label;
  const AlertPriority(this.label);

  /// True when [severity] — exactly as published — belongs to this bucket.
  bool matches(String? severity) {
    if (this == AlertPriority.all) return true;
    final value = severity?.trim().toLowerCase() ?? '';
    if (value.isEmpty) return this == AlertPriority.unspecified;
    return switch (this) {
      AlertPriority.critical => value.contains('crit') ||
          value.contains('extreme') ||
          value.contains('severe') ||
          value.contains('danger') ||
          value.contains('no-go') ||
          value.contains('no_go'),
      AlertPriority.warning =>
        value.contains('warn') || value.contains('caution') || value.contains('moderate'),
      AlertPriority.advisory => value.contains('advis') ||
          value.contains('info') ||
          value.contains('watch') ||
          value.contains('minor'),
      AlertPriority.unspecified => value == 'unspecified' || value == 'unknown',
      AlertPriority.all => true,
    };
  }
}

/// Currently selected priority filter.
final alertPriorityFilterProvider =
    StateProvider<AlertPriority>((ref) => AlertPriority.all);

/// When true, only unread alerts are listed.
final alertUnreadOnlyProvider = StateProvider<bool>((ref) => false);
