import 'package:flutter/material.dart';
import '../theme/verdict_colors.dart';

/// Freshness state of an observation or cached payload (§7, §14).
enum StalenessState {
  fresh, // < 30 min
  recent, // 30 min - 3 hours
  stale, // > 3 hours
  unreachable,
}

/// Helper model for calculating staleness metadata.
class StalenessInfo {
  final StalenessState state;
  final Duration age;
  final DateTime fetchedAt;
  final bool isCached;

  const StalenessInfo({
    required this.state,
    required this.age,
    required this.fetchedAt,
    this.isCached = false,
  });

  /// Computes staleness from fetch timestamp.
  factory StalenessInfo.fromDateTime(DateTime fetchedAt, {bool isCached = false}) {
    final now = DateTime.now();
    final age = now.difference(fetchedAt);

    StalenessState state;
    if (age.inMinutes < 30) {
      state = StalenessState.fresh;
    } else if (age.inHours < 3) {
      state = StalenessState.recent;
    } else {
      state = StalenessState.stale;
    }

    return StalenessInfo(
      state: state,
      age: age,
      fetchedAt: fetchedAt,
      isCached: isCached,
    );
  }

  /// True once the payload has outlived the 3-hour freshness budget, or when
  /// the source could not be reached at all. Screens use this to decide
  /// between a `CACHED` and a `STALE` badge.
  bool get isStale =>
      state == StalenessState.stale || state == StalenessState.unreachable;

  /// Badge label for UI display.
  String get label {
    final prefix = isCached ? 'Cached · ' : '';
    switch (state) {
      case StalenessState.fresh:
        return '${prefix}Fresh (<30m)';
      case StalenessState.recent:
        return '${prefix}Recent (${age.inMinutes}m ago)';
      case StalenessState.stale:
        return '${prefix}Stale (${age.inHours}h ago)';
      case StalenessState.unreachable:
        return '${prefix}Unreachable';
    }
  }

  /// Badge color according to design system tokens (§15).
  Color get color {
    switch (state) {
      case StalenessState.fresh:
        return VerdictColors.go;
      case StalenessState.recent:
        return VerdictColors.caution;
      case StalenessState.stale:
        return VerdictColors.stale;
      case StalenessState.unreachable:
        return VerdictColors.critical;
    }
  }
}
