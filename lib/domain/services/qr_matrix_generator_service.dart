import 'dart:math' as math;
import 'dart:typed_data';

/// QR Code Error Correction Level conforming to ISO/IEC 18004.
enum QrErrorCorrectionLevel {
  /// Low error recovery (~7% of codewords can be restored).
  low(formatBits: 0x01, recoveryPercentage: 0.07, label: 'L'),

  /// Medium error recovery (~15% of codewords can be restored).
  medium(formatBits: 0x00, recoveryPercentage: 0.15, label: 'M'),

  /// Quartile error recovery (~25% of codewords can be restored).
  quartile(formatBits: 0x03, recoveryPercentage: 0.25, label: 'Q'),

  /// High error recovery (~30% of codewords can be restored).
  high(formatBits: 0x02, recoveryPercentage: 0.30, label: 'H');

  /// 2-bit indicator placed into the format information string.
  final int formatBits;

  /// Theoretical error recovery percentage.
  final double recoveryPercentage;

  /// Single-letter designation according to ISO/IEC 18004.
  final String label;

  const QrErrorCorrectionLevel({
    required this.formatBits,
    required this.recoveryPercentage,
    required this.label,
  });
}

/// The 8 standard QR Code mask patterns defined by ISO/IEC 18004 Section 6.8.1.
enum QrMaskPattern {
  /// (row + col) % 2 == 0
  pattern000(0),

  /// row % 2 == 0
  pattern001(1),

  /// col % 3 == 0
  pattern010(2),

  /// (row + col) % 3 == 0
  pattern011(3),

  /// (floor(row / 2) + floor(col / 3)) % 2 == 0
  pattern100(4),

  /// ((row * col) % 2) + ((row * col) % 3) == 0
  pattern101(5),

  /// (((row * col) % 2) + ((row * col) % 3)) % 2 == 0
  pattern110(6),

  /// (((row + col) % 2) + ((row * col) % 3)) % 2 == 0
  pattern111(7);

  /// Integer value 0..7 corresponding to the 3-bit mask pattern reference.
  final int value;

  const QrMaskPattern(this.value);

  /// Evaluates whether the module at ([row], [col]) should be inverted.
  bool shouldInvert(int row, int col) {
    switch (value) {
      case 0:
        return (row + col) % 2 == 0;
      case 1:
        return row % 2 == 0;
      case 2:
        return col % 3 == 0;
      case 3:
        return (row + col) % 3 == 0;
      case 4:
        return ((row ~/ 2) + (col ~/ 3)) % 2 == 0;
      case 5:
        return ((row * col) % 2) + ((row * col) % 3) == 0;
      case 6:
        return (((row * col) % 2) + ((row * col) % 3)) % 2 == 0;
      case 7:
        return (((row + col) % 2) + ((row * col) % 3)) % 2 == 0;
      default:
        return false;
    }
  }
}

/// Identifies the role of an individual module within a QR code matrix.
enum QrModuleType {
  /// Regular data or error-correction payload module.
  data,

  /// One of the 3 large finder patterns (top-left, top-right, bottom-left).
  finder,

  /// 1-module light separator border surrounding finder patterns.
  separator,

  /// Alternating timing lines along row 6 and column 6.
  timing,

  /// Small 5x5 alignment squares present in versions >= 2.
  alignment,

  /// Format information bits (15 modules around finders).
  format,

  /// Version information bits (18 modules for versions 7 through 40).
  version,

  /// Mandatory permanent dark module located at (4*version + 9, 8).
  darkModule,

  /// Quiet zone whitespace border.
  quietZone,
}

/// In-memory representation of a QR Code matrix.
class QrMatrix {
  /// QR version (1 to 40).
  final int version;

  /// Error correction level.
  final QrErrorCorrectionLevel errorCorrectionLevel;

  /// Applied mask pattern, or null if unmasked.
  final QrMaskPattern? maskPattern;

  /// Grid dimension in modules (size = 17 + 4 * version).
  final int size;

  final List<List<bool>> _modules;
  final List<List<QrModuleType>> _moduleTypes;
  final List<List<bool>> _isFunction;

  QrMatrix({
    required this.version,
    required this.errorCorrectionLevel,
    this.maskPattern,
  })  : assert(version >= 1 && version <= 40, 'Version must be 1..40'),
        size = 17 + 4 * version,
        _modules = List.generate(
          17 + 4 * version,
          (_) => List.filled(17 + 4 * version, false),
        ),
        _moduleTypes = List.generate(
          17 + 4 * version,
          (_) => List.filled(17 + 4 * version, QrModuleType.data),
        ),
        _isFunction = List.generate(
          17 + 4 * version,
          (_) => List.filled(17 + 4 * version, false),
        );

  QrMatrix._internal({
    required this.version,
    required this.errorCorrectionLevel,
    required this.maskPattern,
    required this.size,
    required List<List<bool>> modules,
    required List<List<QrModuleType>> moduleTypes,
    required List<List<bool>> isFunction,
  })  : _modules = modules,
        _moduleTypes = moduleTypes,
        _isFunction = isFunction;

  /// Returns true if module at ([row], [col]) is dark (true) or light (false).
  bool getModule(int row, int col) {
    _assertBounds(row, col);
    return _modules[row][col];
  }

  /// Sets module state at ([row], [col]) and marks its type.
  void setModule(
    int row,
    int col,
    bool isDark, {
    QrModuleType type = QrModuleType.data,
    bool isFunction = false,
  }) {
    _assertBounds(row, col);
    _modules[row][col] = isDark;
    _moduleTypes[row][col] = type;
    if (isFunction) {
      _isFunction[row][col] = true;
    }
  }

  /// Checks whether module at ([row], [col]) is a function/reserved module.
  bool isFunction(int row, int col) {
    _assertBounds(row, col);
    return _isFunction[row][col];
  }

  /// Returns the architectural classification of module at ([row], [col]).
  QrModuleType getModuleType(int row, int col) {
    _assertBounds(row, col);
    return _moduleTypes[row][col];
  }

  /// Deep clones this matrix.
  QrMatrix clone({QrMaskPattern? newMaskPattern}) {
    final newModules = List.generate(
      size,
      (r) => List<bool>.from(_modules[r]),
    );
    final newTypes = List.generate(
      size,
      (r) => List<QrModuleType>.from(_moduleTypes[r]),
    );
    final newIsFunction = List.generate(
      size,
      (r) => List<bool>.from(_isFunction[r]),
    );

    return QrMatrix._internal(
      version: version,
      errorCorrectionLevel: errorCorrectionLevel,
      maskPattern: newMaskPattern ?? maskPattern,
      size: size,
      modules: newModules,
      moduleTypes: newTypes,
      isFunction: newIsFunction,
    );
  }

  /// Renders visual ASCII representation for debugging and CLI auditing.
  String toAsciiString({String dark = '██', String light = '  '}) {
    final sb = StringBuffer();
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        sb.write(_modules[r][c] ? dark : light);
      }
      sb.writeln();
    }
    return sb.toString();
  }

  void _assertBounds(int r, int c) {
    if (r < 0 || r >= size || c < 0 || c >= size) {
      throw RangeError('Coordinates ($r, $c) out of bounds for size $size');
    }
  }
}

