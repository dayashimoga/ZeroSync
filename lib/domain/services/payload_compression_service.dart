import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart'
    show GZipDecoder, GZipEncoder, ZLibDecoder, ZLibEncoder;
import 'package:equatable/equatable.dart';

/// Compression algorithms supported by the ZeroSync protocol.
enum CompressionAlgorithm {
  none(0x00, 'none'),
  zlib(0x01, 'zlib'),
  gzip(0x02, 'gzip'),
  brotli(0x03, 'brotli');

  final int code;
  final String identifier;
  const CompressionAlgorithm(this.code, this.identifier);

  /// Resolves an algorithm from its single-byte wire code.
  static CompressionAlgorithm fromCode(int code) {
    switch (code) {
      case 0x00:
        return CompressionAlgorithm.none;
      case 0x01:
        return CompressionAlgorithm.zlib;
      case 0x02:
        return CompressionAlgorithm.gzip;
      case 0x03:
        return CompressionAlgorithm.brotli;
      default:
        throw ArgumentError(
          'Unknown compression algorithm code: 0x${code.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }
}

/// Abstract codec interface for pluggable Brotli compression engines.
abstract class BrotliCodec {
  Uint8List compress(Uint8List data, {int quality = 6});
  Uint8List decompress(Uint8List data);
}

/// Encapsulates the result of a compression operation.
class CompressedPayload extends Equatable {
  final CompressionAlgorithm algorithm;
  final Uint8List data;
  final int originalSize;
  final int compressedSize;

  const CompressedPayload({
    required this.algorithm,
    required this.data,
    required this.originalSize,
    required this.compressedSize,
  });

  /// Compression ratio: compressed / original.
  /// Values < 1.0 denote positive compression savings.
  double get compressionRatio =>
      originalSize == 0 ? 1.0 : compressedSize / originalSize;

  /// Percentage of space saved: ((original - compressed) / original) * 100.
  /// Values > 0 denote space reduction.
  double get spaceSavingsPercentage => originalSize == 0
      ? 0.0
      : ((originalSize - compressedSize) / originalSize) * 100.0;

  /// Whether compression yielded a strictly smaller payload than the original.
  bool get isCompressed =>
      algorithm != CompressionAlgorithm.none && compressedSize < originalSize;

  /// Serializes into an encapsulated envelope byte array:
  /// [0] : 1 byte algorithm code
  /// [1..N] : compressed or raw bytes
  Uint8List toWireEnvelope() {
    final envelope = Uint8List(1 + data.length);
    envelope[0] = algorithm.code;
    envelope.setRange(1, envelope.length, data);
    return envelope;
  }

  /// Deserializes a wire envelope into a [CompressedPayload].
  factory CompressedPayload.fromWireEnvelope(
    Uint8List envelope, {
    int? originalSize,
  }) {
    if (envelope.isEmpty) {
      throw const FormatException('Compressed envelope cannot be empty');
    }
    final algorithm = CompressionAlgorithm.fromCode(envelope[0]);
    final payloadBytes = Uint8List.sublistView(envelope, 1);
    return CompressedPayload(
      algorithm: algorithm,
      data: payloadBytes,
      originalSize: originalSize ?? payloadBytes.length,
      compressedSize: payloadBytes.length,
    );
  }

  @override
  List<Object?> get props => [algorithm, data, originalSize, compressedSize];
}

/// In-memory binary compression service for air-gapped optical transfer streams.
///
/// Features:
/// - ZLib (RFC 1950), GZip (RFC 1952), and Brotli (RFC 7932) multi-algorithm support.
/// - Automated compression ratio evaluation with auto-fallback to raw pass-through
///   when payloads expand or savings fail to exceed the efficiency threshold.
/// - Single-frame optical boundary enforcement (<= 450 bytes per module grid).
class PayloadCompressionService {
  /// Maximum payload capacity per individual QR frame to maintain optical focus fidelity (450 bytes).
  static const int maxSingleFramePayloadBytes = 450;

  /// Maximum permissible payload for an optical session (50 MB).
  static const int maxPayloadBytes = 50 * 1024 * 1024;

  /// Payloads smaller than this threshold typically expand due to compression headers.
  static const int minCompressionThresholdBytes = 32;

  final BrotliCodec? _brotliCodec;

  const PayloadCompressionService({BrotliCodec? brotliCodec})
      : _brotliCodec = brotliCodec;

  /// Compresses [payload] using the specified [algorithm].
  CompressedPayload compress(
    Uint8List payload, {
    CompressionAlgorithm algorithm = CompressionAlgorithm.zlib,
  }) {
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError(
        'Payload exceeds maximum allowed transfer size ($maxPayloadBytes bytes)',
      );
    }

    if (payload.isEmpty || algorithm == CompressionAlgorithm.none) {
      return CompressedPayload(
        algorithm: CompressionAlgorithm.none,
        data: payload,
        originalSize: payload.length,
        compressedSize: payload.length,
      );
    }

    final Uint8List compressedBytes;
    switch (algorithm) {
      case CompressionAlgorithm.zlib:
        final encoded = const ZLibEncoder().encode(payload);
        compressedBytes = Uint8List.fromList(encoded);
        break;
      case CompressionAlgorithm.gzip:
        final encoded = GZipEncoder().encode(payload);
        if (encoded == null) {
          throw StateError('GZip compression failed to produce output');
        }
        compressedBytes = Uint8List.fromList(encoded);
        break;
      case CompressionAlgorithm.brotli:
        final codec = _brotliCodec;
        if (codec == null) {
          throw UnsupportedError(
            'BrotliCodec is not configured on PayloadCompressionService',
          );
        }
        compressedBytes = codec.compress(payload);
        break;
      case CompressionAlgorithm.none:
        compressedBytes = payload;
        break;
    }

    return CompressedPayload(
      algorithm: algorithm,
      data: compressedBytes,
      originalSize: payload.length,
      compressedSize: compressedBytes.length,
    );
  }

  /// Automatically evaluates compression ratios across multiple candidate algorithms
  /// and selects the most compact representation.
  ///
  /// If no candidate achieves at least [minSavingsRatio] savings (or if payloads expand),
  /// the service automatically passes through the raw payload under [CompressionAlgorithm.none].
  CompressedPayload compressAuto(
    Uint8List payload, {
    List<CompressionAlgorithm>? candidateAlgorithms,
    double minSavingsRatio = 0.05,
  }) {
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError(
        'Payload exceeds maximum allowed transfer size ($maxPayloadBytes bytes)',
      );
    }

    // Small payloads (< 32 bytes) almost always expand under compression headers.
    if (payload.length < minCompressionThresholdBytes) {
      return CompressedPayload(
        algorithm: CompressionAlgorithm.none,
        data: payload,
        originalSize: payload.length,
        compressedSize: payload.length,
      );
    }

    final candidates = candidateAlgorithms ??
        [
          CompressionAlgorithm.zlib,
          CompressionAlgorithm.gzip,
          if (_brotliCodec != null) CompressionAlgorithm.brotli,
        ];

    CompressedPayload? bestResult;

    for (final algo in candidates) {
      if (algo == CompressionAlgorithm.none) continue;
      try {
        final result = compress(payload, algorithm: algo);
        if (bestResult == null ||
            result.compressedSize < bestResult.compressedSize) {
          bestResult = result;
        }
      } catch (_) {
        // Skip algorithms that fail or are unsupported
        continue;
      }
    }

    // Evaluate savings ratio: 1.0 - (compressed / original)
    if (bestResult != null) {
      final savings = 1.0 - bestResult.compressionRatio;
      if (savings >= minSavingsRatio &&
          bestResult.compressedSize < payload.length) {
        return bestResult;
      }
    }

    // Compression yielded no meaningful savings; return raw uncompressed
    return CompressedPayload(
      algorithm: CompressionAlgorithm.none,
      data: payload,
      originalSize: payload.length,
      compressedSize: payload.length,
    );
  }

  /// Decompresses a [CompressedPayload] back into raw bytes.
  Uint8List decompress(CompressedPayload compressed) {
    return decompressBytes(compressed.data, compressed.algorithm);
  }

  /// Decompresses raw [data] using the indicated [algorithm].
  Uint8List decompressBytes(Uint8List data, CompressionAlgorithm algorithm) {
    if (data.isEmpty || algorithm == CompressionAlgorithm.none) {
      return data;
    }

    switch (algorithm) {
      case CompressionAlgorithm.zlib:
        final decoded = const ZLibDecoder().decodeBytes(data);
        return Uint8List.fromList(decoded);
      case CompressionAlgorithm.gzip:
        final decoded = GZipDecoder().decodeBytes(data);
        return Uint8List.fromList(decoded);
      case CompressionAlgorithm.brotli:
        final codec = _brotliCodec;
        if (codec == null) {
          throw UnsupportedError(
            'BrotliCodec is not configured on PayloadCompressionService',
          );
        }
        return codec.decompress(data);
      case CompressionAlgorithm.none:
        return data;
    }
  }

  /// Decompresses an encapsulated wire envelope (1 byte algorithm + data).
  Uint8List decompressEnvelope(Uint8List envelope) {
    final payload = CompressedPayload.fromWireEnvelope(envelope);
    return decompress(payload);
  }

  /// Slices a binary [payload] into discrete frame chunks respecting the
  /// optical frame boundary limit ([maxSingleFramePayloadBytes] = 450 bytes).
  List<Uint8List> slicePayloadIntoFrames(
    Uint8List payload, {
    int frameLimitBytes = maxSingleFramePayloadBytes,
  }) {
    if (payload.isEmpty) {
      throw ArgumentError('Payload cannot be empty');
    }
    if (frameLimitBytes <= 0) {
      throw ArgumentError('Frame limit must be greater than zero');
    }
    if (frameLimitBytes > maxSingleFramePayloadBytes) {
      throw ArgumentError(
        'Frame limit ($frameLimitBytes bytes) exceeds maximum single-frame boundary ($maxSingleFramePayloadBytes bytes)',
      );
    }

    final totalFrames = (payload.length / frameLimitBytes).ceil();
    final frames = <Uint8List>[];

    for (var i = 0; i < totalFrames; i++) {
      final startIndex = i * frameLimitBytes;
      final endIndex = min(startIndex + frameLimitBytes, payload.length);
      final frameSlice = Uint8List.sublistView(payload, startIndex, endIndex);

      validateFrameBoundary(frameSlice);
      frames.add(frameSlice);
    }

    return frames;
  }

  /// Validates that an individual frame adheres to the 450-byte optical focus limit.
  void validateFrameBoundary(Uint8List frameBytes) {
    if (frameBytes.length > maxSingleFramePayloadBytes) {
      throw ArgumentError(
        'Frame size (${frameBytes.length} bytes) exceeds maximum single-frame limit ($maxSingleFramePayloadBytes bytes)',
      );
    }
  }
}
