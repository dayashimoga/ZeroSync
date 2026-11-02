import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/domain/services/binary_file_chunker.dart';
import 'package:airdrop_qr/presentation/blocs/optical_session/optical_session_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpticalSessionBloc Specification Tests', () {
    test('Initial state is OpticalSessionIdle with zeroed metrics', () {
      final bloc = OpticalSessionBloc();
      expect(bloc.state, isA<OpticalSessionIdle>());
      expect(bloc.state.activeMode, equals(0));
      expect(bloc.state.metrics.totalChunks, equals(0));
      expect(bloc.state.metrics.receivedChunks, equals(0));
      expect(bloc.state.metrics.progressPercentage, equals(0.0));
      expect(bloc.state.metrics.isComplete, isFalse);
      expect(bloc.state.framePayloads, isEmpty);
      expect(bloc.state.statusText, contains('Air-gap optical link ready'));
      bloc.close();
    });

    blocTest<OpticalSessionBloc, OpticalSessionState>(
      'Switches mode cleanly between receiver (0) and transmitter (1)',
      build: () => OpticalSessionBloc(),
      act: (bloc) => bloc.add(const OpticalSessionModeChanged(1)),
      expect: () => [
        isA<OpticalSessionIdle>()
            .having((s) => s.activeMode, 'activeMode', 1)
            .having((s) => s.statusText, 'statusText',
                contains('Visual transmitter ready')),
      ],
    );

    blocTest<OpticalSessionBloc, OpticalSessionState>(
      'Prepares payload and transitions to OpticalSessionTransmitting with accurate chunks',
      build: () => OpticalSessionBloc(),
      act: (bloc) {
        final payload = utf8.encode('ZeroSync Air-Gap Test Payload ' * 10);
        bloc.add(OpticalSessionPayloadPrepared(
          fileName: 'test_doc.txt',
          fileBytes: Uint8List.fromList(payload),
          chunkSize: 64,
        ));
      },
      expect: () => [
        isA<OpticalSessionPreparing>()
            .having((s) => s.fileName, 'fileName', 'test_doc.txt'),
        isA<OpticalSessionTransmitting>()
            .having((s) => s.fileName, 'fileName', 'test_doc.txt')
            .having((s) => s.framePayloads.length, 'frames', greaterThan(1))
            .having((s) => s.metrics.totalChunks, 'totalChunks', greaterThan(1))
            .having((s) => s.metrics.isComplete, 'isComplete', isFalse),
      ],
    );

    blocTest<OpticalSessionBloc, OpticalSessionState>(
      'Advances transmitter frame index and updates progress metrics',
      build: () => OpticalSessionBloc(),
      seed: () {
        final sampleChunks = ['frame0', 'frame1', 'frame2', 'frame3'];
        return OpticalSessionTransmitting(
          metrics: OpticalSessionIdle().metrics,
          activeMode: 1,
          statusText: 'Transmitting',
          fileName: 'sample.bin',
          fileSizeBytes: 100,
          framePayloads: sampleChunks,
          currentFrameIndex: 0,
        );
      },
      act: (bloc) => bloc.add(const OpticalSessionFrameAdvanced(2)),
      expect: () => [
        isA<OpticalSessionTransmitting>()
            .having((s) => s.currentFrameIndex, 'index', 2)
            .having((s) => s.metrics.receivedChunks, 'received', 3)
            .having((s) => s.metrics.progressPercentage, 'progress', 75.0),
      ],
    );

    test(
        'Ingests multi-chunk frames and cryptographically verifies reassembled payload',
        () async {
      final bloc = OpticalSessionBloc();

      final originalData =
          utf8.encode('Top-Secret SCIF Attestation Data Block ' * 5);
      final originalBytes = Uint8List.fromList(originalData);
      final expectedSha = sha256.convert(originalBytes).toString();

      final chunks = BinaryFileChunker.splitFile(
        fileName: 'classified.dat',
        fileBytes: originalBytes,
        chunkSize: 60,
      );

      expect(chunks.length, greaterThan(1));

      // Ingest first chunk
      final firstWire = base64.encode(chunks[0].toWireBytes());
      bloc.add(OpticalSessionFrameIngested(firstWire));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state, isA<OpticalSessionReceiving>());
      expect(bloc.state.metrics.receivedChunks, equals(1));
      expect(bloc.state.metrics.isComplete, isFalse);

      // Ingest remaining chunks
      for (var i = 1; i < chunks.length; i++) {
        final wire = base64.encode(chunks[i].toWireBytes());
        bloc.add(OpticalSessionFrameIngested(wire));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(bloc.state, isA<OpticalSessionVerified>());
      final verified = bloc.state as OpticalSessionVerified;
      expect(verified.metrics.isComplete, isTrue);
      expect(verified.verifiedSha256, equals(expectedSha));
      expect(verified.verifiedPayload, equals(originalBytes));
      expect(verified.statusText, contains('Transfer complete!'));

      await bloc.close();
    });

    test('Ingests standalone single-code QR and verifies immediately',
        () async {
      final bloc = OpticalSessionBloc();
      const rawPayload = 'https://zerosync.security/airgap/scif';

      bloc.add(const OpticalSessionFrameIngested(rawPayload));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state, isA<OpticalSessionVerified>());
      final verified = bloc.state as OpticalSessionVerified;
      expect(verified.metrics.isComplete, isTrue);
      expect(verified.verifiedSha256,
          equals(sha256.convert(utf8.encode(rawPayload)).toString()));

      await bloc.close();
    });

    blocTest<OpticalSessionBloc, OpticalSessionState>(
      'OpticalSessionReset restores honest idle state',
      build: () => OpticalSessionBloc(),
      seed: () => OpticalSessionVerified(
        metrics: OpticalSessionIdle().metrics,
        activeMode: 1,
        statusText: 'Done',
        verifiedPayload: null,
        verifiedSha256: 'abc',
      ),
      act: (bloc) => bloc.add(const OpticalSessionReset()),
      expect: () => [
        isA<OpticalSessionIdle>()
            .having((s) => s.activeMode, 'activeMode', 1)
            .having((s) => s.metrics.totalChunks, 'totalChunks', 0),
      ],
    );
  });
}
