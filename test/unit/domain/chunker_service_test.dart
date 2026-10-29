import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/stream_frame.dart';
import 'package:airdrop_qr/domain/services/chunker_service.dart';
import 'package:airdrop_qr/domain/value_objects/chunk_header.dart';

void main() {
  late ChunkerService chunker;

  setUp(() {
    chunker = ChunkerService();
  });

  group('ChunkHeader & Wire Protocol Specs', () {
    test('Header serializes and deserializes cleanly without byte drift', () {
      const original = ChunkHeader(
        sessionId: 0x123456789ABCDEF0,
        sequenceNumber: 42,
        totalChunks: 100,
        fecType: FecType.systematic,
        crc32: 0xDEADBEEF,
      );

      final bytes = original.toBytes();
      expect(bytes.length, equals(ChunkHeader.headerSize));

      final restored = ChunkHeader.fromBytes(bytes);
      expect(restored, equals(original));
      expect(restored.sessionId, equals(0x123456789ABCDEF0));
      expect(restored.sequenceNumber, equals(42));
      expect(restored.totalChunks, equals(100));
      expect(restored.fecType, equals(FecType.systematic));
      expect(restored.crc32, equals(0xDEADBEEF));
    });

    test('Throws FormatException on invalid magic preamble', () {
      final badBytes = Uint8List(ChunkHeader.headerSize);
      badBytes[0] = 0x00; // Corrupt magic
      expect(() => ChunkHeader.fromBytes(badBytes), throwsFormatException);
    });

    test('Throws ArgumentError when sequence exceeds total chunks', () {
      const invalid = ChunkHeader(
        sessionId: 1,
        sequenceNumber: 15,
        totalChunks: 10,
        fecType: FecType.systematic,
        crc32: 1234,
      );
      expect(() => invalid.validateInvariants(), throwsArgumentError);
    });
  });

  group('StreamFrame Datagram Encapsulation', () {
    test('Round-trip wire serialization preserves payload integrity', () {
      final samplePayload = Uint8List.fromList(
        utf8.encode('ZeroSync Air-Gapped Optical Frame Payload Verification'),
      );

      // Slicing through chunker ensures correct CRC
      final chunked = chunker.chunkPayload(
        payload: samplePayload,
        forcedSessionId: 9999,
      );
      expect(chunked.length, equals(1));

      final wire = chunked.first.toWireBytes();
      final decoded = StreamFrame.fromWireBytes(wire);

      expect(decoded.header, equals(chunked.first.header));
      expect(decoded.payload, equals(samplePayload));
      expect(decoded.isValidChecksum, isTrue);
    });

    test('Flags bit-flip corruptions during fromWireBytes', () {
      final samplePayload = Uint8List.fromList(utf8.encode('Sensitive cryptographic key'));
      final frames = chunker.chunkPayload(payload: samplePayload);
      final wire = frames.first.toWireBytes();

      // Flip a single bit in the payload portion
      wire[wire.length - 1] ^= 0x01;

      expect(() => StreamFrame.fromWireBytes(wire), throwsFormatException);
    });
  });

  group('ChunkerService Slicing & Reassembly', () {
    test('Chunks arbitrary binary payload across multiple frames', () {
      final rawData = Uint8List(500);
      for (var i = 0; i < rawData.length; i++) {
        rawData[i] = i % 256;
      }

      final frames = chunker.chunkPayload(
        payload: rawData,
        mtuBytes: 100,
        forcedSessionId: 12345,
      );

      expect(frames.length, equals(5));
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i].header.sequenceNumber, equals(i + 1));
        expect(frames[i].header.totalChunks, equals(5));
        expect(frames[i].header.sessionId, equals(12345));
        expect(frames[i].isValidChecksum, isTrue);
      }

      // Reassemble
      final reassembled = chunker.reassemblePayload(frames);
      expect(reassembled, equals(rawData));
    });

    test('Reassembles out-of-order received frames correctly', () {
      final rawData = Uint8List.fromList(utf8.encode('Reordering resilience test for optical streaming'));
      final frames = chunker.chunkPayload(payload: rawData, mtuBytes: 20);

      // Reverse frame order to simulate jitter
      final shuffled = frames.reversed.toList();
      final reassembled = chunker.reassemblePayload(shuffled);

      expect(reassembled, equals(rawData));
    });

    test('Throws on empty payload', () {
      expect(
        () => chunker.chunkPayload(payload: Uint8List(0)),
        throwsArgumentError,
      );
    });

    test('Throws when reassembling with missing chunks', () {
      final rawData = Uint8List(300);
      final frames = chunker.chunkPayload(payload: rawData, mtuBytes: 100);
      // Drop chunk 2
      final incomplete = [frames[0], frames[2]];

      expect(
        () => chunker.reassemblePayload(incomplete),
        throwsStateError,
      );
    });
  });
}
