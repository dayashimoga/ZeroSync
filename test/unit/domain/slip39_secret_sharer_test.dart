import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/domain/services/slip39_secret_sharer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GaloisField256 Arithmetic Specs', () {
    test('Addition, multiplication and division inverses in GF(256)', () {
      GaloisField256.init();

      // In GF(2^8), a ^ a == 0
      expect(GaloisField256.add(42, 42), equals(0));
      expect(GaloisField256.sub(42, 42), equals(0));

      // Multiplicative identity: a * 1 == a
      expect(GaloisField256.mul(123, 1), equals(123));

      // Multiplicative inverse: a * (1 / a) == 1 for all non-zero a
      for (int a = 1; a < 256; a++) {
        final inv = GaloisField256.div(1, a);
        expect(GaloisField256.mul(a, inv), equals(1));
      }

      // Multiplication by zero yields zero
      expect(GaloisField256.mul(0, 150), equals(0));
      expect(GaloisField256.mul(150, 0), equals(0));

      // Division by zero throws
      expect(() => GaloisField256.div(5, 0), throwsA(isA<ArgumentError>()));
    });
  });

  group('Slip39Share Binary Serialization Specs', () {
    test('Round-trip serialization toBytes and fromBytes', () {
      final share = Slip39Share(
        identifier: 0xABCD,
        threshold: 3,
        totalShares: 5,
        index: 2,
        data: Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]),
      );

      final bytes = share.toBytes();
      final restored = Slip39Share.fromBytes(bytes);

      expect(restored, equals(share));
    });

    test('fromBytes throws on truncated byte buffer', () {
      expect(
        () => Slip39Share.fromBytes(Uint8List(4)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Slip39SecretSharer Threshold Split & Reconstruction Specs', () {
    test('2-of-3 split and recovery across all 2-share subsets', () {
      final secret = utf8.encode('Correct Horse Battery Staple 2026!');
      final secretBytes = Uint8List.fromList(secret);

      final shares = Slip39SecretSharer.splitSecret(
        secret: secretBytes,
        threshold: 2,
        totalShares: 3,
      );

      expect(shares.length, equals(3));

      // Subset {1, 2}
      final rec12 = Slip39SecretSharer.recoverSecret([shares[0], shares[1]]);
      expect(rec12, equals(secretBytes));

      // Subset {1, 3}
      final rec13 = Slip39SecretSharer.recoverSecret([shares[0], shares[2]]);
      expect(rec13, equals(secretBytes));

      // Subset {2, 3}
      final rec23 = Slip39SecretSharer.recoverSecret([shares[1], shares[2]]);
      expect(rec23, equals(secretBytes));
    });

    test('3-of-5 split recovers across all 10 combinations of 3 shares', () {
      final secretBytes = Uint8List.fromList(
        List.generate(32, (i) => (i * 37 + 13) % 256), // 256-bit seed
      );

      final shares = Slip39SecretSharer.splitSecret(
        secret: secretBytes,
        threshold: 3,
        totalShares: 5,
      );

      expect(shares.length, equals(5));

      // Test all 10 combinations of 3 shares
      int combinationsTested = 0;
      for (int i = 0; i < 5; i++) {
        for (int j = i + 1; j < 5; j++) {
          for (int k = j + 1; k < 5; k++) {
            final subset = [shares[i], shares[j], shares[k]];
            final recovered = Slip39SecretSharer.recoverSecret(subset);
            expect(recovered, equals(secretBytes));
            combinationsTested++;
          }
        }
      }
      expect(combinationsTested, equals(10));
    });

    test('Fails reconstruction when fewer than threshold shares are provided',
        () {
      final secret = Uint8List.fromList([1, 2, 3, 4]);
      final shares = Slip39SecretSharer.splitSecret(
        secret: secret,
        threshold: 3,
        totalShares: 5,
      );

      expect(
        () => Slip39SecretSharer.recoverSecret([shares[0], shares[1]]),
        throwsA(isA<StateError>()),
      );
    });

    test('Throws on invalid thresholds or parameters', () {
      final secret = Uint8List.fromList([1, 2, 3]);

      // Threshold < 2
      expect(
        () => Slip39SecretSharer.splitSecret(
          secret: secret,
          threshold: 1,
          totalShares: 3,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Threshold > totalShares
      expect(
        () => Slip39SecretSharer.splitSecret(
          secret: secret,
          threshold: 4,
          totalShares: 3,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
