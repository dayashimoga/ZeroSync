import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/camera_viewport_widget.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';

/// Primary camera scanner workspace providing hardware-accelerated viewport targeting,
/// auto-focus laser reticle, and pre-action zero-trust threat inspection.
class CameraScannerView extends StatefulWidget {
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const CameraScannerView({
    super.key,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  @override
  State<CameraScannerView> createState() => _CameraScannerViewState();
}

class _CameraScannerViewState extends State<CameraScannerView> {
  bool _isInspectorOpen = false;
  String? _lastScannedPayload;

  void _handleBarcodeDetect(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty || _isInspectorOpen) return;

    setState(() {
      _isInspectorOpen = true;
      _lastScannedPayload = trimmed;
    });

    ThreatInspectorSheet.show(
      context: context,
      rawPayload: trimmed,
      onSaveToVault: widget.onSaveToVault,
      onActionDispatched: widget.onActionDispatched,
    ).then((_) {
      if (mounted) {
        setState(() {
          _isInspectorOpen = false;
        });
      }
    });
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: ZeroSyncColors.darkGraphite,
        title: const Row(
          children: [
            Icon(Icons.keyboard_outlined, color: ZeroSyncColors.cyan, size: 20),
            SizedBox(width: 8),
            Text('Manual Payload Inspection',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: const TextStyle(color: ZeroSyncColors.trueWhite),
          decoration: const InputDecoration(
            hintText: 'Enter URL, Wi-Fi, vCard, or custom QR payload...',
            hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              Navigator.of(dialogCtx).pop();
              if (text.isNotEmpty) {
                _handleBarcodeDetect(text);
              }
            },
            child: const Text('Inspect Threat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Hardware Camera Viewport with Optical Scanline & Reticle
        CameraViewportWidget(
          config: const CameraViewportConfig(
            reticleColor: ZeroSyncColors.cyan,
            laserColor: ZeroSyncColors.cyan,
            showLaserScanline: true,
          ),
          onDetect: (capture) {
            if (capture.barcodes.isNotEmpty) {
              final raw = capture.barcodes.first.rawValue;
              if (raw != null) {
                _handleBarcodeDetect(raw);
              }
            }
          },
          errorBuilder: _buildCameraError(),
        ),

        // 2. Top Status Badge & Manual Entry Action Button
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SafeArea(
            child: Row(
              children: [
                // Zero-Trust Scanner Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: ZeroSyncColors.emerald, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield,
                          color: ZeroSyncColors.emerald, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'ZERO-TRUST SCANNER',
                        style: TextStyle(
                          color: ZeroSyncColors.emerald,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Manual Payload Entry / Simulation Button
                IconButton.filledTonal(
                  tooltip: 'Manual Payload Inspection',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black87,
                    side: const BorderSide(color: ZeroSyncColors.darkBorder),
                  ),
                  icon: const Icon(Icons.keyboard_outlined,
                      color: ZeroSyncColors.cyan, size: 20),
                  onPressed: _showManualEntryDialog,
                ),
              ],
            ),
          ),
        ),

        // 3. Bottom Last Scanned Pill (if available)
        if (_lastScannedPayload != null && !_isInspectorOpen)
          Positioned(
            bottom: 84,
            left: 24,
            right: 24,
            child: GestureDetector(
              onTap: () => _handleBarcodeDetect(_lastScannedPayload!),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ZeroSyncColors.cyan.withAlpha(120)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        size: 16, color: ZeroSyncColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last: $_lastScannedPayload',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Re-Inspect',
                        style: TextStyle(
                            fontSize: 10,
                            color: ZeroSyncColors.cyan,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
      ],
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
              'Optical Camera Viewport Ready',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite),
            ),
            const SizedBox(height: ZeroSyncSpacing.xs),
            const Text(
              'No physical camera sensor detected or permissions pending. Use manual entry or local image decoding.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ZeroSyncColors.lightTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: ZeroSyncSpacing.lg),
            ElevatedButton.icon(
              icon: const Icon(Icons.keyboard_outlined),
              label: const Text('Enter Payload Manually for Inspection'),
              onPressed: _showManualEntryDialog,
            ),
          ],
        ),
      ),
    );
  }
}
