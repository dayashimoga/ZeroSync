import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../../core/utils/disposal_auditor.dart';

/// Native FFI-backed secure memory buffer with explicit zeroization barrier.
///
/// Designed for zero-trust cryptographic keys, passphrases, seed phrases, and
/// decrypted optical payloads to prevent sensitive artifacts from lingering in
/// the Dart VM managed heap.
class SecureBuffer {
  final Pointer<Uint8> pointer;
  final int length;
  final String tag;
  int _auditorId = -1;
  bool _isDisposed = false;

  SecureBuffer._({
    required this.pointer,
    required this.length,
    required this.tag,
  });

  /// Allocates zero-initialized native memory of [length] bytes via `calloc<Uint8>`.
  factory SecureBuffer.allocate(int length, {String tag = 'SecureBuffer'}) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Buffer length must be > 0');
    }

    final ptr = calloc<Uint8>(length);
    final buffer = SecureBuffer._(
      pointer: ptr,
      length: length,
      tag: tag,
    );

    final auditorId = DisposalAuditor.instance.trackAllocation(
      target: buffer,
      tag: tag,
      category: ResourceCategory.nativeBinding,
      byteSize: length,
    );
    buffer._auditorId = auditorId;

    return buffer;
  }

  /// Allocates native memory and copies [source] bytes into it.
  factory SecureBuffer.fromBytes(Uint8List source,
      {String tag = 'SecureBuffer'}) {
    final buffer = SecureBuffer.allocate(source.length, tag: tag);
    buffer.copyFrom(source);
    return buffer;
  }

  /// Whether the native buffer has been scrubbed and freed.
  bool get isDisposed => _isDisposed;

  /// Returns a live [Uint8List] view pointing directly to the native memory block.
  Uint8List asTypedList() {
    _ensureNotDisposed();
    return pointer.asTypedList(length);
  }

  /// Copies bytes from [source] into the native buffer.
  void copyFrom(Uint8List source) {
    _ensureNotDisposed();
    final count = min(length, source.length);
    final view = pointer.asTypedList(length);
    view.setRange(0, count, source);
  }

  /// Memory Wiping Barrier: Overwrites every native byte with `0x00`.
  void zeroize() {
    _ensureNotDisposed();
    final view = pointer.asTypedList(length);
    for (var i = 0; i < length; i++) {
      view[i] = 0x00;
    }
  }

  /// Verifies that all bytes in the native block are strictly `0x00`.
  bool verifyZeroState() {
    _ensureNotDisposed();
    final view = pointer.asTypedList(length);
    for (var i = 0; i < length; i++) {
      if (view[i] != 0x00) return false;
    }
    return true;
  }

  /// Executes memory wiping barrier, verifies zero-state, and frees native memory.
  void dispose() {
    if (_isDisposed) return;

    // 1. Overwrite with zeroes
    final view = pointer.asTypedList(length);
    for (var i = 0; i < length; i++) {
      view[i] = 0x00;
    }

    // 2. Verify complete zeroization
    var isZeroed = true;
    for (var i = 0; i < length; i++) {
      if (view[i] != 0x00) {
        isZeroed = false;
        break;
      }
    }

    // 3. Free native allocation back to system allocator
    calloc.free(pointer);
    _isDisposed = true;

    // 4. Update auditor
    DisposalAuditor.instance.markDisposedById(_auditorId);

    if (!isZeroed) {
      throw StateError(
        'Critical Security Failure: SecureBuffer wiping barrier failed to zero memory before free!',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot access SecureBuffer ($tag) after disposal');
    }
  }
}

/// Scoped memory management arena tracking native allocations and guaranteeing
/// strict LIFO zeroization barriers.
class SecureMemoryArena {
  final List<SecureBuffer> _activeBuffers = <SecureBuffer>[];
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get activeBufferCount =>
      _activeBuffers.where((b) => !b.isDisposed).length;

  /// Allocates a new [SecureBuffer] managed by this arena.
  SecureBuffer allocate(int length, {String tag = 'ArenaBuffer'}) {
    _ensureNotDisposed();
    final buffer = SecureBuffer.allocate(length, tag: tag);
    _activeBuffers.add(buffer);
    return buffer;
  }

  /// Allocates a new [SecureBuffer] initialized with [source] bytes.
  SecureBuffer allocateFrom(Uint8List source, {String tag = 'ArenaBuffer'}) {
    _ensureNotDisposed();
    final buffer = SecureBuffer.fromBytes(source, tag: tag);
    _activeBuffers.add(buffer);
    return buffer;
  }

  /// Executes [action] with a temporary [SecureBuffer], guaranteeing zeroization and disposal.
  static T withBuffer<T>(
    int length,
    T Function(SecureBuffer buffer) action, {
    String tag = 'ScopedBuffer',
  }) {
    final buffer = SecureBuffer.allocate(length, tag: tag);
    try {
      return action(buffer);
    } finally {
      buffer.dispose();
    }
  }

  /// Executes [action] with two temporary [SecureBuffer]s (e.g. key and plaintext),
  /// guaranteeing zeroization and disposal for both.
  static T withTwoBuffers<T>(
    int len1,
    int len2,
    T Function(SecureBuffer b1, SecureBuffer b2) action, {
    String tag1 = 'ScopedBuffer1',
    String tag2 = 'ScopedBuffer2',
  }) {
    final b1 = SecureBuffer.allocate(len1, tag: tag1);
    try {
      final b2 = SecureBuffer.allocate(len2, tag: tag2);
      try {
        return action(b1, b2);
      } finally {
        b2.dispose();
      }
    } finally {
      b1.dispose();
    }
  }

  /// Zeroizes and frees all active buffers in reverse order of allocation (LIFO).
  void disposeAll() {
    if (_isDisposed) return;
    for (var i = _activeBuffers.length - 1; i >= 0; i--) {
      final buffer = _activeBuffers[i];
      if (!buffer.isDisposed) {
        buffer.dispose();
      }
    }
    _activeBuffers.clear();
  }

  /// Disposes all managed buffers and closes the arena.
  void dispose() {
    disposeAll();
    _isDisposed = true;
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('Cannot allocate from a disposed SecureMemoryArena');
    }
  }
}
