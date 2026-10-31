import 'package:airdrop_qr/domain/services/forensic_audit_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ForensicAuditExporter Specifications', () {
    late ForensicAuditReport report;

    setUp(() {
      report = ForensicAuditExporter.generateReport(
        reportId: 'AUDIT-2026-OCT-001',
        devicePlatform: 'Android 14 (Air-Gapped)',
        auditLogs: [
          {'event': 'VAULT_OPEN', 'status': 'SUCCESS'},
          {'event': 'OPTICAL_TRANSFER', 'bytes': 1024},
        ],
        securityEvents: [
          {
            'severity': 'INFO',
            'title': 'AirGap Verified',
            'details': '0 network sockets'
          },
        ],
        integrityMetrics: {
          'crc_failures': 0,
          'poisoned_frames_rejected': 0,
          'total_frames_processed': 480,
        },
        timestamp: DateTime.utc(2026, 10, 31, 14, 0, 0),
      );
    });

    test('generateReport computes valid deterministic SHA-256 digest', () {
      expect(report.reportId, equals('AUDIT-2026-OCT-001'));
      expect(report.sha256Digest, isNotEmpty);
      expect(report.sha256Digest.length, equals(64)); // 32 bytes hex
      expect(ForensicAuditExporter.verifyReportIntegrity(report), isTrue);
    });

    test('exportJson produces valid JSON representation containing digest', () {
      final json = ForensicAuditExporter.exportJson(report);
      expect(json, contains('AUDIT-2026-OCT-001'));
      expect(json, contains(report.sha256Digest));
      expect(json, contains('Air-Gapped'));
    });

    test('exportMarkdownReport generates formatted markdown certificate', () {
      final md = ForensicAuditExporter.exportMarkdownReport(report);
      expect(md,
          contains('# ZeroSync Cryptographic & Forensic Audit Certificate'));
      expect(md, contains('`AUDIT-2026-OCT-001`'));
      expect(md, contains('`${report.sha256Digest}`'));
      expect(md, contains('crc_failures'));
    });

    test('verifyReportIntegrity detects tampering', () {
      expect(ForensicAuditExporter.verifyReportIntegrity(report), isTrue);

      // Create tampered copy with modified audit logs
      final tampered = ForensicAuditReport(
        reportId: report.reportId,
        generatedAt: report.generatedAt,
        devicePlatform: report.devicePlatform,
        auditLogs: const [
          {'event': 'VAULT_OPEN', 'status': 'TAMPERED'},
        ],
        securityEvents: report.securityEvents,
        integrityMetrics: report.integrityMetrics,
        sha256Digest: report.sha256Digest, // original digest
      );

      expect(ForensicAuditExporter.verifyReportIntegrity(tampered), isFalse);
    });
  });
}
