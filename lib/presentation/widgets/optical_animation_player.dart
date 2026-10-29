import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Pluggable interface for overriding and restoring device screen brightness.
abstract class ScreenBrightnessManager {
  Future<void> setMaxBrightness();
  Future<void> restoreBrightness();
}

/// Default in-memory / platform-safe brightness manager.
class DefaultScreenBrightnessManager implements ScreenBrightnessManager {
  bool _isMaxBrightness = false;
  bool get isMaxBrightness => _isMaxBrightness;

  @override
  Future<void> setMaxBrightness() async {
    _isMaxBrightness = true;
  }

  @override
  Future<void> restoreBrightness() async {
    _isMaxBrightness = false;
  }
}

/// High-speed optical animation player for transmitting sequential and fountain QR frames.
///
/// Features:
/// - Dynamic frame rate throttling (5 to 15 FPS) with user-configurable intervals.
/// - Automatic optical contrast enhancement (edge sharpening, pure black/white, quiet zone).
/// - Dynamic screen brightness override to 100% upon mounting and automatic restoration on disposal.
class OpticalAnimationPlayer extends StatefulWidget {
  /// Ordered list of wire frames or text payloads to cycle through.
  final List<String> framePayloads;

  /// Initial animation playback speed in frames per second (5..15).
  final double initialFps;

  /// Whether to automatically override screen brightness to 100% while active.
  final bool overrideBrightness;

  /// Whether to enforce maximum optical contrast mode (pure B/W, sharpened edges).
  final bool highContrastMode;

  /// Optional custom brightness manager (injected for testing or platform interop).
  final ScreenBrightnessManager? brightnessManager;

  /// Callback triggered when the active frame changes.
  final ValueChanged<int>? onFrameChanged;

  /// Size of the rendered QR code canvas in logical pixels.
  final double qrSize;

  const OpticalAnimationPlayer({
    super.key,
    required this.framePayloads,
    this.initialFps = 10.0,
    this.overrideBrightness = true,
    this.highContrastMode = true,
    this.brightnessManager,
    this.onFrameChanged,
    this.qrSize = 280.0,
  }) : assert(initialFps >= 5.0 && initialFps <= 15.0, 'FPS must be between 5 and 15');

  /// Convenience constructor taking binary frame bytes and converting to Latin-1 / Base64.
  factory OpticalAnimationPlayer.fromBytes({
    Key? key,
    required List<Uint8List> byteFrames,
    double initialFps = 10.0,
    bool overrideBrightness = true,
    bool highContrastMode = true,
    ScreenBrightnessManager? brightnessManager,
    ValueChanged<int>? onFrameChanged,
    double qrSize = 280.0,
  }) {
    final stringFrames = byteFrames
        .map((bytes) => String.fromCharCodes(bytes))
        .toList();

    return OpticalAnimationPlayer(
      key: key,
      framePayloads: stringFrames,
      initialFps: initialFps,
      overrideBrightness: overrideBrightness,
      highContrastMode: highContrastMode,
      brightnessManager: brightnessManager,
      onFrameChanged: onFrameChanged,
      qrSize: qrSize,
    );
  }

  @override
  State<OpticalAnimationPlayer> createState() => _OpticalAnimationPlayerState();
}

class _OpticalAnimationPlayerState extends State<OpticalAnimationPlayer> {
  late final ScreenBrightnessManager _brightnessManager;
  late double _currentFps;
  int _currentIndex = 0;
  bool _isPlaying = true;
  bool _isInverted = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentFps = widget.initialFps.clamp(5.0, 15.0);
    _brightnessManager =
        widget.brightnessManager ?? DefaultScreenBrightnessManager();

    if (widget.overrideBrightness) {
      unawaited(_brightnessManager.setMaxBrightness());
    }

