import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// A tamper-evident forensic security and compliance audit report.
class ForensicAuditReport extends Equatable {
  final String reportId;
  final DateTime generatedAt;
  final String devicePlatform;
  final List<Map<String, dynamic>> auditLogs;
  final List<Map<String, dynamic>> securityEvents;
  final Map<String, dynamic> integrityMetrics;
  final String sha256Digest;

  const ForensicAuditReport({
    required this.reportId,
    required this.generatedAt,
    required this.devicePlatform,
    required this.auditLogs,
    required this.securityEvents,
    required this.integrityMetrics,
    required this.sha256Digest,
  });

  Map<String, dynamic> toCanonicalMap() => {
        'report_id': reportId,
        'generated_at': generatedAt.toUtc().toIso8601String(),
        'platform': devicePlatform,
        'audit_logs': auditLogs,
        'security_events': securityEvents,
        'integrity_metrics': integrityMetrics,
      };

  @override
  List<Object?> get props => [
        reportId,
        generatedAt,
        devicePlatform,
        auditLogs,
        securityEvents,
        integrityMetrics,
        sha256Digest,
      ];
}

/// Service exporting verifiable, tamper-evident security audit reports and compliance digests.
class ForensicAuditExporter {
  /// Compiles a [ForensicAuditReport] with an embedded SHA-256 integrity seal.
  static ForensicAuditReport generateReport({
    required String reportId,
    required String devicePlatform,
    required List<Map<String, dynamic>> auditLogs,
    required List<Map<String, dynamic>> securityEvents,
    required Map<String, dynamic> integrityMetrics,
    DateTime? timestamp,
  }) {
    final now = (timestamp ?? DateTime.now()).toUtc();
    final canonicalMap = {
      'report_id': reportId,
      'generated_at': now.toIso8601String(),
      'platform': devicePlatform,
      'audit_logs': auditLogs,
      'security_events': securityEvents,
      'integrity_metrics': integrityMetrics,
    };

    final canonicalJson = jsonEncode(canonicalMap);
    final digest = sha256.convert(utf8.encode(canonicalJson)).toString();

    return ForensicAuditReport(
      reportId: reportId,
      generatedAt: now,
      devicePlatform: devicePlatform,
      auditLogs: auditLogs,
      securityEvents: securityEvents,
      integrityMetrics: integrityMetrics,
      sha256Digest: digest,
    );
  }

  /// Exports report as formatted RFC 8259 JSON string with signature.
  static String exportJson(ForensicAuditReport report) {
    final map = report.toCanonicalMap();
    map['sha256_digest'] = report.sha256Digest;
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Exports report as human-readable Markdown forensic certificate.
  static String exportMarkdownReport(ForensicAuditReport report) {
    final buffer = StringBuffer();
    buffer.writeln('# ZeroSync Cryptographic & Forensic Audit Certificate');
    buffer.writeln();
    buffer.writeln('- **Report Identifier:** `${report.reportId}`');
    buffer.writeln(
        '- **Timestamp (UTC):** ${report.generatedAt.toIso8601String()}');
    buffer.writeln('- **Host Platform:** ${report.devicePlatform}');
    buffer.writeln(
        '- **Cryptographic Seal (SHA-256):** `${report.sha256Digest}`');
    buffer.writeln();
    buffer.writeln('## 1. System Integrity Metrics');
    report.integrityMetrics.forEach((k, v) {
      buffer.writeln('- **$k:** $v');
    });
    buffer.writeln();
    buffer.writeln('## 2. Security Incidents & Threat Events');
    if (report.securityEvents.isEmpty) {
      buffer
          .writeln('_Zero security incidents or duress violations recorded._');
    } else {
      for (final event in report.securityEvents) {
        buffer.writeln(
            '- [${event['severity'] ?? 'INFO'}] ${event['title'] ?? 'Event'}: ${event['details'] ?? ''}');
      }
    }
    buffer.writeln();
    buffer.writeln('## 3. Optical Ingestion Audit Logs');
    buffer.writeln('Total log entries recorded: ${report.auditLogs.length}');

    return buffer.toString();
  }

  /// Verifies that a [ForensicAuditReport] has not been altered or tampered with.
  static bool verifyReportIntegrity(ForensicAuditReport report) {
    final canonicalMap = report.toCanonicalMap();
    final canonicalJson = jsonEncode(canonicalMap);
    final calculatedDigest =
        sha256.convert(utf8.encode(canonicalJson)).toString();
    return calculatedDigest == report.sha256Digest;
  }
}
