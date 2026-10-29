import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

/// Available geometric styling for standard data and function modules.
enum QrModuleShape {
  /// Traditional sharp square module.
  square,

  /// Circular module centered within the module cell.
  circle,

  /// Rounded rectangle with customizable corner curvature.
  roundedSquare,

  /// Diamond / rhombus module oriented at 45 degrees.
  diamond,

  /// Fluid organic module that connects smoothly with adjacent dark modules.
  fluid,
}

/// Available geometric styling for the 7x7 outer frame of finder patterns (eyes).
enum QrEyeFrameShape {
  /// Standard sharp square border.
  square,

  /// Uniformly rounded square border.
  roundedSquare,

  /// Circular annular ring.
  circle,

  /// Asymmetric leaf shape (top-left & bottom-right rounded, others sharp).
  leaf,
}

/// Available geometric styling for the 3x3 inner pupil of finder patterns (eyes).
enum QrEyePupilShape {
  /// Standard sharp square pupil.
  square,

  /// Uniformly rounded square pupil.
  roundedSquare,

  /// Circular dot pupil.
  circle,

  /// Diamond pupil rotated 45 degrees.
  diamond,
}

/// High-performance Canvas rendering configuration for stylized QR codes.
class QrStylerConfig {
  /// Shape of individual data and non-finder modules.
  final QrModuleShape moduleShape;

  /// Shape of the 7x7 outer eye frame for all 3 finder patterns.
  final QrEyeFrameShape eyeFrameShape;

  /// Shape of the 3x3 inner eye pupil for all 3 finder patterns.
  final QrEyePupilShape eyePupilShape;

  /// Primary color for data modules. Overridden if [dataGradient] is set.
  final Color dataColor;

  /// Optional gradient for data modules across the full matrix bounds.
  final Gradient? dataGradient;

  /// Dedicated color for outer eye frames. Defaults to [dataColor] if null.
  final Color? eyeFrameColor;

  /// Optional gradient for outer eye frames.
  final Gradient? eyeFrameGradient;

  /// Dedicated color for inner eye pupils. Defaults to [dataColor] if null.
  final Color? eyePupilColor;

  /// Optional gradient for inner eye pupils.
  final Gradient? eyePupilGradient;

  /// Background color surrounding all modules and filling the quiet zone.
  final Color backgroundColor;

  /// Width of quiet zone in module units (ISO/IEC 18004 specifies >= 4).
  final int quietZoneModules;

  /// Inner padding ratio inside each module cell (0.0 = edge-to-edge, 0.2 = 20% margin).
  final double modulePaddingRatio;

  /// Corner radius ratio for rounded squares (0.0 = sharp, 0.5 = fully rounded).
  final double cornerRadiusRatio;

  const QrStylerConfig({
    this.moduleShape = QrModuleShape.square,
    this.eyeFrameShape = QrEyeFrameShape.square,
    this.eyePupilShape = QrEyePupilShape.square,
    this.dataColor = Colors.black,
    this.dataGradient,
    this.eyeFrameColor,
    this.eyeFrameGradient,
    this.eyePupilColor,
    this.eyePupilGradient,
    this.backgroundColor = Colors.white,
    this.quietZoneModules = 4,
    this.modulePaddingRatio = 0.0,
    this.cornerRadiusRatio = 0.35,
  })  : assert(quietZoneModules >= 0, 'Quiet zone must be >= 0'),
        assert(modulePaddingRatio >= 0.0 && modulePaddingRatio <= 0.45,
            'Module padding must be between 0.0 and 0.45'),
        assert(cornerRadiusRatio >= 0.0 && cornerRadiusRatio <= 0.5,
            'Corner radius ratio must be between 0.0 and 0.5');

  /// High-contrast dark theme preset.
  static const QrStylerConfig darkTheme = QrStylerConfig(
    dataColor: Colors.white,
    backgroundColor: Color(0xFF121212),
    quietZoneModules: 4,
  );

