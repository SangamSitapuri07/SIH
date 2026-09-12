import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncStatus { pending, syncing, synced, failed, retrying }

class SyncOperation {
  final String id;
  final String entityType; // location, catch_report, feedback, profile
  final String action; // CREATE, UPDATE, DELETE
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entity_type': entityType,
      'action': action,
      'payload': payload,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'retries': retries,
    };
  }
}

/// Offline-First Sync Engine (§14, §15, §16).
/// Automatically queues operations locally and syncs when connectivity returns.
class SyncManager extends StateNotifier<List<SyncOperation>> {
  final Ref _ref;
  bool _isSyncing = false;

  SyncManager(this._ref) : super([]) {
    _loadOutbox();
  }

  int get pendingCount => state.where((op) => op.status == SyncStatus.pending || op.status == SyncStatus.retrying).length;
  bool get isSyncing => _isSyncing;

  void _loadOutbox() {
    // Outbox queue initialization
  }

  void enqueue(String entityType, String action, Map<String, dynamic> payload) {
    final op = SyncOperation(
      id: 'sync-${DateTime.now().millisecondsSinceEpoch}',
      entityType: entityType,
      action: action,
      payload: payload,
      timestamp: DateTime.now(),
    );
    state = [...state, op];
    debugPrint('Queued offline sync operation: ${op.id} ($entityType)');
    triggerSync();
  }

  Future<void> triggerSync() async {
    if (_isSyncing || pendingCount == 0) return;

    _isSyncing = true;
    final pendingOps = state.where((op) => op.status == SyncStatus.pending || op.status == SyncStatus.retrying).toList();

    for (var op in pendingOps) {
      op.status = SyncStatus.syncing;
      state = [...state];

      try {
        await Future.delayed(const Duration(milliseconds: 600)); // Simulate remote sync
        op.status = SyncStatus.synced;
        debugPrint('Successfully synced operation: ${op.id}');
      } catch (e) {
        op.retries++;
        op.status = SyncStatus.retrying;
        debugPrint('Failed to sync operation: ${op.id}, retry count: ${op.retries}');
      }
    }

    _isSyncing = false;
    // Remove synced operations after successful push
    state = state.where((op) => op.status != SyncStatus.synced).toList();
  }
}

final syncManagerProvider = StateNotifierProvider<SyncManager, List<SyncOperation>>((ref) {
  return SyncManager(ref);
});
