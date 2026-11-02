import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/enterprise_policy.dart';
import 'package:airdrop_qr/domain/entities/license_certificate.dart';
import 'package:airdrop_qr/domain/services/duress_manager_service.dart';
import 'package:airdrop_qr/domain/services/enterprise_policy_service.dart';
import 'package:airdrop_qr/domain/services/license_verifier_service.dart';

void main() {
  group('EnterprisePolicyService Specs', () {
    late EnterprisePolicyService policyService;
    late SimpleKeyPair testKeyPair;
    late Uint8List testPublicKeyBytes;
    late LicenseVerifierService verifierService;

    setUp(() async {
      final ed25519 = Ed25519();
      testKeyPair = await ed25519.newKeyPair();
      final pubKey = await testKeyPair.extractPublicKey();
      testPublicKeyBytes = Uint8List.fromList(pubKey.bytes);

      verifierService = LicenseVerifierService(
        pinnedPublicKey: testPublicKeyBytes,
        ed25519: ed25519,
      );

      policyService = EnterprisePolicyService(
        verifierService: verifierService,
      );
    });

    test('Defaults to Community Edition with restricted enterprise features',
        () {
      expect(policyService.effectiveTier, equals(LicenseTier.community));
      expect(policyService.isTrialActive, isFalse);
      expect(policyService.maxOpticalTransferMb, equals(10));

      // Community features allowed
      expect(policyService.isFeatureAllowed('cameraScanner'), isTrue);
      expect(policyService.isFeatureAllowed('imageScanner'), isTrue);
      expect(policyService.isFeatureAllowed('standardGenerator'), isTrue);

      // Enterprise / Pro features denied
      expect(policyService.isFeatureAllowed('batchScanner'), isFalse);
      expect(policyService.isFeatureAllowed('advancedStyler'), isFalse);
      expect(policyService.isFeatureAllowed('enterpriseStudio'), isFalse);
      expect(policyService.isFeatureAllowed('rgbMultiplexing'), isFalse);
      expect(policyService.isFeatureAllowed('forensicAudit'), isFalse);
    });

    test('Activates 14-day offline trial and elevates to Enterprise tier', () {
      final activated = policyService.activateOfflineTrial(durationDays: 14);
      expect(activated, isTrue);
      expect(policyService.isTrialActive, isTrue);
      expect(policyService.effectiveTier, equals(LicenseTier.enterprise));
      expect(policyService.maxOpticalTransferMb, equals(500));

      // All features unlocked during trial
      expect(policyService.isFeatureAllowed('batchScanner'), isTrue);
      expect(policyService.isFeatureAllowed('advancedStyler'), isTrue);
      expect(policyService.isFeatureAllowed('enterpriseStudio'), isTrue);
      expect(policyService.isFeatureAllowed('rgbMultiplexing'), isTrue);

      // Cannot activate trial a second time
      final reattempt = policyService.activateOfflineTrial();
      expect(reattempt, isFalse);
    });

    test('Installs valid cryptographic .zslic Pro license and revokes cleanly',
        () async {
      final payload = LicensePayload(
        id: 'LIC-PRO-2026',
        licensedTo: 'ZeroSync Gov User',
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        tier: LicenseTier.pro,
        features: const {
          LicenseFeature.forensicExport,
        },
      );

      final cert = await LicenseVerifierService.issueLicense(
        payload: payload,
        signingKeyPair: testKeyPair,
      );

      final encoded = cert.toEncodedString();
      final result = await policyService.installLicense(encoded);

      expect(result.isValid, isTrue);
      expect(policyService.effectiveTier, equals(LicenseTier.pro));
      expect(policyService.maxOpticalTransferMb, equals(50));
      expect(
          policyService.activeCertificate?.payload.id, equals('LIC-PRO-2026'));

      // Pro features allowed
      expect(policyService.isFeatureAllowed('batchScanner'), isTrue);
      expect(policyService.isFeatureAllowed('advancedStyler'), isTrue);
      // Enterprise feature still denied
      expect(policyService.isFeatureAllowed('enterpriseStudio'), isFalse);

      // Revocation returns to Community
      policyService.revokeLicense();
      expect(policyService.effectiveTier, equals(LicenseTier.community));
      expect(policyService.isFeatureAllowed('batchScanner'), isFalse);
    });

    test('Rejects invalidly signed license string', () async {
      const bogus = 'zerosync:lic:v1:eyJpZCI6IiJ9.bogussig';
      final result = await policyService.installLicense(bogus);
      expect(result.isValid, isFalse);
      expect(policyService.effectiveTier, equals(LicenseTier.community));
    });

    test('Granular feature toggles can override tier allowance', () {
      // Community feature toggled off
      expect(policyService.isFeatureAllowed('cameraScanner'), isTrue);
      policyService.setFeatureToggle('cameraScanner', false);
      expect(policyService.isFeatureAllowed('cameraScanner'), isFalse);
      expect(policyService.getFeatureToggle('cameraScanner'), isFalse);

      policyService.setFeatureToggle('cameraScanner', true);
      expect(policyService.isFeatureAllowed('cameraScanner'), isTrue);
    });

    test('Enforces security policies: mandatory encryption and retention', () {
      expect(policyService.mandatoryEncryption, isFalse);
      policyService.setMandatoryEncryption(true);
      expect(policyService.mandatoryEncryption, isTrue);

      expect(policyService.strictAirgapLockdown, isTrue);
      policyService.setStrictAirgapLockdown(false);
      expect(policyService.strictAirgapLockdown, isFalse);

      expect(policyService.retentionPolicy,
          equals(AuditRetentionPolicy.retainForever));
      policyService.setRetentionPolicy(AuditRetentionPolicy.purge7Days);
      expect(policyService.retentionPolicy,
          equals(AuditRetentionPolicy.purge7Days));
    });

    test(
        'Configures Duress Manager and detects Panic PIN under physical coercion',
        () {
      policyService.configureDuressPins(
        primaryPin: '1234',
        duressPin: '9999',
        autoScrubRealKeyOnDuress: true,
      );

      final snapshot = policyService.snapshot;
      expect(snapshot.isDuressConfigured, isTrue);
      expect(snapshot.isDuressActive, isFalse);

      // Normal authentication
      final normal = policyService.evaluateDuressPin('1234');
      expect(normal, equals(PinAuthResult.primaryAccess));
      expect(policyService.snapshot.isDuressActive, isFalse);

      // Under duress authentication
      final panic = policyService.evaluateDuressPin('9999');
      expect(panic, equals(PinAuthResult.duressPanicTriggered));
      expect(policyService.snapshot.isDuressActive, isTrue);
    });
  });
}
