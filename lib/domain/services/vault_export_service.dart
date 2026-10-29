import 'dart:convert';

import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';

/// Supported structured file export formats for local encrypted vault records.
enum VaultExportFormat {
  /// Structured RFC 8259 JSON array with full nested metadata.
  json,

  /// RFC 4180 compliant Comma-Separated Values table for spreadsheet software.
  csv,

  /// Clean, human-readable ASCII formatted text with metadata summaries.
  plainText,
}

/// Advanced offline search and multi-attribute filter criteria for scan records.
class VaultSearchFilter {
  /// Substring query evaluated across raw value, title, and user notes.
  final String? searchQuery;

  /// Inclusive lower bound timestamp filter.
  final DateTime? startDate;

  /// Inclusive upper bound timestamp filter.
  final DateTime? endDate;

  /// List of tag names to filter against.
  final List<String> tags;

  /// If `true`, a record must match all specified [tags]; if `false`, matching any tag qualifies.
  final bool matchAllTags;

  /// Filter by semantic content category (e.g. `url`, `vcard`, `wifi`, `crypto`).
  final String? contentType;

  /// Filter exclusively for favorite records.
  final bool? isFavoriteOnly;

  /// Filter by minimum or exact threat severity (e.g. `high`, `critical`).
  final String? threatSeverity;

  const VaultSearchFilter({
    this.searchQuery,
    this.startDate,
    this.endDate,
    this.tags = const <String>[],
    this.matchAllTags = false,
    this.contentType,
    this.isFavoriteOnly,
    this.threatSeverity,
  });

  /// Evaluates whether [record] satisfies all configured filter constraints.
  bool matches(ScanRecord record) {
    // 1. Text Search Query Filter
    if (searchQuery != null && searchQuery!.trim().isNotEmpty) {
      final String query = searchQuery!.trim().toLowerCase();
      final bool valueMatch = record.rawValue.toLowerCase().contains(query);
      final bool titleMatch = record.title?.toLowerCase().contains(query) ?? false;
      final bool notesMatch = record.notes?.toLowerCase().contains(query) ?? false;
      final bool tagMatch = record.tags.any((t) => t.toLowerCase().contains(query));

      if (!valueMatch && !titleMatch && !notesMatch && !tagMatch) {
        return false;
      }
    }

    // 2. Date Range Boundaries
    if (startDate != null && record.createdAt.isBefore(startDate!)) {
      return false;
    }
    if (endDate != null && record.createdAt.isAfter(endDate!)) {
      return false;
    }

    // 3. Favorite Filter
    if (isFavoriteOnly == true && !record.isFavorite) {
      return false;
    }

    // 4. Content Type Filter
    if (contentType != null &&
        contentType!.trim().isNotEmpty &&
        record.contentType.toLowerCase() != contentType!.trim().toLowerCase()) {
      return false;
    }

    // 5. Threat Severity Filter
    if (threatSeverity != null &&
        threatSeverity!.trim().isNotEmpty &&
        record.threatSeverity?.toLowerCase() != threatSeverity!.trim().toLowerCase()) {
      return false;
    }

    // 6. Categorization Tags Filter
    if (tags.isNotEmpty) {
      final Set<String> recordTags =
          record.tags.map((t) => t.toLowerCase()).toSet();
      final List<String> queryTags =
          tags.map((t) => t.trim().toLowerCase()).toList();

      if (matchAllTags) {
        final bool hasAll = queryTags.every((t) => recordTags.contains(t));
        if (!hasAll) return false;
      } else {
        final bool hasAny = queryTags.any((t) => recordTags.contains(t));
        if (!hasAny) return false;
      }
    }

    return true;
  }
}

/// Output payload produced by batch data export execution.
class VaultExportResult {
  /// Target serialization format.
  final VaultExportFormat format;

  /// Serialized document contents.
  final String exportedContent;

  /// Number of records serialized in the export.
  final int recordCount;

  /// Generation timestamp.
  final DateTime exportedAt;

  /// Total character length / byte size of the exported output.
  final int byteSize;

  /// Canonical suggested file name (e.g. `zerosync_export_20261029_140000.csv`).
  final String defaultFileName;

  const VaultExportResult({
    required this.format,
    required this.exportedContent,
    required this.recordCount,
    required this.exportedAt,
    required this.byteSize,
    required this.defaultFileName,
  });

  @override
  String toString() =>
      'VaultExportResult(format: ${format.name}, records: $recordCount, size: ${byteSize}B, file: "$defaultFileName")';
}

/// Domain service implementing local full-text search, multi-attribute filtering,
/// and batch export serialization for encrypted vault records.
class VaultExportService {
  const VaultExportService();

