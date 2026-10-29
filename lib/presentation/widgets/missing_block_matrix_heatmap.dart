import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Telemetry metrics for an ongoing optical air-gap transfer session.
class TransferProgressMetrics {
  final int totalChunks;
  final int receivedChunks;
  final List<int> missingIndices;
  final double progressPercentage;
  final double transferSpeedKbps;
  final Duration? estimatedTimeRemaining;
  final int totalBytesReceived;
  final bool isComplete;

  const TransferProgressMetrics({
    required this.totalChunks,
    required this.receivedChunks,
    required this.missingIndices,
    required this.progressPercentage,
    required this.transferSpeedKbps,
    this.estimatedTimeRemaining,
    this.totalBytesReceived = 0,
    required this.isComplete,
  });

  /// Factory creating metrics from chunk counts and temporal delta.
  factory TransferProgressMetrics.compute({
    required int totalChunks,
    required int receivedChunks,
    required List<int> missingIndices,
    required int totalBytesReceived,
    required Duration elapsed,
  }) {
    final progress = totalChunks > 0
        ? ((receivedChunks / totalChunks) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final seconds = elapsed.inMilliseconds / 1000.0;
    final speedKbps = seconds > 0.1 ? (totalBytesReceived / 1024.0) / seconds : 0.0;

    Duration? eta;
    final missingCount = missingIndices.length;
    if (speedKbps > 0.05 && missingCount > 0 && receivedChunks > 0) {
      final avgBytesPerChunk = totalBytesReceived / receivedChunks;
      final remainingBytes = missingCount * avgBytesPerChunk;
      final remainingSeconds = (remainingBytes / 1024.0) / speedKbps;
      eta = Duration(milliseconds: (remainingSeconds * 1000.0).round());
    }

    return TransferProgressMetrics(
      totalChunks: totalChunks,
      receivedChunks: receivedChunks,
      missingIndices: missingIndices,
      progressPercentage: progress,
      transferSpeedKbps: speedKbps,
      estimatedTimeRemaining: eta,
      totalBytesReceived: totalBytesReceived,
      isComplete: totalChunks > 0 && receivedChunks >= totalChunks,
    );
  }

  /// Initial empty state.
  factory TransferProgressMetrics.initial() {
    return const TransferProgressMetrics(
      totalChunks: 0,
      receivedChunks: 0,
      missingIndices: [],
      progressPercentage: 0.0,
      transferSpeedKbps: 0.0,
      estimatedTimeRemaining: null,
      totalBytesReceived: 0,
      isComplete: false,
    );
  }
}

/// Visual 2D missing-block heatmap and real-time optical receiver telemetry widget.
///
/// Features:
/// - Real-time metrics bar: progress percentage, speed (KB/s), ETA, and missing counts.
/// - Dynamic 2D matrix heatmap showing received (green) vs missing (amber) blocks.
/// - Distance guidance banner assisting the user to maintain optimal camera focus.
class MissingBlockMatrixHeatmap extends StatelessWidget {
  /// Progress metrics representing the active transmission.
  final TransferProgressMetrics metrics;

  /// Optional maximum height for the heatmap grid container.
  final double maxHeight;

  /// Number of columns in the 2D block matrix grid.
  final int gridColumns;

  /// Callback when a missing chunk tile is tapped.
  final ValueChanged<int>? onChunkTapped;

