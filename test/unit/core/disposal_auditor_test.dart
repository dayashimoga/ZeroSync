import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/core/utils/disposal_auditor.dart';

void main() {
  group('DisposalAuditor Specs', () {
    final auditor = DisposalAuditor.instance;

    setUp(() {
      auditor.reset();
      auditor.setAuditingEnabled(true);
    });

    test('Tracks allocation and marks disposal by object reference', () {
      final target = Object();
      expect(auditor.activeResourceCount, equals(0));

      final id = auditor.trackAllocation(
        target: target,
        tag: 'MockController',
        category: ResourceCategory.controller,
      );

      expect(id, greaterThan(0));
      expect(auditor.activeResourceCount, equals(1));
      expect(auditor.undisposedRecords.length, equals(1));

      final disposed = auditor.markDisposed(target);
      expect(disposed, isTrue);
      expect(auditor.activeResourceCount, equals(0));
      expect(auditor.undisposedRecords.isEmpty, isTrue);

      // Subsequent markDisposed is a no-op
      expect(auditor.markDisposed(target), isFalse);
    });

    test('Throws MemoryLeakException when undisposed resources exist', () {
      final target = Object();
      auditor.trackAllocation(
        target: target,
        tag: 'LeakedStream',
        category: ResourceCategory.streamSubscription,
        captureStackTrace: true,
      );

      expect(
        () => auditor.assertZeroUndisposed(),
        throwsA(
          isA<MemoryLeakException>().having(
            (e) => e.toString(),
            'toString()',
            contains('LeakedStream'),
          ),
        ),
      );
    });

    test('Zeroes memory buffer with scrubBuffer to prevent heap retention', () {
      final buffer =
          Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF, 0x42, 0xFF]);
      expect(buffer.every((b) => b == 0), isFalse);

      DisposalAuditor.scrubBuffer(buffer);

      expect(buffer.every((b) => b == 0), isTrue);
    });

    test('Bypasses tracking when auditing is disabled', () {
      auditor.setAuditingEnabled(false);
      final target = Object();

      final id = auditor.trackAllocation(
        target: target,
        tag: 'Ignored',
        category: ResourceCategory.custom,
      );

      expect(id, equals(-1));
      expect(auditor.activeResourceCount, equals(0));
      expect(auditor.markDisposed(target), isFalse);
    });
  });

  group('DeterministicDisposalBag Specs', () {
    final auditor = DisposalAuditor.instance;

    setUp(() {
      auditor.reset();
      auditor.setAuditingEnabled(true);
    });

    test('Executes disposers in strict reverse LIFO order', () {
      final bag = DeterministicDisposalBag(tag: 'TestBag');
      final executionOrder = <int>[];

      bag.addDisposer(() => executionOrder.add(1));
      bag.addDisposer(() => executionOrder.add(2));
      bag.addDisposer(() => executionOrder.add(3));

      expect(bag.registeredResourceCount, equals(3));
      expect(bag.isDisposed, isFalse);

      bag.dispose();

      expect(bag.isDisposed, isTrue);
      expect(executionOrder, equals(<int>[3, 2, 1]));

      // Idempotent dispose call
      bag.dispose();
      expect(executionOrder, equals(<int>[3, 2, 1]));
    });

    test('Cancels StreamSubscriptions and marks disposed in auditor', () async {
      final bag = DeterministicDisposalBag();
      final controller = StreamController<int>();
      bool subscriptionCancelled = false;

      final subscription = controller.stream.listen(
        (_) {},
        onDone: () => subscriptionCancelled = true,
      );

      bag.addSubscription(subscription);
      expect(auditor.activeResourceCount, equals(1));

      bag.dispose();

      expect(auditor.activeResourceCount, equals(0));
      expect(subscriptionCancelled, isFalse); // cancel does not trigger onDone
      await controller.close();
    });

    test('Cancels Timers and marks disposed in auditor', () {
      final bag = DeterministicDisposalBag();
      final timer = Timer(const Duration(hours: 1), () {});

      expect(timer.isActive, isTrue);
      bag.addTimer(timer);
      expect(auditor.activeResourceCount, equals(1));

      bag.dispose();

      expect(timer.isActive, isFalse);
      expect(auditor.activeResourceCount, equals(0));
    });

    test('Closes Sinks and marks disposed in auditor', () async {
      final bag = DeterministicDisposalBag();
      // ignore: close_sinks
      final controller = StreamController<String>();

      bag.addSink(controller.sink);
      expect(auditor.activeResourceCount, equals(1));

      bag.dispose();

      expect(controller.isClosed, isTrue);
      expect(auditor.activeResourceCount, equals(0));
    });

    test('Scrubs buffers and marks disposed in auditor', () {
      final bag = DeterministicDisposalBag();
      final secretData = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

      bag.addBuffer(secretData, scrubOnDispose: true);
      expect(auditor.activeResourceCount, equals(1));

      bag.dispose();

      expect(secretData.every((b) => b == 0), isTrue);
      expect(auditor.activeResourceCount, equals(0));
    });

    test('Throws StateError if resource added after disposal', () {
      final bag = DeterministicDisposalBag();
      bag.dispose();

      expect(
        () => bag.addDisposer(() {}),
        throwsA(isA<StateError>()),
      );
    });

    test('Isolates exceptions so all registered disposers run', () {
      final bag = DeterministicDisposalBag();
      bool secondRan = false;

      bag.addDisposer(() => secondRan = true);
      bag.addDisposer(() => throw const FormatException('Corrupt resource'));

      expect(
        () => bag.dispose(),
        throwsA(isA<Exception>().having(
            (e) => e.toString(), 'error', contains('Corrupt resource'))),
      );

      expect(secondRan, isTrue);
      expect(bag.isDisposed, isTrue);
    });
  });
}
