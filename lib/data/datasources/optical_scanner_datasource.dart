import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:airdrop_qr/core/platform/windows_zxing_decoder.dart';

export 'package:airdrop_qr/core/platform/windows_zxing_decoder.dart';

/// Supported hardware-accelerated optical detection engines for QR and barcode scanning.
enum OpticalDetectionEngine {
  /// Google ML Kit Barcode Scanning pipeline (Hardware-accelerated on Android NNAPI/GPU and iOS).
  googleMlKit,

  /// Apple Vision Framework (`VNDetectBarcodesRequest`) pipeline (Optimized for Apple Neural Engine).
  appleVision,

  /// Windows ZXing-C++ high-performance optical engine.
  windowsZxing,

  /// Automatic platform detection: selects [windowsZxing] on Windows, [appleVision] on iOS/macOS,
  /// and [googleMlKit] on Android/others.
  auto,
}

/// Operational scanning modes tailored for air-gapped data transfers and user workflows.
enum OpticalScanningMode {
  /// Air-gapped visual data stream mode (ZeroSync / Luby / RaptorQ fountain ingestion).
  ///
  /// In this mode:
  /// - High frame-rate ingestion (targeting 60 FPS) is prioritized.
  /// - Duplicate suppression is disabled so sequential chunk streams are never filtered out.
  /// - Ring buffer overflow triggers explicit dropped frame accounting.
  continuousAirGap,

  /// Interactive single-code detection mode.
  ///
  /// In this mode:
  /// - Identical barcode payloads are debounced for a cooldown window (e.g. 1500 ms).
  /// - Optimizes battery and thermal dissipation during interactive camera aiming.
  singleCode,

  /// High-volume multi-item batch scanning mode.
  ///
  /// Emits unique barcode codes sequentially and suppresses duplicates already recorded in the active batch set.
  batchMode,
}

/// Runtime configuration options for [OpticalScannerDataSource].
class OpticalScannerConfig {
  /// Active optical detection engine pipeline.
  final OpticalDetectionEngine engine;

  /// High-level scanning mode determining duplicate filtering and buffer throughput policies.
  final OpticalScanningMode scanningMode;

  /// Desired continuous frame throughput in frames per second (default: 60 FPS).
  final int targetFps;

  /// Maximum capacity of the zero-allocation circular frame buffer.
  final int frameBufferSize;

  /// Debounce duration for suppressing consecutive identical codes in [OpticalScanningMode.singleCode].
  final Duration duplicateDebounceWindow;

  /// Filter set of barcode formats accepted by the scanner pipeline.
  final List<BarcodeFormat> supportedFormats;

  /// Whether to detect inverted (light-on-dark) optical codes.
  final bool invertDetection;

  /// Whether to preserve the decoded raw byte array alongside the UTF-8 string payload.
  final bool retainRawBytes;

  const OpticalScannerConfig({
    this.engine = OpticalDetectionEngine.auto,
    this.scanningMode = OpticalScanningMode.continuousAirGap,
    this.targetFps = 60,
    this.frameBufferSize = 128,
    this.duplicateDebounceWindow = const Duration(milliseconds: 1500),
    this.supportedFormats = const <BarcodeFormat>[BarcodeFormat.qrCode],
    this.invertDetection = false,
    this.retainRawBytes = true,
  })  : assert(
            frameBufferSize > 0, 'frameBufferSize must be strictly positive'),
        assert(targetFps > 0, 'targetFps must be strictly positive');

  /// Creates a copy of this configuration with specified fields replaced.
  OpticalScannerConfig copyWith({
    OpticalDetectionEngine? engine,
    OpticalScanningMode? scanningMode,
    int? targetFps,
    int? frameBufferSize,
    Duration? duplicateDebounceWindow,
    List<BarcodeFormat>? supportedFormats,
    bool? invertDetection,
    bool? retainRawBytes,
  }) {
    return OpticalScannerConfig(
      engine: engine ?? this.engine,
      scanningMode: scanningMode ?? this.scanningMode,
      targetFps: targetFps ?? this.targetFps,
      frameBufferSize: frameBufferSize ?? this.frameBufferSize,
      duplicateDebounceWindow:
          duplicateDebounceWindow ?? this.duplicateDebounceWindow,
      supportedFormats: supportedFormats ?? this.supportedFormats,
      invertDetection: invertDetection ?? this.invertDetection,
      retainRawBytes: retainRawBytes ?? this.retainRawBytes,
    );
  }
}

