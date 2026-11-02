import 'package:airdrop_qr/domain/entities/enterprise_policy.dart';
import 'package:airdrop_qr/domain/entities/license_certificate.dart';
import 'package:airdrop_qr/domain/services/duress_manager_service.dart';
import 'package:airdrop_qr/domain/services/enterprise_policy_service.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';

/// Enterprise Licensing, Offline Trial, Feature Flags & Security Policy Center.
///
/// Provides a zero-trust, completely offline control interface for:
/// 1. Offline .zslic cryptographic license authentication via Ed25519 signature checks.
/// 2. 14-day offline enterprise trial activation.
/// 3. Tier capability matrix (Community, Pro, Enterprise).
/// 4. Granular feature flag toggles.
/// 5. Zero-network security policies (mandatory encryption, strict air-gap lockdown, retention).
/// 6. Duress panic guard configuration with primary and decoy PIN testing.
class EnterprisePolicyPage extends StatefulWidget {
  final EnterprisePolicyService? policyService;

  const EnterprisePolicyPage({
    super.key,
    this.policyService,
  });

  @override
  State<EnterprisePolicyPage> createState() => _EnterprisePolicyPageState();
}

class _EnterprisePolicyPageState extends State<EnterprisePolicyPage> {
  late final EnterprisePolicyService _policyService;
  late EnterprisePolicySnapshot _snapshot;

  @override
  void initState() {
    super.initState();
    _policyService = widget.policyService ?? EnterprisePolicyService();
    _refreshState();
  }

  void _refreshState() {
    setState(() {
      _snapshot = _policyService.snapshot;
    });
  }

  Color _getTierColor(LicenseTier tier) {
    switch (tier) {
      case LicenseTier.community:
        return ZeroSyncColors.cyan;
      case LicenseTier.pro:
        return const Color(0xFFFFB300); // Amber/Gold
      case LicenseTier.enterprise:
        return ZeroSyncColors.emerald;
    }
  }

