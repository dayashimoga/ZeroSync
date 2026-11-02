import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/presentation/blocs/optical_session/optical_session_bloc.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/adaptive_split_pane_scaffold.dart';
import 'package:airdrop_qr/presentation/widgets/camera_viewport_widget.dart';
import 'package:airdrop_qr/presentation/widgets/missing_block_matrix_heatmap.dart';
import 'package:airdrop_qr/presentation/widgets/optical_animation_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Primary application shell for AirDrop-QR / ZeroSync.
class ZeroSyncHomePage extends StatefulWidget {
  final OpticalSessionBloc? bloc;

  const ZeroSyncHomePage({super.key, this.bloc});

  @override
  State<ZeroSyncHomePage> createState() => _ZeroSyncHomePageState();
}

class _ZeroSyncHomePageState extends State<ZeroSyncHomePage> {
  late final OpticalSessionBloc _sessionBloc;
  bool _isInternalBloc = false;

  @override
  void initState() {
    super.initState();
    if (widget.bloc != null) {
      _sessionBloc = widget.bloc!;
      _isInternalBloc = false;
    } else {
      _sessionBloc = OpticalSessionBloc();
      _isInternalBloc = true;
    }
  }

  @override
  void dispose() {
    if (_isInternalBloc) {
      _sessionBloc.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OpticalSessionBloc>.value(
      value: _sessionBloc,
      child: BlocBuilder<OpticalSessionBloc, OpticalSessionState>(
        builder: (context, state) {
          return AdaptiveSplitPaneScaffold(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined,
                    color: ZeroSyncColors.emerald, size: 20),
                const SizedBox(width: ZeroSyncSpacing.sm),
                const Text(
                  'ZeroSync',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
                const SizedBox(width: ZeroSyncSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: ZeroSyncColors.emerald.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: ZeroSyncColors.emerald, width: 0.8),
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
                tooltip: 'Reset Session',
                icon: const Icon(Icons.refresh,
                    color: ZeroSyncColors.lightTextSecondary),
                onPressed: () {
                  context
                      .read<OpticalSessionBloc>()
                      .add(const OpticalSessionReset());
                },
              ),
              IconButton(
                tooltip: state.activeMode == 0
                    ? 'Switch to Transmitter Mode'
                    : 'Switch to Receiver Mode',
                icon: Icon(
                  state.activeMode == 0
                      ? Icons.cell_tower
                      : Icons.qr_code_scanner,
                  color: ZeroSyncColors.cyan,
                ),
                onPressed: () {
                  final nextMode = state.activeMode == 0 ? 1 : 0;
                  context
                      .read<OpticalSessionBloc>()
                      .add(OpticalSessionModeChanged(nextMode));
                },
              ),
            ],
            primaryPane: _buildPrimaryPane(context, state),
            secondaryPane: _buildSecondaryPane(context, state),
            primaryTabLabel: 'Optical',
            secondaryTabLabel: 'Vault',
            primaryTabIcon: Icons.qr_code_scanner,
            secondaryTabIcon: Icons.lock_outline,
          );
        },
      ),
    );
  }

  Widget _buildPrimaryPane(BuildContext context, OpticalSessionState state) {
    if (state.activeMode == 1) {
      return _buildTransmitterView(context, state);
    }

    return CameraViewportWidget(
      config: const CameraViewportConfig(
        reticleColor: ZeroSyncColors.cyan,
        laserColor: ZeroSyncColors.cyan,
        showLaserScanline: true,
      ),
      onDetect: (capture) {
        if (capture.barcodes.isNotEmpty) {
          for (final barcode in capture.barcodes) {
            final raw = barcode.rawValue;
            if (raw != null && raw.isNotEmpty) {
              context
                  .read<OpticalSessionBloc>()
                  .add(OpticalSessionFrameIngested(raw));
            }
          }
        }
      },
      errorBuilder: _buildCameraError(),
    );
  }

  Widget _buildTransmitterView(
      BuildContext context, OpticalSessionState state) {
    if (state is OpticalSessionTransmitting && state.framePayloads.isNotEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZeroSyncSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OpticalAnimationPlayer(
                framePayloads: state.framePayloads,
                initialFps: 10.0,
                onFrameChanged: (index) {
                  context
                      .read<OpticalSessionBloc>()
                      .add(OpticalSessionFrameAdvanced(index));
                },
              ),
              const SizedBox(height: ZeroSyncSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: ZeroSyncSpacing.md,
                    vertical: ZeroSyncSpacing.sm),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.darkSlate,
                  borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
                  border: Border.all(color: ZeroSyncColors.cyan.withAlpha(100)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attachment,
                        size: 16, color: ZeroSyncColors.cyan),
                    const SizedBox(width: ZeroSyncSpacing.xs),
                    Text(
                      '${state.fileName} (${state.fileSizeBytes} B • ${state.framePayloads.length} Chunks)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: ZeroSyncColors.trueWhite,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZeroSyncSpacing.md),
              OutlinedButton.icon(
                icon: const Icon(Icons.file_upload_outlined, size: 16),
                label: const Text('Transmit Different Payload'),
                onPressed: () => _showPayloadPickerDialog(context),
              ),
            ],
          ),
        ),
      );
    }

    if (state is OpticalSessionPreparing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: ZeroSyncColors.emerald),
            SizedBox(height: ZeroSyncSpacing.md),
            Text(
              'Slicing and preparing optical datagrams...',
              style: TextStyle(color: ZeroSyncColors.trueWhite),
            ),
          ],
        ),
      );
    }

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
              'Select a file, document, or custom payload to initiate optical fountain streaming.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: ZeroSyncColors.lightTextSecondary, fontSize: 13),
            ),
            const SizedBox(height: ZeroSyncSpacing.lg),
            ElevatedButton.icon(
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Select File for Optical Transfer'),
              onPressed: () => _showPayloadPickerDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showPayloadPickerDialog(BuildContext parentContext) {
    showModalBottomSheet<void>(
      context: parentContext,
      backgroundColor: ZeroSyncColors.darkGraphite,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZeroSyncRadii.lg)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ZeroSyncSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Select Optical Transfer Payload',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
                const SizedBox(height: ZeroSyncSpacing.xs),
                const Text(
                  'Choose a sample air-gapped document or enter custom text to transmit.',
                  style: TextStyle(
                      fontSize: 12, color: ZeroSyncColors.lightTextSecondary),
                ),
                const SizedBox(height: ZeroSyncSpacing.md),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ZeroSyncColors.emerald.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.description_outlined,
                        color: ZeroSyncColors.emerald),
                  ),
                  title: const Text(
                      'Sample Zero-Trust Attestation (2.5 KB JSON)',
                      style: TextStyle(color: ZeroSyncColors.trueWhite)),
                  subtitle: const Text('Multi-chunk optical benchmark file',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                  onTap: () {
                    Navigator.of(bottomSheetContext).pop();
                    _prepareSamplePayload(parentContext);
                  },
                ),
                const Divider(color: ZeroSyncColors.darkBorder),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ZeroSyncColors.cyan.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.edit_note_outlined,
                        color: ZeroSyncColors.cyan),
                  ),
                  title: const Text('Enter Custom Text / Payload',
                      style: TextStyle(color: ZeroSyncColors.trueWhite)),
                  subtitle: const Text('Type or paste data to stream optically',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                  onTap: () {
                    Navigator.of(bottomSheetContext).pop();
                    _showCustomTextDialog(parentContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _prepareSamplePayload(BuildContext context) {
    const sampleDoc = '''{
  "system": "ZeroSync AirDrop-QR",
  "version": "3.1.0",
  "compliance": "NIST SP 800-53 SCIF Air-Gap Certified",
  "security_invariants": {
    "zero_network_permissions": true,
    "memory_zeroization_barrier": "calloc<Uint8> 0x00 wipe",
    "vault_encryption": "SQLCipher AES-256",
    "wire_header": "20-byte ZSP1 with CRC-32C",
    "optical_multiplexing": "RGB 3-Channel Spectral Split"
  },
  "timestamp": "2026-11-02T12:00:00Z",
  "checksum_digest": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}''';

    final bytes = Uint8List.fromList(utf8.encode(sampleDoc));
    context.read<OpticalSessionBloc>().add(
          OpticalSessionPayloadPrepared(
            fileName: 'zerosync_airgap_manifest.json',
            fileBytes: bytes,
            mimeType: 'application/json',
            chunkSize: 180, // Generates clean multi-chunk stream
          ),
        );
  }

  void _showCustomTextDialog(BuildContext parentContext) {
    final textController = TextEditingController();

    showDialog<void>(
      context: parentContext,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: ZeroSyncColors.darkGraphite,
          title: const Text('Enter Custom Payload',
              style: TextStyle(color: ZeroSyncColors.trueWhite)),
          content: TextField(
            controller: textController,
            maxLines: 4,
            style: const TextStyle(color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              hintText: 'Type or paste payload data...',
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
                final text = textController.text.trim();
                Navigator.of(dialogCtx).pop();
                if (text.isNotEmpty) {
                  final bytes = Uint8List.fromList(utf8.encode(text));
                  parentContext.read<OpticalSessionBloc>().add(
                        OpticalSessionPayloadPrepared(
                          fileName: 'custom_payload.txt',
                          fileBytes: bytes,
                          mimeType: 'text/plain',
                          chunkSize: 120,
                        ),
                      );
                }
              },
              child: const Text('Prepare Stream'),
            ),
          ],
        );
      },
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
              'Ensure camera permissions are granted or run on a physical device with an optical camera sensor.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white.withAlpha(180), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryPane(BuildContext context, OpticalSessionState state) {
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

          // Transfer Progress & Telemetry Matrix (Bound to Reactive BLoC State)
          const Text(
            'Transfer Session Telemetry',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite),
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),
          MissingBlockMatrixHeatmap(
            metrics: state.metrics,
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
                Icon(
                  state is OpticalSessionVerified
                      ? Icons.check_circle_outline
                      : (state is OpticalSessionError
                          ? Icons.error_outline
                          : Icons.info_outline),
                  size: 16,
                  color: state is OpticalSessionVerified
                      ? ZeroSyncColors.emerald
                      : (state is OpticalSessionError
                          ? Colors.redAccent
                          : ZeroSyncColors.cyan),
                ),
                const SizedBox(width: ZeroSyncSpacing.xs),
                Expanded(
                  child: Text(
                    state.statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: state is OpticalSessionVerified
                          ? ZeroSyncColors.emerald
                          : (state is OpticalSessionError
                              ? Colors.redAccent
                              : ZeroSyncColors.cyan),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Verified Payload Details Card
          if (state is OpticalSessionVerified) ...[
            const SizedBox(height: ZeroSyncSpacing.md),
            Container(
              padding: const EdgeInsets.all(ZeroSyncSpacing.md),
              decoration: BoxDecoration(
                color: ZeroSyncColors.emerald.withAlpha(20),
                borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
                border:
                    Border.all(color: ZeroSyncColors.emerald.withAlpha(120)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.verified,
                          size: 16, color: ZeroSyncColors.emerald),
                      SizedBox(width: ZeroSyncSpacing.xs),
                      Text(
                        'Cryptographic Validation Succeeded',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: ZeroSyncColors.emerald,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ZeroSyncSpacing.xs),
                  Text(
                    'SHA-256: ${state.verifiedSha256}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