  /// Filters [records] according to the criteria defined in [filter].
  List<ScanRecord> filter(List<ScanRecord> records, VaultSearchFilter filter) {
    return records.where((record) => filter.matches(record)).toList();
  }

  /// Serializes [records] into an RFC 8259 compliant JSON document.
  String exportToJson(List<ScanRecord> records, {bool pretty = true}) {
    final List<Map<String, dynamic>> jsonList = records.map((r) {
      return <String, dynamic>{
        'id': r.id,
        'rawValue': r.rawValue,
        'format': r.format,
        'contentType': r.contentType,
        'createdAt': r.createdAt.toIso8601String(),
        'updatedAt': r.updatedAt.toIso8601String(),
        'isFavorite': r.isFavorite,
        'title': r.title,
        'notes': r.notes,
        'threatSeverity': r.threatSeverity,
        'tags': r.tags,
        if (r.rawBytes != null) 'rawBytesBase64': base64Encode(r.rawBytes!),
      };
    }).toList();

    return pretty
        ? const JsonEncoder.withIndent('  ').convert(jsonList)
        : jsonEncode(jsonList);
  }

  /// Serializes [records] into an RFC 4180 compliant CSV document.
  String exportToCsv(List<ScanRecord> records) {
    final StringBuffer buffer = StringBuffer();

    // CSV Header row
    buffer.writeln(
      'ID,Raw Value,Format,Content Type,Created At,Updated At,Favorite,Title,Notes,Threat Severity,Tags',
    );

    for (final ScanRecord record in records) {
      final List<String> fields = <String>[
        record.id,
        record.rawValue,
        record.format,
        record.contentType,
        record.createdAt.toIso8601String(),
        record.updatedAt.toIso8601String(),
        record.isFavorite ? 'true' : 'false',
        record.title ?? '',
        record.notes ?? '',
        record.threatSeverity ?? '',
        record.tags.join('; '),
      ];

      final String row = fields.map(_escapeCsvField).join(',');
      buffer.writeln(row);
    }

    return buffer.toString();
  }

  /// Serializes [records] into human-readable plain text blocks.
  String exportToPlainText(List<ScanRecord> records) {
    final StringBuffer buffer = StringBuffer();
    final String separator = '=' * 60;

    buffer.writeln('ZEROSYNC SCAN VAULT EXPORT');
    buffer.writeln('Total Records: ${records.length}');
    buffer.writeln('Exported At  : ${DateTime.now().toIso8601String()}');
    buffer.writeln(separator);
    buffer.writeln();

    for (int i = 0; i < records.length; i++) {
      final ScanRecord r = records[i];
      buffer.writeln('[#${i + 1}] ID: ${r.id}');
      buffer.writeln('Content: ${r.rawValue}');
      buffer.writeln('Format : ${r.format} (${r.contentType})');
      buffer.writeln('Date   : ${r.createdAt.toIso8601String()}');
      if (r.isFavorite) buffer.writeln('Favorite: Yes');
      if (r.title != null && r.title!.isNotEmpty) buffer.writeln('Title  : ${r.title}');
      if (r.threatSeverity != null) buffer.writeln('Threat : ${r.threatSeverity}');
      if (r.tags.isNotEmpty) buffer.writeln('Tags   : ${r.tags.join(", ")}');
      if (r.notes != null && r.notes!.isNotEmpty) buffer.writeln('Notes  : ${r.notes}');
      buffer.writeln('-' * 60);
    }

    return buffer.toString();
  }

  /// High-level entry point executing filtering and export serialization.
  VaultExportResult exportBatch(
    List<ScanRecord> records, {
    required VaultExportFormat format,
    VaultSearchFilter? filter,
    bool prettyJson = true,
  }) {
    final DateTime now = DateTime.now();
    final List<ScanRecord> workingList =
        filter != null ? this.filter(records, filter) : records;

    String content;
    String extension;

    switch (format) {
      case VaultExportFormat.json:
        content = exportToJson(workingList, pretty: prettyJson);
        extension = 'json';
      case VaultExportFormat.csv:
        content = exportToCsv(workingList);
        extension = 'csv';
      case VaultExportFormat.plainText:
        content = exportToPlainText(workingList);
        extension = 'txt';
    }

    final String timestampStr =
        '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
    final String fileName = 'zerosync_export_$timestampStr.$extension';

    return VaultExportResult(
      format: format,
      exportedContent: content,
      recordCount: workingList.length,
      exportedAt: now,
      byteSize: utf8.encode(content).length,
      defaultFileName: fileName,
    );
  }

  String _escapeCsvField(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      final String escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

