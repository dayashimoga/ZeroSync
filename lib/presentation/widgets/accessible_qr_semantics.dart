import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Mathematically precise WCAG 2.1 relative luminance and contrast ratio engine.
class WcagContrastRatio {
  WcagContrastRatio._();

  /// Calculates the relative luminance of a given [Color] according to WCAG 2.1 specifications.
  ///
  /// Formula: L = 0.2126 * R + 0.7152 * G + 0.0722 * B,
  /// where each sRGB component is normalized to 0.0-1.0 and linearized.
  static double calculateLuminance(Color color) {
    double linearize(double normalized) {
      return normalized <= 0.04045
          ? normalized / 12.92
          : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
    }

    final double r = linearize(color.r);
    final double g = linearize(color.g);
    final double b = linearize(color.b);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculates the contrast ratio between two colors: (L1 + 0.05) / (L2 + 0.05),
  /// where L1 is the lighter luminance and L2 is the darker luminance.
  static double calculateRatio(Color foreground, Color background) {
    final double l1 = calculateLuminance(foreground);
    final double l2 = calculateLuminance(background);

    final double lighter = math.max(l1, l2);
    final double darker = math.min(l1, l2);

    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Checks whether contrast satisfies WCAG 2.1 Level AA.
  ///
  /// - Normal text requires >= 4.5:1.
  /// - Large text (>= 18pt or >= 14pt bold) and UI components require >= 3.0:1.
  static bool isWcagAaCompliant(
    Color foreground,
    Color background, {
    bool isLargeTextOrGraphic = false,
  }) {
    final double ratio = calculateRatio(foreground, background);
    return isLargeTextOrGraphic ? ratio >= 3.0 : ratio >= 4.5;
  }

  /// Checks whether contrast satisfies WCAG 2.1 Level AAA (>= 7.0:1).
  static bool isWcagAaaCompliant(Color foreground, Color background) {
    return calculateRatio(foreground, background) >= 7.0;
  }
}

/// Accessible Semantics wrapper for static and generated QR code vector matrices.
class AccessibleQrCodeSemantics extends StatelessWidget {
  final Widget child;
  final String label;
  final String? value;
  final String? payloadType;
  final String? eccLevel;
  final bool isSensitive;

  const AccessibleQrCodeSemantics({
    super.key,
    required this.child,
    required this.label,
    this.value,
    this.payloadType,
    this.eccLevel,
    this.isSensitive = false,
  });

  @override
  Widget build(BuildContext context) {
    final StringBuffer semanticLabel = StringBuffer(label);
    if (payloadType != null) {
      semanticLabel.write(', Type: $payloadType');
    }
    if (eccLevel != null) {
      semanticLabel.write(', Error Correction: $eccLevel');
    }

    final String? accessibleValue = isSensitive ? 'Obscured cryptographic credential' : value;

    return Semantics(
      image: true,
      readOnly: true,
      label: semanticLabel.toString(),
      value: accessibleValue,
      hint: 'Double tap to inspect payload details or copy to secure clipboard',
      child: child,
    );
  }
}

/// Accessible Semantics wrapper for the live camera viewfinder and scanning reticle.
class AccessibleScannerViewportSemantics extends StatelessWidget {
  final Widget child;
  final bool isScanningActive;
  final int detectedCount;
  final String? aimingGuidance;

  const AccessibleScannerViewportSemantics({
    super.key,
    required this.child,
    this.isScanningActive = true,
    this.detectedCount = 0,
    this.aimingGuidance,
  });

  @override
  Widget build(BuildContext context) {
    final String status = isScanningActive
        ? 'Camera scanner active. Align optical code inside reticle.'
        : 'Camera scanner suspended.';
    final String guidance = aimingGuidance ?? 'Hold camera steady 6 to 12 inches from optical code.';
    final String fullLabel = '$status $guidance (Items captured: $detectedCount)';

    return Semantics(
      liveRegion: true,
      container: true,
      label: fullLabel,
      child: child,
    );
  }
}

/// Accessible Semantics wrapper for visual fountain streaming and transfer progress.
class AccessibleOpticalStreamSemantics extends StatelessWidget {
  final Widget child;
  final int currentFrame;
  final int totalFrames;
  final double progressRatio;
  final int fps;
  final bool isComplete;

  const AccessibleOpticalStreamSemantics({
    super.key,
    required this.child,
    required this.currentFrame,
    required this.totalFrames,
    required this.progressRatio,
    required this.fps,
    this.isComplete = false,
  });

  @override
  Widget build(BuildContext context) {
    final int percent = (progressRatio.clamp(0.0, 1.0) * 100).round();
    final String description = isComplete
        ? 'Optical transfer complete. 100% of chunks received and verified.'
        : 'Optical transfer stream in progress: $percent% complete. Frame $currentFrame of $totalFrames at $fps FPS.';

    return Semantics(
      liveRegion: true,
      container: true,
      label: description,
      value: '$percent%',
      child: child,
    );
  }
}
