import 'dart:math';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Galois Field GF(2^8) arithmetic using generator 2 and polynomial 0x11D.
class GaloisField256 {
  static final List<int> expTable = List<int>.filled(512, 0);
  static final List<int> logTable = List<int>.filled(256, 0);
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    int x = 1;
    for (int i = 0; i < 255; i++) {
      expTable[i] = x;
      expTable[i + 255] = x;
      logTable[x] = i;
      x <<= 1;
      if ((x & 0x100) != 0) {
        x ^= 0x11D;
      }
    }
    _initialized = true;
  }

  static int add(int a, int b) => a ^ b;
  static int sub(int a, int b) => a ^ b;

  static int mul(int a, int b) {
    if (!_initialized) init();
    if (a == 0 || b == 0) return 0;
    return expTable[logTable[a] + logTable[b]];
  }

  static int div(int a, int b) {
    if (!_initialized) init();
    if (b == 0) {
      throw ArgumentError('Division by zero in GF(256)');
    }
    if (a == 0) return 0;
    return expTable[(logTable[a] - logTable[b] + 255) % 255];
  }
}

/// An individual share produced by SLIP-39 / Shamir's Secret Sharing.
class Slip39Share extends Equatable {
  /// Unique 16-bit identifier binding all shares in a split group.
  final int identifier;

  /// Required threshold (T) of shares to reconstruct the secret.
  final int threshold;

  /// Total number of shares (N) generated.
  final int totalShares;

  /// 1-based index (x coordinate in GF(256)) of this share.
  final int index;

  /// Share payload values (y coordinates).
  final Uint8List data;

  const Slip39Share({
    required this.identifier,
    required this.threshold,
    required this.totalShares,
    required this.index,
    required this.data,
  });

  /// Serializes the share into a compact binary representation:
  /// [2B: identifier] [1B: threshold] [1B: totalShares] [1B: index] [data bytes].
  Uint8List toBytes() {
    final bytes = Uint8List(5 + data.length);
    final bdata = ByteData.sublistView(bytes);
    bdata.setUint16(0, identifier, Endian.big);
    bytes[2] = threshold;
    bytes[3] = totalShares;
    bytes[4] = index;
    bytes.setRange(5, bytes.length, data);
    return bytes;
  }

  /// Deserializes a [Slip39Share] from its compact binary wire format.
  factory Slip39Share.fromBytes(Uint8List bytes) {
    if (bytes.length < 6) {
      throw const FormatException('Share bytes too short for header');
    }
    final bdata = ByteData.sublistView(bytes);
    final identifier = bdata.getUint16(0, Endian.big);
    final threshold = bytes[2];
    final totalShares = bytes[3];
    final index = bytes[4];
    final data = bytes.sublist(5);

    return Slip39Share(
      identifier: identifier,
      threshold: threshold,
      totalShares: totalShares,
      index: index,
      data: data,
    );
  }

  @override
  List<Object?> get props => [identifier, threshold, totalShares, index, data];
}

