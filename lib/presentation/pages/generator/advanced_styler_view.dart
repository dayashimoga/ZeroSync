import 'dart:convert';

import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/ecc_allocator_service.dart';
import 'package:airdrop_qr/domain/services/logo_clipping_mask_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/domain/services/vector_export_service.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/qr_custom_styler_canvas.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Workspace for advanced visual styling of QR codes:
/// - Custom data module geometries (square, circle, rounded, diamond, fluid)
/// - Custom finder eye frames (square, rounded, circle, leaf) and pupils
/// - Linear and radial gradients with high-contrast safety validation
/// - Central security logo cutout with automatic ECC Level H escalation
/// - Offline vector export (SVG XML, ISO 32000 PDF with bleed marks, high-DPI PNG)
class AdvancedStylerView extends StatefulWidget {
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const AdvancedStylerView({
    super.key,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  @override
  State<AdvancedStylerView> createState() => _AdvancedStylerViewState();
}

class _AdvancedStylerViewState extends State<AdvancedStylerView> {
  final TextEditingController _payloadController =
      TextEditingController(text: 'https://zerosync.security/airgap-styler');

  final QrMatrixGeneratorService _matrixGenerator = QrMatrixGeneratorService();
  final VectorExportService _vectorExporter = VectorExportService();
  final LogoClippingMaskService _logoMaskService = LogoClippingMaskService();
  final EccAllocatorService _eccAllocator = EccAllocatorService();

  // Active visual styling parameters
  QrModuleShape _moduleShape = QrModuleShape.fluid;
  QrEyeFrameShape _eyeFrameShape = QrEyeFrameShape.roundedSquare;
  QrEyePupilShape _eyePupilShape = QrEyePupilShape.circle;

  Color _dataColor = ZeroSyncColors.cyan;
  Color _backgroundColor = ZeroSyncColors.trueBlack;
  bool _useGradient = true;
  bool _embedLogo = false;

  late QrMatrix _matrix;
  LogoClippingResult? _clippingResult;
  QrErrorCorrectionLevel _effectiveEccLevel = QrErrorCorrectionLevel.medium;

  @override
  void initState() {
    super.initState();
    _recomputeMatrix();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  void _recomputeMatrix() {
    final text = _payloadController.text.trim();
    final effectiveText =
        text.isEmpty ? 'ZeroSync Air-Gap Secure Payload' : text;
    final bytes = Uint8List.fromList(utf8.encode(effectiveText));

    if (_embedLogo) {
      _effectiveEccLevel = QrErrorCorrectionLevel.high;
    } else {
      final allocation = _eccAllocator.allocateEcc(
        payloadLength: bytes.length,
        exportTarget: QrExportTarget.screenDisplay,
        strategy: EccOptimizationStrategy.balanced,
      );
      _effectiveEccLevel = allocation.finalEccLevel;
    }

    try {
      _matrix = _matrixGenerator.generateMatrix(
        payload: bytes,
        eccLevel: _effectiveEccLevel,
      );
    } catch (_) {
      // Fallback matrix
      _matrix = _matrixGenerator.generateMatrix(
        payload: Uint8List.fromList(utf8.encode('ZeroSync Fallback')),
        eccLevel: QrErrorCorrectionLevel.medium,
      );
    }

    if (_embedLogo) {
      _clippingResult = _logoMaskService.computeClippingMask(
        matrixSize: _matrix.size,
        eccLevel: QrErrorCorrectionLevel.high,
        shape: LogoMaskShape.circle,
      );
    } else {
      _clippingResult = null;
    }
  }

  QrStylerConfig _buildConfig() {
    return QrStylerConfig(
      moduleShape: _moduleShape,
      eyeFrameShape: _eyeFrameShape,
      eyePupilShape: _eyePupilShape,
      dataColor: _dataColor,
      backgroundColor: _backgroundColor,
      dataGradient: _useGradient
          ? LinearGradient(
              colors: [_dataColor, ZeroSyncColors.emerald],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      eyeFrameColor: _dataColor,
      eyePupilColor: ZeroSyncColors.emerald,
      quietZoneModules: 4,
    );
  }

  void _applyPreset(String preset) {
    setState(() {
      switch (preset) {
        case 'Classic':
          _moduleShape = QrModuleShape.square;
          _eyeFrameShape = QrEyeFrameShape.square;
          _eyePupilShape = QrEyePupilShape.square;
          _dataColor = Colors.white;
          _backgroundColor = Colors.black;
          _useGradient = false;
          _embedLogo = false;
          break;
        case 'Neon Fluid':
          _moduleShape = QrModuleShape.fluid;
          _eyeFrameShape = QrEyeFrameShape.roundedSquare;
          _eyePupilShape = QrEyePupilShape.circle;
          _dataColor = ZeroSyncColors.cyan;
          _backgroundColor = ZeroSyncColors.trueBlack;
          _useGradient = true;
          break;
        case 'Emerald Secure':
          _moduleShape = QrModuleShape.roundedSquare;
          _eyeFrameShape = QrEyeFrameShape.leaf;
          _eyePupilShape = QrEyePupilShape.diamond;
          _dataColor = ZeroSyncColors.emerald;
          _backgroundColor = ZeroSyncColors.darkGraphite;
          _useGradient = false;
          _embedLogo = true;
          break;
      }
      _recomputeMatrix();
    });
  }

  void _exportSvg() {
    final svgXml = _vectorExporter.exportToSvg(
      _matrix,
      options: SvgExportOptions(
        dimension: 1024,
        foregroundColorHex: '#00E5FF',
        backgroundColorHex: '#000000',
        moduleShape: _moduleShape.name,
      ),
    );

    Clipboard.setData(ClipboardData(text: svgXml));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Exported Scalable Vector Graphics (SVG XML copied to clipboard).'),
      ),
    );
  }

  void _exportPdf() {
    final pdfBytes = _vectorExporter.exportToPdf(
      _matrix,
      options: const PdfExportOptions(
        includeBleedMarks: true,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Generated print-ready ISO 32000 PDF with bleed & trim marks (${pdfBytes.length} bytes).',
        ),
      ),
    );
  }

  void _saveToVault() {
    final record = ScanRecord.create(
      rawValue: _payloadController.text.trim(),
      format: 'QR_CODE',
      contentType: 'STYLED_QR',
      title: 'Styled QR: ${_moduleShape.name} / ${_eyeFrameShape.name}',
      tags: ['Styler', 'VectorExport', 'Shape:${_moduleShape.name}'],
    );

    widget.onSaveToVault?.call(record);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${record.title}" to SQLCipher vault.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = _buildConfig();

    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Column: Styler Studio Controls
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: const EdgeInsets.all(ZeroSyncSpacing.md),
                    children: _buildControlsWidgets(),
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  color: ZeroSyncColors.darkBorder,
                ),
                // Right Column: Stylized Vector Canvas & Export Options
                Expanded(
                  flex: 4,
                  child: ListView(
                    padding: const EdgeInsets.all(ZeroSyncSpacing.md),
                    children: [
                      _buildCanvasCard(config),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return ListView(
              padding: const EdgeInsets.all(ZeroSyncSpacing.md),
              children: [
                ..._buildControlsWidgets(),
                const SizedBox(height: ZeroSyncSpacing.lg),
                _buildCanvasCard(config),
              ],
            );
          }
        },
      ),
    );
  }

  List<Widget> _buildControlsWidgets() {
    return [
      // 1. Payload Input
      _buildPayloadSection(),
      const SizedBox(height: ZeroSyncSpacing.md),

      // 2. Preset Themes
      _buildPresetsSection(),
      const SizedBox(height: ZeroSyncSpacing.md),

      // 3. Module Geometries
      _buildModuleShapeSection(),
      const SizedBox(height: ZeroSyncSpacing.md),

      // 4. Finder Pattern Eye Geometries
      _buildEyeShapesSection(),
      const SizedBox(height: ZeroSyncSpacing.md),

      // 5. Logo Embedding & ECC Escalation
      _buildLogoSection(),
    ];
  }

  Widget _buildPayloadSection() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: TextField(
        controller: _payloadController,
        style: const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
        decoration: const InputDecoration(
          labelText: 'Payload Data',
          hintText: 'Enter text or URL to stylize...',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          setState(() {
            _recomputeMatrix();
          });
        },
      ),
    );
  }

  Widget _buildPresetsSection() {
    final presets = ['Classic', 'Neon Fluid', 'Emerald Secure'];

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Styler Theme Presets',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: presets.map((preset) {
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.trueWhite,
                  side: const BorderSide(color: ZeroSyncColors.darkBorder),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _applyPreset(preset),
                child: Text(preset, style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleShapeSection() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Module Shape',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: QrModuleShape.values.map((shape) {
              final isSelected = _moduleShape == shape;
              return ChoiceChip(
                label: Text(shape.name, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _moduleShape = shape);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEyeShapesSection() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Finder Pattern (Eye) Frame Shape',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: QrEyeFrameShape.values.map((shape) {
              final isSelected = _eyeFrameShape == shape;
              return ChoiceChip(
                label: Text(shape.name, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _eyeFrameShape = shape);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Finder Pattern Inner Pupil Shape',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: QrEyePupilShape.values.map((shape) {
              final isSelected = _eyePupilShape == shape;
              return ChoiceChip(
                label: Text(shape.name, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _eyePupilShape = shape);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    final cutoutRatioText = _clippingResult != null
        ? 'Cutout: ${(_clippingResult!.areaCoverageRatio * 100).toStringAsFixed(1)}%'
        : '<= 20% Optical Limit';

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(
          color: _embedLogo
              ? ZeroSyncColors.emerald.withAlpha(150)
              : ZeroSyncColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Embed Central Security Shield Logo',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite,
              ),
            ),
            subtitle: const Text(
              'Computes safe cutout bounds and automatically escalates ECC to Level H (30%).',
              style: TextStyle(fontSize: 10, color: Colors.white60),
            ),
            value: _embedLogo,
            activeThumbColor: ZeroSyncColors.emerald,
            onChanged: (val) {
              setState(() {
                _embedLogo = val;
                _recomputeMatrix();
              });
            },
          ),
          if (_embedLogo) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield,
                      size: 14, color: ZeroSyncColors.emerald),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ECC Escalated to Level H • $cutoutRatioText',
                      style: const TextStyle(
                          fontSize: 10, color: ZeroSyncColors.emerald),
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

  Widget _buildCanvasCard(QrStylerConfig config) {
    final eccString = _effectiveEccLevel == QrErrorCorrectionLevel.high
        ? 'ECC: H (30%)'
        : (_effectiveEccLevel == QrErrorCorrectionLevel.quartile
            ? 'ECC: Q (25%)'
            : (_effectiveEccLevel == QrErrorCorrectionLevel.medium
                ? 'ECC: M (15%)'
                : 'ECC: L (7%)'));

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.palette, size: 18, color: ZeroSyncColors.cyan),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'High-Resolution Vector Canvas',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.trueBlack,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  eccString,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: ZeroSyncColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Custom Painted QR Canvas
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: config.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ZeroSyncColors.darkBorder),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                QrCustomStylerCanvas(
                  matrix: _matrix,
                  config: config,
                  size: 240,
                ),
                if (_embedLogo)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: config.backgroundColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ZeroSyncColors.emerald,
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.shield,
                        size: 24,
                        color: ZeroSyncColors.emerald,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Vector Export Actions
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.cyan,
                  side: const BorderSide(color: ZeroSyncColors.cyan),
                ),
                icon: const Icon(Icons.code, size: 14),
                label: const Text('Export SVG', style: TextStyle(fontSize: 11)),
                onPressed: _exportSvg,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.emerald,
                  side: const BorderSide(color: ZeroSyncColors.emerald),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                label: const Text('Export PDF', style: TextStyle(fontSize: 11)),
                onPressed: _exportPdf,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.amber,
                  side: const BorderSide(color: ZeroSyncColors.amber),
                ),
                icon: const Icon(Icons.security, size: 14),
                label: const Text('Inspect Threat',
                    style: TextStyle(fontSize: 11)),
                onPressed: () {
                  ThreatInspectorSheet.show(
                    context: context,
                    rawPayload: _payloadController.text.trim(),
                    onActionDispatched: (String p) =>
                        widget.onActionDispatched?.call(p),
                  );
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.emerald,
                  foregroundColor: ZeroSyncColors.trueBlack,
                ),
                icon: const Icon(Icons.save, size: 14),
                label: const Text('Save to Vault',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _saveToVault,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
