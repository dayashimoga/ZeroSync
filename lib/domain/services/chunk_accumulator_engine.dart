import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import '../value_objects/packed_transport_header.dart';
import '../value_objects/transport_header.dart';
import 'luby_transform_fec_service.dart';

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
      throw RangeError.index(
          index, this, 'index', 'Index out of bounds', capacity);
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

/// Immutable snapshot representing receiver progress, fountain degree telemetry, and early termination.
class AccumulatorSnapshot extends Equatable {
  final AccumulatorState state;
  final int? sessionId;
  final int totalChunks;
  final int receivedCount;
  final int duplicateCount;
  final int rejectedCount;
  final MimeTypeFlag? mimeFlag;
  final Map<int, int> degreeDistribution;
  final bool isEarlyTerminated;

  const AccumulatorSnapshot({
    required this.state,
    required this.sessionId,
    required this.totalChunks,
    required this.receivedCount,
    required this.duplicateCount,
    required this.rejectedCount,
    this.mimeFlag,
    this.degreeDistribution = const {},
    this.isEarlyTerminated = false,
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
      degreeDistribution: {},
      isEarlyTerminated: false,
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
        degreeDistribution,
        isEarlyTerminated,
      ];
}

/// Asynchronous optical frame accumulator with zero-allocation deduplication,
/// bipartite graph peeling poisoning protection, and early termination.
///
/// Designed for 60 FPS continuous optical camera scanning:
/// - Fast $O(1)$ duplicate suppression via [ChunkBitSet] bitmask and seed sets.
/// - Ingests out-of-order systematic frames into fixed-size sparse array.
/// - Ingests rateless LT fountain frames with Castagnoli CRC-32C validation.
/// - Early termination upon full equation recovery without waiting for excess droplets.
class ChunkAccumulatorEngine {
  AccumulatorState _state = AccumulatorState.idle;
  int? _activeSessionId;
  int _totalChunks = 0;
  int _receivedCount = 0;
  int _duplicateCount = 0;
  int _rejectedCount = 0;
  MimeTypeFlag? _mimeFlag;
  bool _isEarlyTerminated = false;

  List<Uint8List?> _sparseArray = const [];
  ChunkBitSet? _bitSet;

  final Set<int> _receivedSeeds = HashSet<int>();
  final Map<int, int> _degreeDistribution = <int, int>{};
  LubyTransformDecoder? _fountainDecoder;

  final StreamController<AccumulatorSnapshot> _stateController =
      StreamController<AccumulatorSnapshot>.broadcast();

  ChunkAccumulatorEngine();

  /// Current lifecycle state.
  AccumulatorState get state => _state;

  /// Active session identifier.
  int? get activeSessionId => _activeSessionId;

  /// Total expected chunks for the current session.
  int get totalChunks => _totalChunks;

  /// Number of unique valid chunks or solved source blocks received so far.
  int get receivedCount => _receivedCount;

  /// Number of redundant frames discarded by duplicate suppression.
  int get duplicateCount => _duplicateCount;

  /// Number of rejected frames (checksum failure, corruption, or mismatched session).
  int get rejectedCount => _rejectedCount;

  /// MIME type flag of the current transmission (systematic mode).
  MimeTypeFlag? get mimeFlag => _mimeFlag;

  /// Whether decoding terminated early as soon as all $K$ source blocks were recovered.
  bool get isEarlyTerminated => _isEarlyTerminated;

  /// Distribution of received fountain droplet degrees for optical rate telemetry.
  Map<int, int> get degreeDistribution => Map.unmodifiable(_degreeDistribution);

  /// Current progress ratio [0.0, 1.0].
  double get progress =>
      _totalChunks == 0 ? 0.0 : _receivedCount / _totalChunks;

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
        degreeDistribution: Map.unmodifiable(_degreeDistribution),
        isEarlyTerminated: _isEarlyTerminated,
      );

  /// Ingests a deserialized [PackedTransportFrame] (v1 systematic mode).
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

    if (_state == AccumulatorState.completed) {
      return false; // Early termination guard for current session
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
      _isEarlyTerminated = true;
    }

