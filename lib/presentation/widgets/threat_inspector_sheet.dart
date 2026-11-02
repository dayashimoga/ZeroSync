import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/domain_inspector_service.dart';
import 'package:airdrop_qr/domain/services/tracker_stripper_service.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Interactive modal sheet displaying a zero-trust threat inspection and privacy report
/// before dispatching or persisting scanned QR payloads.
class ThreatInspectorSheet extends StatelessWidget {
  final String rawPayload;
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;

  const ThreatInspectorSheet({
    super.key,
    required this.rawPayload,
    this.onSaveToVault,
    this.onActionDispatched,
  });

  /// Displays the [ThreatInspectorSheet] as a bottom sheet or responsive dialog.
  static Future<void> show({
    required BuildContext context,
    required String rawPayload,
    ValueChanged<ScanRecord>? onSaveToVault,
    ValueChanged<String>? onActionDispatched,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ZeroSyncColors.darkGraphite,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZeroSyncRadii.lg)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.85,
        child: ThreatInspectorSheet(
          rawPayload: rawPayload,
          onSaveToVault: onSaveToVault,
          onActionDispatched: onActionDispatched,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Run zero-trust domain & URL inspection
    final inspectionReport = DomainInspectorService().inspect(rawPayload);

    // 2. Run tracker stripping & privacy sanitization
    final sanitizedResult = TrackerStripperService().sanitize(rawPayload);

    return Scaffold(
      backgroundColor: ZeroSyncColors.darkGraphite,
      appBar: AppBar(
        backgroundColor: ZeroSyncColors.darkSlate,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined,
                color: ZeroSyncColors.emerald, size: 20),
            SizedBox(width: ZeroSyncSpacing.xs),
            Text(
              'Zero-Trust Pre-Flight Threat Inspector',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70),
            tooltip: 'Dismiss Inspector',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZeroSyncSpacing.md),
        children: [
          // 1. Overall Severity Rating Card
          _buildSeverityCard(inspectionReport.overallSeverity),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 2. Payload Inspection Overview
          _buildPayloadOverview(inspectionReport, sanitizedResult),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 3. Security Threats Section (if any detected)
          if (inspectionReport.detectedThreats.isNotEmpty) ...[
            _buildThreatsSection(inspectionReport.detectedThreats),
            const SizedBox(height: ZeroSyncSpacing.md),
          ],

          // 4. Privacy & Telemetry Stripping Card
          _buildPrivacyCard(sanitizedResult),
          const SizedBox(height: ZeroSyncSpacing.lg),

          // 5. Pre-Action Action Controls
          _buildActionControls(context, inspectionReport, sanitizedResult),
        ],
      ),
    );
  }

  Widget _buildSeverityCard(ThreatSeverity severity) {
    Color cardColor;
    Color textColor;
    IconData icon;
    String label;
    String description;

    switch (severity) {
      case ThreatSeverity.critical:
        cardColor = Colors.red.shade900;
        textColor = Colors.red.shade100;
        icon = Icons.gpp_bad;
        label = 'CRITICAL SECURITY THREAT DETECTED';
        description =
            'Script execution, punycode spoofing, or malicious payload pattern identified. Automatic execution is blocked.';
        break;
      case ThreatSeverity.high:
        cardColor = Colors.orange.shade900;
        textColor = Colors.orange.shade100;
        icon = Icons.warning_amber;
        label = 'HIGH RISK PAYLOAD';
        description =
            'Raw numeric IP host, privileged scheme, or deceptive subdomains detected. Proceed with extreme caution.';
        break;
      case ThreatSeverity.medium:
        cardColor = Colors.amber.shade900;
        textColor = Colors.amber.shade100;
        icon = Icons.report_problem_outlined;
        label = 'SUSPICIOUS ADVISORY';
        description =
            'Potentially unsafe parameters or non-standard TLD detected.';
        break;
      case ThreatSeverity.low:
        cardColor = Colors.blueGrey.shade800;
        textColor = Colors.cyan.shade100;
        icon = Icons.info_outline;
        label = 'INFORMATIONAL OBSERVATION';
        description =
            'Unencrypted HTTP protocol or non-standard port detected.';
        break;
      case ThreatSeverity.none:
        cardColor = Colors.green.shade900;
        textColor = Colors.green.shade100;
        icon = Icons.verified_user;
        label = 'ZERO DETECTED THREATS (CLEAN)';
        description =
            'Payload validated against known exploit heuristics. Structure conforms to standard offline schemas.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: cardColor.withAlpha(80),
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: cardColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 28),
          const SizedBox(width: ZeroSyncSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style:
                      TextStyle(color: textColor.withAlpha(220), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayloadOverview(
    DomainInspectionReport inspection,
    SanitizedUrlResult sanitized,
  ) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.data_object,
                  size: 16, color: ZeroSyncColors.cyan),
              const SizedBox(width: ZeroSyncSpacing.xs),
              const Text(
                'Payload Attributes',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.trueBlack,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  inspection.scheme.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.cyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),
          SelectableText(
            rawPayload,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: ZeroSyncColors.lightTextPrimary,
            ),
          ),
          if (inspection.host.isNotEmpty) ...[
            const Divider(color: ZeroSyncColors.darkBorder),
            Row(
              children: [
                const Text('Destination Host: ',
                    style: TextStyle(fontSize: 11, color: Colors.white60)),
                Text(inspection.host,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: ZeroSyncColors.trueWhite)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThreatsSection(List<SecurityThreat> threats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.security, size: 16, color: Colors.amber),
            const SizedBox(width: ZeroSyncSpacing.xs),
            Text(
              'Security Findings (${threats.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite,
              ),
            ),
          ],
        ),
        const SizedBox(height: ZeroSyncSpacing.xs),
        ...threats.map((threat) {
          final isCritical = threat.severity == ThreatSeverity.critical ||
              threat.severity == ThreatSeverity.high;
          final color = isCritical ? Colors.redAccent : Colors.amberAccent;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(120)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isCritical ? Icons.cancel_outlined : Icons.warning_amber,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        threat.category.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        threat.description,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                      if (threat.evidence.isNotEmpty)
                        Text(
                          'Evidence: "${threat.evidence}"',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.white38,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPrivacyCard(SanitizedUrlResult sanitized) {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.sm),
        border: Border.all(
          color: sanitized.wasModified
              ? ZeroSyncColors.emerald.withAlpha(100)
              : ZeroSyncColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sanitized.wasModified
                    ? Icons.cleaning_services_outlined
                    : Icons.check_circle_outline,
                size: 16,
                color: sanitized.wasModified
                    ? ZeroSyncColors.emerald
                    : ZeroSyncColors.cyan,
              ),
              const SizedBox(width: ZeroSyncSpacing.xs),
              Text(
                sanitized.wasModified
                    ? 'Privacy Telemetry Stripped (${sanitized.bytesSaved} Bytes Cleaned)'
                    : 'Privacy Check: No Commercial Trackers Detected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: sanitized.wasModified
                      ? ZeroSyncColors.emerald
                      : ZeroSyncColors.cyan,
                ),
              ),
            ],
          ),
          if (sanitized.wasModified) ...[
            const SizedBox(height: 6),
            Text(
              'Removed Tracking Identifiers: ${sanitized.strippedParameters.join(', ')}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                sanitized.sanitizedUrl,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: ZeroSyncColors.emerald,
                ),
              ),
            ),
          ],
          if (sanitized.isShortlink) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withAlpha(40),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link_off,
                      size: 14, color: Colors.amberAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sanitized.shortlinkWarning ??
                          'Unexpanded shortlink detected.',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.amberAccent),
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

  Widget _buildActionControls(
    BuildContext context,
    DomainInspectionReport inspection,
    SanitizedUrlResult sanitized,
  ) {
    final isBlocked = inspection.overallSeverity == ThreatSeverity.critical;
    final effectivePayload =
        sanitized.wasModified ? sanitized.sanitizedUrl : rawPayload;

    return Row(
      children: [
        // Copy Clean Payload Button
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Clean'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: effectivePayload));
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Cleaned payload copied to clipboard.')),
              );
            },
          ),
        ),
        const SizedBox(width: ZeroSyncSpacing.sm),

        // Save to Vault Button
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save to Vault'),
            onPressed: () {
              final record = ScanRecord.create(
                rawValue: effectivePayload,
                format: 'QR_CODE',
                contentType: inspection.scheme,
                title:
                    'Scan: ${inspection.host.isNotEmpty ? inspection.host : inspection.scheme}',
                tags: [
                  'Scanner',
                  if (inspection.overallSeverity != ThreatSeverity.none)
                    'Threat:${inspection.overallSeverity.name}',
                ],
              );
              onSaveToVault?.call(record);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Record persisted to encrypted vault.')),
              );
            },
          ),
        ),
        const SizedBox(width: ZeroSyncSpacing.sm),

        // Sandboxed Intent Dispatch (Only when not critically blocked)
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isBlocked ? Colors.grey.shade800 : ZeroSyncColors.emerald,
            ),
            icon: Icon(
              isBlocked ? Icons.block : Icons.launch,
              size: 16,
              color: isBlocked ? Colors.white38 : ZeroSyncColors.trueBlack,
            ),
            label: Text(
              isBlocked ? 'Blocked' : 'Dispatch',
              style: TextStyle(
                color: isBlocked ? Colors.white38 : ZeroSyncColors.trueBlack,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: isBlocked
                ? null
                : () {
                    onActionDispatched?.call(effectivePayload);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sandboxed dispatch: $effectivePayload'),
                      ),
                    );
                  },
          ),
        ),
      ],
    );
  }
}
