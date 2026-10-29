import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/airgap_file_writer_service.dart';
import 'package:airdrop_qr/domain/services/integrity_checksum_service.dart';
import 'package:airdrop_qr/domain/services/payload_compression_service.dart';
import 'package:airdrop_qr/domain/value_objects/packed_transport_header.dart';

void main() {
  late MemorySandboxedStorageAdapter storageAdapter;
  late AirgapFileWriterService service;
  const integrityService = IntegrityChecksumService();
  const compressionService = PayloadCompressionService();

  setUp(() {
    storageAdapter = MemorySandboxedStorageAdapter();
    service = AirgapFileWriterService(
      storageAdapter: storageAdapter,
      integrityService: integrityService,
      compressionService: compressionService,
    );
  });

  group('MIME Extension & Filename Sanitization Specs', () {
    test('Resolves canonical extensions across all MIME flags', () {
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.plainText), '.txt');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.json), '.json');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.vcard), '.vcf');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.wifi), '.conf');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.imageJpeg), '.jpg');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.imagePng), '.png');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.cryptoKey), '.pem');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.archiveZip), '.zip');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.binary), '.bin');
      expect(AirgapFileWriterService.resolveExtensionForMime(MimeTypeFlag.custom), '.dat');
    });

    test('Sanitizes illegal path traversal characters in filenames', () {
      expect(
        AirgapFileWriterService.sanitizeFileName('../../etc/passwd'),
        'etc_passwd',
      );
      expect(
        AirgapFileWriterService.sanitizeFileName('report:version?1*'),
        'report_version_1_',
      );
      expect(
        AirgapFileWriterService.sanitizeFileName('...test.txt'),
        'test.txt',
      );
      expect(
        AirgapFileWriterService.sanitizeFileName('   '),
        'zerosync_file',
      );
    });
  });

  group('Uncompressed Stream Deserialization & Storage Specs', () {
    test('Verifies SHA-256 and writes uncompressed file with canonical extension', () async {
      final payload = Uint8List.fromList('ZeroSync Contact Card V4'.codeUnits);
      final expectedSha = integrityService.computeSha256Hex(payload);

      final result = await service.processCompletedStream(
        assembledPayload: payload,
        mimeFlag: MimeTypeFlag.vcard,
        expectedSha256Hex: expectedSha,
        preferredFileName: 'contact_alice',
      );

      expect(result.fileName, 'contact_alice.vcf');
      expect(result.sha256Checksum, expectedSha);
      expect(result.fileSizeBytes, payload.length);
      expect(result.mimeFlag, MimeTypeFlag.vcard);

      final exists = await storageAdapter.fileExists(result.filePath);
      expect(exists, isTrue);

      final readBytes = await storageAdapter.readBinaryFile(result.filePath);
      expect(readBytes, equals(payload));
    });

    test('Preserves extension if already provided in preferredFileName', () async {
      final payload = Uint8List.fromList('{"session":"test"}'.codeUnits);

      final result = await service.processCompletedStream(
        assembledPayload: payload,
        mimeFlag: MimeTypeFlag.json,
        preferredFileName: 'metadata.json',
      );

      expect(result.fileName, 'metadata.json');
      expect(result.filePath, endsWith('metadata.json'));
    });

    test('Generates hash-based filename when preferredFileName is omitted', () async {
      final payload = Uint8List.fromList('Binary Data Stream'.codeUnits);
      final sha = integrityService.computeSha256Hex(payload);
      final shortHash = sha.substring(0, 10);

      final result = await service.processCompletedStream(
        assembledPayload: payload,
        mimeFlag: MimeTypeFlag.binary,
      );

      expect(result.fileName, 'zerosync_$shortHash.bin');
      expect(result.filePath, endsWith('zerosync_$shortHash.bin'));
    });
  });

  group('Compressed Envelope Decompression & Storage Specs', () {
    test('Decompresses wire envelope, validates SHA-256, and writes decompressed data', () async {
      final originalText = 'AIR_GAPPED_OPTICAL_TRANSFER_COMPRESSION_TEST_' * 20;
      final originalBytes = Uint8List.fromList(originalText.codeUnits);
      final expectedSha = integrityService.computeSha256Hex(originalBytes);

      // Compress and envelope
      final compressed = compressionService.compress(
        originalBytes,
        algorithm: CompressionAlgorithm.zlib,
      );
      final envelope = compressed.toWireEnvelope();

      final result = await service.processCompletedStream(
        assembledPayload: envelope,
        mimeFlag: MimeTypeFlag.plainText,
        expectedSha256Hex: expectedSha,
        preferredFileName: 'decompressed_report.txt',
        isCompressedEnvelope: true,
      );

      expect(result.fileName, 'decompressed_report.txt');
      expect(result.fileSizeBytes, originalBytes.length);
      expect(result.sha256Checksum, expectedSha);

      final savedBytes = await storageAdapter.readBinaryFile(result.filePath);
      expect(savedBytes, equals(originalBytes));
    });
  });

  group('Error & Invariant Handling Specs', () {
    test('Throws ArgumentError on empty assembled payload', () async {
      expect(
        () => service.processCompletedStream(
          assembledPayload: Uint8List(0),
          mimeFlag: MimeTypeFlag.plainText,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws CryptographicIntegrityException on SHA-256 mismatch without writing to disk', () async {
      final payload = Uint8List.fromList('Valid Data'.codeUnits);
      const corruptedSha = '0000000000000000000000000000000000000000000000000000000000000000';

      expect(
        () => service.processCompletedStream(
          assembledPayload: payload,
          mimeFlag: MimeTypeFlag.plainText,
          expectedSha256Hex: corruptedSha,
          preferredFileName: 'untrusted_file',
        ),
        throwsA(isA<CryptographicIntegrityException>()),
      );

      // Verify no file was written to disk
      final exists = await storageAdapter.fileExists('/sandboxed/zerosync_vault/untrusted_file.txt');
      expect(exists, isFalse);
    });
  });
}
