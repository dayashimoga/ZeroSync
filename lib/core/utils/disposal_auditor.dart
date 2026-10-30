import 'dart:async';
import 'dart:typed_data';

/// Exception thrown when undisposed allocations or leaked resources are detected.
class MemoryLeakException implements Exception {
  final String message;
  final List<DisposalRecord> leakedRecords;

  const MemoryLeakException(this.message,
      [this.leakedRecords = const <DisposalRecord>[]]);

  @override
  String toString() {
    if (leakedRecords.isEmpty) return 'MemoryLeakException: $message';
    final StringBuffer sb =
        StringBuffer('MemoryLeakException: $message\nLeaked Resources:');
    for (final DisposalRecord record in leakedRecords) {
      sb.write(
          '\n - [${record.category}] ${record.tag} (Allocated: ${record.allocatedAt})');
    }
    return sb.toString();
  }
}

/// Resource category for memory auditing and lifecycle tracking.
enum ResourceCategory {
  streamSubscription,
  controller,
  byteBuffer,
  timer,
  nativeBinding,
  custom,
}

/// Metadata record tracking an allocated resource throughout its lifecycle.
class DisposalRecord {
  final int id;
  final String tag;
  final ResourceCategory category;
  final int? byteSize;
  final DateTime allocatedAt;
  final StackTrace? allocationTrace;
  DateTime? disposedAt;
  bool isDisposed;

  DisposalRecord({
    required this.id,
    required this.tag,
    required this.category,
    this.byteSize,
    this.allocationTrace,
    DateTime? allocatedAt,
  })  : allocatedAt = allocatedAt ?? DateTime.now(),
        isDisposed = false;

  void markDisposed() {
    isDisposed = true;
    disposedAt = DateTime.now();
  }
}

/// Central auditor that tracks resource allocations, detects memory leaks,
/// and verifies deterministic disposal across the application lifecycle.
class DisposalAuditor {
  DisposalAuditor._();

  static final DisposalAuditor instance = DisposalAuditor._();

  int _nextId = 0;
  final Map<int, DisposalRecord> _activeRecords = <int, DisposalRecord>{};
  final Expando<int> _objectIndex = Expando<int>('DisposalAuditorIndex');

  bool _isAuditingEnabled = true;

  bool get isAuditingEnabled => _isAuditingEnabled;
  int get activeResourceCount =>
      _activeRecords.values.where((r) => !r.isDisposed).length;
  List<DisposalRecord> get undisposedRecords =>
      _activeRecords.values.where((r) => !r.isDisposed).toList(growable: false);

  void setAuditingEnabled(bool enabled) {
    _isAuditingEnabled = enabled;
  }

  /// Registers an active resource for lifecycle tracking.
  int trackAllocation({
    required Object target,
    required String tag,
    required ResourceCategory category,
    int? byteSize,
    bool captureStackTrace = false,
  }) {
    if (!_isAuditingEnabled) return -1;

    final int id = ++_nextId;
    final DisposalRecord record = DisposalRecord(
      id: id,
      tag: tag,
      category: category,
      byteSize: byteSize,
      allocationTrace: captureStackTrace ? StackTrace.current : null,
    );

    _activeRecords[id] = record;
    _objectIndex[target] = id;
    return id;
  }

  /// Marks a tracked resource as deterministically disposed.
  bool markDisposed(Object target) {
    if (!_isAuditingEnabled) return false;

    final int? id = _objectIndex[target];
    if (id == null) {
      return false;
    }

    final DisposalRecord? record = _activeRecords[id];
    if (record != null && !record.isDisposed) {
      record.markDisposed();
      return true;
    }
    return false;
  }

  /// Explicitly marks a record as disposed by its unique registration id.
  bool markDisposedById(int id) {
    if (!_isAuditingEnabled) return false;

    final DisposalRecord? record = _activeRecords[id];
    if (record != null && !record.isDisposed) {
      record.markDisposed();
      return true;
    }
    return false;
  }

