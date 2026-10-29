import 'dart:typed_data';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

/// Intended optical target or physical medium for the QR code payload.
enum QrExportTarget {
  /// Electronic display (phone-to-phone optical air-gap stream or screen-to-camera).
  /// Balances module density and scanning distance.
  screenDisplay,

  /// High-density small paper prints (stickers, thermal receipts, asset labels).
  /// Vulnerable to wear, dirt, and smudges; prefers higher ECC (Q or H).
  printHighDensity,

  /// Large outdoor signage, billboards, or projection screens.
  /// Scanned from large distances; medium ECC with larger module size is preferred.
  printBillboards,

  /// Hostile, degraded, or rugged environments (dirty lens, low light, glare, military air-gap).
  /// Enforces maximum possible ECC (H 30% recovery).
  damagedEnvironment,

  /// High-speed sequential visual streaming (ZSP-V1 protocol).
  /// Constrains matrix version (e.g. Version <= 10) to optimize camera frame ingestion FPS.
  airGapStream,
}

/// Strategy for selecting error correction level and version matrix size.
enum EccOptimizationStrategy {
  /// Maximizes error correction (H -> Q -> M -> L) within version constraints.
  maximizeResilience,

  /// Minimizes matrix dimensions (L -> M -> Q -> H) to maximize scan distance and speed.
  minimizeDensity,

  /// Balances resilience and size: starts at baseline (M or target-defined)
  /// and automatically upgrades to Q or H if it fits within the same version size.
  balanced,

  /// Enforces a strict, unchanging ECC level without auto-scaling.
  fixedLevel,
}

/// Comprehensive outcome of the dynamic ECC allocation calculation.
class EccAllocationResult {
  /// The selected QR Error Correction Level.
  final QrErrorCorrectionLevel finalEccLevel;

  /// The resulting minimum QR Version (1 to 40).
  final int allocatedVersion;

  /// Grid dimensions in modules (17 + 4 * allocatedVersion).
  final int matrixDimension;

  /// Strategy used for the allocation.
  final EccOptimizationStrategy strategyUsed;

  /// Target export profile evaluated.
  final QrExportTarget exportTarget;

  /// Maximum byte capacity available at [allocatedVersion] and [finalEccLevel].
  final int capacityBytes;

  /// Input payload length in bytes.
  final int payloadBytes;

  /// Leftover capacity margin in bytes (capacityBytes - payloadBytes).
  final int capacityMarginBytes;

  /// True if ECC was upgraded compared to baseline without increasing version.
  final bool isUpgraded;

  /// True if ECC was downgraded to satisfy a maxVersion constraint.
  final bool isDowngraded;

  /// Error recovery capability percentage (e.g., 0.07, 0.15, 0.25, 0.30).
  final double recoveryPercentage;

  const EccAllocationResult({
    required this.finalEccLevel,
    required this.allocatedVersion,
    required this.matrixDimension,
    required this.strategyUsed,
    required this.exportTarget,
    required this.capacityBytes,
    required this.payloadBytes,
    required this.capacityMarginBytes,
    required this.isUpgraded,
    required this.isDowngraded,
    required this.recoveryPercentage,
  });

  @override
  String toString() =>
      'EccAllocationResult(Version: $allocatedVersion (${matrixDimension}x$matrixDimension), '
      'ECC: ${finalEccLevel.label} (${(recoveryPercentage * 100).toInt()}%), '
      'Payload: $payloadBytes/$capacityBytes B, '
      'Upgraded: $isUpgraded, Downgraded: $isDowngraded, Target: ${exportTarget.name})';
}

/// Clean Architecture Domain Service for Reed-Solomon polynomial division,
/// syndrome checking, and dynamic auto-upgrading/downgrading ECC strategies.
class EccAllocatorService {
  final QrMatrixGeneratorService _matrixService;

  EccAllocatorService({QrMatrixGeneratorService? matrixService})
      : _matrixService = matrixService ?? QrMatrixGeneratorService();

  // Galois Field GF(2^8) lookup tables with primitive polynomial 0x11D (285).
  static final List<int> _gfExp = List<int>.filled(512, 0);
  static final List<int> _gfLog = List<int>.filled(256, 0);
  static bool _gfInitialized = false;

  static void _initGf() {
    if (_gfInitialized) return;
    int x = 1;
    for (int i = 0; i < 255; i++) {
      _gfExp[i] = x;
      _gfLog[x] = i;
      x <<= 1;
      if (x >= 256) {
        x ^= 0x11D;
      }
    }
    for (int i = 255; i < 512; i++) {
      _gfExp[i] = _gfExp[i - 255];
    }
    _gfInitialized = true;
  }

