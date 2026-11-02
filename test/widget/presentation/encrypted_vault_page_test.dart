import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:airdrop_qr/presentation/pages/vault/encrypted_vault_page.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockEncryptedVaultDataSource extends Mock
    implements EncryptedVaultDataSource {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      ScanRecord.create(
        rawValue: 'fallback',
        format: 'QR_CODE',
        contentType: 'text',
      ),
    );
  });

  group('EncryptedVaultPage Specs', () {
    late MockEncryptedVaultDataSource mockVault;
    late List<ScanRecord> mockRecords;

    setUp(() {
      mockVault = MockEncryptedVaultDataSource();
      mockRecords = [
        ScanRecord.create(
          rawValue: 'https://zerosync.security/airgap-protocol',
          format: 'QR_CODE',
          contentType: 'url',
          title: 'ZeroSync Optical Protocol',
          tags: const ['Documentation', 'AuditControl'],
        ),
        ScanRecord.create(
          rawValue: 'WIFI:S:SecureAirGapNet;T:WPA;P:TopSecretPass;;',
          format: 'QR_CODE',
          contentType: 'wifi',
          title: 'AirGap Secure Wi-Fi',
          tags: const ['Network'],
        ),
        ScanRecord.create(
          rawValue: 'BEGIN:VCARD\nFN:Alice Smith\nTEL:5550199\nEND:VCARD',
          format: 'QR_CODE',
          contentType: 'vcard',
          title: 'Alice Smith Contact',
          tags: const ['Corporate'],
        ),
      ];

      when(() => mockVault.getAllScans())
          .thenAnswer((_) async => List.of(mockRecords));
      when(() => mockVault.deleteScan(any())).thenAnswer((inv) async {
        final id = inv.positionalArguments.first as String;
        mockRecords.removeWhere((r) => r.id == id);
      });
      when(() => mockVault.insertScan(any())).thenAnswer((inv) async {
        final record = inv.positionalArguments.first as ScanRecord;
        mockRecords.add(record);
        return record;
      });
      when(() => mockVault.clearAllScans()).thenAnswer((_) async {
        final count = mockRecords.length;
        mockRecords.clear();
        return count;
      });
    });

    Widget buildTestHost({ValueChanged<String>? onActionDispatched}) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: EncryptedVaultPage(
          vaultOverride: mockVault,
          onActionDispatched: onActionDispatched,
        ),
      );
    }

    testWidgets('Renders vault title, actions, and list of records',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Encrypted SQLCipher Vault'), findsOneWidget);
      expect(find.byTooltip('Generate Forensic Audit Seal'), findsOneWidget);
      expect(find.byTooltip('Export Vault Records'), findsOneWidget);
      expect(find.byTooltip('Purge Encrypted Vault'), findsOneWidget);

      // Verifies all 3 records are listed
      expect(find.text('ZeroSync Optical Protocol'), findsOneWidget);
      expect(find.text('AirGap Secure Wi-Fi'), findsOneWidget);
      expect(find.text('Alice Smith Contact'), findsOneWidget);
    });

    testWidgets('Filters vault records via search query', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Enter search query
      await tester.enterText(
        find.widgetWithText(TextField, 'Search encrypted vault records...'),
        'Secure Wi-Fi',
      );
      await tester.pump();

      expect(find.text('AirGap Secure Wi-Fi'), findsOneWidget);
      expect(find.text('ZeroSync Optical Protocol'), findsNothing);
      expect(find.text('Alice Smith Contact'), findsNothing);
    });

    testWidgets('Filters vault records via category choice chip',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap 'URL' category chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'URL'));
      await tester.pump();

      expect(find.text('ZeroSync Optical Protocol'), findsOneWidget);
      expect(find.text('AirGap Secure Wi-Fi'), findsNothing);
      expect(find.text('Alice Smith Contact'), findsNothing);
    });

    testWidgets('Tapping Inspect Threat opens ThreatInspectorSheet',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Inspect Threat on the first record
      await tester.tap(find.text('Inspect Threat').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
      expect(
          find.text('Zero-Trust Pre-Flight Threat Inspector'), findsOneWidget);
    });

    testWidgets('Generates tamper-evident forensic audit seal dialog',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap forensic audit seal icon button
      await tester.tap(find.byTooltip('Generate Forensic Audit Seal'));
      await tester.pump();

      expect(find.text('Tamper-Evident Forensic Audit Seal'), findsOneWidget);
      expect(find.text('Cryptographic SHA-256 Digest Seal:'), findsOneWidget);
      expect(find.text('Copy Forensic Certificate'), findsOneWidget);

      // Copy certificate
      await tester.tap(find.text('Copy Forensic Certificate'));
      await tester.pump();

      expect(
        find.text(
            'Tamper-evident forensic audit certificate copied to clipboard.'),
        findsOneWidget,
      );
    });

    testWidgets('Deletes an individual record from the vault', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('ZeroSync Optical Protocol'), findsOneWidget);

      // Tap delete on the first record
      await tester.tap(find.byTooltip('Delete Record').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVault.deleteScan(any())).called(1);
      expect(find.text('ZeroSync Optical Protocol'), findsNothing);
    });

    testWidgets('Renders empty state when vault has no records',
        (tester) async {
      mockRecords.clear();

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No Encrypted Records Found'), findsOneWidget);
      expect(find.text('Insert Sample Auditable Record'), findsOneWidget);

      // Tap insert sample record
      await tester.tap(find.text('Insert Sample Auditable Record'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVault.insertScan(any())).called(1);
    });
  });
}
