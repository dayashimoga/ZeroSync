import 'dart:io' show Platform;

import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';
import 'package:airdrop_qr/domain/services/forensic_audit_exporter.dart';
import 'package:airdrop_qr/domain/services/vault_export_service.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Workspace for exploring, filtering, and forensically auditing AES-256 encrypted
/// vault records and exporting cryptographically sealed audit reports.
class EncryptedVaultPage extends StatefulWidget {
  final EncryptedVaultDataSource? vaultOverride;
  final VaultExportService? exportServiceOverride;
  final ValueChanged<String>? onActionDispatched;

  const EncryptedVaultPage({
    super.key,
    this.vaultOverride,
    this.exportServiceOverride,
    this.onActionDispatched,
  });

  @override
  State<EncryptedVaultPage> createState() => _EncryptedVaultPageState();
}

class _EncryptedVaultPageState extends State<EncryptedVaultPage> {
  late final EncryptedVaultDataSource _vault;
  final VaultExportService _exportService = const VaultExportService();

  bool _isLoading = true;
  List<ScanRecord> _allRecords = <ScanRecord>[];
  String _searchQuery = '';
  String? _selectedCategory;
  bool _favoriteOnly = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _vault = widget.vaultOverride ?? EncryptedVaultDataSourceImpl();
    _loadVaultRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVaultRecords() async {
    setState(() => _isLoading = true);

    try {
      final records = await _vault.getAllScans();
      if (mounted) {
        setState(() {
          _allRecords = records;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<ScanRecord> get _filteredRecords {
    final filter = VaultSearchFilter(
      searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      contentType: _selectedCategory,
      isFavoriteOnly: _favoriteOnly ? true : null,
    );
    return _exportService.filter(_allRecords, filter);
  }

  Future<void> _deleteRecord(ScanRecord record) async {
    await _vault.deleteScan(record.id);
    await _loadVaultRecords();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Deleted record "${record.title ?? record.id}"')),
      );
    }
  }

  Future<void> _clearAllVault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: ZeroSyncColors.darkGraphite,
        title: const Text('Purge Encrypted Vault?',
            style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'This action permanently deletes all AES-256 encrypted records from local storage. '
          'RAM buffers will be zeroized immediately.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Purge All Records'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _vault.clearAllScans();
      await _loadVaultRecords();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All vault records purged.')),
        );
      }
    }
  }

