import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:equatable/equatable.dart';
import '../../core/utils/crc32.dart';

/// Exception thrown when a per-chunk CRC32 checksum fails verification.
class ChecksumMismatchException implements Exception {
  final int chunkIndex;
  final int expectedCrc32;
  final int actualCrc32;

  const ChecksumMismatchException({
    required this.chunkIndex,
    required this.expectedCrc32,
    required this.actualCrc32,
  });

  @override
  String toString() =>
      'ChecksumMismatchException: CRC32 failure at chunk $chunkIndex (expected 0x${expectedCrc32.toRadixString(16)}, got 0x${actualCrc32.toRadixString(16)})';
}

/// Exception thrown when whole-payload SHA-256 cryptographic verification fails.
class CryptographicIntegrityException implements Exception {
  final String expectedSha256;
  final String actualSha256;

  const CryptographicIntegrityException({
    required this.expectedSha256,
    required this.actualSha256,
  });

  @override
  String toString() =>
      'CryptographicIntegrityException: SHA-256 digest mismatch (expected $expectedSha256, got $actualSha256)';
}

/// Comprehensive verification report summarizing chunk and whole-file integrity.
class PayloadIntegrityReport extends Equatable {
  final bool isEntirelyValid;
  final int totalChunks;
  final int validChunksCount;
  final List<int> corruptedChunkIndices;
  final String computedSha256;
  final bool? sha256Match;

  const PayloadIntegrityReport({
    required this.isEntirelyValid,
    required this.totalChunks,
    required this.validChunksCount,
    required this.corruptedChunkIndices,
    required this.computedSha256,
    this.sha256Match,
  });

  @override
  List<Object?> get props => [
        isEntirelyValid,
        totalChunks,
        validChunksCount,
        corruptedChunkIndices,
        computedSha256,
        sha256Match,
      ];
}

/// Domain service orchestrating continuous per-chunk CRC32 verification alongside
/// end-to-end SHA-256 cryptographic validation upon optical datagram assembly.
class IntegrityChecksumService {
  const IntegrityChecksumService();

  /// Computes IEEE 802.3 32-bit CRC32 checksum for a chunk.
  int computeCrc32(Uint8List chunk) => Crc32.compute(chunk);

  /// Validates a single chunk against an expected CRC32 value.
  bool verifyChunkCrc32(Uint8List chunk, int expectedCrc32) {
    return Crc32.compute(chunk) == expectedCrc32;
  }

  /// Asserts that a chunk matches [expectedCrc32], throwing [ChecksumMismatchException] on divergence.
  void assertChunkCrc32(
    Uint8List chunk,
    int expectedCrc32, {
    int chunkIndex = 0,
  }) {
    final actual = Crc32.compute(chunk);
    if (actual != expectedCrc32) {
      throw ChecksumMismatchException(
        chunkIndex: chunkIndex,
        expectedCrc32: expectedCrc32,
        actualCrc32: actual,
      );
    }
  }

  /// Computes SHA-256 cryptographic hash of a binary payload as a 64-character lowercase hex string.
  String computeSha256Hex(Uint8List payload) {
    final digest = crypto.sha256.convert(payload);
    return digest.toString();
  }

  /// Computes raw 32-byte SHA-256 digest bytes for a binary payload.
  Uint8List computeSha256Bytes(Uint8List payload) {
    final digest = crypto.sha256.convert(payload);
    return Uint8List.fromList(digest.bytes);
  }

  /// Verifies a payload against an expected SHA-256 hex string (case-insensitive).
  bool verifySha256(Uint8List payload, String expectedSha256Hex) {
    final actualHex = computeSha256Hex(payload);
    return actualHex.toLowerCase() == expectedSha256Hex.trim().toLowerCase();
  }

  /// Asserts that a payload matches [expectedSha256Hex], throwing [CryptographicIntegrityException] on mismatch.
  void assertSha256(Uint8List payload, String expectedSha256Hex) {
    final actualHex = computeSha256Hex(payload);
    final normalizedExpected = expectedSha256Hex.trim().toLowerCase();
    if (actualHex != normalizedExpected) {
      throw CryptographicIntegrityException(
        expectedSha256: normalizedExpected,
        actualSha256: actualHex,
      );
    }
  }

  /// Audits a set of chunks with their expected CRC32 checksums, assembling them into
  /// a contiguous payload and verifying the resulting whole-file SHA-256 hash.
  PayloadIntegrityReport auditAndAssemble({
    required Map<int, Uint8List> chunksByIndex,
    required Map<int, int> expectedCrc32ByIndex,
    required int totalExpectedChunks,
    String? expectedSha256Hex,
  }) {
    final corruptedIndices = <int>[];
    var validCount = 0;

    for (var i = 1; i <= totalExpectedChunks; i++) {
      final chunk = chunksByIndex[i];
      final expectedCrc = expectedCrc32ByIndex[i];

      if (chunk == null || expectedCrc == null) {
        corruptedIndices.add(i);
        continue;
      }

      if (verifyChunkCrc32(chunk, expectedCrc)) {
        validCount++;
      } else {
        corruptedIndices.add(i);
      }
    }

    if (corruptedIndices.isNotEmpty || validCount < totalExpectedChunks) {
      return PayloadIntegrityReport(
        isEntirelyValid: false,
        totalChunks: totalExpectedChunks,
        validChunksCount: validCount,
        corruptedChunkIndices: corruptedIndices,
        computedSha256: '',
        sha256Match: false,
      );
    }

    // Assemble payload
    var totalBytes = 0;
    for (var i = 1; i <= totalExpectedChunks; i++) {
      totalBytes += chunksByIndex[i]!.length;
    }

    final assembled = Uint8List(totalBytes);
    var offset = 0;
    for (var i = 1; i <= totalExpectedChunks; i++) {
      final chunk = chunksByIndex[i]!;
      assembled.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final actualSha256 = computeSha256Hex(assembled);
    final shaMatch = expectedSha256Hex != null
        ? actualSha256 == expectedSha256Hex.trim().toLowerCase()
        : null;

    final isEntirelyValid = shaMatch ?? true;

    return PayloadIntegrityReport(
      isEntirelyValid: isEntirelyValid,
      totalChunks: totalExpectedChunks,
      validChunksCount: validCount,
      corruptedChunkIndices: const [],
      computedSha256: actualSha256,
      sha256Match: shaMatch,
    );
  }
}

