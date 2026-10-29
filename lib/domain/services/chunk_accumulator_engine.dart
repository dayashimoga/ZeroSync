import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../value_objects/packed_transport_header.dart';

/// Memory-efficient, zero-allocation bitset for $O(1)$ duplicate checking during continuous scanning.
class ChunkBitSet {
  final int capacity;
  final Uint32List _words;

  ChunkBitSet(this.capacity) : _words = Uint32List((capacity + 31) >> 5);

  /// Checks if bit at [index] is set.
  bool contains(int index) {
    if (index < 0 || index >= capacity) return false;
    final word = index >> 5;
    final bit = index & 31;
    return (_words[word] & (1 << bit)) != 0;
  }

  /// Sets bit at [index]. Returns `true` if newly added, `false` if already set.
  bool add(int index) {
    if (index < 0 || index >= capacity) {
      throw RangeError.index(index, this, 'index', 'Index out of bounds', capacity);
    }
    final word = index >> 5;
    final bit = index & 31;
    final mask = 1 << bit;
    if ((_words[word] & mask) != 0) {
      return false; // Already present
    }
    _words[word] |= mask;
    return true; // Newly added
  }

  /// Clears all bits.
  void clear() {
    _words.fillRange(0, _words.length, 0);
  }
}

/// Lifecycle states of the optical chunk accumulator.
enum AccumulatorState {
  idle,
  accumulating,
  completed,
  aborted,
}

/// Immutable snapshot representing receiver progress and telemetry.
class AccumulatorSnapshot extends Equatable {
  final AccumulatorState state;
  final int? sessionId;
  final int totalChunks;
  final int receivedCount;
  final int duplicateCount;
  final int rejectedCount;
  final MimeTypeFlag? mimeFlag;

  const AccumulatorSnapshot({
    required this.state,
    required this.sessionId,
    required this.totalChunks,
    required this.receivedCount,
    required this.duplicateCount,
    required this.rejectedCount,
    this.mimeFlag,
  });

  /// Factory for initial empty state.
  factory AccumulatorSnapshot.idle() {
    return const AccumulatorSnapshot(
      state: AccumulatorState.idle,
      sessionId: null,
      totalChunks: 0,
      receivedCount: 0,
      duplicateCount: 0,
      rejectedCount: 0,
      mimeFlag: null,
    );
  }

  /// Normalized progress ratio [0.0, 1.0].
  double get progress => totalChunks == 0 ? 0.0 : receivedCount / totalChunks;

  /// Whether all expected frames for the current session have been collected.
  bool get isComplete => state == AccumulatorState.completed;

  @override
  List<Object?> get props => [
        state,
        sessionId,
        totalChunks,
        receivedCount,
        duplicateCount,
        rejectedCount,
        mimeFlag,
      ];
}

/// Asynchronous optical frame accumulator with zero-allocation deduplication and sparse array caching.
///
/// Designed for 60 FPS continuous camera scanning:
/// - Fast $O(1)$ duplicate suppression via [ChunkBitSet] bitmask.
/// - Ingests out-of-order optical frames into fixed-size sparse array.
/// - Validates per-chunk CRC32 checksums and locks to active Session ID.
class ChunkAccumulatorEngine {
  AccumulatorState _state = AccumulatorState.idle;
  int? _activeSessionId;
  int _totalChunks = 0;
  int _receivedCount = 0;
  int _duplicateCount = 0;
  int _rejectedCount = 0;
  MimeTypeFlag? _mimeFlag;

  List<Uint8List?> _sparseArray = const [];
  ChunkBitSet? _bitSet;

  final StreamController<AccumulatorSnapshot> _stateController =
      StreamController<AccumulatorSnapshot>.broadcast();

  ChunkAccumulatorEngine();

  /// Current lifecycle state.
  AccumulatorState get state => _state;

  /// Active session identifier.
  int? get activeSessionId => _activeSessionId;

  /// Total expected chunks for the current session.
  int get totalChunks => _totalChunks;

  /// Number of unique valid chunks received so far.
  int get receivedCount => _receivedCount;

  /// Number of redundant frames discarded by duplicate suppression.
  int get duplicateCount => _duplicateCount;

  /// Number of rejected frames (checksum failure or mismatched session).
  int get rejectedCount => _rejectedCount;

  /// MIME type flag of the current transmission.
  MimeTypeFlag? get mimeFlag => _mimeFlag;

