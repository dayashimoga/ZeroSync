import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/domain/services/binary_file_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BinaryFileManifest & Chunk Serialization Specs', () {
    test('Round-trip manifest JSON serialization', () {
      const manifest = BinaryFileManifest(
        fileName: 'airgap_payload.bin',
        fileSizeBytes: 1024,
        mimeType: 'application/octet-stream',
        sha256Hex: 'abcd1234ef5678',
        chunkIndex: 2,
        totalChunks: 8,
        chunkSize: 128,
      );

      final json = manifest.toJson();
      final restored = BinaryFileManifest.fromJson(json);

      expect(restored, equals(manifest));
    });

    test('Round-trip chunk toWireBytes and fromWireBytes serialization', () {
      const manifest = BinaryFileManifest(
        fileName: 'secrets.tar',
        fileSizeBytes: 512,
        mimeType: 'application/x-tar',
        sha256Hex: 'deadbeef1234',
        chunkIndex: 0,
        totalChunks: 2,
        chunkSize: 256,
      );
      final payload = Uint8List.fromList([10, 20, 30, 40, 50]);
      final chunk = BinaryFileChunk(manifest: manifest, payload: payload);

      final wire = chunk.toWireBytes();
      final restored = BinaryFileChunk.fromWireBytes(wire);

      expect(restored.manifest, equals(manifest));
      expect(restored.payload, equals(payload));
    });

    test('fromWireBytes throws on truncated wire data', () {
      expect(
        () => BinaryFileChunk.fromWireBytes(Uint8List(2)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('BinaryFileChunker Splitting & Reassembly Specs', () {
    test('Splits and reassembles binary file with 100% SHA-256 parity', () {
      final originalData = utf8.encode(
        'ZeroSync Air-Gapped Optical Transfer File Payload for Testing ' * 50,
      );
      final fileBytes = Uint8List.fromList(originalData);

      final chunks = BinaryFileChunker.splitFile(
        fileName: 'airgap_document.txt',
        fileBytes: fileBytes,
        mimeType: 'text/plain',
        chunkSize: 200,
      );

      expect(chunks, isNotEmpty);
      expect(chunks.length, equals((fileBytes.length / 200).ceil()));

      // Reassemble in order
      final assembled = BinaryFileChunker.assembleFile(chunks);
      expect(assembled, equals(fileBytes));

      // Reassemble reversed (out of order)
      final reversedChunks = chunks.reversed.toList();
      final assembledFromReversed =
          BinaryFileChunker.assembleFile(reversedChunks);
      expect(assembledFromReversed, equals(fileBytes));
    });

    test('assembleFile detects bit tampering and throws StateError', () {
      final fileBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final chunks = BinaryFileChunker.splitFile(
        fileName: 'test.dat',
        fileBytes: fileBytes,
        chunkSize: 4,
      );

      // Tamper with second chunk payload
      chunks[1].payload[0] ^= 0xFF;

      expect(
        () => BinaryFileChunker.assembleFile(chunks),
        throwsA(isA<StateError>()),
      );
    });

    test('assembleFile throws StateError on incomplete chunks', () {
      final fileBytes = Uint8List(100);
      final chunks = BinaryFileChunker.splitFile(
        fileName: 'file.bin',
        fileBytes: fileBytes,
        chunkSize: 20,
      );

      // Remove last chunk
      final incomplete = chunks.sublist(0, chunks.length - 1);

      expect(
        () => BinaryFileChunker.assembleFile(incomplete),
        throwsA(isA<StateError>()),
      );
    });

    test('splitFile throws ArgumentError on empty bytes or zero chunkSize', () {
      expect(
        () => BinaryFileChunker.splitFile(
          fileName: 'empty.bin',
          fileBytes: Uint8List(0),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => BinaryFileChunker.splitFile(
          fileName: 'zero.bin',
          fileBytes: Uint8List(10),
          chunkSize: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