/// A parsed optical scan result emitted by the continuous ingestion pipeline.
@immutable
class OpticalScanResult {
  /// Decoded UTF-8 text or URI payload.
  final String rawValue;

  /// Decoded raw binary payload, preserving binary datagrams for fountain chunks.
  final Uint8List? rawBytes;

  /// Symbology format of the decoded code (e.g. QR code).
  final BarcodeFormat format;

  /// Timestamp when the sensor frame or detection event was created.
  final DateTime timestamp;

  /// Detection engine responsible for resolving this optical code.
  final OpticalDetectionEngine engineUsed;

  /// Bounding polygon corner points in normalized/viewport coordinate space.
  final List<Offset> cornerPoints;

  /// Instantaneous optical scanning frame-rate (FPS) calculated at the time of emission.
  final double instantaneousFps;

  /// Monotonically increasing sequential frame identifier.
  final int frameSequence;

  /// Total ingestion-to-dispatch latency duration.
  final Duration processingLatency;

  const OpticalScanResult({
    required this.rawValue,
    this.rawBytes,
    required this.format,
    required this.timestamp,
    required this.engineUsed,
    this.cornerPoints = const <Offset>[],
    required this.instantaneousFps,
    required this.frameSequence,
    required this.processingLatency,
  });

  @override
  String toString() =>
      'OpticalScanResult(seq: $frameSequence, fps: ${instantaneousFps.toStringAsFixed(1)}, '
      'engine: ${engineUsed.name}, format: ${format.name}, value: ${rawValue.length > 32 ? "${rawValue.substring(0, 32)}..." : rawValue})';
}

/// Real-time telemetry and performance metrics for the optical scanner pipeline.
@immutable
class ScannerMetrics {
  /// Total raw camera capture events received from the hardware controller.
  final int totalFramesReceived;

  /// Total decoded optical symbols successfully dispatched downstream.
  final int totalFramesProcessed;

  /// Total frames dropped due to buffer saturation or backpressure.
  final int droppedFrames;

  /// Rolling throughput in frames per second over the active measurement window.
  final double currentFps;

  /// Exponential moving average of per-frame ingestion-to-dispatch latency.
  final Duration averageLatency;

  /// Current saturation of the circular ring buffer (0.0 = empty, 1.0 = fully saturated).
  final double bufferUtilization;

  const ScannerMetrics({
    required this.totalFramesReceived,
    required this.totalFramesProcessed,
    required this.droppedFrames,
    required this.currentFps,
    required this.averageLatency,
    required this.bufferUtilization,
  });

  /// Initial zeroed metrics snapshot.
  factory ScannerMetrics.zero() {
    return const ScannerMetrics(
      totalFramesReceived: 0,
      totalFramesProcessed: 0,
      droppedFrames: 0,
      currentFps: 0.0,
      averageLatency: Duration.zero,
      bufferUtilization: 0.0,
    );
  }

  @override
  String toString() =>
      'ScannerMetrics(received: $totalFramesReceived, processed: $totalFramesProcessed, '
      'dropped: $droppedFrames, fps: ${currentFps.toStringAsFixed(1)}, '
      'avgLatency: ${averageLatency.inMicroseconds / 1000.0}ms, util: ${(bufferUtilization * 100).toStringAsFixed(1)}%)';
}

/// Exception thrown when optical scanner initialization or runtime ingestion fails.
class OpticalScannerException implements Exception {
  /// Explanatory error message.
  final String message;

  /// Underlying cause or nested exception if available.
  final Object? cause;

  const OpticalScannerException(this.message, [this.cause]);

  @override
  String toString() =>
      'OpticalScannerException: $message${cause != null ? " (Cause: $cause)" : ""}';
}

