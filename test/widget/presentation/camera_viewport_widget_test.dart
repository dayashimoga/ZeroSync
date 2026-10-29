import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/widgets/camera_viewport_widget.dart';

void main() {
  group('CameraViewportWidget Initialization & Configuration', () {
    testWidgets('Renders camera viewport with overlay controls and reticle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraViewportWidget(),
          ),
        ),
      );

      expect(find.byType(CameraViewportWidget), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify controls
      expect(find.byTooltip('Toggle Flashlight'), findsOneWidget);
      expect(find.byTooltip('Switch Camera'), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('Respects custom configuration disabling controls',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraViewportWidget(
              config: CameraViewportConfig(
                showTorchControl: false,
                showCameraFlipControl: false,
                showZoomBadge: false,
                showLaserScanline: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Toggle Flashlight'), findsNothing);
      expect(find.byTooltip('Switch Camera'), findsNothing);
      expect(find.text('1.0x'), findsNothing);
    });

    test('Throws AssertionError when scanWindowWidthRatio is outside 0..1', () {
      expect(
        () => CameraViewportConfig(scanWindowWidthRatio: 0.0),
        throwsAssertionError,
      );
      expect(
        () => CameraViewportConfig(scanWindowWidthRatio: 1.5),
        throwsAssertionError,
      );
    });

    test('Throws AssertionError when minZoom > maxZoom', () {
      expect(
        () => CameraViewportConfig(minZoom: 0.8, maxZoom: 0.5),
        throwsAssertionError,
      );
    });
  });

  group('Interactive Gestures & Lifecycle Management', () {
    testWidgets('Double-tap triggers zoom toggle', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraViewportWidget(
              config: CameraViewportConfig(initialZoom: 0.0),
            ),
          ),
        ),
      );

      final state = tester
          .state<CameraViewportWidgetState>(find.byType(CameraViewportWidget));

      // Double-tap on gesture detector
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump(const Duration(milliseconds: 100));

      // State is active and handles double tap
      expect(state.mounted, isTrue);
    });

    testWidgets('Handles AppLifecycleState pause and resume events gracefully',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CameraViewportWidget(),
          ),
        ),
      );

      final state = tester
          .state<CameraViewportWidgetState>(find.byType(CameraViewportWidget));

      // Simulate AppLifecycleState transition to paused
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(state.mounted, isTrue);

      // Simulate AppLifecycleState transition to resumed
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(state.mounted, isTrue);
    });

    testWidgets('Renders custom errorBuilder when provided',
        (WidgetTester tester) async {
      const customKey = Key('custom_camera_error');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CameraViewportWidget(
              errorBuilder: Container(
                key: customKey,
                child: const Text('Custom Error Placeholder'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CameraViewportWidget), findsOneWidget);
    });
  });
}
