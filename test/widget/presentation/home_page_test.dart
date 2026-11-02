import 'package:airdrop_qr/main.dart';
import 'package:airdrop_qr/presentation/pages/home_page.dart';
import 'package:airdrop_qr/presentation/widgets/optical_animation_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ZeroSyncHomePage Widget & Startup Telemetry Specs', () {
    testWidgets(
        'ZeroSyncApp launches with honest idle state and zero pre-populated green blocks',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verifies app shell, branding & security card
      expect(find.byType(ZeroSyncHomePage), findsOneWidget);
      expect(find.text('ZeroSync'), findsOneWidget);
      expect(find.text('AIR-GAPPED'), findsOneWidget);
      expect(find.text('HARDENED ZERO-TRUST AIR-GAP'), findsOneWidget);

      // Verifies honest idle telemetry: 0 chunks, 0.0%, no green tiles
      expect(find.text('Waiting for incoming stream...'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('0 / 0 Chunks'), findsOneWidget);
      expect(find.text('ETA: --'), findsOneWidget);

      // Verifies DEFECT ABSENCE: Fake 32 chunks and fake completion banner do NOT exist
      expect(find.text('32 / 32 Chunks'), findsNothing);
      expect(find.text('Transfer complete! Payload verified.'), findsNothing);
      expect(find.text('45.2 KB/s'), findsNothing);
      expect(find.text('32'), findsNothing); // Tile 32
    });

    testWidgets(
        'Toggles between Receiver and Transmitter modes and prepares sample payload',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Initially in Receiver mode
      expect(find.byTooltip('Switch to Transmitter Mode'), findsOneWidget);

      // 2. Tap toggle to switch to Transmitter Mode
      await tester.tap(find.byTooltip('Switch to Transmitter Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 3. Verify transmitter setup view is displayed
      expect(find.text('Visual ZeroSync Transmitter'), findsOneWidget);
      final selectButton = find.text('Select File for Optical Transfer');
      expect(selectButton, findsOneWidget);

      // 4. Tap Select File button - opens bottom sheet
      await tester.tap(selectButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Select Optical Transfer Payload'), findsOneWidget);
      expect(find.text('Sample Zero-Trust Attestation (2.5 KB JSON)'),
          findsOneWidget);

      // 5. Select sample attestation payload
      await tester
          .tap(find.text('Sample Zero-Trust Attestation (2.5 KB JSON)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 6. Verify optical emitter animation player is active with sliced chunks
      expect(find.byType(OpticalAnimationPlayer), findsOneWidget);
      expect(
          find.textContaining('zerosync_airgap_manifest.json'), findsWidgets);

      // 7. Tap Reset Session button
      await tester.tap(find.byTooltip('Reset Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 8. Verify restored to idle state
      expect(find.text('Visual ZeroSync Transmitter'), findsOneWidget);
      expect(find.text('Waiting for incoming stream...'), findsOneWidget);
    });
  });
}