/// Service providing SLIP-39 / Shamir's Secret Sharing threshold cryptography
/// over Galois Field GF(2^8) for optical air-gapped seed backup and recovery.
class Slip39SecretSharer {
  /// Splits [secret] into [totalShares] shares requiring [threshold] shares to recover.
  static List<Slip39Share> splitSecret({
    required Uint8List secret,
    required int threshold,
    required int totalShares,
    int? identifier,
    Random? random,
  }) {
    if (secret.isEmpty) {
      throw ArgumentError('Secret cannot be empty');
    }
    if (threshold < 2) {
      throw ArgumentError('Threshold must be at least 2');
    }
    if (threshold > totalShares) {
      throw ArgumentError(
          'Threshold ($threshold) cannot exceed total shares ($totalShares)');
    }
    if (totalShares > 254) {
      throw ArgumentError('Total shares cannot exceed 254 in GF(256)');
    }

    GaloisField256.init();
    final rng = random ?? Random.secure();
    final groupId = identifier ?? rng.nextInt(65536);

    final shareByteArrays = List.generate(
      totalShares,
      (_) => Uint8List(secret.length),
    );

    // Apply Shamir's polynomial per byte column
    for (int byteIdx = 0; byteIdx < secret.length; byteIdx++) {
      final s = secret[byteIdx];

      // Polynomial coefficients a_0 = s, a_1, ..., a_{threshold-1}
      final coefficients = List<int>.filled(threshold, 0);
      coefficients[0] = s;
      for (int c = 1; c < threshold; c++) {
        coefficients[c] = rng.nextInt(256);
      }

      // Evaluate at x = 1, 2, ..., totalShares
      for (int i = 0; i < totalShares; i++) {
        final x = i + 1; // 1-based non-zero x coordinate
        var y = 0;
        var xPower = 1;

        for (int c = 0; c < threshold; c++) {
          final term = GaloisField256.mul(coefficients[c], xPower);
          y = GaloisField256.add(y, term);
          xPower = GaloisField256.mul(xPower, x);
        }

        shareByteArrays[i][byteIdx] = y;
      }
    }

    return List.generate(
      totalShares,
      (i) => Slip39Share(
        identifier: groupId,
        threshold: threshold,
        totalShares: totalShares,
        index: i + 1,
        data: shareByteArrays[i],
      ),
    );
  }

  /// Reconstructs the master secret from any [threshold] or more valid [shares]
  /// via Lagrange interpolation in GF(256).
  static Uint8List recoverSecret(List<Slip39Share> shares) {
    if (shares.isEmpty) {
      throw ArgumentError('Shares list cannot be empty');
    }

    final first = shares.first;
    final threshold = first.threshold;
    final identifier = first.identifier;
    final secretLength = first.data.length;

    // Deduplicate shares by index
    final uniqueShares = <int, Slip39Share>{};
    for (final share in shares) {
      if (share.identifier != identifier) {
        throw ArgumentError('Mismatched share group identifier');
      }
      if (share.threshold != threshold) {
        throw ArgumentError('Mismatched share threshold attribute');
      }
      if (share.data.length != secretLength) {
        throw ArgumentError('Inconsistent share data lengths');
      }
      uniqueShares[share.index] = share;
    }

    if (uniqueShares.length < threshold) {
      throw StateError(
        'Insufficient shares: have ${uniqueShares.length}, need $threshold for reconstruction',
      );
    }

    // Select exactly threshold shares for Lagrange interpolation
    final selectedShares = uniqueShares.values.take(threshold).toList();
    final xCoords = selectedShares.map((s) => s.index).toList();

    GaloisField256.init();
    final recovered = Uint8List(secretLength);

    // Compute Lagrange basis coefficients L_j(0) = product_{m != j} (x_m / (x_j ^ x_m))
    final lagrangeWeights = List<int>.filled(threshold, 0);
    for (int j = 0; j < threshold; j++) {
      var weight = 1;
      final xj = xCoords[j];

      for (int m = 0; m < threshold; m++) {
        if (m == j) continue;
        final xm = xCoords[m];
        final denominator = GaloisField256.sub(xj, xm);
        final factor = GaloisField256.div(xm, denominator);
        weight = GaloisField256.mul(weight, factor);
      }
      lagrangeWeights[j] = weight;
    }

    // Interpolate P(0) for each byte column
    for (int byteIdx = 0; byteIdx < secretLength; byteIdx++) {
      var secretByte = 0;
      for (int j = 0; j < threshold; j++) {
        final yj = selectedShares[j].data[byteIdx];
        final term = GaloisField256.mul(yj, lagrangeWeights[j]);
        secretByte = GaloisField256.add(secretByte, term);
      }
      recovered[byteIdx] = secretByte;
    }

    return recovered;
  }
}