  /// Modern rounded cyberpunk/neon gradient preset.
  static const QrStylerConfig neonFluid = QrStylerConfig(
    moduleShape: QrModuleShape.fluid,
    eyeFrameShape: QrEyeFrameShape.roundedSquare,
    eyePupilShape: QrEyePupilShape.circle,
    dataGradient: LinearGradient(
      colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    eyeFrameColor: Color(0xFF00E5FF),
    eyePupilColor: Color(0xFF7C4DFF),
    backgroundColor: Color(0xFF0A0E21),
    quietZoneModules: 4,
  );
}

/// A reactive Flutter widget that renders an ISO/IEC 18004 QR code matrix with
/// custom shapes, gradients, eye frames, and optical-contrast safe margins.
class QrCustomStylerCanvas extends StatelessWidget {
  /// The underlying domain QR code matrix model.
  final QrMatrix matrix;

  /// Visual styling configuration.
  final QrStylerConfig config;

  /// Desired size of the canvas (width and height).
  /// If null, expands to fill parent constraints while preserving square aspect ratio.
  final double? size;

  const QrCustomStylerCanvas({
    super.key,
    required this.matrix,
    this.config = const QrStylerConfig(),
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    Widget canvas = CustomPaint(
      painter: QrCustomStylerPainter(
        matrix: matrix,
        config: config,
      ),
      size: size != null ? Size(size!, size!) : Size.infinite,
    );

    if (size != null) {
      return SizedBox(
        width: size,
        height: size,
        child: canvas,
      );
    }

    return AspectRatio(
      aspectRatio: 1.0,
      child: canvas,
    );
  }
}

/// Underlying CustomPainter executing the geometric rendering of the QR matrix.
class QrCustomStylerPainter extends CustomPainter {
  final QrMatrix matrix;
  final QrStylerConfig config;

  const QrCustomStylerPainter({
    required this.matrix,
    required this.config,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    if (side <= 0) return;

    final double offsetX = (size.width - side) / 2.0;
    final double offsetY = (size.height - side) / 2.0;

    final int matrixSize = matrix.size;
    final int totalGridUnits = matrixSize + (config.quietZoneModules * 2);
    final double moduleSize = side / totalGridUnits;

    final Rect fullRect = Rect.fromLTWH(offsetX, offsetY, side, side);

    // 1. Fill Safe Quiet Zone / Background
    final Paint bgPaint = Paint()..color = config.backgroundColor;
    canvas.drawRect(fullRect, bgPaint);

    // 2. Prepare Paints & Shaders
    final Paint dataPaint = Paint()..style = PaintingStyle.fill;
    if (config.dataGradient != null) {
      dataPaint.shader = config.dataGradient!.createShader(fullRect);
    } else {
      dataPaint.color = config.dataColor;
    }

    // 3. Render 3 Finder Eyes (isolated from regular modules)
    _renderEye(
      canvas: canvas,
      matrixR: 0,
      matrixC: 0,
      offsetX: offsetX,
      offsetY: offsetY,
      moduleSize: moduleSize,
      fullRect: fullRect,
    );
    _renderEye(
      canvas: canvas,
      matrixR: 0,
      matrixC: matrixSize - 7,
      offsetX: offsetX,
      offsetY: offsetY,
      moduleSize: moduleSize,
      fullRect: fullRect,
    );
    _renderEye(
      canvas: canvas,
      matrixR: matrixSize - 7,
      matrixC: 0,
      offsetX: offsetX,
      offsetY: offsetY,
      moduleSize: moduleSize,
      fullRect: fullRect,
    );

    // 4. Render Data & Other Modules
    final double pad = moduleSize * config.modulePaddingRatio;

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        // Skip finder modules and separators (handled independently by _renderEye)
        if (_isFinderArea(r, c, matrixSize)) {
          continue;
        }

        if (matrix.getModule(r, c)) {
          final double left =
              offsetX + (c + config.quietZoneModules) * moduleSize + pad;
          final double top =
              offsetY + (r + config.quietZoneModules) * moduleSize + pad;
          final double effectiveSize = moduleSize - (pad * 2);
          final Rect moduleRect =
              Rect.fromLTWH(left, top, effectiveSize, effectiveSize);

          _drawModule(
            canvas: canvas,
            rect: moduleRect,
            paint: dataPaint,
            row: r,
            col: c,
            matrixSize: matrixSize,
          );
        }
      }
    }
  }

