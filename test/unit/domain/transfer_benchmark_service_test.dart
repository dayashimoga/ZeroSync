import 'package:airdrop_qr/domain/services/transfer_benchmark_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferBenchmarkService Specs', () {
    late TransferBenchmarkService benchmarkService;

    setUp(() {
      benchmarkService = TransferBenchmarkService();
    });

    test('Returns default baseline telemetry when insufficient frames recorded',
        () {
      final initial = benchmarkService.computeTelemetry();
      expect(initial.currentFps, equals(0.0));
      expect(initial.currentThroughputKbps, equals(0.0));
      expect(initial.recommendedFps, equals(15));
      expect(initial.recommendedChunkBytes, equals(180));
    });

    test(
        'Computes realistic FPS, throughput, and scales up when drop rate is low',
        () {
      final t0 = DateTime(2026, 11, 2, 12, 0, 0);

      // Record 15 frames over 1 second (15 FPS, 200 bytes per frame = ~3 KB/s)
      for (var i = 0; i < 15; i++) {
        benchmarkService.recordFrame(
          byteSize: 200,
          timestamp: t0.add(Duration(milliseconds: i * 66)),
        );
      }

      final telemetry = benchmarkService.computeTelemetry();
      expect(telemetry.currentFps, greaterThan(13.0));
      expect(telemetry.currentThroughputKbps, greaterThan(2.0));
      expect(telemetry.frameDropRate, equals(0.0));
      // With low drop rate and high FPS, auto-tuner recommends higher FPS
      expect(telemetry.recommendedFps, equals(25));
      expect(telemetry.recommendedChunkBytes, equals(220));
    });

    test('Detects high frame drop rate and backs off parameters for stability',
        () {
      final t0 = DateTime(2026, 11, 2, 12, 0, 0);

      // Record 5 successful frames and 5 dropped frames (50% drop rate)
      for (var i = 0; i < 5; i++) {
        benchmarkService.recordFrame(
          byteSize: 200,
          timestamp: t0.add(Duration(milliseconds: i * 200)),
        );
        benchmarkService.recordFrameDrop();
      }

      final telemetry = benchmarkService.computeTelemetry();
      expect(telemetry.frameDropRate, equals(50.0));
      // Under high drop rate, auto-tuner backs off to conservative settings
      expect(telemetry.recommendedFps, equals(10));
      expect(telemetry.recommendedChunkBytes, equals(140));
    });

    test('Resets metrics cleanly', () {
      benchmarkService.recordFrame(byteSize: 500);
      benchmarkService.recordFrameDrop();
      benchmarkService.reset();

      final telemetry = benchmarkService.computeTelemetry();
      expect(telemetry.currentFps, equals(0.0));
      expect(telemetry.frameDropRate, equals(0.0));
    });
  });
}
