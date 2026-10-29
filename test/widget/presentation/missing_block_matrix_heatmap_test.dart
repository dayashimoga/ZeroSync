import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/presentation/widgets/missing_block_matrix_heatmap.dart';

void main() {
  group('TransferProgressMetrics Calculation Specs', () {
    test('Computes progress percentage, transfer speed, and ETA accurately', () {
      final metrics = TransferProgressMetrics.compute(
        totalChunks: 20,
        receivedChunks: 15,
        missingIndices: [4, 8, 12, 16, 20],
        totalBytesReceived: 15 * 200, // 3000 bytes
        elapsed: const Duration(milliseconds: 1000), // 1 second
      );

      expect(metrics.progressPercentage, equals(75.0));
      // 3000 bytes / 1024 / 1.0s = ~2.929 KB/s
      expect(metrics.transferSpeedKbps, closeTo(2.93, 0.05));
      expect(metrics.isComplete, isFalse);
      expect(metrics.estimatedTimeRemaining, isNotNull);
      // ETA: 5 remaining chunks * 200 bytes = 1000 bytes / 1024 / ~2.93 = ~0.33s
      expect(metrics.estimatedTimeRemaining!.inMilliseconds, greaterThan(0));
    });

    test('Handles zero chunks and zero elapsed gracefully without error', () {
      final initial = TransferProgressMetrics.initial();
      expect(initial.progressPercentage, 0.0);
      expect(initial.transferSpeedKbps, 0.0);
      expect(initial.isComplete, isFalse);
      expect(initial.estimatedTimeRemaining, isNull);

      final zeroElapsed = TransferProgressMetrics.compute(
        totalChunks: 10,
        receivedChunks: 0,
        missingIndices: List.generate(10, (i) => i + 1),
        totalBytesReceived: 0,
        elapsed: Duration.zero,
      );
      expect(zeroElapsed.progressPercentage, 0.0);
      expect(zeroElapsed.transferSpeedKbps, 0.0);
    });

    test('Marks isComplete as true when received >= total', () {
      final done = TransferProgressMetrics.compute(
        totalChunks: 5,
        receivedChunks: 5,
        missingIndices: const [],
        totalBytesReceived: 1000,
        elapsed: const Duration(seconds: 1),
      );

      expect(done.isComplete, isTrue);
      expect(done.progressPercentage, 100.0);
    });
  });

  group('MissingBlockMatrixHeatmap Widget Specs', () {
    testWidgets('Renders telemetry header, progress bar, and 2D matrix tiles', (tester) async {
      const metrics = TransferProgressMetrics(
        totalChunks: 6,
        receivedChunks: 4,
        missingIndices: [2, 5],
        progressPercentage: 66.7,
        transferSpeedKbps: 4.5,
        estimatedTimeRemaining: Duration(seconds: 1),
        totalBytesReceived: 800,
        isComplete: false,
      );

      int? tappedChunk;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MissingBlockMatrixHeatmap(
              metrics: metrics,
              gridColumns: 6,
              maxHeight: 400.0,
              onChunkTapped: (idx) => tappedChunk = idx,
            ),
          ),
        ),
      );

      expect(find.text('66.7%'), findsOneWidget);
      expect(find.text('4 / 6 Chunks'), findsOneWidget);
      expect(find.text('4.5 KB/s'), findsOneWidget);
      expect(find.text('ETA: 1.0s'), findsOneWidget);

      // Verify chunk tiles 1 to 6 exist
      for (var i = 1; i <= 6; i++) {
        expect(find.text('$i'), findsOneWidget);
      }

      // Verify missing chips exist
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#5'), findsOneWidget);

      // Tap missing tile 2
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(tappedChunk, equals(2));
    });

    testWidgets('Displays completed guidance message when transfer is finished', (tester) async {
      const metrics = TransferProgressMetrics(
        totalChunks: 10,
        receivedChunks: 10,
        missingIndices: [],
        progressPercentage: 100.0,
        transferSpeedKbps: 12.0,
        estimatedTimeRemaining: null,
        totalBytesReceived: 2000,
        isComplete: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MissingBlockMatrixHeatmap(metrics: metrics),
          ),
        ),
      );

      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('Transfer complete! Payload verified.'), findsOneWidget);
    });

    testWidgets('Displays slow optical lock hint when speed < 0.5 KB/s with missing chunks', (tester) async {
      const metrics = TransferProgressMetrics(
        totalChunks: 10,
        receivedChunks: 2,
        missingIndices: [3, 4, 5, 6, 7, 8, 9, 10],
        progressPercentage: 20.0,
        transferSpeedKbps: 0.2, // Slow
        estimatedTimeRemaining: Duration(seconds: 15),
        totalBytesReceived: 400,
        isComplete: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MissingBlockMatrixHeatmap(metrics: metrics),
          ),
        ),
      );

      expect(
        find.text('Optical lock slow: align screen reticle and reduce glare'),
        findsOneWidget,
      );
    });

    testWidgets('Handles initial waiting state when totalChunks is zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MissingBlockMatrixHeatmap(
              metrics: TransferProgressMetrics.initial(),
            ),
          ),
        ),
      );

      expect(find.text('Waiting for incoming stream...'), findsOneWidget);
      expect(find.text('0.0%'), findsOneWidget);
    });
  });
}
