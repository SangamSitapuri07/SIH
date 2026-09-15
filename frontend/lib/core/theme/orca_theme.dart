import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'verdict_colors.dart';

/// ORCA design system.
///
/// The visual language follows the ORCA reference workspace: a near-white
/// marine canvas, white cards with hairline borders, deep-teal decision panels
/// and a single cyan/mint accent. Nothing in this file carries data — colour is
/// never used to imply that an unavailable measurement is verified.
class OrcaTheme {
  // ---- Canvas & cards ----
  // ---- Palette, measured from the reference workspace stylesheet ----------
  /// Page canvas: light marine wash (reference `--background` / `.orca-shell`).
  static const Color background = Color(0xFFF2F8F9);

  /// Sidebar and top bar surface (`.orca-sidebar` / `.orca-topbar`).
  static const Color sidebarSurface = Color(0xFFF8FCFC);

  static const Color surface = Color(0xFFFFFFFF);

  /// Low-emphasis tile fill (`.orca-route-stat div`, `.orca-bubble`).
  static const Color surfaceElevated = Color(0xFFF4FAFA);

  /// Slightly cooler fill used behind inputs (`#fbfefe`).
  static const Color surfaceSunken = Color(0xFFF3F9FA);

  static const Color inputFill = Color(0xFFFBFEFE);

  /// Card hairline (`.orca-card` border).
  static const Color cardBorder = Color(0xFFDCEBED);

  /// Structural hairlines: sidebar/top bar (`#d9e9eb`) and in-card dividers
  /// (`#e4eff0`).
  static const Color shellBorder = Color(0xFFD9E9EB);
  static const Color divider = Color(0xFFE4EFF0);
  static const Color dividerSoft = Color(0xFFE5EFF0);

  /// Input and outline borders (`#cfe2e5`) and filter chips (`#d6e7e8`).
  static const Color cardBorderStrong = Color(0xFFCFE2E5);
  /// `.orca-big-map` canvas: #d8efef with a #c7e0e2 frame.
  static const Color mapCanvas = Color(0xFFD8EFEF);
  static const Color mapFrame = Color(0xFFC7E0E2);
  static const Color chipBorder = Color(0xFFD6E7E8);

  /// Navy heading ink (`#12354a`) and the softer heading used inside cards.
  static const Color textPrimary = Color(0xFF12354A);
  static const Color headingSoft = Color(0xFF20495A);
  static const Color textSecondary = Color(0xFF68828C);
  static const Color textMuted = Color(0xFF78919A);
  static const Color textFaint = Color(0xFF91A4A8);

  /// Metric value ink (`.orca-metric-value`).
  static const Color metricInk = Color(0xFF153D52);

  /// Muted metric label ink (`.orca-metric-label`).
  static const Color metricLabelInk = Color(0xFF738D96);

  /// Positive metric footnote ink (`.orca-metric-foot`).
  static const Color metricFootInk = Color(0xFF4C9A92);

  /// Navigation link ink (`.orca-nav-link`).
  static const Color navInk = Color(0xFF52707B);

  /// Teal family: accent bar/ring, eyebrow text, icon ink, positive verdict.
  static const Color accent = Color(0xFF20B4B1);
  static const Color accentSoft = Color(0xFFD9F3F2);
  static const Color accentWash = Color(0xFFEAF6F7);
  static const Color accentDark = Color(0xFF149EA0);
  static const Color accentInk = Color(0xFF0F898A);
  static const Color accentDeep = Color(0xFF147B6A);

  /// Deep navy-teal used by the brand mark, primary buttons and the verdict
  /// panel.
  static const Color deepTeal = Color(0xFF143D52);
  static const Color deepTealElevated = Color(0xFF153E53);
  static const Color onDeepTeal = Color(0xFFC7E4E7);
  static const Color onDeepTealMuted = Color(0xFFAADADD);
  static const Color onDeepTealTitle = Color(0xFFD6F3F2);
  static const Color onDeepTealStrong = Color(0xFF88EDE5);
  static const Color onDeepTealEyebrow = Color(0xFF83E7E1);
  static const Color brandInk = Color(0xFF7DE8E5);

  static const Color primary = Color(0xFF153E53);