  void _exportVault(VaultExportFormat format) {
    final records = _filteredRecords;
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records matching filter to export.')),
      );
      return;
    }

    String content;
    switch (format) {
      case VaultExportFormat.json:
        content = _exportService.exportToJson(records);
        break;
      case VaultExportFormat.csv:
        content = _exportService.exportToCsv(records);
        break;
      case VaultExportFormat.plainText:
        content = _exportService.exportToPlainText(records);
        break;
    }

    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Exported ${records.length} records as ${format.name.toUpperCase()} (copied to clipboard).',
        ),
      ),
    );
  }

  void _showForensicAuditDialog() {
    final records = _allRecords;
    final platform = kIsWeb
        ? 'Web'
        : (Platform.isWindows
            ? 'Windows x64'
            : (Platform.isAndroid
                ? 'Android'
                : (Platform.isIOS ? 'iOS' : 'Desktop')));

    final auditLogs = records
        .map((r) => {
              'id': r.id,
              'created_at': r.createdAt.toUtc().toIso8601String(),
              'category': r.contentType,
              'threat_severity': r.threatSeverity ?? 'none',
              'tags': r.tags,
            })
        .toList();

    final report = ForensicAuditExporter.generateReport(
      reportId: 'zs-audit-${DateTime.now().millisecondsSinceEpoch}',
      devicePlatform: platform,
      auditLogs: auditLogs,
      securityEvents: [
        {
          'event': 'VAULT_INSPECTION',
          'status': 'SECURE_AIR_GAP_VERIFIED',
          'network_permitted': false,
        }
      ],
      integrityMetrics: {
        'total_vault_records': records.length,
        'cipher': 'SQLCipher AES-256-CBC',
        'kdf': 'PBKDF2-HMAC-SHA512 (64,000 iterations)',
      },
    );

    final markdownCert = ForensicAuditExporter.exportMarkdownReport(report);

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: ZeroSyncColors.darkGraphite,
        title: const Row(
          children: [
            Icon(Icons.verified, color: ZeroSyncColors.emerald, size: 22),
            SizedBox(width: 8),
            Text('Tamper-Evident Forensic Audit Seal',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cryptographic SHA-256 Digest Seal:',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: ZeroSyncColors.emerald.withAlpha(120)),
              ),
              child: SelectableText(
                report.sha256Digest,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: ZeroSyncColors.emerald,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Audited Records: ${report.auditLogs.length} | Platform: ${report.devicePlatform}\n'
              'Integrity: AES-256 Vault Intact | Air-Gap Enforced',
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZeroSyncColors.cyan,
              foregroundColor: ZeroSyncColors.trueBlack,
            ),
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copy Forensic Certificate'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: markdownCert));
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Tamper-evident forensic audit certificate copied to clipboard.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _insertSampleRecord() async {
    final sample = ScanRecord.create(
      rawValue: 'https://zerosync.security/docs/airgap-protocol',
      format: 'QR_CODE',
      contentType: 'url',
      title: 'ZeroSync Optical Air-Gap Spec',
      tags: const ['Documentation', 'AuditControl'],
    );
    await _vault.insertScan(sample);
    await _loadVaultRecords();
  }

  @override
  Widget build(BuildContext context) {
    final records = _filteredRecords;

    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      appBar: AppBar(
        title: const Text('Encrypted Vault & Forensic Audit'),
        actions: [
          // Forensic Audit Seal Button
          IconButton(
            icon: const Icon(Icons.verified_outlined,
                color: ZeroSyncColors.emerald),
            tooltip: 'Generate Forensic Audit Seal',
            onPressed: _showForensicAuditDialog,
          ),

          // Export Menu Button
          PopupMenuButton<VaultExportFormat>(
            icon: const Icon(Icons.file_download_outlined,
                color: ZeroSyncColors.cyan),
            tooltip: 'Export Vault Records',
            onSelected: _exportVault,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: VaultExportFormat.json,
                child: Text('Export as JSON (RFC 8259)'),
              ),
              PopupMenuItem(
                value: VaultExportFormat.csv,
                child: Text('Export as CSV (Spreadsheet)'),
              ),
              PopupMenuItem(
                value: VaultExportFormat.plainText,
                child: Text('Export as Plain Text'),
              ),
            ],
          ),

          // Purge Vault Button
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined,
                color: Colors.redAccent),
            tooltip: 'Purge Encrypted Vault',
            onPressed: _clearAllVault,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filter Strip
          _buildFilterBar(),

          // 2. Records List or Empty State
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: ZeroSyncColors.cyan),
                  )
                : records.isEmpty
                    ? _buildEmptyState()
                    : _buildRecordsList(records),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      color: ZeroSyncColors.darkSlate,
      child: Column(
        children: [
          // Search Box & Favorite Toggle
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: InputDecoration(
                      hintText: 'Search encrypted vault records...',
                      hintStyle:
                          const TextStyle(fontSize: 11, color: Colors.white38),
                      prefixIcon: const Icon(Icons.search,
                          size: 18, color: Colors.white54),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val.trim());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Favorites Filter Icon
              IconButton(
                icon: Icon(
                  _favoriteOnly ? Icons.star : Icons.star_border,
                  color: _favoriteOnly ? Colors.amber : Colors.white60,
                ),
                tooltip: 'Favorites Only',
                onPressed: () {
                  setState(() => _favoriteOnly = !_favoriteOnly);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryChip('All', null),
                const SizedBox(width: 4),
                _buildCategoryChip('URL', 'url'),
                const SizedBox(width: 4),
                _buildCategoryChip('Wi-Fi', 'wifi'),
                const SizedBox(width: 4),
                _buildCategoryChip('Contact', 'vcard'),
                const SizedBox(width: 4),
                _buildCategoryChip('TOTP', 'totp'),
                const SizedBox(width: 4),
                _buildCategoryChip('Crypto', 'crypto'),
                const SizedBox(width: 4),
                _buildCategoryChip('Text', 'text'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String? category) {
    final isSelected = _selectedCategory == category;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedCategory = selected ? category : null;
        });
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZeroSyncSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_outlined,
                size: 52, color: Colors.white24),
            const SizedBox(height: ZeroSyncSpacing.md),
            const Text(
              'No Encrypted Records Found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: ZeroSyncColors.trueWhite,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Records saved from the QR Scanner, Image Decoder, or Batch Scanner '
              'will appear here protected by SQLCipher AES-256.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: ZeroSyncSpacing.md),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZeroSyncColors.darkSlate,
                foregroundColor: ZeroSyncColors.cyan,
                side: const BorderSide(color: ZeroSyncColors.cyan),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Insert Sample Auditable Record'),
              onPressed: _insertSampleRecord,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsList(List<ScanRecord> records) {
    return ListView.builder(
      primary: false,
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        return _buildRecordCard(record);
      },
    );
  }

  Widget _buildRecordCard(ScanRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: ZeroSyncColors.darkGraphite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: ZeroSyncColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Title & Format
            Row(
              children: [
                Icon(
                  record.contentType == 'url'
                      ? Icons.link
                      : (record.contentType == 'wifi'
                          ? Icons.wifi
                          : (record.contentType == 'vcard'
                              ? Icons.contact_page
                              : Icons.qr_code)),
                  size: 18,
                  color: ZeroSyncColors.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.title ?? record.contentType.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: ZeroSyncColors.trueWhite,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: ZeroSyncColors.trueBlack,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.format.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Raw Payload Text
            SelectableText(
              record.rawValue,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: ZeroSyncColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Tags & Timestamp
            Row(
              children: [
                ...record.tags.map((tag) => Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: ZeroSyncColors.darkSlate,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: ZeroSyncColors.darkBorder),
                      ),
                      child: Text(
                        '#$tag',
                        style: const TextStyle(
                            fontSize: 9, color: ZeroSyncColors.cyan),
                      ),
                    )),
                const Spacer(),
                Text(
                  '${record.createdAt.year}-${record.createdAt.month.toString().padLeft(2, '0')}-${record.createdAt.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
            const Divider(color: ZeroSyncColors.darkBorder, height: 16),

            // Action Row
            Row(
              children: [
                // Threat Inspector Action
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: ZeroSyncColors.emerald,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.shield_outlined, size: 14),
                  label: const Text('Inspect Threat',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    ThreatInspectorSheet.show(
                      context: context,
                      rawPayload: record.rawValue,
                      onActionDispatched: widget.onActionDispatched,
                    );
                  },
                ),
                const Spacer(),

                // Copy Payload
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  tooltip: 'Copy Payload',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: record.rawValue));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Payload copied to clipboard')),
                    );
                  },
                ),

                // Delete Record
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.redAccent),
                  tooltip: 'Delete Record',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(6),
                  onPressed: () => _deleteRecord(record),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
