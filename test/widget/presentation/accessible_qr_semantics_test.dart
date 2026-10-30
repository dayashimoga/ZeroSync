import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/accessible_qr_semantics.dart';

void main() {
  group('WcagContrastRatio Specs', () {
    test(
        'Calculates mathematically sound relative luminance and contrast ratios',
        () {
      const black = Colors.black;
      const white = Colors.white;

      expect(WcagContrastRatio.calculateLuminance(black), equals(0.0));
      expect(WcagContrastRatio.calculateLuminance(white), closeTo(1.0, 0.001));

      // Black on White maximum theoretical contrast is 21.0:1
      final ratio = WcagContrastRatio.calculateRatio(black, white);
      expect(ratio, closeTo(21.0, 0.1));

      expect(WcagContrastRatio.isWcagAaCompliant(black, white), isTrue);
      expect(WcagContrastRatio.isWcagAaaCompliant(black, white), isTrue);

      // Identical colors yield 1:1 contrast and fail AA
      expect(WcagContrastRatio.calculateRatio(black, black), equals(1.0));
      expect(WcagContrastRatio.isWcagAaCompliant(black, black), isFalse);
    });

    test('Validates WCAG 2.1 AA compliance for ZeroSync design tokens', () {
      // OLED True Black vs High-Visibility Optical Cyan
      expect(
        WcagContrastRatio.isWcagAaCompliant(
          ZeroSyncColors.cyan,
          ZeroSyncColors.trueBlack,
          isLargeTextOrGraphic: true,
        ),
        isTrue,
      );

      // OLED True Black vs High-Visibility Amber
      expect(
        WcagContrastRatio.isWcagAaCompliant(
          ZeroSyncColors.amber,
          ZeroSyncColors.trueBlack,
          isLargeTextOrGraphic: true,
        ),
        isTrue,
      );

      // Light theme background vs primary text
      expect(
        WcagContrastRatio.isWcagAaCompliant(
          ZeroSyncColors.lightTextPrimary,
          ZeroSyncColors.lightBackground,
        ),
        isTrue,
      );
    });
  });

  group('AccessibleQrCodeSemantics Specs', () {
    testWidgets(
        'Exposes full descriptive semantics and obscures sensitive values',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessibleQrCodeSemantics(
              label: 'Wi-Fi Network QR Code',
              payloadType: 'Wi-Fi Configuration',
              eccLevel: 'High (30%)',
              value: 'WIFI:S:ZeroSyncNet;T:WPA;P:SuperSecret;;',
              isSensitive: true,
              child: SizedBox(
                key: ValueKey('QrChildWidget'),
                width: 200,
                height: 200,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('QrChildWidget')), findsOneWidget);

      final semanticsFinder = find.byType(Semantics);
      expect(semanticsFinder, findsWidgets);

      // Verify Semantics properties
      final Semantics semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('QrChildWidget')),
              matching: find.byType(Semantics),
            )
            .first,
      );

      expect(semantics.properties.image, isTrue);
      expect(semantics.properties.readOnly, isTrue);
      expect(
        semantics.properties.label,
        contains(
            'Wi-Fi Network QR Code, Type: Wi-Fi Configuration, Error Correction: High (30%)'),
      );
      // Obscured cryptographic payload assertion
      expect(semantics.properties.value,
          equals('Obscured cryptographic credential'));
    });
  });

  group('AccessibleScannerViewportSemantics Specs', () {
    testWidgets('Announces scanner live state, aiming guidance, and item count',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessibleScannerViewportSemantics(
              isScanningActive: true,
              detectedCount: 5,
              aimingGuidance: 'Hold steady 8 inches away.',
              child: SizedBox(
                key: ValueKey('ViewportChild'),
                width: 300,
                height: 300,
              ),
            ),
          ),
        ),
      );

      final Semantics semantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('ViewportChild')),
              matching: find.byType(Semantics),
            )
            .first,
      );

      expect(semantics.properties.liveRegion, isTrue);
      expect(semantics.properties.label, contains('Camera scanner active'));
      expect(
          semantics.properties.label, contains('Hold steady 8 inches away.'));
      expect(semantics.properties.label, contains('(Items captured: 5)'));
    });
  });

  group('AccessibleOpticalStreamSemantics Specs', () {
    testWidgets('Announces transfer percentage progress and completion state',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessibleOpticalStreamSemantics(
              currentFrame: 45,
              totalFrames: 100,
              progressRatio: 0.45,
              fps: 12,
              child: SizedBox(
                key: ValueKey('StreamChild'),
                width: 300,
                height: 300,
              ),
            ),
          ),
        ),
      );

      final Semantics inProgressSemantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('StreamChild')),
              matching: find.byType(Semantics),
            )
            .first,
      );

      expect(inProgressSemantics.properties.liveRegion, isTrue);
      expect(inProgressSemantics.properties.label, contains('45% complete'));
      expect(inProgressSemantics.properties.label,
          contains('Frame 45 of 100 at 12 FPS'));
      expect(inProgressSemantics.properties.value, equals('45%'));

      // Test completion state
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessibleOpticalStreamSemantics(
              currentFrame: 100,
              totalFrames: 100,
              progressRatio: 1.0,
              fps: 12,
              isComplete: true,
              child: SizedBox(
                key: ValueKey('StreamChildCompleted'),
                width: 300,
                height: 300,
              ),
            ),
          ),
        ),
      );

      final Semantics completedSemantics = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('StreamChildCompleted')),
              matching: find.byType(Semantics),
            )
            .first,
      );

      expect(completedSemantics.properties.label,
          contains('Optical transfer complete'));
    });
  });
}
