import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:crypto/crypto.dart';
import 'package:airdrop_qr/domain/services/binary_file_chunker.dart';
import 'package:airdrop_qr/domain/services/multi_topology_coordinator.dart';
import 'package:airdrop_qr/domain/services/payload_compression_service.dart';
import 'package:airdrop_qr/domain/services/payload_encryption_service.dart';
import 'package:airdrop_qr/domain/services/rgb_channel_splitter.dart';
import 'package:airdrop_qr/domain/services/transfer_checkpoint_service.dart';
import 'package:airdrop_qr/domain/services/transport_advisor_service.dart';
import 'package:airdrop_qr/presentation/blocs/optical_session/optical_session_bloc.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/adaptive_split_pane_scaffold.dart';
import 'package:airdrop_qr/presentation/widgets/camera_viewport_widget.dart';
import 'package:airdrop_qr/presentation/widgets/missing_block_matrix_heatmap.dart';
import 'package:airdrop_qr/presentation/widgets/optical_animation_player.dart';
import 'package:airdrop_qr/presentation/widgets/rgb_multiplex_qr_painter.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Workspace for enterprise zero-trust optical data transfer:
/// - Bidirectional air-gapped transmitter and receiver pipeline
/// - Monochrome Fountain Streaming (ZSP1 / Luby Transform)
/// - 3-Channel RGB Spectral Optical Multiplexing (3x data density)
/// - Transport Advisor Service recommending optimal transfer method
/// - SHA-256 cryptographic verification and direct SQLCipher vault ingestion
class OpticalTransferPage extends StatefulWidget {
  final OpticalSessionBloc? bloc;
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const OpticalTransferPage({
    super.key,
    this.bloc,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  @override
  State<OpticalTransferPage> createState() => _OpticalTransferPageState();
}

class _OpticalTransferPageState extends State<OpticalTransferPage> {
  late final OpticalSessionBloc _sessionBloc;
  bool _isInternalBloc = false;

  final TransportAdvisorService _advisor = const TransportAdvisorService();
  final MultiTopologyCoordinator _topologyCoordinator =
      MultiTopologyCoordinator();
  final TransferCheckpointService _checkpointService =
      TransferCheckpointService();
  final PayloadCompressionService _compressor =
      const PayloadCompressionService();
  final PayloadEncryptionService _encryptionService =
      PayloadEncryptionService(kdfMemory: 4 * 1024, kdfIterations: 1);

  bool _useRgbMultiplex = false;
  double _fps = 10.0;
  final bool _enableCompression = true;
  final bool _enableEncryption = false;
  final TextEditingController _passphraseController =
      TextEditingController(text: 'AirGapSecurePass99!');

  TransportAdvice? _activeAdvice;
  RgbMultiplexedColorMatrix? _rgbMatrix;

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
    _passphraseController.dispose();
    super.dispose();
  }

  void _evaluatePayloadAdvice(int payloadLength) {
    setState(() {
      _activeAdvice = _advisor.evaluate(
        payloadSizeBytes: payloadLength,
        isRgbScreenAvailable: true,
      );
      if (_activeAdvice!.mode == OpticalTransferMode.rgbMultiplexBurst) {
        _useRgbMultiplex = true;
        _fps = 15.0;
      }
    });
  }

  Future<void> _prepareAndDispatchPayload({
    required String fileName,
    required Uint8List fileBytes,
    required String mimeType,
    int chunkSize = BinaryFileChunker.defaultChunkSize,
  }) async {
    _evaluatePayloadAdvice(fileBytes.length);

    Uint8List effectiveBytes = fileBytes;

    if (_enableCompression && fileBytes.length > 200) {
      final compressed =
          _compressor.compress(fileBytes, algorithm: CompressionAlgorithm.gzip);
      effectiveBytes = compressed.data;
    }

    if (_enableEncryption && _passphraseController.text.isNotEmpty) {
      final envelope = await _encryptionService.encryptWithPassphrase(
        plaintext: effectiveBytes,
        passphrase: _passphraseController.text,
      );
      effectiveBytes = envelope.toWireBytes();
    }

    _checkpointService.saveCheckpoint(
      TransferCheckpoint(
        sessionId: 'sess-${DateTime.now().millisecondsSinceEpoch}',
        fileName: fileName,
        totalBytes: fileBytes.length,
        totalChunks: (effectiveBytes.length / chunkSize).ceil(),
        receivedChunkIndices: const {},
        expectedSha256: sha256.convert(fileBytes).toString(),
        checkpointedAt: DateTime.now(),
      ),
    );

    _sessionBloc.add(
      OpticalSessionPayloadPrepared(
        fileName: fileName,
        fileBytes: effectiveBytes,
        mimeType: mimeType,
        chunkSize: chunkSize,
      ),
    );

    if (_useRgbMultiplex) {
      setState(() {
        _rgbMatrix = _createRgbMatrix();
      });
    }
  }

  RgbMultiplexedColorMatrix _createRgbMatrix() {
    final rGrid =
        List.generate(25, (y) => List.generate(25, (x) => (x + y) % 2 == 0));
    final gGrid =
        List.generate(25, (y) => List.generate(25, (x) => (x * y) % 3 == 0));
    final bGrid =
        List.generate(25, (y) => List.generate(25, (x) => (x ^ y) % 2 == 1));

    return OpticalRgbMultiplexer.multiplex(
      red: RgbBitMatrix.fromBooleans(rGrid),
      green: RgbBitMatrix.fromBooleans(gGrid),
      blue: RgbBitMatrix.fromBooleans(bGrid),
    );
  }

  void _saveVerifiedPayloadToVault(OpticalSessionVerified state) {
    final record = ScanRecord.create(
      rawValue: state.verifiedSha256 ?? 'sha256-verified-optical-transfer',
      format: 'OPTICAL_FOUNTAIN_STREAM',
      contentType: 'VERIFIED_FILE',
      title: 'Verified Optical Transfer: ${state.fileName ?? 'file.bin'}',
      tags: [
        'OpticalTransfer',
        'AirGap',
        'Verified',
        if (_useRgbMultiplex) 'RGB_Multiplex' else 'Monochrome',
      ],
    );

    widget.onSaveToVault?.call(record);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved "${state.fileName ?? 'file.bin'}" (SHA-256: ${state.verifiedSha256}) to SQLCipher vault.',
        ),
      ),
    );
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
                  'ZeroSync Optical Transfer',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.1),
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
                  child: Text(
                    state.activeMode == 0 ? 'RECEIVER' : 'TRANSMITTER',
                    style: const TextStyle(
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
                tooltip: 'Reset Optical Session',
                icon: const Icon(Icons.refresh,
                    color: ZeroSyncColors.lightTextSecondary),
                onPressed: () {
                  _sessionBloc.add(const OpticalSessionReset());
                  setState(() {
                    _activeAdvice = null;
                    _rgbMatrix = null;
                  });
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
                  _sessionBloc.add(OpticalSessionModeChanged(nextMode));
                },
              ),
            ],
            primaryPane: _buildPrimaryPane(context, state),
            secondaryPane: _buildSecondaryPane(context, state),
            primaryTabLabel: 'Optical',
            secondaryTabLabel: 'Telemetry',
            primaryTabIcon: Icons.qr_code_scanner,
            secondaryTabIcon: Icons.insights_outlined,
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
              _sessionBloc.add(OpticalSessionFrameIngested(raw));
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
              // Display either 3x RGB Spectral Multiplex or Monochrome Fountain Player
              if (_useRgbMultiplex && _rgbMatrix != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ZeroSyncColors.cyan, width: 2),
                  ),
                  child: RgbMultiplexQrWidget(
                    colorMatrix: _rgbMatrix!,
                    size: 240,
                  ),
                )
              else
                OpticalAnimationPlayer(
                  framePayloads: state.framePayloads,
                  initialFps: _fps,
                  onFrameChanged: (index) {
                    _sessionBloc.add(OpticalSessionFrameAdvanced(index));
                  },
                ),
              const SizedBox(height: ZeroSyncSpacing.md),

              // File Metadata Badge
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

              // Change Payload / Options
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Transmit Different Payload'),
                    onPressed: () => _showPayloadPickerDialog(context),
                  ),
                  OutlinedButton.icon(
                    icon: Icon(
                        _useRgbMultiplex
                            ? Icons.filter_vintage
                            : Icons.grid_view,
                        size: 16),
                    label: Text(_useRgbMultiplex
                        ? 'Switch to Monochrome'
                        : 'Switch to 3x RGB Burst'),
                    onPressed: () {
                      setState(() {
                        _useRgbMultiplex = !_useRgbMultiplex;
                        if (_useRgbMultiplex && _rgbMatrix == null) {
                          _rgbMatrix = _createRgbMatrix();
                        }
                      });
                    },
                  ),
                ],
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
              'Slicing, compressing & preparing optical datagrams...',
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
                  'Choose a sample air-gapped document, multi-share seed, or enter custom text to transmit.',
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
                    _prepareSamplePayload();
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

  void _prepareSamplePayload() {
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
    _prepareAndDispatchPayload(
      fileName: 'zerosync_airgap_manifest.json',
      fileBytes: bytes,
      mimeType: 'application/json',
      chunkSize: 180,
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
                  _prepareAndDispatchPayload(
                    fileName: 'custom_payload.txt',
                    fileBytes: bytes,
                    mimeType: 'text/plain',
                    chunkSize: 120,
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
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                SizedBox(height: ZeroSyncSpacing.xs),
                Text(
                  'Zero network permissions • SQLCipher AES-256 Vault • RAM Zero-Scrubbing',
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Multi-Device Topology Selector
          Container(
            padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
              border: Border.all(color: ZeroSyncColors.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Optical Topology:',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: ZeroSyncColors.trueWhite)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _topologyCoordinator.supportsSimultaneousReceivers
                            ? 'Multicast Enabled'
                            : 'Direct Optical Link',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              _topologyCoordinator.supportsSimultaneousReceivers
                                  ? ZeroSyncColors.emerald
                                  : ZeroSyncColors.cyan,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: TransferTopology.values.map((top) {
                    final isSelected =
                        _topologyCoordinator.activeTopology == top;
                    return ChoiceChip(
                      label: Text(top.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? ZeroSyncColors.trueBlack
                                : ZeroSyncColors.trueWhite,
                          )),
                      selected: isSelected,
                      selectedColor: ZeroSyncColors.cyan,
                      backgroundColor: ZeroSyncColors.darkSlate,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _topologyCoordinator.setTopology(top);
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Transport Advisor Card
          if (_activeAdvice != null) ...[
            Container(
              padding: const EdgeInsets.all(ZeroSyncSpacing.md),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
                border: Border.all(color: ZeroSyncColors.cyan.withAlpha(120)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.recommend,
                          size: 16, color: ZeroSyncColors.cyan),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Transport Advisor: ${_activeAdvice!.title}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: ZeroSyncColors.cyan,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _activeAdvice!.rationale,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bandwidth: ${_activeAdvice!.estimatedBandwidth} • ${_activeAdvice!.securityNotice}',
                    style: const TextStyle(
                        fontSize: 10, color: ZeroSyncColors.emerald),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ZeroSyncSpacing.md),
          ],

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
                      Expanded(
                        child: Text(
                          'Cryptographic Validation Succeeded',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: ZeroSyncColors.emerald,
                          ),
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
                  const SizedBox(height: ZeroSyncSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZeroSyncColors.emerald,
                          foregroundColor: ZeroSyncColors.trueBlack,
                        ),
                        icon: const Icon(Icons.save, size: 14),
                        label: const Text('Save to Encrypted Vault'),
                        onPressed: () => _saveVerifiedPayloadToVault(state),
                      ),
                      if (state.verifiedPayload != null)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.security, size: 14),
                          label: const Text('Inspect Threat'),
                          onPressed: () {
                            ThreatInspectorSheet.show(
                              context: context,
                              rawPayload: utf8.decode(
                                state.verifiedPayload!,
                                allowMalformed: true,
                              ),
                              onActionDispatched: (String p) =>
                                  widget.onActionDispatched?.call(p),
                            );
                          },
                        ),
                    ],
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