  /// Multiplication over Galois Field GF(2^8).
  static int gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    _initGf();
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  /// Division over Galois Field GF(2^8).
  static int gfDiv(int a, int b) {
    if (b == 0) throw ArgumentError('Division by zero in GF(2^8)');
    if (a == 0) return 0;
    _initGf();
    return _gfExp[(_gfLog[a] - _gfLog[b] + 255) % 255];
  }

  /// Evaluates polynomial at [x] in GF(2^8) using Horner's method.
  static int gfPolyEval(List<int> poly, int x) {
    int y = 0;
    for (int i = 0; i < poly.length; i++) {
      y = gfMul(y, x) ^ poly[i];
    }
    return y;
  }

  /// Computes Reed-Solomon generator polynomial for [ecCount] error correction codewords:
  /// g(x) = (x - alpha^0)(x - alpha^1)...(x - alpha^(ecCount-1)).
  static List<int> getGeneratorPolynomial(int ecCount) {
    _initGf();
    List<int> poly = <int>[1];
    for (int i = 0; i < ecCount; i++) {
      final factor = <int>[1, _gfExp[i]];
      final newPoly = List<int>.filled(poly.length + 1, 0);
      for (int j = 0; j < poly.length; j++) {
        for (int k = 0; k < factor.length; k++) {
          newPoly[j + k] ^= gfMul(poly[j], factor[k]);
        }
      }
      poly = newPoly;
    }
    return poly;
  }

  /// Generates [ecCount] Reed-Solomon parity codewords via synthetic polynomial division.
  Uint8List computeErrorCorrectionCodewords(Uint8List data, int ecCount) {
    if (ecCount <= 0) {
      throw ArgumentError.value(ecCount, 'ecCount', 'Must be > 0');
    }
    _initGf();
    final generator = getGeneratorPolynomial(ecCount);
    final msg = List<int>.filled(data.length + ecCount, 0);
    msg.setRange(0, data.length, data);

    for (int i = 0; i < data.length; i++) {
      final lead = msg[i];
      if (lead != 0) {
        for (int j = 0; j < generator.length; j++) {
          msg[i + j] ^= gfMul(lead, generator[j]);
        }
      }
    }

    return Uint8List.fromList(msg.sublist(data.length));
  }

  /// Verifies data and error correction codewords by calculating syndromes.
  /// Returns true if all syndromes are zero (meaning no corruption is detected).
  bool verifyCodewords(Uint8List data, Uint8List ecCodewords) {
    _initGf();
    final combined = List<int>.from(data)..addAll(ecCodewords);
    final ecCount = ecCodewords.length;

    for (int i = 0; i < ecCount; i++) {
      final syndrome = gfPolyEval(combined, _gfExp[i]);
      if (syndrome != 0) {
        return false;
      }
    }
    return true;
  }

  /// Evaluates syndromic integrity and returns count of non-zero syndromes.
  int evaluateSyndromes(Uint8List dataWithEc, int ecCount) {
    _initGf();
    int nonZero = 0;
    for (int i = 0; i < ecCount; i++) {
      if (gfPolyEval(dataWithEc, _gfExp[i]) != 0) {
        nonZero++;
      }
    }
    return nonZero;
  }

  /// Dynamically allocates optimal QR Error Correction Level and Version based on
  /// payload density, physical export profile, and upgrade/downgrade rules.
  EccAllocationResult allocateEcc({
    required int payloadLength,
    QrExportTarget exportTarget = QrExportTarget.screenDisplay,
    EccOptimizationStrategy strategy = EccOptimizationStrategy.balanced,
    int? maxVersion,
    QrErrorCorrectionLevel? baselineLevel,
  }) {
    if (payloadLength < 0) {
      throw ArgumentError.value(
          payloadLength, 'payloadLength', 'Cannot be negative');
    }

    final targetMaxVersion =
        maxVersion ?? (exportTarget == QrExportTarget.airGapStream ? 10 : 40);
    if (targetMaxVersion < 1 || targetMaxVersion > 40) {
      throw RangeError.range(targetMaxVersion, 1, 40, 'maxVersion');
    }

    // Determine target-driven baseline ECC level
    final defaultBaseline = _getBaselineLevelForTarget(exportTarget);
    final effectiveBaseline = baselineLevel ?? defaultBaseline;

    switch (strategy) {
      case EccOptimizationStrategy.fixedLevel:
        return _allocateFixedLevel(
          payloadLength: payloadLength,
          level: effectiveBaseline,
          maxVersion: targetMaxVersion,
          exportTarget: exportTarget,
        );

      case EccOptimizationStrategy.minimizeDensity:
        return _allocateMinimizeDensity(
          payloadLength: payloadLength,
          maxVersion: targetMaxVersion,
          exportTarget: exportTarget,
        );

      case EccOptimizationStrategy.maximizeResilience:
        return _allocateMaximizeResilience(
          payloadLength: payloadLength,
          maxVersion: targetMaxVersion,
          exportTarget: exportTarget,
        );

      case EccOptimizationStrategy.balanced:
        return _allocateBalanced(
          payloadLength: payloadLength,
          baselineLevel: effectiveBaseline,
          maxVersion: targetMaxVersion,
          exportTarget: exportTarget,
        );
    }
  }

