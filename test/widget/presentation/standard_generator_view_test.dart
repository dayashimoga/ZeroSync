import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/pages/generator/standard_generator_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StandardGeneratorView Specs', () {
    Widget buildTestHost({
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: StandardGeneratorView(
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
          ),
        ),
      );
    }

    testWidgets(
        'Renders all 8 schema chips, preview canvas, and action buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Schema Chips
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('URL'), findsOneWidget);
      expect(find.text('Wi-Fi'), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
      expect(find.text('Geo'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);

      // Preview Card
      expect(find.text('Live QR Matrix Preview'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Inspect'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('Edits Text schema and updates live preview', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Enter new text
      await tester.enterText(
        find.widgetWithText(
            TextField, 'ZeroSync: Air-Gapped Optical Data Transfer'),
        'CLASSIFIED_TOP_SECRET_AIRGAP_PAYLOAD',
      );
      await tester.pump();

      expect(
          find.text('CLASSIFIED_TOP_SECRET_AIRGAP_PAYLOAD'), findsNWidgets(2));
    });

    testWidgets(
        'Selects URL schema, strips commercial tracking parameters in preview',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Switch to URL schema
      await tester.tap(find.text('URL'));
      await tester.pump();

      // Enter URL with tracker parameters
      await tester.enterText(
        find.widgetWithText(TextField, 'https://zerosync.security'),
        'https://example.com/login?utm_source=facebook&client_id=123',
      );
      await tester.pump();

      // Verifies stripped parameter badge appears
      expect(
          find.textContaining('Stripped Trackers: utm_source'), findsOneWidget);
      expect(
          find.text('https://example.com/login?client_id=123'), findsOneWidget);
    });

    testWidgets('Selects Wi-Fi schema and produces valid ZXing Wi-Fi syntax',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Switch to Wi-Fi
      await tester.tap(find.text('Wi-Fi'));
      await tester.pump();

      expect(find.text('Network SSID'), findsOneWidget);
      expect(find.text('Pre-Shared Key / Password'), findsOneWidget);

      // Verify serialized ZXing Wi-Fi payload
      expect(
        find.textContaining(
            'WIFI:T:WPA2;S:ZeroSync-AirGap;P:HardenedPassword2026;;'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Selects Contact schema and serializes RFC 6350 vCard 4.0 structure',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Switch to Contact
      await tester.tap(find.text('Contact'));
      await tester.pump();

      expect(find.text('Full Formatted Name *'), findsOneWidget);

      // Verify vCard payload preview
      expect(find.textContaining('BEGIN:VCARD'), findsOneWidget);
      expect(find.textContaining('FN:Security Officer'), findsOneWidget);
    });

    testWidgets('Tapping Inspect Threat opens ThreatInspectorSheet',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Tap Inspect button
      await tester.tap(find.text('Inspect'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
      expect(
          find.text('Zero-Trust Pre-Flight Threat Inspector'), findsOneWidget);
    });

    testWidgets('Tapping Save commits generated record to vault callback',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      ScanRecord? savedRecord;

      await tester.pumpWidget(buildTestHost(
        onSaveToVault: (record) => savedRecord = record,
      ));
      await tester.pump();

      // Tap Save button
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(savedRecord, isNotNull);
      expect(savedRecord!.rawValue,
          contains('ZeroSync: Air-Gapped Optical Data Transfer'));
      expect(savedRecord!.tags, contains('Generator'));
    });

    testWidgets('Changes ECC level chip and recomputes optimal version',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Tap 'H (30%)' choice chip
      await tester.tap(find.text('H (30%)'));
      await tester.pump();

      final chip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'H (30%)'));
      expect(chip.selected, isTrue);
    });
  });
}
