import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ===========================================================================
// Be@Mandaluyong — Design System
// ---------------------------------------------------------------------------
// A small set of design tokens (color, type, spacing, radius) plus the app
// theme that wires them into Material 3. Build screens from these tokens so
// the whole app stays consistent.
// ===========================================================================

/// Corner-radius scale. Use these instead of raw numbers so every surface
/// shares the same rounding language.
class AppRadius {
  AppRadius._();
  static const double sm = 12; // chips, small controls, thumbnails
  static const double md = 16; // buttons, inputs
  static const double lg = 20; // cards, sheets
  static const double xl = 28; // hero / banner surfaces
  static const double pill = 999; // fully rounded
}

/// 4-point spacing scale. Use for padding, gaps and margins.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20; // default screen padding
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Central place for the app's look & feel.
///
/// Colors are based on the official City of Mandaluyong flag & seal:
/// the flag's blue (calm, civic base) and the seal's gold sun as a warm
/// accent, with the bold city red reserved for identity moments.
class AppTheme {
  AppTheme._();

  // --- Brand colors --------------------------------------------------------
  static const Color brandBlue = Color(0xFF0038A8); // flag blue (seed/primary)
  static const Color brandGold = Color(0xFFFCD116); // seal sun (accent)

  /// Bold Mandaluyong seal red — identity accent only (logout, branding).
  static const Color cityRed = Color(0xFFCE1126);

  // --- Semantic colors -----------------------------------------------------
  // "Verified / success" is a brand moment on the trail, so it gets a defined,
  // accessible green rather than a raw Colors.green.
  static const Color success = Color(0xFF1E8E3E); // AA on white
  static const Color _successDark = Color(0xFF6CCB8B); // for dark surfaces
  static const Color successContainer = Color(0xFFE6F4EA);

  /// Success color tuned for the current brightness.
  static Color successFor(Brightness b) =>
      b == Brightness.dark ? _successDark : success;

  /// Brand display style — a warm serif used for the welcome / brand title to
  /// give the heritage app a touch of character. Body text stays sans.
  static TextStyle brandTextStyle({
    double fontSize = 32,
    Color? color,
    FontWeight fontWeight = FontWeight.w800,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.1,
      );

  // --- Themes --------------------------------------------------------------
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    // Harmonious Material 3 scheme seeded with the Mandaluyong blue; tones are
    // softened automatically so nothing is harsh. Gold is pinned as the accent.
    final base =
        ColorScheme.fromSeed(seedColor: brandBlue, brightness: brightness);
    final scheme = base.copyWith(
      tertiary: brandGold,
      onTertiary: Colors.black, // gold must always carry dark content
      tertiaryContainer: brandGold,
      onTertiaryContainer: Colors.black,
    );

    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,

      // App bar: flat, surface-colored, gains a subtle tint on scroll.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),

      // Rounded, flat tonal cards with a hairline border for definition.
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),

      // Primary action: filled, comfortable tap height for all ages.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge),
      ),

      // Soft, filled inputs.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.l,
          vertical: AppSpacing.l,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),

      // Chips (era / nearest-landmark badges) consistent with the scale.
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        labelStyle: text.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 6),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 3,
        height: 68,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: AppSpacing.xxl,
      ),
    );
  }

  /// One deliberate type scale, set in Plus Jakarta Sans (legible, friendly,
  /// civic). Body sizes are bumped to 16+ with relaxed line-height for easy
  /// reading across ages.
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = GoogleFonts.plusJakartaSansTextTheme();
    return base
        .copyWith(
          displaySmall:
              base.displaySmall?.copyWith(fontWeight: FontWeight.w800, height: 1.15),
          headlineMedium:
              base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
          headlineSmall:
              base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
          titleLarge: base.titleLarge
              ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
          titleMedium: base.titleMedium
              ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 16.5, height: 1.45),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 15.5, height: 1.45),
          labelLarge: base.labelLarge
              ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}