  /// Asserts that all tracked resources have been properly disposed.
  ///
  /// Throws [MemoryLeakException] if any active resource remains undisposed.
  void assertZeroUndisposed() {
    final List<DisposalRecord> leaks = undisposedRecords;
    if (leaks.isNotEmpty) {
      throw MemoryLeakException(
        'Detected ${leaks.length} undisposed resources during memory audit!',
        leaks,
      );
    }
  }

  /// Securely sanitizes and zeroes out sensitive typed data buffers (e.g., cryptographic keys,
  /// decrypted frame buffers) to eliminate retention in Dart VM heap pages.
  static void scrubBuffer(Uint8List buffer) {
    buffer.fillRange(0, buffer.length, 0);
  }

  /// Resets auditor registry (typically used between test cases).
  void reset() {
    _activeRecords.clear();
    _nextId = 0;
  }
}

/// Deterministic resource container that aggregates multiple disposable resources
/// and releases them in strict LIFO order upon [dispose].
class DeterministicDisposalBag {
  DeterministicDisposalBag({String tag = 'DeterministicDisposalBag'})
      : _tag = tag;

  final String _tag;
  final List<void Function()> _cleanupActions = <void Function()>[];
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;
  int get registeredResourceCount => _cleanupActions.length;

  /// Registers an arbitrary disposal callback.
  void addDisposer(void Function() disposeCallback) {
    _ensureNotDisposed();
    _cleanupActions.add(disposeCallback);
  }

  /// Registers a [StreamSubscription] for cancellation on disposal.
  void addSubscription(StreamSubscription<dynamic> subscription,
      {String tag = 'StreamSubscription'}) {
    _ensureNotDisposed();
    final int recordId = DisposalAuditor.instance.trackAllocation(
      target: subscription,
      tag: '$_tag::$tag',
      category: ResourceCategory.streamSubscription,
    );

    addDisposer(() {
      subscription.cancel();
      DisposalAuditor.instance.markDisposedById(recordId);
    });
  }

  /// Registers a [Timer] for cancellation on disposal.
  void addTimer(Timer timer, {String tag = 'Timer'}) {
    _ensureNotDisposed();
    final int recordId = DisposalAuditor.instance.trackAllocation(
      target: timer,
      tag: '$_tag::$tag',
      category: ResourceCategory.timer,
    );

    addDisposer(() {
      timer.cancel();
      DisposalAuditor.instance.markDisposedById(recordId);
    });
  }

  /// Registers a [Sink] for closing on disposal.
  void addSink(Sink<dynamic> sink, {String tag = 'Sink'}) {
    _ensureNotDisposed();
    final int recordId = DisposalAuditor.instance.trackAllocation(
      target: sink,
      tag: '$_tag::$tag',
      category: ResourceCategory.controller,
    );

    addDisposer(() {
      sink.close();
      DisposalAuditor.instance.markDisposedById(recordId);
    });
  }

  /// Registers a raw [Uint8List] buffer for memory auditing and optional zero-scrubbing.
  void addBuffer(
    Uint8List buffer, {
    String tag = 'ByteBuffer',
    bool scrubOnDispose = true,
  }) {
    _ensureNotDisposed();
    final int recordId = DisposalAuditor.instance.trackAllocation(
      target: buffer,
      tag: '$_tag::$tag',
      category: ResourceCategory.byteBuffer,
      byteSize: buffer.lengthInBytes,
    );

    addDisposer(() {
      if (scrubOnDispose) {
        DisposalAuditor.scrubBuffer(buffer);
      }
      DisposalAuditor.instance.markDisposedById(recordId);
    });
  }

  /// Deterministically executes all registered disposers in LIFO order.
  ///
  /// Errors in individual disposers are captured and aggregated, ensuring all
  /// remaining resources are still guaranteed to be released.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    final List<Object> errors = <Object>[];

    // Execute in reverse registration order (LIFO)
    for (int i = _cleanupActions.length - 1; i >= 0; i--) {
      try {
        _cleanupActions[i]();
      } catch (e) {
        errors.add(e);
      }
    }

    _cleanupActions.clear();

    if (errors.isNotEmpty) {
      throw Exception(
        'Encountered ${errors.length} error(s) during deterministic disposal of $_tag: $errors',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError(
          'Cannot register resources to an already disposed DeterministicDisposalBag ($_tag)');
    }
  }
}
