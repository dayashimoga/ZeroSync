import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/luby_transform_fec_service.dart';

void main() {
  const service = LubyTransformFecService();

  group('DeterministicPrng Specs', () {
    test('Produces identical sequences from the same seed', () {
      final prng1 = DeterministicPrng(12345);
      final prng2 = DeterministicPrng(12345);

      final seq1 = List<int>.generate(10, (_) => prng1.nextUint32());
      final seq2 = List<int>.generate(10, (_) => prng2.nextUint32());

      expect(seq1, equals(seq2));
    });

    test('Different seeds produce divergent sequences', () {
      final prng1 = DeterministicPrng(1111);
      final prng2 = DeterministicPrng(2222);

      final val1 = prng1.nextUint32();
      final val2 = prng2.nextUint32();

      expect(val1, isNot(equals(val2)));
    });

    test('nextInt generates integers strictly within [0, max - 1]', () {
      final prng = DeterministicPrng(999);
      for (var i = 0; i < 50; i++) {
        final val = prng.nextInt(7);
        expect(val, greaterThanOrEqualTo(0));
        expect(val, lessThan(7));
      }
    });
  });

  group('Robust Soliton Distribution Specs', () {
    test('K=1 always generates degree 1 and index 0', () {
      final soliton = RobustSolitonDistribution(1);
      final prng = DeterministicPrng(42);

      expect(soliton.sampleDegree(prng), equals(1));
      expect(soliton.sampleIndices(1, prng), equals([0]));
    });

    test('K > 1 samples degree in range [1, K] and distinct sorted indices',
        () {
      final soliton = RobustSolitonDistribution(10);
      final prng = DeterministicPrng(100);

      for (var i = 0; i < 25; i++) {
        final degree = soliton.sampleDegree(prng);
        expect(degree, greaterThanOrEqualTo(1));
        expect(degree, lessThanOrEqualTo(10));

        final indices = soliton.sampleIndices(degree, prng);
        expect(indices.length, equals(degree));
        // Verify distinctness and sort order
        for (var j = 0; j < indices.length; j++) {
          expect(indices[j], greaterThanOrEqualTo(0));
          expect(indices[j], lessThan(10));
          if (j > 0) {
            expect(indices[j], greaterThan(indices[j - 1]));
          }
        }
      }
    });
  });

  group('FountainDroplet Wire Serialization Specs', () {
    test(
        'Serializes to 12-byte header + data and reconstructs identical droplet',
        () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      final droplet = FountainDroplet(
        seed: 777,
        totalSourceBlocks: 4,
        symbolSize: 4,
        originalPayloadLength: 14,
        sourceIndices: const [0, 2],
        data: data,
      );

      final wireBytes = droplet.toWireBytes();
      expect(wireBytes.length, equals(12 + 4));

      final restored = FountainDroplet.fromWireBytes(wireBytes);
      expect(restored.seed, 777);
      expect(restored.totalSourceBlocks, 4);
      expect(restored.symbolSize, 4);
      expect(restored.originalPayloadLength, 14);
      expect(restored.data, equals(data));
      // Reconstructed deterministic indices
      expect(restored.sourceIndices, isNotEmpty);
    });

    test('Throws FormatException on datagram shorter than header size', () {
      expect(
        () => FountainDroplet.fromWireBytes(Uint8List(11)),
        throwsA(isA<FormatException>()),
      );
    });

    test('Throws FormatException on symbol size mismatch', () {
      final data = Uint8List(14); // 12 header + 2 data, but symbolSize=4
      final view = ByteData.sublistView(data);
      view.setUint16(6, 4, Endian.big); // symbolSize = 4

      expect(
        () => FountainDroplet.fromWireBytes(data),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Partitioning & Single-Block Payload Specs', () {
    test('Partitions payload into uniform source blocks with zero-padding', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final blocks = service.partitionSourceBlocks(payload, symbolSize: 3);

      expect(blocks.length, equals(2));
      expect(blocks[0], equals(Uint8List.fromList([1, 2, 3])));
      expect(blocks[1], equals(Uint8List.fromList([4, 5, 0]))); // zero padded
    });

    test('Single-block payload (K=1) decodes immediately on the first droplet',
        () {
      final payload = Uint8List.fromList('ZeroSync Air-Gap Fountain'.codeUnits);
      final droplets = service.generateNDroplets(payload, 1, symbolSize: 100);

      expect(droplets.length, equals(1));
      expect(droplets[0].totalSourceBlocks, equals(1));
      expect(droplets[0].degree, equals(1));

      final restored = service.decodeDroplets(droplets);
      expect(restored, equals(payload));
    });
  });

  group('Erasure Recovery & Multi-Block Fountain Decoding', () {
    test('Rebuilds multi-block payload from N + epsilon droplets', () {
      // 5 blocks of size 20 bytes = 100 bytes payload
      final payload = Uint8List(100);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = (i * 3 + 7) % 256;
      }

      // Generate K + 5 droplets (N=5, epsilon=5)
      final droplets = service.generateNDroplets(
        payload,
        15,
        symbolSize: 20,
        startSeed: 42,
      );

      final restored = service.decodeDroplets(droplets);
      expect(restored, equals(payload));
    });

    test('Rebuilds successfully when droplets arrive out of order', () {
      const text =
          'CONFIDENTIAL_KEY_RATELOCK_LUBY_TRANSFORM_STREAMING_TEST_VECTOR';
      final payload = Uint8List.fromList(text.codeUnits);

      final droplets = service.generateNDroplets(
        payload,
        25,
        symbolSize: 16,
        startSeed: 10,
      );

      // Deterministically shuffle droplets
      final rng = Random(99);
      final shuffled = List<FountainDroplet>.from(droplets)..shuffle(rng);

      final restored = service.decodeDroplets(shuffled);
      expect(restored, equals(payload));
    });

    test(
        'Packet Drop Simulation: Recovers payload when 50% of frames are erased',
        () {
      final payload = Uint8List(250);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = i % 256;
      }

      // Generate 50 droplets for K = 250 / 25 = 10 blocks
      final allDroplets = service.generateNDroplets(
        payload,
        50,
        symbolSize: 25,
        startSeed: 500,
      );

      // Simulate optical noise: drop even-indexed droplets (50% packet drop rate)
      final receivedDroplets = <FountainDroplet>[];
      for (var i = 0; i < allDroplets.length; i++) {
        if (i.isOdd) {
          receivedDroplets.add(allDroplets[i]);
        }
      }

      expect(receivedDroplets.length,
          equals(25)); // 25 droplets received for 10 source blocks

      final restored = service.decodeDroplets(receivedDroplets);
      expect(restored, equals(payload));
    });

    test('Incremental decoding tracks progress and detects redundant droplets',
        () {
      final payload =
          Uint8List.fromList('STREAMING_PROGRESS_OBSERVER'.codeUnits);
      final droplets = service.generateNDroplets(
        payload,
        15,
        symbolSize: 10,
        startSeed: 1,
      );

      final decoder = LubyTransformDecoder.fromDroplet(droplets.first);
      expect(decoder.isDecoded, isFalse);
      expect(decoder.progress, 0.0);

      var anyNew = false;
      for (final droplet in droplets) {
        final providedNewInfo = decoder.addDroplet(droplet);
        if (providedNewInfo) anyNew = true;
        if (decoder.isDecoded) break;
      }

      expect(anyNew, isTrue);
      expect(decoder.isDecoded, isTrue);
      expect(decoder.progress, 1.0);
      expect(decoder.solvedBlocksCount, equals(decoder.totalSourceBlocks));
      expect(decoder.getDecodedPayload(), equals(payload));

      // Ingesting duplicate after decoded returns false
      expect(decoder.addDroplet(droplets.first), isFalse);
    });

    test('Throws StateError on insufficient droplets with progress metric', () {
      final payload = Uint8List(500); // K = 25 blocks at 20 bytes each
      // Only supply 1 droplet
      final droplets = service.generateNDroplets(payload, 1, symbolSize: 20);

      expect(
        () => service.decodeDroplets(droplets),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Insufficient droplets'),
        )),
      );
    });
  });
}
