import 'dart:typed_data';
import 'package:equatable/equatable.dart';

enum FecType {
  systematic(0),
  repair(1);

  final int value;
  const FecType(this.value);

  static FecType fromValue(int val) {
    if (val == 1) return FecType.repair;
    return FecType.systematic;
  }
}

/// ZeroSync Protocol Header (ZSP-V1)
/// Binary layout:
/// [0..3]   : Magic bytes (0x5A, 0x53, 0x50, 0x31 -> "ZSP1")
/// [4]      : Version (0x01)
/// [5..12]  : Session ID (64-bit BigEndian unsigned integer)
/// [13..14] : Sequence Number (16-bit BigEndian unsigned integer)
/// [15..16] : Total Chunks (16-bit BigEndian unsigned integer)
/// [17]     : FEC Type (0 = Systematic, 1 = Repair)
/// [18..21] : IEEE 802.3 CRC32 of payload (32-bit BigEndian unsigned integer)
/// Total Header Size = 22 Bytes
class ChunkHeader extends Equatable {
  static const int headerSize = 22;
  static const List<int> magicBytes = [0x5A, 0x53, 0x50, 0x31]; // "ZSP1"
  static const int currentVersion = 1;

  final int sessionId;
  final int sequenceNumber;
  final int totalChunks;
  final FecType fecType;
  final int crc32;

  const ChunkHeader({
    required this.sessionId,
    required this.sequenceNumber,
    required this.totalChunks,
    required this.fecType,
    required this.crc32,
  });

  /// Invariant check
  void validateInvariants() {
    if (sequenceNumber < 1) {
      throw ArgumentError('Sequence number must be >= 1');
    }
    if (totalChunks < 1) {
      throw ArgumentError('Total chunks must be >= 1');
    }
    if (fecType == FecType.systematic && sequenceNumber > totalChunks) {
      throw ArgumentError('Systematic sequence cannot exceed total chunks');
    }
  }

  Uint8List toBytes() {
    final buffer = ByteData(headerSize);
    // Magic
    buffer.setUint8(0, magicBytes[0]);
    buffer.setUint8(1, magicBytes[1]);
    buffer.setUint8(2, magicBytes[2]);
    buffer.setUint8(3, magicBytes[3]);
    // Version
    buffer.setUint8(4, currentVersion);
    // Session ID (64-bit)
    buffer.setUint64(5, sessionId, Endian.big);
    // Sequence Number (16-bit)
    buffer.setUint16(13, sequenceNumber, Endian.big);
    // Total Chunks (16-bit)
    buffer.setUint16(15, totalChunks, Endian.big);
    // FEC Type (8-bit)
    buffer.setUint8(17, fecType.value);
    // CRC32 (32-bit)
    buffer.setUint32(18, crc32, Endian.big);

    return buffer.buffer.asUint8List();
  }

  factory ChunkHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
        'Invalid header length: expected $headerSize, got ${bytes.length}',
      );
    }

    final data = ByteData.sublistView(bytes, 0, headerSize);

    // Verify magic
    if (data.getUint8(0) != magicBytes[0] ||
        data.getUint8(1) != magicBytes[1] ||
        data.getUint8(2) != magicBytes[2] ||
        data.getUint8(3) != magicBytes[3]) {
      throw const FormatException('Invalid ZSP magic preamble');
    }

    final version = data.getUint8(4);
    if (version != currentVersion) {
      throw FormatException('Unsupported ZSP version: $version');
    }

    final sessionId = data.getUint64(5, Endian.big);
    final sequenceNumber = data.getUint16(13, Endian.big);
    final totalChunks = data.getUint16(15, Endian.big);
    final fecType = FecType.fromValue(data.getUint8(17));
    final crc32 = data.getUint32(18, Endian.big);

    final header = ChunkHeader(
      sessionId: sessionId,
      sequenceNumber: sequenceNumber,
      totalChunks: totalChunks,
      fecType: fecType,
      crc32: crc32,
    );
    header.validateInvariants();
    return header;
  }

  @override
  List<Object?> get props => [
        sessionId,
        sequenceNumber,
        totalChunks,
        fecType,
        crc32,
      ];
}
