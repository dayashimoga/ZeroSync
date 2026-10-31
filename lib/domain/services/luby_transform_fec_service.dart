import 'dart:math';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Pure Dart Deterministic Linear Congruential PRNG (Lehmer / Park-Miller with MurmurHash3 seed mixer).
/// Guarantees identical pseudo-random sequence across all architectures and isolates.
class DeterministicPrng {
  int _state;

  DeterministicPrng(int seed) : _state = _mix32(seed & 0xFFFFFFFF) {
    if (_state == 0) _state = 0x6D2B79F5;
  }

  static int _mix32(int x) {
    var z = ((x ^ (x >>> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
    z = ((z ^ (z >>> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
    z = (z ^ (z >>> 16)) & 0x7FFFFFFF;
    return z;
  }

  /// Generates next 32-bit unsigned integer.
  int nextUint32() {
    _state = (_state * 48271) % 0x7FFFFFFF;
    return _state;
  }

  /// Generates uniform double in [0.0, 1.0).
  double nextDouble() {
    return (nextUint32() - 1) / 0x7FFFFFFE;
  }

  /// Generates integer in [0, max - 1].
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError('max must be positive');
    return nextUint32() % max;
  }
}

/// Robust Soliton Degree Distribution for Luby Transform rateless codes.
class RobustSolitonDistribution {
  final int totalBlocks;
  final double c;
  final double delta;
  late final List<double> _cdf;

  RobustSolitonDistribution(
    this.totalBlocks, {
    this.c = 0.1,
    this.delta = 0.5,
  }) {
    if (totalBlocks < 1) {
      throw ArgumentError('totalBlocks must be >= 1');
    }
    _cdf = _buildCdf();
  }

  List<double> _buildCdf() {
    final k = totalBlocks;
    if (k == 1) return [1.0];

    final rho = List<double>.filled(k + 1, 0.0);
    rho[1] = 1.0 / k;
    for (var d = 2; d <= k; d++) {
      rho[d] = 1.0 / (d * (d - 1));
    }

    final tau = List<double>.filled(k + 1, 0.0);
    final r = c * log(k / delta) * sqrt(k);
    final pivot = (k / r).floor();

    for (var d = 1; d <= k; d++) {
      if (d < pivot) {
        tau[d] = r / (d * k);
      } else if (d == pivot) {
        tau[d] = (r * log(r / delta)) / k;
      } else {
        tau[d] = 0.0;
      }
    }

    final weights = List<double>.filled(k + 1, 0.0);
    var sumWeight = 0.0;
    for (var d = 1; d <= k; d++) {
      weights[d] = rho[d] + tau[d];
      sumWeight += weights[d];
    }

    final cdf = List<double>.filled(k + 1, 0.0);
    var cumulative = 0.0;
    for (var d = 1; d <= k; d++) {
      cumulative += weights[d] / sumWeight;
      cdf[d] = cumulative;
    }
    cdf[k] = 1.0; // Ensure ceiling
    return cdf;
  }

  /// Samples a degree d in [1, totalBlocks] deterministically using [prng].
  int sampleDegree(DeterministicPrng prng) {
    if (totalBlocks == 1) return 1;

    final u = prng.nextDouble();
    for (var d = 1; d <= totalBlocks; d++) {
      if (u <= _cdf[d]) {
        return d;
      }
    }
    return totalBlocks;
  }

  /// Samples [degree] distinct source block indices from [0, totalBlocks - 1].
  List<int> sampleIndices(int degree, DeterministicPrng prng) {
    if (degree >= totalBlocks) {
      return List<int>.generate(totalBlocks, (i) => i);
    }

    final selected = <int>{};
    while (selected.length < degree) {
      selected.add(prng.nextInt(totalBlocks));
    }
    final sorted = selected.toList()..sort();
    return sorted;
  }
}

/// A self-describing rateless droplet produced by the Luby Transform engine.
class FountainDroplet extends Equatable {
  /// Wire preamble size: seed (4B) + totalBlocks (2B) + symbolSize (2B) + originalLength (4B) = 12 Bytes.
  static const int headerSize = 12;

  final int seed;
  final int totalSourceBlocks;
  final int symbolSize;
  final int originalPayloadLength;
  final List<int> sourceIndices;
  final Uint8List data;

  const FountainDroplet({
    required this.seed,
    required this.totalSourceBlocks,
    required this.symbolSize,
    required this.originalPayloadLength,
    required this.sourceIndices,
    required this.data,
  });

  /// Degree of the droplet (number of combined source blocks).
  int get degree => sourceIndices.length;

  /// Serializes droplet to wire bytes:
  /// [0..3]   : Seed (32-bit unsigned, BigEndian)
  /// [4..5]   : Total source blocks (16-bit unsigned, BigEndian)
  /// [6..7]   : Symbol size (16-bit unsigned, BigEndian)
  /// [8..11]  : Original payload length (32-bit unsigned, BigEndian)
  /// [12..N]  : Data bytes (length = symbolSize)
  Uint8List toWireBytes() {
    final bytes = Uint8List(headerSize + data.length);
    final view = ByteData.sublistView(bytes);

    view.setUint32(0, seed, Endian.big);
    view.setUint16(4, totalSourceBlocks, Endian.big);
    view.setUint16(6, symbolSize, Endian.big);
    view.setUint32(8, originalPayloadLength, Endian.big);
    bytes.setRange(headerSize, bytes.length, data);

    return bytes;
  }

  /// Deserializes a raw wire packet into a [FountainDroplet], reconstructing
  /// the source indices using the deterministic soliton distribution.
  factory FountainDroplet.fromWireBytes(Uint8List wireBytes) {
    if (wireBytes.length < headerSize) {
      throw FormatException(
        'Droplet wire datagram too short: ${wireBytes.length} bytes (minimum $headerSize)',
      );
    }

    final view = ByteData.sublistView(wireBytes, 0, headerSize);
    final seed = view.getUint32(0, Endian.big);
    final totalBlocks = view.getUint16(4, Endian.big);
    final symbolSize = view.getUint16(6, Endian.big);
    final originalLength = view.getUint32(8, Endian.big);

    final payloadData = Uint8List.sublistView(wireBytes, headerSize);
    if (payloadData.length != symbolSize) {
      throw FormatException(
        'Droplet payload size mismatch: expected $symbolSize bytes, received ${payloadData.length}',
      );
    }

    final prng = DeterministicPrng(seed);
    final soliton = RobustSolitonDistribution(totalBlocks);
    final degree = soliton.sampleDegree(prng);
    final indices = soliton.sampleIndices(degree, prng);

    return FountainDroplet(
      seed: seed,
      totalSourceBlocks: totalBlocks,
      symbolSize: symbolSize,
      originalPayloadLength: originalLength,
      sourceIndices: indices,
      data: payloadData,
    );
  }

  @override
  List<Object?> get props => [
        seed,
        totalSourceBlocks,
        symbolSize,
        originalPayloadLength,
        sourceIndices,
        data,
      ];
}

/// Bitwise XOR utility for byte arrays.
Uint8List xorUint8Lists(Uint8List a, Uint8List b) {
  final length = min(a.length, b.length);
  final result = Uint8List(length);
  for (var i = 0; i < length; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

/// Stateful Luby Transform Decoder combining Belief Propagation (peeling ripple)
/// with a GF(2) Gaussian Elimination fallback for optimal erasure recovery.
class LubyTransformDecoder {
  final int totalSourceBlocks;
  final int symbolSize;
  final int originalPayloadLength;

  /// Solved source blocks: index -> block data.
  final Map<int, Uint8List> _solvedBlocks = <int, Uint8List>{};

  /// Unresolved linear equations: indices set -> data.
  final List<_Equation> _equations = <_Equation>[];

  LubyTransformDecoder({
    required this.totalSourceBlocks,
    required this.symbolSize,
    required this.originalPayloadLength,
  });

  /// Factory creating decoder initialized from first received droplet.
  factory LubyTransformDecoder.fromDroplet(FountainDroplet droplet) {
    return LubyTransformDecoder(
      totalSourceBlocks: droplet.totalSourceBlocks,
      symbolSize: droplet.symbolSize,
      originalPayloadLength: droplet.originalPayloadLength,
    );
  }

  /// Whether all source blocks have been decoded.
  bool get isDecoded => _solvedBlocks.length >= totalSourceBlocks;

  /// Decoding progress ratio [0.0, 1.0].
  double get progress =>
      totalSourceBlocks == 0 ? 1.0 : _solvedBlocks.length / totalSourceBlocks;

  /// Number of recovered source blocks.
  int get solvedBlocksCount => _solvedBlocks.length;

  /// Ingests a new droplet. Returns `true` if the droplet provided new linear information.
  bool addDroplet(FountainDroplet droplet) {
    if (isDecoded) return false;
    if (droplet.totalSourceBlocks != totalSourceBlocks ||
        droplet.symbolSize != symbolSize) {
      throw ArgumentError('Mismatched droplet transmission parameters');
    }

    // Poisoning protection: reject corrupted source block indices outside [0, totalSourceBlocks - 1]
    if (droplet.sourceIndices
        .any((idx) => idx < 0 || idx >= totalSourceBlocks)) {
      return false;
    }

    var indices = Set<int>.from(droplet.sourceIndices);
    var data = Uint8List.fromList(droplet.data);

    // Substitute already known source blocks
    final solvedIndices = indices.intersection(_solvedBlocks.keys.toSet());
    for (final solvedIndex in solvedIndices) {
      data = xorUint8Lists(data, _solvedBlocks[solvedIndex]!);
      indices.remove(solvedIndex);
    }

    if (indices.isEmpty) {
      return false; // Redundant droplet
    }

    final newEq = _Equation(indices, data);
    return _processEquation(newEq);
  }

  bool _processEquation(_Equation initialEq) {
    final ripple = <_Equation>[initialEq];
    var providedNewInfo = false;

    while (ripple.isNotEmpty) {
      final eq = ripple.removeLast();

      // Substitute solved blocks
      final solved = eq.indices.intersection(_solvedBlocks.keys.toSet());
      for (final s in solved) {
        eq.data = xorUint8Lists(eq.data, _solvedBlocks[s]!);
        eq.indices.remove(s);
      }

      if (eq.indices.isEmpty) continue;

      if (eq.indices.length == 1) {
        // Degree-1 equation: Direct source block recovery!
        final solvedIndex = eq.indices.first;
        if (!_solvedBlocks.containsKey(solvedIndex)) {
          _solvedBlocks[solvedIndex] = eq.data;
          providedNewInfo = true;

          // Propagate into all pending equations
          final nextEquations = <_Equation>[];
          for (final pending in _equations) {
            if (pending.indices.contains(solvedIndex)) {
              pending.data = xorUint8Lists(pending.data, eq.data);
              pending.indices.remove(solvedIndex);
              if (pending.indices.length == 1) {
                ripple.add(pending);
              } else if (pending.indices.isNotEmpty) {
                nextEquations.add(pending);
              }
            } else {
              nextEquations.add(pending);
            }
          }
          _equations
            ..clear()
            ..addAll(nextEquations);
        }
      } else {
        // Degree > 1: Store equation for future ripple or GF(2) fallback
        _equations.add(eq);
        providedNewInfo = true;
      }
    }

    // If peeling stalls but we have enough equations, run GF(2) fallback
    if (!isDecoded &&
        _equations.length >= (totalSourceBlocks - _solvedBlocks.length)) {
      _runGaussianElimination();
    }

    return providedNewInfo;
  }

  /// Solves remaining unsolved variables using Gaussian Elimination over GF(2).
  void _runGaussianElimination() {
    final unsolvedList = <int>[];
    for (var i = 0; i < totalSourceBlocks; i++) {
      if (!_solvedBlocks.containsKey(i)) {
        unsolvedList.add(i);
      }
    }

    final m = unsolvedList.length;
    if (m == 0 || _equations.isEmpty) return;

    final varToIndex = <int, int>{};
    for (var i = 0; i < m; i++) {
      varToIndex[unsolvedList[i]] = i;
    }

    // Build binary matrix and data vector
    final matrix = <List<bool>>[];
    final dataVec = <Uint8List>[];

    for (final eq in _equations) {
      final row = List<bool>.filled(m, false);
      for (final idx in eq.indices) {
        final col = varToIndex[idx];
        if (col != null) {
          row[col] = true;
        }
      }
      matrix.add(row);
      dataVec.add(Uint8List.fromList(eq.data));
    }

    final numRows = matrix.length;
    var pivotRow = 0;

    for (var col = 0; col < m && pivotRow < numRows; col++) {
      // Find pivot
      var selectedRow = -1;
      for (var r = pivotRow; r < numRows; r++) {
        if (matrix[r][col]) {
          selectedRow = r;
          break;
        }
      }

      if (selectedRow == -1) continue; // No pivot in this column

      // Swap selectedRow and pivotRow
      if (selectedRow != pivotRow) {
        final tempRow = matrix[pivotRow];
        matrix[pivotRow] = matrix[selectedRow];
        matrix[selectedRow] = tempRow;

        final tempData = dataVec[pivotRow];
        dataVec[pivotRow] = dataVec[selectedRow];
        dataVec[selectedRow] = tempData;
      }

      // Eliminate all other rows
      for (var r = 0; r < numRows; r++) {
        if (r != pivotRow && matrix[r][col]) {
          for (var c = 0; c < m; c++) {
            matrix[r][c] = matrix[r][c] ^ matrix[pivotRow][c];
          }
          dataVec[r] = xorUint8Lists(dataVec[r], dataVec[pivotRow]);
        }
      }

      pivotRow++;
    }

    // Extract solved single-variable rows
    final newlySolved = <int>[];
    for (var r = 0; r < numRows; r++) {
      var count = 0;
      var solvedCol = -1;
      for (var c = 0; c < m; c++) {
        if (matrix[r][c]) {
          count++;
          solvedCol = c;
        }
      }

      if (count == 1 && solvedCol != -1) {
        final originalIdx = unsolvedList[solvedCol];
        if (!_solvedBlocks.containsKey(originalIdx)) {
          _solvedBlocks[originalIdx] = dataVec[r];
          newlySolved.add(originalIdx);
        }
      }
    }

    if (newlySolved.isNotEmpty) {
      final remaining = <_Equation>[];
      for (final eq in _equations) {
        for (final s in newlySolved) {
          if (eq.indices.contains(s)) {
            eq.data = xorUint8Lists(eq.data, _solvedBlocks[s]!);
            eq.indices.remove(s);
          }
        }
        if (eq.indices.length == 1) {
          final idx = eq.indices.first;
          if (!_solvedBlocks.containsKey(idx)) {
            _solvedBlocks[idx] = eq.data;
          }
        } else if (eq.indices.isNotEmpty) {
          remaining.add(eq);
        }
      }
      _equations
        ..clear()
        ..addAll(remaining);
    }
  }

  /// Assembles and returns the full original decoded payload, truncated to original length.
  Uint8List? getDecodedPayload() {
    if (!isDecoded) return null;

    final assembled = Uint8List(totalSourceBlocks * symbolSize);
    for (var i = 0; i < totalSourceBlocks; i++) {
      final block = _solvedBlocks[i]!;
      assembled.setRange(i * symbolSize, (i + 1) * symbolSize, block);
    }

    return Uint8List.sublistView(assembled, 0, originalPayloadLength);
  }
}

class _Equation {
  final Set<int> indices;
  Uint8List data;

  _Equation(this.indices, this.data);
}

/// Domain service orchestrating Luby Transform (LT) / Fountain rateless erasure coding.
class LubyTransformFecService {
  /// Default symbol block size in bytes (calibrated for optical QR frames).
  static const int defaultSymbolSize = 180;

  const LubyTransformFecService();

  /// Slices [payload] into $K$ source blocks of size [symbolSize], zero-padding the last block.
  List<Uint8List> partitionSourceBlocks(
    Uint8List payload, {
    int symbolSize = defaultSymbolSize,
  }) {
    if (payload.isEmpty) {
      throw ArgumentError('Payload cannot be empty');
    }
    if (symbolSize <= 0) {
      throw ArgumentError('Symbol size must be positive');
    }

    final k = (payload.length / symbolSize).ceil();
    final blocks = <Uint8List>[];

    for (var i = 0; i < k; i++) {
      final block = Uint8List(symbolSize);
      final start = i * symbolSize;
      final end = min(start + symbolSize, payload.length);
      block.setRange(0, end - start, payload.sublist(start, end));
      blocks.add(block);
    }

    return blocks;
  }

  /// Generates a single rateless [FountainDroplet] from source blocks using [seed].
  FountainDroplet generateDroplet({
    required List<Uint8List> sourceBlocks,
    required int originalPayloadLength,
    required int seed,
  }) {
    final k = sourceBlocks.length;
    final symbolSize = sourceBlocks.first.length;

    final prng = DeterministicPrng(seed);
    final soliton = RobustSolitonDistribution(k);
    final degree = soliton.sampleDegree(prng);
    final indices = soliton.sampleIndices(degree, prng);

    final combined = Uint8List(symbolSize);
    for (final idx in indices) {
      final block = sourceBlocks[idx];
      for (var b = 0; b < symbolSize; b++) {
        combined[b] ^= block[b];
      }
    }

    return FountainDroplet(
      seed: seed,
      totalSourceBlocks: k,
      symbolSize: symbolSize,
      originalPayloadLength: originalPayloadLength,
      sourceIndices: indices,
      data: combined,
    );
  }

  /// Stream generator yielding an infinite sequence of rateless recovery droplets.
  Iterable<FountainDroplet> generateDropletStream(
    Uint8List payload, {
    int symbolSize = defaultSymbolSize,
    int startSeed = 0,
  }) sync* {
    final blocks = partitionSourceBlocks(payload, symbolSize: symbolSize);
    var seed = startSeed;

    while (true) {
      yield generateDroplet(
        sourceBlocks: blocks,
        originalPayloadLength: payload.length,
        seed: seed++,
      );
    }
  }

  /// Generates a finite collection of [count] droplets.
  List<FountainDroplet> generateNDroplets(
    Uint8List payload,
    int count, {
    int symbolSize = defaultSymbolSize,
    int startSeed = 0,
  }) {
    if (count <= 0) throw ArgumentError('Count must be > 0');
    final stream = generateDropletStream(
      payload,
      symbolSize: symbolSize,
      startSeed: startSeed,
    );
    return stream.take(count).toList();
  }

  /// Decodes a collection of droplets, returning the reconstructed payload.
  /// Throws [StateError] if the received droplets are insufficient to decode.
  Uint8List decodeDroplets(List<FountainDroplet> droplets) {
    if (droplets.isEmpty) {
      throw ArgumentError('Droplets collection cannot be empty');
    }

    final decoder = LubyTransformDecoder.fromDroplet(droplets.first);
    for (final droplet in droplets) {
      decoder.addDroplet(droplet);
      if (decoder.isDecoded) {
        return decoder.getDecodedPayload()!;
      }
    }

    throw StateError(
      'Insufficient droplets for complete recovery (progress: ${(decoder.progress * 100).toStringAsFixed(1)}%)',
    );
  }
}
