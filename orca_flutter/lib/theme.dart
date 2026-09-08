import 'package:flutter/material.dart';

/// ORCA theme — ORIGINAL reference theme (user-locked 2026-09-08):
/// white background + teal-green, simple flat cards. Plan: docs/FLUTTER-PLAN.md §4.
class OrcaTheme {
  // ── locked tokens (light/default) ──────────────────────────────
  static const teal = Color(0xFF14B8A6);       // primary
  static const tealDeep = Color(0xFF0D9488);   // hero gradient start
  static const okGreen = Color(0xFF22C55E);    // GO / healthy
  static const warnAmber = Color(0xFFF59E0B);  // caution / stale
  static const dangerRed = Color(0xFFEF4444);  // NO-GO / risk / SOS
  static const inkText = Color(0xFF1F2937);    // body
  static const subText = Color(0xFF6B7280);    // subtitles
  static const cardLine = Color(0xFFE5EAF0);   // hairline
  static const surfaceAlt = Color(0xFFF3F6F9); // input bar / inactive chips
  static const mintChip = Color(0xFFCCFBF1);   // avatar / agent pills
  static const alertBg = Color(0xFFFFF7EA);    // amber alert card
  static const dhoopYellow = Color(0xFFFFE600);

  /// LIGHT — app ka default look (white bg + teal).
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      secondary: tealDeep,
      surface: Colors.white,
      error: dangerRed,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      cardColor: Colors.white,
      dividerColor: cardLine,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: inkText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: inkText, fontSize: 15),
        titleLarge: TextStyle(color: inkText, fontWeight: FontWeight.w800),
      ),
    );
  }

  /// DARK — raat ki sailing ke liye (optional toggle; structure same).
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      primary: teal,
      surface: const Color(0xFF1E293B),
      error: dangerRed,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      cardColor: const Color(0xFF1E293B),
      dividerColor: const Color(0xFF273449),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Color(0xFFE5EAF0),
        elevation: 0,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Color(0xFFE5EAF0), fontSize: 15),
        titleLarge: TextStyle(color: Color(0xFFE5EAF0), fontWeight: FontWeight.w800),
      ),
    );
  }

  /// DHOOP — deck pe seedhi dhoop: yellow on pure black, ultra contrast.
  /// Palette-independent (sun-tested survival mode).
  static ThemeData dhoop() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      cardColor: const Color(0xFF0A0A00),
      dividerColor: const Color(0xFF3A3A00),
      colorScheme: const ColorScheme.dark(
        primary: dhoopYellow,
        secondary: dhoopYellow,
        surface: Color(0xFF0A0A00),
        onPrimary: Colors.black,
        onSurface: dhoopYellow,
        error: Color(0xFFFF6B6B), // SOS dhoop mein bhi red-family rahe
      ),
      iconTheme: const IconThemeData(color: dhoopYellow),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: dhoopYellow, fontSize: 15, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: dhoopYellow, fontWeight: FontWeight.w800),
      ),
    );
  }
}
