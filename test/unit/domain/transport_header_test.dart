import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/value_objects/transport_header.dart';

void main() {
  group('TransportHeader 20-Byte Wire Specification Tests', () {
    test('Header binary size is exactly 20 bytes', () {
      final header = TransportHeader.createForPayload(
        payload: Uint8List.fromList([1, 2, 3, 4, 5]),
        k: 100,
        seed: 42,
        isEncrypted: true,
        rgbMode: RgbColorMode.green,
      );

      final bytes = header.toBytes();
      expect(bytes.length, equals(20));
      expect(TransportHeader.headerSize, equals(20));
    });

    test('Preamble magic is strictly 0x5A53', () {
      final header = TransportHeader.createForPayload(
        payload: Uint8List.fromList([1, 2, 3]),
        k: 10,
        seed: 1,
      );
      final bytes = header.toBytes();
      expect(bytes[0], equals(0x5A));
      expect(bytes[1], equals(0x53));
    });

    test('Flags serialize and deserialize correctly for all permutations', () {
      for (final isEncrypted in [true, false]) {
        for (final isCompressed in [true, false]) {
          for (final mode in RgbColorMode.values) {
            final header = TransportHeader(
              isEncrypted: isEncrypted,
              rgbMode: mode,
              isCompressed: isCompressed,
              k: 50,
              seed: 12345,
              payloadLength: 128,
              crc32c: 0xAABBCCDD,
            );

            final bytes = header.toBytes();
            final restored = TransportHeader.fromBytes(bytes);

            expect(restored.isEncrypted, equals(isEncrypted));
            expect(restored.rgbMode, equals(mode));
            expect(restored.isCompressed, equals(isCompressed));
            expect(restored.k, equals(50));
            expect(restored.seed, equals(12345));
            expect(restored.payloadLength, equals(128));
            expect(restored.crc32c, equals(0xAABBCCDD));
            expect(restored, equals(header));
          }
        }
      }
    });

    test('TransportFrame serializes and deserializes valid payload faithfully',
        () {
      final payload =
          Uint8List.fromList(List.generate(100, (i) => (i * 7) & 0xFF));
      final header = TransportHeader.createForPayload(
        payload: payload,
        k: 25,
        seed: 999,
        isEncrypted: true,
        rgbMode: RgbColorMode.red,
      );

      final frame = TransportFrame(header: header, payload: payload);
      expect(frame.isValidChecksum, isTrue);

      final wireBytes = frame.toWireBytes();
      expect(wireBytes.length, equals(20 + payload.length));

      final restoredFrame = TransportFrame.fromWireBytes(wireBytes);
      expect(restoredFrame.header, equals(header));
      expect(restoredFrame.payload, equals(payload));
      expect(restoredFrame.isValidChecksum, isTrue);
    });

    test('Rejects headers shorter than 20 bytes', () {
      expect(
        () => TransportHeader.fromBytes(Uint8List(19)),
        throwsA(isA<FormatException>()),
      );
    });

    test('Rejects frames shorter than 20 bytes', () {
      expect(
        () => TransportFrame.fromWireBytes(Uint8List(15)),
        throwsA(isA<FormatException>()),
      );
    });

    test('Rejects invalid magic preamble', () {
      final valid = TransportHeader.createForPayload(
        payload: Uint8List.fromList([1, 2, 3]),
        k: 10,
        seed: 1,
      ).toBytes();

      // Corrupt magic
      valid[0] = 0x00;
      expect(() => TransportHeader.fromBytes(valid),
          throwsA(isA<FormatException>()));
    });

    test('Rejects invalid K < 1', () {
      expect(
        () => const TransportHeader(
          isEncrypted: false,
          rgbMode: RgbColorMode.mono,
          k: 0,
          seed: 1,
          payloadLength: 10,
          crc32c: 0,
        ).validateInvariants(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('100% bit-flip rejection across wire frame (header + payload)', () {
      final payload = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      final frame = TransportFrame(
        header: TransportHeader.createForPayload(
          payload: payload,
          k: 12,
          seed: 777,
          isEncrypted: false,
          rgbMode: RgbColorMode.blue,
        ),
        payload: payload,
      );

      final wire = frame.toWireBytes();
      var rejectedCount = 0;
      final totalBits = wire.length * 8;

      for (var byteIdx = 0; byteIdx < wire.length; byteIdx++) {
        for (var bit = 0; bit < 8; bit++) {
          final corrupted = Uint8List.fromList(wire);
          corrupted[byteIdx] ^= (1 << bit);

          var rejected = false;
          try {
            final parsedFrame =
                TransportFrame.fromWireBytes(corrupted, verifyChecksum: true);
            // If it parsed without throwing, did the checksum flag as invalid?
            if (!parsedFrame.isValidChecksum) {
              rejected = true;
            }
          } catch (_) {
            rejected = true;
          }

          if (rejected) {
            rejectedCount++;
          }
        }
      }

      // Every single bit flip in the frame MUST be rejected
      expect(rejectedCount, equals(totalBits),
          reason:
              'Every 1-bit corruption in 20-byte header or payload must be rejected');
    });
  });
}
