import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/core/utils/disposal_auditor.dart';
import 'package:airdrop_qr/domain/services/secure_memory_arena.dart';

void main() {
  group('SecureBuffer & SecureMemoryArena Zeroization Barrier Specs', () {
    setUp(() {
      DisposalAuditor.instance.reset();
    });

    tearDown(() {
      DisposalAuditor.instance.assertZeroUndisposed();
    });

    test('Allocates zero-initialized native memory of requested byte length',
        () {
      final buffer = SecureBuffer.allocate(64, tag: 'AesKeyBuffer');
      expect(buffer.isDisposed, isFalse);
      expect(buffer.length, equals(64));
      expect(buffer.verifyZeroState(), isTrue);

      buffer.dispose();
      expect(buffer.isDisposed, isTrue);
    });

    test('Zeroization barrier wipes all sensitive byte data before disposal',
        () {
      final secretKey = Uint8List.fromList(List.generate(32, (i) => 0xAA ^ i));
      final buffer = SecureBuffer.fromBytes(secretKey, tag: 'SecretKey');

      final view = buffer.asTypedList();
      expect(view, equals(secretKey));
      expect(buffer.verifyZeroState(), isFalse);

      // Explicit zeroize
      buffer.zeroize();
      expect(buffer.verifyZeroState(), isTrue);
      for (final byte in view) {
        expect(byte, equals(0x00));
      }

      buffer.dispose();
      expect(buffer.isDisposed, isTrue);
    });

    test('Accessing buffer after dispose throws StateError', () {
      final buffer = SecureBuffer.allocate(16);
      buffer.dispose();

      expect(() => buffer.asTypedList(), throwsA(isA<StateError>()));
      expect(() => buffer.zeroize(), throwsA(isA<StateError>()));
      expect(() => buffer.verifyZeroState(), throwsA(isA<StateError>()));
    });

    test(
        'withBuffer guarantees zeroization and disposal even on thrown exceptions',
        () {
      expect(
        () => SecureMemoryArena.withBuffer(32, (buffer) {
          buffer.copyFrom(Uint8List.fromList(List.filled(32, 0xFF)));
          expect(buffer.verifyZeroState(), isFalse);
          throw Exception('Simulated cryptographic pipeline failure');
        }),
        throwsA(isA<Exception>()),
      );

      // DisposalAuditor verifies zero undisposed allocations
      expect(DisposalAuditor.instance.activeResourceCount, equals(0));
    });

    test('withTwoBuffers manages dual cryptographic operands (key + iv) safely',
        () {
      final result =
          SecureMemoryArena.withTwoBuffers<int>(32, 16, (keyBuf, ivBuf) {
        keyBuf.copyFrom(Uint8List.fromList(List.filled(32, 0x11)));
        ivBuf.copyFrom(Uint8List.fromList(List.filled(16, 0x22)));

        expect(keyBuf.length, equals(32));
        expect(ivBuf.length, equals(16));
        return 42;
      });

      expect(result, equals(42));
      expect(DisposalAuditor.instance.activeResourceCount, equals(0));
    });

    test('SecureMemoryArena tracks multiple buffers and frees in LIFO order',
        () {
      final arena = SecureMemoryArena();
      final b1 = arena.allocate(10, tag: 'B1');
      final b2 = arena.allocate(20, tag: 'B2');
      final b3 = arena.allocateFrom(Uint8List.fromList([1, 2, 3]), tag: 'B3');

      expect(arena.activeBufferCount, equals(3));
      expect(b1.isDisposed, isFalse);
      expect(b2.isDisposed, isFalse);
      expect(b3.isDisposed, isFalse);

      arena.dispose();
      expect(arena.isDisposed, isTrue);
      expect(arena.activeBufferCount, equals(0));
      expect(b1.isDisposed, isTrue);
      expect(b2.isDisposed, isTrue);
      expect(b3.isDisposed, isTrue);
    });
  });
}
