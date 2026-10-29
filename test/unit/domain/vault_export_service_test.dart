import 'dart:convert';
import 'dart:typed_data';

import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:airdrop_qr/domain/services/vault_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late VaultExportService exportService;
  late List<ScanRecord> sampleRecords;

  setUp(() {
    exportService = const VaultExportService();

    final t0 = DateTime(2026, 10, 29, 10, 0, 0);
    final t1 = DateTime(2026, 10, 29, 11, 0, 0);
    final t2 = DateTime(2026, 10, 29, 12, 0, 0);

    sampleRecords = [
      ScanRecord(
        id: 'rec-001',
        rawValue: 'https://flutter.dev/docs',
        format: 'qrCode',
        contentType: 'url',
        createdAt: t0,
        updatedAt: t0,
        isFavorite: true,
        title: 'Flutter Documentation',
        notes: 'Useful reference',
        threatSeverity: 'none',
        tags: const ['dev', 'flutter'],
      ),
      ScanRecord(
        id: 'rec-002',
        rawValue: 'WIFI:S:ZeroSyncLAN;T:WPA;P:SecretPass;;',
        rawBytes: Uint8List.fromList([1, 2, 3, 4]),
        format: 'qrCode',
        contentType: 'wifi',
        createdAt: t1,
        updatedAt: t1,
        isFavorite: false,
        title: 'Office Network',
        notes: 'WPA3 secured',
        threatSeverity: 'none',
        tags: const ['work', 'network'],
      ),
      ScanRecord(
        id: 'rec-003',
        rawValue: 'http://192.168.1.1/exploit',
        format: 'qrCode',
        contentType: 'url',
        createdAt: t2,
        updatedAt: t2,
        isFavorite: false,
        title: 'Suspicious Router URL',
        notes: 'Potential drive-by download',
        threatSeverity: 'critical',
        tags: const ['security', 'threat', 'network'],
      ),
    ];
  });

  group('VaultSearchFilter Multi-Attribute Filtering Tests', () {
    test('Filters by substring search across rawValue, title, notes, and tags', () {
      const filterValue = VaultSearchFilter(searchQuery: 'flutter.dev');
      expect(exportService.filter(sampleRecords, filterValue).length, equals(1));

      const filterTitle = VaultSearchFilter(searchQuery: 'router');
      expect(exportService.filter(sampleRecords, filterTitle).length, equals(1));

      const filterNotes = VaultSearchFilter(searchQuery: 'drive-by');
      expect(exportService.filter(sampleRecords, filterNotes).length, equals(1));

      const filterTag = VaultSearchFilter(searchQuery: 'network');
      expect(exportService.filter(sampleRecords, filterTag).length, equals(2));
    });

    test('Filters by date range boundaries', () {
      final filterTime = VaultSearchFilter(
        startDate: DateTime(2026, 10, 29, 10, 30, 0),
        endDate: DateTime(2026, 10, 29, 11, 30, 0),
      );

      final matches = exportService.filter(sampleRecords, filterTime);
      expect(matches.length, equals(1));
      expect(matches.first.id, equals('rec-002'));
    });

    test('Filters by favorite flag', () {
      const filterFav = VaultSearchFilter(isFavoriteOnly: true);
      final matches = exportService.filter(sampleRecords, filterFav);
      expect(matches.length, equals(1));
      expect(matches.first.id, equals('rec-001'));
    });

    test('Filters by contentType and threatSeverity', () {
      const filterUrl = VaultSearchFilter(contentType: 'url');
      expect(exportService.filter(sampleRecords, filterUrl).length, equals(2));

      const filterCritical = VaultSearchFilter(threatSeverity: 'critical');
      final matches = exportService.filter(sampleRecords, filterCritical);
      expect(matches.length, equals(1));
      expect(matches.first.id, equals('rec-003'));
    });

    test('Filters by tags (any match vs all match)', () {
      // Any match: 'dev' or 'threat' -> rec-001 and rec-003
      const filterAny = VaultSearchFilter(
        tags: ['dev', 'threat'],
        matchAllTags: false,
      );
      expect(exportService.filter(sampleRecords, filterAny).length, equals(2));

      // All match: 'network' and 'threat' -> only rec-003
      const filterAll = VaultSearchFilter(
        tags: ['network', 'threat'],
        matchAllTags: true,
      );
      final matchesAll = exportService.filter(sampleRecords, filterAll);
      expect(matchesAll.length, equals(1));
      expect(matchesAll.first.id, equals('rec-003'));
    });
  });

  group('JSON Batch Export Pipeline', () {
    test('Generates valid conforming JSON array with base64 bytes', () {
      final jsonOutput = exportService.exportToJson(sampleRecords, pretty: true);

      expect(jsonOutput, isNotEmpty);
      final decoded = jsonDecode(jsonOutput) as List<dynamic>;
      expect(decoded.length, equals(3));

      final rec2 = decoded[1] as Map<String, dynamic>;
      expect(rec2['id'], equals('rec-002'));
      expect(rec2['rawBytesBase64'], equals(base64Encode([1, 2, 3, 4])));
      expect(rec2['tags'], equals(['work', 'network']));
    });
  });

  group('CSV Batch Export Pipeline (RFC 4180)', () {
    test('Generates conforming CSV table with escaping for quotes and commas', () {
      final trickyRecords = [
        ScanRecord.create(
          rawValue: 'Field with, comma and "quotes" and \n newline',
          format: 'qrCode',
          contentType: 'text',
          title: 'Special "Chars"',
          notes: 'Line 1,\nLine 2',
        ),
      ];

      final csv = exportService.exportToCsv(trickyRecords);
      expect(csv, contains('ID,Raw Value,Format,Content Type,Created At,Updated At,Favorite,Title,Notes,Threat Severity,Tags'));
      // Escaped quotes are represented as ""
      expect(csv, contains('""quotes""'));
      expect(csv, contains('""Chars""'));
    });
  });

  group('Plain Text Batch Export Pipeline', () {
    test('Generates readable text blocks with headers and metadata', () {
      final textOutput = exportService.exportToPlainText(sampleRecords);

      expect(textOutput, contains('ZEROSYNC SCAN VAULT EXPORT'));
      expect(textOutput, contains('Total Records: 3'));
      expect(textOutput, contains('[#1] ID: rec-001'));
      expect(textOutput, contains('Content: https://flutter.dev/docs'));
      expect(textOutput, contains('Favorite: Yes'));
      expect(textOutput, contains('Threat : critical'));
    });
  });

  group('High-Level exportBatch Execution', () {
    test('Applies filter and formats output with metadata and generated file name', () {
      final batchResult = exportService.exportBatch(
        sampleRecords,
        format: VaultExportFormat.json,
        filter: const VaultSearchFilter(isFavoriteOnly: true),
      );

      expect(batchResult.format, equals(VaultExportFormat.json));
      expect(batchResult.recordCount, equals(1));
      expect(batchResult.byteSize, greaterThan(0));
      expect(batchResult.defaultFileName, startsWith('zerosync_export_'));
      expect(batchResult.defaultFileName, endsWith('.json'));
      expect(batchResult.toString(), contains('VaultExportResult'));
    });
  });
}
