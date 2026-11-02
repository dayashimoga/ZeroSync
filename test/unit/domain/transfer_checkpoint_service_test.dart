import 'package:airdrop_qr/domain/services/transfer_checkpoint_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransferCheckpointService Specs', () {
    late TransferCheckpointService checkpointService;

    setUp(() {
      checkpointService = TransferCheckpointService();
    });

    test('Saves, retrieves, and checks existence of transfer checkpoints', () {
      final checkpoint = TransferCheckpoint(
        sessionId: 'session-xyz-123',
        fileName: 'classified_briefing.pdf',
        totalBytes: 524288,
        totalChunks: 32,
        receivedChunkIndices: const {0, 1, 2, 3, 4, 5, 6, 7},
        expectedSha256:
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        checkpointedAt: DateTime.now(),
      );

      checkpointService.saveCheckpoint(checkpoint);

      expect(checkpointService.hasCheckpoint('session-xyz-123'), isTrue);
      final retrieved = checkpointService.getCheckpoint('session-xyz-123');
      expect(retrieved, isNotNull);
      expect(retrieved?.progressPercentage, equals(25.0));
      expect(retrieved?.isComplete, isFalse);

      checkpointService.removeCheckpoint('session-xyz-123');
      expect(checkpointService.hasCheckpoint('session-xyz-123'), isFalse);
    });

    test('Serializes and deserializes checkpoint to JSON deterministically',
        () {
      final now = DateTime.now();
      final original = TransferCheckpoint(
        sessionId: 'sess-abc',
        fileName: 'airgap_spec.json',
        totalBytes: 1024,
        totalChunks: 10,
        receivedChunkIndices: const {0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
        expectedSha256: 'deadbeef',
        checkpointedAt: now,
      );

      final json = original.toJson();
      final restored = TransferCheckpoint.fromJson(json);

      expect(restored.sessionId, equals(original.sessionId));
      expect(restored.isComplete, isTrue);
      expect(restored.progressPercentage, equals(100.0));
      expect(restored.receivedChunkIndices.length, equals(10));
    });
  });
}
