import 'dart:typed_data';

import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/payload_encryption_service.dart';
import 'package:airdrop_qr/presentation/pages/generator/enterprise_generator_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTestEncryptionService extends PayloadEncryptionService {
  @override
  Future<EncryptedPayloadEnvelope> encryptWithPassphrase({
    required Uint8List plaintext,
    required String passphrase,
    Uint8List? salt,
    List<int> aad = const [],
  }) async {
    return EncryptedPayloadEnvelope(
      salt: Uint8List(16)..fillRange(0, 16, 0xAA),
      nonce: Uint8List(24)..fillRange(0, 24, 0xBB),
      mac: Uint8List(16)..fillRange(0, 16, 0xCC),
      ciphertext: Uint8List.fromList(plaintext),
    );
  }
}

void main() {
  group('EnterpriseGeneratorView Specs', () {
    Widget buildTestHost({
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
      PayloadEncryptionService? encryptionService,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: EnterpriseGeneratorView(
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
            encryptionServiceOverride:
                encryptionService ?? _FakeTestEncryptionService(),
          ),
        ),
      );
    }

    testWidgets(
        'Renders schema selection chips, preview card, and action buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Schemas
      expect(find.text('TOTP Authenticator'), findsOneWidget);
      expect(find.text('Web3 Crypto Payment'), findsOneWidget);
      expect(find.text('SLIP-39 Shamir Deck'), findsOneWidget);
      expect(find.text('XChaCha20 Envelope'), findsOneWidget);

      // Actions
      expect(find.text('Copy Payload'), findsOneWidget);
      expect(find.text('Inspect Threat'), findsOneWidget);
      expect(find.text('Save to Vault'), findsOneWidget);
    });

    testWidgets('Generates valid RFC 6238 TOTP Key URI', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Default TOTP Key URI preview
      expect(find.textContaining('otpauth://totp/'), findsOneWidget);
      expect(find.textContaining('secret=JBSWY3DPEHPK3PXP'), findsOneWidget);

      // Modify Account field
      await tester.enterText(
        find.widgetWithText(TextField, 'sec-admin@zerosync.corp'),
        'ops-lead@airgap.internal',
      );
      await tester.pump();

      expect(find.textContaining('ops-lead%40airgap.internal'), findsOneWidget);
    });

    testWidgets('Switches to Web3 Crypto and generates Bitcoin BIP-21 URI',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Web3 Crypto Payment'));
      await tester.pump();

      // Crypto options visible
      expect(find.text('Bitcoin (BIP-21)'), findsOneWidget);
      expect(find.text('Ethereum (EIP-681)'), findsOneWidget);
      expect(find.text('Solana Pay'), findsOneWidget);

      // Default Bitcoin URI
      expect(
        find.textContaining(
            'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.05'),
        findsOneWidget,
      );
    });

    testWidgets('Switches to Ethereum in Web3 Mode and generates EIP-681 URI',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Web3 Crypto Payment'));
      await tester.pump();

      await tester.tap(find.text('Ethereum (EIP-681)'));
      await tester.pump();

      expect(
        find.textContaining(
            'ethereum:0x71C7656EC7ab88b098defB751B7401B5f6d8976F?value=1.25e18'),
        findsOneWidget,
      );
    });

    testWidgets('Switches to Solana in Web3 Mode and generates Solana Pay URI',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Web3 Crypto Payment'));
      await tester.pump();

      await tester.tap(find.text('Solana Pay'));
      await tester.pump();

      expect(
        find.textContaining(
            'solana:7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU?amount=10.5'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Switches to SLIP-39 Shamir Deck, verifies threshold sharing & carousel navigation',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('SLIP-39 Shamir Deck'));
      await tester.pump();

      // Initial share 1 of 3
      expect(find.text('Share 1 of 3 (Threshold: 2-of-3)'), findsOneWidget);
      expect(find.textContaining('slip39://'), findsOneWidget);

      // Navigate to share 2
      await tester.tap(find.byIcon(Icons.arrow_forward_ios));
      await tester.pump();

      expect(find.text('Share 2 of 3 (Threshold: 2-of-3)'), findsOneWidget);
    });

    testWidgets(
        'Switches to Encrypted Payload Envelope, executes Argon2id key derivation and encryption',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('XChaCha20 Envelope'));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('encrypt_payload_button')), findsOneWidget);

      await tester
          .ensureVisible(find.byKey(const ValueKey('encrypt_payload_button')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('encrypt_payload_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Envelope Preamble: 0x5A45'), findsOneWidget);
      expect(find.textContaining('ze://'), findsOneWidget);
    });

    testWidgets('Tapping Save to Vault fires onSaveToVault callback',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ScanRecord? savedRecord;
      await tester.pumpWidget(buildTestHost(
        onSaveToVault: (record) => savedRecord = record,
      ));
      await tester.pump();

      await tester.tap(find.text('Save to Vault'));
      await tester.pump();

      expect(savedRecord, isNotNull);
      expect(savedRecord!.contentType, 'ENTERPRISE_TOTP');
      expect(savedRecord!.tags, contains('Enterprise'));
      expect(
        find.textContaining(
            'Saved "Enterprise TOTP Authenticator" to SQLCipher vault.'),
        findsOneWidget,
      );
    });
  });
}
