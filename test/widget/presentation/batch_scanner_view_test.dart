import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/blocs/batch_scanner/batch_scanner_bloc.dart';
import 'package:airdrop_qr/presentation/pages/scanner/batch_scanner_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BatchScannerView Specs', () {
    Widget buildTestHost({
      BatchScannerBloc? batchBloc,
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: BatchScannerView(
            batchBlocOverride: batchBloc,
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
          ),
        ),
      );
    }

    testWidgets(
        'Renders telemetry header, ingestion controls, and empty state prompt',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Verifies streaming status and counters
      expect(find.text('STREAMING'), findsOneWidget);
      expect(find.text('Items: 0'), findsOneWidget);
      expect(find.text('Suppressed: 0'), findsOneWidget);

      // Verifies action controls
      expect(find.byTooltip('Pause Ingestion'), findsOneWidget);
      expect(find.byTooltip('Clear Batch'), findsOneWidget);
      expect(find.byTooltip('Export CSV to Clipboard'), findsOneWidget);
      expect(find.text('Commit'), findsOneWidget);

      // Verifies empty state prompt
      expect(find.text('Continuous Batch Ingestion Ready'), findsOneWidget);
    });

    testWidgets(
        'Ingests novel barcodes and suppresses immediate duplicates in feed',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // 1. Enter and ingest first barcode
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'INV-SKU-1001',
      );
      await tester.pump();

      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifies 1 item in feed
      expect(find.text('Items: 1'), findsOneWidget);
      expect(find.text('INV-SKU-1001'), findsOneWidget);
      expect(find.text('TEXT'), findsOneWidget);

      // 2. Ingest the same barcode immediately (within debounce window)
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'INV-SKU-1001',
      );
      await tester.pump();

      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Items count should still be 1, duplicate suppressed
      expect(find.text('Items: 1'), findsOneWidget);
      expect(find.text('Suppressed: 1'), findsOneWidget);

      // 3. Ingest a second distinct code
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'https://zerosync.security/airgap',
      );
      await tester.pump();

      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifies 2 unique items in feed
      expect(find.text('Items: 2'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('https://zerosync.security/airgap'), findsOneWidget);
    });

    testWidgets(
        'Tapping Inspect Threat on a feed item opens ThreatInspectorSheet',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Ingest URL item
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'https://example.com/checkout?utm_campaign=blackfriday',
      );
      await tester.pump();
      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap inspect threat icon on the card
      await tester.tap(find.byTooltip('Inspect Threat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verifies ThreatInspectorSheet is displayed
      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
      expect(
          find.text('Zero-Trust Pre-Flight Threat Inspector'), findsOneWidget);
      expect(find.textContaining('Privacy Telemetry Stripped'), findsOneWidget);
    });

    testWidgets('Toggles pause and resume ingestion status', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      expect(find.text('STREAMING'), findsOneWidget);

      // Tap Pause
      await tester.tap(find.byTooltip('Pause Ingestion'));
      await tester.pump();

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.byTooltip('Resume Ingestion'), findsOneWidget);

      // Tap Resume
      await tester.tap(find.byTooltip('Resume Ingestion'));
      await tester.pump();

      expect(find.text('STREAMING'), findsOneWidget);
    });

    testWidgets('Removes an individual item from the feed', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Ingest item
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'REMOVE-ME-123',
      );
      await tester.pump();
      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('REMOVE-ME-123'), findsOneWidget);
      expect(find.text('Items: 1'), findsOneWidget);

      // Tap remove button
      await tester.tap(find.byTooltip('Remove from Batch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('REMOVE-ME-123'), findsNothing);
      expect(find.text('Items: 0'), findsOneWidget);
    });

    testWidgets('Clears all items in batch session', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Ingest item
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'CODE-A',
      );
      await tester.pump();
      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Items: 1'), findsOneWidget);

      // Clear batch
      await tester.tap(find.byTooltip('Clear Batch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Items: 0'), findsOneWidget);
      expect(find.text('Continuous Batch Ingestion Ready'), findsOneWidget);
    });

    testWidgets('Exports CSV format of batch items', (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Ingest item
      await tester.enterText(
        find.widgetWithText(TextField, 'Scan or type barcode to ingest...'),
        'SKU-9900',
      );
      await tester.pump();
      await tester.tap(find.text('Ingest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap export CSV
      await tester.tap(find.byTooltip('Export CSV to Clipboard'));
      await tester.pump();

      expect(find.text('Exported 1 batch items as CSV (copied to clipboard).'),
          findsOneWidget);
    });
  });
}
