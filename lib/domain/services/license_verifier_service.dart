import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import '../entities/license_certificate.dart';

/// Outcome of an offline Ed25519 license verification.
class LicenseVerificationResult extends Equatable {
  final bool isValid;
  final LicenseCertificate? certificate;
  final String? failureReason;

  const LicenseVerificationResult.valid(LicenseCertificate cert)
      : isValid = true,
        certificate = cert,
        failureReason = null;

  const LicenseVerificationResult.invalid(String reason)
      : isValid = false,
        certificate = null,
        failureReason = reason;

  @override
  List<Object?> get props => [isValid, certificate, failureReason];
}

/// Offline air-gapped license entitlement verifier and feature gate.
///
/// Uses pinned Ed25519 public key cryptography to authenticate `.zslic`
/// entitlements without network connectivity, remote telemetry, or DRM servers.
class LicenseVerifierService {
  /// Default pinned ZeroSync Root Ed25519 Public Key (32 bytes).
  static final Uint8List defaultPinnedRootPublicKey = Uint8List.fromList([
    0x3B,
    0x6A,
    0x27,
    0xBC,
    0xCE,
    0xB6,
    0xA4,
    0x2D,
    0x62,
    0xA3,
    0xA8,
    0xD0,
    0x2A,
    0x6F,
    0x0D,
    0x73,
    0x65,
    0x32,
    0x15,
    0x77,
    0x1D,
    0xE2,
    0x43,
    0xA6,
    0x3A,
    0xC0,
    0x48,
    0xA1,
    0x8B,
    0x59,
    0xDA,
    0x29,
  ]);

  final Uint8List _pinnedPublicKeyBytes;
  final Ed25519 _ed25519;

  LicenseVerifierService({
    Uint8List? pinnedPublicKey,
    Ed25519? ed25519,
  })  : _pinnedPublicKeyBytes = pinnedPublicKey ?? defaultPinnedRootPublicKey,
        _ed25519 = ed25519 ?? Ed25519();

  /// Pinned 32-byte Ed25519 public key bytes.
  Uint8List get pinnedPublicKeyBytes => _pinnedPublicKeyBytes;

  /// Cryptographically verifies [certificate] against the pinned Ed25519 root key.
  Future<LicenseVerificationResult> verifyCertificate(
    LicenseCertificate certificate, {
    DateTime? evaluationTime,
  }) async {
    try {
      final canonicalBytes = certificate.payload.toCanonicalBytes();
      final publicKey = SimplePublicKey(
        _pinnedPublicKeyBytes,
        type: KeyPairType.ed25519,
      );

      final signature = Signature(
        certificate.signature,
        publicKey: publicKey,
      );

      final isSigValid = await _ed25519.verify(
        canonicalBytes,
        signature: signature,
      );

      if (!isSigValid) {
        return const LicenseVerificationResult.invalid(
          'Cryptographic signature verification failed: invalid Ed25519 signature',
        );
      }

      if (certificate.payload.isExpired(evaluationTime)) {
        return LicenseVerificationResult.invalid(
          'License expired on ${certificate.payload.expiresAt?.toIso8601String()}',
        );
      }

      return LicenseVerificationResult.valid(certificate);
    } catch (e) {
      return LicenseVerificationResult.invalid('Verification error: $e');
    }
  }

  /// Verifies an encoded `.zslic` Base64 or JSON license string.
  Future<LicenseVerificationResult> verifyEncodedString(
    String encoded, {
    DateTime? evaluationTime,
  }) async {
    try {
      final cert = LicenseCertificate.fromEncodedString(encoded);
      return verifyCertificate(cert, evaluationTime: evaluationTime);
    } catch (e) {
      return LicenseVerificationResult.invalid(
          'Malformed license encoding: $e');
    }
  }

  /// Verifies a binary `.zslic` datagram.
  Future<LicenseVerificationResult> verifyBinary(
    Uint8List binaryBytes, {
    DateTime? evaluationTime,
  }) async {
    try {
      final cert = LicenseCertificate.fromBinary(binaryBytes);
      return verifyCertificate(cert, evaluationTime: evaluationTime);
    } catch (e) {
      return LicenseVerificationResult.invalid('Malformed binary license: $e');
    }
  }

  /// Evaluates whether a restricted capability is permitted under the active license.
  bool isFeatureAllowed(
    LicenseFeature feature,
    LicenseCertificate? activeLicense, {
    DateTime? evaluationTime,
  }) {
    if (activeLicense == null) {
      // Community edition: baseline features only
      return false;
    }

    if (activeLicense.payload.isExpired(evaluationTime)) {
      return false;
    }

    // Enterprise tier unlocks all features unconditionally
    if (activeLicense.payload.tier == LicenseTier.enterprise) {
      return true;
    }

    return activeLicense.payload.features.contains(feature);
  }

  /// Administrative & test helper: signs [payload] with [signingKeyPair] to produce a valid [LicenseCertificate].
  static Future<LicenseCertificate> issueLicense({
    required LicensePayload payload,
    required KeyPair signingKeyPair,
    Ed25519? ed25519,
  }) async {
    final algorithm = ed25519 ?? Ed25519();
    final canonicalBytes = payload.toCanonicalBytes();
    final signature =
        await algorithm.sign(canonicalBytes, keyPair: signingKeyPair);

    return LicenseCertificate(
      payload: payload,
      signature: Uint8List.fromList(signature.bytes),
    );
  }
}
