import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart' hide Crc32;
import 'package:airdrop_qr/core/utils/crc32.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';

/// Available resolution presets for rasterized PNG export.
enum PngResolution {
  /// 1024x1024 pixels (standard digital sharing / mobile display).
  standard(1024),

  /// 2048x2048 pixels (Retina / High-DPI screens & desktop publishing).
  highDpi(2048),

  /// 4096x4096 pixels (Ultra-HD / Professional 300+ DPI physical printing).
  ultraDpi(4096);

  final int dimension;
  const PngResolution(this.dimension);
}

/// Configuration options for raw XML-based SVG vector generation.
class SvgExportOptions {
  /// Width and height of the rendered SVG in points or CSS pixels.
  final double dimension;

  /// Number of quiet zone modules surrounding the matrix (ISO specifies >= 4).
  final int quietZoneModules;

  /// Hex color string for dark data modules (e.g. "#000000").
  final String foregroundColorHex;

  /// Hex color string for quiet zone and module background (e.g. "#FFFFFF").
  final String backgroundColorHex;

  /// Optional linear gradient colors [startHex, endHex].
  final List<String>? linearGradientHex;

  /// Module geometry: "square", "circle", or "rounded".
  final String moduleShape;

  const SvgExportOptions({
    this.dimension = 512.0,
    this.quietZoneModules = 4,
    this.foregroundColorHex = '#000000',
    this.backgroundColorHex = '#FFFFFF',
    this.linearGradientHex,
    this.moduleShape = 'square',
  }) : assert(quietZoneModules >= 0, 'Quiet zone must be >= 0');
}

/// Configuration options for print-ready vector PDF generation.
class PdfExportOptions {
  /// Printable artwork dimension in PDF points (1 pt = 1/72 inch).
  final double artworkPoints;

  /// Bleed allowance extending beyond the trim edge in points (9 pt = ~3mm).
  final double bleedPoints;

  /// Slug/margin surrounding the bleed area for trim and registration marks (in points).
  final double slugPoints;

  /// Number of quiet zone modules surrounding the matrix.
  final int quietZoneModules;

  /// Whether to render professional corner trim crosshairs and registration marks.
  final bool includeBleedMarks;

  /// Normalized RGB foreground color [0.0..1.0].
  final List<double> foregroundRgb;

  /// Normalized RGB background color [0.0..1.0].
  final List<double> backgroundRgb;

  const PdfExportOptions({
    this.artworkPoints = 300.0,
    this.bleedPoints = 9.0, // 3mm standard commercial bleed
    this.slugPoints = 36.0, // 0.5 inch printer margin
    this.quietZoneModules = 4,
    this.includeBleedMarks = true,
    this.foregroundRgb = const [0.0, 0.0, 0.0],
    this.backgroundRgb = const [1.0, 1.0, 1.0],
  })  : assert(quietZoneModules >= 0, 'Quiet zone must be >= 0'),
        assert(bleedPoints >= 0.0, 'Bleed must be >= 0');
}

/// Configuration options for High-DPI raster PNG generation.
class PngExportOptions {
  /// Target square dimension in pixels (e.g. 1024, 2048, 4096).
  final int dimension;

  /// Number of quiet zone modules surrounding the matrix.
  final int quietZoneModules;

  /// 32-bit ARGB foreground color integer (e.g. 0xFF000000).
  final int foregroundArgb;

  /// 32-bit ARGB background color integer (e.g. 0xFFFFFFFF).
  final int backgroundArgb;

  const PngExportOptions({
    this.dimension = 1024,
    this.quietZoneModules = 4,
    this.foregroundArgb = 0xFF000000,
    this.backgroundArgb = 0xFFFFFFFF,
  })  : assert(dimension > 0, 'Dimension must be > 0'),
        assert(quietZoneModules >= 0, 'Quiet zone must be >= 0');
}

/// Clean Architecture Domain Service executing vector and high-DPI export pipelines:
/// - Crisp, raw XML SVG generation without raster dependencies.
/// - Print-ready ISO 32000 vector PDF generation with TrimBox, BleedBox, and trim markers.
/// - Fast, pure-Dart high-DPI PNG generation (1024x1024, 2048x2048, 4096x4096).
class VectorExportService {
  /// Compiles [matrix] into a clean, standalone, scalable vector graphics (SVG) XML document.
  String exportToSvg(
    QrMatrix matrix, {
    SvgExportOptions options = const SvgExportOptions(),
  }) {
    final int matrixSize = matrix.size;
    final int totalGridUnits = matrixSize + (options.quietZoneModules * 2);
    final double unitScale = options.dimension / totalGridUnits;

    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<svg xmlns="http://www.w3.org/2000/svg" version="1.1" '
        'width="${options.dimension.toStringAsFixed(1)}" '
        'height="${options.dimension.toStringAsFixed(1)}" '
        'viewBox="0 0 ${options.dimension.toStringAsFixed(1)} ${options.dimension.toStringAsFixed(1)}" '
        'shape-rendering="crispEdges">');

