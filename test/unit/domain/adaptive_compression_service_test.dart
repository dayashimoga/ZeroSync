import 'dart:convert';
import 'dart:typed_data';
import 'package:airdrop_qr/domain/services/adaptive_compression_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdaptiveCompressionService Specs', () {
    late AdaptiveCompressionService compressionService;

    setUp(() {
      compressionService = AdaptiveCompressionService();
    });

    test('Compresses highly repetitive low-entropy text payload', () {
      final repetitive =
          'ZeroSync Air-Gap Optical Protocol Security Invariant ' * 50;
      final bytes = Uint8List.fromList(utf8.encode(repetitive));

      final result = compressionService.process(bytes);
      expect(result.wasCompressed, isTrue);
      expect(result.compressionRatio, lessThan(0.5));
      expect(result.shannonEntropy, lessThan(6.0));

      // Verify lossless decompression
      final decompressed = compressionService.decompress(result.outputBytes);
      expect(utf8.decode(decompressed), equals(repetitive));
    });

    test('Skips compression on high-entropy pseudorandom bytes', () {
      // 256 bytes covering full uniform byte distribution (maximum entropy ~8.0)
      final highEntropy = Uint8List.fromList(List.generate(256, (i) => i));

      final result = compressionService.process(highEntropy);
      expect(result.shannonEntropy, greaterThan(7.5));
      expect(result.wasCompressed, isFalse);
      expect(result.outputBytes.length, equals(highEntropy.length));
    });

    test('Handles empty payload gracefully', () {
      final result = compressionService.process(Uint8List(0));
      expect(result.wasCompressed, isFalse);
      expect(result.outputBytes.isEmpty, isTrue);
      expect(result.shannonEntropy, equals(0.0));
    });
  });
}
