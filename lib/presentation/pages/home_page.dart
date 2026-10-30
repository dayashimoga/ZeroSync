import 'package:flutter/material.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/adaptive_split_pane_scaffold.dart';
import 'package:airdrop_qr/presentation/widgets/camera_viewport_widget.dart';
import 'package:airdrop_qr/presentation/widgets/missing_block_matrix_heatmap.dart';

/// Primary application shell for AirDrop-QR / ZeroSync.
class ZeroSyncHomePage extends StatefulWidget {
  const ZeroSyncHomePage({super.key});

  @override
  State<ZeroSyncHomePage> createState() => _ZeroSyncHomePageState();
}

class _ZeroSyncHomePageState extends State<ZeroSyncHomePage> {
  int _activeMode = 0; // 0: Receiver (Camera), 1: Transmitter (Visual Loop)
  String _statusText = 'Air-gap optical link ready. Point camera at source.';

  @override
  Widget build(BuildContext context) {
    return AdaptiveSplitPaneScaffold(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined,
              color: ZeroSyncColors.emerald, size: 20),
          const SizedBox(width: ZeroSyncSpacing.sm),
          const Text(
            'ZeroSync',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          const SizedBox(width: ZeroSyncSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ZeroSyncColors.emerald.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: ZeroSyncColors.emerald, width: 0.8),
            ),
            child: const Text(
              'AIR-GAPPED',
              style: TextStyle(
                color: ZeroSyncColors.emerald,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Toggle Receiver / Transmitter',
          icon: Icon(
            _activeMode == 0 ? Icons.qr_code_2 : Icons.camera_alt_outlined,
            color: ZeroSyncColors.cyan,
          ),
          onPressed: () {
            setState(() {
              _activeMode = _activeMode == 0 ? 1 : 0;
            });
          },
        ),
      ],
      primaryPane: _buildPrimaryPane(),
      secondaryPane: _buildSecondaryPane(),
      primaryTabLabel: 'Optical',
      secondaryTabLabel: 'Vault',
      primaryTabIcon: Icons.qr_code_scanner,
      secondaryTabIcon: Icons.lock_outline,
    );
  }

  Widget _buildPrimaryPane() {
    if (_activeMode == 1) {
      return _buildTransmitterPlaceholder();
    }

    return CameraViewportWidget(
      config: const CameraViewportConfig(
        reticleColor: ZeroSyncColors.cyan,
        laserColor: ZeroSyncColors.cyan,
        showLaserScanline: true,
      ),
      onDetect: (capture) {
        if (capture.barcodes.isNotEmpty) {
          final raw = capture.barcodes.first.rawValue ?? '';
          if (mounted) {
            setState(() {
              _statusText = 'Ingested datagram: ${raw.length} bytes';
            });
          }
        }
      },
      errorBuilder: _buildCameraError(),
    );
  }

  Widget _buildCameraError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZeroSyncSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                size: 56, color: ZeroSyncColors.amber),
            const SizedBox(height: ZeroSyncSpacing.md),
            const Text(
              'Camera Feed Inactive',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite),
            ),
            const SizedBox(height: ZeroSyncSpacing.xs),
            Text(
              'Ensure camera permissions are granted or run on a physical device with a camera sensor.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransmitterPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZeroSyncSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cell_tower,
                size: 56, color: ZeroSyncColors.emerald),
            const SizedBox(height: ZeroSyncSpacing.md),
            const Text(
              'Visual ZeroSync Transmitter',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite),
            ),
            const SizedBox(height: ZeroSyncSpacing.xs),
            const Text(
              'Select a file or payload from the Vault to initiate optical fountain streaming.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ZeroSyncColors.lightTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: ZeroSyncSpacing.lg),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Select File for Optical Transfer'),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryPane() {
    return Container(
      color: ZeroSyncColors.darkGraphite,
      child: ListView(
        padding: const EdgeInsets.all(ZeroSyncSpacing.lg),
        children: [
          // Security Status Card
          Container(
            padding: const EdgeInsets.all(ZeroSyncSpacing.md),
            decoration: BoxDecoration(
              color: ZeroSyncColors.darkSlate,
              borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
              border: Border.all(color: ZeroSyncColors.emerald.withAlpha(80)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: ZeroSyncColors.emerald, size: 18),
                    SizedBox(width: ZeroSyncSpacing.xs),
                    Expanded(
                      child: Text(
                        'HARDENED ZERO-TRUST AIR-GAP',
                        style: TextStyle(
                          color: ZeroSyncColors.emerald,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ZeroSyncSpacing.xs),
                Text(
                  'Zero network permissions • SQLCipher AES-256 Vault • RAM Zero-Scrubbing',
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withAlpha(160)),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Transfer Progress & Telemetry Matrix
          const Text(
            'Transfer Session Telemetry',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite),
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),
          const MissingBlockMatrixHeatmap(
            metrics: TransferProgressMetrics(
              totalChunks: 32,
              receivedChunks: 32,
              missingIndices: [],
              progressPercentage: 100.0,
              transferSpeedKbps: 45.2,
              totalBytesReceived: 16384,
              isComplete: true,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Active Status Banner
          Container(
            padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
              border: Border.all(color: ZeroSyncColors.darkBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: ZeroSyncColors.cyan),
                const SizedBox(width: ZeroSyncSpacing.xs),
                Expanded(
                  child: Text(
                    _statusText,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.cyan),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
