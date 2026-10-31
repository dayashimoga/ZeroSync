import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// Metadata manifest accompanying an air-gapped binary file transfer chunk.
class BinaryFileManifest extends Equatable {
  final String fileName;
  final int fileSizeBytes;
  final String mimeType;
  final String sha256Hex;
  final int chunkIndex;
  final int totalChunks;
  final int chunkSize;

  const BinaryFileManifest({
    required this.fileName,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.sha256Hex,
    required this.chunkIndex,
    required this.totalChunks,
    required this.chunkSize,
  });

  Map<String, dynamic> toMap() => {
        'file_name': fileName,
        'file_size': fileSizeBytes,
        'mime_type': mimeType,
        'sha256': sha256Hex,
        'chunk_index': chunkIndex,
        'total_chunks': totalChunks,
        'chunk_size': chunkSize,
      };

  factory BinaryFileManifest.fromMap(Map<String, dynamic> map) {
    return BinaryFileManifest(
      fileName: map['file_name'] as String,
      fileSizeBytes: map['file_size'] as int,
      mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
      sha256Hex: map['sha256'] as String,
      chunkIndex: map['chunk_index'] as int,
      totalChunks: map['total_chunks'] as int,
      chunkSize: map['chunk_size'] as int,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory BinaryFileManifest.fromJson(String source) =>
      BinaryFileManifest.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  List<Object?> get props => [
        fileName,
        fileSizeBytes,
        mimeType,
        sha256Hex,
        chunkIndex,
        totalChunks,
        chunkSize,
      ];
}

/// An individual transmission slice of a binary file with embedded manifest metadata.
class BinaryFileChunk extends Equatable {
  final BinaryFileManifest manifest;
  final Uint8List payload;

  const BinaryFileChunk({
    required this.manifest,
    required this.payload,
  });

  /// Serializes chunk to a self-contained transport wire format:
  /// [4 bytes: manifest JSON length] + [manifest JSON UTF-8] + [payload bytes].
  Uint8List toWireBytes() {
    final manifestBytes = utf8.encode(manifest.toJson());
    final result = Uint8List(4 + manifestBytes.length + payload.length);
    final bdata = ByteData.sublistView(result);
    bdata.setUint32(0, manifestBytes.length, Endian.big);
    result.setRange(4, 4 + manifestBytes.length, manifestBytes);
    result.setRange(4 + manifestBytes.length, result.length, payload);
    return result;
  }

  /// Deserializes a [BinaryFileChunk] from its wire format.
  factory BinaryFileChunk.fromWireBytes(Uint8List wire) {
    if (wire.length < 4) {
      throw const FormatException('Wire bytes too short for header length');
    }
    final bdata = ByteData.sublistView(wire);
    final manifestLen = bdata.getUint32(0, Endian.big);
    if (wire.length < 4 + manifestLen) {
      throw const FormatException('Wire bytes truncated for manifest JSON');
    }

    final manifestBytes = wire.sublist(4, 4 + manifestLen);
    final manifestJson = utf8.decode(manifestBytes);
    final manifest = BinaryFileManifest.fromJson(manifestJson);
    final payload = wire.sublist(4 + manifestLen);

    return BinaryFileChunk(manifest: manifest, payload: payload);
  }

  @override
  List<Object?> get props => [manifest, payload];
}

/// Service providing slicing of arbitrary binary files into self-contained optical chunks
/// and tamper-evident reassembly validated by cryptographic SHA-256 hashes.
class BinaryFileChunker {
  /// Default chunk size in bytes tailored for standard QR optical transfer blocks.
  static const int defaultChunkSize = 512;

  /// Splits [fileBytes] into a series of [BinaryFileChunk] instances.
  static List<BinaryFileChunk> splitFile({
    required String fileName,
    required Uint8List fileBytes,
    String mimeType = 'application/octet-stream',
    int chunkSize = defaultChunkSize,
  }) {
    if (fileBytes.isEmpty) {
      throw ArgumentError('fileBytes cannot be empty');
    }
    if (chunkSize <= 0) {
      throw ArgumentError('chunkSize must be strictly positive');
    }

    final sha256Hex = sha256.convert(fileBytes).toString();
    final totalChunks = (fileBytes.length / chunkSize).ceil();
    final chunks = <BinaryFileChunk>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = min(start + chunkSize, fileBytes.length);
      final slice = fileBytes.sublist(start, end);

      final manifest = BinaryFileManifest(
        fileName: fileName,
        fileSizeBytes: fileBytes.length,
        mimeType: mimeType,
        sha256Hex: sha256Hex,
        chunkIndex: i,
        totalChunks: totalChunks,
        chunkSize: chunkSize,
      );

      chunks.add(BinaryFileChunk(manifest: manifest, payload: slice));
    }

    return chunks;
  }

  /// Reassembles a complete file from an unordered collection of [chunks],
  /// strictly validating SHA-256 integrity against the expected manifest hash.
  static Uint8List assembleFile(
    List<BinaryFileChunk> chunks, {
    String? expectedSha256Hex,
  }) {
    if (chunks.isEmpty) {
      throw ArgumentError('Chunks list cannot be empty');
    }

    final first = chunks.first.manifest;
    final totalChunks = first.totalChunks;
    final sha256Target = expectedSha256Hex ?? first.sha256Hex;
    final fileName = first.fileName;

    final chunkMap = <int, Uint8List>{};
    for (final chunk in chunks) {
      if (chunk.manifest.fileName != fileName) {
        throw ArgumentError(
          'Mismatched filename: expected $fileName but found ${chunk.manifest.fileName}',
        );
      }
      if (chunk.manifest.sha256Hex != sha256Target) {
        throw ArgumentError('Mismatched SHA-256 hash in chunk manifest');
      }
      chunkMap[chunk.manifest.chunkIndex] = chunk.payload;
    }

    if (chunkMap.length < totalChunks) {
      throw StateError(
        'Incomplete file transfer: received ${chunkMap.length} of $totalChunks chunks',
      );
    }

    final totalBytes = first.fileSizeBytes;
    final assembled = Uint8List(totalBytes);
    var offset = 0;

    for (int i = 0; i < totalChunks; i++) {
      final slice = chunkMap[i];
      if (slice == null) {
        throw StateError('Missing chunk index $i in transfer collection');
      }
      assembled.setRange(offset, offset + slice.length, slice);
      offset += slice.length;
    }

    // Verify SHA-256 integrity
    final computedHash = sha256.convert(assembled).toString();
    if (computedHash != sha256Target) {
      throw StateError(
        'Tamper detection violation: Reassembled file hash ($computedHash) does not match target ($sha256Target)',
      );
    }

    return assembled;
  }
}
