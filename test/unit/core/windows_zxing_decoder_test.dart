import 'dart:typed_data';

import 'package:airdrop_qr/data/datasources/optical_scanner_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('OpticalImageFrame Specification Tests', () {
    test('Constructs OpticalImageFrame with explicit and default attributes',
        () {
      final bytes = Uint8List.fromList([0x00, 0xFF, 0x80, 0x7F]);
      final timestamp = DateTime(2026, 10, 31, 12, 0, 0);

      final frame = OpticalImageFrame(
        bytes: bytes,
        width: 640,
        height: 480,
        bytesPerRow: 640 * 4,
        format: OpticalImagePixelFormat.bgra8888,
        timestamp: timestamp,
      );

      expect(frame.bytes, equals(bytes));
      expect(frame.width, equals(640));
      expect(frame.height, equals(480));
      expect(frame.bytesPerRow, equals(2560));
      expect(frame.format, equals(OpticalImagePixelFormat.bgra8888));
      expect(frame.timestamp, equals(timestamp));
    });

    test('OpticalImageFrame.now assigns current timestamp', () {
      final bytes = Uint8List(16);
      final frame = OpticalImageFrame.now(
        bytes: bytes,
        width: 4,
        height: 4,
        bytesPerRow: 16,
        format: OpticalImagePixelFormat.luminance8,
      );

      expect(frame.format, equals(OpticalImagePixelFormat.luminance8));
      expect(
          frame.timestamp
              .isBefore(DateTime.now().add(const Duration(seconds: 1))),
          isTrue);
    });
  });

  group('WindowsZxingDecoderImpl Specs', () {
    test('Decodes optical frame using injected custom handler', () async {
      final testFrame = OpticalImageFrame.now(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        width: 100,
        height: 100,
        bytesPerRow: 400,
      );

      final decoder = WindowsZxingDecoderImpl(
        customHandler: (frame) => OpticalScanResult(
          rawValue: 'ZEROSYNC-WIN-TEST-PAYLOAD',
          rawBytes: Uint8List.fromList([0xAA, 0xBB]),
          format: BarcodeFormat.qrCode,
          timestamp: frame.timestamp,
          engineUsed: OpticalDetectionEngine.windowsZxing,
          cornerPoints: const [Offset(0, 0), Offset(100, 100)],
          instantaneousFps: 60.0,
          frameSequence: 1,
          processingLatency: const Duration(milliseconds: 5),
        ),
      );

      final result = await decoder.decodeFrame(testFrame);
      expect(result, isNotNull);
      expect(result!.rawValue, equals('ZEROSYNC-WIN-TEST-PAYLOAD'));
      expect(result.rawBytes, equals(Uint8List.fromList([0xAA, 0xBB])));
      expect(result.engineUsed, equals(OpticalDetectionEngine.windowsZxing));
    });

    test('Returns null gracefully when frame is empty or invalid', () async {
      final decoder = WindowsZxingDecoderImpl();

      final emptyFrame = OpticalImageFrame.now(
        bytes: Uint8List(0),
        width: 0,
        height: 0,
        bytesPerRow: 0,
      );

      final result = await decoder.decodeFrame(emptyFrame);
      expect(result, isNull);
    });

    test('Handles missing native library without throwing exception', () {
      final decoder = WindowsZxingDecoderImpl();
      expect(() => decoder.isNativeAvailable, returnsNormally);
    });
  });
}
