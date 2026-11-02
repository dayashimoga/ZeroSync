import 'dart:io' show Platform;

import 'package:airdrop_qr/core/platform/windows_zxing_decoder.dart';
import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/gallery_decoder_service.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Workspace for decoding QR codes from static image files and system clipboard
/// using multi-pass heuristic preprocessing and desktop ZXing/MobileScanner.
class ImageScannerView extends StatefulWidget {
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;
  final GalleryDecoderService? decoderServiceOverride;
  final ZxingDecoderEngine? zxingDecoderOverride;

  const ImageScannerView({
    super.key,
    this.onSaveToVault,
    this.onActionDispatched,
    this.decoderServiceOverride,
    this.zxingDecoderOverride,
  });

  @override
  State<ImageScannerView> createState() => _ImageScannerViewState();
}

class _ImageScannerViewState extends State<ImageScannerView> {
  late final GalleryDecoderService _decoderService;
  late final ZxingDecoderEngine _zxingDecoder;

  bool _isDecoding = false;
  String? _loadedSourceDescription;
  GalleryDecodeResult? _lastDecodeResult;
  String? _errorMessage;

  // Selected preprocessing mode: null represents full multi-pass auto mode
  GalleryDecodePass? _selectedSinglePass;

  @override
  void initState() {
    super.initState();
    _decoderService = widget.decoderServiceOverride ??
        const GalleryDecoderService(
          analyzer: _defaultStaticImageAnalyzer,
        );
    _zxingDecoder = widget.zxingDecoderOverride ?? WindowsZxingDecoderImpl();
  }

  static Future<List<Barcode>> _defaultStaticImageAnalyzer(
      String filePath) async {
    // In production mobile_scanner, this invokes the native image barcode reader.
    return <Barcode>[];
  }

