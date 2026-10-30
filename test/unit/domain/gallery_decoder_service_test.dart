import 'dart:typed_data';

import 'package:airdrop_qr/domain/services/gallery_decoder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('RawImageData Specifications & BMP Serialization', () {
    test('Initializes valid grayscale, rgb, and rgba raster bitmaps', () {
      final gray = RawImageData(
        width: 2,
        height: 2,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([10, 20, 30, 40]),
      );
      expect(gray.bytesPerPixel, equals(1));
      expect(gray.pixels.length, equals(4));

      final rgb = RawImageData(
        width: 1,
        height: 2,
        format: PixelFormat.rgb,
        pixels: Uint8List.fromList([255, 0, 0, 0, 255, 0]),
      );
      expect(rgb.bytesPerPixel, equals(3));
      expect(rgb.pixels.length, equals(6));

      final rgba = RawImageData(
        width: 1,
        height: 1,
        format: PixelFormat.rgba,
        pixels: Uint8List.fromList([100, 150, 200, 255]),
      );
      expect(rgba.bytesPerPixel, equals(4));
    });

    test('Throws assertion on invalid dimensions or buffer size mismatch', () {
      expect(
        () => RawImageData(
          width: 0,
          height: 10,
          format: PixelFormat.grayscale,
          pixels: Uint8List(0),
        ),
        throwsA(isA<AssertionError>()),
      );

      expect(
        () => RawImageData(
          width: 4,
          height: 4,
          format: PixelFormat.grayscale,
          pixels: Uint8List(10), // Should be 16
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('Encodes standard 24-bit uncompressed Windows BMP with padding', () {
      // 3x2 RGB bitmap -> (3 * 3 = 9 bytes/row, padding = 3 bytes/row)
      final rgbImage = RawImageData(
        width: 3,
        height: 2,
        format: PixelFormat.rgb,
        pixels: Uint8List.fromList([
          // Row 0
          255, 0, 0, // Red
          0, 255, 0, // Green
          0, 0, 255, // Blue
          // Row 1
          255, 255, 255, // White
          0, 0, 0, // Black
          128, 128, 128, // Gray
        ]),
      );

      final bmpBytes = rgbImage.toBmpBytes();

      // Verify BMP Signature 'BM' (0x42, 0x4D)
      expect(bmpBytes[0], equals(0x42));
      expect(bmpBytes[1], equals(0x4D));

      final byteData = ByteData.sublistView(bmpBytes);
      final fileSize = byteData.getUint32(2, Endian.little);
      final offset = byteData.getUint32(10, Endian.little);
      final headerSize = byteData.getUint32(14, Endian.little);
      final width = byteData.getInt32(18, Endian.little);
      final height = byteData.getInt32(22, Endian.little);
      final bpp = byteData.getUint16(28, Endian.little);

      expect(offset, equals(54));
      expect(headerSize, equals(40));
      expect(width, equals(3));
      expect(height, equals(-2)); // Negative indicates top-down bitmap
      expect(bpp, equals(24));
      expect(fileSize, equals(bmpBytes.length));

      // Row stride: 3 * 3 = 9 -> padded to 12. Total pixel bytes = 12 * 2 = 24.
      // Total size = 54 + 24 = 78 bytes.
      expect(fileSize, equals(78));

      // Verify BGR order in pixel array for Red pixel (R=255, G=0, B=0 -> B=0, G=0, R=255)
      expect(bmpBytes[54], equals(0)); // B
      expect(bmpBytes[55], equals(0)); // G
      expect(bmpBytes[56], equals(255)); // R
    });

    test('Encodes grayscale image to 24-bit BMP correctly', () {
      final grayImage = RawImageData(
        width: 2,
        height: 1,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([100, 200]),
      );

      final bmpBytes = grayImage.toBmpBytes();
      // Row stride: 2 * 3 = 6 -> padded to 8. Total = 54 + 8 = 62.
      expect(bmpBytes.length, equals(62));
      // First pixel BGR = (100, 100, 100)
      expect(bmpBytes[54], equals(100));
      expect(bmpBytes[55], equals(100));
      expect(bmpBytes[56], equals(100));
      // Second pixel BGR = (200, 200, 200)
      expect(bmpBytes[57], equals(200));
      expect(bmpBytes[58], equals(200));
      expect(bmpBytes[59], equals(200));
    });
  });

  group('GalleryDecoderOptions & GalleryDecodeResult Entities', () {
    test('Default options and assertions', () {
      const options = GalleryDecoderOptions();
      expect(options.passes.length, equals(5));
      expect(options.returnFirstMatch, isTrue);
      expect(options.maxDimension, equals(1600));
      expect(options.runInIsolate, isTrue);

      expect(
        () => GalleryDecoderOptions(maxDimension: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('GalleryDecodeResult formatting and properties', () {
      final resultSuccess = GalleryDecodeResult.success(
        barcodes: const [
          Barcode(rawValue: 'RESULT_1', format: BarcodeFormat.qrCode)
        ],
        successfulPass: GalleryDecodePass.inverted,
        totalPassesExecuted: 4,
        duration: const Duration(milliseconds: 45),
      );

      expect(resultSuccess.isSuccess, isTrue);
      expect(resultSuccess.barcodes.length, equals(1));
      expect(resultSuccess.successfulPass, equals(GalleryDecodePass.inverted));
      expect(resultSuccess.totalPassesExecuted, equals(4));
      expect(resultSuccess.processingDuration.inMilliseconds, equals(45));
      expect(resultSuccess.toString(), contains('pass: inverted'));

      final resultFailure = GalleryDecodeResult.failure(
        totalPassesExecuted: 5,
        duration: const Duration(milliseconds: 120),
        message: 'No code detected',
      );

      expect(resultFailure.isSuccess, isFalse);
      expect(resultFailure.barcodes, isEmpty);
      expect(resultFailure.successfulPass, isNull);
      expect(resultFailure.errorMessage, equals('No code detected'));
      expect(resultFailure.toString(), contains('isSuccess: false'));
    });
  });

  group('Automated Image Preprocessing Transformations', () {
    test('toGrayscale performs ITU-R BT.601 integer conversion', () {
      final rgb = RawImageData(
        width: 3,
        height: 1,
        format: PixelFormat.rgb,
        pixels: Uint8List.fromList([
          255, 255, 255, // Pure White -> 255
          0, 0, 0, // Pure Black -> 0
          255, 0, 0, // Pure Red -> (77 * 255) >> 8 = 76
        ]),
      );

      final gray = GalleryDecoderService.toGrayscale(rgb);
      expect(gray.format, equals(PixelFormat.grayscale));
      expect(gray.width, equals(3));
      expect(gray.height, equals(1));
      expect(gray.pixels[0], equals(255));
      expect(gray.pixels[1], equals(0));
      expect(gray.pixels[2], equals(76));

      // Calling toGrayscale on already grayscale image returns original without copy
      final same = GalleryDecoderService.toGrayscale(gray);
      expect(identical(same, gray), isTrue);
    });

    test('maximizeContrast stretches pixel intensities to 0..255 dynamic range',
        () {
      final gray = RawImageData(
        width: 3,
        height: 1,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([100, 125, 150]),
      );

      final stretched = GalleryDecoderService.maximizeContrast(gray);
      expect(stretched.pixels[0], equals(0)); // Min mapped to 0
      expect(stretched.pixels[1], equals(127)); // Midpoint stretched
      expect(stretched.pixels[2], equals(255)); // Max mapped to 255
    });

    test('maximizeContrast handles uniform image without dividing by zero', () {
      final uniform = RawImageData(
        width: 2,
        height: 1,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([128, 128]),
      );

      final result = GalleryDecoderService.maximizeContrast(uniform);
      expect(result.pixels, equals(uniform.pixels));
    });

    test('invertImage inverts pixel polarity (255 - pixel)', () {
      final gray = RawImageData(
        width: 4,
        height: 1,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([0, 55, 200, 255]),
      );

      final inverted = GalleryDecoderService.invertImage(gray);
      expect(inverted.pixels[0], equals(255));
      expect(inverted.pixels[1], equals(200));
      expect(inverted.pixels[2], equals(55));
      expect(inverted.pixels[3], equals(0));
    });

    test('binarizeAdaptive thresholds pixels to binary 0 and 255 based on mean',
        () {
      // Mean = (10 + 20 + 80 + 90) / 4 = 50
      final gray = RawImageData(
        width: 4,
        height: 1,
        format: PixelFormat.grayscale,
        pixels: Uint8List.fromList([10, 20, 80, 90]),
      );

      final binary = GalleryDecoderService.binarizeAdaptive(gray);
      expect(binary.pixels[0], equals(0));
      expect(binary.pixels[1], equals(0));
      expect(binary.pixels[2], equals(255));
      expect(binary.pixels[3], equals(255));
    });

    test(
        'downscaleImage downscales oversized dimensions while preserving aspect ratio',
        () {
      final largeImage = RawImageData(
        width: 2000,
        height: 1000,
        format: PixelFormat.grayscale,
        pixels: Uint8List(2000 * 1000),
      );

      final scaled = GalleryDecoderService.downscaleImage(largeImage, 1000);
      expect(scaled.width, equals(1000));
      expect(scaled.height, equals(500));
      expect(scaled.pixels.length, equals(1000 * 500));

      // Image already smaller than maxDimension returns unchanged
      final small = RawImageData(
        width: 400,
        height: 300,
        format: PixelFormat.grayscale,
        pixels: Uint8List(400 * 300),
      );
      final notScaled = GalleryDecoderService.downscaleImage(small, 800);
      expect(identical(notScaled, small), isTrue);
    });
  });

  group('GalleryDecoderService Multi-Pass Decoding Pipeline', () {
    test('Resolves barcode on first pass (raw) immediately', () async {
      final sampleImage = RawImageData(
        width: 10,
        height: 10,
        format: PixelFormat.grayscale,
        pixels: Uint8List(100),
      );

      final service = GalleryDecoderService(
        analyzer: (path) async {
          return const [
            Barcode(rawValue: 'PASS_RAW', format: BarcodeFormat.qrCode)
          ];
        },
      );

      final result = await service.decodeRawImage(
        sampleImage,
        options: const GalleryDecoderOptions(runInIsolate: false),
      );

      expect(result.isSuccess, isTrue);
      expect(result.barcodes.first.rawValue, equals('PASS_RAW'));
      expect(result.successfulPass, equals(GalleryDecodePass.raw));
      expect(result.totalPassesExecuted, equals(1));
    });

    test(
        'Iterates through passes and succeeds on inverted pass for dark-mode QR',
        () async {
      final sampleImage = RawImageData(
        width: 10,
        height: 10,
        format: PixelFormat.grayscale,
        pixels: Uint8List(100),
      );

      int callIndex = 0;
      final service = GalleryDecoderService(
        analyzer: (path) async {
          callIndex++;
          // Simulate failure on passes 1..3 and success on pass 4 (inverted)
          if (callIndex == 4) {
            return const [
              Barcode(rawValue: 'DARK_MODE_QR', format: BarcodeFormat.qrCode)
            ];
          }
          return const <Barcode>[];
        },
      );

      final result = await service.decodeRawImage(
        sampleImage,
        options: const GalleryDecoderOptions(runInIsolate: false),
      );

      expect(result.isSuccess, isTrue);
      expect(result.barcodes.first.rawValue, equals('DARK_MODE_QR'));
      expect(result.successfulPass, equals(GalleryDecodePass.inverted));
      expect(result.totalPassesExecuted, equals(4));
    });

    test('Reports failure when no passes detect barcodes', () async {
      final sampleImage = RawImageData(
        width: 10,
        height: 10,
        format: PixelFormat.grayscale,
        pixels: Uint8List(100),
      );

      final service = GalleryDecoderService(
        analyzer: (path) async => const <Barcode>[],
      );

      final result = await service.decodeRawImage(
        sampleImage,
        options: const GalleryDecoderOptions(runInIsolate: false),
      );

      expect(result.isSuccess, isFalse);
      expect(result.barcodes, isEmpty);
      expect(result.successfulPass, isNull);
      expect(result.totalPassesExecuted, equals(5));
      expect(result.errorMessage, contains('No valid barcodes detected'));
    });

    test('Fails immediately when no analyzer adapter is configured', () async {
      final sampleImage = RawImageData(
        width: 10,
        height: 10,
        format: PixelFormat.grayscale,
        pixels: Uint8List(100),
      );

      const service = GalleryDecoderService(analyzer: null);
      final result = await service.decodeRawImage(
        sampleImage,
        options: const GalleryDecoderOptions(runInIsolate: false),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage,
          contains('No static image analyzer adapter configured'));
      expect(result.totalPassesExecuted, equals(0));
    });

    test(
        'Executes preprocessing passes in background isolate when runInIsolate is true',
        () async {
      final sampleImage = RawImageData(
        width: 20,
        height: 20,
        format: PixelFormat.rgb,
        pixels: Uint8List(20 * 20 * 3),
      );

      final service = GalleryDecoderService(
        analyzer: (path) async {
          return const [
            Barcode(rawValue: 'ISOLATE_DECODED', format: BarcodeFormat.qrCode)
          ];
        },
      );

      final result = await service.decodeRawImage(
        sampleImage,
        options: const GalleryDecoderOptions(
          passes: [GalleryDecodePass.grayscale],
          runInIsolate: true,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(result.barcodes.first.rawValue, equals('ISOLATE_DECODED'));
      expect(result.successfulPass, equals(GalleryDecodePass.grayscale));
    });
  });
}
