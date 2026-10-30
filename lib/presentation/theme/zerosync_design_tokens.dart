import 'package:flutter/material.dart';

/// Available visual theme modes for the ZeroSync air-gap interface.
enum ZeroSyncThemeMode {
  light,
  dark,
  oledBlack,
  highContrastAmber,
}

/// Strictly typed primitive color tokens.
class ZeroSyncColors {
  ZeroSyncColors._();

  // Brand & Optical Spectrum
  static const Color cyan = Color(0xFF00E5FF);
  static const Color emerald = Color(0xFF00E676);
  static const Color amber = Color(0xFFFFB300);
  static const Color electricBlue = Color(0xFF2979FF);

  // Status & Telemetry
  static const Color success = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFD600);
  static const Color error = Color(0xFFFF1744);
  static const Color info = Color(0xFF2979FF);

  // High-Contrast OLED Neutrals
  static const Color trueBlack = Color(0xFF000000);
  static const Color trueWhite = Color(0xFFFFFFFF);
  static const Color darkGraphite = Color(0xFF121418);
  static const Color darkSlate = Color(0xFF1E222A);
  static const Color darkBorder = Color(0xFF2E3440);

  // Light Mode Neutrals
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
}

/// Spacing tokens following a strict 4pt/8pt optical baseline.
class ZeroSyncSpacing {
  ZeroSyncSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);
}

/// Border radius tokens for geometric consistency.
class ZeroSyncRadii {
  ZeroSyncRadii._();

  static const double none = 0.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double full = 9999.0;

  static const BorderRadius radiusSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius radiusMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius radiusLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius radiusFull =
      BorderRadius.all(Radius.circular(full));
}

/// Optical HUD typography scales optimized for legibility at viewing distance.
class ZeroSyncTypography {
  ZeroSyncTypography._();

  static const String monospaceFont = 'monospace';

  static const TextStyle displayLarge = TextStyle(
    fontSize: 28.0,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  // Optical Telemetry Typography (Monospace)
  static const TextStyle telemetryHeader = TextStyle(
    fontFamily: monospaceFont,
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  static const TextStyle telemetryBody = TextStyle(
    fontFamily: monospaceFont,
    fontSize: 13.0,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle telemetryCode = TextStyle(
    fontFamily: monospaceFont,
    fontSize: 11.0,
    fontWeight: FontWeight.normal,
  );
}

/// Cohesive Theme Engine generating light, dark, OLED, and high-contrast theme variations.
class ZeroSyncTheme {
  ZeroSyncTheme._();

  /// Builds a [ThemeData] instance according to the chosen [ZeroSyncThemeMode].
  static ThemeData buildTheme(ZeroSyncThemeMode mode) {
    switch (mode) {
      case ZeroSyncThemeMode.light:
        return _buildLightTheme();
      case ZeroSyncThemeMode.dark:
        return _buildDarkTheme();
      case ZeroSyncThemeMode.oledBlack:
        return _buildOledBlackTheme();
      case ZeroSyncThemeMode.highContrastAmber:
        return _buildHighContrastAmberTheme();
    }
  }

  static ThemeData get lightTheme => _buildLightTheme();
  static ThemeData get darkTheme => _buildDarkTheme();
  static ThemeData get oledBlackTheme => _buildOledBlackTheme();
  static ThemeData get highContrastAmberTheme => _buildHighContrastAmberTheme();

  static ThemeData _buildLightTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: ZeroSyncColors.electricBlue,
      onPrimary: Colors.white,
      secondary: ZeroSyncColors.cyan,
      onSecondary: Colors.black,
      error: ZeroSyncColors.error,
      onError: Colors.white,
      surface: ZeroSyncColors.lightSurface,
      onSurface: ZeroSyncColors.lightTextPrimary,
      outline: ZeroSyncColors.lightBorder,
    );

    return _assembleTheme(
      colorScheme: colorScheme,
      scaffoldBg: ZeroSyncColors.lightBackground,
      cardBg: ZeroSyncColors.lightSurface,
      textPrimary: ZeroSyncColors.lightTextPrimary,
      textSecondary: ZeroSyncColors.lightTextSecondary,
    );
  }

  static ThemeData _buildDarkTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ZeroSyncColors.cyan,
      onPrimary: Colors.black,
      secondary: ZeroSyncColors.emerald,
      onSecondary: Colors.black,
      error: ZeroSyncColors.error,
      onError: Colors.white,
      surface: ZeroSyncColors.darkSlate,
      onSurface: Colors.white,
      outline: ZeroSyncColors.darkBorder,
    );