    // Gradient definitions if requested
    String fillAttribute = 'fill="${options.foregroundColorHex}"';
    if (options.linearGradientHex != null &&
        options.linearGradientHex!.length >= 2) {
      sb.writeln('  <defs>');
      sb.writeln(
          '    <linearGradient id="qrGrad" x1="0%" y1="0%" x2="100%" y2="100%">');
      sb.writeln(
          '      <stop offset="0%" stop-color="${options.linearGradientHex![0]}" />');
      sb.writeln(
          '      <stop offset="100%" stop-color="${options.linearGradientHex![1]}" />');
      sb.writeln('    </linearGradient>');
      sb.writeln('  </defs>');
      fillAttribute = 'fill="url(#qrGrad)"';
    }

    // Background rect covering quiet zone
    sb.writeln(
        '  <rect width="100%" height="100%" fill="${options.backgroundColorHex}" />');

    // Construct unified SVG Path for dark modules
    final pathSb = StringBuffer();
    final double q = options.quietZoneModules.toDouble();

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (matrix.getModule(r, c)) {
          final double x = (c + q) * unitScale;
          final double y = (r + q) * unitScale;

          if (options.moduleShape == 'circle') {
            final double cx = x + unitScale / 2.0;
            final double cy = y + unitScale / 2.0;
            final double rad = unitScale * 0.45;
            // Draw circle as SVG path arc
            pathSb.write('M ${cx - rad} $cy ');
            pathSb.write('a $rad $rad 0 1 0 ${rad * 2} 0 ');
            pathSb.write('a $rad $rad 0 1 0 ${-rad * 2} 0 ');
          } else {
            // Default crisp square path: M x y h w v h h -w z
            pathSb.write('M ${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} '
                'h ${unitScale.toStringAsFixed(2)} '
                'v ${unitScale.toStringAsFixed(2)} '
                'h -${unitScale.toStringAsFixed(2)} z ');
          }
        }
      }
    }

    sb.writeln('  <path d="${pathSb.toString().trim()}" $fillAttribute />');
    sb.writeln('</svg>');

    return sb.toString();
  }

  /// Compiles [matrix] into a commercial print-ready ISO 32000-1 vector PDF
  /// with MediaBox, BleedBox, TrimBox, and precision corner trim crosshair markers.
  Uint8List exportToPdf(
    QrMatrix matrix, {
    PdfExportOptions options = const PdfExportOptions(),
  }) {
    final double artwork = options.artworkPoints;
    final double bleed = options.bleedPoints;
    final double slug = options.includeBleedMarks ? options.slugPoints : 0.0;

    // Total page media dimension (artwork + 2*bleed + 2*slug)
    final double mediaWidth = artwork + (bleed * 2.0) + (slug * 2.0);
    final double mediaHeight = mediaWidth;

    // Coordinate offsets (PDF coordinates origin is bottom-left)
    final double trimLeft = slug + bleed;
    final double trimBottom = slug + bleed;
    final double trimRight = trimLeft + artwork;
    final double trimTop = trimBottom + artwork;

    final double bleedLeft = slug;
    final double bleedBottom = slug;
    final double bleedRight = mediaWidth - slug;
    final double bleedTop = mediaHeight - slug;

    // Content stream instructions
    final cs = StringBuffer();

    // 1. Draw Background covering BleedBox
    final bgR = options.backgroundRgb[0];
    final bgG = options.backgroundRgb[1];
    final bgB = options.backgroundRgb[2];
    cs.writeln('$bgR $bgG $bgB rg');
    cs.writeln(
        '$bleedLeft $bleedBottom ${(bleedRight - bleedLeft).toStringAsFixed(2)} ${(bleedTop - bleedBottom).toStringAsFixed(2)} re f');

    // 2. Draw QR Modules inside TrimBox
    final fgR = options.foregroundRgb[0];
    final fgG = options.foregroundRgb[1];
    final fgB = options.foregroundRgb[2];
    cs.writeln('$fgR $fgG $fgB rg');

    final int matrixSize = matrix.size;
    final int totalGrid = matrixSize + (options.quietZoneModules * 2);
    final double modulePoints = artwork / totalGrid;
    final double q = options.quietZoneModules.toDouble();

    for (int r = 0; r < matrixSize; r++) {
      for (int c = 0; c < matrixSize; c++) {
        if (matrix.getModule(r, c)) {
          final double x = trimLeft + (c + q) * modulePoints;
          // Invert row because PDF Y=0 is bottom
          final double y = trimTop - (r + q + 1) * modulePoints;
          cs.writeln('${x.toStringAsFixed(2)} ${y.toStringAsFixed(2)} '
              '${modulePoints.toStringAsFixed(2)} ${modulePoints.toStringAsFixed(2)} re f');
        }
      }
    }

    // 3. Draw Print-Ready Bleed & Trim Crosshair Marks
    if (options.includeBleedMarks) {
      cs.writeln('0 0 0 RG'); // 100% Black for registration marks
      cs.writeln('0.5 w'); // 0.5 pt fine hairline stroke
      const double markLength = 18.0;

      // Bottom-Left Trim Mark
      cs.writeln(
          '${trimLeft - markLength} $trimBottom m $trimLeft $trimBottom l S');
      cs.writeln(
          '$trimLeft ${trimBottom - markLength} m $trimLeft $trimBottom l S');

      // Top-Left Trim Mark
      cs.writeln('${trimLeft - markLength} $trimTop m $trimLeft $trimTop l S');
      cs.writeln('$trimLeft ${trimTop + markLength} m $trimLeft $trimTop l S');

      // Bottom-Right Trim Mark
      cs.writeln(
          '${trimRight + markLength} $trimBottom m $trimRight $trimBottom l S');
      cs.writeln(
          '$trimRight ${trimBottom - markLength} m $trimRight $trimBottom l S');

      // Top-Right Trim Mark
      cs.writeln(
          '${trimRight + markLength} $trimTop m $trimRight $trimTop l S');
      cs.writeln(
          '$trimRight ${trimTop + markLength} m $trimRight $trimTop l S');

      // Circular Registration Crosshair centered in top slug
      final double regX = mediaWidth / 2.0;
      final double regY = mediaHeight - (slug / 2.0);
      const double regRadius = 6.0;
      cs.writeln('${regX - regRadius} $regY m ${regX + regRadius} $regY l S');
      cs.writeln('$regX ${regY - regRadius} m $regX ${regY + regRadius} l S');
    }

    final contentBytes = utf8.encode(cs.toString());

    // Build PDF 1.4 Object Structure
    final List<int> pdfBuffer = <int>[];
    final offsets = <int>[];

    void writeString(String s) {
      pdfBuffer.addAll(utf8.encode(s));
    }

    // Header
    writeString('%PDF-1.4\n');
    writeString('%\xE2\xE3\xCF\xD3\n'); // Binary marker

    // Object 1: Catalog
    offsets.add(pdfBuffer.length);
    writeString('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    // Object 2: Pages Tree
    offsets.add(pdfBuffer.length);
    writeString('2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');

    // Object 3: Page Object
    offsets.add(pdfBuffer.length);
    writeString('3 0 obj\n<< /Type /Page /Parent 2 0 R\n');
    writeString(
        '   /MediaBox [0 0 ${mediaWidth.toStringAsFixed(2)} ${mediaHeight.toStringAsFixed(2)}]\n');
    writeString(
        '   /BleedBox [${bleedLeft.toStringAsFixed(2)} ${bleedBottom.toStringAsFixed(2)} '
        '${bleedRight.toStringAsFixed(2)} ${bleedTop.toStringAsFixed(2)}]\n');
    writeString(
        '   /TrimBox [${trimLeft.toStringAsFixed(2)} ${trimBottom.toStringAsFixed(2)} '
        '${trimRight.toStringAsFixed(2)} ${trimTop.toStringAsFixed(2)}]\n');
    writeString('   /Contents 4 0 R\n');
    writeString('   /Resources << >>\n>>\nendobj\n');

    // Object 4: Contents Stream
    offsets.add(pdfBuffer.length);
    writeString('4 0 obj\n<< /Length ${contentBytes.length} >>\nstream\n');
    pdfBuffer.addAll(contentBytes);
    writeString('\nendstream\nendobj\n');

    // Cross-Reference Table
    final int xrefOffset = pdfBuffer.length;
    writeString('xref\n0 5\n');
    writeString('0000000000 65535 f \n');
    for (final off in offsets) {
      writeString('${off.toString().padLeft(10, '0')} 00000 n \n');
    }

    // Trailer
    writeString('trailer\n<< /Size 5 /Root 1 0 R >>\n');
    writeString('startxref\n$xrefOffset\n%%EOF\n');

    return Uint8List.fromList(pdfBuffer);
  }

  /// Compiles [matrix] into a lossless, high-DPI PNG raster buffer (e.g. 1024, 2048, 4096)
  /// using pure Dart RFC 2083 encapsulation with zlib compression.
  Uint8List exportToPng(
    QrMatrix matrix, {
    PngExportOptions options = const PngExportOptions(),
  }) {
    final int width = options.dimension;
    final int height = options.dimension;

    final int matrixSize = matrix.size;
    final int totalGridUnits = matrixSize + (options.quietZoneModules * 2);
    final double scale = width / totalGridUnits;
    final int q = options.quietZoneModules;

    // Extract ARGB components
    final int fgA = (options.foregroundArgb >> 24) & 0xFF;
    final int fgR = (options.foregroundArgb >> 16) & 0xFF;
    final int fgG = (options.foregroundArgb >> 8) & 0xFF;
    final int fgB = options.foregroundArgb & 0xFF;

    final int bgA = (options.backgroundArgb >> 24) & 0xFF;
    final int bgR = (options.backgroundArgb >> 16) & 0xFF;
    final int bgG = (options.backgroundArgb >> 8) & 0xFF;
    final int bgB = options.backgroundArgb & 0xFF;

    // Construct uncompressed scanlines: each scanline starts with filter byte 0 (None),
    // followed by width * 4 bytes (RGBA).
    final int bytesPerScanline = 1 + (width * 4);
    final Uint8List rawScanlines = Uint8List(bytesPerScanline * height);

    for (int y = 0; y < height; y++) {
      final int scanlineOffset = y * bytesPerScanline;
      rawScanlines[scanlineOffset] = 0; // Filter: None

      final int r = (y / scale).floor() - q;
      final bool rowInBounds = r >= 0 && r < matrixSize;

      for (int x = 0; x < width; x++) {
        final int pixelOffset = scanlineOffset + 1 + (x * 4);
        final int c = (x / scale).floor() - q;

        final bool isDark =
            rowInBounds && c >= 0 && c < matrixSize && matrix.getModule(r, c);

        if (isDark) {
          rawScanlines[pixelOffset] = fgR;
          rawScanlines[pixelOffset + 1] = fgG;
          rawScanlines[pixelOffset + 2] = fgB;
          rawScanlines[pixelOffset + 3] = fgA;
        } else {
          rawScanlines[pixelOffset] = bgR;
          rawScanlines[pixelOffset + 1] = bgG;
          rawScanlines[pixelOffset + 2] = bgB;
          rawScanlines[pixelOffset + 3] = bgA;
        }
      }
    }

    // Compress scanlines with zlib
    final compressedIdat = const ZLibEncoder().encode(rawScanlines);

    // Assemble standard PNG file (RFC 2083)
    final png = BytesBuilder();

    // 1. PNG Signature (8 bytes)
    png.add([137, 80, 78, 71, 13, 10, 26, 10]);

    // 2. IHDR Chunk
    final ihdrData = ByteData(13)
      ..setUint32(0, width, Endian.big)
      ..setUint32(4, height, Endian.big)
      ..setUint8(8, 8) // Bit depth: 8
      ..setUint8(9, 6) // Color type: 6 (RGBA)
      ..setUint8(10, 0) // Compression: Deflate
      ..setUint8(11, 0) // Filter: None
      ..setUint8(12, 0); // Interlace: None
    _writeChunk(png, 'IHDR', ihdrData.buffer.asUint8List());

    // 3. IDAT Chunk
    _writeChunk(png, 'IDAT', Uint8List.fromList(compressedIdat));

    // 4. IEND Chunk
    _writeChunk(png, 'IEND', Uint8List(0));

    return png.toBytes();
  }

  void _writeChunk(BytesBuilder builder, String type, Uint8List data) {
    final typeBytes = utf8.encode(type);

    // 1. Length (4 bytes BE)
    final lengthBytes = ByteData(4)..setUint32(0, data.length, Endian.big);
    builder.add(lengthBytes.buffer.asUint8List());

    // 2. Type & Data for CRC
    final crcPayload = Uint8List(4 + data.length);
    crcPayload.setRange(0, 4, typeBytes);
    crcPayload.setRange(4, 4 + data.length, data);
    builder.add(crcPayload);

    // 3. CRC32 (4 bytes BE)
    final crcValue = Crc32.compute(crcPayload);
    final crcBytes = ByteData(4)..setUint32(0, crcValue, Endian.big);
    builder.add(crcBytes.buffer.asUint8List());
  }
}
