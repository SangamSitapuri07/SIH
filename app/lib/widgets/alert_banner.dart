import 'package:flutter/material.dart';

import '../theme.dart';

/// Shows one alert string at the top of the response card.
class AlertBanner extends StatelessWidget {
  final String message;
  const AlertBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isWarning = message.contains('⚠') || message.contains('unsafe');
    final isBlock = message.contains('⛔') || message.contains('restricted');
    final color = isBlock
        ? OrcaColors.dangerRed
        : (isWarning ? OrcaColors.warnAmber : OrcaColors.accent);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isBlock ? Icons.block : Icons.warning_amber_rounded,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact pill showing the 0..1 safety score, color-coded.
class SafetyScorePill extends StatelessWidget {
  final double? score;
  const SafetyScorePill({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    if (score == null) return const SizedBox.shrink();
    final s = score!;
    final (color, label) = switch (s) {
      >= 0.75 => (OrcaColors.safeGreen, 'Safe'),
      >= 0.5 => (OrcaColors.warnAmber, 'Caution'),
      _ => (OrcaColors.dangerRed, 'Unsafe'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            '$label · ${(s * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