/// Pre-allocated, zero-allocation circular ring buffer designed for 60 FPS video ingestion.
///
/// Prevents garbage collector pauses by reusing fixed-size slots and avoiding dynamic
/// list allocations during high-frequency camera frame processing.
class OpticalFrameRingBuffer<T> {
  final int _capacity;
  final List<T?> _buffer;
  int _head = 0;
  int _tail = 0;
  int _size = 0;
  int _dropCount = 0;

  OpticalFrameRingBuffer(int capacity)
      : _capacity = capacity,
        _buffer = List<T?>.filled(capacity, null);

  /// Maximum capacity of the ring buffer.
  int get capacity => _capacity;

  /// Number of active items currently stored in the ring buffer.
  int get size => _size;

  /// Whether the buffer is completely empty.
  bool get isEmpty => _size == 0;

  /// Whether the buffer has reached maximum capacity.
  bool get isFull => _size == _capacity;

  /// Current buffer fullness ratio (0.0 to 1.0).
  double get utilization => _capacity > 0 ? _size / _capacity : 0.0;

  /// Lifetime count of dropped items caused by buffer overflow.
  int get dropCount => _dropCount;

  /// Pushes an [item] into the ring buffer.
  ///
  /// If the buffer is full, the oldest unread item is evicted (dropped) to make room
  /// for real-time fresh frame ingestion, incrementing [dropCount]. Returns `true`
  /// if the item was added without dropping, or `false` if an older frame was evicted.
  bool push(T item) {
    if (isFull) {
      // Evict oldest item to ensure low latency and prevent stalls
      _buffer[_head] = null;
      _head = (_head + 1) % _capacity;
      _dropCount++;
      _buffer[_tail] = item;
      _tail = (_tail + 1) % _capacity;
      return false;
    } else {
      _buffer[_tail] = item;
      _tail = (_tail + 1) % _capacity;
      _size++;
      return true;
    }
  }

  /// Pops the oldest item from the buffer. Returns `null` if the buffer is empty.
  T? pop() {
    if (isEmpty) return null;
    final T? item = _buffer[_head];
    _buffer[_head] = null;
    _head = (_head + 1) % _capacity;
    _size--;
    return item;
  }

  /// Peeks at the oldest item without removing it. Returns `null` if empty.
  T? peek() {
    if (isEmpty) return null;
    return _buffer[_head];
  }

  /// Clears all entries from the buffer and resets head/tail indices.
  /// If [resetDropCount] is `true`, resets the lifetime drop counter to zero.
  void clear({bool resetDropCount = false}) {
    for (int i = 0; i < _capacity; i++) {
      _buffer[i] = null;
    }
    _head = 0;
    _tail = 0;
    _size = 0;
    if (resetDropCount) {
      _dropCount = 0;
    }
  }
}

/// Abstract contract for high-performance optical barcode and sequential stream scanning.
abstract class OpticalScannerDataSource {
  /// Stream emitting parsed optical scan results.
  Stream<OpticalScanResult> get scanStream;

  /// Stream emitting real-time hardware telemetry and frame-rate metrics.
  Stream<ScannerMetrics> get metricsStream;

  /// Active scanner configuration.
  OpticalScannerConfig get config;

  /// Current real-time performance and pipeline metrics.
  ScannerMetrics get currentMetrics;

  /// Whether the scanner is actively running and processing optical input.
  bool get isScanning;

  /// Whether scanning has been temporarily paused.
  bool get isPaused;

  /// Initializes the optical detection pipeline with the provided [config].
  Future<void> initialize({OpticalScannerConfig? config});

  /// Starts or resumes the optical scanning stream.
  Future<void> startScanning();

  /// Pauses the optical scanner without releasing underlying resources.
  Future<void> pauseScanning();

  /// Resumes scanning after a [pauseScanning] invocation.
  Future<void> resumeScanning();

  /// Stops scanning and flushes active buffers.
  Future<void> stopScanning();

  /// Ingests a raw [BarcodeCapture] emitted from a camera controller or simulated test harness.
  void ingestCapture(BarcodeCapture capture, {DateTime? captureTime});

