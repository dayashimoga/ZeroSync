import 'dart:async';
import 'package:flutter/foundation.dart';

/// Hardware thermal status levels mapped from native OS power/thermal engines
/// (Android PowerManager / iOS ProcessInfo).
enum DeviceThermalState {
  /// Normal device thermal operating conditions (< 39°C).
  nominal,

  /// Mild temperature rise (39°C - 42.9°C). Slight throttling applied.
  fair,

  /// Significant heat accumulation (43°C - 46.9°C). Aggressive frame drop applied.
  serious,

  /// Critical overheating threshold (>= 47°C). Severe downsampling to prevent shutdown.
  critical,
}

/// Policies governing optical frame rate and downsampling factors.
class ThermalThrottlePolicy {
  final int targetFps;
  final int downsampleFactor; // 1 = every frame, 2 = every 2nd frame, etc.
  final Duration minFrameInterval;

  const ThermalThrottlePolicy({
    required this.targetFps,
    required this.downsampleFactor,
    required this.minFrameInterval,
  });

  static const ThermalThrottlePolicy nominal = ThermalThrottlePolicy(
    targetFps: 60,
    downsampleFactor: 1,
    minFrameInterval: Duration(milliseconds: 16),
  );

  static const ThermalThrottlePolicy fair = ThermalThrottlePolicy(
    targetFps: 30,
    downsampleFactor: 2,
    minFrameInterval: Duration(milliseconds: 33),
  );

  static const ThermalThrottlePolicy serious = ThermalThrottlePolicy(
    targetFps: 15,
    downsampleFactor: 4,
    minFrameInterval: Duration(milliseconds: 66),
  );

  static const ThermalThrottlePolicy critical = ThermalThrottlePolicy(
    targetFps: 5,
    downsampleFactor: 8,
    minFrameInterval: Duration(milliseconds: 200),
  );
}

/// Manages camera sensor frame downsampling under thermal stress and enforces
/// automatic camera stream suspension after an inactivity timeout window.
class ThermalThrottleManager with ChangeNotifier {
  ThermalThrottleManager({
    Duration inactivityTimeout = const Duration(minutes: 3),
    Duration inactivityCheckInterval = const Duration(seconds: 1),
    DeviceThermalState initialThermalState = DeviceThermalState.nominal,
    void Function()? onSuspend,
    void Function()? onResume,
  })  : _inactivityTimeout = inactivityTimeout,
        _inactivityCheckInterval = inactivityCheckInterval,
        _thermalState = initialThermalState,
        _onSuspend = onSuspend,
        _onResume = onResume {
    _lastActivityTime = DateTime.now();
    _startInactivityTimer();
  }

  final Duration _inactivityTimeout;
  final Duration _inactivityCheckInterval;
  final void Function()? _onSuspend;
  final void Function()? _onResume;

  Timer? _inactivityTimer;
  DeviceThermalState _thermalState;
  double? _lastReportedTemperatureCelsius;

  late DateTime _lastActivityTime;
  DateTime _lastProcessedFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  int _totalFramesEvaluated = 0;
  int _totalFramesProcessed = 0;
  int _totalFramesThermalDropped = 0;

  bool _isSuspendedDueToInactivity = false;
  bool _isManuallyPaused = false;
  bool _isDisposed = false;

  // --- Getters ---

  DeviceThermalState get thermalState => _thermalState;
  double? get lastReportedTemperatureCelsius => _lastReportedTemperatureCelsius;
  bool get isSuspendedDueToInactivity => _isSuspendedDueToInactivity;
  bool get isManuallyPaused => _isManuallyPaused;
  bool get isCameraStreamingActive => !_isSuspendedDueToInactivity && !_isManuallyPaused;
  DateTime get lastActivityTime => _lastActivityTime;
  Duration get inactivityTimeout => _inactivityTimeout;

  int get totalFramesEvaluated => _totalFramesEvaluated;
  int get totalFramesProcessed => _totalFramesProcessed;
  int get totalFramesThermalDropped => _totalFramesThermalDropped;

