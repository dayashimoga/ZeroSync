import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/gallery_decoder_service.dart';
import 'package:airdrop_qr/presentation/pages/scanner/image_scanner_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  group('ImageScannerView Specs', () {
    Widget buildTestHost({
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
      GalleryDecoderService? decoderServiceOverride,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: ImageScannerView(
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
            decoderServiceOverride: decoderServiceOverride,
          ),
        ),
      );
    }

    testWidgets(
        'Renders header card, action buttons, and preprocessing choice chips',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      expect(find.text('Offline Image & Clipboard QR Decoder'), findsOneWidget);
      expect(find.text('100% AIR-GAPPED OFFLINE'), findsOneWidget);
      expect(find.text('Open Local Image'), findsOneWidget);
      expect(find.text('Paste Clipboard'), findsOneWidget);
      expect(find.byIcon(Icons.science_outlined), findsOneWidget);

      // Preprocessing chips
      expect(find.text('Auto Multi-Pass (All 5)'), findsOneWidget);
      expect(find.text('raw'), findsOneWidget);
      expect(find.text('grayscale'), findsOneWidget);
      expect(find.text('contrastMaximized'), findsOneWidget);
      expect(find.text('inverted'), findsOneWidget);
      expect(find.text('adaptiveThreshold'), findsOneWidget);
    });

    testWidgets(
        'Decodes sample image successfully and renders decoded results card',
        (tester) async {
      ScanRecord? savedRecord;

      // Mock analyzer returning a successful barcode
      final mockDecoder = GalleryDecoderService(
        analyzer: (path) async => [
          const Barcode(
            rawValue: 'https://zerosync.security/airgap-payload',
            format: BarcodeFormat.qrCode,
          ),
        ],
      );

      await tester.pumpWidget(buildTestHost(
        onSaveToVault: (record) => savedRecord = record,
        decoderServiceOverride: mockDecoder,
      ));
      await tester.pump();

      // Tap sample button
      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Assert success results card
      expect(find.textContaining('Successfully Decoded'), findsOneWidget);
      expect(find.text('QRCODE'), findsOneWidget);
      expect(find.text('https://zerosync.security/airgap-payload'),
          findsOneWidget);
      expect(find.text('Inspect Threat'), findsOneWidget);
      expect(find.text('Save to Vault'), findsOneWidget);

      // Tap Save to Vault
      await tester.tap(find.text('Save to Vault'));
      await tester.pump();

      expect(savedRecord, isNotNull);
      expect(savedRecord!.rawValue,
          equals('https://zerosync.security/airgap-payload'));
      expect(savedRecord!.tags, contains('ImageDecoder'));
    });

    testWidgets('Tapping Inspect Threat opens ThreatInspectorSheet',
        (tester) async {
      final mockDecoder = GalleryDecoderService(
        analyzer: (path) async => [
          const Barcode(
            rawValue: 'https://evil.com/login?utm_source=fb',
            format: BarcodeFormat.qrCode,
          ),
        ],
      );

      await tester.pumpWidget(buildTestHost(
        decoderServiceOverride: mockDecoder,
      ));
      await tester.pump();

      // Decode sample
      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Tap Inspect Threat
      await tester.tap(find.text('Inspect Threat'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verifies ThreatInspectorSheet is displayed
      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
      expect(
          find.text('Zero-Trust Pre-Flight Threat Inspector'), findsOneWidget);
      expect(find.textContaining('Privacy Telemetry Stripped'), findsOneWidget);
    });

    testWidgets('Select local image file dialog opens and triggers decode',
        (tester) async {
      final mockDecoder = GalleryDecoderService(
        analyzer: (path) async => [
          const Barcode(
            rawValue: 'WIFI:S:SecureAirGap;T:WPA;P:SecretPass;;',
            format: BarcodeFormat.qrCode,
          ),
        ],
      );

      await tester.pumpWidget(buildTestHost(
        decoderServiceOverride: mockDecoder,
      ));
      await tester.pump();

      // Open dialog
      await tester.tap(find.text('Open Local Image'));
      await tester.pump();

      expect(find.text('Select Local Image File'), findsOneWidget);

      // Tap Load & Decode
      await tester.tap(find.text('Load & Decode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Successfully Decoded'), findsOneWidget);
      expect(find.text('WIFI:S:SecureAirGap;T:WPA;P:SecretPass;;'),
          findsOneWidget);
    });

    testWidgets('Renders error card when decoding fails across all passes',
        (tester) async {
      // Mock analyzer returning zero barcodes
      final mockDecoder = GalleryDecoderService(
        analyzer: (path) async => <Barcode>[],
      );

      await tester.pumpWidget(buildTestHost(
        decoderServiceOverride: mockDecoder,
      ));
      await tester.pump();

      // Decode sample
      await tester.tap(find.byIcon(Icons.science_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No QR Code Resolved'), findsOneWidget);
      expect(
          find.textContaining(
              'No barcodes detected across 5 preprocessing passes.'),
          findsOneWidget);
    });

    testWidgets('Allows selecting individual preprocessing pass',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Tap contrastMaximized chip
      await tester.tap(find.text('contrastMaximized'));
      await tester.pump();

      final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'contrastMaximized'));
      expect(chip.selected, isTrue);
    });
  });
}
