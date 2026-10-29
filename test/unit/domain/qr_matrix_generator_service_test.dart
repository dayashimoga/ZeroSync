import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

void main() {
  late QrMatrixGeneratorService service;

  setUp(() {
    service = QrMatrixGeneratorService();
  });

  group('QR Matrix Dimension & Topology Invariants', () {
    test('Calculates exact ISO/IEC 18004 dimensions for Versions 1 through 40',
        () {
      for (int v = 1; v <= 40; v++) {
        final expectedSize = 17 + 4 * v;
        final matrix = service.initializeEmptyMatrix(
          v,
          QrErrorCorrectionLevel.medium,
        );
        expect(matrix.version, equals(v));
        expect(matrix.size, equals(expectedSize));
      }
    });

    test('Verifies specific dimension milestones: V1, V2, V7, V40', () {
      final v1 = service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.low);
      expect(v1.size, equals(21)); // 21x21

      final v2 =
          service.initializeEmptyMatrix(2, QrErrorCorrectionLevel.medium);
      expect(v2.size, equals(25)); // 25x25

      final v7 =
          service.initializeEmptyMatrix(7, QrErrorCorrectionLevel.quartile);
      expect(v7.size, equals(45)); // 45x45

      final v40 =
          service.initializeEmptyMatrix(40, QrErrorCorrectionLevel.high);
      expect(v40.size, equals(177)); // 177x177
    });

    test('Throws RangeError when version is outside 1..40 range', () {
      expect(
        () => service.initializeEmptyMatrix(0, QrErrorCorrectionLevel.low),
        throwsRangeError,
      );
      expect(
        () => service.initializeEmptyMatrix(41, QrErrorCorrectionLevel.low),
        throwsRangeError,
      );
    });

    test('Validates Finder Pattern structure and isolation', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.low);

      // Verify top-left finder (0,0 to 6,6)
      for (int r = 0; r < 7; r++) {
        for (int c = 0; c < 7; c++) {
          final isBorder = r == 0 || r == 6 || c == 0 || c == 6;
          final isCenter = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          final expectedDark = isBorder || isCenter;
          expect(matrix.getModule(r, c), equals(expectedDark),
              reason: 'Mismatch at ($r, $c)');
          expect(matrix.isFunction(r, c), isTrue);
          expect(matrix.getModuleType(r, c), equals(QrModuleType.finder));
        }
      }

      // Verify separator light borders around top-left finder
      for (int c = 0; c <= 7; c++) {
        expect(matrix.getModule(7, c), isFalse); // horizontal separator
        expect(matrix.isFunction(7, c), isTrue);
        expect(matrix.getModuleType(7, c), equals(QrModuleType.separator));
      }
      for (int r = 0; r <= 7; r++) {
        expect(matrix.getModule(r, 7), isFalse); // vertical separator
        expect(matrix.isFunction(r, 7), isTrue);
        expect(matrix.getModuleType(r, 7), equals(QrModuleType.separator));
      }
    });

    test('Validates Timing Patterns along row 6 and column 6', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      for (int i = 8; i < matrix.size - 8; i++) {
        final expectedDark = (i % 2 == 0);
        expect(matrix.getModule(6, i), equals(expectedDark));
        expect(matrix.getModule(i, 6), equals(expectedDark));
        expect(matrix.getModuleType(6, i), equals(QrModuleType.timing));
        expect(matrix.getModuleType(i, 6), equals(QrModuleType.timing));
      }
    });

    test('Validates permanent dark module at (size - 8, 8)', () {
      for (int v in [1, 2, 7, 20, 40]) {
        final m = service.initializeEmptyMatrix(v, QrErrorCorrectionLevel.high);
        expect(m.getModule(m.size - 8, 8), isTrue);
        expect(m.isFunction(m.size - 8, 8), isTrue);
        expect(m.getModuleType(m.size - 8, 8), equals(QrModuleType.darkModule));
      }
    });

    test('Validates alignment pattern placement in V2 and exclusion in V1', () {
      final v1 = service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.low);
      // V1 has no alignment patterns
      for (int r = 0; r < v1.size; r++) {
        for (int c = 0; c < v1.size; c++) {
          expect(v1.getModuleType(r, c), isNot(equals(QrModuleType.alignment)));
        }
      }

      // V2 has alignment pattern centered at (18, 18)
      final v2 =
          service.initializeEmptyMatrix(2, QrErrorCorrectionLevel.medium);
      expect(
          v2.getModuleType(18, 18), equals(QrModuleType.alignment)); // center
      expect(v2.getModule(18, 18), isTrue); // center is dark
      expect(v2.getModule(18, 17), isFalse); // 1-step ring is light
      expect(v2.getModule(16, 16), isTrue); // 2-step border is dark
    });
  });

  group('ISO/IEC 18004 Format & Version Codeword Mathematical Verification',
      () {
    test('Format info bits match ISO 18004 Table C.1 standard vectors', () {
      // ECC Level L (01)
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.low, QrMaskPattern.pattern000),
        equals(0x77c4),
      );
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.low, QrMaskPattern.pattern101),
        equals(0x6318),
      );

      // ECC Level M (00)
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.medium, QrMaskPattern.pattern000),
        equals(0x5412),
      );
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.medium, QrMaskPattern.pattern111),
        equals(0x4aa0),
      );

      // ECC Level Q (11)
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.quartile, QrMaskPattern.pattern000),
        equals(0x355f),
      );
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.quartile, QrMaskPattern.pattern110),
        equals(0x2eda),
      );

      // ECC Level H (10)
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.high, QrMaskPattern.pattern000),
        equals(0x1689),
      );
      expect(
        QrMatrixGeneratorService.computeFormatBits(
            QrErrorCorrectionLevel.high, QrMaskPattern.pattern100),
        equals(0x0762),
      );
    });

    test('Version info bits match ISO 18004 Table D.1 standard vectors', () {
      expect(QrMatrixGeneratorService.computeVersionBits(6), equals(0)); // < 7
      expect(QrMatrixGeneratorService.computeVersionBits(7), equals(0x07c94));
      expect(QrMatrixGeneratorService.computeVersionBits(8), equals(0x085bc));
      expect(QrMatrixGeneratorService.computeVersionBits(9), equals(0x09a99));
      expect(QrMatrixGeneratorService.computeVersionBits(10), equals(0x0a4d3));
      expect(QrMatrixGeneratorService.computeVersionBits(20), equals(0x149a6));
      expect(QrMatrixGeneratorService.computeVersionBits(40), equals(0x28c69));
    });
  });

  group('ISO/IEC 18004 Penalty Score Evaluations (N1, N2, N3, N4)', () {
    test('N1 Evaluation: penalizes consecutive identical modules >= 5', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);

      // Set a row of 5 consecutive dark modules in an unreserved region (e.g., row 10, cols 8..12)
      for (int c = 8; c < 13; c++) {
        matrix.setModule(10, c, true);
      }

      final n1 = QrPenaltyCalculator.calculateN1(matrix);
      // Row 10 has run of 5 => 3 + (5-5) = 3 points (plus timing patterns and finders)
      expect(n1, greaterThanOrEqualTo(3));
    });

    test('N2 Evaluation: penalizes 2x2 same-color blocks', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);

      // Finder patterns already contain multiple 2x2 blocks
      final n2 = QrPenaltyCalculator.calculateN2(matrix);
      expect(n2, greaterThan(0));
      expect(n2 % 3, equals(0),
          reason: 'N2 must always be an exact multiple of 3');
    });

    test(
        'N3 Evaluation: detects 1:1:3:1:1 finder-like patterns with 4 light guards',
        () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      final initialN3 = QrPenaltyCalculator.calculateN3(matrix);

      // Intentionally craft Pattern A: 1 0 1 1 1 0 1 0 0 0 0 in row 15
      final patternA = [
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        false,
        false,
        false,
        false
      ];
      for (int i = 0; i < 11; i++) {
        matrix.setModule(15, i + 8, patternA[i]);
      }

      final updatedN3 = QrPenaltyCalculator.calculateN3(matrix);
      expect(updatedN3, equals(initialN3 + 40));
    });

    test('N4 Evaluation: evaluates dark/light module ratio deviation', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      final n4 = QrPenaltyCalculator.calculateN4(matrix);
      expect(n4, greaterThanOrEqualTo(0));
      expect(n4 % 10, equals(0),
          reason: 'N4 must always be an exact multiple of 10');
    });

    test('Composite Penalty Calculator computes sum of N1, N2, N3, N4', () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      final score = QrPenaltyCalculator.calculate(matrix);

      expect(
        score.totalScore,
        equals(score.n1Score + score.n2Score + score.n3Score + score.n4Score),
      );
    });
  });

  group('Mask Pattern Engine & Optimal Mask Selection', () {
    test('All 8 mask conditions compute mathematically correct inversion', () {
      // Pattern 0: (r + c) % 2 == 0
      expect(QrMaskPattern.pattern000.shouldInvert(2, 2), isTrue);
      expect(QrMaskPattern.pattern000.shouldInvert(2, 3), isFalse);

      // Pattern 1: r % 2 == 0
      expect(QrMaskPattern.pattern001.shouldInvert(4, 3), isTrue);
      expect(QrMaskPattern.pattern001.shouldInvert(5, 3), isFalse);

      // Pattern 2: c % 3 == 0
      expect(QrMaskPattern.pattern010.shouldInvert(4, 6), isTrue);
      expect(QrMaskPattern.pattern010.shouldInvert(4, 7), isFalse);

      // Pattern 3: (r + c) % 3 == 0
      expect(QrMaskPattern.pattern011.shouldInvert(1, 2), isTrue);
      expect(QrMaskPattern.pattern011.shouldInvert(1, 3), isFalse);

      // Pattern 4: (floor(r/2) + floor(c/3)) % 2 == 0
      expect(QrMaskPattern.pattern100.shouldInvert(0, 0), isTrue);
      expect(QrMaskPattern.pattern100.shouldInvert(2, 0), isFalse);

      // Pattern 5: ((r*c)%2) + ((r*c)%3) == 0
      expect(QrMaskPattern.pattern101.shouldInvert(0, 5), isTrue);
      expect(
          QrMaskPattern.pattern101.shouldInvert(2, 3), isTrue); // (6%2)+(6%3)=0
      expect(QrMaskPattern.pattern101.shouldInvert(1, 2),
          isFalse); // (2%2)+(2%3)=2!=0

      // Pattern 6: (((r*c)%2) + ((r*c)%3)) % 2 == 0
      expect(QrMaskPattern.pattern110.shouldInvert(0, 0), isTrue);
      expect(QrMaskPattern.pattern110.shouldInvert(1, 1),
          isTrue); // (1%2)+(1%3)=2, 2%2==0
      expect(QrMaskPattern.pattern110.shouldInvert(1, 3),
          isFalse); // (3%2)+(3%3)=1, 1%2!=0

      // Pattern 7: (((r+c)%2) + ((r*c)%3)) % 2 == 0
      expect(QrMaskPattern.pattern111.shouldInvert(0, 0), isTrue);
      expect(QrMaskPattern.pattern111.shouldInvert(1, 0),
          isFalse); // (1%2)+(0%3)=1, 1%2!=0
    });

    test('Masking preserves function modules unchanged while toggling data',
        () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      final masked = service.applyMask(
        matrix,
        QrMaskPattern.pattern000,
        QrErrorCorrectionLevel.medium,
      );

      // Verify function modules (e.g. finder pattern) are unmodified
      expect(masked.getModule(0, 0), equals(matrix.getModule(0, 0)));
      expect(masked.getModule(1, 1), equals(matrix.getModule(1, 1)));
      expect(masked.getModule(6, 8), equals(matrix.getModule(6, 8))); // Timing
    });

    test(
        'Optimal Mask Selector evaluates all 8 patterns and picks minimal score',
        () {
      final matrix =
          service.initializeEmptyMatrix(1, QrErrorCorrectionLevel.medium);
      final bestMask =
          service.selectOptimalMask(matrix, QrErrorCorrectionLevel.medium);

      final scores = <QrMaskPattern, int>{};
      for (final mask in QrMaskPattern.values) {
        final applied =
            service.applyMask(matrix, mask, QrErrorCorrectionLevel.medium);
        scores[mask] = QrPenaltyCalculator.calculate(applied).totalScore;
      }

      final minScore =
          scores.values.reduce((curr, next) => curr < next ? curr : next);
      expect(scores[bestMask], equals(minScore));
    });
  });

  group('Version Growth Selection & Payload Density Calculation', () {
    test('Selects minimal version able to hold payload bytes', () {
      expect(
        service.selectOptimalVersion(10, QrErrorCorrectionLevel.medium),
        equals(1),
      );
      expect(
        service.selectOptimalVersion(14, QrErrorCorrectionLevel.medium),
        equals(1),
      );
      // V1 Medium max is 14 bytes; 15 bytes must grow to V2
      expect(
        service.selectOptimalVersion(15, QrErrorCorrectionLevel.medium),
        equals(2),
      );
      // Large payload
      expect(
        service.selectOptimalVersion(250, QrErrorCorrectionLevel.medium),
        equals(11),
      );
    });

    test('Throws ArgumentError if payload exceeds Version 40 maximum capacity',
        () {
      final maxV40Low =
          service.getMaxCapacity(40, QrErrorCorrectionLevel.low); // 2953 bytes
      expect(
        () => service.selectOptimalVersion(
            maxV40Low + 1, QrErrorCorrectionLevel.low),
        throwsArgumentError,
      );
    });

    test('All 40 versions satisfy Total Codewords = Data + EC Codewords', () {
      for (int v = 1; v <= 40; v++) {
        final totalCodewords = service.getTotalCodewords(v);
        for (final ecc in QrErrorCorrectionLevel.values) {
          final data = service.getDataCodewords(v, ecc);
          final ec = service.getEcCodewords(v, ecc);
          expect(
            data + ec,
            equals(totalCodewords),
            reason: 'Codeword conservation violated for V$v Level ${ecc.label}',
          );
        }
      }
    });
  });

  group('End-to-End Matrix Generation Pipeline', () {
    test('Generates valid QR Matrix for ASCII text', () {
      final payload = utf8.encode('AirDrop-QR ZeroSync Air-Gap Protocol');
      final matrix = service.generateMatrix(
        payload: Uint8List.fromList(payload),
        eccLevel: QrErrorCorrectionLevel.medium,
      );

      expect(matrix.version, greaterThanOrEqualTo(2));
      expect(matrix.maskPattern, isNotNull);
      expect(matrix.size, equals(17 + 4 * matrix.version));

      // Visual ASCII representation verification
      final ascii = matrix.toAsciiString();
      expect(ascii.isNotEmpty, isTrue);
      expect(ascii.split('\n').length, equals(matrix.size + 1));
    });

    test('Generates valid QR Matrix across multiple versions (V1, V7, V20)',
        () {
      // Small payload fits in V1
      final v1Payload = Uint8List.fromList(utf8.encode('ZeroSync'));
      final v1Matrix = service.generateMatrix(
        payload: v1Payload,
        eccLevel: QrErrorCorrectionLevel.low,
      );
      expect(v1Matrix.version, equals(1));
      expect(v1Matrix.size, equals(21));

      // Medium payload fitting in V7
      final v7Payload = Uint8List(140);
      for (int i = 0; i < v7Payload.length; i++) {
        v7Payload[i] = i % 256;
      }
      final v7Matrix = service.generateMatrix(
        payload: v7Payload,
        eccLevel: QrErrorCorrectionLevel.low,
      );
      expect(v7Matrix.version, equals(7));
      expect(v7Matrix.size, equals(45));

      // Large payload forcing V20
      final v20Payload = Uint8List(800);
      for (int i = 0; i < v20Payload.length; i++) {
        v20Payload[i] = (i * 7) % 256;
      }
      final v20Matrix = service.generateMatrix(
        payload: v20Payload,
        eccLevel: QrErrorCorrectionLevel.low,
      );
      expect(v20Matrix.version, equals(20));
      expect(v20Matrix.size, equals(97));
    });

    test('Allows fixed version and fixed mask overrides', () {
      final payload = Uint8List.fromList(utf8.encode('Test Override'));
      final matrix = service.generateMatrix(
        payload: payload,
        eccLevel: QrErrorCorrectionLevel.high,
        fixedVersion: 5,
        fixedMask: QrMaskPattern.pattern101,
      );

      expect(matrix.version, equals(5));
      expect(matrix.maskPattern, equals(QrMaskPattern.pattern101));
      expect(matrix.size, equals(37));
    });

    test('Throws ArgumentError if fixedVersion cannot accommodate payload', () {
      final largePayload = Uint8List(100);
      expect(
        () => service.generateMatrix(
          payload: largePayload,
          eccLevel: QrErrorCorrectionLevel.high,
          fixedVersion: 1, // V1 High max is 7 bytes
        ),
        throwsArgumentError,
      );
    });
  });
}
