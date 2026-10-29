import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/integrity_checksum_service.dart';

void main() {
  const service = IntegrityChecksumService();

  group('Continuous CRC32 Chunk Validation', () {
    test('Computes and verifies valid CRC32 checksum for chunk data', () {
      final chunk = Uint8List.fromList('Optical Chunk Datagram #1'.codeUnits);
      final crc = service.computeCrc32(chunk);

      expect(crc, isA<int>());
      expect(crc, greaterThan(0));
      expect(service.verifyChunkCrc32(chunk, crc), isTrue);

      // Mutate chunk byte
      final mutated = Uint8List.fromList(chunk);
      mutated[0] ^= 0xFF;
      expect(service.verifyChunkCrc32(mutated, crc), isFalse);
    });

    test('assertChunkCrc32 completes normally on matching CRC and throws on mismatch', () {
      final chunk = Uint8List.fromList([10, 20, 30, 40]);
      final crc = service.computeCrc32(chunk);

      expect(() => service.assertChunkCrc32(chunk, crc, chunkIndex: 1), returnsNormally);

      expect(
        () => service.assertChunkCrc32(chunk, crc ^ 0x12345678, chunkIndex: 5),
        throwsA(
          isA<ChecksumMismatchException>()
              .having((e) => e.chunkIndex, 'chunkIndex', 5)
              .having((e) => e.expectedCrc32, 'expectedCrc32', crc ^ 0x12345678)
              .having((e) => e.actualCrc32, 'actualCrc32', crc),
        ),
      );
    });
  });

  group('SHA-256 Cryptographic Checksum Specs', () {
    test('Validates standard NIST SHA-256 vectors', () {
      // Empty input vector
      final empty = Uint8List(0);
      expect(
        service.computeSha256Hex(empty),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      // "hello world" vector
      final hello = Uint8List.fromList('hello world'.codeUnits);
      expect(
        service.computeSha256Hex(hello),
        'b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9',
      );
    });

    test('computeSha256Bytes returns 32-byte digest', () {
      final data = Uint8List.fromList('ZeroSync SHA-256 Digest Test'.codeUnits);
      final digestBytes = service.computeSha256Bytes(data);
      expect(digestBytes.length, equals(32));
    });

    test('verifySha256 evaluates case-insensitively with whitespace tolerance', () {
      final data = Uint8List.fromList('hello world'.codeUnits);
      const expected = 'B94D27B9934D3E08A52E52D7DA7DABFAC484EFE37A5380EE9088F7ACE2EFCDE9';

      expect(service.verifySha256(data, expected), isTrue);
      expect(service.verifySha256(data, '   $expected   '), isTrue);
      expect(service.verifySha256(data, '0000000000000000000000000000000000000000000000000000000000000000'), isFalse);
    });

    test('assertSha256 throws CryptographicIntegrityException on digest mismatch', () {
      final data = Uint8List.fromList('Sensitive Vault File'.codeUnits);
      final actualHex = service.computeSha256Hex(data);
      const invalidHex = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      expect(() => service.assertSha256(data, actualHex), returnsNormally);

      expect(
        () => service.assertSha256(data, invalidHex),
        throwsA(
          isA<CryptographicIntegrityException>()
              .having((e) => e.expectedSha256, 'expectedSha256', invalidHex)
              .having((e) => e.actualSha256, 'actualSha256', actualHex),
        ),
      );
    });
  });

  group('Assembly & Audit Pipeline (auditAndAssemble)', () {
    test('Assembles intact chunks and verifies valid SHA-256', () {
      final chunk1 = Uint8List.fromList('ZERO_SYNC_PART_1_'.codeUnits);
      final chunk2 = Uint8List.fromList('ZERO_SYNC_PART_2_'.codeUnits);
      final chunk3 = Uint8List.fromList('ZERO_SYNC_PART_3'.codeUnits);

      final chunks = <int, Uint8List>{
        1: chunk1,
        2: chunk2,
        3: chunk3,
      };

      final crcMap = <int, int>{
        1: service.computeCrc32(chunk1),
        2: service.computeCrc32(chunk2),
        3: service.computeCrc32(chunk3),
      };

      final assembledExpected = Uint8List.fromList('ZERO_SYNC_PART_1_ZERO_SYNC_PART_2_ZERO_SYNC_PART_3'.codeUnits);
      final expectedSha = service.computeSha256Hex(assembledExpected);

      final report = service.auditAndAssemble(
        chunksByIndex: chunks,
        expectedCrc32ByIndex: crcMap,
        totalExpectedChunks: 3,
        expectedSha256Hex: expectedSha,
      );

      expect(report.isEntirelyValid, isTrue);
      expect(report.totalChunks, 3);
      expect(report.validChunksCount, 3);
      expect(report.corruptedChunkIndices, isEmpty);
      expect(report.computedSha256, expectedSha);
      expect(report.sha256Match, isTrue);
    });

    test('Flags corrupted chunk in CRC audit and halts whole-file hash calculation', () {
      final chunk1 = Uint8List.fromList([1, 2, 3]);
      final chunk2 = Uint8List.fromList([4, 5, 6]);

      final chunks = <int, Uint8List>{
        1: chunk1,
        2: chunk2,
      };

      final crcMap = <int, int>{
        1: service.computeCrc32(chunk1),
        2: service.computeCrc32(chunk2) ^ 0xAAAA, // corrupted expected CRC
      };

      final report = service.auditAndAssemble(
        chunksByIndex: chunks,
        expectedCrc32ByIndex: crcMap,
        totalExpectedChunks: 2,
      );

      expect(report.isEntirelyValid, isFalse);
      expect(report.validChunksCount, 1);
      expect(report.corruptedChunkIndices, equals([2]));
      expect(report.computedSha256, isEmpty);
      expect(report.sha256Match, isFalse);
    });

    test('Flags missing chunk in chunk map', () {
      final chunk1 = Uint8List.fromList([1, 2]);

      final chunks = <int, Uint8List>{
        1: chunk1,
        // Chunk 2 is missing
      };

      final crcMap = <int, int>{
        1: service.computeCrc32(chunk1),
        2: 0x12345678,
      };

      final report = service.auditAndAssemble(
        chunksByIndex: chunks,
        expectedCrc32ByIndex: crcMap,
        totalExpectedChunks: 2,
      );

      expect(report.isEntirelyValid, isFalse);
      expect(report.corruptedChunkIndices, equals([2]));
    });

    test('Detects valid chunks whose combined SHA-256 does not match expected hash', () {
      final chunk1 = Uint8List.fromList([1, 2, 3]);
      final chunks = <int, Uint8List>{1: chunk1};
      final crcMap = <int, int>{1: service.computeCrc32(chunk1)};

      const wrongHash = '0000000000000000000000000000000000000000000000000000000000000000';

      final report = service.auditAndAssemble(
        chunksByIndex: chunks,
        expectedCrc32ByIndex: crcMap,
        totalExpectedChunks: 1,
        expectedSha256Hex: wrongHash,
      );

      expect(report.isEntirelyValid, isFalse);
      expect(report.validChunksCount, 1);
      expect(report.corruptedChunkIndices, isEmpty);
      expect(report.sha256Match, isFalse);
    });
  });
}