  bool _isFinderArea(int r, int c, int matrixSize) {
    // Top-left finder + separator
    if (r <= 7 && c <= 7) return true;
    // Top-right finder + separator
    if (r <= 7 && c >= matrixSize - 8) return true;
    // Bottom-left finder + separator
    if (r >= matrixSize - 8 && c <= 7) return true;
    return false;
  }

  void _renderEye({
    required Canvas canvas,
    required int matrixR,
    required int matrixC,
    required double offsetX,
    required double offsetY,
    required double moduleSize,
    required Rect fullRect,
  }) {
    final double left =
        offsetX + (matrixC + config.quietZoneModules) * moduleSize;
    final double top =
        offsetY + (matrixR + config.quietZoneModules) * moduleSize;
    final double eyeSize = moduleSize * 7.0;
    final Rect eyeRect = Rect.fromLTWH(left, top, eyeSize, eyeSize);

    // Configure Eye Frame Paint
    final Paint framePaint = Paint()..style = PaintingStyle.fill;
    if (config.eyeFrameGradient != null) {
      framePaint.shader = config.eyeFrameGradient!.createShader(eyeRect);
    } else if (config.eyeFrameColor != null) {
      framePaint.color = config.eyeFrameColor!;
    } else if (config.dataGradient != null) {
      framePaint.shader = config.dataGradient!.createShader(fullRect);
    } else {
      framePaint.color = config.dataColor;
    }

    // Configure Eye Pupil Paint
    final Paint pupilPaint = Paint()..style = PaintingStyle.fill;
    if (config.eyePupilGradient != null) {
      pupilPaint.shader = config.eyePupilGradient!.createShader(eyeRect);
    } else if (config.eyePupilColor != null) {
      pupilPaint.color = config.eyePupilColor!;
    } else if (config.dataGradient != null) {
      pupilPaint.shader = config.dataGradient!.createShader(fullRect);
    } else {
      pupilPaint.color = config.dataColor;
    }

    // Render Outer Frame (7x7 minus inner 5x5 cutout)
    _drawEyeFrame(canvas, eyeRect, moduleSize, framePaint);

    // Render Inner Pupil (3x3 center)
    final Rect pupilRect = Rect.fromLTWH(
      left + moduleSize * 2.0,
      top + moduleSize * 2.0,
      moduleSize * 3.0,
      moduleSize * 3.0,
    );
    _drawEyePupil(canvas, pupilRect, moduleSize, pupilPaint);
  }

  void _drawEyeFrame(
    Canvas canvas,
    Rect outerRect,
    double moduleSize,
    Paint paint,
  ) {
    final Rect innerCutout = Rect.fromLTWH(
      outerRect.left + moduleSize,
      outerRect.top + moduleSize,
      outerRect.width - (moduleSize * 2),
      outerRect.height - (moduleSize * 2),
    );

    final Path path = Path()..fillType = PathFillType.evenOdd;

    switch (config.eyeFrameShape) {
      case QrEyeFrameShape.square:
        path.addRect(outerRect);
        path.addRect(innerCutout);
        break;

      case QrEyeFrameShape.roundedSquare:
        final double outerRadius = moduleSize * 1.5;
        final double innerRadius = moduleSize * 0.8;
        path.addRRect(
            RRect.fromRectAndRadius(outerRect, Radius.circular(outerRadius)));
        path.addRRect(
            RRect.fromRectAndRadius(innerCutout, Radius.circular(innerRadius)));
        break;

      case QrEyeFrameShape.circle:
        path.addOval(outerRect);
        path.addOval(innerCutout);
        break;

      case QrEyeFrameShape.leaf:
        final double r = moduleSize * 2.5;
        path.addRRect(RRect.fromRectAndCorners(
          outerRect,
          topLeft: Radius.circular(r),
          bottomRight: Radius.circular(r),
          topRight: Radius.zero,
          bottomLeft: Radius.zero,
        ));
        path.addRRect(RRect.fromRectAndCorners(
          innerCutout,
          topLeft: Radius.circular(r * 0.6),
          bottomRight: Radius.circular(r * 0.6),
          topRight: Radius.zero,
          bottomLeft: Radius.zero,
        ));
        break;
    }

    canvas.drawPath(path, paint);
  }

