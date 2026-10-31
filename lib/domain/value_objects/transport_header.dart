import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../../core/utils/crc32c.dart';

/// Optical RGB color multiplexing channels for multi-stream throughput acceleration.
enum RgbColorMode {
  /// Monochrome / standard single-matrix optical stream.
  mono(0x00),

  /// Red color multiplexing channel.
  red(0x01),

  /// Green color multiplexing channel.
  green(0x02),

  /// Blue color multiplexing channel.
  blue(0x03);

  final int value;
  const RgbColorMode(this.value);

  static RgbColorMode fromValue(int val) {
    switch (val & 0x03) {
      case 0x01:
        return RgbColorMode.red;
      case 0x02:
        return RgbColorMode.green;
      case 0x03:
        return RgbColorMode.blue;
      case 0x00:
      default:
        return RgbColorMode.mono;
    }
  }
}

/// ZeroSync Protocol v2 20-Byte Binary Wire Header.
///
/// Binary Byte Alignment (Big-Endian):
/// ```text
/// [0..1]   : Magic bytes (0x5A, 0x53 -> 'ZS' for ZeroSync)   (2 Bytes)
/// [2]      : Protocol Version (0x02 for v2)                   (1 Byte)
/// [3]      : Flags & Color Mode (uint8)                       (1 Byte)
///            - Bit 0: isEncrypted (0 = plain, 1 = encrypted)
///            - Bit 1..2: RgbColorMode (00=mono, 01=R, 10=G, 11=B)
///            - Bit 3: isCompressed (0 = raw, 1 = compressed)
///            - Bits 4..7: reserved (must be strictly 0)
/// [4..7]   : K (Total source blocks, 32-bit unsigned)         (4 Bytes)
/// [8..11]  : Seed (Droplet PRNG seed / sequence, 32-bit uint) (4 Bytes)
/// [12..15] : Payload Length / Symbol Size (32-bit unsigned)   (4 Bytes)
/// [16..19] : CRC-32C Checksum (Castagnoli, 32-bit unsigned)  (4 Bytes)
/// Total Size = 20 Bytes
/// ```
class TransportHeader extends Equatable {
  /// Header size on the wire in bytes.
  static const int headerSize = 20;

  /// Preamble prefix size before CRC-32C field (bytes 0..15).
  static const int prefixSize = 16;

  /// Expected protocol magic bytes: 0x5A, 0x53 ('Z', 'S').
  static const int magicConstant = 0x5A53;

  /// Current wire protocol version (v2).
  static const int currentVersion = 2;

  final int magic;
  final int version;
  final bool isEncrypted;
  final RgbColorMode rgbMode;
  final bool isCompressed;
  final int k;
  final int seed;
  final int payloadLength;
  final int crc32c;

  const TransportHeader({
    this.magic = magicConstant,
    this.version = currentVersion,
    required this.isEncrypted,
    required this.rgbMode,
    this.isCompressed = false,
    required this.k,
    required this.seed,
    required this.payloadLength,
    required this.crc32c,
  });