  const MissingBlockMatrixHeatmap({
    super.key,
    required this.metrics,
    this.maxHeight = 220.0,
    this.gridColumns = 10,
    this.onChunkTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = metrics.isComplete;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDone ? Colors.green.shade400 : theme.colorScheme.outlineVariant,
          width: isDone ? 2.0 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8.0,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header telemetry bar: Progress %, Speed, ETA
          _buildTelemetryBar(theme),

          const SizedBox(height: 12.0),

          // Linear progress track
          ClipRRect(
            borderRadius: BorderRadius.circular(6.0),
            child: LinearProgressIndicator(
              value: metrics.progressPercentage / 100.0,
              minHeight: 8.0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? Colors.green : theme.colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 14.0),

          // Dynamic Camera Guidance Banner
          _buildGuidanceBanner(theme),

          const SizedBox(height: 12.0),

          // 2D Missing-Block Heatmap Matrix
          if (metrics.totalChunks > 0)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: _buildHeatmapGrid(),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Text(
                  'Waiting for incoming stream...',
                  style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
            ),

          if (metrics.missingIndices.isNotEmpty && metrics.missingIndices.length <= 15) ...[
            const SizedBox(height: 10.0),
            _buildMissingChips(theme),
          ],
        ],
      ),
    );
  }

  Widget _buildTelemetryBar(ThemeData theme) {
    final etaStr = metrics.estimatedTimeRemaining != null
        ? '${(metrics.estimatedTimeRemaining!.inMilliseconds / 1000.0).toStringAsFixed(1)}s'
        : '--';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${metrics.progressPercentage.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 22.0,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              '${metrics.receivedChunks} / ${metrics.totalChunks} Chunks',
              style: TextStyle(
                fontSize: 12.0,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Speed Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.speed, size: 14.0, color: Colors.blue.shade700),
                  const SizedBox(width: 4.0),
                  Text(
                    '${metrics.transferSpeedKbps.toStringAsFixed(1)} KB/s',
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8.0),
            // ETA Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14.0, color: Colors.purple.shade700),
                  const SizedBox(width: 4.0),
                  Text(
                    'ETA: $etaStr',
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuidanceBanner(ThemeData theme) {
    final IconData icon;
    final String message;
    final Color bgColor;
    final Color textColor;

    if (metrics.isComplete) {
      icon = Icons.check_circle_outline;
      message = 'Transfer complete! Payload verified.';
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade900;
    } else if (metrics.progressPercentage > 85.0) {
      icon = Icons.camera_alt_outlined;
      message = 'Finishing stream: hold camera steady at 15-20cm';
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade900;
    } else if (metrics.missingIndices.isNotEmpty && metrics.transferSpeedKbps < 0.5) {
      icon = Icons.zoom_in_outlined;
      message = 'Optical lock slow: align screen reticle and reduce glare';
      bgColor = Colors.amber.shade50;
      textColor = Colors.amber.shade900;
    } else {
      icon = Icons.center_focus_strong;
      message = 'Optimal camera distance maintained';
      bgColor = Colors.teal.shade50;
      textColor = Colors.teal.shade900;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16.0, color: textColor),
          const SizedBox(width: 6.0),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.0, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid() {
    final missingSet = Set<int>.from(metrics.missingIndices);
    final columns = math.max(1, gridColumns);

    return GridView.builder(
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 3.0,
        mainAxisSpacing: 3.0,
      ),
      itemCount: metrics.totalChunks,
      itemBuilder: (context, index) {
        final chunkIndex = index + 1;
        final isMissing = missingSet.contains(chunkIndex);
        final color = isMissing ? Colors.amber.shade600 : Colors.green.shade600;

        return InkWell(
          onTap: () => onChunkTapped?.call(chunkIndex),
          borderRadius: BorderRadius.circular(3.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3.0),
              border: Border.all(
                color: isMissing ? Colors.amber.shade800 : Colors.green.shade800,
                width: 0.5,
              ),
            ),
            child: Center(
              child: Text(
                '$chunkIndex',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissingChips(ThemeData theme) {
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      children: [
        const Text(
          'Missing: ',
          style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.bold),
        ),
        ...metrics.missingIndices.map(
          (idx) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.0),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(4.0),
              border: Border.all(color: Colors.amber.shade400, width: 0.5),
            ),
            child: Text(
              '#$idx',
              style: TextStyle(
                fontSize: 10.0,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
