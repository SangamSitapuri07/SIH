import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'verdict_colors.dart';

/// ORCA design system — light marine palette matched to the reference UI
/// (#F2F8F9 canvas, white cards, deep-teal hero panels, cyan #18BBC3 accent,
/// Inter typography). Same static API as before so every existing widget
/// rethemes automatically; new tokens cover the hero/panel surfaces.
class OrcaTheme {
  // ---- Canvas & cards (light marine) ----
  static const Color background = Color(0xFFF2F8F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFE9F5F5);
  static const Color cardBorder = Color(0xFFDCE9EB);

  // ---- Text ----
  static const Color textPrimary = Color(0xFF16303F);
  static const Color textSecondary = Color(0xFF5B7A8C);
  static const Color textMuted = Color(0xFF8AA5B1);

  // ---- Accent (cyan) ----
  static const Color accent = Color(0xFF18BBC3);
  static const Color accentSoft = Color(0xFFD9F3F2);
  static const Color accentDark = Color(0xFF0C7C84);

  // ---- Deep teal hero panels (map/hero cards) ----
  static const Color deepTeal = Color(0xFF153E53);
  static const Color deepTealElevated = Color(0xFF1C4E68);
  static const Color onDeepTeal = Color(0xFFEAF6F8);
  static const Color onDeepTealMuted = Color(0xFF9DBECB);

  // ---- Primary (deep marine navy) ----
  static const Color primary = Color(0xFF143C5C);

  static ThemeData get darkTheme => theme;

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: VerdictColors.critical,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
    );
    return base.copyWith(
      textTheme: _interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: const TextStyle(
          fontFamily: 'Inter',
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentSoft,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Inter',
              color: accentDark,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            );
          }
          return const TextStyle(
            fontFamily: 'Inter',
            color: textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 11.5,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentDark, size: 24);
          }
          return const IconThemeData(color: textSecondary, size: 22);
        }),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1.0),
        ),
      ),
      dividerTheme: const DividerThemeData(color: cardBorder, thickness: 1),
      splashFactory: InkRipple.splashFactory,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48), // >= 48px touch target
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 48),
          side: const BorderSide(color: cardBorder, width: 1.2),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(
            fontFamily: 'Inter', color: textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  static TextTheme _interTextTheme(TextTheme base) {
    final style = base.copyWith(
      displayLarge: base.displayLarge?.copyWith(color: textPrimary),
      displayMedium: base.displayMedium?.copyWith(color: textPrimary),
      displaySmall: base.displaySmall?.copyWith(color: textPrimary),
      headlineLarge: base.headlineLarge?.copyWith(color: textPrimary),
      headlineMedium: base.headlineMedium?.copyWith(color: textPrimary),
      headlineSmall: base.headlineSmall?.copyWith(color: textPrimary),
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        color: textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      titleSmall: const TextStyle(
        fontFamily: 'Inter',
        color: textSecondary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      bodyLarge: const TextStyle(
        fontFamily: 'Inter',
        color: textPrimary,
        fontSize: 15,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        color: textSecondary,
        fontSize: 13.5,
        height: 1.4,
      ),
      bodySmall: const TextStyle(
        fontFamily: 'Inter',
        color: textMuted,
        fontSize: 11.5,
      ),
      labelLarge: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 0.6,
      ),
      labelMedium: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 11,
        letterSpacing: 0.8,
      ),
      labelSmall: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 10,
        letterSpacing: 1.0,
      ),
    );
    // Apply the Inter family to every style not explicitly overridden above.
    return style.apply(fontFamily: 'Inter');
  }
}
