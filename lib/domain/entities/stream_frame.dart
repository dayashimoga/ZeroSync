import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../../core/utils/crc32.dart';
import '../value_objects/chunk_header.dart';

/// Represents a single self-describing optical datagram frame.
class StreamFrame extends Equatable {
  final ChunkHeader header;
  final Uint8List payload;

  const StreamFrame({
    required this.header,
    required this.payload,
  });

  /// Validates whether the payload matches the recorded CRC32 checksum in the header.
  bool get isValidChecksum {
    final calculated = Crc32.compute(payload);
    return calculated == header.crc32;
  }

  /// Encodes this frame into a raw binary packet for QR transmission.
  Uint8List toWireBytes() {
    final headerBytes = header.toBytes();
    final combined = Uint8List(headerBytes.length + payload.length);
    combined.setRange(0, headerBytes.length, headerBytes);
    combined.setRange(headerBytes.length, combined.length, payload);
    return combined;
  }

  /// Deserializes a raw binary wire packet into a StreamFrame.
  factory StreamFrame.fromWireBytes(Uint8List wireBytes) {
    if (wireBytes.length < ChunkHeader.headerSize) {
      throw FormatException(
        'Wire datagram too short: ${wireBytes.length} bytes (minimum ${ChunkHeader.headerSize})',
      );
    }

    final headerBytes = Uint8List.sublistView(
      wireBytes,
      0,
      ChunkHeader.headerSize,
    );
    final header = ChunkHeader.fromBytes(headerBytes);

    final payload = Uint8List.sublistView(
      wireBytes,
      ChunkHeader.headerSize,
      wireBytes.length,
    );

    final frame = StreamFrame(header: header, payload: payload);
    if (!frame.isValidChecksum) {
      throw FormatException(
        'CRC32 checksum mismatch: expected ${header.crc32}, got ${Crc32.compute(payload)}',
      );
    }

    return frame;
  }

  @override
  List<Object?> get props => [header, payload];
}