  String _getTierLabel(LicenseTier tier) {
    switch (tier) {
      case LicenseTier.community:
        return 'COMMUNITY EDITION';
      case LicenseTier.pro:
        return 'PRO EDITION';
      case LicenseTier.enterprise:
        return 'ENTERPRISE EDITION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor(_snapshot.activeTier);

    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      appBar: AppBar(
        backgroundColor: ZeroSyncColors.trueBlack,
        title: const Text(
          'Enterprise Policy & Licensing Center',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: ZeroSyncColors.trueWhite,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: ZeroSyncSpacing.md),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tierColor.withAlpha(30),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: tierColor),
            ),
            child: Text(
              _getTierLabel(_snapshot.activeTier),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: tierColor,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZeroSyncSpacing.md),
        children: [
          // 1. License & Trial Status Card
          _buildLicenseStatusCard(tierColor),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 2. Offline Trial Banner (if eligible)
          if (!_snapshot.isTrialActive &&
              !_policyService.isTrialConsumed &&
              _snapshot.activeTier == LicenseTier.community) ...[
            _buildTrialActivationBanner(),
            const SizedBox(height: ZeroSyncSpacing.md),
          ],

          // 3. Security & Air-Gap Invariant Policies
          _buildSecurityPoliciesCard(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 4. Granular Feature Flags Control
          _buildFeatureFlagsCard(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 5. Tier Comparison Matrix
          _buildTierComparisonMatrix(),
          const SizedBox(height: ZeroSyncSpacing.md),

          // 6. Duress Panic Decoy Vault Configuration
          _buildDuressConfigurationCard(),
          const SizedBox(height: ZeroSyncSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildLicenseStatusCard(Color tierColor) {
    final cert = _snapshot.certificate;

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: tierColor.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user, color: tierColor, size: 28),
              const SizedBox(width: ZeroSyncSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getTierLabel(_snapshot.activeTier),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: tierColor,
                      ),
                    ),
                    Text(
                      cert != null
                          ? 'Licensed to: ${cert.payload.licensedTo}'
                          : (_snapshot.isTrialActive
                              ? 'Active 14-Day Offline Trial (Expires: ${_formatDate(_snapshot.trialExpiresAt!)})'
                              : '100% Offline Air-Gapped License • Ed25519 Root Pinning'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: ZeroSyncColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (cert != null) ...[
            const Divider(color: ZeroSyncColors.darkBorder, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'License ID: ${cert.payload.id}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  cert.payload.expiresAt != null
                      ? 'Valid until: ${_formatDate(cert.payload.expiresAt!)}'
                      : 'Lifetime Perpetual License',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
          const SizedBox(height: ZeroSyncSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload_outlined, size: 16),
                  label: const Text('Import .zslic License'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZeroSyncColors.cyan,
                    side: const BorderSide(color: ZeroSyncColors.cyan),
                  ),
                  onPressed: _showImportLicenseDialog,
                ),
              ),
              if (_snapshot.certificate != null) ...[
                const SizedBox(width: ZeroSyncSpacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.redAccent),
                  label: const Text('Revoke',
                      style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  onPressed: () {
                    _policyService.revokeLicense();
                    _refreshState();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'License revoked. Restored to Community Edition.'),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrialActivationBanner() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.emerald.withAlpha(20),
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.emerald),
      ),
      child: Row(
        children: [
          const Icon(Icons.offline_bolt,
              color: ZeroSyncColors.emerald, size: 28),
          const SizedBox(width: ZeroSyncSpacing.md),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '14-Day Offline Enterprise Trial',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.emerald,
                  ),
                ),
                Text(
                  'Instantly unlock 3x RGB multiplexing, SLIP-39, and forensic export without internet access.',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZeroSyncColors.emerald,
              foregroundColor: ZeroSyncColors.trueBlack,
            ),
            onPressed: () {
              final ok = _policyService.activateOfflineTrial();
              _refreshState();
              if (ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '14-Day Offline Enterprise Trial successfully activated!'),
                  ),
                );
              }
            },
            child: const Text('Activate Trial'),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityPoliciesCard() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Security Policies & Air-Gap Invariants',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.xs),
          const Text(
            'Hardened cryptographic rules enforced across all transfer and storage operations.',
            style: TextStyle(
                fontSize: 11, color: ZeroSyncColors.lightTextSecondary),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Mandatory Encryption Switch
          SwitchListTile(
            tileColor: ZeroSyncColors.trueBlack,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text('Mandatory Payload Encryption',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 13)),
            subtitle: const Text(
              'Enforces XChaCha20-Poly1305 encryption on all generated payloads and transfers.',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
            value: _snapshot.mandatoryEncryption,
            activeThumbColor: ZeroSyncColors.emerald,
            onChanged: (val) {
              _policyService.setMandatoryEncryption(val);
              _refreshState();
            },
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Strict Air-Gap Lockdown Switch
          SwitchListTile(
            tileColor: ZeroSyncColors.trueBlack,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text('Strict Air-Gap SCIF Lockdown',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 13)),
            subtitle: const Text(
              'Forbids unverified external file export; optical pipeline operates with 0 network permissions.',
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
            value: _snapshot.strictAirgapLockdown,
            activeThumbColor: ZeroSyncColors.cyan,
            onChanged: (val) {
              _policyService.setStrictAirgapLockdown(val);
              _refreshState();
            },
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Audit Log Retention Dropdown
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: ZeroSyncSpacing.md, vertical: ZeroSyncSpacing.sm),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Forensic Log Retention',
                          style: TextStyle(
                              color: ZeroSyncColors.trueWhite, fontSize: 13)),
                      Text(
                        'Automatic scrubbing interval for encrypted vault history.',
                        style: TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<AuditRetentionPolicy>(
                  value: _snapshot.retentionPolicy,
                  dropdownColor: ZeroSyncColors.darkGraphite,
                  style:
                      const TextStyle(color: ZeroSyncColors.cyan, fontSize: 12),
                  underline: const SizedBox(),
                  items: AuditRetentionPolicy.values.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(p.label),
                    );
                  }).toList(),
                  onChanged: (newPolicy) {
                    if (newPolicy != null) {
                      _policyService.setRetentionPolicy(newPolicy);
                      _refreshState();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Max Optical Transfer Capacity indicator
          Container(
            padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max Optical Transfer Size:',
                    style: TextStyle(
                        fontSize: 12,
                        color: ZeroSyncColors.lightTextSecondary)),
                Text(
                  '${_snapshot.maxOpticalTransferMb} MB per session',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.emerald,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureFlagsCard() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Granular Feature Flags',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.xs),
          const Text(
            'Toggle individual application modules on or off within your entitlement tier.',
            style: TextStyle(
                fontSize: 11, color: ZeroSyncColors.lightTextSecondary),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          ...EnterprisePolicyService.featureCatalog.map((gate) {
            final isToggled = _policyService.getFeatureToggle(gate.featureKey);
            final tierSufficient =
                _isTierSufficient(_snapshot.activeTier, gate.minimumTier);

            return Padding(
              padding: const EdgeInsets.only(bottom: ZeroSyncSpacing.xs),
              child: SwitchListTile(
                tileColor: ZeroSyncColors.trueBlack,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                title: Row(
                  children: [
                    Text(gate.title,
                        style: TextStyle(
                          color: tierSufficient
                              ? ZeroSyncColors.trueWhite
                              : Colors.white38,
                          fontSize: 13,
                        )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: _getTierColor(gate.minimumTier).withAlpha(30),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        gate.minimumTier.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: _getTierColor(gate.minimumTier),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  gate.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: tierSufficient ? Colors.white60 : Colors.white24,
                  ),
                ),
                value: isToggled && tierSufficient,
                activeThumbColor: ZeroSyncColors.cyan,
                onChanged: tierSufficient
                    ? (val) {
                        _policyService.setFeatureToggle(gate.featureKey, val);
                        _refreshState();
                      }
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  bool _isTierSufficient(LicenseTier current, LicenseTier required) {
    const hierarchy = {
      LicenseTier.community: 1,
      LicenseTier.pro: 2,
      LicenseTier.enterprise: 3,
    };
    final currentLevel = hierarchy[current] ?? 1;
    final requiredLevel = hierarchy[required] ?? 1;
    return currentLevel >= requiredLevel;
  }

  Widget _buildTierComparisonMatrix() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tier Capability Comparison',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(ZeroSyncColors.trueBlack),
              columns: const [
                DataColumn(
                    label: Text('Capability',
                        style: TextStyle(
                            color: ZeroSyncColors.trueWhite,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Community',
                        style: TextStyle(
                            color: ZeroSyncColors.cyan,
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Pro',
                        style: TextStyle(
                            color: Color(0xFFFFB300),
                            fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('Enterprise',
                        style: TextStyle(
                            color: ZeroSyncColors.emerald,
                            fontWeight: FontWeight.bold))),
              ],
              rows: const [
                DataRow(cells: [
                  DataCell(Text('Camera & Image Scanner',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Universal QR Generator (8 Types)',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Batch Continuous Scanner',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Advanced Styler & Vector PDF/SVG',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Encrypted SQLCipher AES-256 Vault',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Enterprise TOTP / Web3 / SLIP-39',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('3x RGB Spectral Multiplexing',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Duress Panic Decoy Database',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.close, color: Colors.white30, size: 16)),
                  DataCell(Icon(Icons.check,
                      color: ZeroSyncColors.emerald, size: 16)),
                ]),
                DataRow(cells: [
                  DataCell(Text('Optical Payload Limit',
                      style: TextStyle(color: Colors.white70))),
                  DataCell(Text('10 MB',
                      style:
                          TextStyle(color: ZeroSyncColors.cyan, fontSize: 11))),
                  DataCell(Text('50 MB',
                      style:
                          TextStyle(color: Color(0xFFFFB300), fontSize: 11))),
                  DataCell(Text('500 MB',
                      style: TextStyle(
                          color: ZeroSyncColors.emerald, fontSize: 11))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDuressConfigurationCard() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkSlate,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: ZeroSyncColors.cyan, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Duress Panic Guard & Decoy Mode',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _snapshot.isDuressConfigured
                      ? ZeroSyncColors.emerald.withAlpha(30)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _snapshot.isDuressConfigured
                      ? 'CONFIGURED'
                      : 'NOT CONFIGURED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _snapshot.isDuressConfigured
                        ? ZeroSyncColors.emerald
                        : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Under physical coercion, entering the Panic PIN mounts a secondary decoy vault and scrubs real keys from RAM.',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          if (_snapshot.isDuressActive) ...[
            const SizedBox(height: ZeroSyncSpacing.sm),
            Container(
              padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.redAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'DECOY DURESS MODE CURRENTLY ACTIVE. Real cryptographic keys have been zeroized.',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: ZeroSyncSpacing.md),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.password, size: 16),
                  label: Text(_snapshot.isDuressConfigured
                      ? 'Update Duress PINs'
                      : 'Configure Duress PINs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZeroSyncColors.cyan,
                    foregroundColor: ZeroSyncColors.trueBlack,
                  ),
                  onPressed: _showDuressSetupDialog,
                ),
              ),
              if (_snapshot.isDuressConfigured) ...[
                const SizedBox(width: ZeroSyncSpacing.sm),
                OutlinedButton.icon(
                  icon: const Icon(Icons.pin, size: 16),
                  label: const Text('Test PIN'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZeroSyncColors.cyan,
                    side: const BorderSide(color: ZeroSyncColors.cyan),
                  ),
                  onPressed: _showTestPinDialog,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showImportLicenseDialog() {
    final textController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: ZeroSyncColors.darkGraphite,
          title: const Text('Import .zslic License',
              style: TextStyle(color: ZeroSyncColors.trueWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the base64 or JSON .zslic cryptographic license payload.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: ZeroSyncSpacing.md),
              TextField(
                controller: textController,
                maxLines: 5,
                style: const TextStyle(
                  color: ZeroSyncColors.trueWhite,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'zerosync:lic:v1:...',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: ZeroSyncColors.trueBlack,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: ZeroSyncColors.darkBorder),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZeroSyncColors.cyan,
                foregroundColor: ZeroSyncColors.trueBlack,
              ),
              onPressed: () async {
                final input = textController.text.trim();
                if (input.isEmpty) return;
                Navigator.of(dialogCtx).pop();

                final result = await _policyService.installLicense(input);
                _refreshState();

                if (!mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                if (result.isValid) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                          'License authenticated! Upgraded to ${_getTierLabel(_snapshot.activeTier)}.'),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(
                          'License verification failed: ${result.failureReason ?? 'Invalid cryptographic signature'}'),
                    ),
                  );
                }
              },
              child: const Text('Verify & Install'),
            ),
          ],
        );
      },
    );
  }

  void _showDuressSetupDialog() {
    final primaryController = TextEditingController();
    final duressController = TextEditingController();
    bool autoScrub = true;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: ZeroSyncColors.darkGraphite,
              title: const Text('Configure Duress Panic PINs',
                  style: TextStyle(color: ZeroSyncColors.trueWhite)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Set two distinct PINs: your standard PIN for legitimate vault access, and a Panic PIN to trigger a plausible decoy database.',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(height: ZeroSyncSpacing.md),
                    TextField(
                      controller: primaryController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: ZeroSyncColors.trueWhite),
                      decoration: const InputDecoration(
                        labelText: 'Primary Vault PIN (e.g. 1234)',
                        labelStyle: TextStyle(color: ZeroSyncColors.cyan),
                        filled: true,
                        fillColor: ZeroSyncColors.trueBlack,
                      ),
                    ),
                    const SizedBox(height: ZeroSyncSpacing.sm),
                    TextField(
                      controller: duressController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(color: ZeroSyncColors.trueWhite),
                      decoration: const InputDecoration(
                        labelText: 'Panic Duress PIN (e.g. 9999)',
                        labelStyle: TextStyle(color: Colors.redAccent),
                        filled: true,
                        fillColor: ZeroSyncColors.trueBlack,
                      ),
                    ),
                    const SizedBox(height: ZeroSyncSpacing.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                          'Auto-scrub real key from RAM on duress',
                          style: TextStyle(
                              color: ZeroSyncColors.trueWhite, fontSize: 11)),
                      value: autoScrub,
                      activeColor: Colors.redAccent,
                      onChanged: (val) {
                        setDialogState(() {
                          autoScrub = val ?? true;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ZeroSyncColors.cyan,
                    foregroundColor: ZeroSyncColors.trueBlack,
                  ),
                  onPressed: () {
                    final p = primaryController.text.trim();
                    final d = duressController.text.trim();
                    if (p.isEmpty || d.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Both PINs must be specified.')),
                      );
                      return;
                    }
                    if (p == d) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Panic PIN must differ from Primary PIN.')),
                      );
                      return;
                    }

                    _policyService.configureDuressPins(
                      primaryPin: p,
                      duressPin: d,
                      autoScrubRealKeyOnDuress: autoScrub,
                    );
                    Navigator.of(dialogCtx).pop();
                    _refreshState();
                    final messenger = ScaffoldMessenger.of(context);
                    messenger.clearSnackBars();
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Duress security configuration saved.'),
                      ),
                    );
                  },
                  child: const Text('Save PINs'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTestPinDialog() {
    final pinController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: ZeroSyncColors.darkGraphite,
          title: const Text('Test PIN Evaluation',
              style: TextStyle(color: ZeroSyncColors.trueWhite)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter either Primary or Duress PIN to test evaluation logic.',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: ZeroSyncSpacing.md),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                style: const TextStyle(color: ZeroSyncColors.trueWhite),
                decoration: const InputDecoration(
                  labelText: 'Enter PIN to evaluate',
                  labelStyle: TextStyle(color: ZeroSyncColors.cyan),
                  filled: true,
                  fillColor: ZeroSyncColors.trueBlack,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: ZeroSyncColors.cyan,
                foregroundColor: ZeroSyncColors.trueBlack,
              ),
              onPressed: () {
                final pin = pinController.text.trim();
                Navigator.of(dialogCtx).pop();
                final result = _policyService.evaluateDuressPin(pin);
                _refreshState();

                String message;
                Color snackColor;
                switch (result) {
                  case PinAuthResult.primaryAccess:
                    message = 'Primary Access Granted: Real vault unlocked.';
                    snackColor = ZeroSyncColors.emerald;
                    break;
                  case PinAuthResult.duressPanicTriggered:
                    message =
                        'DURESS PANIC TRIGGERED: Decoy database mounted. Keys wiped.';
                    snackColor = Colors.redAccent;
                    break;
                  case PinAuthResult.invalidPin:
                    message = 'Authentication Failed: Invalid PIN.';
                    snackColor = Colors.orangeAccent;
                    break;
                }

                final messenger = ScaffoldMessenger.of(context);
                messenger.clearSnackBars();
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: snackColor,
                    content: Text(message),
                  ),
                );
              },
              child: const Text('Evaluate PIN'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