  /// Validates structural header invariants.
  void validateInvariants() {
    if (magic != magicConstant) {
      throw FormatException(
        'Invalid ZeroSync magic preamble: expected 0x5A53, received 0x${magic.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      );
    }
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported protocol version: expected $currentVersion, received $version',
      );
    }
    if ((flagsByte & 0xF0) != 0) {
      throw ArgumentError('Reserved flag bits (4..7) must be strictly 0');
    }
    if (k < 1 || k > 0xFFFFFFFF) {
      throw ArgumentError('Total blocks K must be in range 1..0xFFFFFFFF');
    }
    if (seed < 0 || seed > 0xFFFFFFFF) {
      throw ArgumentError('Seed must be an unsigned 32-bit integer');
    }
    if (payloadLength < 0 || payloadLength > 0xFFFFFFFF) {
      throw ArgumentError('Payload length must be an unsigned 32-bit integer');
    }
    if (crc32c < 0 || crc32c > 0xFFFFFFFF) {
      throw ArgumentError('CRC-32C must be an unsigned 32-bit integer');
    }
  }

  /// Encodes header flags into a single uint8 byte.
  int get flagsByte {
    var flags = 0;
    if (isEncrypted) flags |= 0x01;
    flags |= (rgbMode.value & 0x03) << 1;
    if (isCompressed) flags |= 0x08;
    return flags;
  }

  /// Returns the 16-byte binary prefix [0..15] used for wire framing and CRC-32C coverage.
  Uint8List toPrefixBytes() {
    final prefix = Uint8List(prefixSize);
    final view = ByteData.sublistView(prefix);

    view.setUint16(0, magic, Endian.big);
    view.setUint8(2, version);
    view.setUint8(3, flagsByte);
    view.setUint32(4, k, Endian.big);
    view.setUint32(8, seed, Endian.big);
    view.setUint32(12, payloadLength, Endian.big);

    return prefix;
  }

  /// Serializes header into a 20-byte big-endian aligned buffer.
  Uint8List toBytes() {
    validateInvariants();

    final bytes = Uint8List(headerSize);
    final view = ByteData.sublistView(bytes);

    bytes.setRange(0, prefixSize, toPrefixBytes());
    view.setUint32(16, crc32c, Endian.big);

    return bytes;
  }

  /// Deserializes a 20-byte big-endian aligned buffer into a [TransportHeader].
  factory TransportHeader.fromBytes(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw FormatException(
        'Transport header datagram too short: expected at least $headerSize bytes, received ${bytes.length}',
      );
    }

    final view = ByteData.sublistView(bytes, 0, headerSize);
    final magic = view.getUint16(0, Endian.big);
    if (magic != magicConstant) {
      throw FormatException(
        'Invalid ZeroSync magic preamble: expected 0x5A53, received 0x${magic.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      );
    }

    final version = view.getUint8(2);
    if (version != currentVersion) {
      throw FormatException(
        'Unsupported protocol version: expected $currentVersion, received $version',
      );
    }

    final flags = view.getUint8(3);
    if ((flags & 0xF0) != 0) {
      throw const FormatException(
          'Reserved flag bits (4..7) must be strictly 0');
    }

    final isEncrypted = (flags & 0x01) != 0;
    final rgbMode = RgbColorMode.fromValue((flags >> 1) & 0x03);
    final isCompressed = (flags & 0x08) != 0;

    final k = view.getUint32(4, Endian.big);
    final seed = view.getUint32(8, Endian.big);
    final payloadLength = view.getUint32(12, Endian.big);
    final crc32c = view.getUint32(16, Endian.big);

    final header = TransportHeader(
      magic: magic,
      version: version,
      isEncrypted: isEncrypted,
      rgbMode: rgbMode,
      isCompressed: isCompressed,
      k: k,
      seed: seed,
      payloadLength: payloadLength,
      crc32c: crc32c,
    );

    header.validateInvariants();
    return header;
  }

  /// Helper factory constructing a [TransportHeader] with CRC-32C calculated over
  /// the 16-byte header prefix and the [payload] data.
  factory TransportHeader.createForPayload({
    required Uint8List payload,
    required int k,
    required int seed,
    bool isEncrypted = false,
    RgbColorMode rgbMode = RgbColorMode.mono,
    bool isCompressed = false,
    int version = currentVersion,
  }) {
    final prefix = Uint8List(prefixSize);
    final view = ByteData.sublistView(prefix);

    var flags = 0;
    if (isEncrypted) flags |= 0x01;
    flags |= (rgbMode.value & 0x03) << 1;
    if (isCompressed) flags |= 0x08;

    view.setUint16(0, magicConstant, Endian.big);
    view.setUint8(2, version);
    view.setUint8(3, flags);
    view.setUint32(4, k, Endian.big);
    view.setUint32(8, seed, Endian.big);
    view.setUint32(12, payload.length, Endian.big);

    final crc = Crc32c.computeCombined(prefix, payload);

    return TransportHeader(
      magic: magicConstant,
      version: version,
      isEncrypted: isEncrypted,
      rgbMode: rgbMode,
      isCompressed: isCompressed,
      k: k,
      seed: seed,
      payloadLength: payload.length,
      crc32c: crc,
    );
  }

  TransportHeader copyWith({
    int? magic,
    int? version,
    bool? isEncrypted,
    RgbColorMode? rgbMode,
    bool? isCompressed,
    int? k,
    int? seed,
    int? payloadLength,
    int? crc32c,
  }) {
    return TransportHeader(
      magic: magic ?? this.magic,
      version: version ?? this.version,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      rgbMode: rgbMode ?? this.rgbMode,
      isCompressed: isCompressed ?? this.isCompressed,
      k: k ?? this.k,
      seed: seed ?? this.seed,
      payloadLength: payloadLength ?? this.payloadLength,
      crc32c: crc32c ?? this.crc32c,
    );
  }

  @override
  List<Object?> get props => [
        magic,
        version,
        isEncrypted,
        rgbMode,
        isCompressed,
        k,
        seed,
        payloadLength,
        crc32c,
      ];
}