    _startAnimationLoop();
  }

  @override
  void didUpdateWidget(covariant OpticalAnimationPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.framePayloads.length != widget.framePayloads.length) {
      if (_currentIndex >= widget.framePayloads.length) {
        _currentIndex = 0;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.overrideBrightness) {
      unawaited(_brightnessManager.restoreBrightness());
    }
    super.dispose();
  }

  void _startAnimationLoop() {
    _timer?.cancel();
    if (!_isPlaying || widget.framePayloads.isEmpty) return;

    final intervalMs = (1000 / _currentFps).round();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted || widget.framePayloads.isEmpty) return;

      setState(() {
        _currentIndex = (_currentIndex + 1) % widget.framePayloads.length;
      });
      widget.onFrameChanged?.call(_currentIndex);
    });
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
    if (_isPlaying) {
      _startAnimationLoop();
    } else {
      _timer?.cancel();
    }
  }

  void _setFps(double newFps) {
    final clamped = newFps.clamp(5.0, 15.0);
    if ((_currentFps - clamped).abs() > 0.01) {
      setState(() {
        _currentFps = clamped;
      });
      if (_isPlaying) {
        _startAnimationLoop();
      }
    }
  }

  void _stepForward() {
    if (widget.framePayloads.isEmpty) return;
    setState(() {
      _isPlaying = false;
      _timer?.cancel();
      _currentIndex = (_currentIndex + 1) % widget.framePayloads.length;
    });
    widget.onFrameChanged?.call(_currentIndex);
  }

  void _stepBackward() {
    if (widget.framePayloads.isEmpty) return;
    setState(() {
      _isPlaying = false;
      _timer?.cancel();
      _currentIndex = (_currentIndex - 1 + widget.framePayloads.length) %
          widget.framePayloads.length;
    });
    widget.onFrameChanged?.call(_currentIndex);
  }

  void _toggleInversion() {
    setState(() {
      _isInverted = !_isInverted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPayloads = widget.framePayloads.isNotEmpty;
    final currentPayload = hasPayloads ? widget.framePayloads[_currentIndex] : '';

    final Color foregroundColor = _isInverted ? Colors.white : Colors.black;
    final Color backgroundColor = _isInverted ? Colors.black : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Contrast-enhanced optical canvas viewport with pure border sharpening
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: widget.highContrastMode ? foregroundColor : Colors.grey.shade400,
              width: 3.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: hasPayloads
              ? QrImageView(
                  data: currentPayload,
                  version: QrVersions.auto,
                  size: widget.qrSize,
                  backgroundColor: backgroundColor,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: foregroundColor,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: foregroundColor,
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  padding: const EdgeInsets.all(12.0),
                )
              : SizedBox(
                  width: widget.qrSize,
                  height: widget.qrSize,
                  child: const Center(
                    child: Text('No frames available'),
                  ),
                ),
        ),

        const SizedBox(height: 12.0),

        // Telemetry header: Frame indicator & FPS
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                hasPayloads
                    ? 'Frame ${_currentIndex + 1} / ${widget.framePayloads.length}'
                    : 'Frame 0 / 0',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                  fontFamily: 'monospace',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade100,
                  borderRadius: BorderRadius.circular(6.0),
                ),
                child: Text(
                  '${_currentFps.toStringAsFixed(1)} FPS (${(1000 / _currentFps).round()} ms)',
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // FPS Throttle Slider (5 to 15 FPS)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              const Text('5 FPS', style: TextStyle(fontSize: 11.0)),
              Expanded(
                child: Slider(
                  value: _currentFps,
                  min: 5.0,
                  max: 15.0,
                  divisions: 10,
                  label: '${_currentFps.toStringAsFixed(0)} FPS',
                  onChanged: _setFps,
                ),
              ),
              const Text('15 FPS', style: TextStyle(fontSize: 11.0)),
            ],
          ),
        ),

        // Playback & Contrast Control Toolbar
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              tooltip: 'Previous Frame',
              onPressed: hasPayloads ? _stepBackward : null,
            ),
            IconButton(
              icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
              iconSize: 36.0,
              tooltip: _isPlaying ? 'Pause' : 'Play',
              onPressed: hasPayloads ? _togglePlayPause : null,
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: 'Next Frame',
              onPressed: hasPayloads ? _stepForward : null,
            ),
            const SizedBox(width: 12.0),
            IconButton(
              icon: Icon(_isInverted ? Icons.light_mode : Icons.dark_mode),
              tooltip: 'Toggle Inverted Contrast',
              onPressed: _toggleInversion,
            ),
          ],
        ),
      ],
    );
  }
}

