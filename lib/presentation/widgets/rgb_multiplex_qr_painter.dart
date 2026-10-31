import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:airdrop_qr/domain/services/rgb_channel_splitter.dart';

/// High-performance [CustomPainter] rendering 3-channel RGB multiplexed QR codes at 60 FPS.
class RgbMultiplexQrPainter extends CustomPainter {
  final RgbMultiplexedColorMatrix colorMatrix;
  final Color backgroundColor;
  final double modulePaddingRatio;

  // Fixed cached Paint instances for all 8 composite RGB color permutations
  // to prevent garbage collection allocations during 60 FPS animations.
  static final List<Paint> _cachedColorPaints = [
    Paint()..color = const Color(0xFF000000), // 0: Black
    Paint()..color = const Color(0xFF0055FF), // 1: Blue
    Paint()..color = const Color(0xFF00FF44), // 2: Green
    Paint()..color = const Color(0xFF00FFFF), // 3: Cyan
    Paint()..color = const Color(0xFFFF2222), // 4: Red
    Paint()..color = const Color(0xFFFF00FF), // 5: Magenta
    Paint()..color = const Color(0xFFFFFF00), // 6: Yellow
    Paint()..color = const Color(0xFFFFFFFF), // 7: White
  ];

  late final Paint _backgroundPaint;

  RgbMultiplexQrPainter({
    required this.colorMatrix,
    this.backgroundColor = const Color(0xFF000000),
    this.modulePaddingRatio = 0.0,
  }) : _backgroundPaint = Paint()..color = backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw solid background
    canvas.drawRect(Offset.zero & size, _backgroundPaint);

    final matrixWidth = colorMatrix.width;
    final matrixHeight = colorMatrix.height;
    if (matrixWidth <= 0 || matrixHeight <= 0) return;

    // 2. Compute module scaling and centering
    final minCanvasDim = math.min(size.width, size.height);
    final maxMatrixDim = math.max(matrixWidth, matrixHeight);
    final moduleSize = minCanvasDim / maxMatrixDim;

    final offsetX = (size.width - (matrixWidth * moduleSize)) / 2.0;
    final offsetY = (size.height - (matrixHeight * moduleSize)) / 2.0;

    final padding = moduleSize * (modulePaddingRatio / 2.0);
    final innerModuleSize = moduleSize - (padding * 2.0);

    // 3. Batch render color modules
    for (int y = 0; y < matrixHeight; y++) {
      final moduleTop = offsetY + (y * moduleSize) + padding;
      for (int x = 0; x < matrixWidth; x++) {
        final code = colorMatrix.getColorCode(x, y);
        // Code 0 matches background, skip drawing to save GPU cycles
        if (code == 0) continue;

        final moduleLeft = offsetX + (x * moduleSize) + padding;
        final rect = Rect.fromLTWH(
          moduleLeft,
          moduleTop,
          innerModuleSize,
          innerModuleSize,
        );

        canvas.drawRect(rect, _cachedColorPaints[code]);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RgbMultiplexQrPainter oldDelegate) {
    return oldDelegate.colorMatrix != colorMatrix ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.modulePaddingRatio != modulePaddingRatio;
  }
}

/// Adaptive Flutter Widget presenting an RGB 3-channel optical multiplexed QR code.
class RgbMultiplexQrWidget extends StatelessWidget {
  final RgbMultiplexedColorMatrix colorMatrix;
  final Color backgroundColor;
  final double modulePaddingRatio;
  final double? size;

  const RgbMultiplexQrWidget({
    super.key,
    required this.colorMatrix,
    this.backgroundColor = const Color(0xFF000000),
    this.modulePaddingRatio = 0.0,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    Widget canvasWidget = CustomPaint(
      painter: RgbMultiplexQrPainter(
        colorMatrix: colorMatrix,
        backgroundColor: backgroundColor,
        modulePaddingRatio: modulePaddingRatio,
      ),
    );

    if (size != null) {
      return SizedBox(
        width: size,
        height: size,
        child: canvasWidget,
      );
    }

    return AspectRatio(
      aspectRatio: 1.0,
      child: canvasWidget,
    );
  }
}