    _emitSnapshot();
    return true;
  }

  /// Ingests a [TransportFrame] (v2 20-byte wire header rateless fountain mode).
  ///
  /// Enforces graph peeling poisoning protection:
  /// 1. Verifies Castagnoli CRC-32C BEFORE inserting into bipartite peeling equations.
  /// 2. $O(1)$ duplicate seed suppression via [HashSet].
  /// 3. Validates reconstructed source block indices range before graph attachment.
  /// 4. Early termination upon full payload recovery.
  bool ingestTransportFrame(TransportFrame frame) {
    // Poisoning protection: reject corrupted frames before touching peeling graph
    if (!frame.isValidChecksum) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    final header = frame.header;
    if (header.k < 1 || frame.payload.isEmpty) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    // Initialize fountain session if idle
    if (_state == AccumulatorState.idle) {
      _activeSessionId = header.seed;
      _totalChunks = header.k;
      _receivedCount = 0;
      _duplicateCount = 0;
      _rejectedCount = 0;
      _receivedSeeds.clear();
      _degreeDistribution.clear();
      _fountainDecoder = LubyTransformDecoder(
        totalSourceBlocks: header.k,
        symbolSize: frame.payload.length,
        originalPayloadLength: header.payloadLength,
      );
      _state = AccumulatorState.accumulating;
    }

    // Validate K matches active session
    if (header.k != _totalChunks) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    if (_state == AccumulatorState.completed) {
      return false; // Early termination guard for current session
    }

    // O(1) duplicate suppression for seed
    if (_receivedSeeds.contains(header.seed)) {
      _duplicateCount++;
      _emitSnapshot();
      return false;
    }
    _receivedSeeds.add(header.seed);

    // Deterministic droplet reconstruction & degree distribution telemetry
    final prng = DeterministicPrng(header.seed);
    final soliton = RobustSolitonDistribution(header.k);
    final degree = soliton.sampleDegree(prng);
    final indices = soliton.sampleIndices(degree, prng);

    _degreeDistribution[degree] = (_degreeDistribution[degree] ?? 0) + 1;

    // Boundary check for poisoning prevention
    if (indices.any((idx) => idx < 0 || idx >= header.k)) {
      _rejectedCount++;
      _emitSnapshot();
      return false;
    }

    final droplet = FountainDroplet(
      seed: header.seed,
      totalSourceBlocks: header.k,
      symbolSize: frame.payload.length,
      originalPayloadLength: header.payloadLength,
      sourceIndices: indices,
      data: frame.payload,
    );

    // Ingest into belief propagation peeling decoder
    final providedNewInfo = _fountainDecoder!.addDroplet(droplet);
    _receivedCount = _fountainDecoder!.solvedBlocksCount;

    // Early termination upon graph resolution
    if (_fountainDecoder!.isDecoded) {
      _state = AccumulatorState.completed;
      _isEarlyTerminated = true;
    }

    _emitSnapshot();
    return providedNewInfo;
  }

  /// Ingests raw optical datagram bytes, automatically detecting v2 wire header (0x5A53)
  /// or v1 packed header.
  bool ingestWireBytes(Uint8List wireBytes) {
    try {
      if (wireBytes.length >= TransportHeader.headerSize &&
          wireBytes[0] == 0x5A &&
          wireBytes[1] == 0x53) {
        final frame =
            TransportFrame.fromWireBytes(wireBytes, verifyChecksum: true);
        return ingestTransportFrame(frame);
      } else {
        final frame =
            PackedTransportFrame.fromWireBytes(wireBytes, verifyChecksum: true);
        return ingestFrame(frame);
      }
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
    if (_state == AccumulatorState.idle) {
      return const [];
    }

    if (_fountainDecoder != null) {
      // In fountain mode, returns 1-based indices of unsolved source blocks
      final missing = <int>[];
      for (var i = 0; i < _totalChunks; i++) {
        if (!_fountainDecoder!.isDecoded &&
            i >= _fountainDecoder!.solvedBlocksCount) {
          missing.add(i + 1);
        }
      }
      return missing;
    }

    if (_bitSet == null) return const [];
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

    if (_fountainDecoder != null && _fountainDecoder!.isDecoded) {
      final decoded = _fountainDecoder!.getDecodedPayload();
      if (decoded != null) return decoded;
      throw StateError('Fountain payload reassembly failed');
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

  /// Resets accumulator to idle state and clears sparse buffer and fountain structures.
  void reset() {
    _state = AccumulatorState.idle;
    _activeSessionId = null;
    _totalChunks = 0;
    _receivedCount = 0;
    _duplicateCount = 0;
    _rejectedCount = 0;
    _mimeFlag = null;
    _isEarlyTerminated = false;
    _sparseArray = const [];
    _bitSet?.clear();
    _bitSet = null;
    _receivedSeeds.clear();
    _degreeDistribution.clear();
    _fountainDecoder = null;
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