  /// Current progress ratio [0.0, 1.0].
  double get progress => _totalChunks == 0 ? 0.0 : _receivedCount / _totalChunks;

  /// Whether all chunks for the session are received and verified.
  bool get isComplete => _state == AccumulatorState.completed;

  /// Reactive stream of accumulator telemetry snapshots.
  Stream<AccumulatorSnapshot> get stateStream => _stateController.stream;

  /// Captures current snapshot.
  AccumulatorSnapshot get snapshot => AccumulatorSnapshot(
        state: _state,
        sessionId: _activeSessionId,
        totalChunks: _totalChunks,
        receivedCount: _receivedCount,
        duplicateCount: _duplicateCount,
        rejectedCount: _rejectedCount,
        mimeFlag: _mimeFlag,
      );

  /// Ingests a deserialized [PackedTransportFrame].
  /// Returns `true` if frame provided new unique data, `false` if duplicate or rejected.
  bool ingestFrame(PackedTransportFrame frame) {
    if (!frame.isValidChecksum) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    // Initialize session if idle
    if (_state == AccumulatorState.idle) {
      _initializeSession(frame);
    }

    // Reject mismatched session
    if (frame.header.sessionId != _activeSessionId) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    final chunkIndex = frame.header.chunkIndex;
    if (chunkIndex < 1 || chunkIndex > _totalChunks) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    // O(1) duplicate check
    if (_bitSet!.contains(chunkIndex)) {
      _duplicateCount++;
      _emitSnapshot();
      return false;
    }

    // Store in sparse array without resizing
    _bitSet!.add(chunkIndex);
    _sparseArray[chunkIndex] = frame.payload;
    _receivedCount++;

    if (_receivedCount >= _totalChunks) {
      _state = AccumulatorState.completed;
    }

    _emitSnapshot();
    return true;
  }

  /// Ingests raw optical datagram bytes, deserializing the header and payload.
  bool ingestWireBytes(Uint8List wireBytes) {
    try {
      final frame = PackedTransportFrame.fromWireBytes(wireBytes, verifyChecksum: true);
      return ingestFrame(frame);
    } catch (_) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }
  }

  void _initializeSession(PackedTransportFrame frame) {
    _activeSessionId = frame.header.sessionId;
    _totalChunks = frame.header.totalChunks;
    _mimeFlag = frame.header.mimeFlag;
    _receivedCount = 0;
    _duplicateCount = 0;
    _rejectedCount = 0;
    _sparseArray = List<Uint8List?>.filled(_totalChunks + 1, null);
    _bitSet = ChunkBitSet(_totalChunks + 1);
    _state = AccumulatorState.accumulating;
  }

  /// Returns sorted list of 1-based chunk indices still missing from the transmission.
  List<int> getMissingIndices() {
    if (_state == AccumulatorState.idle || _bitSet == null) {
      return const [];
    }
    final missing = <int>[];
    for (var i = 1; i <= _totalChunks; i++) {
      if (!_bitSet!.contains(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  /// Assembles all accumulated chunks into a contiguous binary payload.
  /// Throws [StateError] if accumulator is not in [AccumulatorState.completed].
  Uint8List assembleContiguousPayload() {
    if (!isComplete) {
      throw StateError(
        'Cannot assemble incomplete payload ($_receivedCount / $_totalChunks received)',
      );
    }

    var totalBytes = 0;
    for (var i = 1; i <= _totalChunks; i++) {
      final chunk = _sparseArray[i];
      if (chunk == null) {
        throw StateError('Integrity violation: missing chunk at index $i');
      }
      totalBytes += chunk.length;
    }

    final assembled = Uint8List(totalBytes);
    var offset = 0;
    for (var i = 1; i <= _totalChunks; i++) {
      final chunk = _sparseArray[i]!;
      assembled.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return assembled;
  }

  /// Resets accumulator to idle state and clears sparse buffer.
  void reset() {
    _state = AccumulatorState.idle;
    _activeSessionId = null;
    _totalChunks = 0;
    _receivedCount = 0;
    _duplicateCount = 0;
    _rejectedCount = 0;
    _mimeFlag = null;
    _sparseArray = const [];
    _bitSet?.clear();
    _bitSet = null;
    _emitSnapshot();
  }

  void _emitSnapshot() {
    if (!_stateController.isClosed) {
      _stateController.add(snapshot);
    }
  }

  /// Closes the reactive state controller.
  Future<void> dispose() async {
    await _stateController.close();
  }
}

