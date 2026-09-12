import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/dio_provider.dart';
import '../cache/cache_service.dart';
import 'connectivity_watcher.dart';

/// Item queued in the offline outbox.
class OutboxItem {
  final String id;
  final String path;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  OutboxItem({
    required this.id,
    required this.path,
    required this.payload,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        path: json['path'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Outbox service managing queued offline mutations (§14).
class OutboxNotifier extends StateNotifier<List<OutboxItem>> {
  final Dio _dio;
  final Ref _ref;
  final CacheService _cache;

  OutboxNotifier(this._dio, this._ref, this._cache) : super(<OutboxItem>[]) {
    _restore();
    // Listen to connectivity changes to auto-flush
    _ref.listen<bool>(isOnlineProvider, (previous, isOnline) {
      if (isOnline && state.isNotEmpty) {
        flush();
      }
    });
  }

  Future<void> _restore() async {
    final record = _cache.get('outbox.pending');
    final items = record?.data['items'];
    if (items is List) {
      state = items
          .whereType<Map>()
          .map((item) => OutboxItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }
  }

  Future<void> _persist() => _cache.put(
        'outbox.pending',
        <String, dynamic>{'items': state.map((item) => item.toJson()).toList()},
        ttl: const Duration(days: 30),
      );

  /// Queues a POST request for later sending.
  void enqueue(String path, Map<String, dynamic> payload) {
    final item = OutboxItem(
      id: 'outbox_${DateTime.now().millisecondsSinceEpoch}',
      path: path,
      payload: payload,
      createdAt: DateTime.now(),
    );
    state = <OutboxItem>[...state, item];
    unawaited(_persist());
    debugPrint('[Outbox] Queued request to ${item.path} (total: ${state.length})');

    // Attempt flush immediately if online
    if (_ref.read(isOnlineProvider)) {
      flush();
    }
  }

  /// Flushes queued items sequentially.
  Future<void> flush() async {
    if (state.isEmpty) return;
    debugPrint('[Outbox] Starting flush of ${state.length} items...');

    final remaining = <OutboxItem>[];
    for (final item in state) {
      try {
        await _dio.post<dynamic>(item.path, data: item.payload);
        debugPrint('[Outbox] Successfully synced item ${item.id} -> ${item.path}');
      } catch (e) {
        debugPrint('[Outbox] Failed syncing item ${item.id}: $e');
        remaining.add(item);
      }
    }
    state = remaining;
    await _persist();
  }
}

/// Outbox provider.
final outboxProvider = StateNotifierProvider<OutboxNotifier, List<OutboxItem>>((ref) {
  final dio = ref.watch(dioProvider);
  final cache = ref.watch(cacheServiceProvider);
  return OutboxNotifier(dio, ref, cache);
});
