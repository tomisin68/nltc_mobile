import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// Builds the light and dark Blueprint themes.
///
/// Screens must never reach for [BlueprintPalette] directly — read from
/// `Theme.of(context).colorScheme` so both modes stay correct for free.
abstract final class AppTheme {
  static ThemeData get light => _build(_lightScheme, Brightness.light);
  static ThemeData get dark => _build(_darkScheme, Brightness.dark);

  // ─── Colour schemes ───────────────────────────────────────────────────────

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: BlueprintPalette.b500,
    onPrimary: BlueprintPalette.white,
    primaryContainer: BlueprintPalette.b100,
    onPrimaryContainer: BlueprintPalette.b800,
    secondary: BlueprintPalette.b700,
    onSecondary: BlueprintPalette.white,
    secondaryContainer: BlueprintPalette.b100,
    onSecondaryContainer: BlueprintPalette.b800,
    tertiary: BlueprintPalette.success,
    onTertiary: BlueprintPalette.white,
    tertiaryContainer: BlueprintPalette.successBg,
    onTertiaryContainer: Color(0xFF064E3B),
    error: BlueprintPalette.error,
    onError: BlueprintPalette.white,
    errorContainer: BlueprintPalette.errorBg,
    onErrorContainer: Color(0xFF7F1D1D),
    surface: BlueprintPalette.white,
    onSurface: BlueprintPalette.text1,
    onSurfaceVariant: BlueprintPalette.text2,
    surfaceContainerLowest: BlueprintPalette.white,
    surfaceContainerLow: BlueprintPalette.b50,
    surfaceContainer: BlueprintPalette.b50,
    surfaceContainerHigh: BlueprintPalette.b100,
    surfaceContainerHighest: Color(0xFFCFE0FB),
    outline: Color(0xFFC3D4EC),
    outlineVariant: Color(0xFFE1EAF7),
    inverseSurface: BlueprintPalette.b900,
    onInverseSurface: BlueprintPalette.b100,
    inversePrimary: BlueprintPalette.b300,
    shadow: Color(0x1A092A5E),
    scrim: Color(0x9902102B),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    // Lifted to b400 — b500 on a near-black navy misses the 4.5:1 bar for
    // body text, while b400 clears it comfortably in both directions.
    primary: BlueprintPalette.b400,
    onPrimary: BlueprintPalette.ink,
    primaryContainer: BlueprintPalette.b800,
    onPrimaryContainer: BlueprintPalette.b100,
    secondary: BlueprintPalette.b300,
    onSecondary: BlueprintPalette.ink,
    secondaryContainer: BlueprintPalette.b800,
    onSecondaryContainer: BlueprintPalette.b100,
    tertiary: Color(0xFF34D399),
    onTertiary: Color(0xFF022C22),
    tertiaryContainer: Color(0xFF065F46),
    onTertiaryContainer: Color(0xFFD1FAE5),
    error: Color(0xFFFF6B6B),
    onError: Color(0xFF450A0A),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: BlueprintPalette.errorBg,
    surface: BlueprintPalette.darkBg,
    onSurface: BlueprintPalette.b100,
    onSurfaceVariant: BlueprintPalette.b300,
    surfaceContainerLowest: BlueprintPalette.ink,
    surfaceContainerLow: BlueprintPalette.darkSurface,
    surfaceContainer: BlueprintPalette.darkSurface,
    surfaceContainerHigh: BlueprintPalette.darkSurfaceHigh,
    surfaceContainerHighest: BlueprintPalette.darkSurfaceHighest,
    outline: Color(0xFF2A4573),
    outlineVariant: Color(0xFF1A2F55),
    inverseSurface: BlueprintPalette.b100,
    onInverseSurface: BlueprintPalette.b900,
    inversePrimary: BlueprintPalette.b600,
    shadow: Color(0xFF000000),
    scrim: Color(0xCC000000),
  );

  // ─── Typography ───────────────────────────────────────────────────────────

  /// Body/UI face — matches `--font-body` on the web.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    // Display styles use Fraunces (`--font-head`) for the few editorial
    // moments — onboarding, score reveal — where the brand voice matters.
    final display = GoogleFonts.frauncesTextTheme();

    return base
        .copyWith(
          displayLarge: display.displayLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -1.0,
          ),
          displayMedium: display.displayMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.8,
          ),
          displaySmall: display.displaySmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
          headlineLarge: base.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          // 16px base with 1.5 line-height — the readable default. Exam
          // questions lean on bodyLarge, so it must not be cramped.
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, height: 1.5),
          bodySmall: base.bodySmall?.copyWith(fontSize: 13, height: 1.45),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        )
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          decorationColor: scheme.onSurface,
        );
  }

  // ─── Assembly ─────────────────────────────────────────────────────────────

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final text = _textTheme(scheme);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: isDark
          ? scheme.surface
          : BlueprintPalette.b50,
      textTheme: text,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? scheme.surface : BlueprintPalette.b50,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      // Every button clears the 48dp touch target without callers thinking
      // about it.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, Tokens.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.rMd),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, Tokens.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.s6),
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.rMd),
          ),
          textStyle: text.labelLarge?.copyWith(fontSize: 15.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, Tokens.minTouchTarget),
          textStyle: text.labelLarge,
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rLg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? scheme.surfaceContainerLow
            : BlueprintPalette.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.s4,
          vertical: Tokens.s4,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? scheme.surfaceContainerLow
            : BlueprintPalette.white,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rXl),
        ),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.rXl)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rSm),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),

      listTileTheme: ListTileThemeData(
        minVerticalPadding: Tokens.s3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.rMd),
        ),
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
