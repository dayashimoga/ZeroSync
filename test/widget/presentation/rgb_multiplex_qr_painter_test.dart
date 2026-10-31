import 'dart:ui';
import 'package:airdrop_qr/domain/services/rgb_channel_splitter.dart';
import 'package:airdrop_qr/presentation/widgets/rgb_multiplex_qr_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RgbMultiplexQrWidget Specs', () {
    testWidgets('Renders widget tree with fixed size', (tester) async {
      final matrix = RgbMultiplexedColorMatrix(width: 8, height: 8);
      matrix.setColorCode(0, 0, 7);
      matrix.setColorCode(1, 1, 4);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RgbMultiplexQrWidget(
                colorMatrix: matrix,
                size: 200,
                backgroundColor: Colors.black,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(RgbMultiplexQrWidget), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RgbMultiplexQrWidget),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );

      final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox));
      expect(sizedBox.width, equals(200));
      expect(sizedBox.height, equals(200));
    });

    testWidgets('Renders with AspectRatio 1.0 when size is omitted',
        (tester) async {
      final matrix = RgbMultiplexedColorMatrix(width: 4, height: 4);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RgbMultiplexQrWidget(
                colorMatrix: matrix,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AspectRatio), findsOneWidget);
      final aspectRatio = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspectRatio.aspectRatio, equals(1.0));
    });
  });

  group('RgbMultiplexQrPainter Paint & Repaint Specs', () {
    test('Executes paint cycle for all 8 module colors without throwing', () {
      final matrix = RgbMultiplexedColorMatrix(width: 4, height: 2);
      for (int i = 0; i < 8; i++) {
        matrix.setColorCode(i % 4, i ~/ 4, i);
      }

      final painter = RgbMultiplexQrPainter(
        colorMatrix: matrix,
        backgroundColor: Colors.black,
        modulePaddingRatio: 0.1,
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(200, 200);

      expect(() => painter.paint(canvas, size), returnsNormally);
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });

    test('shouldRepaint detects matrix and background mutations', () {
      final m1 = RgbMultiplexedColorMatrix(width: 2, height: 2);
      final m2 = RgbMultiplexedColorMatrix(width: 2, height: 2);
      m2.setColorCode(0, 0, 7);

      final p1 = RgbMultiplexQrPainter(colorMatrix: m1);
      final p1Identical = RgbMultiplexQrPainter(colorMatrix: m1);
      final p2 = RgbMultiplexQrPainter(colorMatrix: m2);
      final pBgChanged = RgbMultiplexQrPainter(
        colorMatrix: m1,
        backgroundColor: Colors.white,
      );

      expect(p1.shouldRepaint(p1Identical), isFalse);
      expect(p1.shouldRepaint(p2), isTrue);
      expect(p1.shouldRepaint(pBgChanged), isTrue);
    });
  });
}
