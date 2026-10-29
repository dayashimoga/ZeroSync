import 'dart:math';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../../core/utils/crc32.dart';

/// MIME types categorized into single-byte flags for optical datagrams.
enum MimeTypeFlag {
  binary(0x00, 'application/octet-stream'),
  plainText(0x01, 'text/plain'),
  json(0x02, 'application/json'),
  vcard(0x03, 'text/vcard'),
  wifi(0x04, 'application/x-wifi-config'),
  imageJpeg(0x05, 'image/jpeg'),
  imagePng(0x06, 'image/png'),
  cryptoKey(0x07, 'application/x-pem-file'),
  archiveZip(0x08, 'application/zip'),
  custom(0xFF, 'application/x-custom');

  final int value;
  final String mimeType;
  const MimeTypeFlag(this.value, this.mimeType);

  static MimeTypeFlag fromByte(int byte) {
    for (final flag in MimeTypeFlag.values) {
      if (flag.value == byte) return flag;
    }
    return MimeTypeFlag.custom;
  }
}

/// Compact 13-Byte Binary Packed Header for Optical Stream Transport.
///
/// Binary Byte Alignment (Big-Endian):
/// [0..3]   : Session ID (32-bit unsigned integer, 4 Bytes)
/// [4..5]   : Total Chunks (16-bit unsigned integer, 2 Bytes)
/// [6..7]   : Chunk Index (16-bit unsigned integer, 1-based, 2 Bytes)
/// [8..11]  : CRC32 Checksum (32-bit unsigned integer, IEEE 802.3, 4 Bytes)
/// [12]     : MIME Flag (8-bit unsigned integer, 1 Byte)
///
/// Total Header Size = exactly 13 Bytes.
class PackedTransportHeader extends Equatable {
  /// Total byte length of the packed header.
  static const int headerSize = 13;

  /// Maximum permissible 16-bit chunk count.
  static const int maxChunks = 65535;

  final int sessionId;
  final int totalChunks;
  final int chunkIndex;
  final int crc32;
  final MimeTypeFlag mimeFlag;

  const PackedTransportHeader({
    required this.sessionId,
    required this.totalChunks,
    required this.chunkIndex,
    required this.crc32,
    required this.mimeFlag,
  });

  /// Validates structural header invariants.
  void validateInvariants() {
    if (sessionId < 0 || sessionId > 0xFFFFFFFF) {
      throw ArgumentError(
        'Session ID must be an unsigned 32-bit integer (0..0xFFFFFFFF)',
      );
    }
    if (totalChunks < 1 || totalChunks > maxChunks) {
      throw ArgumentError('Total chunks must be in range 1..$maxChunks');
    }
    if (chunkIndex < 1 || chunkIndex > totalChunks) {
      throw ArgumentError(
        'Chunk index ($chunkIndex) out of range for total chunks ($totalChunks)',
      );
    }
    if (crc32 < 0 || crc32 > 0xFFFFFFFF) {
      throw ArgumentError(
        'CRC32 must be an unsigned 32-bit integer (0..0xFFFFFFFF)',
      );
    }
  }

  /// Serializes header into a 13-byte big-endian aligned buffer.
  Uint8List toBytes() {
    validateInvariants();

    final bytes = Uint8List(headerSize);
    final buffer = ByteData.sublistView(bytes);

    buffer.setUint32(0, sessionId, Endian.big);
    buffer.setUint16(4, totalChunks, Endian.big);
    buffer.setUint16(6, chunkIndex, Endian.big);
    buffer.setUint32(8, crc32, Endian.big);
    buffer.setUint8(12, mimeFlag.value);

    return bytes;
  }

  /// Deserializes a 13-byte big-endian aligned buffer into a [PackedTransportHeader].
  factory PackedTransportHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
        'Invalid header length: expected at least $headerSize bytes, received ${bytes.length}',
      );
    }

    final buffer = ByteData.sublistView(bytes, 0, headerSize);

    final sessionId = buffer.getUint32(0, Endian.big);
    final totalChunks = buffer.getUint16(4, Endian.big);
    final chunkIndex = buffer.getUint16(6, Endian.big);
    final crc32 = buffer.getUint32(8, Endian.big);
    final mimeFlag = MimeTypeFlag.fromByte(buffer.getUint8(12));

    final header = PackedTransportHeader(
      sessionId: sessionId,
      totalChunks: totalChunks,
      chunkIndex: chunkIndex,
      crc32: crc32,
      mimeFlag: mimeFlag,
    );

    header.validateInvariants();
    return header;
  }

  @override
  List<Object?> get props => [
        sessionId,
        totalChunks,
        chunkIndex,
        crc32,
        mimeFlag,
      ];
}

/// Self-describing optical frame combining a [PackedTransportHeader] and payload slice.
class PackedTransportFrame extends Equatable {
  /// Maximum optical single-frame byte budget (450 bytes).
  static const int maxFrameWireBytes = 450;

  /// Maximum permissible payload per single frame (450 - 13 = 437 bytes).
  static const int maxPayloadChunkBytes =
      maxFrameWireBytes - PackedTransportHeader.headerSize;

