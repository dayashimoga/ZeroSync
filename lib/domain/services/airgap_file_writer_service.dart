import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../value_objects/packed_transport_header.dart';
import 'integrity_checksum_service.dart';
import 'payload_compression_service.dart';

/// Abstract storage adapter providing sandboxed file I/O abstraction for the domain layer.
abstract class SandboxedStorageAdapter {
  Future<String> writeBinaryFile({
    required String filename,
    required Uint8List bytes,
  });

  Future<Uint8List?> readBinaryFile(String path);

  Future<bool> fileExists(String path);
}

/// In-memory storage adapter for testing and hermetic air-gap verification.
class MemorySandboxedStorageAdapter implements SandboxedStorageAdapter {
  final Map<String, Uint8List> _storage = <String, Uint8List>{};
  final String sandboxRoot;

  MemorySandboxedStorageAdapter(
      {this.sandboxRoot = '/sandboxed/zerosync_vault/'});

  @override
  Future<String> writeBinaryFile({
    required String filename,
    required Uint8List bytes,
  }) async {
    final fullPath = '$sandboxRoot$filename';
    _storage[fullPath] = Uint8List.fromList(bytes);
    return fullPath;
  }

  @override
  Future<Uint8List?> readBinaryFile(String path) async {
    return _storage[path];
  }

  @override
  Future<bool> fileExists(String path) async {
    return _storage.containsKey(path);
  }

  void clear() => _storage.clear();
}

/// Structured outcome of a verified, decompressed air-gap file write operation.
class AirgapFileResult extends Equatable {
  final String filePath;
  final String fileName;
  final String sha256Checksum;
  final int fileSizeBytes;
  final MimeTypeFlag mimeFlag;
  final String mimeType;

  const AirgapFileResult({
    required this.filePath,
    required this.fileName,
    required this.sha256Checksum,
    required this.fileSizeBytes,
    required this.mimeFlag,
    required this.mimeType,
  });

  @override
  List<Object?> get props => [
        filePath,
        fileName,
        sha256Checksum,
        fileSizeBytes,
        mimeFlag,
        mimeType,
      ];
}

/// Domain service orchestrating stream completion triggers:
/// 1. Whole-payload SHA-256 validation against transport signatures.
/// 2. Decompression of wire envelopes or raw payloads.
/// 3. MIME-type based file extension reconstruction and path sanitization.
/// 4. Safe persistent write to sandboxed application storage.
class AirgapFileWriterService {
  final SandboxedStorageAdapter _storageAdapter;
  final IntegrityChecksumService _integrityService;
  final PayloadCompressionService _compressionService;

  const AirgapFileWriterService({
    required SandboxedStorageAdapter storageAdapter,
    IntegrityChecksumService integrityService =
        const IntegrityChecksumService(),
    PayloadCompressionService compressionService =
        const PayloadCompressionService(),
  })  : _storageAdapter = storageAdapter,
        _integrityService = integrityService,
        _compressionService = compressionService;

  /// Resolves the canonical file extension for a given [MimeTypeFlag].
  static String resolveExtensionForMime(MimeTypeFlag flag) {
    switch (flag) {
      case MimeTypeFlag.plainText:
        return '.txt';
      case MimeTypeFlag.json:
        return '.json';
      case MimeTypeFlag.vcard:
        return '.vcf';
      case MimeTypeFlag.wifi:
        return '.conf';
      case MimeTypeFlag.imageJpeg:
        return '.jpg';
      case MimeTypeFlag.imagePng:
        return '.png';
      case MimeTypeFlag.cryptoKey:
        return '.pem';
      case MimeTypeFlag.archiveZip:
        return '.zip';
      case MimeTypeFlag.binary:
        return '.bin';
      case MimeTypeFlag.custom:
        return '.dat';
    }
  }

  /// Sanitizes a file name, removing path traversal sequences and illegal characters.
  static String sanitizeFileName(String rawName) {
    var sanitized = rawName.replaceAll(RegExp(r'[/\\?%*:|"<>]+'), '_');
    sanitized = sanitized.replaceAll('..', '_');
    sanitized = sanitized.replaceAll(RegExp(r'^_+'), '');
    sanitized = sanitized.replaceAll(RegExp(r'^\.+'), '');
    if (sanitized.trim().isEmpty) {
      sanitized = 'zerosync_file';
    }
    return sanitized.trim();
  }

  /// Automates stream completion: verifies cryptographic checksum, decompresses payload,
  /// reconstructs extension, and safely writes to sandboxed storage.
  Future<AirgapFileResult> processCompletedStream({
    required Uint8List assembledPayload,
    required MimeTypeFlag mimeFlag,
    String? expectedSha256Hex,
    String? preferredFileName,
    bool isCompressedEnvelope = false,
  }) async {
    if (assembledPayload.isEmpty) {
      throw ArgumentError('Cannot process empty stream payload');
    }

    // 1. Decompress if flagged as compressed envelope
    final Uint8List rawBytes;
    if (isCompressedEnvelope) {
      rawBytes = _compressionService.decompressEnvelope(assembledPayload);
    } else {
      rawBytes = assembledPayload;
    }

    // 2. Validate whole-payload cryptographic SHA-256
    final actualSha256 = _integrityService.computeSha256Hex(rawBytes);
    if (expectedSha256Hex != null) {
      _integrityService.assertSha256(rawBytes, expectedSha256Hex);
    }

    // 3. Reconstruct filename and extension
    final canonicalExt = resolveExtensionForMime(mimeFlag);
    final String targetFileName;

    if (preferredFileName != null && preferredFileName.trim().isNotEmpty) {
      final sanitized = sanitizeFileName(preferredFileName);
      if (sanitized.toLowerCase().endsWith(canonicalExt)) {
        targetFileName = sanitized;
      } else {
        targetFileName = '$sanitized$canonicalExt';
      }
    } else {
      final shortHash = actualSha256.substring(0, 10);
      targetFileName = 'zerosync_$shortHash$canonicalExt';
    }

    // 4. Safely write to sandboxed storage
    final savedPath = await _storageAdapter.writeBinaryFile(
      filename: targetFileName,
      bytes: rawBytes,
    );

    return AirgapFileResult(
      filePath: savedPath,
      fileName: targetFileName,
      sha256Checksum: actualSha256,
      fileSizeBytes: rawBytes.length,
      mimeFlag: mimeFlag,
      mimeType: mimeFlag.mimeType,
    );
  }
}