/// Optical wire datagram uniting a 20-byte [TransportHeader] with its symbol payload.
class TransportFrame extends Equatable {
  final TransportHeader header;
  final Uint8List payload;

  const TransportFrame({
    required this.header,
    required this.payload,
  });

  /// Evaluates payload and header prefix against recorded Castagnoli CRC-32C checksum.
  bool get isValidChecksum {
    final prefix = header.toPrefixBytes();
    return Crc32c.computeCombined(prefix, payload) == header.crc32c;
  }

  /// Serializes frame to wire bytes (20 bytes header + payload).
  Uint8List toWireBytes() {
    final headerBytes = header.toBytes();
    final wireBytes = Uint8List(headerBytes.length + payload.length);
    wireBytes.setRange(0, headerBytes.length, headerBytes);
    wireBytes.setRange(headerBytes.length, wireBytes.length, payload);
    return wireBytes;
  }

  /// Deserializes a raw optical wire datagram into a [TransportFrame].
  ///
  /// Verifies magic preamble, header length, payload length consistency,
  /// and Castagnoli CRC-32C checksum directly against the raw wire prefix.
  factory TransportFrame.fromWireBytes(
    Uint8List wireBytes, {
    bool verifyChecksum = true,
  }) {
    if (wireBytes.length < TransportHeader.headerSize) {
      throw FormatException(
        'Transport datagram too short: ${wireBytes.length} bytes (minimum ${TransportHeader.headerSize})',
      );
    }

    final rawPrefix = Uint8List.sublistView(
      wireBytes,
      0,
      TransportHeader.prefixSize,
    );

    final headerBytes = Uint8List.sublistView(
      wireBytes,
      0,
      TransportHeader.headerSize,
    );
    final header = TransportHeader.fromBytes(headerBytes);

    final payload = Uint8List.sublistView(
      wireBytes,
      TransportHeader.headerSize,
      wireBytes.length,
    );

    if (payload.length != header.payloadLength) {
      throw FormatException(
        'Payload size mismatch: expected ${header.payloadLength} bytes, found ${payload.length}',
      );
    }

    if (verifyChecksum) {
      final calculatedCrc = Crc32c.computeCombined(rawPrefix, payload);
      if (calculatedCrc != header.crc32c) {
        throw FormatException(
          'TransportFrame CRC-32C verification failed: expected 0x${header.crc32c.toRadixString(16).padLeft(8, '0').toUpperCase()}, calculated 0x${calculatedCrc.toRadixString(16).padLeft(8, '0').toUpperCase()}',
        );
      }
    }

    return TransportFrame(header: header, payload: payload);
  }

  @override
  List<Object?> get props => [header, payload];
}
