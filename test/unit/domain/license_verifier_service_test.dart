import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/license_certificate.dart';
import 'package:airdrop_qr/domain/services/license_verifier_service.dart';

void main() {
  group('LicenseCertificate Encoding & Binary Formatting Specs', () {
    test('JSON and Base64 .zslic round-trip preserves all entitlements', () {
      final payload = LicensePayload(
        id: 'LIC-2026-TEST-001',
        licensedTo: 'ZeroSync Operational Unit 7',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2030, 1, 1),
        tier: LicenseTier.pro,
        features: const {
          LicenseFeature.rgbMultiplexing,
          LicenseFeature.duressDecoyVault,
        },
      );
      final sig = Uint8List(64)..fillRange(0, 64, 0x42);
      final cert = LicenseCertificate(payload: payload, signature: sig);

      final encoded = cert.toEncodedString();
      final restored = LicenseCertificate.fromEncodedString(encoded);

      expect(restored.payload.id, equals(payload.id));
      expect(restored.payload.licensedTo, equals(payload.licensedTo));
      expect(restored.payload.tier, equals(LicenseTier.pro));
      expect(restored.payload.features, equals(payload.features));
      expect(restored.signature, equals(sig));
    });

    test('Compact binary format serialization round-trip', () {
      final payload = LicensePayload(
        id: 'BIN-LIC-002',
        licensedTo: 'Field Agent',
        issuedAt: DateTime.utc(2026, 6, 1),
        tier: LicenseTier.enterprise,
        features: const {LicenseFeature.unlimitedPayloadSize},
      );
      final sig = Uint8List(64)..fillRange(0, 64, 0x99);
      final cert = LicenseCertificate(payload: payload, signature: sig);

      final binary = cert.toBinary();
      expect(binary.length, greaterThan(68));
      expect(binary[0], equals(0x5A)); // 'Z'
      expect(binary[1], equals(0x53)); // 'S'
      expect(binary[2], equals(0x4C)); // 'L'
      expect(binary[3], equals(0x31)); // '1'

      final restored = LicenseCertificate.fromBinary(binary);
      expect(restored.payload.id, equals(payload.id));
      expect(restored.payload.tier, equals(LicenseTier.enterprise));
      expect(restored.signature, equals(sig));
    });
  });

  group('LicenseVerifierService Offline Ed25519 & Feature Gate Specs', () {
    late SimpleKeyPair rootKeyPair;
    late SimplePublicKey rootPublicKey;
    late LicenseVerifierService verifier;

    setUp(() async {
      final ed25519 = Ed25519();
      rootKeyPair = await ed25519.newKeyPair();
      rootPublicKey = await rootKeyPair.extractPublicKey();

      verifier = LicenseVerifierService(
        pinnedPublicKey: Uint8List.fromList(rootPublicKey.bytes),
      );
    });

    test('Validly signed license authenticates successfully offline', () async {
      final payload = LicensePayload(
        id: 'VAL-001',
        licensedTo: 'Secure Corp',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2028, 1, 1),
        tier: LicenseTier.pro,
        features: const {LicenseFeature.rgbMultiplexing},
      );

      final cert = await LicenseVerifierService.issueLicense(
        payload: payload,
        signingKeyPair: rootKeyPair,
      );

      final result = await verifier.verifyCertificate(
        cert,
        evaluationTime: DateTime.utc(2026, 6, 1),
      );

      expect(result.isValid, isTrue);
      expect(result.certificate, equals(cert));
      expect(result.failureReason, isNull);
    });

    test('Tampered license payload signature fails verification', () async {
      final payload = LicensePayload(
        id: 'VAL-002',
        licensedTo: 'Secure Corp',
        issuedAt: DateTime.utc(2026, 1, 1),
        tier: LicenseTier.pro,
        features: const {LicenseFeature.rgbMultiplexing},
      );

      final cert = await LicenseVerifierService.issueLicense(
        payload: payload,
        signingKeyPair: rootKeyPair,
      );

      // Malicious actor tampers with tier (escalating to enterprise)
      final tamperedPayload = LicensePayload(
        id: payload.id,
        licensedTo: payload.licensedTo,
        issuedAt: payload.issuedAt,
        tier: LicenseTier.enterprise,
        features: const {
          LicenseFeature.rgbMultiplexing,
          LicenseFeature.duressDecoyVault
        },
      );
      final forgedCert = LicenseCertificate(
        payload: tamperedPayload,
        signature: cert.signature,
      );

      final result = await verifier.verifyCertificate(forgedCert);
      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('Ed25519'));
    });

    test('Expired license is detected and rejected', () async {
      final payload = LicensePayload(
        id: 'EXP-001',
        licensedTo: 'Expirable Demo',
        issuedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 3, 1),
        tier: LicenseTier.pro,
        features: const {LicenseFeature.rgbMultiplexing},
      );

      final cert = await LicenseVerifierService.issueLicense(
        payload: payload,
        signingKeyPair: rootKeyPair,
      );

      final result = await verifier.verifyCertificate(
        cert,
        evaluationTime: DateTime.utc(2026, 4, 1), // Evaluated after expiration
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('expired'));
    });

    test('FeatureGate correctly evaluates permitted capabilities per tier',
        () async {
      final proPayload = LicensePayload(
        id: 'PRO-001',
        licensedTo: 'Pro User',
        issuedAt: DateTime.utc(2026, 1, 1),
        tier: LicenseTier.pro,
        features: const {LicenseFeature.rgbMultiplexing},
      );
      final proCert = await LicenseVerifierService.issueLicense(
        payload: proPayload,
        signingKeyPair: rootKeyPair,
      );

      final entPayload = LicensePayload(
        id: 'ENT-001',
        licensedTo: 'Enterprise Org',
        issuedAt: DateTime.utc(2026, 1, 1),
        tier: LicenseTier.enterprise,
        features: const {},
      );
      final entCert = await LicenseVerifierService.issueLicense(
        payload: entPayload,
        signingKeyPair: rootKeyPair,
      );

      // Community tier (no license)
      expect(verifier.isFeatureAllowed(LicenseFeature.rgbMultiplexing, null),
          isFalse);
      expect(verifier.isFeatureAllowed(LicenseFeature.duressDecoyVault, null),
          isFalse);

      // Pro tier
      expect(verifier.isFeatureAllowed(LicenseFeature.rgbMultiplexing, proCert),
          isTrue);
      expect(
          verifier.isFeatureAllowed(LicenseFeature.duressDecoyVault, proCert),
          isFalse);

      // Enterprise tier unlocks all features
      expect(verifier.isFeatureAllowed(LicenseFeature.rgbMultiplexing, entCert),
          isTrue);
      expect(
          verifier.isFeatureAllowed(LicenseFeature.duressDecoyVault, entCert),
          isTrue);
      expect(verifier.isFeatureAllowed(LicenseFeature.highSpeedCamera, entCert),
          isTrue);
    });
  });
}
