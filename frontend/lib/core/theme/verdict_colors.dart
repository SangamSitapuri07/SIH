import 'package:flutter/material.dart';

/// Single source of truth for all verdict, severity, and ocean tokens (§15).
class VerdictColors {
  /// 🟢 GO SAFE (#16A34A — AA on light backgrounds)
  static const Color go = Color(0xFF16A34A);

  /// 🟠 CAUTION (#D97706 — AA on light backgrounds)
  static const Color caution = Color(0xFFD97706);

  /// 🔴 NO-GO / DANGER (#DC2626 — AA on light backgrounds)
  static const Color noGo = Color(0xFFDC2626);

  /// 🔵 INFO (#0E9FAD — AA on light backgrounds)
  static const Color info = Color(0xFF0E9FAD);

  /// 🚨 CRITICAL (#DC2626 — AA on light backgrounds)
  static const Color critical = Color(0xFFDC2626);

  /// ⚪ STALE BADGE (#64748B — readable on light)
  static const Color stale = Color(0xFF64748B);

  /// ⛰️ LAND MASK TONE (#2e4066)
  static const Color land = Color(0xFF2E4066);

  /// 🌊 SEA DEEP TONE (#0d3a63)
  static const Color sea = Color(0xFF0D3A63);

  // Background card tints for verdicts (light marine soft tints)
  static const Color goBg = Color(0xFFE7F8EE);
  static const Color cautionBg = Color(0xFFFEF5E0);
  static const Color noGoBg = Color(0xFFFDEBEB);
  static const Color infoBg = Color(0xFFE4F6F9);

  /// Maps string verdict to Color.
  static Color fromVerdict(String? verdict) {
    if (verdict == null) return stale;
    final lower = verdict.toLowerCase().replaceAll('-', '_');
    if (lower.contains('go') && !lower.contains('no_go') && !lower.contains('nogo')) {
      return go;
    }
    if (lower.contains('caution') || lower.contains('mod') || lower.contains('warning')) {
      return caution;
    }
    if (lower.contains('no_go') || lower.contains('nogo') || lower.contains('danger') || lower.contains('crit')) {
      return noGo;
    }
    if (lower.contains('info')) {
      return info;
    }
    return stale;
  }

  /// Maps string verdict to Card Background tint.
  static Color backgroundFromVerdict(String? verdict) {
    if (verdict == null) return infoBg;
    final lower = verdict.toLowerCase().replaceAll('-', '_');
    if (lower.contains('go') && !lower.contains('no_go') && !lower.contains('nogo')) {
      return goBg;
    }
    if (lower.contains('caution') || lower.contains('mod')) {
      return cautionBg;
    }
    if (lower.contains('no_go') || lower.contains('nogo') || lower.contains('danger')) {
      return noGoBg;
    }
    return infoBg;
  }

  /// Shape icon for low-literacy clarity (§7).
  static IconData iconForVerdict(String? verdict) {
    if (verdict == null) return Icons.help_outline;
    final lower = verdict.toLowerCase().replaceAll('-', '_');
    if (lower.contains('go') && !lower.contains('no_go') && !lower.contains('nogo')) {
      return Icons.check_circle; // ✔ ●
    }
    if (lower.contains('caution') || lower.contains('mod')) {
      return Icons.warning_rounded; // ⚠ ▲
    }
    if (lower.contains('no_go') || lower.contains('nogo') || lower.contains('danger')) {
      return Icons.dangerous; // ⛔ ■
    }
    return Icons.info_outline;
  }
}
