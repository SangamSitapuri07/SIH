import 'package:flutter/material.dart';

import '../theme/orca_theme.dart';
import '../theme/verdict_colors.dart';

/// The truthfulness state of a single displayed marine value or panel.
///
/// ORCA never renders a number without also being able to answer "how do you
/// know this?". Every value-bearing widget in the app takes a [DataState] so
/// the answer is structural rather than decorative.
enum DataState {
  /// A real value arrived from a live provider response in this session.
  live,

  /// A real value, but it is a *model forecast* for a future valid time
  /// rather than an observation.
  forecast,

  /// A real value that was previously fetched and is being served from the
  /// local Hive cache while still inside its TTL.
  cached,

  /// A real value from cache that has outlived its TTL.
  stale,

  /// A request is in flight and no value can be shown yet.
  loading,

  /// The provider answered, but it published no value for this field.
  unavailable,

  /// The request itself failed (network, timeout, 5xx).
  error,

  /// The device has no connectivity, so only cached values are possible.
  offline,
}

extension DataStateX on DataState {
  /// Short uppercase token used in badges.
  String get token => switch (this) {
        DataState.live => 'LIVE',
        DataState.forecast => 'FORECAST',
        DataState.cached => 'CACHED',
        DataState.stale => 'STALE',
        DataState.loading => 'LOADING',
        DataState.unavailable => 'UNAVAILABLE',
        DataState.error => 'ERROR',
        DataState.offline => 'OFFLINE',
      };

  /// Sentence-case label used inline in value slots.
  String get label => switch (this) {
        DataState.live => 'Live',
        DataState.forecast => 'Forecast',
        DataState.cached => 'Cached',
        DataState.stale => 'Stale',
        DataState.loading => 'Loading…',
        DataState.unavailable => 'Unavailable',
        DataState.error => 'Error',
        DataState.offline => 'Offline',
      };

  /// True when a real value exists behind this state and may be rendered.
  bool get hasValue =>
      this == DataState.live ||
      this == DataState.forecast ||
      this == DataState.cached ||
      this == DataState.stale;

  Color get color => switch (this) {
        DataState.live => VerdictColors.go,
        DataState.forecast => VerdictColors.info,
        DataState.cached => OrcaTheme.accentDark,
        DataState.stale => VerdictColors.caution,
        DataState.loading => OrcaTheme.textMuted,
        DataState.unavailable => OrcaTheme.textMuted,
        DataState.error => VerdictColors.critical,
        DataState.offline => VerdictColors.caution,
      };

  IconData get icon => switch (this) {
        DataState.live => Icons.sensors_rounded,
        DataState.forecast => Icons.schedule_rounded,
        DataState.cached => Icons.history_toggle_off_rounded,
        DataState.stale => Icons.running_with_errors_rounded,
        DataState.loading => Icons.hourglass_empty_rounded,
        DataState.unavailable => Icons.remove_circle_outline_rounded,
        DataState.error => Icons.cloud_off_rounded,
        DataState.offline => Icons.wifi_off_rounded,
      };
}

/// Provenance attached to a marine value, overlay, advisory or visualization.
///
/// This is the contract that makes the UI auditable: a caller cannot show a
/// number through ORCA's widgets without stating where it came from and when
/// it was valid. Everything is nullable *except* [state], because the honest
/// answer to "what is the source?" is sometimes literally "the provider did
/// not say" — and that must render as `Source unavailable`, not as a guess.
@immutable
class Provenance {
  /// Freshness / availability state of the value.
  final DataState state;

  /// Provider name exactly as reported by the backend (e.g.
  /// "Open-Meteo Marine (MFWAM/ECMWF)"). Never invented client-side.
  final String? source;

  /// The time the value is *about*: observation time for measurements, model
  /// valid time for forecasts.
  final DateTime? validAt;

  /// Label describing what [validAt] means, as published by the backend
  /// (e.g. "Model valid", "Observation time", "ORCA retrieved").
  final String? validAtLabel;

  /// When ORCA retrieved the value from the provider.
  final DateTime? retrievedAt;

  /// End of the validity window, when the provider publishes one.
  final DateTime? validUntil;

  /// Reason the value is unavailable / errored, as reported upstream.
  final String? reason;

  const Provenance({
    required this.state,
    this.source,
    this.validAt,
    this.validAtLabel,
    this.retrievedAt,
    this.validUntil,
    this.reason,
  });

  const Provenance.loading() : this(state: DataState.loading);

  const Provenance.unavailable({String? source, String? reason})
      : this(state: DataState.unavailable, source: source, reason: reason);

  const Provenance.error({String? source, String? reason})
      : this(state: DataState.error, source: source, reason: reason);

  const Provenance.offline() : this(state: DataState.offline);

  bool get hasValue => state.hasValue;

  Provenance copyWith({DataState? state, String? source, String? reason}) =>
      Provenance(
        state: state ?? this.state,
        source: source ?? this.source,
        validAt: validAt,
        validAtLabel: validAtLabel,
        retrievedAt: retrievedAt,
        validUntil: validUntil,
        reason: reason ?? this.reason,
      );

  /// Human summary line: "Open-Meteo Marine · Model valid 09:42 IST".
  /// Falls back to explicit unavailability language, never to a plausible
  /// placeholder.
  String summary() {
    final buffer = StringBuffer(source ?? 'Source unavailable');
    final time = validAt ?? retrievedAt;
    if (time != null) {
      final label = validAtLabel ?? (validAt != null ? 'Valid' : 'Retrieved');
      buffer.write(' · $label ${_istTime(time)}');
    } else {
      buffer.write(' · Time unavailable');
    }
    return buffer.toString();
  }

  static String _istTime(DateTime value) {
    final ist = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    final hh = ist.hour.toString().padLeft(2, '0');
    final mm = ist.minute.toString().padLeft(2, '0');
    return '$hh:$mm IST';
  }

  /// Formats [validUntil] as a validity window sentence, or null when the
  /// provider published no window (in which case the UI must not imply one).
  String? validityWindow() {
    if (validUntil == null) return null;
    final from = validAt ?? retrievedAt;
    if (from == null) return 'Valid until ${_istTime(validUntil!)}';
    return 'Valid ${_istTime(from)} – ${_istTime(validUntil!)}';
  }
}
