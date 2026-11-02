import 'package:equatable/equatable.dart';

/// Supported Air-Gapped Optical Transfer Modes.
enum OpticalTransferMode {
  /// Single high-contrast static QR code for small payloads (< 1 KB).
  staticQr('Single Static QR', 'Instant optical capture without frame sync.'),

  /// Animated fountain streaming in monochrome (ZSP1 / LT Fountain Code).
  monochromeFountain('Monochrome Fountain Stream',
      'Robust 1-bit optical fountain playback (5–20 FPS).'),

  /// 3-Channel RGB Spectral Multiplexing (3x data density on color screens).
  rgbMultiplexBurst('3x RGB Spectral Burst',
      'Concurrent Red/Green/Blue color-multiplexed stream (3x throughput).'),

  /// M-of-N SLIP-39 Shamir Secret Sharing recovery deck.
  slip39Deck('SLIP-39 Recovery Deck',
      'Threshold cryptographic multi-share physical/optical backup.');

  final String label;
  final String description;
  const OpticalTransferMode(this.label, this.description);
}

/// Security Classification Level for the transfer payload.
enum SecurityClassification {
  /// Unclassified or public data.
  standard,

  /// Confidential organizational or business data.
  confidential,

  /// Maximum isolation: SCIF air-gap, defense, zero-trace memory wiping.
  topSecretAirgap,
}

/// Advice and optimal configuration returned by [TransportAdvisorService].
class TransportAdvice extends Equatable {
  final OpticalTransferMode mode;
  final String title;
  final String rationale;
  final String estimatedBandwidth;
  final int recommendedFps;
  final int recommendedChunkSize;
  final bool enableCompression;
  final bool enableEncryption;
  final String securityNotice;

  const TransportAdvice({
    required this.mode,
    required this.title,
    required this.rationale,
    required this.estimatedBandwidth,
    required this.recommendedFps,
    required this.recommendedChunkSize,
    required this.enableCompression,
    required this.enableEncryption,
    required this.securityNotice,
  });

  @override
  List<Object?> get props => [
        mode,
        title,
        rationale,
        estimatedBandwidth,
        recommendedFps,
        recommendedChunkSize,
        enableCompression,
        enableEncryption,
        securityNotice,
      ];
}

/// Pure Dart Clean Architecture Domain Service recommending the optimal optical
/// transfer methodology based on payload size, security invariants, and device environment.
class TransportAdvisorService {
  const TransportAdvisorService();

  /// Analyzes payload parameters and returns the optimal transport advice.
  TransportAdvice evaluate({
    required int payloadSizeBytes,
    SecurityClassification classification =
        SecurityClassification.topSecretAirgap,
    bool isRgbScreenAvailable = true,
    bool isCryptographicKeyOrSeed = false,
  }) {
    if (payloadSizeBytes < 0) {
      throw ArgumentError.value(
          payloadSizeBytes, 'payloadSizeBytes', 'Must be non-negative');
    }

    // 1. SLIP-39 Shamir Deck for Cryptographic Seeds
    if (isCryptographicKeyOrSeed) {
      return const TransportAdvice(
        mode: OpticalTransferMode.slip39Deck,
        title: 'SLIP-39 Shamir Multi-Share Deck',
        rationale:
            'Cryptographic seed detected. Recommends M-of-N threshold sharing for redundant optical backup.',
        estimatedBandwidth: 'N/A (Multi-Share Carousel)',
        recommendedFps: 0,
        recommendedChunkSize: 64,
        enableCompression: false,
        enableEncryption: true,
        securityNotice:
            'Threshold cryptographic shares require M shares to reconstruct. Decoy resistance enforced.',
      );
    }

    // 2. Static QR for small payloads (< 800 bytes)
    if (payloadSizeBytes < 800) {
      return TransportAdvice(
        mode: OpticalTransferMode.staticQr,
        title: 'Single-Frame Optical QR',
        rationale:
            'Payload ($payloadSizeBytes B) comfortably fits into a single high-contrast QR code without streaming.',
        estimatedBandwidth: 'Instant (1 Frame)',
        recommendedFps: 0,
        recommendedChunkSize: payloadSizeBytes,
        enableCompression: payloadSizeBytes > 200,
        enableEncryption: classification != SecurityClassification.standard,
        securityNotice:
            'Zero RF emanation. Optical line-of-sight only. 100% offline.',
      );
    }

    // 3. 3x RGB Spectral Burst for larger payloads on color displays (>= 25 KB)
    if (payloadSizeBytes >= 25 * 1024 && isRgbScreenAvailable) {
      return TransportAdvice(
        mode: OpticalTransferMode.rgbMultiplexBurst,
        title: '3x RGB Spectral Multiplex Mode',
        rationale:
            'Payload (${(payloadSizeBytes / 1024).toStringAsFixed(1)} KB) benefits from 3-channel optical multiplexing to achieve 3x transfer throughput.',
        estimatedBandwidth: '45–90 KB/s @ 15 FPS',
        recommendedFps: 15,
        recommendedChunkSize: 320,
        enableCompression: true,
        enableEncryption: classification != SecurityClassification.standard,
        securityNotice:
            'Physical air-gap maintained. Eliminates Wi-Fi/Bluetooth attack surfaces completely.',
      );
    }

    // 4. Default: Robust Monochrome LT Fountain Streaming
    final fps = payloadSizeBytes > 10 * 1024 ? 12 : 10;
    final speed =
        '${(fps * 0.18).toStringAsFixed(1)}–${(fps * 0.25).toStringAsFixed(1)} KB/s';

    return TransportAdvice(
      mode: OpticalTransferMode.monochromeFountain,
      title: 'Monochrome LT Fountain Stream',
      rationale:
          'Payload (${(payloadSizeBytes / 1024).toStringAsFixed(1)} KB) streams optimally with Luby Transform rateless erasure codes across any camera sensor.',
      estimatedBandwidth: speed,
      recommendedFps: fps,
      recommendedChunkSize: 180,
      enableCompression: true,
      enableEncryption: classification != SecurityClassification.standard,
      securityNotice:
          'Rateless fountain streaming ensures 100% packet recovery even under ambient glare or partial occlusions.',
    );
  }
}