  /// Status pill pairs (`.orca-status-*`).
  static const Color liveBg = Color(0xFFE2F8F3);
  static const Color liveFg = Color(0xFF147A65);
  static const Color cachedBg = Color(0xFFE9F2F7);
  static const Color cachedFg = Color(0xFF427288);
  static const Color staleBg = Color(0xFFFFF2D8);
  static const Color staleFg = Color(0xFF9A6316);
  static const Color unavailableBg = Color(0xFFF2E9EA);
  static const Color unavailableFg = Color(0xFF914B52);

  /// Alert severity / result fills, exact reference pairs: high `#fde5e2` /
  /// `#c2453b`, medium `#fff1d7` / `#b77817`, low `#e2f4f3` / `#168b8c`.
  static const Color warnBg = Color(0xFFFFF1D7);
  static const Color warnFg = Color(0xFFB77817);
  static const Color warnBorder = Color(0xFFF2DFAE);
  static const Color dangerBg = Color(0xFFFDE5E2);
  static const Color dangerFg = Color(0xFFC2453B);
  static const Color dangerBorder = Color(0xFFF5D2CE);
  static const Color infoBg = Color(0xFFE2F4F3);
  static const Color infoFg = Color(0xFF168B8C);

  /// Count badge on the alerts nav item (`#e85e4f`).
  static const Color badge = Color(0xFFE85E4F);

  /// Verdict panel: `linear-gradient(140deg,#123c52 0%,#14536a 72%,#167180 100%)`.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: <double>[0.0, 0.72, 1.0],
    colors: <Color>[Color(0xFF123C52), Color(0xFF14536A), Color(0xFF167180)],
  );

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF143D52), Color(0xFF143D52)],
  );

  /// Card elevation: `0 8px 26px rgba(29,89,105,.045)`.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0C1D5969), blurRadius: 26, offset: Offset(0, 8)),
  ];

  /// Floating map chrome: stronger than a card so it reads over tiles.
  static const List<BoxShadow> floatingShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1F235B64), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// Brand mark elevation: `0 5px 14px rgba(24,73,91,.16)`.
  static const List<BoxShadow> markShadow = <BoxShadow>[
    BoxShadow(color: Color(0x2918495B), blurRadius: 14, offset: Offset(0, 5)),
  ];

  // ---- Layout tokens, measured from the reference stylesheet ----
  /// `.orca-sidebar` width (248px; 208px at <=1020px).
  static const double sidebarWidth = 248;
  static const double sidebarWidthCompact = 208;

  /// `.orca-content` padding and max width.
  static const double contentMaxWidth = 1380;
  static const double contentPadH = 34;
  static const double contentPadV = 27;
  static const double contentPadBottom = 46;

  /// `.orca-topbar` height.
  static const double topBarHeight = 79;

  /// Grid gutter used by every two-column workspace (18px).
  static const double gutter = 18;

  /// `.orca-card` corner radius (16px) and metric tile radius (13px).
  static const double cardRadius = 16;
  static const double tileRadius = 13;

  /// Breakpoints: 740 = reference mobile nav, 1020 = reference compact sidebar.
  static const double mobileBreakpoint = 740;
  static const double compactBreakpoint = 1020;

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
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accentSoft,
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: 'Inter',
              color: accentDark,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            );
          }
          return const TextStyle(
            fontFamily: 'Inter',
            color: textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentDark, size: 23);
          }
          return const IconThemeData(color: textSecondary, size: 21);
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
      splashFactory: InkSparkle.splashFactory,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: deepTeal,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: const BorderSide(color: cardBorderStrong, width: 1),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentDark,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        hintStyle: const TextStyle(fontFamily: 'Inter', color: textMuted, fontSize: 13.5),
        labelStyle: const TextStyle(fontFamily: 'Inter', color: textSecondary, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
    );
  }

  static TextTheme _interTextTheme(TextTheme base) {
    final style = base.copyWith(
      titleLarge: const TextStyle(
        fontFamily: 'Inter',
        color: textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 17,
      ),
      titleMedium: const TextStyle(
        fontFamily: 'Inter',
        color: textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
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
        fontSize: 14.5,
        height: 1.45,
      ),
      bodyMedium: const TextStyle(
        fontFamily: 'Inter',
        color: textSecondary,
        fontSize: 13,
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
        letterSpacing: 0.4,
      ),
      labelMedium: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 10.5,
        letterSpacing: 0.8,
      ),
      labelSmall: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w700,
        fontSize: 10,
        letterSpacing: 1.0,
      ),
    );
    return style.apply(fontFamily: 'Inter');
  }
}

