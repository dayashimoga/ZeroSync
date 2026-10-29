import 'dart:math' as math;
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

/// Supported geometric bounding silhouettes for the central embedded logo mask.
enum LogoMaskShape {
  /// Sharp square cutout.
  square,

  /// Circular cutout centered on the matrix.
  circle,

  /// Rounded rectangle cutout with soft corner radii.
  roundedSquare,
}

/// Precise spatial bounds and metadata for a clipped logo region within a QR matrix.
class LogoClippingResult {
  /// Matrix dimension in modules (size = 17 + 4 * version).
  final int matrixSize;

  /// Shape of the clipping mask.
  final LogoMaskShape shape;

  /// Center row coordinate in module space.
  final double centerRow;

  /// Center column coordinate in module space.
  final double centerCol;

  /// Total width of the cutout area in modules (including padding).
  final double widthModules;

  /// Total height of the cutout area in modules (including padding).
  final double heightModules;

  /// Margin of cleared empty space surrounding the logo in module units.
  final double paddingModules;

  /// Total area occupied by the logo cutout divided by total matrix area.
  final double areaCoverageRatio;

  /// Percentage of data modules removed/clipped by the logo mask.
  final double dataModuleLossRatio;

  /// 2D boolean mask indicating which (row, col) cells must be clipped/cleared.
  final List<List<bool>> clipMask;

  /// Total count of modules cleared by the mask.
  final int clippedModuleCount;

  const LogoClippingResult({
    required this.matrixSize,
    required this.shape,
    required this.centerRow,
    required this.centerCol,
    required this.widthModules,
    required this.heightModules,
    required this.paddingModules,
    required this.areaCoverageRatio,
    required this.dataModuleLossRatio,
    required this.clipMask,
    required this.clippedModuleCount,
  });

  /// Evaluates whether the cell at ([row], [col]) is cleared by this mask.
  bool isClipped(int row, int col) {
    if (row < 0 || row >= matrixSize || col < 0 || col >= matrixSize) {
      return false;
    }
    return clipMask[row][col];
  }
}

/// Clean Architecture Domain Service responsible for validating logo sizing invariants,
/// enforcing ISO/IEC 18004 ECC Level H redundancy, and generating auto-clipping masks.
class LogoClippingMaskService {
  /// Maximum permitted area coverage of an embedded logo (< 20.0%).
  /// Exceeding this threshold compromises optical decode contrast and error budget.
  static const double maxLogoAreaRatio = 0.20;

  /// Recommended default logo area coverage ratio (~15%).
  static const double defaultLogoAreaRatio = 0.15;