    return _assembleTheme(
      colorScheme: colorScheme,
      scaffoldBg: ZeroSyncColors.darkGraphite,
      cardBg: ZeroSyncColors.darkSlate,
      textPrimary: Colors.white,
      textSecondary: Colors.grey.shade400,
    );
  }

  static ThemeData _buildOledBlackTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ZeroSyncColors.cyan,
      onPrimary: Colors.black,
      secondary: ZeroSyncColors.emerald,
      onSecondary: Colors.black,
      error: ZeroSyncColors.error,
      onError: Colors.white,
      surface: ZeroSyncColors.trueBlack,
      onSurface: Colors.white,
      outline: Colors.white24,
    );

    return _assembleTheme(
      colorScheme: colorScheme,
      scaffoldBg: ZeroSyncColors.trueBlack,
      cardBg: ZeroSyncColors.trueBlack,
      textPrimary: Colors.white,
      textSecondary: Colors.white70,
      isOled: true,
    );
  }

  static ThemeData _buildHighContrastAmberTheme() {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ZeroSyncColors.amber,
      onPrimary: Colors.black,
      secondary: ZeroSyncColors.amber,
      onSecondary: Colors.black,
      error: ZeroSyncColors.error,
      onError: Colors.white,
      surface: Colors.black,
      onSurface: ZeroSyncColors.amber,
      outline: ZeroSyncColors.amber,
    );

    return _assembleTheme(
      colorScheme: colorScheme,
      scaffoldBg: Colors.black,
      cardBg: Colors.black,
      textPrimary: ZeroSyncColors.amber,
      textSecondary: ZeroSyncColors.amber,
      isHighContrast: true,
    );
  }

  static ThemeData _assembleTheme({
    required ColorScheme colorScheme,
    required Color scaffoldBg,
    required Color cardBg,
    required Color textPrimary,
    required Color textSecondary,
    bool isOled = false,
    bool isHighContrast = false,
  }) {
    final baseTextTheme = TextTheme(
      displayLarge:
          ZeroSyncTypography.displayLarge.copyWith(color: textPrimary),
      headlineMedium:
          ZeroSyncTypography.headlineMedium.copyWith(color: textPrimary),
      titleMedium: ZeroSyncTypography.titleMedium.copyWith(color: textPrimary),
      bodyLarge: ZeroSyncTypography.bodyLarge.copyWith(color: textPrimary),
      bodyMedium: ZeroSyncTypography.bodyMedium.copyWith(color: textSecondary),
      labelSmall: ZeroSyncTypography.labelSmall.copyWith(color: textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: baseTextTheme,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: isOled || isHighContrast ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: ZeroSyncRadii.radiusMd,
          side: isHighContrast
              ? const BorderSide(color: ZeroSyncColors.amber, width: 2)
              : isOled
                  ? const BorderSide(color: Colors.white24, width: 1)
                  : BorderSide.none,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: const RoundedRectangleBorder(
              borderRadius: ZeroSyncRadii.radiusSm),
          padding: const EdgeInsets.symmetric(
            horizontal: ZeroSyncSpacing.lg,
            vertical: ZeroSyncSpacing.md,
          ),
        ),
      ),
    );
  }
}
