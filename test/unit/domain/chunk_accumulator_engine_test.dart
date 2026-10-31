import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/chunk_accumulator_engine.dart';
import 'package:airdrop_qr/domain/services/luby_transform_fec_service.dart';
import 'package:airdrop_qr/domain/value_objects/packed_transport_header.dart';
import 'package:airdrop_qr/domain/value_objects/transport_header.dart';

void main() {
  group('ChunkBitSet Zero-Allocation Bitmask Specs', () {
    test('Correctly tracks bit states and rejects out-of-range access', () {
      final bitset = ChunkBitSet(100);

      expect(bitset.contains(0), isFalse);
      expect(bitset.contains(50), isFalse);

      expect(bitset.add(50), isTrue);
      expect(bitset.contains(50), isTrue);

      // Duplicate add returns false
      expect(bitset.add(50), isFalse);

      expect(bitset.contains(0), isFalse);
      expect(bitset.contains(99), isFalse);

      // Boundaries
      expect(() => bitset.add(100), throwsA(isA<RangeError>()));
      expect(() => bitset.add(-1), throwsA(isA<RangeError>()));
      expect(bitset.contains(-1), isFalse);
      expect(bitset.contains(100), isFalse);

      bitset.clear();
      expect(bitset.contains(50), isFalse);
    });
  });

  group('ChunkAccumulatorEngine Ingest & Deduplication Specs', () {
    late ChunkAccumulatorEngine engine;

    setUp(() {
      engine = ChunkAccumulatorEngine();
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('Initializes into idle state with empty snapshot', () {
      expect(engine.state, AccumulatorState.idle);
      expect(engine.receivedCount, 0);
      expect(engine.duplicateCount, 0);
      expect(engine.rejectedCount, 0);
      expect(engine.progress, 0.0);
      expect(engine.isComplete, isFalse);
      expect(engine.getMissingIndices(), isEmpty);
    });

    test('Ingests first frame, initializes session, and tracks progress', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList('Payload split into chunks'.codeUnits),
        sessionId: 0xABCD,
        mimeFlag: MimeTypeFlag.plainText,
        maxChunkSize: 10,
      );

      expect(frames.length, greaterThan(1));

      // Ingest first frame
      final accepted = engine.ingestFrame(frames[0]);
      expect(accepted, isTrue);
      expect(engine.state, AccumulatorState.accumulating);
      expect(engine.activeSessionId, 0xABCD);
      expect(engine.totalChunks, frames.length);
      expect(engine.receivedCount, 1);
      expect(engine.duplicateCount, 0);
      expect(engine.mimeFlag, MimeTypeFlag.plainText);
    });

    test('Deduplicates redundant frames in O(1) without reallocating', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
        sessionId: 111,
        maxChunkSize: 4,
      );

      expect(frames.length, equals(2));

      // Ingest frame 1
      expect(engine.ingestFrame(frames[0]), isTrue);
      expect(engine.receivedCount, 1);
      expect(engine.duplicateCount, 0);

      // Ingest frame 1 duplicate
      expect(engine.ingestFrame(frames[0]), isFalse);
      expect(engine.receivedCount, 1);
      expect(engine.duplicateCount, 1);

      // Ingest frame 1 duplicate again
      expect(engine.ingestFrame(frames[0]), isFalse);
      expect(engine.duplicateCount, 2);
    });

    test('Rejects frames from a mismatched session ID', () {
      final sessionAFrames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([1, 2, 3, 4]),
        sessionId: 0xAAAA,
      );
      final sessionBFrames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([5, 6, 7, 8]),
        sessionId: 0xBBBB,
      );

      // Start session A
      expect(engine.ingestFrame(sessionAFrames[0]), isTrue);

      // Ingest frame from session B
      expect(engine.ingestFrame(sessionBFrames[0]), isFalse);
      expect(engine.rejectedCount, 1);
      expect(engine.receivedCount, 1);
    });

    test('Rejects corrupted frames with invalid CRC32', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([10, 20, 30, 40]),
        sessionId: 555,
      );

      final validFrame = frames[0];
      final corruptedFrame = PackedTransportFrame(
        header: validFrame.header,
        payload: Uint8List.fromList([99, 99, 99]), // Mismatched payload
      );

      expect(corruptedFrame.isValidChecksum, isFalse);
      expect(engine.ingestFrame(corruptedFrame), isFalse);
      expect(engine.rejectedCount, 1);
    });

    test('Ingests raw wire bytes through ingestWireBytes', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList('Wire Datagram Test Vector'.codeUnits),
        sessionId: 999,
        maxChunkSize: 12,
      );

      final wireBytes = frames[0].toWireBytes();
      expect(engine.ingestWireBytes(wireBytes), isTrue);
      expect(engine.receivedCount, 1);

      // Tampered wire bytes rejected
      wireBytes[15] ^= 0xFF;
      expect(engine.ingestWireBytes(wireBytes), isFalse);
      expect(engine.rejectedCount, 1);
    });

    test(
        'Accepts out-of-order frames, tracks missing indices, and reassembles intact payload',
        () {
      final originalData = Uint8List(500);
      for (var i = 0; i < originalData.length; i++) {
        originalData[i] = (i * 7 + 11) % 256;
      }

      final frames = PackedTransportFrame.packPayload(
        rawPayload: originalData,
        sessionId: 777,
        maxChunkSize: 100, // 5 chunks
      );

      expect(frames.length, 5);

      // Ingest out-of-order: [frame 3, frame 5, frame 1]
      expect(engine.ingestFrame(frames[2]), isTrue);
      expect(engine.ingestFrame(frames[4]), isTrue);
      expect(engine.ingestFrame(frames[0]), isTrue);

      expect(engine.receivedCount, 3);
      expect(engine.isComplete, isFalse);
      expect(engine.getMissingIndices(), equals([2, 4]));

      // Cannot assemble while incomplete
      expect(
        () => engine.assembleContiguousPayload(),
        throwsA(isA<StateError>()),
      );

      // Ingest remaining missing frames: [frame 4, frame 2]
      expect(engine.ingestFrame(frames[3]), isTrue);
      expect(engine.getMissingIndices(), equals([2]));

      expect(engine.ingestFrame(frames[1]), isTrue);
      expect(engine.getMissingIndices(), isEmpty);
      expect(engine.receivedCount, 5);
      expect(engine.isComplete, isTrue);
      expect(engine.state, AccumulatorState.completed);

      // Assemble contiguous payload
      final assembled = engine.assembleContiguousPayload();
      expect(assembled, equals(originalData));
    });

    test('Reset clears all state and allows new session to start', () {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([1, 2, 3]),
        sessionId: 10,
      );

      expect(engine.ingestFrame(frames[0]), isTrue);
      expect(engine.isComplete, isTrue);

      engine.reset();
      expect(engine.state, AccumulatorState.idle);
      expect(engine.activeSessionId, isNull);
      expect(engine.receivedCount, 0);

      // New session can now be started
      final newFrames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([4, 5, 6]),
        sessionId: 20,
      );
      expect(engine.ingestFrame(newFrames[0]), isTrue);
      expect(engine.activeSessionId, 20);
    });

    test('Emits snapshots through reactive stateStream', () async {
      final frames = PackedTransportFrame.packPayload(
        rawPayload: Uint8List.fromList([1, 2, 3, 4]),
        sessionId: 44,
        maxChunkSize: 2,
      );

      final snapshots = <AccumulatorSnapshot>[];
      final sub = engine.stateStream.listen(snapshots.add);

      engine.ingestFrame(frames[0]);
      engine.ingestFrame(frames[1]);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(snapshots.length, 2);
      expect(snapshots[0].receivedCount, 1);
      expect(snapshots[1].receivedCount, 2);
      expect(snapshots[1].isComplete, isTrue);
    });

    test(
        'Poisoning Protection: Rejects bit-corrupted TransportFrame before graph insertion',
        () {
      final payload = Uint8List.fromList([10, 20, 30, 40]);
      final validHeader = TransportHeader.createForPayload(
        payload: payload,
        k: 4,
        seed: 123,
      );
      final validFrame = TransportFrame(header: validHeader, payload: payload);

      // Ingest valid frame
      expect(engine.ingestTransportFrame(validFrame), isTrue);
      expect(engine.rejectedCount, 0);

      // Mutate payload bit -> CRC-32C mismatch
      final corruptedPayload = Uint8List.fromList([10, 20, 30, 41]);
      final corruptedFrame =
          TransportFrame(header: validHeader, payload: corruptedPayload);

      expect(engine.ingestTransportFrame(corruptedFrame), isFalse);
      expect(engine.rejectedCount, 1);
    });

    test('Deduplicates identical fountain seeds in O(1)', () {
      final payload = Uint8List.fromList([1, 2, 3, 4]);
      final header = TransportHeader.createForPayload(
        payload: payload,
        k: 2,
        seed: 555,
      );
      final frame = TransportFrame(header: header, payload: payload);

      expect(engine.ingestTransportFrame(frame), isTrue);
      expect(engine.duplicateCount, 0);

      // Duplicate seed
      expect(engine.ingestTransportFrame(frame), isFalse);
      expect(engine.duplicateCount, 1);
    });

    test('Degree distribution telemetry records received degrees', () {
      for (var seed = 1; seed <= 5; seed++) {
        final payload = Uint8List.fromList([seed, seed * 2]);
        final header = TransportHeader.createForPayload(
          payload: payload,
          k: 10,
          seed: seed,
        );
        final frame = TransportFrame(header: header, payload: payload);
        engine.ingestTransportFrame(frame);
      }

      expect(engine.degreeDistribution, isNotEmpty);
      var totalTracked = 0;
      for (final count in engine.degreeDistribution.values) {
        totalTracked += count;
      }
      expect(totalTracked, equals(5));
    });

    test(
        'Early Termination: Terminates immediately once all K blocks are resolved and recovers payload',
        () {
      const fecService = LubyTransformFecService();
      final originalData = Uint8List.fromList(
        List.generate(120, (i) => (i * 3 + 7) & 0xFF),
      );
      const symbolSize = 40; // K = 3 blocks
      final sourceBlocks = fecService.partitionSourceBlocks(originalData,
          symbolSize: symbolSize);
      final k = sourceBlocks.length;
      expect(k, equals(3));

      var seed = 100;
      var acceptedCount = 0;

      while (!engine.isComplete && seed < 300) {
        final droplet = fecService.generateDroplet(
          sourceBlocks: sourceBlocks,
          seed: seed,
          originalPayloadLength: originalData.length,
        );

        final frame = TransportFrame(
          header: TransportHeader.createForPayload(
            payload: droplet.data,
            k: k,
            seed: seed,
            originalPayloadLength: originalData.length,
          ),
          payload: droplet.data,
        );

        if (engine.ingestTransportFrame(frame)) {
          acceptedCount++;
        }
        seed++;
      }

      expect(engine.isComplete, isTrue);
      expect(engine.isEarlyTerminated, isTrue);
      expect(acceptedCount, greaterThanOrEqualTo(k));

      // Extra frames ingested after early termination must be rejected immediately
      final extraDroplet = fecService.generateDroplet(
        sourceBlocks: sourceBlocks,
        seed: 9999,
        originalPayloadLength: originalData.length,
      );
      final extraFrame = TransportFrame(
        header: TransportHeader.createForPayload(
          payload: extraDroplet.data,
          k: k,
          seed: 9999,
          originalPayloadLength: originalData.length,
        ),
        payload: extraDroplet.data,
      );
      expect(engine.ingestTransportFrame(extraFrame), isFalse);

      // Verify intact payload reassembly
      final assembled = engine.assembleContiguousPayload();
      expect(assembled, equals(originalData));
    });

    test(
        'Dual-mode ingestWireBytes automatically identifies 0x5A53 v2 wire datagrams',
        () {
      final payload = Uint8List.fromList([42, 43, 44, 45]);
      final header = TransportHeader.createForPayload(
        payload: payload,
        k: 1,
        seed: 77,
      );
      final frame = TransportFrame(header: header, payload: payload);
      final wireBytes = frame.toWireBytes();

      expect(engine.ingestWireBytes(wireBytes), isTrue);
      expect(engine.isComplete, isTrue);
    });
  });
}