  /// Computes the optimal clipping mask for a central logo given matrix parameters.
  ///
  /// Invariants Enforced:
  /// 1. [eccLevel] must be [QrErrorCorrectionLevel.high] (30% redundancy).
  /// 2. [logoAreaRatio] must be strictly < 0.20 (< 20% area coverage).
  /// 3. The cutout region must never overlap the 3 finder patterns or their separators.
  LogoClippingResult computeClippingMask({
    required int matrixSize,
    required QrErrorCorrectionLevel eccLevel,
    double logoAreaRatio = defaultLogoAreaRatio,
    LogoMaskShape shape = LogoMaskShape.roundedSquare,
    double paddingModules = 1.0,
  }) {
    // Invariant 1: Enforce ECC Level H
    if (eccLevel != QrErrorCorrectionLevel.high) {
      throw ArgumentError(
        'Embedded logo injection strictly requires ECC Level H (30% redundancy). '
        'Level ${eccLevel.label} (${(eccLevel.recoveryPercentage * 100).toInt()}%) cannot guarantee optical decodability.',
      );
    }

    // Invariant 2: Cap area coverage strictly < 20%
    if (logoAreaRatio <= 0.0 || logoAreaRatio >= maxLogoAreaRatio) {
      throw ArgumentError(
        'Logo area ratio (${(logoAreaRatio * 100).toStringAsFixed(1)}%) must be > 0.0% and < ${(maxLogoAreaRatio * 100).toInt()}.0%.',
      );
    }

    if (paddingModules < 0.0) {
      throw ArgumentError.value(
          paddingModules, 'paddingModules', 'Cannot be negative');
    }

    // Compute central cutout dimension
    // Area ratio = (cutoutSide / matrixSize)^2 => cutoutSide = matrixSize * sqrt(ratio)
    final double rawCutoutSide = matrixSize * math.sqrt(logoAreaRatio);
    final double totalSideWithPadding = rawCutoutSide + (paddingModules * 2.0);

    final double center = (matrixSize - 1) / 2.0;
    final double halfSide = totalSideWithPadding / 2.0;

    final int minRow = (center - halfSide).floor();
    final int maxRow = (center + halfSide).ceil();
    final int minCol = (center - halfSide).floor();
    final int maxCol = (center + halfSide).ceil();

    // Invariant 3: Guard against finder pattern collision
    // Top-left finder: 0..7
    // Top-right finder: (matrixSize - 8)..matrixSize - 1
    // Bottom-left finder: (matrixSize - 8)..matrixSize - 1
    if (minRow <= 7 && minCol <= 7) {
      throw ArgumentError('Logo bounds overlap top-left finder pattern.');
    }
    if (minRow <= 7 && maxCol >= matrixSize - 8) {
      throw ArgumentError('Logo bounds overlap top-right finder pattern.');
    }
    if (maxRow >= matrixSize - 8 && minCol <= 7) {
      throw ArgumentError('Logo bounds overlap bottom-left finder pattern.');
    }

    final mask = List.generate(
      matrixSize,
      (_) => List.filled(matrixSize, false),
    );

    int clippedCount = 0;
    final double radius = halfSide;

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        final double dr = (r - center).abs();
        final double dc = (c - center).abs();

        bool inside = false;
        switch (shape) {
          case LogoMaskShape.square:
            inside = dr <= halfSide && dc <= halfSide;
            break;

          case LogoMaskShape.circle:
            inside = (dr * dr + dc * dc) <= (radius * radius);
            break;

          case LogoMaskShape.roundedSquare:
            final double cornerR = halfSide * 0.35;
            final double straightLimit = halfSide - cornerR;
            if (dr <= straightLimit || dc <= straightLimit) {
              inside = dr <= halfSide && dc <= halfSide;
            } else {
              final double cornerDr = dr - straightLimit;
              final double cornerDc = dc - straightLimit;
              inside = (cornerDr * cornerDr + cornerDc * cornerDc) <=
                  (cornerR * cornerR);
            }
            break;
        }

        if (inside) {
          mask[r][c] = true;
          clippedCount++;
        }
      }
    }

    final int totalModules = matrixSize * matrixSize;
    final double actualAreaRatio = clippedCount / totalModules;

    // Estimate data module loss (assuming non-finder cells are predominantly data)
    final double estimatedDataLoss = clippedCount / (totalModules - (3 * 64));

    return LogoClippingResult(
      matrixSize: matrixSize,
      shape: shape,
      centerRow: center,
      centerCol: center,
      widthModules: totalSideWithPadding,
      heightModules: totalSideWithPadding,
      paddingModules: paddingModules,
      areaCoverageRatio: actualAreaRatio,
      dataModuleLossRatio: estimatedDataLoss,
      clipMask: mask,
      clippedModuleCount: clippedCount,
    );
  }

  /// Applies [clippingResult] to [matrix] by resetting all clipped cells to false (light),
  /// preventing dark modules from rendering beneath or bleeding through transparent logos.
  QrMatrix applyLogoClipping(
      QrMatrix matrix, LogoClippingResult clippingResult) {
    if (matrix.size != clippingResult.matrixSize) {
      throw ArgumentError(
        'Matrix size (${matrix.size}) does not match clipping mask size (${clippingResult.matrixSize}).',
      );
    }

    final cloned = matrix.clone();
    final size = matrix.size;

    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (clippingResult.isClipped(r, c)) {
          // Clear module so it does not render under transparent logo pixels
          cloned.setModule(r, c, false, type: QrModuleType.quietZone);
        }
      }
    }

    return cloned;
  }
}
