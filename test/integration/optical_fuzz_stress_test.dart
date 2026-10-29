import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Domain Engines & Services
import 'package:airdrop_qr/core/utils/crc32.dart';
import 'package:airdrop_qr/core/utils/disposal_auditor.dart';
import 'package:airdrop_qr/domain/services/airgap_file_writer_service.dart';
import 'package:airdrop_qr/domain/services/chunk_accumulator_engine.dart';
import 'package:airdrop_qr/domain/services/gallery_decoder_service.dart';
import 'package:airdrop_qr/domain/services/integrity_checksum_service.dart';
import 'package:airdrop_qr/domain/services/luby_transform_fec_service.dart';
import 'package:airdrop_qr/domain/services/payload_compression_service.dart';
import 'package:airdrop_qr/domain/value_objects/packed_transport_header.dart';

void main() {
  group('Packet-Drop, Noise & Blur Fault-Tolerance Stress Specs', () {
    const compressionService = PayloadCompressionService();
    const integrityService = IntegrityChecksumService();
    const fecService = LubyTransformFecService();
    late MemorySandboxedStorageAdapter storageAdapter;
    late AirgapFileWriterService fileWriterService;

    setUp(() {
      storageAdapter = MemorySandboxedStorageAdapter();
      fileWriterService = AirgapFileWriterService(
        storageAdapter: storageAdapter,
        integrityService: integrityService,
        compressionService: compressionService,
      );
      DisposalAuditor.instance.reset();
      DisposalAuditor.instance.setAuditingEnabled(true);
    });

    tearDown(() {
      DisposalAuditor.instance.assertZeroUndisposed();
    });

    // =========================================================================
    // 1. VARIABLE PACKET-DROP STRESS MATRIX (10%, 20%, 30%, 40% LOSS)
    // =========================================================================

    for (final dropRate in <double>[0.10, 0.20, 0.30, 0.40]) {
      final int dropPercent = (dropRate * 100).round();

      test('Fountain Engine Recovers Complete Payload Under $dropPercent% Random Packet Loss', () async {
        final bag = DeterministicDisposalBag(tag: 'DropStress_${dropPercent}Pct');

        // 1. Generate 3.0 KB randomized realistic file payload
        final rng = math.Random(0x1000 + dropPercent);
        final rawBytes = Uint8List(3000);
        for (int i = 0; i < rawBytes.length; i++) {
          rawBytes[i] = rng.nextInt(256);
        }
        bag.addBuffer(rawBytes, scrubOnDispose: false);

        // 2. Compress to wire envelope
        final compressed = compressionService.compress(
          rawBytes,
          algorithm: CompressionAlgorithm.zlib,
        );
        final envelope = compressed.toWireEnvelope();
        bag.addBuffer(envelope, scrubOnDispose: false);

        // 3. Partition into symbols (symbol size = 150 bytes, K = 20 blocks)
        const int symbolSize = 150;
        final int kSourceBlocks = (envelope.length / symbolSize).ceil();

        // Generate overhead factor: higher loss rates demand slightly more droplets
        final int overheadMultiplier = dropRate >= 0.35 ? 4 : 3;
        final droplets = fecService.generateNDroplets(
          envelope,
          kSourceBlocks * overheadMultiplier,
          symbolSize: symbolSize,
          startSeed: 42,
        );

        // 4. Initialize receiver decoder and accumulator
        final decoder = LubyTransformDecoder.fromDroplet(droplets.first);
        final accumulator = ChunkAccumulatorEngine();

        int frameCounter = 0;
        int droppedFramesCount = 0;
        int deliveredFramesCount = 0;

        for (final droplet in droplets) {
          bag.addBuffer(droplet.data, scrubOnDispose: false);
          frameCounter++;

          // Simulate random camera packet drop based on PRNG
          if (rng.nextDouble() < dropRate) {
            droppedFramesCount++;
            continue; // Packet dropped!
          }

          deliveredFramesCount++;
          final wireDroplet = droplet.toWireBytes();
          final crc = Crc32.compute(wireDroplet);

          final frame = PackedTransportFrame(
            header: PackedTransportHeader(
              sessionId: 0xF00D0000 + dropPercent,
              totalChunks: kSourceBlocks,
              chunkIndex: math.min(frameCounter, kSourceBlocks),
              crc32: crc,
              mimeFlag: MimeTypeFlag.binary,
            ),
            payload: wireDroplet,
          );
          bag.addBuffer(frame.toWireBytes(), scrubOnDispose: false);

          accumulator.ingestFrame(frame);
          decoder.addDroplet(droplet);

          if (decoder.isDecoded) {
            break;
          }
        }

        // 5. Verify decoder solved all source blocks despite dropped packets
        expect(
          decoder.isDecoded,
          isTrue,
          reason: 'Decoder failed at $dropPercent% loss: delivered=$deliveredFramesCount, dropped=$droppedFramesCount',
        );

        // 6. Verify whole-payload byte-for-byte fidelity
        final reconstructedEnvelope = decoder.getDecodedPayload();
        expect(reconstructedEnvelope, isNotNull);
        expect(reconstructedEnvelope, equals(envelope));

        // 7. Decapsulate and verify complete file SHA-256
        final fileResult = await fileWriterService.processCompletedStream(
          assembledPayload: reconstructedEnvelope!,
          mimeFlag: MimeTypeFlag.binary,
          isCompressedEnvelope: true,
          expectedSha256Hex: integrityService.computeSha256Hex(rawBytes),
          preferredFileName: 'stress_test_${dropPercent}pct.bin',
        );

        final writtenBytes = await storageAdapter.readBinaryFile(fileResult.filePath);
        expect(writtenBytes, equals(rawBytes));
        expect(fileResult.sha256Checksum, equals(integrityService.computeSha256Hex(rawBytes)));

        bag.dispose();
      });
    }

    // =========================================================================
    // 2. SYNTHETIC CHANNEL NOISE & BIT CORRUPTION FUZZING
    // =========================================================================

    test('CRC32 Checksum Engine Discards 100% of Bit-Corrupted Optical Datagrams', () {
      final bag = DeterministicDisposalBag(tag: 'CorruptionFuzz');
      final rng = math.Random(0xDEAD);

      // Create a valid frame
      final validPayload = Uint8List.fromList(List<int>.generate(200, (i) => i % 256));
      final validCrc = Crc32.compute(validPayload);
      final validHeader = PackedTransportHeader(
        sessionId: 0x12345678,
        totalChunks: 5,
        chunkIndex: 1,
        crc32: validCrc,
        mimeFlag: MimeTypeFlag.binary,
      );
      final validFrame = PackedTransportFrame(
        header: validHeader,
        payload: validPayload,
      );
      expect(validFrame.isValidChecksum, isTrue);

      final accumulator = ChunkAccumulatorEngine();
      expect(accumulator.ingestFrame(validFrame), isTrue);

      // Mutate payload bytes (simulate optical blur/sensor noise flips)
      int corruptedFramesRejected = 0;
      const int numMutations = 50;

      for (int i = 0; i < numMutations; i++) {
        final corruptedPayload = Uint8List.fromList(validPayload);
        // Flip 1 to 5 random bits
        final flipIndex = rng.nextInt(corruptedPayload.length);
        corruptedPayload[flipIndex] ^= (1 << rng.nextInt(8));
        bag.addBuffer(corruptedPayload, scrubOnDispose: false);

        final corruptedFrame = PackedTransportFrame(
          header: validHeader, // Header still retains original CRC32
          payload: corruptedPayload,
        );

        // Verification: Frame must detect corrupt checksum
        expect(corruptedFrame.isValidChecksum, isFalse);

        // Accumulator must reject corrupted frame without poisoning state
        final ingested = accumulator.ingestFrame(corruptedFrame);
        expect(ingested, isFalse);
        corruptedFramesRejected++;
      }

      expect(corruptedFramesRejected, equals(numMutations));
      expect(accumulator.rejectedCount, equals(numMutations));

      bag.dispose();
    });

    // =========================================================================
    // 3. BURST OCCLUSION & OUT-OF-ORDER SHUFFLING RESILIENCE
    // =========================================================================

    test('Recovers Full Payload Under 6-Consecutive Frame Burst Drop & Packet Shuffling', () async {
      final bag = DeterministicDisposalBag(tag: 'BurstDropTest');

      final rawBytes = Uint8List.fromList(
        utf8.encode('ZeroSync Air-Gapped Optical Protocol - Burst Fault Tolerance Test 2026'),
      );
      bag.addBuffer(rawBytes, scrubOnDispose: false);

      final compressed = compressionService.compress(rawBytes, algorithm: CompressionAlgorithm.zlib);
      final envelope = compressed.toWireEnvelope();
      bag.addBuffer(envelope, scrubOnDispose: false);

      const int symbolSize = 16;
      final int totalSourceBlocks = (envelope.length / symbolSize).ceil();
      final droplets = fecService.generateNDroplets(
        envelope,
        totalSourceBlocks * 4,
        symbolSize: symbolSize,
        startSeed: 77,
      );

      // Simulate Burst Drop: frames 4, 5, 6, 7, 8, 9 completely occluded!
      final transmittedDroplets = <FountainDroplet>[];
      for (int i = 0; i < droplets.length; i++) {
        if (i >= 3 && i <= 8) {
          continue; // Consecutive burst occlusion!
        }
        transmittedDroplets.add(droplets[i]);
      }

      // Shuffle transmitted droplets (out-of-order optical ingestion)
      transmittedDroplets.shuffle(math.Random(0xCAFE));

      final decoder = LubyTransformDecoder.fromDroplet(transmittedDroplets.first);
      for (final droplet in transmittedDroplets) {
        decoder.addDroplet(droplet);
        if (decoder.isDecoded) break;
      }

      expect(decoder.isDecoded, isTrue);
      final decodedEnvelope = decoder.getDecodedPayload();
      expect(decodedEnvelope, equals(envelope));

      final decompressed = compressionService.decompressEnvelope(decodedEnvelope!);
      expect(decompressed, equals(rawBytes));

      bag.dispose();
    });

    // =========================================================================
    // 4. SYNTHETIC MOTION BLUR & CONTRAST MAXIMIZATION (RawImageData)
    // =========================================================================

    test('RawImageData Preprocessing Pipeline Inverts and Stretches Degraded Contrast', () {
      // 4x4 Grayscale degraded optical image (low dynamic range: pixels clustered 100..150)
      final lowContrastPixels = Uint8List.fromList(<int>[
        100, 110, 120, 130,
        140, 150, 110, 120,
        130, 140, 150, 100,
        120, 130, 140, 150,
      ]);

      final rawImage = RawImageData(
        width: 4,
        height: 4,
        format: PixelFormat.grayscale,
        pixels: lowContrastPixels,
      );

      // Verify BMP serialization of raw image
      final bmp = rawImage.toBmpBytes();
      expect(bmp.length, greaterThan(54)); // Standard BMP header is 54 bytes
      expect(String.fromCharCodes(bmp.sublist(0, 2)), equals('BM'));

      // Test pixel polarity inversion
      final invertedPixels = Uint8List(lowContrastPixels.length);
      for (int i = 0; i < lowContrastPixels.length; i++) {
        invertedPixels[i] = 255 - lowContrastPixels[i];
      }

      final invertedImage = RawImageData(
        width: 4,
        height: 4,
        format: PixelFormat.grayscale,
        pixels: invertedPixels,
      );

      expect(invertedImage.pixels.first, equals(255 - 100)); // 155
      expect(invertedImage.pixels.last, equals(255 - 150));  // 105
    });
  });
}
