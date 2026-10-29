import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/core/utils/crc32.dart';
import 'package:airdrop_qr/domain/value_objects/packed_transport_header.dart';

void main() {
  group('PackedTransportHeader Bit-Packing & Alignment Specs', () {
    test('Exact 13-byte layout and Big-Endian alignment verification', () {
      const header = PackedTransportHeader(
        sessionId: 0x12345678,
        totalChunks: 0x000A, // 10
        chunkIndex: 0x0003, // 3
        crc32: 0x89ABCDEF,
        mimeFlag: MimeTypeFlag.json, // 0x02
      );

      final bytes = header.toBytes();
      expect(bytes.length, equals(13));

      // Byte 0..3: Session ID (0x12, 0x34, 0x56, 0x78)
      expect(bytes[0], 0x12);
      expect(bytes[1], 0x34);
      expect(bytes[2], 0x56);
      expect(bytes[3], 0x78);

      // Byte 4..5: Total Chunks (0x00, 0x0A)
      expect(bytes[4], 0x00);
      expect(bytes[5], 0x0A);

      // Byte 6..7: Chunk Index (0x00, 0x03)
      expect(bytes[6], 0x00);
      expect(bytes[7], 0x03);

      // Byte 8..11: CRC32 (0x89, 0xAB, 0xCD, 0xEF)
      expect(bytes[8], 0x89);
      expect(bytes[9], 0xAB);
      expect(bytes[10], 0xCD);
      expect(bytes[11], 0xEF);

      // Byte 12: MIME Flag (0x02)
      expect(bytes[12], 0x02);
    });

    test('Round-trip serialization preserves all fields', () {
      const original = PackedTransportHeader(
        sessionId: 0xA1B2C3D4,
        totalChunks: 250,
        chunkIndex: 125,
        crc32: 0xFEEDFACE,
        mimeFlag: MimeTypeFlag.vcard,
      );

      final bytes = original.toBytes();
      final restored = PackedTransportHeader.fromBytes(bytes);

      expect(restored.sessionId, original.sessionId);
      expect(restored.totalChunks, original.totalChunks);
      expect(restored.chunkIndex, original.chunkIndex);
      expect(restored.crc32, original.crc32);
      expect(restored.mimeFlag, original.mimeFlag);
      expect(restored, equals(original));
    });

    test('MimeTypeFlag resolution from raw byte', () {
      expect(MimeTypeFlag.fromByte(0x00), MimeTypeFlag.binary);
      expect(MimeTypeFlag.fromByte(0x01), MimeTypeFlag.plainText);
      expect(MimeTypeFlag.fromByte(0x02), MimeTypeFlag.json);
      expect(MimeTypeFlag.fromByte(0x03), MimeTypeFlag.vcard);
      expect(MimeTypeFlag.fromByte(0x04), MimeTypeFlag.wifi);
      expect(MimeTypeFlag.fromByte(0x05), MimeTypeFlag.imageJpeg);
      expect(MimeTypeFlag.fromByte(0x06), MimeTypeFlag.imagePng);
      expect(MimeTypeFlag.fromByte(0x07), MimeTypeFlag.cryptoKey);
      expect(MimeTypeFlag.fromByte(0x08), MimeTypeFlag.archiveZip);
      expect(MimeTypeFlag.fromByte(0x99), MimeTypeFlag.custom);
      expect(MimeTypeFlag.fromByte(0xFF), MimeTypeFlag.custom);
    });

    test('Enforces structural invariants on invalid values', () {
      // Chunk index < 1
      expect(
        () => const PackedTransportHeader(
          sessionId: 1,
          totalChunks: 5,
          chunkIndex: 0,
          crc32: 0,
          mimeFlag: MimeTypeFlag.binary,
        ).toBytes(),
        throwsA(isA<ArgumentError>()),
      );

      // Chunk index > totalChunks
      expect(
        () => const PackedTransportHeader(
          sessionId: 1,
          totalChunks: 5,
          chunkIndex: 6,
          crc32: 0,
          mimeFlag: MimeTypeFlag.binary,
        ).toBytes(),
        throwsA(isA<ArgumentError>()),
      );

      // Total chunks < 1
      expect(
        () => const PackedTransportHeader(
          sessionId: 1,
          totalChunks: 0,
          chunkIndex: 1,
          crc32: 0,
          mimeFlag: MimeTypeFlag.binary,
        ).toBytes(),
        throwsA(isA<ArgumentError>()),
      );

      // Total chunks > 65535
      expect(
        () => const PackedTransportHeader(
          sessionId: 1,
          totalChunks: 65536,
          chunkIndex: 1,
          crc32: 0,
          mimeFlag: MimeTypeFlag.binary,
        ).toBytes(),
        throwsA(isA<ArgumentError>()),
      );

      // Negative session ID
      expect(
        () => const PackedTransportHeader(
          sessionId: -1,
          totalChunks: 1,
          chunkIndex: 1,
          crc32: 0,
          mimeFlag: MimeTypeFlag.binary,
        ).toBytes(),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws FormatException when deserializing buffer shorter than 13 bytes', () {
      expect(
        () => PackedTransportHeader.fromBytes(Uint8List(12)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PackedTransportFrame Wire Datagrams & Integrity', () {
    test('Encodes and decodes wire datagrams with CRC32 integrity check', () {
      final payload = Uint8List.fromList('Payload slice test vector'.codeUnits);
      final crc = Crc32.compute(payload);

      final header = PackedTransportHeader(
        sessionId: 0x99,
        totalChunks: 1,
        chunkIndex: 1,
        crc32: crc,
        mimeFlag: MimeTypeFlag.plainText,
      );

      final frame = PackedTransportFrame(header: header, payload: payload);
      expect(frame.isValidChecksum, isTrue);

      final wireBytes = frame.toWireBytes();
      expect(wireBytes.length, equals(13 + payload.length));

      final restored = PackedTransportFrame.fromWireBytes(wireBytes);
      expect(restored.header, equals(header));
      expect(restored.payload, equals(payload));
      expect(restored.isValidChecksum, isTrue);
    });

    test('Detects CRC32 checksum tampering', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final crc = Crc32.compute(payload);

      final header = PackedTransportHeader(
        sessionId: 10,
        totalChunks: 1,
        chunkIndex: 1,
        crc32: crc,
        mimeFlag: MimeTypeFlag.binary,
      );

      final frame = PackedTransportFrame(header: header, payload: payload);
      final wireBytes = frame.toWireBytes();

      // Tamper with payload byte in wire datagram
      wireBytes[14] ^= 0xFF;

      expect(
        () => PackedTransportFrame.fromWireBytes(wireBytes, verifyChecksum: true),
        throwsA(isA<FormatException>()),
      );

      final untrustedFrame = PackedTransportFrame.fromWireBytes(
        wireBytes,
        verifyChecksum: false,
      );
      expect(untrustedFrame.isValidChecksum, isFalse);
    });

    test('Throws FormatException on datagram shorter than header size', () {
      expect(
        () => PackedTransportFrame.fromWireBytes(Uint8List(10)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Payload Slicing & Reassembly Pipeline', () {
    test('Slices small payload into a single frame within 450 bytes', () {
      final payload = Uint8List.fromList('Single Frame Transfer'.codeUnits);
      final frames = PackedTransportFrame.packPayload(
        rawPayload: payload,
        sessionId: 101,
        mimeFlag: MimeTypeFlag.plainText,
      );

      expect(frames.length, equals(1));
      expect(frames[0].header.totalChunks, 1);
      expect(frames[0].header.chunkIndex, 1);
      expect(frames[0].header.sessionId, 101);
      expect(frames[0].header.mimeFlag, MimeTypeFlag.plainText);
      expect(frames[0].toWireBytes().length, lessThanOrEqualTo(450));
      expect(frames[0].isValidChecksum, isTrue);

      final unpacked = PackedTransportFrame.unpackPayload(frames);
      expect(unpacked, equals(payload));
    });

    test('Slices multi-frame payload and guarantees each wire frame <= 450 bytes', () {
      final payload = Uint8List(1200);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = (i * 3) % 256;
      }

      final frames = PackedTransportFrame.packPayload(
        rawPayload: payload,
        sessionId: 404,
        mimeFlag: MimeTypeFlag.binary,
      );

      // 1200 bytes / 437 bytes max payload = 3 chunks (437 + 437 + 326)
      expect(frames.length, equals(3));

      for (var i = 0; i < frames.length; i++) {
        final frame = frames[i];
        expect(frame.header.sessionId, 404);
        expect(frame.header.totalChunks, 3);
        expect(frame.header.chunkIndex, i + 1);
        expect(frame.toWireBytes().length, lessThanOrEqualTo(450));
        expect(frame.isValidChecksum, isTrue);
      }

      expect(frames[0].payload.length, 437);
      expect(frames[1].payload.length, 437);
      expect(frames[2].payload.length, 326);

      // Reassemble in exact order
      final unpacked = PackedTransportFrame.unpackPayload(frames);
      expect(unpacked, equals(payload));
    });

    test('Reassembles out-of-order received frames correctly', () {
      final payload = Uint8List(1000);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = i % 256;
      }

      final frames = PackedTransportFrame.packPayload(
        rawPayload: payload,
        sessionId: 505,
      );

      // Reorder frames: [frame3, frame1, frame2]
      final shuffled = [frames[2], frames[0], frames[1]];
      final unpacked = PackedTransportFrame.unpackPayload(shuffled);

      expect(unpacked, equals(payload));
    });

    test('Throws ArgumentError on empty payload packing', () {
      expect(
        () => PackedTransportFrame.packPayload(
          rawPayload: Uint8List(0),
          sessionId: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError on invalid maxChunkSize', () {
      final data = Uint8List(50);
      expect(
        () => PackedTransportFrame.packPayload(
          rawPayload: data,
          sessionId: 1,
          maxChunkSize: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => PackedTransportFrame.packPayload(
          rawPayload: data,
          sessionId: 1,
          maxChunkSize: 438, // > 437 max
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError when unpacking frames from different sessions', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List(500),
        sessionId: 100,
      );
      final mismatched = PackedTransportFrame.packPayload(
        rawPayload: Uint8List(500),
        sessionId: 200,
      );

      expect(
        () => PackedTransportFrame.unpackPayload([frames[0], mismatched[1]]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws StateError when unpacking incomplete frames', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List(1000), // 3 frames
        sessionId: 300,
      );

      expect(
        () => PackedTransportFrame.unpackPayload([frames[0], frames[2]]),
        throwsA(isA<StateError>()),
      );
    });
  });
}
