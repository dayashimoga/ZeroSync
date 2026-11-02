import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/blocs/optical_session/optical_session_bloc.dart';
import 'package:airdrop_qr/presentation/pages/optical/optical_transfer_page.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/optical_animation_player.dart';
import 'package:airdrop_qr/presentation/widgets/rgb_multiplex_qr_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpticalTransferPage Specs', () {
    Widget buildTestHost({
      OpticalSessionBloc? bloc,
      ValueChanged<ScanRecord>? onSaveToVault,
      ValueChanged<String>? onActionDispatched,
    }) {
      return MaterialApp(
        theme: ZeroSyncTheme.oledBlackTheme,
        home: Scaffold(
          body: OpticalTransferPage(
            bloc: bloc,
            onSaveToVault: onSaveToVault,
            onActionDispatched: onActionDispatched,
          ),
        ),
      );
    }

    testWidgets(
        'Starts in Receiver mode with honest idle telemetry (0 chunks, 0.0%)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('ZeroSync Optical Transfer'), findsOneWidget);
      expect(find.text('RECEIVER'), findsOneWidget);
      expect(find.text('HARDENED ZERO-TRUST AIR-GAP'), findsOneWidget);
      expect(find.text('Transfer Session Telemetry'), findsOneWidget);
      expect(find.text('0 / 0 Chunks'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.text('Air-gap optical link ready. Point camera at source.'),
          findsOneWidget);
    });

    testWidgets(
        'Switches to Transmitter mode and renders transmitter CTA and action buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to Transmitter
      await tester.tap(find.byTooltip('Switch to Transmitter Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('TRANSMITTER'), findsOneWidget);
      expect(find.text('Visual ZeroSync Transmitter'), findsOneWidget);
      expect(find.text('Select File for Optical Transfer'), findsOneWidget);
    });

    testWidgets(
        'Prepares sample payload, triggers Transport Advisor, and mounts OpticalAnimationPlayer',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to Transmitter
      await tester.tap(find.byTooltip('Switch to Transmitter Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open picker
      await tester.tap(find.text('Select File for Optical Transfer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Select sample payload
      await tester.tap(find.textContaining('Sample Zero-Trust Attestation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Transport advisor card
      expect(find.textContaining('Transport Advisor:'), findsOneWidget);

      // Optical animation player
      expect(find.byType(OpticalAnimationPlayer), findsOneWidget);
      expect(
          find.textContaining(
              'zerosync_airgap_manifest.json (393 B • 3 Chunks)'),
          findsOneWidget);
    });

    testWidgets('Toggles 3x RGB Spectral Multiplex Mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to Transmitter
      await tester.tap(find.byTooltip('Switch to Transmitter Mode'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Open picker and select sample
      await tester.tap(find.text('Select File for Optical Transfer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('Sample Zero-Trust Attestation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Switch to RGB Mode
      await tester.tap(find.text('Switch to 3x RGB Burst'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(RgbMultiplexQrWidget), findsOneWidget);
      expect(find.text('Switch to Monochrome'), findsOneWidget);
    });

    testWidgets(
        'Simulates completed transfer and verifies cryptographic success card and vault commit',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bloc = OpticalSessionBloc();
      addTearDown(bloc.close);

      ScanRecord? committedRecord;
      await tester.pumpWidget(buildTestHost(
        bloc: bloc,
        onSaveToVault: (record) => committedRecord = record,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Prepare a tiny 1-chunk payload
      const testContent = 'ZeroSync Verified Air-Gap Transport Stream';
      final testBytes = Uint8List.fromList(utf8.encode(testContent));
      bloc.add(
        OpticalSessionPayloadPrepared(
          fileName: 'verified_manifest.json',
          fileBytes: testBytes,
          chunkSize: 500,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ingest frame 0 (completes transfer)
      final state = bloc.state;
      if (state is OpticalSessionTransmitting &&
          state.framePayloads.isNotEmpty) {
        bloc.add(const OpticalSessionModeChanged(0)); // Switch to Receiver
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        bloc.add(OpticalSessionFrameIngested(state.framePayloads.first));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(find.text('Cryptographic Validation Succeeded'), findsOneWidget);
      expect(find.text('Save to Encrypted Vault'), findsOneWidget);

      await tester.tap(find.text('Save to Encrypted Vault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(committedRecord, isNotNull);
      expect(committedRecord!.format, 'OPTICAL_FOUNTAIN_STREAM');
      expect(committedRecord!.tags, contains('Verified'));
    });

    testWidgets('Resets optical session back to idle', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHost());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byTooltip('Reset Optical Session'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('0 / 0 Chunks'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
    });
  });
}
