import 'package:flutter/material.dart';

/// Raw Blueprint palette — the single source of colour truth.
///
/// These values are lifted verbatim from the web app's design system
/// (`src/styles/globals.css`) so the app and the website read as one product.
/// Nothing outside this file should hardcode a hex value; screens read colours
/// from `Theme.of(context).colorScheme` instead.
abstract final class BlueprintPalette {
  // ─── Blue ramp ────────────────────────────────────────────────────────────
  static const ink = Color(0xFF02102B);
  static const b900 = Color(0xFF041838);
  static const b800 = Color(0xFF06316E);
  static const b700 = Color(0xFF0A47A0);
  static const b600 = Color(0xFF1259D6);
  static const b500 = Color(0xFF1D6FF2); // brand primary
  static const b400 = Color(0xFF4D93FF);
  static const b300 = Color(0xFF8AB8FF);
  static const b200 = Color(0xFFBFDBFF);
  static const b100 = Color(0xFFE3EEFF);
  static const b50 = Color(0xFFF4F8FF);

  static const white = Color(0xFFFFFFFF);

  // ─── Light-mode text ramp ────────────────────────────────────────────────
  static const text1 = Color(0xFF092A5E);
  static const text2 = Color(0xFF3B5B8C);

  /// Decorative / disabled only — 3.1:1 on white, below the 4.5:1 body-text bar.
  static const text3 = Color(0xFF7C96BE);

  // ─── Dark-mode surface ramp ──────────────────────────────────────────────
  // The website has no dark theme, so this ramp is new. It keeps the navy
  // brand cast rather than going neutral grey, which would read as a
  // different product.
  static const darkBg = Color(0xFF02102B);
  static const darkSurface = Color(0xFF071A3A);
  static const darkSurfaceHigh = Color(0xFF0C244C);
  static const darkSurfaceHighest = Color(0xFF123061);

  // ─── Semantic ───────────────────────────────────────────────────────────
  static const success = Color(0xFF10B981);
  static const successBg = Color(0xFFD1FAE5);
  static const error = Color(0xFFEF4444);
  static const errorBg = Color(0xFFFEE2E2);
  static const warning = Color(0xFFF59E0B);
  static const warningBg = Color(0xFFFEF3C7);
}

/// Design tokens that aren't colours: radii, spacing and elevation.
///
/// Mirrors the `--r-*` and `--shadow-*` custom properties on the web.
abstract final class Tokens {
  // Radii
  static const rXs = 6.0;
  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 20.0;
  static const rXl = 28.0;

  // Spacing — 4pt grid
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;

  /// Minimum tappable edge. Android/iOS guidance is 48dp/44pt; we take the
  /// larger so one number is safe on both.
  static const minTouchTarget = 48.0;
}

/// Motion tokens. Durations sit in the 150–300ms band where transitions read
/// as responsive rather than sluggish; anything longer is reserved for
/// full-screen choreography.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);

  /// Entrances ease out (decelerate into place); exits ease in and run
  /// shorter, so dismissals never feel like they're dragging.
  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
}
