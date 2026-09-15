import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../cache/cache_service.dart';
import '../config/api_paths.dart';
import '../network/dio_provider.dart';
import '../offline/connectivity_watcher.dart';

enum SyncStatus { pending, syncing, synced, failed, retrying }

class SyncOperation {
  final String id;
  final String entityType;
  final String action;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  SyncStatus status;
  int retries;

  SyncOperation({
    required this.id,
    required this.entityType,
    required this.action,
    required this.payload,
    required this.timestamp,
    this.status = SyncStatus.pending,
    this.retries = 0,
  });

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final entityType = json['entity_type']?.toString();
    final action = json['action']?.toString();
    final payload = json['payload'];
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    if (id == null || entityType == null || action == null || payload is! Map || timestamp == null) {
      throw const FormatException('Invalid saved offline operation.');
    }
    final statusName = json['status']?.toString();
    var status = SyncStatus.pending;
    for (final candidate in SyncStatus.values) {
      if (candidate.name == statusName) {
        status = candidate;
        break;
      }
    }
    return SyncOperation(
      id: id,
      entityType: entityType,
      action: action,
      payload: Map<String, dynamic>.from(payload),
      timestamp: timestamp,
      // A process cannot resume an in-flight request after restart.
      status: status == SyncStatus.syncing ? SyncStatus.retrying : status,
      retries: (json['retries'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity_type': entityType,
        'action': action,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        'status': status.name,
        'retries': retries,
      };
}

/// Persistent offline outbox. Operations are removed only after the actual
/// backend acknowledges the specific request; this never simulates a sync.
class SyncManager extends StateNotifier<List<SyncOperation>> {
  static const _cacheKey = 'sync.outbox.v1';
  final Ref _ref;
  bool _isSyncing = false;

  SyncManager(this._ref) : super(const []) {
    unawaited(_loadOutbox());
    _ref.listen<bool>(isOnlineProvider, (previous, online) {
      if (online && previous != true) unawaited(triggerSync());
    });
  }

  int get pendingCount => state.where((operation) =>
      operation.status == SyncStatus.pending || operation.status == SyncStatus.retrying || operation.status == SyncStatus.failed).length;
  bool get isSyncing => _isSyncing;

  Future<void> _loadOutbox() async {
    final saved = _ref.read(cacheServiceProvider).get(_cacheKey)?.data['operations'];
    if (saved is List) {
      final restored = <SyncOperation>[];
      for (final value in saved) {
        if (value is Map) {
          try {
            restored.add(SyncOperation.fromJson(Map<String, dynamic>.from(value)));
          } catch (_) {
            // Corrupt operation records cannot safely be replayed.
          }
        }
      }
      state = restored;
    }
    if (_ref.read(isOnlineProvider)) await triggerSync();
  }

  Future<void> _persist() => _ref.read(cacheServiceProvider).put(
        _cacheKey,
        {'operations': state.map((operation) => operation.toJson()).toList()},
        ttl: const Duration(days: 30),
      );

  void enqueue(String entityType, String action, Map<String, dynamic> payload) {
    final now = DateTime.now();
    final operation = SyncOperation(
      id: 'sync-${now.microsecondsSinceEpoch}',
      entityType: entityType,
      action: action,
      payload: payload,
      timestamp: now,
    );
    state = [...state, operation];
    unawaited(_persist());
    unawaited(triggerSync());
  }

  Future<void> triggerSync() async {
    if (_isSyncing || pendingCount == 0 || !_ref.read(isOnlineProvider)) return;
    _isSyncing = true;
    final queued = state.where((operation) =>
        operation.status == SyncStatus.pending || operation.status == SyncStatus.retrying || operation.status == SyncStatus.failed).toList();

    for (final operation in queued) {
      operation.status = SyncStatus.syncing;
      state = [...state];
      await _persist();
      try {
        final response = await _ref.read(dioProvider).post<dynamic>(
          ApiPaths.sync,
          data: {'operations': [operation.toJson()]},
        );
        final data = response.data;
        final accepted = data is Map && data['status'] == 'synced' && data['processed_operations'] == 1;
        if (!accepted) throw const FormatException('Backend did not acknowledge the queued operation.');
        operation.status = SyncStatus.synced;
      } on DioException catch (error) {
        operation.retries += 1;
        operation.status = SyncStatus.retrying;
        debugPrint('Offline operation ${operation.id} awaits retry: ${error.message}');
      } catch (error) {
        operation.retries += 1;
        operation.status = SyncStatus.failed;
        debugPrint('Offline operation ${operation.id} was rejected: $error');
      }
      state = [...state];
      await _persist();
    }

    _isSyncing = false;
    state = state.where((operation) => operation.status != SyncStatus.synced).toList();
    await _persist();
  }
}

final syncManagerProvider = StateNotifierProvider<SyncManager, List<SyncOperation>>((ref) => SyncManager(ref));