  /// Retrieves the active throttle policy dictated by the current thermal status.
  ThermalThrottlePolicy get activePolicy {
    switch (_thermalState) {
      case DeviceThermalState.nominal:
        return ThermalThrottlePolicy.nominal;
      case DeviceThermalState.fair:
        return ThermalThrottlePolicy.fair;
      case DeviceThermalState.serious:
        return ThermalThrottlePolicy.serious;
      case DeviceThermalState.critical:
        return ThermalThrottlePolicy.critical;
    }
  }

  // --- Thermal Regulation & Frame Downsampling ---

  /// Updates device core temperature directly and recalculates thermal classification.
  void updateTemperature(double celsius) {
    if (_isDisposed) return;
    _lastReportedTemperatureCelsius = celsius;

    final DeviceThermalState newState;
    if (celsius < 39.0) {
      newState = DeviceThermalState.nominal;
    } else if (celsius < 43.0) {
      newState = DeviceThermalState.fair;
    } else if (celsius < 47.0) {
      newState = DeviceThermalState.serious;
    } else {
      newState = DeviceThermalState.critical;
    }

    setThermalState(newState);
  }

  /// Explicitly sets the device thermal state (e.g. from native platform channels).
  void setThermalState(DeviceThermalState newState) {
    if (_isDisposed) return;
    if (_thermalState != newState) {
      _thermalState = newState;
      notifyListeners();
    }
  }

  /// Determines whether an incoming camera frame should be decoded or dropped
  /// based on thermal throttling interval and downsample factors.
  bool shouldProcessFrame({DateTime? frameTimestamp}) {
    if (!isCameraStreamingActive) {
      return false;
    }

    _totalFramesEvaluated++;
    final DateTime now = frameTimestamp ?? DateTime.now();
    final ThermalThrottlePolicy policy = activePolicy;

    // Evaluate downsample factor modulo
    if (policy.downsampleFactor > 1) {
      if ((_totalFramesEvaluated % policy.downsampleFactor) != 0) {
        _totalFramesThermalDropped++;
        return false;
      }
    }

    // Evaluate minimum frame interval
    if (now.difference(_lastProcessedFrameTime) < policy.minFrameInterval) {
      _totalFramesThermalDropped++;
      return false;
    }

    _lastProcessedFrameTime = now;
    _totalFramesProcessed++;
    return true;
  }

  // --- Inactivity Sleep Engine ---

  /// Records user or optical interaction (e.g., successful QR detection, touch tap, UI navigation).
  ///
  /// Resets the inactivity countdown timer and automatically resumes camera stream if suspended.
  void recordInteraction() {
    if (_isDisposed) return;
    _lastActivityTime = DateTime.now();

    if (_isSuspendedDueToInactivity) {
      _isSuspendedDueToInactivity = false;
      _onResume?.call();
      notifyListeners();
    }
  }

  /// Manually pauses or resumes camera stream (e.g. when app moves to background).
  void setManuallyPaused(bool paused) {
    if (_isDisposed) return;
    if (_isManuallyPaused != paused) {
      _isManuallyPaused = paused;
      notifyListeners();
    }
  }

  /// Explicitly triggers an immediate check against the inactivity timeout window.
  void checkInactivity({DateTime? currentTime}) {
    if (_isDisposed || _isSuspendedDueToInactivity) return;

    final DateTime now = currentTime ?? DateTime.now();
    final Duration elapsed = now.difference(_lastActivityTime);

    if (elapsed >= _inactivityTimeout) {
      _isSuspendedDueToInactivity = true;
      _onSuspend?.call();
      notifyListeners();
    }
  }

  /// Resets frame counters and metrics.
  void resetMetrics() {
    _totalFramesEvaluated = 0;
    _totalFramesProcessed = 0;
    _totalFramesThermalDropped = 0;
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(_inactivityCheckInterval, (_) {
      checkInactivity();
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    super.dispose();
  }
}

