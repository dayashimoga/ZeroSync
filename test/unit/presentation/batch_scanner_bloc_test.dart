import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:airdrop_qr/data/datasources/optical_scanner_datasource.dart';
import 'package:airdrop_qr/presentation/blocs/batch_scanner/batch_scanner_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';

class MockEncryptedVaultDataSource extends Mock implements EncryptedVaultDataSource {}
class MockBatchScannerFeedbackService extends Mock implements BatchScannerFeedbackService {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      ScanRecord.create(
        rawValue: 'fallback',
        format: 'qrCode',
        contentType: 'text',
      ),
    );
  });

  group('BatchScanItem Entity & Content Inference', () {
    test('Correctly infers content type based on payload prefix', () {
      expect(BatchScanItem.create(rawValue: 'https://flutter.dev', format: 'qrCode').contentType, equals('url'));
      expect(BatchScanItem.create(rawValue: 'http://example.com', format: 'qrCode').contentType, equals('url'));
      expect(BatchScanItem.create(rawValue: 'WIFI:S:HomeNet;;', format: 'qrCode').contentType, equals('wifi'));
      expect(BatchScanItem.create(rawValue: 'BEGIN:VCARD\nFN:John\nEND:VCARD', format: 'qrCode').contentType, equals('vcard'));
      expect(BatchScanItem.create(rawValue: 'BEGIN:VEVENT\nSUMMARY:Meet\nEND:VEVENT', format: 'qrCode').contentType, equals('calendar'));
      expect(BatchScanItem.create(rawValue: 'geo:37.7749,-122.4194', format: 'qrCode').contentType, equals('geo'));
      expect(BatchScanItem.create(rawValue: 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP', format: 'qrCode').contentType, equals('totp'));
      expect(BatchScanItem.create(rawValue: 'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', format: 'qrCode').contentType, equals('crypto'));
      expect(BatchScanItem.create(rawValue: 'arbitrary plain text', format: 'qrCode').contentType, equals('text'));
    });

    test('copyWithIncrement increments scan count', () {
      final item = BatchScanItem.create(rawValue: 'CODE_1', format: 'qrCode');
      expect(item.scanCount, equals(1));

      final incremented = item.copyWithIncrement();
      expect(incremented.scanCount, equals(2));
      expect(incremented.id, equals(item.id));
      expect(incremented.rawValue, equals(item.rawValue));
    });
  });

  group('BatchScannerBloc State Machine & Deduplication Tests', () {
    late MockEncryptedVaultDataSource mockVault;
    late MockBatchScannerFeedbackService mockFeedback;

    setUp(() {
      mockVault = MockEncryptedVaultDataSource();
      mockFeedback = MockBatchScannerFeedbackService();

      when(() => mockFeedback.triggerSuccessHaptic()).thenAnswer((_) async {});
      when(() => mockFeedback.triggerSuccessChime()).thenAnswer((_) async {});
      when(() => mockFeedback.triggerDuplicateWarning()).thenAnswer((_) async {});
      when(() => mockVault.insertScan(any())).thenAnswer((inv) async => inv.positionalArguments.first as ScanRecord);
    });

    OpticalScanResult createScan(String value, {BarcodeFormat format = BarcodeFormat.qrCode}) {
      return OpticalScanResult(
        rawValue: value,
        format: format,
        timestamp: DateTime.now(),
        engineUsed: OpticalDetectionEngine.googleMlKit,
        instantaneousFps: 60.0,
        frameSequence: 1,
        processingLatency: const Duration(milliseconds: 15),
      );
    }

    test('Initial state is BatchScannerInitial', () {
      final bloc = BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      );
      expect(bloc.state, equals(const BatchScannerInitial()));
      bloc.close();
    });

    blocTest<BatchScannerBloc, BatchScannerState>(
      'BatchScannerStarted initializes active session and clears previous data',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) => bloc.add(const BatchScannerStarted(
        autoSaveToVault: true,
        debounceWindow: Duration(milliseconds: 1500),
        batchTag: 'Warehouse Scan',
      )),
      expect: () => [
        isA<BatchScannerActive>()
            .having((s) => s.items, 'items', isEmpty)
            .having((s) => s.duplicateCount, 'duplicates', equals(0))
            .having((s) => s.isPaused, 'isPaused', isFalse)
            .having((s) => s.autoSaveToVault, 'autoSave', isTrue),
      ],
    );

    blocTest<BatchScannerBloc, BatchScannerState>(
      'Ingests unique codes, fires feedback, and auto-saves to encrypted vault',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) {
        bloc.add(const BatchScannerStarted(autoSaveToVault: true));
        bloc.add(BatchScannerCodeScanned(createScan('ITEM-A')));
        bloc.add(BatchScannerCodeScanned(createScan('ITEM-B')));
      },
      expect: () => [
        isA<BatchScannerActive>().having((s) => s.itemCount, 'count', equals(0)),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(1))
            .having((s) => s.items.first.rawValue, 'latest', equals('ITEM-A')),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(2))
            .having((s) => s.items.first.rawValue, 'latest', equals('ITEM-B')),
      ],
      verify: (_) {
        verify(() => mockFeedback.triggerSuccessHaptic()).called(2);
        verify(() => mockFeedback.triggerSuccessChime()).called(2);
        verify(() => mockVault.insertScan(any())).called(2);
      },
    );

    blocTest<BatchScannerBloc, BatchScannerState>(
      'Suppresses duplicate code within 1500ms sliding window and triggers warning feedback',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) {
        bloc.add(const BatchScannerStarted(debounceWindow: Duration(milliseconds: 1500)));
        bloc.add(BatchScannerCodeScanned(createScan('DUP-1')));
        // Immediate duplicate
        bloc.add(BatchScannerCodeScanned(createScan('DUP-1')));
      },
      expect: () => [
        isA<BatchScannerActive>().having((s) => s.itemCount, 'count', equals(0)),
        isA<BatchScannerActive>().having((s) => s.itemCount, 'count', equals(1)),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(1))
            .having((s) => s.duplicateCount, 'duplicates', equals(1))
            .having((s) => s.feedbackMessage, 'msg', contains('Duplicate suppressed')),
      ],
      verify: (_) {
        verify(() => mockFeedback.triggerSuccessHaptic()).called(1);
        verify(() => mockFeedback.triggerDuplicateWarning()).called(1);
        verify(() => mockVault.insertScan(any())).called(1); // Only 1 save
      },
    );

    blocTest<BatchScannerBloc, BatchScannerState>(
      'Accepts re-scanned code after debounce window expires, incrementing scanCount',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) async {
        bloc.add(const BatchScannerStarted(debounceWindow: Duration(milliseconds: 50)));
        bloc.add(BatchScannerCodeScanned(createScan('RE-SCAN')));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        bloc.add(BatchScannerCodeScanned(createScan('RE-SCAN')));
      },
      expect: () => [
        isA<BatchScannerActive>().having((s) => s.itemCount, 'count', equals(0)),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(1))
            .having((s) => s.items.first.scanCount, 'scans', equals(1)),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(1))
            .having((s) => s.items.first.scanCount, 'scans', equals(2)),
      ],
      verify: (_) {
        verify(() => mockFeedback.triggerSuccessHaptic()).called(2);
      },
    );

    blocTest<BatchScannerBloc, BatchScannerState>(
      'Pausing blocks code ingestion until resumed',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) {
        bloc.add(const BatchScannerStarted());
        bloc.add(const BatchScannerPaused());
        bloc.add(BatchScannerCodeScanned(createScan('IGNORED_WHILE_PAUSED')));
        bloc.add(const BatchScannerResumed());
        bloc.add(BatchScannerCodeScanned(createScan('ACCEPTED_AFTER_RESUME')));
      },
      expect: () => [
        isA<BatchScannerActive>().having((s) => s.itemCount, 'count', equals(0)),
        isA<BatchScannerActive>().having((s) => s.isPaused, 'paused', isTrue),
        isA<BatchScannerActive>().having((s) => s.isPaused, 'resumed', isFalse),
        isA<BatchScannerActive>()
            .having((s) => s.itemCount, 'count', equals(1))
            .having((s) => s.items.first.rawValue, 'item', equals('ACCEPTED_AFTER_RESUME')),
      ],
    );

    test('Removes individual item and clears batch correctly', () async {
      final bloc = BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      );

      bloc.add(const BatchScannerStarted());
      bloc.add(BatchScannerCodeScanned(createScan('ITEM-1')));
      bloc.add(BatchScannerCodeScanned(createScan('ITEM-2')));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      var state = bloc.state as BatchScannerActive;
      expect(state.itemCount, equals(2));
      final itemToRemoveId = state.items.last.id; // ITEM-1

      bloc.add(BatchScannerItemRemoved(itemToRemoveId));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      state = bloc.state as BatchScannerActive;
      expect(state.itemCount, equals(1));
      expect(state.items.first.rawValue, equals('ITEM-2'));

      bloc.add(const BatchScannerCleared());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      state = bloc.state as BatchScannerActive;
      expect(state.itemCount, equals(0));
      expect(state.duplicateCount, equals(0));

      await bloc.close();
    });

    blocTest<BatchScannerBloc, BatchScannerState>(
      'Explicit BatchScannerSavedToVault persists all items and emits success',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) {
        bloc.add(const BatchScannerStarted(autoSaveToVault: false));
        bloc.add(BatchScannerCodeScanned(createScan('ITEM-1')));
        bloc.add(BatchScannerCodeScanned(createScan('ITEM-2')));
        bloc.add(const BatchScannerSavedToVault(customTag: 'Manual Export'));
      },
      expect: () => [
        isA<BatchScannerActive>(),
        isA<BatchScannerActive>(),
        isA<BatchScannerActive>(),
        isA<BatchScannerSaving>().having((s) => s.totalCount, 'total', equals(2)),
        isA<BatchScannerSaveSuccess>()
            .having((s) => s.savedCount, 'saved', equals(2))
            .having((s) => s.appliedTag, 'tag', equals('Manual Export')),
      ],
      verify: (_) {
        verify(() => mockVault.insertScan(any())).called(2);
      },
    );

    blocTest<BatchScannerBloc, BatchScannerState>(
      'BatchScannerStopped transitions back to BatchScannerInitial',
      build: () => BatchScannerBloc(
        vaultDataSource: mockVault,
        feedbackService: mockFeedback,
      ),
      act: (bloc) {
        bloc.add(const BatchScannerStarted());
        bloc.add(const BatchScannerStopped());
      },
      expect: () => [
        isA<BatchScannerActive>(),
        const BatchScannerInitial(),
      ],
    );
  });
}
