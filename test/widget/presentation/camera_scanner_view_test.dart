import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/pages/scanner/camera_scanner_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraScannerView & ThreatInspectorSheet Specs', () {
    Widget buildTestHost({
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: CameraScannerView(
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
          ),
        ),
      );
    }

    Future<void> pumpTransition(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
        'Renders camera scanner viewport, zero-trust badge, and manual payload button',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verifies zero-trust scanner badge
      expect(find.text('ZERO-TRUST SCANNER'), findsOneWidget);

      // Verifies manual entry button
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
    });

    testWidgets(
        'Manual payload entry with tracking triggers ThreatInspectorSheet with stripped trackers',
        (tester) async {
      ScanRecord? savedRecord;

      await tester.pumpWidget(buildTestHost(
        onSaveToVault: (record) => savedRecord = record,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Open manual payload dialog
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await pumpTransition(tester);

      expect(find.text('Manual Payload Inspection'), findsOneWidget);

      // 2. Enter payload with tracker parameter
      await tester.enterText(
        find.byType(TextField),
        'https://example.com/login?utm_source=fb&user=alice',
      );
      await tester.pump();

      // 3. Tap 'Inspect Threat'
      await tester.tap(find.text('Inspect Threat'));
      await pumpTransition(tester);

      // 4. Verify ThreatInspectorSheet is rendered
      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
      expect(
          find.text('Zero-Trust Pre-Flight Threat Inspector'), findsOneWidget);

      // 5. Verify tracker stripping detected
      expect(
        find.textContaining('Privacy Telemetry Stripped'),
        findsOneWidget,
      );
      expect(
        find.text('Removed Tracking Identifiers: utm_source'),
        findsOneWidget,
      );

      // 6. Test 'Save to Vault' button
      expect(find.text('Save to Vault'), findsOneWidget);
      await tester.tap(find.text('Save to Vault'));
      await pumpTransition(tester);

      expect(savedRecord, isNotNull);
      expect(savedRecord!.rawValue,
          contains('https://example.com/login?user=alice'));
      expect(savedRecord!.tags, contains('Scanner'));
    });

    testWidgets('Inspects clean payload and triggers sandboxed dispatch',
        (tester) async {
      String? dispatchedPayload;

      await tester.pumpWidget(buildTestHost(
        onActionDispatched: (payload) => dispatchedPayload = payload,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Open manual payload entry
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await pumpTransition(tester);

      // 2. Enter clean URL
      await tester.enterText(
        find.byType(TextField),
        'https://zerosync.security/docs',
      );
      await tester.pump();

      // 3. Inspect
      await tester.tap(find.text('Inspect Threat'));
      await pumpTransition(tester);

      // 4. Verify clean status
      expect(find.text('ZERO DETECTED THREATS (CLEAN)'), findsOneWidget);

      // 5. Verify Dispatch button
      final dispatchButton = find.text('Dispatch');
      expect(dispatchButton, findsOneWidget);

      await tester.tap(dispatchButton);
      await pumpTransition(tester);

      expect(dispatchedPayload, equals('https://zerosync.security/docs'));
    });

    testWidgets(
        'Renders last scanned payload pill and re-opens inspector on tap',
        (tester) async {
      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Enter manual payload
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await pumpTransition(tester);

      await tester.enterText(
        find.byType(TextField),
        'https://zerosync.security/airgap',
      );
      await tester.pump();

      await tester.tap(find.text('Inspect Threat'));
      await pumpTransition(tester);

      // Close inspector via close button
      await tester.tap(find.byTooltip('Dismiss Inspector'));
      await pumpTransition(tester);

      // Verify last scanned pill is visible
      expect(find.textContaining('Last: https://zerosync.security/airgap'),
          findsOneWidget);

      // Tap the pill to re-open inspector
      await tester
          .tap(find.textContaining('Last: https://zerosync.security/airgap'));
      await pumpTransition(tester);

      expect(find.byType(ThreatInspectorSheet), findsOneWidget);
    });
  });
}
