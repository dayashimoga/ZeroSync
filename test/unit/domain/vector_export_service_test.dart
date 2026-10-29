import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart' hide Crc32;
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/domain/services/vector_export_service.dart';

void main() {
  late VectorExportService exportService;
  late QrMatrix testMatrix;

  setUp(() {
    exportService = VectorExportService();
    final matrixService = QrMatrixGeneratorService();
    testMatrix = matrixService.generateMatrix(
      payload: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
      eccLevel: QrErrorCorrectionLevel.medium,
      fixedVersion: 1, // 21x21
    );
  });

  group('Raw XML SVG Vector Generator', () {
    test('Generates valid standalone SVG XML structure', () {
      final svg = exportService.exportToSvg(
        testMatrix,
        options: const SvgExportOptions(
          dimension: 400.0,
          quietZoneModules: 4,
          foregroundColorHex: '#123456',
          backgroundColorHex: '#FAFAFA',
        ),
      );

      expect(svg.startsWith('<?xml version="1.0" encoding="UTF-8"?>'), isTrue);
      expect(svg.contains('<svg xmlns="http://www.w3.org/2000/svg"'), isTrue);
      expect(svg.contains('width="400.0"'), isTrue);
      expect(svg.contains('height="400.0"'), isTrue);
      expect(svg.contains('viewBox="0 0 400.0 400.0"'), isTrue);
      expect(svg.contains('<rect width="100%" height="100%" fill="#FAFAFA"'),
          isTrue);
      expect(svg.contains('<path d="M'), isTrue);
      expect(svg.contains('fill="#123456"'), isTrue);
      expect(svg.trim().endsWith('</svg>'), isTrue);
    });

    test('Injects linear gradient definitions when requested', () {
      final svg = exportService.exportToSvg(
        testMatrix,
        options: const SvgExportOptions(
          linearGradientHex: ['#00E5FF', '#7C4DFF'],
        ),
      );

      expect(svg.contains('<defs>'), isTrue);
      expect(svg.contains('<linearGradient id="qrGrad"'), isTrue);
      expect(svg.contains('stop-color="#00E5FF"'), isTrue);
      expect(svg.contains('stop-color="#7C4DFF"'), isTrue);
      expect(svg.contains('fill="url(#qrGrad)"'), isTrue);
    });

    test('Renders circular dot paths when moduleShape is circle', () {
      final svg = exportService.exportToSvg(
        testMatrix,
        options: const SvgExportOptions(
          moduleShape: 'circle',
        ),
      );

      // SVG path contains arc commands (a ...)
      expect(svg.contains(' a '), isTrue);
    });
  });

  group('Print-Ready Vector PDF Generator (ISO 32000-1)', () {
    test('Generates conforming PDF document with bleed, trim, and media boxes',
        () {
      final pdfBytes = exportService.exportToPdf(
        testMatrix,
        options: const PdfExportOptions(
          artworkPoints: 300.0,
          bleedPoints: 9.0, // 3mm bleed
          slugPoints: 36.0,
          includeBleedMarks: true,
        ),
      );

      final pdfString = latin1.decode(pdfBytes);

      // 1. PDF Header & Binary comment
      expect(pdfString.startsWith('%PDF-1.4\n'), isTrue);

      // 2. Structural Dictionaries
      expect(pdfString.contains('/Type /Catalog'), isTrue);
      expect(pdfString.contains('/Type /Pages'), isTrue);
      expect(pdfString.contains('/Type /Page'), isTrue);

      // 3. Print Boxes
      expect(pdfString.contains('/MediaBox'), isTrue);
      expect(pdfString.contains('/BleedBox'), isTrue);
      expect(pdfString.contains('/TrimBox'), isTrue);

      // 4. Content stream and vector operators
      expect(pdfString.contains('stream\n'), isTrue);
      expect(pdfString.contains('re f'), isTrue); // Fill rectangles
      expect(pdfString.contains('m '), isTrue); // MoveTo
      expect(pdfString.contains('l S'), isTrue); // LineTo + Stroke

      // 5. Cross-reference table & trailer
      expect(pdfString.contains('xref\n0 5\n'), isTrue);
      expect(pdfString.contains('trailer\n<< /Size 5 /Root 1 0 R >>'), isTrue);
      expect(pdfString.contains('startxref\n'), isTrue);
      expect(pdfString.trim().endsWith('%%EOF'), isTrue);
    });

    test('Renders without bleed marks when disabled', () {
      final pdfBytes = exportService.exportToPdf(
        testMatrix,
        options: const PdfExportOptions(
          includeBleedMarks: false,
        ),
      );

      final pdfString = latin1.decode(pdfBytes);
      expect(pdfString.contains('0 0 0 RG'), isFalse);
    });
  });

  group('High-DPI Raster PNG Generator (RFC 2083)', () {
    test('Generates valid PNG signature and IHDR/IDAT/IEND chunks', () {
      final pngBytes = exportService.exportToPng(
        testMatrix,
        options: const PngExportOptions(
          dimension: 128, // Fast test resolution
          quietZoneModules: 4,
        ),
      );

      // 1. PNG Signature (8 bytes)
      expect(
        pngBytes.sublist(0, 8),
        equals(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
      );

      // 2. IHDR Chunk
      final ihdrLength = ByteData.sublistView(pngBytes, 8, 12).getUint32(0);
      expect(ihdrLength, equals(13));
      final ihdrType = utf8.decode(pngBytes.sublist(12, 16));
      expect(ihdrType, equals('IHDR'));

      final width = ByteData.sublistView(pngBytes, 16, 20).getUint32(0);
      final height = ByteData.sublistView(pngBytes, 20, 24).getUint32(0);
      expect(width, equals(128));
      expect(height, equals(128));

      // 3. Verify IEND chunk at end
      final iendIndex = pngBytes.length - 12;
      final iendType =
          utf8.decode(pngBytes.sublist(iendIndex + 4, iendIndex + 8));
      expect(iendType, equals('IEND'));
    });

    test('Decompresses IDAT chunk to verify exact scanline byte count', () {
      const dimension = 64;
      final pngBytes = exportService.exportToPng(
        testMatrix,
        options: const PngExportOptions(
          dimension: dimension,
        ),
      );

      // Extract IDAT chunk payload (starts after IHDR: 8 + 12 + 13 = 33)
      final idatLength = ByteData.sublistView(pngBytes, 33, 37).getUint32(0);
      final idatType = utf8.decode(pngBytes.sublist(37, 41));
      expect(idatType, equals('IDAT'));

      final compressedData = pngBytes.sublist(41, 41 + idatLength);
      final decompressed = const ZLibDecoder().decodeBytes(compressedData);

      // Each scanline has 1 filter byte + dimension * 4 bytes RGBA
      const expectedBytes = dimension * (1 + dimension * 4);
      expect(decompressed.length, equals(expectedBytes));
    });

    test('Supports high-DPI presets: 1024x1024 and 2048x2048', () {
      // 1024x1024 Standard
      final png1024 = exportService.exportToPng(
        testMatrix,
        options: PngExportOptions(
          dimension: PngResolution.standard.dimension,
        ),
      );
      final width1024 = ByteData.sublistView(png1024, 16, 20).getUint32(0);
      expect(width1024, equals(1024));

      // 2048x2048 High-DPI
      final png2048 = exportService.exportToPng(
        testMatrix,
        options: PngExportOptions(
          dimension: PngResolution.highDpi.dimension,
        ),
      );
      final width2048 = ByteData.sublistView(png2048, 16, 20).getUint32(0);
      expect(width2048, equals(2048));
    });
  });
}
