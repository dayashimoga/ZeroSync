import 'dart:typed_data';

import 'package:airdrop_qr/domain/services/rgb_channel_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RgbBitMatrix Specification Tests', () {
    test('Constructs empty bit matrix and manipulates individual bits', () {
      final matrix = RgbBitMatrix.empty(8, 8);
      expect(matrix.width, equals(8));
      expect(matrix.height, equals(8));

      expect(matrix.get(0, 0), isFalse);
      matrix.set(0, 0, true);
      expect(matrix.get(0, 0), isTrue);

      matrix.set(7, 7, true);
      expect(matrix.get(7, 7), isTrue);
      expect(matrix.get(1, 1), isFalse);

      matrix.set(0, 0, false);
      expect(matrix.get(0, 0), isFalse);
    });

    test('RgbBitMatrix.fromBooleans constructs matching matrix', () {
      final grid = [
        [true, false, true],
        [false, true, false],
        [true, true, false],
      ];
      final matrix = RgbBitMatrix.fromBooleans(grid);
      expect(matrix.width, equals(3));
      expect(matrix.height, equals(3));

      expect(matrix.get(0, 0), isTrue);
      expect(matrix.get(1, 0), isFalse);
      expect(matrix.get(1, 1), isTrue);
      expect(matrix.get(2, 2), isFalse);
    });

    test('Throws RangeError on out of bounds access', () {
      final matrix = RgbBitMatrix.empty(4, 4);
      expect(() => matrix.get(-1, 0), throwsA(isA<RangeError>()));
      expect(() => matrix.get(4, 0), throwsA(isA<RangeError>()));
      expect(() => matrix.set(0, 4, true), throwsA(isA<RangeError>()));
    });

    test('Throws ArgumentError on empty grid in fromBooleans', () {
      expect(() => RgbBitMatrix.fromBooleans(const []),
          throwsA(isA<ArgumentError>()));
    });

    test('Equatable value equality', () {
      final m1 = RgbBitMatrix.empty(3, 3);
      final m2 = RgbBitMatrix.empty(3, 3);
      m1.set(1, 1, true);
      m2.set(1, 1, true);

      expect(m1, equals(m2));
      m2.set(1, 1, false);
      expect(m1 == m2, isFalse);
    });
  });

  group('RgbMultiplexedColorMatrix Specification Tests', () {
    test('Stores and retrieves 3-bit color codes (0..7)', () {
      final matrix = RgbMultiplexedColorMatrix(width: 4, height: 4);
      expect(matrix.getColorCode(0, 0), equals(0));

      matrix.setColorCode(0, 0, 7); // White
      matrix.setColorCode(1, 1, 6); // Yellow
      matrix.setColorCode(2, 2, 5); // Magenta
      matrix.setColorCode(3, 3, 4); // Red

      expect(matrix.getColorCode(0, 0), equals(7));
      expect(matrix.getColorCode(1, 1), equals(6));
      expect(matrix.getColorCode(2, 2), equals(5));
      expect(matrix.getColorCode(3, 3), equals(4));
    });

    test('Masks values outside 0..7 to 3 bits', () {
      final matrix = RgbMultiplexedColorMatrix(width: 2, height: 2);
      matrix.setColorCode(0, 0, 0xFF); // 255 & 7 = 7
      expect(matrix.getColorCode(0, 0), equals(7));
    });

    test('Throws RangeError on out of bounds access', () {
      final matrix = RgbMultiplexedColorMatrix(width: 2, height: 2);
      expect(() => matrix.getColorCode(2, 0), throwsA(isA<RangeError>()));
      expect(() => matrix.setColorCode(0, 2, 1), throwsA(isA<RangeError>()));
    });
  });

  group('OpticalRgbMultiplexer Multiplex & Split Specs', () {
    test('Multiplexes 3 channels and splits back with 100% bit-exact parity',
        () {
      const w = 4;
      const h = 4;

      final red = RgbBitMatrix.empty(w, h);
      final green = RgbBitMatrix.empty(w, h);
      final blue = RgbBitMatrix.empty(w, h);

      // (0,0): Red only -> code 4
      red.set(0, 0, true);

      // (1,0): Green only -> code 2
      green.set(1, 0, true);

      // (2,0): Blue only -> code 1
      blue.set(2, 0, true);

      // (3,0): Red + Green -> Yellow (code 6)
      red.set(3, 0, true);
      green.set(3, 0, true);

      // (0,1): Red + Blue -> Magenta (code 5)
      red.set(0, 1, true);
      blue.set(0, 1, true);

      // (1,1): Green + Blue -> Cyan (code 3)
      green.set(1, 1, true);
      blue.set(1, 1, true);

      // (2,1): Red + Green + Blue -> White (code 7)
      red.set(2, 1, true);
      green.set(2, 1, true);
      blue.set(2, 1, true);

      // (3,1): All false -> Black (code 0)

      final multiplexed = OpticalRgbMultiplexer.multiplex(
        red: red,
        green: green,
        blue: blue,
      );

      expect(multiplexed.getColorCode(0, 0), equals(4));
      expect(multiplexed.getColorCode(1, 0), equals(2));
      expect(multiplexed.getColorCode(2, 0), equals(1));
      expect(multiplexed.getColorCode(3, 0), equals(6));
      expect(multiplexed.getColorCode(0, 1), equals(5));
      expect(multiplexed.getColorCode(1, 1), equals(3));
      expect(multiplexed.getColorCode(2, 1), equals(7));
      expect(multiplexed.getColorCode(3, 1), equals(0));

      final split = OpticalRgbMultiplexer.splitColorMatrix(multiplexed);

      expect(split.red, equals(red));
      expect(split.green, equals(green));
      expect(split.blue, equals(blue));
    });

    test('Throws ArgumentError if channel dimensions mismatch in multiplex',
        () {
      final r = RgbBitMatrix.empty(4, 4);
      final g = RgbBitMatrix.empty(5, 4);
      final b = RgbBitMatrix.empty(4, 4);

      expect(
        () => OpticalRgbMultiplexer.multiplex(red: r, green: g, blue: b),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
        'splitPixelBuffer extracts channels from raw RGBA buffer with threshold',
        () {
      const w = 2;
      const h = 2;
      // 4 pixels * 4 bytes = 16 bytes RGBA
      final pixels = Uint8List.fromList([
        // Pixel (0,0): Red 255, Green 0, Blue 0, Alpha 255
        255, 0, 0, 255,
        // Pixel (1,0): Red 250, Green 220, Blue 30, Alpha 255 (Yellowish)
        250, 220, 30, 255,
        // Pixel (0,1): Red 10, Green 240, Blue 240, Alpha 255 (Cyanish)
        10, 240, 240, 255,
        // Pixel (1,1): Red 20, Green 30, Blue 15, Alpha 255 (Black)
        20, 30, 15, 255,
      ]);

      final split = OpticalRgbMultiplexer.splitPixelBuffer(
        pixels: pixels,
        width: w,
        height: h,
        bytesPerPixel: 4,
        threshold: 128,
      );

      // (0,0): Red=true, Green=false, Blue=false
      expect(split.red.get(0, 0), isTrue);
      expect(split.green.get(0, 0), isFalse);
      expect(split.blue.get(0, 0), isFalse);

      // (1,0): Red=true, Green=true, Blue=false
      expect(split.red.get(1, 0), isTrue);
      expect(split.green.get(1, 0), isTrue);
      expect(split.blue.get(1, 0), isFalse);

      // (0,1): Red=false, Green=true, Blue=true
      expect(split.red.get(0, 1), isFalse);
      expect(split.green.get(0, 1), isTrue);
      expect(split.blue.get(0, 1), isTrue);

      // (1,1): Red=false, Green=false, Blue=false
      expect(split.red.get(1, 1), isFalse);
      expect(split.green.get(1, 1), isFalse);
      expect(split.blue.get(1, 1), isFalse);
    });

    test('toRgbaPixels converts color matrix into valid RGBA byte buffer', () {
      final matrix = RgbMultiplexedColorMatrix(width: 2, height: 1);
      matrix.setColorCode(0, 0, 7); // White
      matrix.setColorCode(1, 0, 4); // Red

      final rgba = OpticalRgbMultiplexer.toRgbaPixels(matrix, activeAlpha: 200);

      // Pixel 0 (White): 255, 255, 255, 200
      expect(rgba[0], equals(255));
      expect(rgba[1], equals(255));
      expect(rgba[2], equals(255));
      expect(rgba[3], equals(200));

      // Pixel 1 (Red): 255, 0, 0, 200
      expect(rgba[4], equals(255));
      expect(rgba[5], equals(0));
      expect(rgba[6], equals(0));
      expect(rgba[7], equals(200));
    });
  });
}