/// Encapsulates the 4 ISO/IEC 18004 penalty metrics and composite score.
class QrPenaltyScore {
  /// Penalty for runs of 5 or more identical-color modules (horizontal + vertical).
  final int n1Score;

  /// Penalty for 2x2 blocks of identical-color modules.
  final int n2Score;

  /// Penalty for 1:1:3:1:1 finder-like patterns with 4 light guards.
  final int n3Score;

  /// Penalty for proportion of dark modules deviating from 50%.
  final int n4Score;

  /// Aggregate total penalty score: N1 + N2 + N3 + N4.
  final int totalScore;

  const QrPenaltyScore({
    required this.n1Score,
    required this.n2Score,
    required this.n3Score,
    required this.n4Score,
    required this.totalScore,
  });

  @override
  String toString() =>
      'QrPenaltyScore(N1: $n1Score, N2: $n2Score, N3: $n3Score, N4: $n4Score, Total: $totalScore)';
}

/// Evaluator implementing ISO/IEC 18004 Section 6.8.2 penalty rules.
class QrPenaltyCalculator {
  /// Computes the complete penalty breakdown for [matrix].
  static QrPenaltyScore calculate(QrMatrix matrix) {
    final n1 = calculateN1(matrix);
    final n2 = calculateN2(matrix);
    final n3 = calculateN3(matrix);
    final n4 = calculateN4(matrix);
    return QrPenaltyScore(
      n1Score: n1,
      n2Score: n2,
      n3Score: n3,
      n4Score: n4,
      totalScore: n1 + n2 + n3 + n4,
    );
  }

  /// N1: Adjacent modules in row/column in same color.
  /// For every run of 5 or more consecutive modules of the same color,
  /// penalty is 3 + (runLength - 5) points.
  static int calculateN1(QrMatrix matrix) {
    int penalty = 0;
    final size = matrix.size;

    // Horizontal scan
    for (int r = 0; r < size; r++) {
      int runLen = 0;
      bool lastColor = false;
      for (int c = 0; c < size; c++) {
        final color = matrix.getModule(r, c);
        if (c == 0) {
          lastColor = color;
          runLen = 1;
        } else if (color == lastColor) {
          runLen++;
        } else {
          if (runLen >= 5) {
            penalty += 3 + (runLen - 5);
          }
          lastColor = color;
          runLen = 1;
        }
      }
      if (runLen >= 5) {
        penalty += 3 + (runLen - 5);
      }
    }

    // Vertical scan
    for (int c = 0; c < size; c++) {
      int runLen = 0;
      bool lastColor = false;
      for (int r = 0; r < size; r++) {
        final color = matrix.getModule(r, c);
        if (r == 0) {
          lastColor = color;
          runLen = 1;
        } else if (color == lastColor) {
          runLen++;
        } else {
          if (runLen >= 5) {
            penalty += 3 + (runLen - 5);
          }
          lastColor = color;
          runLen = 1;
        }
      }
      if (runLen >= 5) {
        penalty += 3 + (runLen - 5);
      }
    }

    return penalty;
  }

  /// N2: Block of modules in same color (2x2 blocks).
  /// 3 points for each 2x2 same-color block found. Overlapping blocks count.
  static int calculateN2(QrMatrix matrix) {
    int penalty = 0;
    final size = matrix.size;
    for (int r = 0; r < size - 1; r++) {
      for (int c = 0; c < size - 1; c++) {
        final m = matrix.getModule(r, c);
        if (matrix.getModule(r, c + 1) == m &&
            matrix.getModule(r + 1, c) == m &&
            matrix.getModule(r + 1, c + 1) == m) {
          penalty += 3;
        }
      }
    }
    return penalty;
  }

  /// N3: 1:1:3:1:1 ratio patterns (finder-like) with 4 light modules on either side:
  /// Pattern A: 1 0 1 1 1 0 1 0 0 0 0
  /// Pattern B: 0 0 0 0 1 0 1 1 1 0 1
  /// 40 points for each match.
  static int calculateN3(QrMatrix matrix) {
    int matches = 0;
    final size = matrix.size;

    // Horizontal scan
    for (int r = 0; r < size; r++) {
      for (int c = 0; c <= size - 11; c++) {
        if (_isN3Pattern(matrix, r, c, isHorizontal: true)) {
          matches++;
        }
      }
    }

    // Vertical scan
    for (int c = 0; c < size; c++) {
      for (int r = 0; r <= size - 11; r++) {
        if (_isN3Pattern(matrix, r, c, isHorizontal: false)) {
          matches++;
        }
      }
    }

    return matches * 40;
  }

  static bool _isN3Pattern(
    QrMatrix matrix,
    int r,
    int c, {
    required bool isHorizontal,
  }) {
    // Read 11 consecutive modules
    final b0 = isHorizontal ? matrix.getModule(r, c) : matrix.getModule(r, c);
    final b1 =
        isHorizontal ? matrix.getModule(r, c + 1) : matrix.getModule(r + 1, c);
    final b2 =
        isHorizontal ? matrix.getModule(r, c + 2) : matrix.getModule(r + 2, c);
    final b3 =
        isHorizontal ? matrix.getModule(r, c + 3) : matrix.getModule(r + 3, c);
    final b4 =
        isHorizontal ? matrix.getModule(r, c + 4) : matrix.getModule(r + 4, c);
    final b5 =
        isHorizontal ? matrix.getModule(r, c + 5) : matrix.getModule(r + 5, c);
    final b6 =
        isHorizontal ? matrix.getModule(r, c + 6) : matrix.getModule(r + 6, c);
    final b7 =
        isHorizontal ? matrix.getModule(r, c + 7) : matrix.getModule(r + 7, c);
    final b8 =
        isHorizontal ? matrix.getModule(r, c + 8) : matrix.getModule(r + 8, c);
    final b9 =
        isHorizontal ? matrix.getModule(r, c + 9) : matrix.getModule(r + 9, c);
    final b10 = isHorizontal
        ? matrix.getModule(r, c + 10)
        : matrix.getModule(r + 10, c);

    // Pattern A: 1 0 1 1 1 0 1 0 0 0 0
    final isPatternA =
        b0 && !b1 && b2 && b3 && b4 && !b5 && b6 && !b7 && !b8 && !b9 && !b10;

    if (isPatternA) return true;

    // Pattern B: 0 0 0 0 1 0 1 1 1 0 1
    final isPatternB =
        !b0 && !b1 && !b2 && !b3 && b4 && !b5 && b6 && b7 && b8 && !b9 && b10;

    return isPatternB;
  }

  /// N4: Proportion of dark modules.
  /// Formula: ((dark * 2 - total).abs() * 10 ~/ total) * 10
  static int calculateN4(QrMatrix matrix) {
    int dark = 0;
    final size = matrix.size;
    final total = size * size;
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (matrix.getModule(r, c)) {
          dark++;
        }
      }
    }

    final fivePercentVariances = (dark * 2 - total).abs() * 10 ~/ total;
    return fivePercentVariances * 10;
  }
}

