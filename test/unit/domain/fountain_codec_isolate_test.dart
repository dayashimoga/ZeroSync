import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/fountain_codec_isolate.dart';
import 'package:airdrop_qr/domain/value_objects/transport_header.dart';

void main() {
  group('FountainCodecIsolate Zero-Copy Background Worker Specs', () {
    late FountainCodecIsolate codecIsolate;

    setUp(() {
      codecIsolate = FountainCodecIsolate();
    });

    tearDown(() async {
      await codecIsolate.dispose();
    });

    test('Spawns background worker isolate and reports running state',
        () async {
      expect(codecIsolate.isRunning, isFalse);
      await codecIsolate.start();
      expect(codecIsolate.isRunning, isTrue);
    });

    test(
        'Encodes payload and decodes batch on persistent worker isolate with 100% fidelity',
        () async {
      final originalData = Uint8List.fromList(
        List.generate(500, (i) => (i * 13 + 37) & 0xFF),
      );

      // Background encoding via TransferableTypedData
      final frames = await codecIsolate.encode(
        payload: originalData,
        symbolSize: 60, // K = 9 blocks
        redundancyFactor: 1.6,
        isEncrypted: true,
        rgbMode: RgbColorMode.blue,
      );

      expect(frames.length, greaterThanOrEqualTo(9));
      expect(frames.first.header.k, equals(9));
      expect(frames.first.header.isEncrypted, isTrue);
      expect(frames.first.header.rgbMode, equals(RgbColorMode.blue));

      // Background decoding via TransferableTypedData
      final decoded = await codecIsolate.decodeBatch(frames);
      expect(decoded, equals(originalData));
    });

    test('Streams frames one-by-one with ingestFrame and reports telemetry',
        () async {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final frames = await codecIsolate.encode(
        payload: payload,
        symbolSize: 4, // K = 2 blocks
        redundancyFactor: 2.0,
      );

      await codecIsolate.resetDecoder();
      FountainCodecTelemetry? lastTelemetry;

      for (final frame in frames) {
        lastTelemetry = await codecIsolate.ingestFrame(frame);
        if (lastTelemetry.isDecoded) break;
      }

      expect(lastTelemetry, isNotNull);
      expect(lastTelemetry!.isDecoded, isTrue);
      expect(lastTelemetry.solvedBlocks, equals(2));
      expect(lastTelemetry.progress, equals(1.0));
    });

    test(
        'encodeFast and decodeFast execute cleanly on ephemeral background isolates',
        () async {
      final payload = Uint8List.fromList(
          'ZeroSync Optical Isolate Acceleration Test'.codeUnits);

      final frames = await FountainCodecIsolate.encodeFast(
        payload: payload,
        symbolSize: 15,
        redundancyFactor: 1.8,
      );

      expect(frames, isNotEmpty);
      for (final frame in frames) {
        expect(frame.isValidChecksum, isTrue);
      }

      final restored = await FountainCodecIsolate.decodeFast(frames);
      expect(restored, equals(payload));
    });

    test('Throws ArgumentError on empty frames in decodeBatch', () async {
      expect(
        () => codecIsolate.decodeBatch([]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError on empty frames in decodeFast', () async {
      expect(
        () => FountainCodecIsolate.decodeFast([]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Resets decoder session on persistent isolate', () async {
      await codecIsolate.start();
      await codecIsolate.resetDecoder();
      expect(codecIsolate.isRunning, isTrue);
    });

    test('Dispose gracefully terminates background worker isolate', () async {
      await codecIsolate.start();
      expect(codecIsolate.isRunning, isTrue);
      await codecIsolate.dispose();
      expect(codecIsolate.isRunning, isFalse);
    });
  });
}