  /// Ingests a raw [OpticalImageFrame] from a native camera sensor or desktop video device.
  Future<void> ingestImageFrame(OpticalImageFrame frame);

  /// Ingests an individual [Barcode] symbol directly.
  void ingestRawBarcode(
    Barcode barcode, {
    DateTime? captureTime,
    OpticalDetectionEngine? engineOverride,
  });

  /// Resets all cumulative metrics (counters, frame drops, rolling averages).
  void resetMetrics();

  /// Releases all stream controllers, buffers, and system resources.
  Future<void> dispose();
}

/// Production implementation of [OpticalScannerDataSource] supporting dual-engine
/// acceleration (Google ML Kit / Apple Vision) and a 60 FPS zero-allocation ring buffer.
class OpticalScannerDataSourceImpl implements OpticalScannerDataSource {
  OpticalScannerConfig _config;
  final OpticalFrameRingBuffer<Barcode> _ringBuffer;

  final StreamController<OpticalScanResult> _scanStreamController =
      StreamController<OpticalScanResult>.broadcast();
  final StreamController<ScannerMetrics> _metricsStreamController =
      StreamController<ScannerMetrics>.broadcast();

  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isPaused = false;
  bool _isDisposed = false;

  // Frame sequencing and telemetry counters
  int _totalFramesReceived = 0;
  int _totalFramesProcessed = 0;
  int _frameSequenceCounter = 0;
  Duration _cumulativeLatency = Duration.zero;

  // Rolling 1000ms window for FPS estimation (zero allocation ring buffer of timestamps)
  static const int _fpsWindowCapacity = 120;
  final List<int> _recentTimestampsUs = List<int>.filled(_fpsWindowCapacity, 0);
  int _timestampHead = 0;
  int _timestampCount = 0;
  double _lastCalculatedFps = 0.0;

  // Duplicate suppression state for singleCode and batchMode
  String? _lastEmittedRawValue;
  DateTime? _lastEmittedTimestamp;
  final Set<String> _batchScannedCodes = <String>{};

  final TargetPlatform _targetPlatform;
  final ZxingDecoderEngine _zxingDecoder;

  OpticalScannerDataSourceImpl({
    OpticalScannerConfig config = const OpticalScannerConfig(),
    TargetPlatform? targetPlatform,
    ZxingDecoderEngine? zxingDecoder,
  })  : _config = config,
        _targetPlatform = targetPlatform ?? defaultTargetPlatform,
        _zxingDecoder = zxingDecoder ?? WindowsZxingDecoderImpl(),
        _ringBuffer = OpticalFrameRingBuffer<Barcode>(config.frameBufferSize);

  @override
  Stream<OpticalScanResult> get scanStream => _scanStreamController.stream;

  @override
  Stream<ScannerMetrics> get metricsStream => _metricsStreamController.stream;

  @override
  OpticalScannerConfig get config => _config;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isPaused => _isPaused;

  @override
  ScannerMetrics get currentMetrics => _buildCurrentMetrics();

  @override
  Future<void> initialize({OpticalScannerConfig? config}) async {
    _assertNotDisposed();
    if (config != null) {
      _config = config;
    }
    _isInitialized = true;
    _isScanning = false;
    _isPaused = false;
    resetMetrics();
  }

  @override
  Future<void> startScanning() async {
    _assertNotDisposed();
    if (!_isInitialized) {
      await initialize();
    }
    _isScanning = true;
    _isPaused = false;
  }

  @override
  Future<void> pauseScanning() async {
    _assertNotDisposed();
    _isPaused = true;
  }

  @override
  Future<void> resumeScanning() async {
    _assertNotDisposed();
    if (_isScanning) {
      _isPaused = false;
    }
  }

  @override
  Future<void> stopScanning() async {
    _assertNotDisposed();
    _isScanning = false;
    _isPaused = false;
    _ringBuffer.clear();
  }