/// Block partitioning and EC parameters per ISO/IEC 18004 Table 9.
class QrEcBlockParams {
  final int ecCodewordsPerBlock;
  final int group1Blocks;
  final int group1DataCodewords;
  final int group2Blocks;
  final int group2DataCodewords;

  const QrEcBlockParams({
    required this.ecCodewordsPerBlock,
    required this.group1Blocks,
    required this.group1DataCodewords,
    this.group2Blocks = 0,
    this.group2DataCodewords = 0,
  });

  int get totalDataCodewords =>
      (group1Blocks * group1DataCodewords) +
      (group2Blocks * group2DataCodewords);

  int get totalEcCodewords =>
      (group1Blocks + group2Blocks) * ecCodewordsPerBlock;

  int get totalCodewords => totalDataCodewords + totalEcCodewords;
}

/// Clean Architecture Domain Service for QR Code matrix generation,
/// ISO/IEC 18004 version-growth calculation, and mask pattern evaluation.
class QrMatrixGeneratorService {
  /// Center coordinates of alignment patterns for Versions 1 through 40 (Annex E Table E.1).
  static const List<List<int>> alignmentPatternCoordinates = <List<int>>[
    <int>[], // V1
    <int>[6, 18], // V2
    <int>[6, 22], // V3
    <int>[6, 26], // V4
    <int>[6, 30], // V5
    <int>[6, 34], // V6
    <int>[6, 22, 38], // V7
    <int>[6, 24, 42], // V8
    <int>[6, 26, 46], // V9
    <int>[6, 28, 50], // V10
    <int>[6, 30, 54], // V11
    <int>[6, 32, 58], // V12
    <int>[6, 34, 62], // V13
    <int>[6, 26, 46, 66], // V14
    <int>[6, 26, 48, 70], // V15
    <int>[6, 26, 50, 74], // V16
    <int>[6, 30, 54, 78], // V17
    <int>[6, 30, 56, 82], // V18
    <int>[6, 30, 58, 86], // V19
    <int>[6, 34, 62, 90], // V20
    <int>[6, 28, 50, 72, 94], // V21
    <int>[6, 26, 50, 74, 98], // V22
    <int>[6, 30, 54, 78, 102], // V23
    <int>[6, 28, 54, 80, 106], // V24
    <int>[6, 32, 58, 84, 110], // V25
    <int>[6, 30, 58, 86, 114], // V26
    <int>[6, 34, 62, 90, 118], // V27
    <int>[6, 26, 50, 74, 98, 122], // V28
    <int>[6, 30, 54, 78, 102, 126], // V29
    <int>[6, 26, 52, 78, 104, 130], // V30
    <int>[6, 30, 56, 82, 108, 134], // V31
    <int>[6, 34, 60, 86, 112, 138], // V32
    <int>[6, 30, 58, 86, 114, 142], // V33
    <int>[6, 34, 62, 90, 118, 146], // V34
    <int>[6, 30, 54, 78, 102, 126, 150], // V35
    <int>[6, 24, 50, 76, 102, 128, 154], // V36
    <int>[6, 28, 54, 80, 106, 132, 158], // V37
    <int>[6, 32, 58, 84, 110, 136, 162], // V38
    <int>[6, 26, 54, 82, 110, 138, 166], // V39
    <int>[6, 30, 58, 86, 114, 142, 170], // V40
  ];

