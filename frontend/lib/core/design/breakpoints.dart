import 'package:flutter/widgets.dart';

/// Layout breakpoints for ORCA's responsive shell.
///
/// The reference product is a two-mode experience, not a single layout that
/// is squeezed: a desktop workspace with a permanent compact rail and a wide
/// content canvas, and a mobile app with a real top app bar, map-first
/// surfaces and bottom sheets. These thresholds are the single place where
/// that decision is made so every screen agrees.
class OrcaBreakpoints {
  /// At or above this width the persistent navigation rail is shown and
  /// screens may use side-by-side workspace layouts.
  static const double desktop = 1000;

  /// At or above this width screens may use the widest three-column /
  /// large-inspector arrangements.
  static const double wide = 1360;

  /// Below this width layouts must collapse to a single column and rely on
  /// sheets rather than inline side panels.
  static const double compact = 640;

  /// At or above this width the map screen can afford a permanent side
  /// inspector next to the canvas. It is lower than [desktop] because the map
  /// keeps its own full-bleed canvas and does not carry body text.
  static const double mapInspector = 900;

  /// Maximum readable content width inside the desktop workspace, so the
  /// page does not stretch to unreadable line lengths on very wide monitors.
  static const double contentMaxWidth = 1320;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;
}
