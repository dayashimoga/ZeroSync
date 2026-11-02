import 'dart:typed_data';
import 'package:airdrop_qr/domain/entities/license_certificate.dart';
import 'package:airdrop_qr/domain/services/enterprise_policy_service.dart';
import 'package:airdrop_qr/domain/services/license_verifier_service.dart';
import 'package:airdrop_qr/presentation/pages/enterprise/enterprise_policy_page.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnterprisePolicyPage Widget Specs', () {
    late EnterprisePolicyService policyService;
    late SimpleKeyPair testKeyPair;
    late Uint8List testPublicKeyBytes;

    setUp(() async {
      final ed25519 = Ed25519();
      testKeyPair = await ed25519.newKeyPair();
      final pubKey = await testKeyPair.extractPublicKey();
      testPublicKeyBytes = Uint8List.fromList(pubKey.bytes);

      final verifierService = LicenseVerifierService(
        pinnedPublicKey: testPublicKeyBytes,
        ed25519: ed25519,
      );

      policyService = EnterprisePolicyService(
        verifierService: verifierService,
      );
    });

    Widget buildTestHost({EnterprisePolicyService? service}) {
      return MaterialApp(
        home: EnterprisePolicyPage(
          policyService: service ?? policyService,
        ),
      );
    }

    testWidgets(
        'Renders Community Edition status, policies, and feature matrix',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Header and active tier badge
      expect(find.text('Enterprise Policy & Licensing Center'), findsOneWidget);
      expect(find.text('COMMUNITY EDITION'), findsWidgets);

      // Trial activation banner present
      expect(find.text('14-Day Offline Enterprise Trial'), findsOneWidget);
      expect(find.text('Activate Trial'), findsOneWidget);

      // Security policies
      expect(
          find.text('Security Policies & Air-Gap Invariants'), findsOneWidget);
      expect(find.text('Mandatory Payload Encryption'), findsOneWidget);
      expect(find.text('Strict Air-Gap SCIF Lockdown'), findsOneWidget);

      // Duress section
      expect(find.text('Duress Panic Guard & Decoy Mode'), findsOneWidget);
      expect(find.text('NOT CONFIGURED'), findsOneWidget);
    });

    testWidgets('Activates 14-Day Offline Enterprise Trial', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Tap Activate Trial
      await tester.tap(find.text('Activate Trial'));
      await tester.pumpAndSettle();

      // Banner should disappear and tier badge should show ENTERPRISE
      expect(find.text('ENTERPRISE EDITION'), findsWidgets);
      expect(policyService.isTrialActive, isTrue);
      expect(
          find.textContaining('Active 14-Day Offline Trial'), findsOneWidget);
    });

    testWidgets('Toggles security policies and retention dropdown',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Toggle mandatory encryption
      final encryptionSwitch = find.ancestor(
        of: find.text('Mandatory Payload Encryption'),
        matching: find.byType(SwitchListTile),
      );
      expect(encryptionSwitch, findsOneWidget);
      await tester.tap(encryptionSwitch);
      await tester.pumpAndSettle();
      expect(policyService.mandatoryEncryption, isTrue);

      // Toggle strict air-gap
      final airgapSwitch = find.ancestor(
        of: find.text('Strict Air-Gap SCIF Lockdown'),
        matching: find.byType(SwitchListTile),
      );
      await tester.tap(airgapSwitch);
      await tester.pumpAndSettle();
      expect(policyService.strictAirgapLockdown, isFalse);
    });

    testWidgets('Configures Duress PINs and evaluates Primary and Panic modes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Open Duress PIN configuration dialog
      await tester.tap(find.text('Configure Duress PINs'));
      await tester.pumpAndSettle();

      expect(find.text('Configure Duress Panic PINs'), findsOneWidget);

      // Enter Primary and Duress PINs
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '1234');
      await tester.enterText(textFields.at(1), '9999');
      await tester.pump();

      // Save PINs
      await tester.tap(find.text('Save PINs'));
      await tester.pumpAndSettle();

      expect(find.text('CONFIGURED'), findsOneWidget);
      expect(find.text('Test PIN'), findsOneWidget);

      // Test Primary PIN
      await tester.tap(find.text('Test PIN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1234');
      await tester.tap(find.text('Evaluate PIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Primary Access Granted'), findsOneWidget);
      expect(policyService.snapshot.isDuressActive, isFalse);

      // Dismiss snackbar
      ScaffoldMessenger.of(tester.element(find.byType(EnterprisePolicyPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Test Panic PIN
      await tester.tap(find.text('Test PIN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.tap(find.text('Evaluate PIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('DURESS PANIC TRIGGERED'), findsOneWidget);
      expect(policyService.snapshot.isDuressActive, isTrue);
      expect(find.textContaining('DECOY DURESS MODE CURRENTLY ACTIVE'),
          findsOneWidget);
    });

    testWidgets('Imports valid .zslic license and verifies tier elevation',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Generate a valid signed Pro license
      final payload = LicensePayload(
        id: 'ZS-GOV-9876',
        licensedTo: 'Department of Defense Air-Gap Unit',
        issuedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        tier: LicenseTier.pro,
        features: const {LicenseFeature.forensicExport},
      );
      final cert = await LicenseVerifierService.issueLicense(
        payload: payload,
        signingKeyPair: testKeyPair,
      );
      final encodedLic = cert.toEncodedString();

      await tester.pumpWidget(buildTestHost());
      await tester.pumpAndSettle();

      // Open Import Dialog
      await tester.tap(find.text('Import .zslic License'));
      await tester.pumpAndSettle();

      expect(find.text('Import .zslic License'), findsWidgets);

      // Paste license string and install
      await tester.enterText(find.byType(TextField), encodedLic);
      await tester.pump();
      await tester.tap(find.text('Verify & Install'));
      await tester.pumpAndSettle();

      // Should be upgraded to Pro Edition
      expect(find.text('PRO EDITION'), findsWidgets);
      expect(find.text('License ID: ZS-GOV-9876'), findsOneWidget);
      expect(find.text('Licensed to: Department of Defense Air-Gap Unit'),
          findsOneWidget);

      // Revoke button should now be visible
      expect(find.text('Revoke'), findsOneWidget);
      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();

      expect(find.text('COMMUNITY EDITION'), findsWidgets);
    });
  });
}
