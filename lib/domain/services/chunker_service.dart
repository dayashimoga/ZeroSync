import 'dart:math';
import 'dart:typed_data';
import '../../core/utils/crc32.dart';
import '../entities/stream_frame.dart';
import '../value_objects/chunk_header.dart';

/// Pure Domain Chunker Service
/// Splits raw binary payloads into uniform StreamFrame packets.
class ChunkerService {
  /// Default MTU in bytes tailored for standard QR Version 10-15 under Medium ECC.
  static const int defaultMtuBytes = 180;

  /// Maximum permissible payload for an air-gapped optical session (50 MB).
  static const int maxPayloadBytes = 50 * 1024 * 1024;

  final Random _random;

  ChunkerService({Random? random}) : _random = random ?? Random.secure();

  /// Slices [payload] into a sequence of [StreamFrame] objects.
  List<StreamFrame> chunkPayload({
    required Uint8List payload,
    int mtuBytes = defaultMtuBytes,
    int? forcedSessionId,
  }) {
    if (payload.isEmpty) {
      throw ArgumentError('Payload cannot be empty');
    }
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError(
        'Payload exceeds maximum allowed size ($maxPayloadBytes bytes)',
      );
    }
    if (mtuBytes < 16) {
      throw ArgumentError('MTU bytes must be >= 16 bytes');
    }

    final totalChunks = (payload.length / mtuBytes).ceil();
    if (totalChunks > 65535) {
      throw ArgumentError(
        'Payload requires $totalChunks chunks, exceeding 16-bit sequence limit (65535)',
      );
    }

    final sessionId = forcedSessionId ?? _generateSessionId();
    final frames = <StreamFrame>[];

    for (var i = 0; i < totalChunks; i++) {
      final startIndex = i * mtuBytes;
      final endIndex = min(startIndex + mtuBytes, payload.length);
      final chunkData = Uint8List.sublistView(payload, startIndex, endIndex);

      final crc = Crc32.compute(chunkData);
      final header = ChunkHeader(
        sessionId: sessionId,
        sequenceNumber: i + 1,
        totalChunks: totalChunks,
        fecType: FecType.systematic,
        crc32: crc,
      );

      frames.add(StreamFrame(header: header, payload: chunkData));
    }

    return frames;
  }

  /// Reassembles an in-order or out-of-order collection of systematic frames.
  Uint8List reassemblePayload(List<StreamFrame> frames) {
    if (frames.isEmpty) {
      throw ArgumentError('Frames list cannot be empty');
    }

    final firstHeader = frames.first.header;
    final sessionId = firstHeader.sessionId;
    final totalChunks = firstHeader.totalChunks;

    final chunkMap = <int, Uint8List>{};
    for (final frame in frames) {
      if (frame.header.sessionId != sessionId) {
        throw ArgumentError('Mismatched session IDs in frame collection');
      }
      if (!frame.isValidChecksum) {
        throw FormatException(
          'Corrupted frame sequence: ${frame.header.sequenceNumber}',
        );
      }
      if (frame.header.fecType == FecType.systematic) {
        chunkMap[frame.header.sequenceNumber] = frame.payload;
      }
    }

    if (chunkMap.length < totalChunks) {
      throw StateError(
        'Incomplete payload: received ${chunkMap.length} of $totalChunks chunks',
      );
    }

    final totalBytes = chunkMap.values.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalBytes);
    var offset = 0;

    for (var seq = 1; seq <= totalChunks; seq++) {
      final chunk = chunkMap[seq];
      if (chunk == null) {
        throw StateError('Missing sequence chunk #$seq during reassembly');
      }
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  int _generateSessionId() {
    // Generate a positive 63-bit integer
    final high = _random.nextInt(0x7FFFFFFF);
    final low = _random.nextInt(0xFFFFFFFF);
    return ((high << 32) | low) & 0x7FFFFFFFFFFFFFFF;
  }
}
