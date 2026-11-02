/// Live benchmark telemetry during an optical transfer session.
class BenchmarkTelemetry {
  final double currentFps;
  final double currentThroughputKbps;
  final double averageLatencyMs;
  final double frameDropRate;
  final int recommendedFps;
  final int recommendedChunkBytes;

  const BenchmarkTelemetry({
    required this.currentFps,
    required this.currentThroughputKbps,
    required this.averageLatencyMs,
    required this.frameDropRate,
    required this.recommendedFps,
    required this.recommendedChunkBytes,
  });
}

/// Service computing real-time optical link throughput and optimizing transfer parameters.
class TransferBenchmarkService {
  final List<DateTime> _frameTimestamps = [];
  final List<int> _frameByteSizes = [];
  int _droppedFrameCount = 0;
  static const int maxHistoryWindow = 30;

  /// Records an ingested frame arrival timestamp and byte size.
  void recordFrame({required int byteSize, DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    _frameTimestamps.add(now);
    _frameByteSizes.add(byteSize);

    if (_frameTimestamps.length > maxHistoryWindow) {
      _frameTimestamps.removeAt(0);
      _frameByteSizes.removeAt(0);
    }
  }

  /// Records a dropped or corrupted frame event.
  void recordFrameDrop() {
    _droppedFrameCount++;
  }

  /// Computes current performance metrics and parameter tuning recommendations.
  BenchmarkTelemetry computeTelemetry() {
    if (_frameTimestamps.length < 2) {
      return const BenchmarkTelemetry(
        currentFps: 0.0,
        currentThroughputKbps: 0.0,
        averageLatencyMs: 0.0,
        frameDropRate: 0.0,
        recommendedFps: 15,
        recommendedChunkBytes: 180,
      );
    }

    final durationSeconds = _frameTimestamps.last
            .difference(_frameTimestamps.first)
            .inMicroseconds /
        1000000.0;

    final fps = durationSeconds > 0
        ? (_frameTimestamps.length - 1) / durationSeconds
        : 0.0;

    final totalBytes = _frameByteSizes.fold<int>(0, (sum, b) => sum + b);
    final throughputKbps =
        durationSeconds > 0 ? (totalBytes / 1024.0) / durationSeconds : 0.0;

    final totalFrames = _frameTimestamps.length + _droppedFrameCount;
    final dropRate =
        totalFrames > 0 ? (_droppedFrameCount / totalFrames) * 100.0 : 0.0;

    final latencyMs = fps > 0 ? 1000.0 / fps : 0.0;

    // Parameter auto-tuner:
    // If drop rate is high (> 25%), back off FPS and chunk size for stability
    // If drop rate is low (< 5%), scale up FPS for higher throughput
    int recFps;
    int recBytes;
    if (dropRate > 25.0) {
      recFps = 10;
      recBytes = 140;
    } else if (dropRate < 5.0 && fps >= 12.0) {
      recFps = 25;
      recBytes = 220;
    } else {
      recFps = 15;
      recBytes = 180;
    }

    return BenchmarkTelemetry(
      currentFps: double.parse(fps.toStringAsFixed(1)),
      currentThroughputKbps: double.parse(throughputKbps.toStringAsFixed(1)),
      averageLatencyMs: double.parse(latencyMs.toStringAsFixed(1)),
      frameDropRate: double.parse(dropRate.toStringAsFixed(1)),
      recommendedFps: recFps,
      recommendedChunkBytes: recBytes,
    );
  }

  /// Resets benchmark metrics.
  void reset() {
    _frameTimestamps.clear();
    _frameByteSizes.clear();
    _droppedFrameCount = 0;
  }
}
