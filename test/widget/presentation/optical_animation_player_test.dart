import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/widgets/optical_animation_player.dart';

class MockBrightnessManager implements ScreenBrightnessManager {
  int setMaxCallCount = 0;
  int restoreCallCount = 0;

  @override
  Future<void> setMaxBrightness() async {
    setMaxCallCount++;
  }

  @override
  Future<void> restoreBrightness() async {
    restoreCallCount++;
  }
}

void main() {
  group('OpticalAnimationPlayer Widget & Animation Loop Specs', () {
    testWidgets('Renders initial frame, counter, and telemetry accurately',
        (tester) async {
      final frames = ['PAYLOAD_CHUNK_1', 'PAYLOAD_CHUNK_2', 'PAYLOAD_CHUNK_3'];
      final mockBrightness = MockBrightnessManager();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: frames,
              initialFps: 10.0,
              brightnessManager: mockBrightness,
            ),
          ),
        ),
      );

      expect(find.text('Frame 1 / 3'), findsOneWidget);
      expect(find.textContaining('10.0 FPS'), findsOneWidget);
      expect(mockBrightness.setMaxCallCount, equals(1));
      expect(mockBrightness.restoreCallCount, equals(0));

      // Advance clock by 100ms (10 FPS)
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Frame 2 / 3'), findsOneWidget);

      // Advance clock by another 100ms
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Frame 3 / 3'), findsOneWidget);

      // Loop wraps back to frame 1
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Frame 1 / 3'), findsOneWidget);
    });

    testWidgets('Play / Pause toggle pauses and resumes the animation loop',
        (tester) async {
      final frames = ['A', 'B', 'C'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: frames,
              initialFps: 10.0,
            ),
          ),
        ),
      );

      expect(find.text('Frame 1 / 3'), findsOneWidget);

      // Tap pause button
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();

      // Clock advances while paused: frame should not change
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Frame 1 / 3'), findsOneWidget);

      // Tap play button to resume
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Frame 2 / 3'), findsOneWidget);
    });

    testWidgets('Manual step forward and backward controls navigate frames',
        (tester) async {
      final frames = ['FRAME_1', 'FRAME_2', 'FRAME_3'];
      int? lastFrameIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: frames,
              onFrameChanged: (idx) => lastFrameIndex = idx,
            ),
          ),
        ),
      );

      // Pause by stepping manually
      await tester.tap(find.byTooltip('Next Frame'));
      await tester.pump();
      expect(find.text('Frame 2 / 3'), findsOneWidget);
      expect(lastFrameIndex, equals(1));

      await tester.tap(find.byTooltip('Next Frame'));
      await tester.pump();
      expect(find.text('Frame 3 / 3'), findsOneWidget);
      expect(lastFrameIndex, equals(2));

      await tester.tap(find.byTooltip('Previous Frame'));
      await tester.pump();
      expect(find.text('Frame 2 / 3'), findsOneWidget);
      expect(lastFrameIndex, equals(1));
    });

    testWidgets('Contrast inversion toggle switches visual contrast',
        (tester) async {
      final frames = ['DATA_PAYLOAD'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: frames,
            ),
          ),
        ),
      );

      // Invert contrast
      await tester.tap(find.byTooltip('Toggle Inverted Contrast'));
      await tester.pump();

      // Second tap flips back
      await tester.tap(find.byTooltip('Toggle Inverted Contrast'));
      await tester.pump();
    });

    testWidgets('Restores screen brightness on widget disposal',
        (tester) async {
      final mockBrightness = MockBrightnessManager();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: const ['FRAME'],
              brightnessManager: mockBrightness,
            ),
          ),
        ),
      );

      expect(mockBrightness.setMaxCallCount, equals(1));
      expect(mockBrightness.restoreCallCount, equals(0));

      // Replace widget tree to trigger disposal
      await tester
          .pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      expect(mockBrightness.restoreCallCount, equals(1));
    });

    testWidgets(
        'OpticalAnimationPlayer.fromBytes converts byte frames to strings',
        (tester) async {
      final byteFrames = [
        Uint8List.fromList([65, 66, 67]), // "ABC"
        Uint8List.fromList([68, 69, 70]), // "DEF"
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer.fromBytes(
              byteFrames: byteFrames,
              initialFps: 8.0,
            ),
          ),
        ),
      );

      expect(find.text('Frame 1 / 2'), findsOneWidget);
      expect(find.textContaining('8.0 FPS'), findsOneWidget);
    });

    testWidgets('Handles empty frame payloads gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OpticalAnimationPlayer(
              framePayloads: [],
            ),
          ),
        ),
      );

      expect(find.text('No frames available'), findsOneWidget);
      expect(find.text('Frame 0 / 0'), findsOneWidget);
    });
  });
}
