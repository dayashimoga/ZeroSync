import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/payload_compression_service.dart';

/// Test implementation of [BrotliCodec] for isolating Brotli support.
class MockBrotliCodec implements BrotliCodec {
  @override
  Uint8List compress(Uint8List data, {int quality = 6}) {
    // Prefix with magic marker [0xDE, 0xAD] followed by reversed data for deterministic testing
    final result = Uint8List(2 + data.length);
    result[0] = 0xDE;
    result[1] = 0xAD;
    for (var i = 0; i < data.length; i++) {
      result[2 + i] = data[data.length - 1 - i];
    }
    return result;
  }

  @override
  Uint8List decompress(Uint8List data) {
    if (data.length < 2 || data[0] != 0xDE || data[1] != 0xAD) {
      throw const FormatException('Corrupted Brotli test frame');
    }
    final raw = Uint8List(data.length - 2);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = data[data.length - 1 - i];
    }
    return raw;
  }
}

void main() {
  group('CompressionAlgorithm & Wire Envelope', () {
    test('Resolves algorithm codes and throws on unknown code', () {
      expect(CompressionAlgorithm.fromCode(0x00), CompressionAlgorithm.none);
      expect(CompressionAlgorithm.fromCode(0x01), CompressionAlgorithm.zlib);
      expect(CompressionAlgorithm.fromCode(0x02), CompressionAlgorithm.gzip);
      expect(CompressionAlgorithm.fromCode(0x03), CompressionAlgorithm.brotli);

      expect(
        () => CompressionAlgorithm.fromCode(0xFF),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Computes ratio and savings percentage correctly', () {
      final payload = CompressedPayload(
        algorithm: CompressionAlgorithm.zlib,
        data: Uint8List.fromList([1, 2, 3, 4]),
        originalSize: 10,
        compressedSize: 4,
      );

      expect(payload.compressionRatio, 0.4);
      expect(payload.spaceSavingsPercentage, 60.0);
      expect(payload.isCompressed, isTrue);

      final expanded = CompressedPayload(
        algorithm: CompressionAlgorithm.zlib,
        data: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        originalSize: 5,
        compressedSize: 6,
      );
      expect(expanded.isCompressed, isFalse);
      expect(expanded.compressionRatio, 1.2);
    });

    test('Handles zero original size without division by zero', () {
      final payload = CompressedPayload(
        algorithm: CompressionAlgorithm.none,
        data: Uint8List(0),
        originalSize: 0,
        compressedSize: 0,
      );

      expect(payload.compressionRatio, 1.0);
      expect(payload.spaceSavingsPercentage, 0.0);
      expect(payload.isCompressed, isFalse);
    });

    test('Encapsulates and deserializes wire envelopes accurately', () {
      final raw = Uint8List.fromList([10, 20, 30, 40]);
      final compressed = CompressedPayload(
        algorithm: CompressionAlgorithm.gzip,
        data: raw,
        originalSize: 100,
        compressedSize: raw.length,
      );

      final envelope = compressed.toWireEnvelope();
      expect(envelope.length, 1 + raw.length);
      expect(envelope[0], CompressionAlgorithm.gzip.code);
      expect(envelope.sublist(1), raw);

      final restored = CompressedPayload.fromWireEnvelope(
        envelope,
        originalSize: 100,
      );
      expect(restored.algorithm, CompressionAlgorithm.gzip);
      expect(restored.data, raw);
      expect(restored.originalSize, 100);
      expect(restored.compressedSize, raw.length);
    });

    test('Throws FormatException on empty wire envelope', () {
      expect(
        () => CompressedPayload.fromWireEnvelope(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('In-Memory Compression & Decompression', () {
    late PayloadCompressionService service;

    setUp(() {
      service = const PayloadCompressionService();
    });

    test('Pass-through on empty payload or algorithm none', () {
      final empty = Uint8List(0);
      final res = service.compress(empty);
      expect(res.algorithm, CompressionAlgorithm.none);
      expect(res.data, empty);
      expect(service.decompress(res), empty);

      final uncompressed = Uint8List.fromList([1, 2, 3]);
      final noneRes = service.compress(
        uncompressed,
        algorithm: CompressionAlgorithm.none,
      );
      expect(noneRes.algorithm, CompressionAlgorithm.none);
      expect(noneRes.data, uncompressed);
      expect(service.decompress(noneRes), uncompressed);
    });

    test('Throws ArgumentError if payload exceeds maximum session size (50MB)', () {
      // Create a dummy byte array referencing size over 50MB
      final overLimit = Uint8List(PayloadCompressionService.maxPayloadBytes + 1);
      expect(
        () => service.compress(overLimit),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ZLib compression and decompression round-trip preserves byte fidelity', () {
      final rawString = 'ZeroSync: Air-Gapped Optical Data Transfer ' * 50;
      final rawBytes = Uint8List.fromList(rawString.codeUnits);

      final compressed = service.compress(
        rawBytes,
        algorithm: CompressionAlgorithm.zlib,
      );

      expect(compressed.algorithm, CompressionAlgorithm.zlib);
      expect(compressed.compressedSize, lessThan(rawBytes.length));
      expect(compressed.isCompressed, isTrue);

      final restored = service.decompress(compressed);
      expect(restored, equals(rawBytes));

      final restoredDirect = service.decompressBytes(
        compressed.data,
        CompressionAlgorithm.zlib,
      );
      expect(restoredDirect, equals(rawBytes));
    });

    test('GZip compression and decompression round-trip preserves byte fidelity', () {
      final rawString = 'Air-Gapped QR Transfer System - GZip Test Vector ' * 40;
      final rawBytes = Uint8List.fromList(rawString.codeUnits);

      final compressed = service.compress(
        rawBytes,
        algorithm: CompressionAlgorithm.gzip,
      );

      expect(compressed.algorithm, CompressionAlgorithm.gzip);
      expect(compressed.compressedSize, lessThan(rawBytes.length));
      expect(compressed.isCompressed, isTrue);

      final restored = service.decompress(compressed);
      expect(restored, equals(rawBytes));
    });

    test('Decompresses wire envelope in a single step', () {
      final rawBytes = Uint8List.fromList('Optical Wire Envelope Test'.codeUnits);
      final compressed = service.compress(
        rawBytes,
        algorithm: CompressionAlgorithm.zlib,
      );
      final envelope = compressed.toWireEnvelope();

      final restored = service.decompressEnvelope(envelope);
      expect(restored, equals(rawBytes));
    });

    test('Throws UnsupportedError if Brotli is requested without a configured codec', () {
      final rawBytes = Uint8List.fromList('Test Payload'.codeUnits);
      expect(
        () => service.compress(rawBytes, algorithm: CompressionAlgorithm.brotli),
        throwsA(isA<UnsupportedError>()),
      );

      expect(
        () => service.decompressBytes(rawBytes, CompressionAlgorithm.brotli),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('Brotli round-trip succeeds when BrotliCodec is supplied', () {
      final serviceWithBrotli = PayloadCompressionService(
        brotliCodec: MockBrotliCodec(),
      );
      final rawBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);

      final compressed = serviceWithBrotli.compress(
        rawBytes,
        algorithm: CompressionAlgorithm.brotli,
      );

      expect(compressed.algorithm, CompressionAlgorithm.brotli);
      expect(compressed.data.sublist(0, 2), [0xDE, 0xAD]);

      final restored = serviceWithBrotli.decompress(compressed);
      expect(restored, equals(rawBytes));
    });
  });

  group('Automated Compression Ratio Evaluation (compressAuto)', () {
    late PayloadCompressionService service;

    setUp(() {
      service = PayloadCompressionService(brotliCodec: MockBrotliCodec());
    });

    test('Small payload (< 32 bytes) auto-falls back to uncompressed', () {
      final tinyPayload = Uint8List.fromList('Short string'.codeUnits);
      expect(tinyPayload.length, lessThan(32));

      final result = service.compressAuto(tinyPayload);
      expect(result.algorithm, CompressionAlgorithm.none);
      expect(result.data, equals(tinyPayload));
    });

    test('Incompressible random data auto-falls back to uncompressed', () {
      final rng = Random(42);
      final randomBytes = Uint8List(256);
      for (var i = 0; i < randomBytes.length; i++) {
        randomBytes[i] = rng.nextInt(256);
      }

      final result = service.compressAuto(randomBytes, minSavingsRatio: 0.10);
      expect(result.algorithm, CompressionAlgorithm.none);
      expect(result.data, equals(randomBytes));
    });

    test('Highly compressible text selects optimal algorithm with significant savings', () {
      final repeatedText = 'CONFIDENTIAL_KEY_STORE_AIR_GAP_TRANSMISSION_' * 30;
      final rawBytes = Uint8List.fromList(repeatedText.codeUnits);

      final result = service.compressAuto(rawBytes);
      expect(result.algorithm, isNot(CompressionAlgorithm.none));
      expect(result.isCompressed, isTrue);
      expect(result.spaceSavingsPercentage, greaterThan(50.0));

      final restored = service.decompress(result);
      expect(restored, equals(rawBytes));
    });

    test('Auto-compression skips candidates when custom list is specified', () {
      final repeatedText = 'SELECT_CANDIDATE_ALGORITHM_SPECIFICATION_' * 25;
      final rawBytes = Uint8List.fromList(repeatedText.codeUnits);

      final result = service.compressAuto(
        rawBytes,
        candidateAlgorithms: [CompressionAlgorithm.gzip],
      );

      expect(result.algorithm, CompressionAlgorithm.gzip);
      final restored = service.decompress(result);
      expect(restored, equals(rawBytes));
    });

    test('Throws ArgumentError if auto-compress payload exceeds 50MB ceiling', () {
      final overLimit = Uint8List(PayloadCompressionService.maxPayloadBytes + 1);
      expect(
        () => service.compressAuto(overLimit),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Frame Boundary Slicing & Validation (<= 450 bytes)', () {
    late PayloadCompressionService service;

    setUp(() {
      service = const PayloadCompressionService();
    });

    test('Throws ArgumentError on empty payload slicing', () {
      expect(
        () => service.slicePayloadIntoFrames(Uint8List(0)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError when frame limit <= 0 or > 450 bytes', () {
      final data = Uint8List(100);
      expect(
        () => service.slicePayloadIntoFrames(data, frameLimitBytes: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => service.slicePayloadIntoFrames(data, frameLimitBytes: 451),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Slices exact multiple of 450 bytes into uniform frames', () {
      final payload = Uint8List(900);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = i % 256;
      }

      final frames = service.slicePayloadIntoFrames(payload);
      expect(frames.length, 2);
      expect(frames[0].length, 450);
      expect(frames[1].length, 450);

      // Reassembly test
      final reassembled = Uint8List(900);
      reassembled.setRange(0, 450, frames[0]);
      reassembled.setRange(450, 900, frames[1]);
      expect(reassembled, equals(payload));
    });

    test('Slices non-multiple payload with trailing frame correctly', () {
      final payload = Uint8List(1000);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = (i * 7) % 256;
      }

      final frames = service.slicePayloadIntoFrames(payload);
      expect(frames.length, 3);
      expect(frames[0].length, 450);
      expect(frames[1].length, 450);
      expect(frames[2].length, 100);

      for (final frame in frames) {
        expect(frame.length, lessThanOrEqualTo(450));
      }

      final totalBytes = frames.fold<int>(0, (sum, f) => sum + f.length);
      expect(totalBytes, 1000);
    });

    test('Validates frame boundary throws on > 450 bytes and succeeds on <= 450', () {
      expect(
        () => service.validateFrameBoundary(Uint8List(451)),
        throwsA(isA<ArgumentError>()),
      );

      expect(() => service.validateFrameBoundary(Uint8List(450)), returnsNormally);
      expect(() => service.validateFrameBoundary(Uint8List(100)), returnsNormally);
    });
  });
}
