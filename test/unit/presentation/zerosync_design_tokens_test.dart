import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';

void main() {
  group('ZeroSyncColors & Neutrals Specs', () {
    test('Defines distinct high-contrast and brand optical colors', () {
      expect(ZeroSyncColors.trueBlack, const Color(0xFF000000));
      expect(ZeroSyncColors.trueWhite, const Color(0xFFFFFFFF));
      expect(ZeroSyncColors.cyan, const Color(0xFF00E5FF));
      expect(ZeroSyncColors.amber, const Color(0xFFFFB300));
      expect(ZeroSyncColors.emerald, const Color(0xFF00E676));
      expect(ZeroSyncColors.electricBlue, const Color(0xFF2979FF));
    });

    test('Semantic status colors are defined and accessible', () {
      expect(ZeroSyncColors.success, isA<Color>());
      expect(ZeroSyncColors.warning, isA<Color>());
      expect(ZeroSyncColors.error, isA<Color>());
      expect(ZeroSyncColors.info, isA<Color>());
    });
  });

  group('Spacing & Radii Scale Invariants', () {
    test('Spacing tokens maintain strict monotonic progression', () {
      expect(ZeroSyncSpacing.xxs, lessThan(ZeroSyncSpacing.xs));
      expect(ZeroSyncSpacing.xs, lessThan(ZeroSyncSpacing.sm));
      expect(ZeroSyncSpacing.sm, lessThan(ZeroSyncSpacing.md));
      expect(ZeroSyncSpacing.md, lessThan(ZeroSyncSpacing.lg));
      expect(ZeroSyncSpacing.lg, lessThan(ZeroSyncSpacing.xl));
      expect(ZeroSyncSpacing.xl, lessThan(ZeroSyncSpacing.xxl));
      expect(ZeroSyncSpacing.xxl, lessThan(ZeroSyncSpacing.xxxl));
    });

    test('Pre-configured EdgeInsets match corresponding scalar tokens', () {
      expect(ZeroSyncSpacing.paddingSm, const EdgeInsets.all(ZeroSyncSpacing.sm));
      expect(ZeroSyncSpacing.paddingMd, const EdgeInsets.all(ZeroSyncSpacing.md));
      expect(ZeroSyncSpacing.paddingLg, const EdgeInsets.all(ZeroSyncSpacing.lg));
    });

    test('BorderRadius tokens maintain curvature hierarchy', () {
      expect(ZeroSyncRadii.xs, lessThan(ZeroSyncRadii.sm));
      expect(ZeroSyncRadii.sm, lessThan(ZeroSyncRadii.md));
      expect(ZeroSyncRadii.md, lessThan(ZeroSyncRadii.lg));
      expect(ZeroSyncRadii.lg, lessThan(ZeroSyncRadii.full));
    });
  });

  group('ZeroSyncTypography & Optical HUD Specs', () {
    test('Telemetry typography scales enforce monospace font family', () {
      expect(ZeroSyncTypography.telemetryHeader.fontFamily, equals('monospace'));
      expect(ZeroSyncTypography.telemetryBody.fontFamily, equals('monospace'));
      expect(ZeroSyncTypography.telemetryCode.fontFamily, equals('monospace'));
    });

    test('Standard typography scales have hierarchical sizing', () {
      expect(
        ZeroSyncTypography.displayLarge.fontSize!,
        greaterThan(ZeroSyncTypography.headlineMedium.fontSize!),
      );
      expect(
        ZeroSyncTypography.headlineMedium.fontSize!,
        greaterThan(ZeroSyncTypography.titleMedium.fontSize!),
      );
      expect(
        ZeroSyncTypography.titleMedium.fontSize!,
        greaterThan(ZeroSyncTypography.bodyLarge.fontSize!),
      );
    });
  });

  group('ZeroSyncTheme Cohesive Builders Specs', () {
    test('Builds valid Light theme with expected brightness and surfaces', () {
      final theme = ZeroSyncTheme.buildTheme(ZeroSyncThemeMode.light);

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, ZeroSyncColors.electricBlue);
      expect(theme.scaffoldBackgroundColor, ZeroSyncColors.lightBackground);
      expect(theme.cardTheme.color, ZeroSyncColors.lightSurface);
      expect(theme.useMaterial3, isTrue);
    });

    test('Builds valid Dark theme with slate surfaces and cyan primary', () {
      final theme = ZeroSyncTheme.buildTheme(ZeroSyncThemeMode.dark);

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, ZeroSyncColors.cyan);
      expect(theme.scaffoldBackgroundColor, ZeroSyncColors.darkGraphite);
      expect(theme.cardTheme.color, ZeroSyncColors.darkSlate);
    });

    test('Builds valid OLED Black theme with true pitch-black surfaces', () {
      final theme = ZeroSyncTheme.buildTheme(ZeroSyncThemeMode.oledBlack);

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, ZeroSyncColors.trueBlack);
      expect(theme.cardTheme.color, ZeroSyncColors.trueBlack);
      expect(theme.cardTheme.elevation, equals(0));
    });

    test('Builds High-Contrast Amber theme with amber text on pure black', () {
      final theme = ZeroSyncTheme.buildTheme(ZeroSyncThemeMode.highContrastAmber);

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, ZeroSyncColors.amber);
      expect(theme.scaffoldBackgroundColor, Colors.black);
      expect(theme.cardTheme.color, Colors.black);
      expect(theme.cardTheme.elevation, equals(0));

      final border = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(border.side.color, ZeroSyncColors.amber);
      expect(border.side.width, equals(2.0));
    });

    test('Direct getters expose same theme instances', () {
      expect(ZeroSyncTheme.lightTheme.brightness, Brightness.light);
      expect(ZeroSyncTheme.darkTheme.brightness, Brightness.dark);
      expect(ZeroSyncTheme.oledBlackTheme.scaffoldBackgroundColor, ZeroSyncColors.trueBlack);
      expect(ZeroSyncTheme.highContrastAmberTheme.colorScheme.primary, ZeroSyncColors.amber);
    });
  });
}