/// Reusable type ramp, transcribed from the reference stylesheet so every
/// workspace shares one scale. Letter-spacing values are the CSS em values
/// converted to logical pixels for the same font size.
///
/// The reference loads Manrope; this build ships Inter (already bundled in
/// `assets/fonts`) and reproduces the sizes, weights, line-heights and tracking
/// exactly. Swap [kOrcaSans] for `Manrope` once a TTF is available.
const String kOrcaSans = 'Inter';

class OrcaType {
  const OrcaType._();

  /// `.orca-eyebrow`: 10px / .14em / 800 uppercase.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 10,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.accentDark,
  );

  static const TextStyle eyebrowMuted = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 10,
    letterSpacing: 1.4,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textMuted,
  );

  /// `.orca-h1`: clamp(28px, 3vw, 43px) / 1.06 / -.055em / 800.
  static const TextStyle display = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 43,
    height: 1.06,
    letterSpacing: -2.37,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textPrimary,
  );

  static const TextStyle displayCompact = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 30,
    height: 1.08,
    letterSpacing: -1.65,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textPrimary,
  );

  /// `.orca-h2`: 21px / 1.2 / -.035em / 800.
  static const TextStyle cardTitle = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 21,
    height: 1.2,
    letterSpacing: -0.74,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textPrimary,
  );

  /// Card sub-headings (`.orca-about-block h3`, `.orca-feed-title`).
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 15,
    height: 1.25,
    letterSpacing: -0.3,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.headingSoft,
  );

  /// `.orca-metric-value`: 23px / -.06em / 800.
  static const TextStyle metricValue = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 23,
    height: 1.05,
    letterSpacing: -1.38,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.metricInk,
  );

  /// `.orca-metric-unit`: 11px / 600.
  static const TextStyle metricUnit = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: OrcaTheme.textMuted,
  );

  /// `.orca-metric-label`: 11px / 700.
  static const TextStyle metricLabel = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    color: OrcaTheme.metricLabelInk,
  );

  /// `.orca-metric-foot`: 10px / 700 teal.
  static const TextStyle metricFoot = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: OrcaTheme.metricFootInk,
  );

  /// `.orca-muted`: 13px / 1.6.
  static const TextStyle body = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 13,
    height: 1.6,
    color: OrcaTheme.textSecondary,
  );

  /// Table/metadata copy: 11-12px with 1.45-1.5 leading.
  static const TextStyle cardBody = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 12,
    height: 1.5,
    color: OrcaTheme.textSecondary,
  );

  /// Smallest metadata line (`.orca-alert-sub`, `.orca-reason-copy`).
  static const TextStyle caption = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 11,
    height: 1.45,
    color: OrcaTheme.textMuted,
  );

  /// `.orca-go`: 68px / .92 / -.09em 800 in mint.
  static const TextStyle heroVerdict = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 68,
    height: 0.92,
    letterSpacing: -6.12,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.onDeepTealStrong,
  );

  static const TextStyle heroVerdictCompact = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 60,
    height: 0.94,
    letterSpacing: -5.4,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.onDeepTealStrong,
  );

  /// `.orca-verdict-title`: 14px / 700.
  static const TextStyle heroTitle = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: OrcaTheme.onDeepTealTitle,
  );

  /// `.orca-verdict-copy`: 13px / 1.6 (max 540px in the panel).
  static const TextStyle heroBody = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 13,
    height: 1.6,
    color: OrcaTheme.onDeepTeal,
  );

  /// `.orca-nav-link`: 13px / 700.
  static const TextStyle navLink = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: OrcaTheme.navInk,
  );

  /// `.orca-button`: 12px / 800.
  static const TextStyle button = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  /// `.orca-status`: 9px / .08em / 800 uppercase.
  static const TextStyle statusPill = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 9,
    letterSpacing: 0.72,
    fontWeight: FontWeight.w800,
  );

  /// `.orca-bubble`: 12px / 1.65.
  static const TextStyle bubble = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 12,
    height: 1.65,
    color: OrcaTheme.headingSoft,
  );

  /// `.orca-msg-label`: 9px / .1em / 800.
  static const TextStyle messageLabel = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 9,
    letterSpacing: 0.9,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textFaint,
  );

  /// `.orca-field label`: 10px / .09em / 800 uppercase.
  static const TextStyle fieldLabel = TextStyle(
    fontFamily: kOrcaSans,
    fontSize: 10,
    letterSpacing: 0.9,
    fontWeight: FontWeight.w800,
    color: OrcaTheme.textMuted,
  );
}