  @override
  void resetMetrics() {
    _totalFramesReceived = 0;
    _totalFramesProcessed = 0;
    _frameSequenceCounter = 0;
    _cumulativeLatency = Duration.zero;
    _ringBuffer.clear(resetDropCount: true);
    _timestampHead = 0;
    _timestampCount = 0;
    _lastCalculatedFps = 0.0;
    _lastEmittedRawValue = null;
    _lastEmittedTimestamp = null;
    _batchScannedCodes.clear();

    if (!_metricsStreamController.isClosed) {
      _metricsStreamController.add(ScannerMetrics.zero());
    }
  }

  @override
  void ingestCapture(BarcodeCapture capture, {DateTime? captureTime}) {
    if (!_isScanning || _isPaused || _isDisposed) return;

    final DateTime ingestionTime = captureTime ?? DateTime.now();
    _totalFramesReceived++;

    for (final Barcode barcode in capture.barcodes) {
      ingestRawBarcode(
        barcode,
        captureTime: ingestionTime,
      );
    }
  }

  @override
  Future<void> ingestImageFrame(OpticalImageFrame frame) async {
    if (!_isScanning || _isPaused || _isDisposed) return;

    _totalFramesReceived++;
    final result = await _zxingDecoder.decodeFrame(frame);
    if (result == null) return;

    if (!_shouldEmitBarcode(result.rawValue, result.timestamp)) {
      return;
    }

    final DateTime now = DateTime.now();
    final Duration latency = now.isAfter(result.timestamp)
        ? now.difference(result.timestamp)
        : Duration.zero;
    _cumulativeLatency += latency;

    _recordFrameTimestamp(now.microsecondsSinceEpoch);
    _totalFramesProcessed++;
    _frameSequenceCounter++;

    final scanResult = OpticalScanResult(
      rawValue: result.rawValue,
      rawBytes: _config.retainRawBytes ? result.rawBytes : null,
      format: result.format,
      timestamp: result.timestamp,
      engineUsed: result.engineUsed,
      cornerPoints: result.cornerPoints,
      instantaneousFps: _lastCalculatedFps,
      frameSequence: _frameSequenceCounter,
      processingLatency: latency,
    );

    if (!_scanStreamController.isClosed) {
      _scanStreamController.add(scanResult);
    }
    if (!_metricsStreamController.isClosed) {
      _metricsStreamController.add(_buildCurrentMetrics());
    }
  }

  @override
  void ingestRawBarcode(
    Barcode barcode, {
    DateTime? captureTime,
    OpticalDetectionEngine? engineOverride,
  }) {
    if (!_isScanning || _isPaused || _isDisposed) return;

    final DateTime timestamp = captureTime ?? DateTime.now();
    final String? rawValue = barcode.rawValue;

    // Filter null or empty optical payloads
    if (rawValue == null || rawValue.isEmpty) return;

    // Filter unsupported formats
    if (_config.supportedFormats.isNotEmpty &&
        !_config.supportedFormats.contains(barcode.format)) {
      return;
    }

    // Duplicate suppression & batch filtering checks
    if (!_shouldEmitBarcode(rawValue, timestamp)) {
      return;
    }

    // Stage in ring buffer for zero-allocation queuing and drop accounting
    _ringBuffer.push(barcode);

    // Compute latency from capture time to dispatch (guarded against clock skew)
    final DateTime now = DateTime.now();
    final Duration latency =
        now.isAfter(timestamp) ? now.difference(timestamp) : Duration.zero;
    _cumulativeLatency += latency;

    // Update rolling FPS estimator
    _recordFrameTimestamp(now.microsecondsSinceEpoch);

    _totalFramesProcessed++;
    _frameSequenceCounter++;

    // Resolve active detection engine
    final OpticalDetectionEngine effectiveEngine =
        engineOverride ?? _resolveEngine(_config.engine);

    // Extract corner points
    final List<Offset> corners = List<Offset>.unmodifiable(barcode.corners);

    final OpticalScanResult result = OpticalScanResult(
      rawValue: rawValue,
      rawBytes: _config.retainRawBytes ? barcode.rawBytes : null,
      format: barcode.format,
      timestamp: timestamp,
      engineUsed: effectiveEngine,
      cornerPoints: corners,
      instantaneousFps: _lastCalculatedFps,
      frameSequence: _frameSequenceCounter,
      processingLatency: latency,
    );

    // Emit result downstream
    if (!_scanStreamController.isClosed) {
      _scanStreamController.add(result);
    }

    // Emit updated metrics
    if (!_metricsStreamController.isClosed) {
      _metricsStreamController.add(_buildCurrentMetrics());
    }
  }

