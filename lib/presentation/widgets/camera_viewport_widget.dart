import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Configuration options for the hardware camera viewport and targeting reticle.
class CameraViewportConfig {
  /// Aspect ratio of the central target scanning window (width / height).
  final double scanWindowAspectRatio;

  /// Width ratio of the target scanning window relative to the screen width (0.0 to 1.0).
  final double scanWindowWidthRatio;

  /// Reticle stroke color when actively scanning.
  final Color reticleColor;

  /// Reticle corner bracket stroke width in logical pixels.
  final double reticleStrokeWidth;

  /// Reticle corner bracket length in logical pixels.
  final double reticleCornerLength;

  /// Whether to display the animated vertical laser scanline.
  final bool showLaserScanline;

  /// Color of the animated laser scanline.
  final Color laserColor;

  /// Default zoom scale applied at initialization (0.0 = 1x wide to 1.0 = maximum optical/digital zoom).
  final double initialZoom;

  /// Minimum zoom factor allowed for pinch gesture.
  final double minZoom;

  /// Maximum zoom factor allowed for pinch gesture.
  final double maxZoom;

  /// Whether torch control button is visible in viewport overlay.
  final bool showTorchControl;

  /// Whether camera flip button (front/back) is visible in viewport overlay.
  final bool showCameraFlipControl;

  /// Whether zoom indicator badge is visible in viewport overlay.
  final bool showZoomBadge;

  const CameraViewportConfig({
    this.scanWindowAspectRatio = 1.0,
    this.scanWindowWidthRatio = 0.72,
    this.reticleColor = const Color(0xFF00E5FF),
    this.reticleStrokeWidth = 3.5,
    this.reticleCornerLength = 28.0,
    this.showLaserScanline = true,
    this.laserColor = const Color(0xFF00E5FF),
    this.initialZoom = 0.0,
    this.minZoom = 0.0,
    this.maxZoom = 1.0,
    this.showTorchControl = true,
    this.showCameraFlipControl = true,
    this.showZoomBadge = true,
  })  : assert(scanWindowWidthRatio > 0.0 && scanWindowWidthRatio <= 1.0,
            'Scan window width ratio must be > 0.0 and <= 1.0'),
        assert(minZoom >= 0.0 && minZoom <= maxZoom,
            'minZoom must be >= 0.0 and <= maxZoom');
}

/// A production-grade, low-latency camera viewport widget providing:
/// - Hardware-accelerated viewport targeting with constrained scanWindow.
/// - Automatic OS lifecycle binding (pauses sensor when backgrounded, resumes when active).
/// - Smooth pinch-to-zoom and double-tap zoom gestures.
/// - Hardware torch toggle and camera flip controls.
/// - Animated high-contrast targeting reticle and scanning laser.
class CameraViewportWidget extends StatefulWidget {
  /// Callback triggered when one or more optical barcodes are ingested by the sensor.
  final void Function(BarcodeCapture capture)? onDetect;

  /// Optional pre-injected scanner controller for dependency injection and testing.
  final MobileScannerController? controller;

  /// Visual and behavior configuration.
  final CameraViewportConfig config;

  /// Optional placeholder displayed when camera permissions are denied or unavailable.
  final Widget? errorBuilder;

  const CameraViewportWidget({
    super.key,
    this.onDetect,
    this.controller,
    this.config = const CameraViewportConfig(),
    this.errorBuilder,
  });

  @override
  State<CameraViewportWidget> createState() => CameraViewportWidgetState();
}

