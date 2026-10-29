import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/logo_clipping_mask_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

void main() {
  late LogoClippingMaskService logoService;
  late QrMatrixGeneratorService matrixService;

  setUp(() {
    logoService = LogoClippingMaskService();
    matrixService = QrMatrixGeneratorService();
  });

  group('Logo Clipping Invariant Verification', () {
    test('Throws ArgumentError if ECC Level is not High (30% redundancy)', () {
      for (final nonHigh in [
        QrErrorCorrectionLevel.low,
        QrErrorCorrectionLevel.medium,
        QrErrorCorrectionLevel.quartile,
      ]) {
        expect(
          () => logoService.computeClippingMask(
            matrixSize: 37,
            eccLevel: nonHigh,
          ),
          throwsArgumentError,
        );
      }
    });

    test('Throws ArgumentError if logo coverage ratio >= 20%', () {
      expect(
        () => logoService.computeClippingMask(
          matrixSize: 37,
          eccLevel: QrErrorCorrectionLevel.high,
          logoAreaRatio: 0.20,
        ),
        throwsArgumentError,
      );

      expect(
        () => logoService.computeClippingMask(
          matrixSize: 37,
          eccLevel: QrErrorCorrectionLevel.high,
          logoAreaRatio: 0.25,
        ),
        throwsArgumentError,
      );
    });

    test('Throws ArgumentError if logo coverage ratio <= 0.0', () {
      expect(
        () => logoService.computeClippingMask(
          matrixSize: 37,
          eccLevel: QrErrorCorrectionLevel.high,
          logoAreaRatio: 0.0,
        ),
        throwsArgumentError,
      );
      expect(
        () => logoService.computeClippingMask(
          matrixSize: 37,
          eccLevel: QrErrorCorrectionLevel.high,
          logoAreaRatio: -0.1,
        ),
        throwsArgumentError,
      );
    });

    test('Accepts valid logo coverage < 20% with ECC Level High', () {
      final result = logoService.computeClippingMask(
        matrixSize: 45, // V7
        eccLevel: QrErrorCorrectionLevel.high,
        logoAreaRatio: 0.15,
      );

      expect(result.matrixSize, equals(45));
      expect(result.areaCoverageRatio, lessThan(0.20));
      expect(result.clippedModuleCount, greaterThan(0));
    });
  });

  group('Logo Mask Geometries (Square, Circle, RoundedSquare)', () {
    test('Square mask clears symmetric central box', () {
      final result = logoService.computeClippingMask(
        matrixSize: 45,
        eccLevel: QrErrorCorrectionLevel.high,
        shape: LogoMaskShape.square,
        logoAreaRatio: 0.10,
        paddingModules: 0.0,
      );

      const center = 22; // 0..44 center is 22
      expect(result.isClipped(center, center), isTrue);

      // Verify corners of the matrix are NOT clipped
      expect(result.isClipped(0, 0), isFalse);
      expect(result.isClipped(0, 44), isFalse);
      expect(result.isClipped(44, 0), isFalse);
      expect(result.isClipped(44, 44), isFalse);
    });

    test('Circle mask clears circular disc around center', () {
      final result = logoService.computeClippingMask(
        matrixSize: 57, // V10
        eccLevel: QrErrorCorrectionLevel.high,
        shape: LogoMaskShape.circle,
        logoAreaRatio: 0.12,
        paddingModules: 0.0,
      );

      const center = 28; // 0..56 center is 28
      expect(result.isClipped(center, center), isTrue);
      expect(result.isClipped(center, center + 4), isTrue);

      // Distant cells outside circle must be false
      expect(result.isClipped(0, 0), isFalse);
      expect(result.isClipped(28, 0), isFalse);
    });

    test('Rounded square mask computes smooth corner transitions', () {
      final result = logoService.computeClippingMask(
        matrixSize: 45,
        eccLevel: QrErrorCorrectionLevel.high,
        shape: LogoMaskShape.roundedSquare,
        logoAreaRatio: 0.14,
      );

      const center = 22;
      expect(result.isClipped(center, center), isTrue);
      expect(result.clippedModuleCount, greaterThan(0));
    });
  });

  group('Matrix Application & Clearance', () {
    test('applyLogoClipping clears modules to false under logo silhouette', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final matrix = matrixService.generateMatrix(
        payload: payload,
        eccLevel: QrErrorCorrectionLevel.high,
        fixedVersion: 7, // 45x45
      );

      final mask = logoService.computeClippingMask(
        matrixSize: matrix.size,
        eccLevel: QrErrorCorrectionLevel.high,
        logoAreaRatio: 0.12,
      );

      final clippedMatrix = logoService.applyLogoClipping(matrix, mask);

      // All clipped cells must now be false (light) and marked quietZone
      for (int r = 0; r < matrix.size; r++) {
        for (int c = 0; c < matrix.size; c++) {
          if (mask.isClipped(r, c)) {
            expect(clippedMatrix.getModule(r, c), isFalse,
                reason: 'Module ($r, $c) was not cleared by mask');
            expect(clippedMatrix.getModuleType(r, c),
                equals(QrModuleType.quietZone));
          } else {
            // Unclipped cells retain original state
            expect(
                clippedMatrix.getModule(r, c), equals(matrix.getModule(r, c)));
          }
        }
      }
    });

    test('Throws ArgumentError on matrix size mismatch', () {
      final v1Matrix = matrixService.initializeEmptyMatrix(
        1,
        QrErrorCorrectionLevel.high,
      );
      final maskForV7 = logoService.computeClippingMask(
        matrixSize: 45, // V7
        eccLevel: QrErrorCorrectionLevel.high,
      );

      expect(
        () => logoService.applyLogoClipping(v1Matrix, maskForV7),
        throwsArgumentError,
      );
    });
  });
}