  final PackedTransportHeader header;
  final Uint8List payload;

  const PackedTransportFrame({
    required this.header,
    required this.payload,
  });

  /// Evaluates payload against recorded CRC32 checksum.
  bool get isValidChecksum => Crc32.compute(payload) == header.crc32;

  /// Serializes frame to wire bytes (13 bytes header + payload).
  Uint8List toWireBytes() {
    final headerBytes = header.toBytes();
    final totalBytes = Uint8List(headerBytes.length + payload.length);
    totalBytes.setRange(0, headerBytes.length, headerBytes);
    totalBytes.setRange(headerBytes.length, totalBytes.length, payload);
    return totalBytes;
  }

  /// Deserializes a raw wire datagram into a [PackedTransportFrame].
  factory PackedTransportFrame.fromWireBytes(
    Uint8List wireBytes, {
    bool verifyChecksum = true,
  }) {
    if (wireBytes.length < PackedTransportHeader.headerSize) {
      throw FormatException(
        'Datagram too short: ${wireBytes.length} bytes (minimum ${PackedTransportHeader.headerSize})',
      );
    }

    final headerBytes = Uint8List.sublistView(
      wireBytes,
      0,
      PackedTransportHeader.headerSize,
    );
    final header = PackedTransportHeader.fromBytes(headerBytes);

    final payload = Uint8List.sublistView(
      wireBytes,
      PackedTransportHeader.headerSize,
      wireBytes.length,
    );

    final frame = PackedTransportFrame(header: header, payload: payload);
    if (verifyChecksum && !frame.isValidChecksum) {
      throw FormatException(
        'Frame CRC32 checksum failure: expected 0x${header.crc32.toRadixString(16)}, got 0x${Crc32.compute(payload).toRadixString(16)}',
      );
    }

    return frame;
  }

  /// Slices [rawPayload] into an indexed sequence of [PackedTransportFrame] packets.
  static List<PackedTransportFrame> packPayload({
    required Uint8List rawPayload,
    required int sessionId,
    MimeTypeFlag mimeFlag = MimeTypeFlag.binary,
    int maxChunkSize = maxPayloadChunkBytes,
  }) {
    if (rawPayload.isEmpty) {
      throw ArgumentError('Payload cannot be empty');
    }
    if (maxChunkSize <= 0 || maxChunkSize > maxPayloadChunkBytes) {
      throw ArgumentError(
        'maxChunkSize ($maxChunkSize) must be between 1 and $maxPayloadChunkBytes bytes',
      );
    }

    final totalChunks = (rawPayload.length / maxChunkSize).ceil();
    if (totalChunks > PackedTransportHeader.maxChunks) {
      throw ArgumentError(
        'Payload requires $totalChunks chunks, exceeding 16-bit limit (${PackedTransportHeader.maxChunks})',
      );
    }

    final frames = <PackedTransportFrame>[];

    for (var i = 0; i < totalChunks; i++) {
      final startIndex = i * maxChunkSize;
      final endIndex = min(startIndex + maxChunkSize, rawPayload.length);
      final chunkData = Uint8List.sublistView(rawPayload, startIndex, endIndex);

      final crc = Crc32.compute(chunkData);
      final header = PackedTransportHeader(
        sessionId: sessionId,
        totalChunks: totalChunks,
        chunkIndex: i + 1,
        crc32: crc,
        mimeFlag: mimeFlag,
      );

      frames.add(PackedTransportFrame(header: header, payload: chunkData));
    }

    return frames;
  }

  /// Reassembles a collection of frames into the contiguous original binary payload.
  static Uint8List unpackPayload(List<PackedTransportFrame> frames) {
    if (frames.isEmpty) {
      throw ArgumentError('Frames collection cannot be empty');
    }

    final expectedSession = frames.first.header.sessionId;
    final totalChunks = frames.first.header.totalChunks;

    final chunkMap = <int, Uint8List>{};
    for (final frame in frames) {
      if (frame.header.sessionId != expectedSession) {
        throw ArgumentError(
          'Mismatched session ID: expected $expectedSession, received ${frame.header.sessionId}',
        );
      }
      if (!frame.isValidChecksum) {
        throw FormatException(
          'Corrupted frame CRC32 at chunk index ${frame.header.chunkIndex}',
        );
      }
      chunkMap[frame.header.chunkIndex] = frame.payload;
    }

    if (chunkMap.length < totalChunks) {
      throw StateError(
        'Incomplete payload: received ${chunkMap.length} of $totalChunks chunks',
      );
    }

    // Compute total assembled size
    var totalBytes = 0;
    for (var i = 1; i <= totalChunks; i++) {
      final chunk = chunkMap[i];
      if (chunk == null) {
        throw StateError('Missing required chunk at index $i');
      }
      totalBytes += chunk.length;
    }

    final result = Uint8List(totalBytes);
    var offset = 0;
    for (var i = 1; i <= totalChunks; i++) {
      final chunk = chunkMap[i]!;
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return result;
  }

  @override
  List<Object?> get props => [header, payload];
}