class CameraViewportWidgetState extends State<CameraViewportWidget>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  bool _isControllerInternal = false;

  late AnimationController _laserAnimationController;
  late Animation<double> _laserAnimation;

  double _currentZoom = 0.0;
  double _baseZoom = 0.0;
  bool _isTorchOn = false;
  CameraFacing _currentFacing = CameraFacing.back;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initController();
    _initLaserAnimation();
  }

  void _initController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _isControllerInternal = false;
    } else {
      _controller = MobileScannerController(
        facing: CameraFacing.back,
        detectionSpeed: DetectionSpeed.unrestricted,
        returnImage: false,
        autoStart: true,
      );
      _isControllerInternal = true;
    }
    _currentZoom = widget.config.initialZoom;
  }

  void _initLaserAnimation() {
    _laserAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _laserAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _laserAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.config.showLaserScanline) {
      _laserAnimationController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Automatic hardware lifecycle management
    switch (state) {
      case AppLifecycleState.resumed:
        // Re-engage hardware camera sensor
        if (!_controller.value.isRunning) {
          _controller.start();
        }
        if (widget.config.showLaserScanline &&
            !_laserAnimationController.isAnimating) {
          _laserAnimationController.repeat(reverse: true);
        }
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Suspend camera sensor to eliminate thermal heating and battery exfiltration
        if (_controller.value.isRunning) {
          _controller.stop();
        }
        if (_laserAnimationController.isAnimating) {
          _laserAnimationController.stop();
        }
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimationController.dispose();

    if (_isControllerInternal) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Toggles hardware flashlight state.
  Future<void> toggleTorch() async {
    try {
      await _controller.toggleTorch();
      setState(() {
        _isTorchOn = !_isTorchOn;
      });
    } catch (_) {
      // Ignored if hardware torch is unavailable
    }
  }

  /// Switches between front and back camera lenses.
  Future<void> switchCamera() async {
    try {
      await _controller.switchCamera();
      setState(() {
        _currentFacing = _currentFacing == CameraFacing.back
            ? CameraFacing.front
            : CameraFacing.back;
      });
    } catch (_) {
      // Ignored if device lacks secondary camera
    }
  }

  /// Sets zoom scale directly (clamped between minZoom and maxZoom).
  Future<void> setZoom(double zoom) async {
    final clamped = zoom.clamp(widget.config.minZoom, widget.config.maxZoom);
    try {
      await _controller.setZoomScale(clamped);
      setState(() {
        _currentZoom = clamped;
      });
    } catch (_) {
      // Ignored if zoom hardware command fails
    }
  }

  /// Resets zoom back to minimum wide-angle setting.
  Future<void> resetZoom() async {
    await setZoom(widget.config.minZoom);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale == 1.0) return;
    // Scale sensitivity multiplier
    final double delta = (details.scale - 1.0) * 0.75;
    final double targetZoom = (_baseZoom + delta).clamp(
      widget.config.minZoom,
      widget.config.maxZoom,
    );
    setZoom(targetZoom);
  }

  void _handleDoubleTap() {
    // Quick zoom toggle: 0.0 -> 0.4 -> 0.0
    if (_currentZoom < 0.2) {
      setZoom(0.4);
    } else {
      resetZoom();
    }
  }

  Rect _calculateScanWindow(Size screenSize) {
    final double windowWidth =
        screenSize.width * widget.config.scanWindowWidthRatio;
    final double windowHeight =
        windowWidth / widget.config.scanWindowAspectRatio;

    final double left = (screenSize.width - windowWidth) / 2.0;
    final double top = (screenSize.height - windowHeight) / 2.0;

    return Rect.fromLTWH(left, top, windowWidth, windowHeight);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewportSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        final Rect scanWindow = _calculateScanWindow(viewportSize);

        return GestureDetector(
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onDoubleTap: _handleDoubleTap,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Hardware Camera Feed with Constrained ScanWindow
              MobileScanner(
                controller: _controller,
                scanWindow: scanWindow,
                onDetect: (BarcodeCapture capture) {
                  widget.onDetect?.call(capture);
                },
                errorBuilder: (BuildContext context,
                    MobileScannerException error, Widget? child) {
                  if (widget.errorBuilder != null) {
                    return widget.errorBuilder!;
                  }
                  return _buildDefaultErrorState(error);
                },
              ),

              // 2. Translucent Mask with Cutout for Target ScanWindow
              CustomPaint(
                painter: _ViewportOverlayPainter(
                  scanWindow: scanWindow,
                  config: widget.config,
                ),
                size: Size.infinite,
              ),

              // 3. Animated Laser Scanline
              if (widget.config.showLaserScanline)
                AnimatedBuilder(
                  animation: _laserAnimation,
                  builder: (BuildContext context, Widget? child) {
                    final double laserY = scanWindow.top +
                        (_laserAnimation.value * scanWindow.height);
                    return Positioned(
                      left: scanWindow.left + 4,
                      top: laserY,
                      width: scanWindow.width - 8,
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: widget.config.laserColor,
                          boxShadow: [
                            BoxShadow(
                              color: widget.config.laserColor
                                  .withValues(alpha: 0.8),
                              blurRadius: 8.0,
                              spreadRadius: 1.5,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              // 4. Overlaid Quick Hardware Controls & Zoom Badge
              _buildControlOverlay(scanWindow),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlOverlay(Rect scanWindow) {
    return Positioned(
      bottom: 24,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Flashlight / Torch Toggle
            if (widget.config.showTorchControl)
              IconButton.filledTonal(
                onPressed: toggleTorch,
                icon: Icon(
                  _isTorchOn ? Icons.flash_on : Icons.flash_off,
                  color: _isTorchOn ? Colors.amber : Colors.white70,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                tooltip: 'Toggle Flashlight',
              ),

            // Zoom Badge
            if (widget.config.showZoomBadge)
              GestureDetector(
                onTap: _handleDoubleTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    '${(1.0 + _currentZoom * 3.0).toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),

            // Camera Flip Toggle
            if (widget.config.showCameraFlipControl)
              IconButton.filledTonal(
                onPressed: switchCamera,
                icon: const Icon(
                  Icons.flip_camera_ios,
                  color: Colors.white70,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                tooltip: 'Switch Camera',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultErrorState(MobileScannerException error) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            color: Colors.redAccent,
            size: 56,
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera Ingestion Sensor Offline',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.errorCode.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering the darkened outer mask and targeting corner brackets.
class _ViewportOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final CameraViewportConfig config;

  _ViewportOverlayPainter({
    required this.scanWindow,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screenRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 1. Darkened Outer Mask with ScanWindow Cutout (PathFillType.evenOdd)
    final Path maskPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(screenRect)
      ..addRRect(
          RRect.fromRectAndRadius(scanWindow, const Radius.circular(16)));

    final Paint maskPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // 2. Draw 4 Corner Reticle Brackets
    final Paint reticlePaint = Paint()
      ..color = config.reticleColor
      ..strokeWidth = config.reticleStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double l = config.reticleCornerLength;
    final double left = scanWindow.left;
    final double top = scanWindow.top;
    final double right = scanWindow.right;
    final double bottom = scanWindow.bottom;

    // Top-Left Corner
    final Path tlPath = Path()
      ..moveTo(left, top + l)
      ..lineTo(left, top + 12)
      ..arcToPoint(Offset(left + 12, top), radius: const Radius.circular(12))
      ..lineTo(left + l, top);
    canvas.drawPath(tlPath, reticlePaint);

    // Top-Right Corner
    final Path trPath = Path()
      ..moveTo(right - l, top)
      ..lineTo(right - 12, top)
      ..arcToPoint(Offset(right, top + 12), radius: const Radius.circular(12))
      ..lineTo(right, top + l);
    canvas.drawPath(trPath, reticlePaint);

    // Bottom-Left Corner
    final Path blPath = Path()
      ..moveTo(left, bottom - l)
      ..lineTo(left, bottom - 12)
      ..arcToPoint(Offset(left + 12, bottom), radius: const Radius.circular(12))
      ..lineTo(left + l, bottom);
    canvas.drawPath(blPath, reticlePaint);

    // Bottom-Right Corner
    final Path brPath = Path()
      ..moveTo(right - l, bottom)
      ..lineTo(right - 12, bottom)
      ..arcToPoint(Offset(right, bottom - 12),
          radius: const Radius.circular(12))
      ..lineTo(right, bottom - l);
    canvas.drawPath(brPath, reticlePaint);
  }

  @override
  bool shouldRepaint(covariant _ViewportOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow || oldDelegate.config != config;
  }
}
