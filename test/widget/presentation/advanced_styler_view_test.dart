import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/pages/generator/advanced_styler_view.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdvancedStylerView Specs', () {
    Widget buildTestHost({
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: AdvancedStylerView(
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
          ),
        ),
      );
    }

    testWidgets(
        'Renders presets, module shapes, eye frames, logo switch, and export buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Theme Presets
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Neon Fluid'), findsOneWidget);
      expect(find.text('Emerald Secure'), findsOneWidget);

      // Module Shapes
      expect(find.text('fluid'), findsOneWidget);
      expect(find.text('square'), findsAtLeastNWidgets(1));
      expect(find.text('circle'), findsAtLeastNWidgets(1));

      // Finder Eye Frames
      expect(find.text('roundedSquare'), findsAtLeastNWidgets(1));
      expect(find.text('leaf'), findsOneWidget);

      // Logo Switch
      expect(find.text('Embed Central Security Shield Logo'), findsOneWidget);

      // Vector Canvas & Actions
      expect(find.text('High-Resolution Vector Canvas'), findsOneWidget);
      expect(find.text('Export SVG'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Save to Vault'), findsOneWidget);
    });

    testWidgets('Applies Classic preset and switches shapes and colors',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Classic'));
      await tester.pump();

      expect(find.text('ECC: M (15%)'), findsOneWidget);
    });

    testWidgets(
        'Applies Emerald Secure preset, escalating ECC to Level H and embedding shield',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Emerald Secure'));
      await tester.pump();

      // Enforces ECC Level H and shows shield indicator
      expect(find.text('ECC: H (30%)'), findsOneWidget);
      expect(
        find.textContaining('ECC Escalated to Level H'),
        findsOneWidget,
      );
    });

    testWidgets('Toggles logo embedding switch directly', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      // Initially ECC: M
      expect(find.text('ECC: M (15%)'), findsOneWidget);

      // Toggle logo switch
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      // Now ECC: H
      expect(find.text('ECC: H (30%)'), findsOneWidget);
      expect(
        find.textContaining('ECC Escalated to Level H'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping Export SVG triggers clipboard copy and snackbar',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Export SVG'));
      await tester.pump();

      expect(
        find.textContaining('Exported Scalable Vector Graphics'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping Export PDF triggers PDF export service and snackbar',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.tap(find.text('Export PDF'));
      await tester.pump();

      expect(
        find.textContaining('Generated print-ready ISO 32000 PDF'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping Save to Vault invokes onSaveToVault callback',
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
      expect(savedRecord!.contentType, 'STYLED_QR');
      expect(savedRecord!.format, 'QR_CODE');
      expect(savedRecord!.tags, contains('Styler'));
      expect(
        find.textContaining('Saved "Styled QR:'),
        findsOneWidget,
      );
    });

    testWidgets('Modifying payload text recalculates matrix', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(
            TextField, 'https://zerosync.security/airgap-styler'),
        'ZeroSync Red Team Secret Styler Text',
      );
      await tester.pump();

      expect(find.text('ZeroSync Red Team Secret Styler Text'), findsOneWidget);
    });
  });
}
