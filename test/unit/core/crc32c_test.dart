import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/core/utils/crc32c.dart';

void main() {
  group('CRC-32C (Castagnoli) Checksum Specification Tests', () {
    test('RFC 3720 standard test vector "123456789" produces 0xE3069283', () {
      final input = Uint8List.fromList('123456789'.codeUnits);
      final crc = Crc32c.compute(input);
      expect(crc, equals(0xE3069283));
    });

    test('Empty byte array yields 0x00000000', () {
      final crc = Crc32c.compute(Uint8List(0));
      expect(crc, equals(0x00000000));
    });

    test('Single zero byte yields expected Castagnoli value 0x527D5351', () {
      final input = Uint8List.fromList([0x00]);
      final crc = Crc32c.compute(input);
      expect(crc, equals(0x527D5351));
    });

    test('Detects single-bit flip across payload data', () {
      final data = Uint8List.fromList(List.generate(256, (i) => i & 0xFF));
      final baselineCrc = Crc32c.compute(data);

      for (var byteIdx = 0; byteIdx < data.length; byteIdx++) {
        for (var bit = 0; bit < 8; bit++) {
          final corrupted = Uint8List.fromList(data);
          corrupted[byteIdx] ^= (1 << bit);
          final corruptedCrc = Crc32c.compute(corrupted);
          expect(corruptedCrc, isNot(equals(baselineCrc)),
              reason: 'Bit $bit in byte $byteIdx failed detection');
        }
      }
    });

    test('Identical data blocks produce identical checksums deterministically',
        () {
      final block1 = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final block2 = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      expect(Crc32c.compute(block1), equals(Crc32c.compute(block2)));
    });
  });
}