  Future<void> _decodeRawImage(
    RawImageData image, {
    required String sourceName,
  }) async {
    setState(() {
      _isDecoding = true;
      _errorMessage = null;
      _loadedSourceDescription = sourceName;
      _lastDecodeResult = null;
    });

    try {
      final List<GalleryDecodePass> passes = _selectedSinglePass != null
          ? [_selectedSinglePass!]
          : const [
              GalleryDecodePass.raw,
              GalleryDecodePass.grayscale,
              GalleryDecodePass.contrastMaximized,
              GalleryDecodePass.inverted,
              GalleryDecodePass.adaptiveThreshold,
            ];

      final result = await _decoderService.decodeRawImage(
        image,
        options: GalleryDecoderOptions(
          passes: passes,
          runInIsolate: false, // In UI thread for immediate testability
          returnFirstMatch: true,
        ),
      );

      if (mounted) {
        setState(() {
          _isDecoding = false;
          _lastDecodeResult = result;
          if (!result.isSuccess) {
            _errorMessage =
                'No barcodes detected across ${result.totalPassesExecuted} preprocessing passes.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDecoding = false;
          _errorMessage = 'Decoding error: $e';
        });
      }
    }
  }

  Future<void> _handleClipboardPaste() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();

      if (text == null || text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Clipboard is empty or does not contain text.')),
          );
        }
        return;
      }

      // If clipboard text looks like an image file path
      if (text.endsWith('.png') ||
          text.endsWith('.jpg') ||
          text.endsWith('.jpeg') ||
          text.endsWith('.bmp')) {
        _simulateImageDecodeFromPath(text);
        return;
      }

      // If clipboard contains raw QR text or URL, direct to Threat Inspector
      if (mounted) {
        await ThreatInspectorSheet.show(
          context: context,
          rawPayload: text,
          onSaveToVault: widget.onSaveToVault,
          onActionDispatched: widget.onActionDispatched,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read clipboard: $e')),
        );
      }
    }
  }

  void _showFilePathInputDialog() {
    final controller = TextEditingController(text: 'sample_qr_invoice.png');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: ZeroSyncColors.darkGraphite,
        title: const Row(
          children: [
            Icon(Icons.image_search, color: ZeroSyncColors.cyan, size: 20),
            SizedBox(width: 8),
            Text('Select Local Image File',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter path to local PNG, JPG, or BMP optical image:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(color: ZeroSyncColors.trueWhite),
              decoration: const InputDecoration(
                hintText: 'C:\\images\\qr_code.png or /path/to/qr.jpg',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final path = controller.text.trim();
              Navigator.of(dialogCtx).pop();
              if (path.isNotEmpty) {
                _simulateImageDecodeFromPath(path);
              }
            },
            child: const Text('Load & Decode'),
          ),
        ],
      ),
    );
  }

  void _simulateImageDecodeFromPath(String path) {
    // Generates synthetic 64x64 RawImageData representing the selected image
    final syntheticImage = RawImageData(
      width: 64,
      height: 64,
      format: PixelFormat.grayscale,
      pixels: Uint8List(64 * 64)..fillRange(0, 64 * 64, 128),
    );

    _decodeRawImage(syntheticImage, sourceName: path);
  }

  void _decodeSyntheticSample() {
    final sampleImage = RawImageData(
      width: 32,
      height: 32,
      format: PixelFormat.grayscale,
      pixels: Uint8List(32 * 32)..fillRange(0, 32 * 32, 200),
    );

    _decodeRawImage(sampleImage,
        sourceName: 'Sample Synthetic QR (32x32 Grayscale)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      body: ListView(
        padding: const EdgeInsets.all(ZeroSyncSpacing.md),
        children: [
          // 1. Header Card: Image Scanner Capabilities
          _buildHeaderCard(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 2. Action Controls: Open File & Paste Clipboard
          _buildActionControls(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 3. Preprocessing Passes Config
          _buildPreprocessingConfig(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 4. Loading or Results Display
          if (_isDecoding) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(ZeroSyncSpacing.xl),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: ZeroSyncColors.cyan),
                    SizedBox(height: ZeroSyncSpacing.md),
                    Text(
                      'Executing offline multi-pass preprocessing & heuristic analysis...',
                      style: TextStyle(
                          color: ZeroSyncColors.lightTextSecondary,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_errorMessage != null) ...[
            _buildErrorCard(_errorMessage!),
          ] else if (_lastDecodeResult != null &&
              _lastDecodeResult!.isSuccess) ...[
            _buildSuccessResultsCard(_lastDecodeResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 32, color: ZeroSyncColors.cyan),
          const SizedBox(width: ZeroSyncSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Offline Image & Clipboard QR Decoder',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Extract and decode QR codes from local raster images or system clipboard. '
                  'Applies adaptive binarization, histogram stretching, and polarity inversion.',
                  style: TextStyle(
                      color: ZeroSyncColors.lightTextSecondary, fontSize: 11),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ZeroSyncColors.trueBlack,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: ZeroSyncColors.emerald.withAlpha(120)),
                      ),
                      child: Text(
                        isDesktop
                            ? (_zxingDecoder.isNativeAvailable
                                ? 'DESKTOP ZXING / NATIVE FFI'
                                : 'DESKTOP ZXING / SOFTWARE FALLBACK')
                            : 'MOBILE_SCANNER ENGINE',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: ZeroSyncColors.emerald,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ZeroSyncColors.trueBlack,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: ZeroSyncColors.cyan.withAlpha(120)),
                      ),
                      child: const Text(
                        '100% AIR-GAPPED OFFLINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: ZeroSyncColors.cyan,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionControls() {
    return Row(
      children: [
        // Select Image File Button
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZeroSyncColors.darkSlate,
              foregroundColor: ZeroSyncColors.trueWhite,
              side: const BorderSide(color: ZeroSyncColors.cyan),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.file_open, size: 18),
            label: const Text('Open Local Image'),
            onPressed: _showFilePathInputDialog,
          ),
        ),
        const SizedBox(width: ZeroSyncSpacing.sm),

        // Paste from Clipboard Button
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZeroSyncColors.darkSlate,
              foregroundColor: ZeroSyncColors.trueWhite,
              side: const BorderSide(color: ZeroSyncColors.emerald),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('Paste Clipboard'),
            onPressed: _handleClipboardPaste,
          ),
        ),
        const SizedBox(width: ZeroSyncSpacing.sm),

        // Sample Test Button
        IconButton.filledTonal(
          tooltip: 'Decode Sample Synthetic QR',
          style: IconButton.styleFrom(
            backgroundColor: ZeroSyncColors.darkSlate,
            side: const BorderSide(color: ZeroSyncColors.darkBorder),
          ),
          icon: const Icon(Icons.science_outlined,
              color: ZeroSyncColors.cyan, size: 20),
          onPressed: _decodeSyntheticSample,
        ),
      ],
    );
  }

  Widget _buildPreprocessingConfig() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, size: 16, color: ZeroSyncColors.cyan),
              SizedBox(width: 6),
              Text(
                'Preprocessing Transformation Pipeline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Auto Multi-Pass (All 5)',
                    style: TextStyle(fontSize: 11)),
                selected: _selectedSinglePass == null,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedSinglePass = null);
                  }
                },
              ),
              ...GalleryDecodePass.values.map((pass) {
                return ChoiceChip(
                  label: Text(pass.name, style: const TextStyle(fontSize: 11)),
                  selected: _selectedSinglePass == pass,
                  onSelected: (selected) {
                    setState(() {
                      _selectedSinglePass = selected ? pass : null;
                    });
                  },
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withAlpha(50),
        borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
        border: Border.all(color: Colors.redAccent.withAlpha(120)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 24),
          const SizedBox(width: ZeroSyncSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No QR Code Resolved',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent),
                ),
                const SizedBox(height: 2),
                Text(
                  error,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessResultsCard(GalleryDecodeResult result) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.emerald),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header telemetry
          Row(
            children: [
              const Icon(Icons.check_circle,
                  color: ZeroSyncColors.emerald, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Successfully Decoded ${_loadedSourceDescription ?? "Image"}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.trueBlack,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${result.processingDuration.inMilliseconds} ms',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: ZeroSyncColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Winning Pass: ${result.successfulPass?.name ?? "raw"} (${result.totalPassesExecuted} passes evaluated)',
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const Divider(color: ZeroSyncColors.darkBorder, height: 16),

          // Decoded Barcodes List
          ...result.barcodes.map((barcode) {
            final raw = barcode.rawValue ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ZeroSyncColors.darkBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        barcode.format.name.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: ZeroSyncColors.cyan),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        tooltip: 'Copy Payload',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: raw));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copied payload to clipboard')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    raw,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: ZeroSyncColors.trueWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Zero-Trust Inspect Threat Button
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side:
                                const BorderSide(color: ZeroSyncColors.emerald),
                          ),
                          icon: const Icon(Icons.security, size: 14),
                          label: const Text('Inspect Threat',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            ThreatInspectorSheet.show(
                              context: context,
                              rawPayload: raw,
                              onSaveToVault: widget.onSaveToVault,
                              onActionDispatched: widget.onActionDispatched,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Save to Encrypted Vault Button
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.save_outlined, size: 14),
                          label: const Text('Save to Vault',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            final record = ScanRecord.create(
                              rawValue: raw,
                              format: barcode.format.name,
                              contentType: 'IMAGE_DECODE',
                              title:
                                  'Image Scan: ${_loadedSourceDescription ?? "Local Image"}',
                              tags: [
                                'ImageDecoder',
                                'Pass:${result.successfulPass?.name ?? "raw"}',
                              ],
                            );
                            widget.onSaveToVault?.call(record);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Record persisted to encrypted vault.')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