  /// Master ISO/IEC 18004 Table 9: Error correction and block partitioning parameters.
  /// Indexed by [version - 1][eccLevel.index].
  static const List<List<QrEcBlockParams>> ecBlockTable =
      <List<QrEcBlockParams>>[
    // V1
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 7, group1Blocks: 1, group1DataCodewords: 19),
      QrEcBlockParams(
          ecCodewordsPerBlock: 10, group1Blocks: 1, group1DataCodewords: 16),
      QrEcBlockParams(
          ecCodewordsPerBlock: 13, group1Blocks: 1, group1DataCodewords: 13),
      QrEcBlockParams(
          ecCodewordsPerBlock: 17, group1Blocks: 1, group1DataCodewords: 9),
    ],
    // V2
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 10, group1Blocks: 1, group1DataCodewords: 34),
      QrEcBlockParams(
          ecCodewordsPerBlock: 16, group1Blocks: 1, group1DataCodewords: 28),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22, group1Blocks: 1, group1DataCodewords: 22),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28, group1Blocks: 1, group1DataCodewords: 16),
    ],
    // V3
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 15, group1Blocks: 1, group1DataCodewords: 55),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26, group1Blocks: 1, group1DataCodewords: 44),
      QrEcBlockParams(
          ecCodewordsPerBlock: 18, group1Blocks: 2, group1DataCodewords: 17),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22, group1Blocks: 2, group1DataCodewords: 13),
    ],
    // V4
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 20, group1Blocks: 1, group1DataCodewords: 80),
      QrEcBlockParams(
          ecCodewordsPerBlock: 18, group1Blocks: 2, group1DataCodewords: 32),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26, group1Blocks: 2, group1DataCodewords: 24),
      QrEcBlockParams(
          ecCodewordsPerBlock: 16, group1Blocks: 4, group1DataCodewords: 9),
    ],
    // V5
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 26, group1Blocks: 1, group1DataCodewords: 108),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24, group1Blocks: 2, group1DataCodewords: 43),
      QrEcBlockParams(
          ecCodewordsPerBlock: 18,
          group1Blocks: 2,
          group1DataCodewords: 15,
          group2Blocks: 2,
          group2DataCodewords: 16),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 2,
          group1DataCodewords: 11,
          group2Blocks: 2,
          group2DataCodewords: 12),
    ],
    // V6
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 18, group1Blocks: 2, group1DataCodewords: 68),
      QrEcBlockParams(
          ecCodewordsPerBlock: 16, group1Blocks: 4, group1DataCodewords: 27),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24, group1Blocks: 4, group1DataCodewords: 19),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28, group1Blocks: 4, group1DataCodewords: 15),
    ],
    // V7
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 20, group1Blocks: 2, group1DataCodewords: 78),
      QrEcBlockParams(
          ecCodewordsPerBlock: 18, group1Blocks: 4, group1DataCodewords: 31),
      QrEcBlockParams(
          ecCodewordsPerBlock: 18,
          group1Blocks: 2,
          group1DataCodewords: 14,
          group2Blocks: 4,
          group2DataCodewords: 15),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 4,
          group1DataCodewords: 13,
          group2Blocks: 1,
          group2DataCodewords: 14),
    ],
    // V8
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 24, group1Blocks: 2, group1DataCodewords: 97),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 2,
          group1DataCodewords: 38,
          group2Blocks: 2,
          group2DataCodewords: 39),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 4,
          group1DataCodewords: 18,
          group2Blocks: 2,
          group2DataCodewords: 19),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 4,
          group1DataCodewords: 14,
          group2Blocks: 2,
          group2DataCodewords: 15),
    ],
    // V9
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30, group1Blocks: 2, group1DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 3,
          group1DataCodewords: 36,
          group2Blocks: 2,
          group2DataCodewords: 37),
      QrEcBlockParams(
          ecCodewordsPerBlock: 20,
          group1Blocks: 4,
          group1DataCodewords: 16,
          group2Blocks: 4,
          group2DataCodewords: 17),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 4,
          group1DataCodewords: 12,
          group2Blocks: 4,
          group2DataCodewords: 13),
    ],
    // V10
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 18,
          group1Blocks: 2,
          group1DataCodewords: 68,
          group2Blocks: 2,
          group2DataCodewords: 69),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 4,
          group1DataCodewords: 43,
          group2Blocks: 1,
          group2DataCodewords: 44),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 6,
          group1DataCodewords: 19,
          group2Blocks: 2,
          group2DataCodewords: 20),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 6,
          group1DataCodewords: 15,
          group2Blocks: 2,
          group2DataCodewords: 16),
    ],
    // V11
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 20, group1Blocks: 4, group1DataCodewords: 81),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 1,
          group1DataCodewords: 50,
          group2Blocks: 4,
          group2DataCodewords: 51),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 4,
          group1DataCodewords: 22,
          group2Blocks: 4,
          group2DataCodewords: 23),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 3,
          group1DataCodewords: 12,
          group2Blocks: 8,
          group2DataCodewords: 13),
    ],
    // V12
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 2,
          group1DataCodewords: 92,
          group2Blocks: 2,
          group2DataCodewords: 93),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 6,
          group1DataCodewords: 36,
          group2Blocks: 2,
          group2DataCodewords: 37),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 4,
          group1DataCodewords: 20,
          group2Blocks: 6,
          group2DataCodewords: 21),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 7,
          group1DataCodewords: 14,
          group2Blocks: 4,
          group2DataCodewords: 15),
    ],
    // V13
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 26, group1Blocks: 4, group1DataCodewords: 107),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 8,
          group1DataCodewords: 37,
          group2Blocks: 1,
          group2DataCodewords: 38),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 8,
          group1DataCodewords: 20,
          group2Blocks: 4,
          group2DataCodewords: 21),
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 12,
          group1DataCodewords: 11,
          group2Blocks: 4,
          group2DataCodewords: 12),
    ],
    // V14
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 3,
          group1DataCodewords: 115,
          group2Blocks: 1,
          group2DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 4,
          group1DataCodewords: 40,
          group2Blocks: 5,
          group2DataCodewords: 41),
      QrEcBlockParams(
          ecCodewordsPerBlock: 20,
          group1Blocks: 11,
          group1DataCodewords: 16,
          group2Blocks: 5,
          group2DataCodewords: 17),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 11,
          group1DataCodewords: 12,
          group2Blocks: 5,
          group2DataCodewords: 13),
    ],
    // V15
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 22,
          group1Blocks: 5,
          group1DataCodewords: 87,
          group2Blocks: 1,
          group2DataCodewords: 88),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 5,
          group1DataCodewords: 41,
          group2Blocks: 5,
          group2DataCodewords: 42),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 5,
          group1DataCodewords: 24,
          group2Blocks: 7,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 11,
          group1DataCodewords: 12,
          group2Blocks: 7,
          group2DataCodewords: 13),
    ],
    // V16
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 5,
          group1DataCodewords: 98,
          group2Blocks: 1,
          group2DataCodewords: 99),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 7,
          group1DataCodewords: 45,
          group2Blocks: 3,
          group2DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24,
          group1Blocks: 15,
          group1DataCodewords: 19,
          group2Blocks: 2,
          group2DataCodewords: 20),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 3,
          group1DataCodewords: 15,
          group2Blocks: 13,
          group2DataCodewords: 16),
    ],
    // V17
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 1,
          group1DataCodewords: 107,
          group2Blocks: 5,
          group2DataCodewords: 108),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 10,
          group1DataCodewords: 46,
          group2Blocks: 1,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 1,
          group1DataCodewords: 22,
          group2Blocks: 15,
          group2DataCodewords: 23),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 2,
          group1DataCodewords: 14,
          group2Blocks: 17,
          group2DataCodewords: 15),
    ],
    // V18
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 5,
          group1DataCodewords: 120,
          group2Blocks: 1,
          group2DataCodewords: 121),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 9,
          group1DataCodewords: 43,
          group2Blocks: 4,
          group2DataCodewords: 44),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 17,
          group1DataCodewords: 22,
          group2Blocks: 1,
          group2DataCodewords: 23),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 2,
          group1DataCodewords: 14,
          group2Blocks: 19,
          group2DataCodewords: 15),
    ],
    // V19
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 3,
          group1DataCodewords: 113,
          group2Blocks: 4,
          group2DataCodewords: 114),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 3,
          group1DataCodewords: 44,
          group2Blocks: 11,
          group2DataCodewords: 45),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 17,
          group1DataCodewords: 21,
          group2Blocks: 4,
          group2DataCodewords: 22),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 9,
          group1DataCodewords: 13,
          group2Blocks: 16,
          group2DataCodewords: 14),
    ],
    // V20
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 3,
          group1DataCodewords: 107,
          group2Blocks: 5,
          group2DataCodewords: 108),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 3,
          group1DataCodewords: 41,
          group2Blocks: 13,
          group2DataCodewords: 42),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 15,
          group1DataCodewords: 24,
          group2Blocks: 5,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 15,
          group1DataCodewords: 15,
          group2Blocks: 10,
          group2DataCodewords: 16),
    ],
    // V21
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 4,
          group1DataCodewords: 116,
          group2Blocks: 4,
          group2DataCodewords: 117),
      QrEcBlockParams(
          ecCodewordsPerBlock: 26, group1Blocks: 17, group1DataCodewords: 42),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 17,
          group1DataCodewords: 22,
          group2Blocks: 6,
          group2DataCodewords: 23),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 19,
          group1DataCodewords: 16,
          group2Blocks: 6,
          group2DataCodewords: 17),
    ],
    // V22
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 2,
          group1DataCodewords: 111,
          group2Blocks: 7,
          group2DataCodewords: 112),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28, group1Blocks: 17, group1DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 7,
          group1DataCodewords: 24,
          group2Blocks: 16,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 24, group1Blocks: 34, group1DataCodewords: 13),
    ],
    // V23
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 4,
          group1DataCodewords: 121,
          group2Blocks: 5,
          group2DataCodewords: 122),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 4,
          group1DataCodewords: 47,
          group2Blocks: 14,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 11,
          group1DataCodewords: 24,
          group2Blocks: 14,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 16,
          group1DataCodewords: 15,
          group2Blocks: 14,
          group2DataCodewords: 16),
    ],
    // V24
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 6,
          group1DataCodewords: 117,
          group2Blocks: 4,
          group2DataCodewords: 118),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 6,
          group1DataCodewords: 45,
          group2Blocks: 14,
          group2DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 11,
          group1DataCodewords: 24,
          group2Blocks: 16,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 30,
          group1DataCodewords: 16,
          group2Blocks: 2,
          group2DataCodewords: 17),
    ],
    // V25
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 26,
          group1Blocks: 8,
          group1DataCodewords: 106,
          group2Blocks: 4,
          group2DataCodewords: 107),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 8,
          group1DataCodewords: 47,
          group2Blocks: 13,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 7,
          group1DataCodewords: 24,
          group2Blocks: 22,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 22,
          group1DataCodewords: 15,
          group2Blocks: 13,
          group2DataCodewords: 16),
    ],
    // V26
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 10,
          group1DataCodewords: 114,
          group2Blocks: 2,
          group2DataCodewords: 115),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 19,
          group1DataCodewords: 46,
          group2Blocks: 4,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 28,
          group1DataCodewords: 22,
          group2Blocks: 6,
          group2DataCodewords: 23),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 33,
          group1DataCodewords: 16,
          group2Blocks: 4,
          group2DataCodewords: 17),
    ],
    // V27
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 8,
          group1DataCodewords: 122,
          group2Blocks: 4,
          group2DataCodewords: 123),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 22,
          group1DataCodewords: 45,
          group2Blocks: 3,
          group2DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 8,
          group1DataCodewords: 23,
          group2Blocks: 26,
          group2DataCodewords: 24),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 12,
          group1DataCodewords: 15,
          group2Blocks: 28,
          group2DataCodewords: 16),
    ],
    // V28
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 3,
          group1DataCodewords: 117,
          group2Blocks: 10,
          group2DataCodewords: 118),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 3,
          group1DataCodewords: 45,
          group2Blocks: 23,
          group2DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 4,
          group1DataCodewords: 24,
          group2Blocks: 31,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 11,
          group1DataCodewords: 15,
          group2Blocks: 31,
          group2DataCodewords: 16),
    ],
    // V29
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 7,
          group1DataCodewords: 116,
          group2Blocks: 7,
          group2DataCodewords: 117),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 21,
          group1DataCodewords: 45,
          group2Blocks: 7,
          group2DataCodewords: 46),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 1,
          group1DataCodewords: 23,
          group2Blocks: 37,
          group2DataCodewords: 24),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 19,
          group1DataCodewords: 15,
          group2Blocks: 26,
          group2DataCodewords: 16),
    ],
    // V30
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 5,
          group1DataCodewords: 115,
          group2Blocks: 10,
          group2DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 19,
          group1DataCodewords: 47,
          group2Blocks: 10,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 15,
          group1DataCodewords: 24,
          group2Blocks: 25,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 23,
          group1DataCodewords: 15,
          group2Blocks: 25,
          group2DataCodewords: 16),
    ],
    // V31
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 13,
          group1DataCodewords: 115,
          group2Blocks: 3,
          group2DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 2,
          group1DataCodewords: 46,
          group2Blocks: 29,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 42,
          group1DataCodewords: 24,
          group2Blocks: 1,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 23,
          group1DataCodewords: 15,
          group2Blocks: 28,
          group2DataCodewords: 16),
    ],
    // V32
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30, group1Blocks: 17, group1DataCodewords: 115),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 10,
          group1DataCodewords: 46,
          group2Blocks: 23,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 10,
          group1DataCodewords: 24,
          group2Blocks: 35,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 19,
          group1DataCodewords: 15,
          group2Blocks: 35,
          group2DataCodewords: 16),
    ],
    // V33
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 17,
          group1DataCodewords: 115,
          group2Blocks: 1,
          group2DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 14,
          group1DataCodewords: 46,
          group2Blocks: 21,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 29,
          group1DataCodewords: 24,
          group2Blocks: 19,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 11,
          group1DataCodewords: 15,
          group2Blocks: 46,
          group2DataCodewords: 16),
    ],
    // V34
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 13,
          group1DataCodewords: 115,
          group2Blocks: 6,
          group2DataCodewords: 116),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 14,
          group1DataCodewords: 46,
          group2Blocks: 23,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 44,
          group1DataCodewords: 24,
          group2Blocks: 7,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 59,
          group1DataCodewords: 16,
          group2Blocks: 1,
          group2DataCodewords: 17),
    ],
    // V35
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 12,
          group1DataCodewords: 121,
          group2Blocks: 7,
          group2DataCodewords: 122),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 12,
          group1DataCodewords: 47,
          group2Blocks: 26,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 39,
          group1DataCodewords: 24,
          group2Blocks: 14,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 22,
          group1DataCodewords: 15,
          group2Blocks: 41,
          group2DataCodewords: 16),
    ],
    // V36
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 6,
          group1DataCodewords: 121,
          group2Blocks: 14,
          group2DataCodewords: 122),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 6,
          group1DataCodewords: 47,
          group2Blocks: 34,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 46,
          group1DataCodewords: 24,
          group2Blocks: 10,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 2,
          group1DataCodewords: 15,
          group2Blocks: 64,
          group2DataCodewords: 16),
    ],
    // V37
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 17,
          group1DataCodewords: 122,
          group2Blocks: 4,
          group2DataCodewords: 123),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 29,
          group1DataCodewords: 46,
          group2Blocks: 14,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 49,
          group1DataCodewords: 24,
          group2Blocks: 10,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 24,
          group1DataCodewords: 15,
          group2Blocks: 46,
          group2DataCodewords: 16),
    ],
    // V38
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 4,
          group1DataCodewords: 122,
          group2Blocks: 18,
          group2DataCodewords: 123),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 13,
          group1DataCodewords: 46,
          group2Blocks: 32,
          group2DataCodewords: 47),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 48,
          group1DataCodewords: 24,
          group2Blocks: 14,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 42,
          group1DataCodewords: 15,
          group2Blocks: 32,
          group2DataCodewords: 16),
    ],
    // V39
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 20,
          group1DataCodewords: 117,
          group2Blocks: 4,
          group2DataCodewords: 118),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 40,
          group1DataCodewords: 47,
          group2Blocks: 7,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 43,
          group1DataCodewords: 24,
          group2Blocks: 22,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 10,
          group1DataCodewords: 15,
          group2Blocks: 67,
          group2DataCodewords: 16),
    ],
    // V40
    <QrEcBlockParams>[
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 19,
          group1DataCodewords: 118,
          group2Blocks: 6,
          group2DataCodewords: 119),
      QrEcBlockParams(
          ecCodewordsPerBlock: 28,
          group1Blocks: 18,
          group1DataCodewords: 47,
          group2Blocks: 31,
          group2DataCodewords: 48),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 34,
          group1DataCodewords: 24,
          group2Blocks: 34,
          group2DataCodewords: 25),
      QrEcBlockParams(
          ecCodewordsPerBlock: 30,
          group1Blocks: 20,
          group1DataCodewords: 15,
          group2Blocks: 61,
          group2DataCodewords: 16),
    ],
  ];

  // Galois Field GF(2^8) lookup tables with primitive polynomial x^8 + x^4 + x^3 + x^2 + 1 = 0x11D (285).
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

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    _initGf();
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  /// Calculates the minimal QR Version (1 to 40) able to contain [byteLength]
  /// bytes at the specified [eccLevel].
  ///
  /// Throws [ArgumentError] if the payload exceeds Version 40 maximum capacity.
  int selectOptimalVersion(int byteLength, QrErrorCorrectionLevel eccLevel) {
    for (int v = 1; v <= 40; v++) {
      if (byteLength <= getMaxCapacity(v, eccLevel)) {
        return v;
      }
    }
    throw ArgumentError(
      'Payload size ($byteLength bytes) exceeds maximum QR code capacity for level ${eccLevel.label} (Max: ${getMaxCapacity(40, eccLevel)} bytes).',
    );
  }

  /// Returns the maximum data capacity (in 8-bit bytes) for the given [version]
  /// and [eccLevel] according to ISO/IEC 18004 Byte Mode rules.
  int getMaxCapacity(int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    final params = ecBlockTable[version - 1][eccLevel.index];
    final totalDataCodewords = params.totalDataCodewords;
    final headerBits = 4 + (version <= 9 ? 8 : 16);
    final availableBits = totalDataCodewords * 8 - headerBits;
    return availableBits ~/ 8;
  }

  /// Returns total codewords (data + error correction) for [version].
  int getTotalCodewords(int version) {
    _assertVersion(version);
    return ecBlockTable[version - 1][0].totalCodewords;
  }

  /// Returns total data codewords available for [version] and [eccLevel].
  int getDataCodewords(int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    return ecBlockTable[version - 1][eccLevel.index].totalDataCodewords;
  }

  /// Returns total error correction codewords for [version] and [eccLevel].
  int getEcCodewords(int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    return ecBlockTable[version - 1][eccLevel.index].totalEcCodewords;
  }

  /// Initializes an empty matrix with all function patterns placed and reserved:
  /// - 3 Finder patterns (7x7) + Separators
  /// - Timing patterns (row 6, column 6)
  /// - Alignment patterns (for versions >= 2)
  /// - Permanent dark module at (4*version + 9, 8)
  /// - Reserved format information areas
  /// - Reserved version information areas (for versions >= 7)
  QrMatrix initializeEmptyMatrix(int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    final matrix = QrMatrix(
      version: version,
      errorCorrectionLevel: eccLevel,
    );
    final size = matrix.size;

    // 1. Finder patterns and separators
    _placeFinderAndSeparator(matrix, 0, 0); // Top-left
    _placeFinderAndSeparator(matrix, 0, size - 7); // Top-right
    _placeFinderAndSeparator(matrix, size - 7, 0); // Bottom-left

    // 2. Timing patterns
    for (int i = 8; i < size - 8; i++) {
      final isDark = i % 2 == 0;
      matrix.setModule(6, i, isDark,
          type: QrModuleType.timing, isFunction: true);
      matrix.setModule(i, 6, isDark,
          type: QrModuleType.timing, isFunction: true);
    }

    // 3. Alignment patterns (Versions >= 2)
    if (version >= 2) {
      final centers = alignmentPatternCoordinates[version - 1];
      for (final r in centers) {
        for (final c in centers) {
          // Do not overlap finder patterns
          if ((r <= 8 && c <= 8) ||
              (r <= 8 && c >= size - 9) ||
              (r >= size - 9 && c <= 8)) {
            continue;
          }
          _placeAlignmentPattern(matrix, r, c);
        }
      }
    }

    // 4. Dark module: always dark at (size - 8, 8)
    matrix.setModule(size - 8, 8, true,
        type: QrModuleType.darkModule, isFunction: true);

    // 5. Reserve format information areas
    _reserveFormatAreas(matrix);

    // 6. Reserve version information areas (Versions >= 7)
    if (version >= 7) {
      _reserveVersionAreas(matrix);
    }

    return matrix;
  }

  void _placeFinderAndSeparator(QrMatrix matrix, int top, int left) {
    final size = matrix.size;

    // 7x7 Finder Pattern
    for (int r = 0; r < 7; r++) {
      for (int c = 0; c < 7; c++) {
        final isBorder = r == 0 || r == 6 || c == 0 || c == 6;
        final isCenter = r >= 2 && r <= 4 && c >= 2 && c <= 4;
        final isDark = isBorder || isCenter;
        matrix.setModule(top + r, left + c, isDark,
            type: QrModuleType.finder, isFunction: true);
      }
    }

    // Separators (1 module width around finder)
    // Top & Bottom horizontal separator line
    for (int c = -1; c <= 7; c++) {
      final col = left + c;
      if (col < 0 || col >= size) continue;

      if (top - 1 >= 0) {
        matrix.setModule(top - 1, col, false,
            type: QrModuleType.separator, isFunction: true);
      }
      if (top + 7 < size) {
        matrix.setModule(top + 7, col, false,
            type: QrModuleType.separator, isFunction: true);
      }
    }

    // Left & Right vertical separator line
    for (int r = -1; r <= 7; r++) {
      final row = top + r;
      if (row < 0 || row >= size) continue;

      if (left - 1 >= 0) {
        matrix.setModule(row, left - 1, false,
            type: QrModuleType.separator, isFunction: true);
      }
      if (left + 7 < size) {
        matrix.setModule(row, left + 7, false,
            type: QrModuleType.separator, isFunction: true);
      }
    }
  }

  void _placeAlignmentPattern(QrMatrix matrix, int centerR, int centerC) {
    for (int dr = -2; dr <= 2; dr++) {
      for (int dc = -2; dc <= 2; dc++) {
        final isBorder = dr.abs() == 2 || dc.abs() == 2;
        final isCenter = dr == 0 && dc == 0;
        final isDark = isBorder || isCenter;
        matrix.setModule(centerR + dr, centerC + dc, isDark,
            type: QrModuleType.alignment, isFunction: true);
      }
    }
  }

  void _reserveFormatAreas(QrMatrix matrix) {
    final size = matrix.size;
    // Around top-left finder:
    // Row 8: cols 0..5, 7..8 (skipping 6)
    for (int c = 0; c <= 8; c++) {
      if (c != 6) {
        matrix.setModule(8, c, false,
            type: QrModuleType.format, isFunction: true);
      }
    }
    // Col 8: rows 0..5, 7 (skipping 6)
    for (int r = 0; r <= 8; r++) {
      if (r != 6) {
        matrix.setModule(r, 8, false,
            type: QrModuleType.format, isFunction: true);
      }
    }

    // Around bottom-left finder:
    // Col 8: rows (size - 7) to (size - 1)
    for (int r = size - 7; r < size; r++) {
      matrix.setModule(r, 8, false,
          type: QrModuleType.format, isFunction: true);
    }

    // Around top-right finder:
    // Row 8: cols (size - 8) to (size - 1)
    for (int c = size - 8; c < size; c++) {
      matrix.setModule(8, c, false,
          type: QrModuleType.format, isFunction: true);
    }
  }

  void _reserveVersionAreas(QrMatrix matrix) {
    final size = matrix.size;
    // Bottom-left 3x6 block: rows (size - 11) to (size - 9), cols 0..5
    for (int r = size - 11; r <= size - 9; r++) {
      for (int c = 0; c < 6; c++) {
        matrix.setModule(r, c, false,
            type: QrModuleType.version, isFunction: true);
      }
    }
    // Top-right 6x3 block: rows 0..5, cols (size - 11) to (size - 9)
    for (int r = 0; r < 6; r++) {
      for (int c = size - 11; c <= size - 9; c++) {
        matrix.setModule(r, c, false,
            type: QrModuleType.version, isFunction: true);
      }
    }
  }

  /// Calculates format information 15-bit codeword using BCH(15, 5) and XOR mask 0x5412.
  static int computeFormatBits(QrErrorCorrectionLevel ecc, QrMaskPattern mask) {
    final data = (ecc.formatBits << 3) | mask.value;
    int d = data << 10;
    while (_highestBit(d) >= 10) {
      d ^= (0x537 << (_highestBit(d) - 10));
    }
    return ((data << 10) | d) ^ 0x5412;
  }

  /// Calculates version information 18-bit codeword using BCH(18, 6) generator 0x1F25.
  static int computeVersionBits(int version) {
    if (version < 7 || version > 40) return 0;
    int d = version << 12;
    while (_highestBit(d) >= 12) {
      d ^= (0x1F25 << (_highestBit(d) - 12));
    }
    return (version << 12) | d;
  }

  static int _highestBit(int value) {
    int bit = 0;
    while ((value >>= 1) != 0) {
      bit++;
    }
    return bit;
  }

  /// Embeds format information into the designated 15 modules of [matrix].
  void embedFormatInformation(
    QrMatrix matrix,
    QrMaskPattern maskPattern,
    QrErrorCorrectionLevel eccLevel,
  ) {
    final formatBits = computeFormatBits(eccLevel, maskPattern);
    final size = matrix.size;

    // Bit 0 is LSB, Bit 14 is MSB
    for (int i = 0; i < 15; i++) {
      final isDark = ((formatBits >> i) & 1) == 1;

      // Placement around top-left finder:
      if (i <= 5) {
        matrix.setModule(8, i, isDark,
            type: QrModuleType.format, isFunction: true);
      } else if (i == 6) {
        matrix.setModule(8, 7, isDark,
            type: QrModuleType.format, isFunction: true);
      } else if (i == 7) {
        matrix.setModule(8, 8, isDark,
            type: QrModuleType.format, isFunction: true);
      } else if (i == 8) {
        matrix.setModule(7, 8, isDark,
            type: QrModuleType.format, isFunction: true);
      } else {
        // i in 9..14 -> rows 5 down to 0
        matrix.setModule(14 - i, 8, isDark,
            type: QrModuleType.format, isFunction: true);
      }

      // Placement around bottom-left & top-right finders:
      if (i < 7) {
        // Bits 0..6 along bottom-left finder: col 8, rows (size - 1) down to (size - 7)
        matrix.setModule(size - 1 - i, 8, isDark,
            type: QrModuleType.format, isFunction: true);
      } else {
        // Bits 7..14 along top-right finder: row 8, cols (size - 8) up to (size - 1)
        matrix.setModule(8, size - 8 + (i - 7), isDark,
            type: QrModuleType.format, isFunction: true);
      }
    }
  }

  /// Embeds 18-bit version information into [matrix] (for versions >= 7).
  void embedVersionInformation(QrMatrix matrix, int version) {
    if (version < 7) return;
    final versionBits = computeVersionBits(version);
    final size = matrix.size;

    for (int i = 0; i < 18; i++) {
      final isDark = ((versionBits >> i) & 1) == 1;
      final rowOffset = i ~/ 3;
      final colOffset = i % 3;

      // Bottom-left 3x6 block:
      matrix.setModule(size - 11 + colOffset, rowOffset, isDark,
          type: QrModuleType.version, isFunction: true);

      // Top-right 6x3 block:
      matrix.setModule(rowOffset, size - 11 + colOffset, isDark,
          type: QrModuleType.version, isFunction: true);
    }
  }

  /// Encodes 8-bit byte payload into QR data codewords with mode header,
  /// character count, terminator, and alternating 0xEC / 0x11 pad bytes.
  Uint8List encodeByteData(
      Uint8List payload, int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    final targetCodewords = getDataCodewords(version, eccLevel);
    final countBits = version <= 9 ? 8 : 16;

    final bitBuffer = <int>[];

    void appendBits(int value, int length) {
      for (int i = length - 1; i >= 0; i--) {
        bitBuffer.add((value >> i) & 1);
      }
    }

    // 1. Mode indicator: 0100 (8-bit Byte mode)
    appendBits(4, 4);

    // 2. Character count indicator
    appendBits(payload.length, countBits);

    // 3. Payload data bytes
    for (final b in payload) {
      appendBits(b, 8);
    }

    // 4. Terminator: up to 4 zero bits to fill capacity
    final maxBits = targetCodewords * 8;
    final terminatorLength = math.min(4, maxBits - bitBuffer.length);
    appendBits(0, terminatorLength);

    // 5. Pad to 8-bit boundary
    while (bitBuffer.length % 8 != 0 && bitBuffer.length < maxBits) {
      bitBuffer.add(0);
    }

    // Convert bits to bytes
    final bytes = <int>[];
    for (int i = 0; i < bitBuffer.length; i += 8) {
      int b = 0;
      for (int j = 0; j < 8; j++) {
        b = (b << 1) | bitBuffer[i + j];
      }
      bytes.add(b);
    }

    // 6. Pad with alternating bytes 0xEC (11101100) and 0x11 (00010001)
    final padBytes = [0xEC, 0x11];
    int padIndex = 0;
    while (bytes.length < targetCodewords) {
      bytes.add(padBytes[padIndex % 2]);
      padIndex++;
    }

    return Uint8List.fromList(bytes);
  }

  /// Partitions data codewords into Reed-Solomon blocks, calculates EC codewords
  /// for each block, and interleaves data + EC codewords byte-by-byte.
  Uint8List generateInterleavedCodewords(
      Uint8List dataCodewords, int version, QrErrorCorrectionLevel eccLevel) {
    _assertVersion(version);
    final params = ecBlockTable[version - 1][eccLevel.index];

    final totalBlocks = params.group1Blocks + params.group2Blocks;
    final dataBlocks = <Uint8List>[];
    final ecBlocks = <Uint8List>[];

    int offset = 0;

    // Group 1 blocks
    for (int i = 0; i < params.group1Blocks; i++) {
      final block =
          dataCodewords.sublist(offset, offset + params.group1DataCodewords);
      dataBlocks.add(block);
      ecBlocks.add(_generateErrorCorrection(block, params.ecCodewordsPerBlock));
      offset += params.group1DataCodewords;
    }

    // Group 2 blocks
    for (int i = 0; i < params.group2Blocks; i++) {
      final block =
          dataCodewords.sublist(offset, offset + params.group2DataCodewords);
      dataBlocks.add(block);
      ecBlocks.add(_generateErrorCorrection(block, params.ecCodewordsPerBlock));
      offset += params.group2DataCodewords;
    }

    // Interleave data codewords
    final interleaved = <int>[];
    final maxDataBlockLen = math.max(
      params.group1DataCodewords,
      params.group2DataCodewords,
    );

    for (int byteIdx = 0; byteIdx < maxDataBlockLen; byteIdx++) {
      for (int blockIdx = 0; blockIdx < totalBlocks; blockIdx++) {
        if (byteIdx < dataBlocks[blockIdx].length) {
          interleaved.add(dataBlocks[blockIdx][byteIdx]);
        }
      }
    }

    // Interleave error correction codewords
    for (int byteIdx = 0; byteIdx < params.ecCodewordsPerBlock; byteIdx++) {
      for (int blockIdx = 0; blockIdx < totalBlocks; blockIdx++) {
        interleaved.add(ecBlocks[blockIdx][byteIdx]);
      }
    }

    return Uint8List.fromList(interleaved);
  }

  static Uint8List _generateErrorCorrection(Uint8List data, int ecCount) {
    _initGf();
    final generator = _getRsGenerator(ecCount);
    final msg = List<int>.filled(data.length + ecCount, 0);
    msg.setRange(0, data.length, data);

    for (int i = 0; i < data.length; i++) {
      final lead = msg[i];
      if (lead != 0) {
        for (int j = 0; j < generator.length; j++) {
          msg[i + j] ^= _gfMul(lead, generator[j]);
        }
      }
    }

    return Uint8List.fromList(msg.sublist(data.length));
  }

  static final Map<int, List<int>> _rsGeneratorCache = <int, List<int>>{};

  static List<int> _getRsGenerator(int count) {
    if (_rsGeneratorCache.containsKey(count)) {
      return _rsGeneratorCache[count]!;
    }
    _initGf();
    List<int> poly = <int>[1];
    for (int i = 0; i < count; i++) {
      final factor = <int>[1, _gfExp[i]];
      final newPoly = List<int>.filled(poly.length + 1, 0);
      for (int j = 0; j < poly.length; j++) {
        for (int k = 0; k < factor.length; k++) {
          newPoly[j + k] ^= _gfMul(poly[j], factor[k]);
        }
      }
      poly = newPoly;
    }
    _rsGeneratorCache[count] = poly;
    return poly;
  }

  /// Places interleaved codewords into [matrix] using the standard 2-column
  /// zigzag trajectory, skipping all function modules and vertical timing column.
  void placeCodewords(QrMatrix matrix, Uint8List interleavedCodewords) {
    final size = matrix.size;

    // Convert codewords to stream of bits
    final bitStream = <bool>[];
    for (final b in interleavedCodewords) {
      for (int i = 7; i >= 0; i--) {
        bitStream.add(((b >> i) & 1) == 1);
      }
    }

    int bitIndex = 0;
    bool upward = true;

    // Zigzag from rightmost column pairs to left
    for (int c = size - 1; c > 0; c -= 2) {
      // Skip column 6 (vertical timing pattern)
      if (c == 6) {
        c--;
      }

      final startR = upward ? size - 1 : 0;
      final endR = upward ? -1 : size;
      final stepR = upward ? -1 : 1;

      for (int r = startR; r != endR; r += stepR) {
        for (int colOffset = 0; colOffset < 2; colOffset++) {
          final targetCol = c - colOffset;
          if (matrix.isFunction(r, targetCol)) {
            continue;
          }

          final isDark =
              bitIndex < bitStream.length ? bitStream[bitIndex] : false;
          matrix.setModule(r, targetCol, isDark, type: QrModuleType.data);
          bitIndex++;
        }
      }
      upward = !upward;
    }
  }

  /// Applies [maskPattern] to all unreserved data modules, embeds corresponding
  /// format information, and returns the cloned masked [QrMatrix].
  QrMatrix applyMask(
    QrMatrix unmaskedMatrix,
    QrMaskPattern maskPattern,
    QrErrorCorrectionLevel eccLevel,
  ) {
    final masked = unmaskedMatrix.clone(newMaskPattern: maskPattern);
    final size = masked.size;

    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (!masked.isFunction(r, c)) {
          if (maskPattern.shouldInvert(r, c)) {
            final current = masked.getModule(r, c);
            masked.setModule(r, c, !current, type: QrModuleType.data);
          }
        }
      }
    }

    embedFormatInformation(masked, maskPattern, eccLevel);
    return masked;
  }

  /// Evaluates all 8 mask patterns against [unmaskedMatrix] and returns the pattern
  /// yielding the lowest total ISO/IEC 18004 penalty score.
  QrMaskPattern selectOptimalMask(
    QrMatrix unmaskedMatrix,
    QrErrorCorrectionLevel eccLevel,
  ) {
    QrMaskPattern bestPattern = QrMaskPattern.pattern000;
    int lowestScore = 999999999;

    for (final pattern in QrMaskPattern.values) {
      final masked = applyMask(unmaskedMatrix, pattern, eccLevel);
      final score = QrPenaltyCalculator.calculate(masked).totalScore;
      if (score < lowestScore) {
        lowestScore = score;
        bestPattern = pattern;
      }
    }

    return bestPattern;
  }

  /// Full end-to-end QR Matrix generation pipeline:
  /// 1. Determines version growth from payload density
  /// 2. Initializes function module topology
  /// 3. Serializes and pads 8-bit byte data
  /// 4. Generates Reed-Solomon EC codewords and interleaves blocks
  /// 5. Zigzag data placement
  /// 6. Automatic mask pattern evaluation (or fixed mask override)
  /// 7. Final format and version codeword embedding
  QrMatrix generateMatrix({
    required Uint8List payload,
    QrErrorCorrectionLevel eccLevel = QrErrorCorrectionLevel.medium,
    int? fixedVersion,
    QrMaskPattern? fixedMask,
  }) {
    final version =
        fixedVersion ?? selectOptimalVersion(payload.length, eccLevel);
    _assertVersion(version);

    if (payload.length > getMaxCapacity(version, eccLevel)) {
      throw ArgumentError(
        'Payload size (${payload.length} bytes) exceeds version $version capacity for level ${eccLevel.label} (${getMaxCapacity(version, eccLevel)} bytes).',
      );
    }

    // Step 1: Initialize matrix layout with reserved function patterns
    final baseMatrix = initializeEmptyMatrix(version, eccLevel);

    // Step 2: Encode byte data into codewords
    final dataCodewords = encodeByteData(payload, version, eccLevel);

    // Step 3: Compute RS parity blocks & interleave
    final interleaved =
        generateInterleavedCodewords(dataCodewords, version, eccLevel);

    // Step 4: Place codewords into matrix
    placeCodewords(baseMatrix, interleaved);

    // Step 5: Evaluate mask patterns
    final optimalMask = fixedMask ?? selectOptimalMask(baseMatrix, eccLevel);
    final maskedMatrix = applyMask(baseMatrix, optimalMask, eccLevel);

    // Step 6: Embed version information if version >= 7
    if (version >= 7) {
      embedVersionInformation(maskedMatrix, version);
    }

    return maskedMatrix;
  }

  void _assertVersion(int version) {
    if (version < 1 || version > 40) {
      throw RangeError.range(
          version, 1, 40, 'version', 'QR Version must be 1..40');
    }
  }
}
