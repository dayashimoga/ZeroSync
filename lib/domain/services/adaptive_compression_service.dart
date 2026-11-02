import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Outcome of adaptive entropy-based compression decision.
class AdaptiveCompressionResult {
  final Uint8List outputBytes;
  final double shannonEntropy;
  final bool wasCompressed;
  final double compressionRatio;

  const AdaptiveCompressionResult({
    required this.outputBytes,
    required this.shannonEntropy,
    required this.wasCompressed,
    required this.compressionRatio,
  });
}

/// Analyzes byte entropy and adaptively compresses payload if beneficial.
class AdaptiveCompressionService {
  /// Shannon entropy threshold (bits per byte) above which data is considered
  /// already incompressible (random, compressed, or encrypted).
  static const double defaultEntropyThreshold = 7.5;

  /// Calculates the Shannon entropy H(X) in bits per byte (0.0 to 8.0).
  static double calculateEntropy(Uint8List bytes) {
    if (bytes.isEmpty) return 0.0;

    final frequencies = List<int>.filled(256, 0);
    for (var i = 0; i < bytes.length; i++) {
      frequencies[bytes[i]]++;
    }

    final len = bytes.length.toDouble();
    var entropy = 0.0;
    for (var i = 0; i < 256; i++) {
      final count = frequencies[i];
      if (count > 0) {
        final p = count / len;
        entropy -= p * (log(p) / ln2);
      }
    }
    return entropy;
  }

  /// Evaluates payload bytes and compresses if entropy is below threshold.
  AdaptiveCompressionResult process(
    Uint8List inputBytes, {
    double entropyThreshold = defaultEntropyThreshold,
  }) {
    if (inputBytes.isEmpty) {
      return AdaptiveCompressionResult(
        outputBytes: inputBytes,
        shannonEntropy: 0.0,
        wasCompressed: false,
        compressionRatio: 1.0,
      );
    }

    final entropy = calculateEntropy(inputBytes);

    // If entropy is high, compression would increase size or waste CPU
    if (entropy > entropyThreshold) {
      return AdaptiveCompressionResult(
        outputBytes: inputBytes,
        shannonEntropy: entropy,
        wasCompressed: false,
        compressionRatio: 1.0,
      );
    }

    // Low or medium entropy: compress using ZLib
    try {
      final compressed =
          Uint8List.fromList(const ZLibEncoder().encode(inputBytes));
      // Only keep compressed if it actually saved space
      if (compressed.length < inputBytes.length) {
        final ratio = compressed.length / inputBytes.length;
        return AdaptiveCompressionResult(
          outputBytes: compressed,
          shannonEntropy: entropy,
          wasCompressed: true,
          compressionRatio: ratio,
        );
      }
    } catch (_) {
      // Fallback to uncompressed on any compression error
    }

    return AdaptiveCompressionResult(
      outputBytes: inputBytes,
      shannonEntropy: entropy,
      wasCompressed: false,
      compressionRatio: 1.0,
    );
  }

  /// Decompresses payload if it was compressed.
  Uint8List decompress(Uint8List compressedBytes) {
    try {
      return Uint8List.fromList(
          const ZLibDecoder().decodeBytes(compressedBytes));
    } catch (_) {
      // If not compressed, return as is
      return compressedBytes;
    }
  }
}