  EccAllocationResult _allocateFixedLevel({
    required int payloadLength,
    required QrErrorCorrectionLevel level,
    required int maxVersion,
    required QrExportTarget exportTarget,
  }) {
    final version = _matrixService.selectOptimalVersion(payloadLength, level);
    if (version > maxVersion) {
      throw ArgumentError(
        'Payload ($payloadLength bytes) at fixed ECC ${level.label} requires Version $version, exceeding maximum Version $maxVersion.',
      );
    }
    final cap = _matrixService.getMaxCapacity(version, level);
    return EccAllocationResult(
      finalEccLevel: level,
      allocatedVersion: version,
      matrixDimension: 17 + 4 * version,
      strategyUsed: EccOptimizationStrategy.fixedLevel,
      exportTarget: exportTarget,
      capacityBytes: cap,
      payloadBytes: payloadLength,
      capacityMarginBytes: cap - payloadLength,
      isUpgraded: false,
      isDowngraded: false,
      recoveryPercentage: level.recoveryPercentage,
    );
  }

  EccAllocationResult _allocateMinimizeDensity({
    required int payloadLength,
    required int maxVersion,
    required QrExportTarget exportTarget,
  }) {
    // Search levels starting from L to H to find minimal version
    int bestVersion = 999;
    QrErrorCorrectionLevel bestLevel = QrErrorCorrectionLevel.low;

    for (final level in [
      QrErrorCorrectionLevel.low,
      QrErrorCorrectionLevel.medium,
      QrErrorCorrectionLevel.quartile,
      QrErrorCorrectionLevel.high,
    ]) {
      try {
        final v = _matrixService.selectOptimalVersion(payloadLength, level);
        if (v < bestVersion) {
          bestVersion = v;
          bestLevel = level;
        }
      } catch (_) {
        // Exceeds capacity at this level, continue
      }
    }

    if (bestVersion > maxVersion) {
      throw ArgumentError(
        'Payload ($payloadLength bytes) exceeds capacity for max Version $maxVersion under minimizeDensity strategy.',
      );
    }

    final cap = _matrixService.getMaxCapacity(bestVersion, bestLevel);
    return EccAllocationResult(
      finalEccLevel: bestLevel,
      allocatedVersion: bestVersion,
      matrixDimension: 17 + 4 * bestVersion,
      strategyUsed: EccOptimizationStrategy.minimizeDensity,
      exportTarget: exportTarget,
      capacityBytes: cap,
      payloadBytes: payloadLength,
      capacityMarginBytes: cap - payloadLength,
      isUpgraded: false,
      isDowngraded: false,
      recoveryPercentage: bestLevel.recoveryPercentage,
    );
  }

  EccAllocationResult _allocateMaximizeResilience({
    required int payloadLength,
    required int maxVersion,
    required QrExportTarget exportTarget,
  }) {
    // Priority: H -> Q -> M -> L within maxVersion
    for (final level in [
      QrErrorCorrectionLevel.high,
      QrErrorCorrectionLevel.quartile,
      QrErrorCorrectionLevel.medium,
      QrErrorCorrectionLevel.low,
    ]) {
      try {
        final v = _matrixService.selectOptimalVersion(payloadLength, level);
        if (v <= maxVersion) {
          final cap = _matrixService.getMaxCapacity(v, level);
          return EccAllocationResult(
            finalEccLevel: level,
            allocatedVersion: v,
            matrixDimension: 17 + 4 * v,
            strategyUsed: EccOptimizationStrategy.maximizeResilience,
            exportTarget: exportTarget,
            capacityBytes: cap,
            payloadBytes: payloadLength,
            capacityMarginBytes: cap - payloadLength,
            isUpgraded: level != QrErrorCorrectionLevel.medium,
            isDowngraded: false,
            recoveryPercentage: level.recoveryPercentage,
          );
        }
      } catch (_) {
        // Exceeds capacity at this level
      }
    }

    throw ArgumentError(
      'Payload ($payloadLength bytes) cannot fit within max Version $maxVersion even at lowest ECC level L.',
    );
  }

