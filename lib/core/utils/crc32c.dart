import 'dart:typed_data';

/// Pure Dart CRC-32C (Castagnoli) Implementation (Polynomial: 0x82F63B78 reflected / 0x1EDC6F41).
///
/// CRC-32C provides superior Hamming distance and error-detection characteristics
/// compared to standard IEEE 802.3 CRC-32, especially for optical transmissions,
/// SCTP, and iSCSI protocols.
class Crc32c {
  // Castagnoli reflected polynomial: 0x82F63B78
  static const int _polynomial = 0x82F63B78;
  static final Uint32List _table = _generateTable();

  static Uint32List _generateTable() {
    final table = Uint32List(256);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var bit = 0; bit < 8; bit++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ _polynomial;
        } else {
          crc = crc >>> 1;
        }
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  /// Computes the 32-bit CRC-32C (Castagnoli) checksum of [data].
  ///
  /// Conforms to RFC 3720 check value:
  /// `Crc32c.compute(Uint8List.fromList('123456789'.codeUnits)) == 0xE3069283`.
  static int compute(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < data.length; i++) {
      final index = (crc ^ data[i]) & 0xFF;
      crc = (crc >>> 8) ^ _table[index];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Computes CRC-32C across two byte sequences sequentially without intermediate allocation.
  static int computeCombined(Uint8List part1, Uint8List part2) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < part1.length; i++) {
      final index = (crc ^ part1[i]) & 0xFF;
      crc = (crc >>> 8) ^ _table[index];
    }
    for (var i = 0; i < part2.length; i++) {
      final index = (crc ^ part2[i]) & 0xFF;
      crc = (crc >>> 8) ^ _table[index];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
