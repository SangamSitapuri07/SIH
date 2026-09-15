import 'package:flutter/material.dart';

import '../../domain/entities/advisory.dart';
import '../../../../core/theme/orca_theme.dart';
import '../../../../core/theme/verdict_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/orca_ui.dart';

/// Presentation helpers that keep ORCA's provenance vocabulary consistent:
/// every marine value is described with its provider, its provider time and an
/// explicit state, or it is shown as unavailable.

/// Maps the provider-supplied variable status onto a visible data state.
OrcaDataState variableState(
  VariableItem? variable, {
  bool isLivePush = false,
  bool isOffline = false,
  bool isLoading = false,
}) {
  if (variable == null) {
    return resolveDataState(hasValue: false, isLoading: isLoading, isOffline: isOffline);
  }
  if (variable.value == null) {
    return resolveDataState(hasValue: false, isLoading: isLoading, isOffline: isOffline);
  }
  final String status = variable.status.toUpperCase();
  if (status.contains('CACHED')) {
    return resolveDataState(hasValue: true, isCached: true, isOffline: isOffline);
  }
  if (status.contains('STALE')) {
    return resolveDataState(hasValue: true, isStale: true, isOffline: isOffline);
  }
  if (status.contains('UNAVAILABLE') || status.contains('UNKNOWN') || status.isEmpty) {
    return resolveDataState(hasValue: true, isStale: true, isOffline: isOffline);
  }
  return resolveDataState(
    hasValue: true,
    isOffline: isOffline,
    isLive: isLivePush,
  );
}

/// Human label for the provider time that accompanies a variable.
String variableTimeLabel(VariableItem? variable) {
  if (variable == null) return 'Time unavailable';
  final String raw = variable.time.trim();
  if (raw.isEmpty) return 'Time unavailable';
  final DateTime? parsed = DateFormatter.parseIso(raw);
  final String formatted = parsed == null ? raw : DateFormatter.formatIstTime(parsed);
  final String prefix = variable.timeLabel?.trim() ?? '';
  return prefix.isEmpty ? formatted : '$prefix $formatted';
}

/// Renders a numeric measurement with its provider unit, or the explicit
/// unavailable wording when the backend supplied nothing.
String formatMeasurement(double? value, String unit, {int decimals = 1}) {
  if (value == null) return kOrcaUnavailableValue;
  final String number = decimals == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(decimals);
  return unit.isEmpty ? number : number;
}

String unitSuffix(String unit) => unit == 'C' ? '°C' : unit;

/// Deterministic verdict wording shared by the overview hero and the advisory.
String verdictWord(String? verdict) {
  if (verdict == null) return 'UNVERIFIED';
  final String normal = verdict.toUpperCase().replaceAll('_', '-');
  if (normal == 'GOOD' || normal == 'GO' || normal == 'SAFE') return 'GO';
  if (normal == 'CAUTION' || normal == 'MODERATE') return 'CAUTION';
  if (normal == 'NO-GO' || normal == 'NOGO' || normal == 'DANGER') return 'NO-GO';
  if (normal == 'UNVERIFIED' || normal == 'UNKNOWN') return 'UNVERIFIED';
  return normal;
}

/// Large display verdict including the shape glyph used for low-literacy
/// clarity. Matches the reference's typographic weight without inventing a
/// verdict the backend did not return.
String verdictDisplay(String? verdict) {
  final String word = verdictWord(verdict);
  return switch (word) {
    'GO' => 'GO',
    'CAUTION' => 'CAUTION',
    'NO-GO' => 'NO-GO',
    _ => 'UNVERIFIED',
  };
}

IconData verdictShapeIcon(String? verdict) => VerdictColors.iconForVerdict(verdict);

/// Source list formatting that never hides a failed provider.
String describeSources(List<String> sources, List<String> failed) {
  final String verified = sources.isEmpty ? 'No verified source' : sources.join(', ');
  if (failed.isEmpty) return verified;
  return '$verified · unavailable: ${failed.join(', ')}';
}

/// Fallback wording for a variable the backend did not publish at all.
String unavailableCaption(String subject) => '$subject unavailable from this deployment';

String greetingForHour(int istHour) {
  if (istHour < 12) return 'Good morning';
  if (istHour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Colour used for a metric value: measurements stay ink-dark so colour never
/// implies a threshold that was not evaluated.
Color metricInk(OrcaDataState state) =>
    state.isVerified ? OrcaTheme.textPrimary : OrcaTheme.textMuted;