  EccAllocationResult _allocateBalanced({
    required int payloadLength,
    required QrErrorCorrectionLevel baselineLevel,
    required int maxVersion,
    required QrExportTarget exportTarget,
  }) {
    // 1. Check if baseline fits within maxVersion
    int? baselineVersion;
    try {
      final v =
          _matrixService.selectOptimalVersion(payloadLength, baselineLevel);
      if (v <= maxVersion) {
        baselineVersion = v;
      }
    } catch (_) {
      baselineVersion = null;
    }

    // 2. If baseline exceeded maxVersion, auto-downgrade (e.g. H -> Q -> M -> L)
    if (baselineVersion == null) {
      final downgradedLevels = _getDowngradeLevels(baselineLevel);
      for (final lvl in downgradedLevels) {
        try {
          final v = _matrixService.selectOptimalVersion(payloadLength, lvl);
          if (v <= maxVersion) {
            final cap = _matrixService.getMaxCapacity(v, lvl);
            return EccAllocationResult(
              finalEccLevel: lvl,
              allocatedVersion: v,
              matrixDimension: 17 + 4 * v,
              strategyUsed: EccOptimizationStrategy.balanced,
              exportTarget: exportTarget,
              capacityBytes: cap,
              payloadBytes: payloadLength,
              capacityMarginBytes: cap - payloadLength,
              isUpgraded: false,
              isDowngraded: true,
              recoveryPercentage: lvl.recoveryPercentage,
            );
          }
        } catch (_) {
          // Keep searching
        }
      }

      throw ArgumentError(
        'Payload ($payloadLength bytes) exceeds maximum capacity for Version $maxVersion even after auto-downgrading to level L.',
      );
    }

    // 3. Auto-upgrading strategy:
    // If the payload fits in baselineVersion, can we upgrade to a higher ECC level
    // (e.g. M -> Q -> H) WITHOUT increasing the version dimension?
    final upgradeCandidates = _getUpgradeLevels(baselineLevel);
    QrErrorCorrectionLevel selectedLevel = baselineLevel;
    bool isUpgraded = false;

    for (final candidate in upgradeCandidates) {
      final candidateCap =
          _matrixService.getMaxCapacity(baselineVersion, candidate);
      if (payloadLength <= candidateCap) {
        selectedLevel = candidate;
        isUpgraded = true;
      }
    }

    final cap = _matrixService.getMaxCapacity(baselineVersion, selectedLevel);
    return EccAllocationResult(
      finalEccLevel: selectedLevel,
      allocatedVersion: baselineVersion,
      matrixDimension: 17 + 4 * baselineVersion,
      strategyUsed: EccOptimizationStrategy.balanced,
      exportTarget: exportTarget,
      capacityBytes: cap,
      payloadBytes: payloadLength,
      capacityMarginBytes: cap - payloadLength,
      isUpgraded: isUpgraded,
      isDowngraded: false,
      recoveryPercentage: selectedLevel.recoveryPercentage,
    );
  }

  QrErrorCorrectionLevel _getBaselineLevelForTarget(QrExportTarget target) {
    switch (target) {
      case QrExportTarget.screenDisplay:
        return QrErrorCorrectionLevel.medium;
      case QrExportTarget.printHighDensity:
        return QrErrorCorrectionLevel.quartile;
      case QrExportTarget.printBillboards:
        return QrErrorCorrectionLevel.medium;
      case QrExportTarget.damagedEnvironment:
        return QrErrorCorrectionLevel.high;
      case QrExportTarget.airGapStream:
        return QrErrorCorrectionLevel.medium;
    }
  }

  List<QrErrorCorrectionLevel> _getUpgradeLevels(
      QrErrorCorrectionLevel current) {
    switch (current) {
      case QrErrorCorrectionLevel.low:
        return [
          QrErrorCorrectionLevel.medium,
          QrErrorCorrectionLevel.quartile,
          QrErrorCorrectionLevel.high,
        ];
      case QrErrorCorrectionLevel.medium:
        return [
          QrErrorCorrectionLevel.quartile,
          QrErrorCorrectionLevel.high,
        ];
      case QrErrorCorrectionLevel.quartile:
        return [
          QrErrorCorrectionLevel.high,
        ];
      case QrErrorCorrectionLevel.high:
        return [];
    }
  }

  List<QrErrorCorrectionLevel> _getDowngradeLevels(
      QrErrorCorrectionLevel current) {
    switch (current) {
      case QrErrorCorrectionLevel.high:
        return [
          QrErrorCorrectionLevel.quartile,
          QrErrorCorrectionLevel.medium,
          QrErrorCorrectionLevel.low,
        ];
      case QrErrorCorrectionLevel.quartile:
        return [
          QrErrorCorrectionLevel.medium,
          QrErrorCorrectionLevel.low,
        ];
      case QrErrorCorrectionLevel.medium:
        return [
          QrErrorCorrectionLevel.low,
        ];
      case QrErrorCorrectionLevel.low:
        return [];
    }
  }
}
