import 'package:airdrop_qr/main.dart';
import 'package:airdrop_qr/presentation/pages/optical/optical_transfer_page.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnifiedPlatformShell Navigation & Adaptive Layout Specs', () {
    testWidgets(
        'Renders desktop/tablet layout with NavigationRail on wide screen (>= 720dp)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verifies NavigationRail exists
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Verifies all 5 destinations are listed
      expect(find.text('Scanner (Ctrl+1)'), findsOneWidget);
      expect(find.text('Generator (Ctrl+2)'), findsOneWidget);
      expect(find.text('Optical Transfer (Ctrl+3)'), findsOneWidget);
      expect(find.text('Vault (Ctrl+4)'), findsOneWidget);
      expect(find.text('Enterprise (Ctrl+5)'), findsOneWidget);

      // Default active workspace is Scanner (Workspace 0)
      expect(find.text('Multi-Modal QR Scanner'), findsOneWidget);
    });

    testWidgets(
        'Renders mobile layout with bottom NavigationBar on compact screen (< 720dp)',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verifies NavigationBar exists on compact viewport
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      // Verifies mobile labels
      expect(find.text('Scanner'), findsWidgets);
      expect(find.text('Generator'), findsOneWidget);
      expect(find.text('Optical'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Policy'), findsOneWidget);
    });

    testWidgets(
        'Switches between all 5 workspaces seamlessly using navigation destinations',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Initial workspace: Scanner
      expect(find.text('Multi-Modal QR Scanner'), findsOneWidget);

      // 2. Switch to Generator (Workspace 1)
      await tester.tap(find.text('Generator (Ctrl+2)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Universal & Enterprise QR Generator'), findsOneWidget);

      // 3. Switch to Optical Transfer (Workspace 2)
      await tester.tap(find.text('Optical Transfer (Ctrl+3)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(OpticalTransferPage), findsOneWidget);
      expect(find.text('HARDENED ZERO-TRUST AIR-GAP'), findsOneWidget);
      expect(find.text('Air-gap optical link ready. Point camera at source.'),
          findsOneWidget);

      // 4. Switch to Vault (Workspace 3)
      await tester.tap(find.text('Vault (Ctrl+4)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Encrypted Vault & Forensic Audit'), findsOneWidget);

      // 5. Switch to Enterprise (Workspace 4)
      await tester.tap(find.text('Enterprise (Ctrl+5)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Enterprise Policy & Licensing Center'), findsOneWidget);
      expect(find.text('COMMUNITY EDITION'), findsWidgets);
    });

    testWidgets('Switches workspaces via keyboard shortcuts (Ctrl+1 to Ctrl+5)',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(const ZeroSyncApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Initially in Scanner (Workspace 0)
      expect(find.text('Multi-Modal QR Scanner'), findsOneWidget);

      // Press Ctrl+2 -> Generator
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Universal & Enterprise QR Generator'), findsOneWidget);

      // Press Ctrl+4 -> Vault
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Encrypted Vault & Forensic Audit'), findsOneWidget);

      // Press Ctrl+1 -> Scanner
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Multi-Modal QR Scanner'), findsOneWidget);
    });

    testWidgets(
        'Hides mobile-only flashlight torch and camera flip on desktop platform',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ZeroSyncApp(
          theme: ZeroSyncTheme.oledBlackTheme.copyWith(
            platform: TargetPlatform.windows,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Mobile torch & flip buttons must NOT be present on Windows desktop
      expect(find.byTooltip('Toggle Flashlight'), findsNothing);
      expect(find.byTooltip('Switch Camera'), findsNothing);
    });
  });
}
