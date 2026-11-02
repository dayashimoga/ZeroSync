import 'package:equatable/equatable.dart';

/// In-flight optical transfer checkpoint snapshot.
class TransferCheckpoint extends Equatable {
  final String sessionId;
  final String fileName;
  final int totalBytes;
  final int totalChunks;
  final Set<int> receivedChunkIndices;
  final String expectedSha256;
  final DateTime checkpointedAt;

  const TransferCheckpoint({
    required this.sessionId,
    required this.fileName,
    required this.totalBytes,
    required this.totalChunks,
    required this.receivedChunkIndices,
    required this.expectedSha256,
    required this.checkpointedAt,
  });

  /// Percentage of chunks received (0.0 to 100.0).
  double get progressPercentage => totalChunks > 0
      ? (receivedChunkIndices.length / totalChunks * 100.0).clamp(0.0, 100.0)
      : 0.0;

  /// Whether the transfer checkpoint represents a complete reception.
  bool get isComplete => receivedChunkIndices.length >= totalChunks;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'totalChunks': totalChunks,
        'receivedChunkIndices': receivedChunkIndices.toList()..sort(),
        'expectedSha256': expectedSha256,
        'checkpointedAt': checkpointedAt.toIso8601String(),
      };

  factory TransferCheckpoint.fromJson(Map<String, dynamic> json) =>
      TransferCheckpoint(
        sessionId: json['sessionId'] as String,
        fileName: json['fileName'] as String,
        totalBytes: json['totalBytes'] as int,
        totalChunks: json['totalChunks'] as int,
        receivedChunkIndices:
            (json['receivedChunkIndices'] as List<dynamic>).cast<int>().toSet(),
        expectedSha256: json['expectedSha256'] as String,
        checkpointedAt: DateTime.parse(json['checkpointedAt'] as String),
      );

  @override
  List<Object?> get props => [
        sessionId,
        fileName,
        totalBytes,
        totalChunks,
        receivedChunkIndices,
        expectedSha256,
        checkpointedAt,
      ];
}

/// Service managing persistent checkpoint saves and session resume states.
class TransferCheckpointService {
  final Map<String, TransferCheckpoint> _checkpoints = {};

  /// Saves or updates a transfer checkpoint.
  void saveCheckpoint(TransferCheckpoint checkpoint) {
    _checkpoints[checkpoint.sessionId] = checkpoint;
  }

  /// Retrieves a saved checkpoint by session ID.
  TransferCheckpoint? getCheckpoint(String sessionId) {
    return _checkpoints[sessionId];
  }

  /// Checks if a resume checkpoint exists for the given session ID.
  bool hasCheckpoint(String sessionId) {
    return _checkpoints.containsKey(sessionId);
  }

  /// Deletes a checkpoint upon completed verification or cancellation.
  void removeCheckpoint(String sessionId) {
    _checkpoints.remove(sessionId);
  }

  /// Clears all checkpoints.
  void clearAll() {
    _checkpoints.clear();
  }
}