  void _drawEyePupil(
    Canvas canvas,
    Rect pupilRect,
    double moduleSize,
    Paint paint,
  ) {
    switch (config.eyePupilShape) {
      case QrEyePupilShape.square:
        canvas.drawRect(pupilRect, paint);
        break;

      case QrEyePupilShape.roundedSquare:
        final double radius = moduleSize * 0.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(pupilRect, Radius.circular(radius)),
          paint,
        );
        break;

      case QrEyePupilShape.circle:
        canvas.drawOval(pupilRect, paint);
        break;

      case QrEyePupilShape.diamond:
        final Path path = Path()
          ..moveTo(pupilRect.center.dx, pupilRect.top)
          ..lineTo(pupilRect.right, pupilRect.center.dy)
          ..lineTo(pupilRect.center.dx, pupilRect.bottom)
          ..lineTo(pupilRect.left, pupilRect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;
    }
  }

  void _drawModule({
    required Canvas canvas,
    required Rect rect,
    required Paint paint,
    required int row,
    required int col,
    required int matrixSize,
  }) {
    switch (config.moduleShape) {
      case QrModuleShape.square:
        canvas.drawRect(rect, paint);
        break;

      case QrModuleShape.circle:
        canvas.drawOval(rect, paint);
        break;

      case QrModuleShape.roundedSquare:
        final double radius = rect.width * config.cornerRadiusRatio;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(radius)),
          paint,
        );
        break;

      case QrModuleShape.diamond:
        final Path path = Path()
          ..moveTo(rect.center.dx, rect.top)
          ..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)
          ..lineTo(rect.left, rect.center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;

      case QrModuleShape.fluid:
        _drawFluidModule(canvas, rect, paint, row, col, matrixSize);
        break;
    }
  }

  void _drawFluidModule(
    Canvas canvas,
    Rect rect,
    Paint paint,
    int r,
    int c,
    int size,
  ) {
    // Check neighbor connectivity
    final bool top =
        r > 0 && matrix.getModule(r - 1, c) && !_isFinderArea(r - 1, c, size);
    final bool bottom = r < size - 1 &&
        matrix.getModule(r + 1, c) &&
        !_isFinderArea(r + 1, c, size);
    final bool left =
        c > 0 && matrix.getModule(r, c - 1) && !_isFinderArea(r, c - 1, size);
    final bool right = c < size - 1 &&
        matrix.getModule(r, c + 1) &&
        !_isFinderArea(r, c + 1, size);

    final double cornerRadius = rect.width * 0.45;

    final RRect rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: (top || left) ? Radius.zero : Radius.circular(cornerRadius),
      topRight: (top || right) ? Radius.zero : Radius.circular(cornerRadius),
      bottomLeft:
          (bottom || left) ? Radius.zero : Radius.circular(cornerRadius),
      bottomRight:
          (bottom || right) ? Radius.zero : Radius.circular(cornerRadius),
    );

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant QrCustomStylerPainter oldDelegate) {
    return oldDelegate.matrix != matrix || oldDelegate.config != config;
  }
}