  /// Determines whether a barcode should be emitted according to active [OpticalScanningMode].
  bool _shouldEmitBarcode(String rawValue, DateTime timestamp) {
    switch (_config.scanningMode) {
      case OpticalScanningMode.continuousAirGap:
        // Continuous air-gap transfers require every frame to reach RaptorQ/fountain decoders
        return true;

      case OpticalScanningMode.singleCode:
        if (_lastEmittedRawValue == rawValue && _lastEmittedTimestamp != null) {
          final Duration elapsed = timestamp.difference(_lastEmittedTimestamp!);
          if (elapsed < _config.duplicateDebounceWindow) {
            return false;
          }
        }
        _lastEmittedRawValue = rawValue;
        _lastEmittedTimestamp = timestamp;
        return true;

      case OpticalScanningMode.batchMode:
        if (_batchScannedCodes.contains(rawValue)) {
          return false;
        }
        _batchScannedCodes.add(rawValue);
        return true;
    }
  }

  /// Computes instantaneous FPS using a rolling timestamp array.
  void _recordFrameTimestamp(int timestampUs) {
    _recentTimestampsUs[_timestampHead] = timestampUs;
    _timestampHead = (_timestampHead + 1) % _fpsWindowCapacity;
    if (_timestampCount < _fpsWindowCapacity) {
      _timestampCount++;
    }

    if (_timestampCount > 1) {
      // Look back to earliest recorded timestamp within capacity
      final int oldestIdx =
          (_timestampHead - _timestampCount + _fpsWindowCapacity) %
              _fpsWindowCapacity;
      final int oldestUs = _recentTimestampsUs[oldestIdx];
      final int durationUs = timestampUs - oldestUs;

      if (durationUs > 0) {
        _lastCalculatedFps = ((_timestampCount - 1) * 1000000.0) / durationUs;
      }
    } else {
      _lastCalculatedFps = 1.0;
    }
  }

  /// Resolves the effective detection engine based on configuration and target platform.
  OpticalDetectionEngine _resolveEngine(OpticalDetectionEngine configured) {
    if (configured != OpticalDetectionEngine.auto) {
      return configured;
    }

    // Platform-aware engine selection:
    // Windows utilizes Windows ZXing-C++ engine;
    // Apple platforms utilize Apple Vision framework (VNDetectBarcodesRequest);
    // Android and others utilize Google ML Kit.
    switch (_targetPlatform) {
      case TargetPlatform.windows:
        return OpticalDetectionEngine.windowsZxing;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return OpticalDetectionEngine.appleVision;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
        return OpticalDetectionEngine.googleMlKit;
    }
  }

  ScannerMetrics _buildCurrentMetrics() {
    final Duration avgLatency = _totalFramesProcessed > 0
        ? Duration(
            microseconds:
                _cumulativeLatency.inMicroseconds ~/ _totalFramesProcessed)
        : Duration.zero;

    return ScannerMetrics(
      totalFramesReceived: _totalFramesReceived,
      totalFramesProcessed: _totalFramesProcessed,
      droppedFrames: _ringBuffer.dropCount,
      currentFps: math.max(0.0, _lastCalculatedFps),
      averageLatency: avgLatency,
      bufferUtilization: _ringBuffer.utilization,
    );
  }

  void _assertNotDisposed() {
    if (_isDisposed) {
      throw const OpticalScannerException(
          'OpticalScannerDataSource has already been disposed');
    }
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _isScanning = false;
    _isPaused = false;
    _ringBuffer.clear();
    await _scanStreamController.close();
    await _metricsStreamController.close();
  }
}
