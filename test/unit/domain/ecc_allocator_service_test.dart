import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/ecc_allocator_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

void main() {
  late EccAllocatorService eccService;

  setUp(() {
    eccService = EccAllocatorService();
  });

  group('Galois Field GF(2^8) Arithmetic Invariants', () {
    test('Multiplication satisfies field axioms', () {
      // Identity
      for (int i = 0; i < 256; i++) {
        expect(EccAllocatorService.gfMul(i, 1), equals(i));
        expect(EccAllocatorService.gfMul(i, 0), equals(0));
      }

      // Commutativity
      expect(
        EccAllocatorService.gfMul(137, 42),
        equals(EccAllocatorService.gfMul(42, 137)),
      );

      // Known GF(2^8) reduction vector
      // 0x02 is alpha (x). Multiplying 0x80 (x^7) by 0x02 produces x^8,
      // which reduces modulo 0x11D to 0x1D (29).
      expect(EccAllocatorService.gfMul(0x80, 0x02), equals(0x1D));
    });

    test('Division is inverse of multiplication in GF(2^8)', () {
      for (int a in [1, 2, 7, 42, 128, 255]) {
        for (int b in [1, 3, 19, 73, 200, 255]) {
          final prod = EccAllocatorService.gfMul(a, b);
          final quotient = EccAllocatorService.gfDiv(prod, b);
          expect(quotient, equals(a),
              reason: 'Division failed for ($a * $b) / $b');
        }
      }
    });

    test('Throws ArgumentError on division by zero', () {
      expect(() => EccAllocatorService.gfDiv(42, 0), throwsArgumentError);
    });

    test('Generator polynomial of degree N produces N+1 coefficients', () {
      for (int n in [7, 10, 13, 17, 28, 30]) {
        final poly = EccAllocatorService.getGeneratorPolynomial(n);
        expect(poly.length, equals(n + 1));
        expect(poly.first, equals(1)); // Leading coefficient is always monic 1
      }
    });
  });

  group('Reed-Solomon Codeword Generation & Syndrome Verification', () {
    test('Calculates parity codewords and passes syndrome validation', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x0C, 0x56, 0x61, 0x80]);
      const ecCount = 10;

      final parity = eccService.computeErrorCorrectionCodewords(data, ecCount);
      expect(parity.length, equals(ecCount));

      // Untouched data + parity must have zero syndromes
      final isValid = eccService.verifyCodewords(data, parity);
      expect(isValid, isTrue);

      final combined = Uint8List.fromList([...data, ...parity]);
      final syndromeCount = eccService.evaluateSyndromes(combined, ecCount);
      expect(syndromeCount, equals(0));
    });

    test('Flags bit-flip corruptions during syndrome evaluation', () {
      final data =
          Uint8List.fromList([0x41, 0x69, 0x72, 0x44, 0x72, 0x6F, 0x70]);
      const ecCount = 7;
      final parity = eccService.computeErrorCorrectionCodewords(data, ecCount);

      // Verify clean data first
      expect(eccService.verifyCodewords(data, parity), isTrue);

      // 1. Corrupt data payload byte
      final corruptedData = Uint8List.fromList(data);
      corruptedData[2] ^= 0xFF; // Bit flip
      expect(eccService.verifyCodewords(corruptedData, parity), isFalse);

      // 2. Corrupt parity codeword byte
      final corruptedParity = Uint8List.fromList(parity);
      corruptedParity[0] ^= 0x01;
      expect(eccService.verifyCodewords(data, corruptedParity), isFalse);
    });

    test('Throws ArgumentError when ecCount is <= 0', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(
        () => eccService.computeErrorCorrectionCodewords(data, 0),
        throwsArgumentError,
      );
    });
  });

  group('Dynamic ECC Strategy: Auto-Upgrading', () {
    test(
        'Auto-upgrades ECC from baseline M to H when payload fits in same version',
        () {
      // 5 bytes fits in Version 1 at Level M (max 14 bytes) AND Level H (max 7 bytes).
      // Since it can fit in Level H without increasing Version 1 dimension (21x21),
      // the balanced strategy auto-upgrades to Level H (30% recovery)!
      final result = eccService.allocateEcc(
        payloadLength: 5,
        exportTarget: QrExportTarget.screenDisplay,
        strategy: EccOptimizationStrategy.balanced,
      );

      expect(result.allocatedVersion, equals(1));
      expect(result.matrixDimension, equals(21));
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.high));
      expect(result.isUpgraded, isTrue);
      expect(result.isDowngraded, isFalse);
      expect(result.recoveryPercentage, equals(0.30));
    });

    test(
        'Auto-upgrades to Q when payload fits in Q but not H within same version',
        () {
      // 10 bytes:
      // V1 High max = 7 bytes (does not fit)
      // V1 Quartile max = 11 bytes (fits!)
      // V1 Medium max = 14 bytes (baseline)
      // Therefore, it should auto-upgrade from M to Q while staying at V1!
      final result = eccService.allocateEcc(
        payloadLength: 10,
        baselineLevel: QrErrorCorrectionLevel.medium,
        strategy: EccOptimizationStrategy.balanced,
      );

      expect(result.allocatedVersion, equals(1));
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.quartile));
      expect(result.isUpgraded, isTrue);
      expect(result.isDowngraded, isFalse);
      expect(result.recoveryPercentage, equals(0.25));
    });
  });

  group('Dynamic ECC Strategy: Auto-Downgrading & Version Clamping', () {
    test('Auto-downgrades from H to Q/M/L to satisfy maxVersion constraint',
        () {
      // In airGapStream, maxVersion defaults to 10.
      // At Level H, Version 10 max capacity is 119 bytes.
      // If payload is 140 bytes, Level H requires Version 12 (> 10).
      // Auto-downgrade should reduce ECC level to Quartile (V10 max is 151 bytes),
      // successfully fitting within maxVersion 10!
      final result = eccService.allocateEcc(
        payloadLength: 140,
        exportTarget: QrExportTarget.airGapStream,
        baselineLevel: QrErrorCorrectionLevel.high,
        strategy: EccOptimizationStrategy.balanced,
      );

      expect(result.allocatedVersion, lessThanOrEqualTo(10));
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.quartile));
      expect(result.isDowngraded, isTrue);
      expect(result.isUpgraded, isFalse);
    });

    test(
        'Throws ArgumentError if payload cannot fit within maxVersion even at Level L',
        () {
      // Max Version 2 at Level L max is 32 bytes.
      expect(
        () => eccService.allocateEcc(
          payloadLength: 50,
          maxVersion: 2,
          strategy: EccOptimizationStrategy.balanced,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Specific Optimization Strategies', () {
    test('Strategy maximizeResilience picks highest viable ECC level', () {
      // 100 bytes with maxVersion 10
      final result = eccService.allocateEcc(
        payloadLength: 100,
        maxVersion: 10,
        strategy: EccOptimizationStrategy.maximizeResilience,
      );

      // Level H fits 100 bytes (V9 High max = 98 bytes, V10 High max = 119 bytes -> fits in V10!)
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.high));
      expect(result.allocatedVersion, equals(10));
    });

    test('Strategy minimizeDensity selects lowest possible version dimension',
        () {
      // 15 bytes:
      // In Level L, 15 bytes fits in V1 (max 17 bytes)
      // In Level M, 15 bytes requires V2 (V1 max is 14 bytes)
      // minimizeDensity must choose Level L to keep Version 1 (21x21)
      final result = eccService.allocateEcc(
        payloadLength: 15,
        strategy: EccOptimizationStrategy.minimizeDensity,
      );

      expect(result.allocatedVersion, equals(1));
      expect(result.matrixDimension, equals(21));
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.low));
    });

    test('Strategy fixedLevel preserves requested level strictly', () {
      final result = eccService.allocateEcc(
        payloadLength: 20,
        baselineLevel: QrErrorCorrectionLevel.low,
        strategy: EccOptimizationStrategy.fixedLevel,
      );

      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.low));
      expect(result.isUpgraded, isFalse);
      expect(result.isDowngraded, isFalse);
    });
  });

  group('Export Target Medium Defaults', () {
    test('Damaged environment enforces high ECC baseline', () {
      final result = eccService.allocateEcc(
        payloadLength: 10,
        exportTarget: QrExportTarget.damagedEnvironment,
      );
      expect(result.finalEccLevel, equals(QrErrorCorrectionLevel.high));
      expect(result.recoveryPercentage, equals(0.30));
    });

    test('Print high-density favors quartile baseline', () {
      final result = eccService.allocateEcc(
        payloadLength: 50,
        exportTarget: QrExportTarget.printHighDensity,
      );
      // 50 bytes fits in V3 Quartile or auto-upgraded to H if possible
      expect(result.recoveryPercentage, greaterThanOrEqualTo(0.25));
    });

    test('AirGapStream defaults to maxVersion 10 for camera sensor FPS', () {
      final result = eccService.allocateEcc(
        payloadLength: 200,
        exportTarget: QrExportTarget.airGapStream,
      );
      expect(result.allocatedVersion, lessThanOrEqualTo(10));
    });
  });
}
