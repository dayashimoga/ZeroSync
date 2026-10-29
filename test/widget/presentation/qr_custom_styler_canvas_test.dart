import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/presentation/widgets/qr_custom_styler_canvas.dart';

void main() {
  late QrMatrix testMatrix;

  setUp(() {
    final service = QrMatrixGeneratorService();
    testMatrix = service.generateMatrix(
      payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]),
      eccLevel: QrErrorCorrectionLevel.medium,
    );
  });

  group('QrCustomStylerCanvas Widget Tests', () {
    testWidgets('Renders widget tree with fixed size',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QrCustomStylerCanvas(
                matrix: testMatrix,
                size: 250,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(QrCustomStylerCanvas), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(QrCustomStylerCanvas),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      final sizedBox = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(QrCustomStylerCanvas),
          matching: find.byType(SizedBox),
        ),
      );
      expect(sizedBox.width, equals(250));
      expect(sizedBox.height, equals(250));
    });

    testWidgets('Renders with AspectRatio 1.0 when size is null',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: QrCustomStylerCanvas(
                matrix: testMatrix,
              ),
            ),
          ),
        ),
      );

      final aspectRatio = tester.widget<AspectRatio>(
        find.descendant(
          of: find.byType(QrCustomStylerCanvas),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(aspectRatio.aspectRatio, equals(1.0));
    });
  });

  group('QrCustomStylerPainter Shapes & Geometries', () {
    testWidgets('Executes paint cycle for all module shapes without throwing',
        (WidgetTester tester) async {
      for (final shape in QrModuleShape.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrCustomStylerCanvas(
                matrix: testMatrix,
                size: 200,
                config: QrStylerConfig(
                  moduleShape: shape,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'Executes paint cycle for all outer eye shapes without throwing',
        (WidgetTester tester) async {
      for (final eyeShape in QrEyeFrameShape.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrCustomStylerCanvas(
                matrix: testMatrix,
                size: 200,
                config: QrStylerConfig(
                  eyeFrameShape: eyeShape,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        'Executes paint cycle for all inner eye pupils without throwing',
        (WidgetTester tester) async {
      for (final pupilShape in QrEyePupilShape.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrCustomStylerCanvas(
                matrix: testMatrix,
                size: 200,
                config: QrStylerConfig(
                  eyePupilShape: pupilShape,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('Gradients, Colors & Theme Presets', () {
    testWidgets('Renders with linear gradients on data and eyes',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrCustomStylerCanvas(
              matrix: testMatrix,
              size: 250,
              config: const QrStylerConfig(
                dataGradient: LinearGradient(
                  colors: [Colors.blue, Colors.purple],
                ),
                eyeFrameColor: Colors.deepPurple,
                eyePupilColor: Colors.amber,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders dark theme and neon fluid presets without throwing',
        (WidgetTester tester) async {
      // Dark theme preset
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrCustomStylerCanvas(
              matrix: testMatrix,
              size: 220,
              config: QrStylerConfig.darkTheme,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      // Neon fluid preset
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrCustomStylerCanvas(
              matrix: testMatrix,
              size: 220,
              config: QrStylerConfig.neonFluid,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Quiet Zone & Margins Verification', () {
    testWidgets('Respects custom quiet zone settings',
        (WidgetTester tester) async {
      for (int q in [0, 2, 4, 6]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QrCustomStylerCanvas(
                matrix: testMatrix,
                size: 200,
                config: QrStylerConfig(quietZoneModules: q),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });

    test('Throws AssertionError when quietZoneModules is negative', () {
      expect(
        () => QrStylerConfig(quietZoneModules: -1),
        throwsAssertionError,
      );
    });
  });

  group('Repaint Lifecycle Contract', () {
    test('shouldRepaint detects matrix and config mutations', () {
      const configA = QrStylerConfig(moduleShape: QrModuleShape.square);
      const configB = QrStylerConfig(moduleShape: QrModuleShape.circle);

      final painterA =
          QrCustomStylerPainter(matrix: testMatrix, config: configA);
      final painterSame =
          QrCustomStylerPainter(matrix: testMatrix, config: configA);
      final painterDiffConfig =
          QrCustomStylerPainter(matrix: testMatrix, config: configB);

      expect(painterA.shouldRepaint(painterSame), isFalse);
      expect(painterA.shouldRepaint(painterDiffConfig), isTrue);
    });
  });
}
