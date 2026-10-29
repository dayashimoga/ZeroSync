import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/widgets/adaptive_split_pane_scaffold.dart';

void main() {
  group('AdaptiveWindowSizeClass Specs', () {
    test('Resolves correct size class across responsive breakpoints', () {
      expect(AdaptiveWindowSizeClass.fromWidth(360.0), AdaptiveWindowSizeClass.compact);
      expect(AdaptiveWindowSizeClass.fromWidth(599.0), AdaptiveWindowSizeClass.compact);
      expect(AdaptiveWindowSizeClass.fromWidth(600.0), AdaptiveWindowSizeClass.medium);
      expect(AdaptiveWindowSizeClass.fromWidth(839.0), AdaptiveWindowSizeClass.medium);
      expect(AdaptiveWindowSizeClass.fromWidth(840.0), AdaptiveWindowSizeClass.expanded);
      expect(AdaptiveWindowSizeClass.fromWidth(1200.0), AdaptiveWindowSizeClass.expanded);
    });
  });

  group('AdaptiveSplitPaneScaffold Mobile & Tablet Specs', () {
    testWidgets('Renders single-column tabbed layout on mobile (< 720px) preserving camera state', (tester) async {
      // Set compact screen size (Phone)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveSplitPaneScaffold(
            title: Text('ZeroSync Scanner'),
            primaryPane: KeyedSubtree(
              key: ValueKey('CameraPane'),
              child: Text('Live Camera Viewport'),
            ),
            secondaryPane: KeyedSubtree(
              key: ValueKey('VaultPane'),
              child: Text('Vault History Data'),
            ),
          ),
        ),
      );

      // Bottom NavigationBar present in mobile mode
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);

      // IndexedStack preserves both panes in widget tree (offstage pane retained)
      expect(find.byKey(const ValueKey('CameraPane')), findsOneWidget);
      expect(find.byKey(const ValueKey('VaultPane'), skipOffstage: false), findsOneWidget);

      // Switch to secondary tab
      await tester.tap(find.text('Vault'));
      await tester.pump();

      // CameraPane is STILL retained in memory by IndexedStack (now offstage)!
      expect(find.byKey(const ValueKey('CameraPane'), skipOffstage: false), findsOneWidget);
      expect(find.text('Vault History Data'), findsOneWidget);
    });

    testWidgets('Renders dual-pane split view on tablet (>= 720px) showing both panes simultaneously', (tester) async {
      // Set tablet screen size (Tablet / Foldable unfolded)
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: AdaptiveSplitPaneScaffold(
            title: Text('ZeroSync Tablet'),
            primaryPane: KeyedSubtree(
              key: ValueKey('TabletCamera'),
              child: Text('Tablet Camera Stream'),
            ),
            secondaryPane: KeyedSubtree(
              key: ValueKey('TabletHistory'),
              child: Text('Tablet History Feed'),
            ),
            splitBreakpoint: 720.0,
            primaryRatio: 0.6,
          ),
        ),
      );

      // No bottom navigation bar on tablet
      expect(find.byType(NavigationBar), findsNothing);

      // Vertical divider present separating workspaces
      expect(find.byType(VerticalDivider), findsOneWidget);

      // Both panes visible and active simultaneously
      expect(find.byKey(const ValueKey('TabletCamera')), findsOneWidget);
      expect(find.byKey(const ValueKey('TabletHistory')), findsOneWidget);
      expect(find.text('Tablet Camera Stream'), findsOneWidget);
      expect(find.text('Tablet History Feed'), findsOneWidget);

      // Verify sizing ratio
      final cameraSize = tester.getSize(find.byKey(const ValueKey('TabletCamera')));
      expect(cameraSize.width, equals(600.0)); // 60% of 1000px
    });
  });
}
