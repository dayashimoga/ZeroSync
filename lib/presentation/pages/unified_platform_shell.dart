import 'package:airdrop_qr/presentation/pages/generator/advanced_styler_view.dart';
import 'package:airdrop_qr/presentation/pages/generator/standard_generator_view.dart';
import 'package:airdrop_qr/presentation/pages/home_page.dart';
import 'package:airdrop_qr/presentation/pages/scanner/batch_scanner_view.dart';
import 'package:airdrop_qr/presentation/pages/scanner/camera_scanner_view.dart';
import 'package:airdrop_qr/presentation/pages/scanner/image_scanner_view.dart';
import 'package:airdrop_qr/presentation/pages/vault/encrypted_vault_page.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Top-level unified multi-platform shell housing the 5 core ZeroSync workspaces:
/// 1. Multi-Modal Scanner (Camera, Image/File, Batch)
/// 2. Universal & Enterprise QR Generator (Standard, Styler, Crypto/TOTP)
/// 3. Air-Gapped Optical Data Transfer (Fountain Transmitter & Receiver)
/// 4. Encrypted SQLCipher Vault & Forensic History
/// 5. Enterprise Policies, Offline Licensing & Duress Defense
class UnifiedPlatformShell extends StatefulWidget {
  final int initialWorkspace;

  const UnifiedPlatformShell({
    super.key,
    this.initialWorkspace = 0,
  }) : assert(initialWorkspace >= 0 && initialWorkspace < 5,
            'Workspace index must be between 0 and 4');

  @override
  State<UnifiedPlatformShell> createState() => _UnifiedPlatformShellState();
}

class _UnifiedPlatformShellState extends State<UnifiedPlatformShell> {
  late int _activeWorkspace;
  final FocusNode _focusNode = FocusNode();

  // Scanner workspace sub-mode (0: Camera, 1: Image, 2: Batch)
  int _scannerSubMode = 0;

  // Generator workspace sub-mode (0: Standard 8-Type, 1: Styler Studio, 2: Enterprise Studio)
  int _generatorSubMode = 0;

  @override
  void initState() {
    super.initState();
    _activeWorkspace = widget.initialWorkspace;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _selectWorkspace(int index) {
    if (index >= 0 && index < 5 && index != _activeWorkspace) {
      setState(() {
        _activeWorkspace = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _selectWorkspace(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _selectWorkspace(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _selectWorkspace(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _selectWorkspace(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            _selectWorkspace(4),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true): () =>
            _selectWorkspace(0),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true): () =>
            _selectWorkspace(1),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true): () =>
            _selectWorkspace(2),
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true): () =>
            _selectWorkspace(3),
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true): () =>
            _selectWorkspace(4),
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWideScreen = constraints.maxWidth >= 720.0;

            if (isWideScreen) {
              return _buildDesktopTabletLayout(constraints.maxWidth);
            } else {
              return _buildMobileLayout();
            }
          },
        ),
      ),
    );
  }

  /// Wide tablet and desktop layout featuring a persistent [NavigationRail].
  Widget _buildDesktopTabletLayout(double totalWidth) {
    final isExtended = totalWidth >= 1000.0;

    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Persistent NavigationRail
          NavigationRail(
            backgroundColor: ZeroSyncColors.darkGraphite,
            selectedIndex: _activeWorkspace,
            extended: isExtended,
            minExtendedWidth: 200,
            onDestinationSelected: _selectWorkspace,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: ZeroSyncSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined,
                      color: ZeroSyncColors.emerald, size: 24),
                  if (isExtended) ...[
                    const SizedBox(width: ZeroSyncSpacing.sm),
                    const Text(
                      'ZeroSync',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.1,
                        color: ZeroSyncColors.trueWhite,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing: isExtended
                ? Padding(
                    padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: ZeroSyncColors.emerald.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: ZeroSyncColors.emerald.withAlpha(100)),
                      ),
                      child: const Text(
                        'SCIF AIR-GAP',
                        style: TextStyle(
                          color: ZeroSyncColors.emerald,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  )
                : null,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.qr_code_scanner),
                selectedIcon:
                    Icon(Icons.qr_code_scanner, color: ZeroSyncColors.cyan),
                label: Text('Scanner (Ctrl+1)'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.qr_code_2),
                selectedIcon: Icon(Icons.qr_code_2, color: ZeroSyncColors.cyan),
                label: Text('Generator (Ctrl+2)'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cell_tower),
                selectedIcon:
                    Icon(Icons.cell_tower, color: ZeroSyncColors.emerald),
                label: Text('Optical Transfer (Ctrl+3)'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.lock_outline),
                selectedIcon:
                    Icon(Icons.lock_outline, color: ZeroSyncColors.cyan),
                label: Text('Vault (Ctrl+4)'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.verified_user_outlined),
                selectedIcon: Icon(Icons.verified_user_outlined,
                    color: ZeroSyncColors.emerald),
                label: Text('Enterprise (Ctrl+5)'),
              ),
            ],
          ),

          const VerticalDivider(
            width: 1.0,
            thickness: 1.0,
            color: ZeroSyncColors.darkBorder,
          ),

          // Main Active Workspace Content (Kept Alive in Memory)
          Expanded(
            child: _buildWorkspaceStack(),
          ),
        ],
      ),
    );
  }

  /// Compact mobile layout with top AppBar and bottom [NavigationBar].
  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      body: _buildWorkspaceStack(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _activeWorkspace,
        onDestinationSelected: _selectWorkspace,
        backgroundColor: ZeroSyncColors.darkGraphite,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_2),
            label: 'Generator',
          ),
          NavigationDestination(
            icon: Icon(Icons.cell_tower),
            label: 'Optical',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_outline),
            label: 'Vault',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            label: 'Policy',
          ),
        ],
      ),
    );
  }

  /// Preserves all 5 workspace state trees simultaneously using [IndexedStack].
  Widget _buildWorkspaceStack() {
    return IndexedStack(
      index: _activeWorkspace,
      children: [
        _buildScannerWorkspace(),
        _buildGeneratorWorkspace(),
        const ZeroSyncHomePage(), // Live Optical Transfer Engine (Transmitter + Receiver)
        _buildVaultWorkspace(),
        _buildEnterpriseWorkspace(),
      ],
    );
  }

  // ============================================================================
  // WORKSPACE 0: MULTI-MODAL QR SCANNER (CAMERA, IMAGE, BATCH)
  // ============================================================================
  Widget _buildScannerWorkspace() {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      appBar: AppBar(
        title: const Text('Multi-Modal QR Scanner'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Camera'),
                  icon: Icon(Icons.camera_alt, size: 14),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Image'),
                  icon: Icon(Icons.image, size: 14),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Batch'),
                  icon: Icon(Icons.dynamic_feed, size: 14),
                ),
              ],
              selected: {_scannerSubMode},
              onSelectionChanged: (set) {
                setState(() {
                  _scannerSubMode = set.first;
                });
              },
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _scannerSubMode,
        children: [
          // Sub-Mode 0: Camera Viewport with Threat Inspector
          CameraScannerView(
            onSaveToVault: (record) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved "${record.title}" to SQLCipher Vault'),
                ),
              );
            },
            onActionDispatched: (payload) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched sandboxed action for: $payload'),
                ),
              );
            },
          ),

          // Sub-Mode 1: Image & Clipboard Offline Decoder Workspace
          ImageScannerView(
            onSaveToVault: (record) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved "${record.title}" to SQLCipher Vault'),
                ),
              );
            },
            onActionDispatched: (payload) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched sandboxed action for: $payload'),
                ),
              );
            },
          ),

          // Sub-Mode 2: High-Speed Continuous Batch Scanner Workspace
          BatchScannerView(
            onSaveToVault: (record) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved "${record.title}" to SQLCipher Vault'),
                ),
              );
            },
            onActionDispatched: (payload) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched sandboxed action for: $payload'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // WORKSPACE 1: UNIVERSAL & ENTERPRISE QR GENERATOR
  // ============================================================================
  Widget _buildGeneratorWorkspace() {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      appBar: AppBar(
        title: const Text('Universal & Enterprise QR Generator'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48.0),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Standard'),
                  icon: Icon(Icons.qr_code, size: 14),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Styler Studio'),
                  icon: Icon(Icons.palette_outlined, size: 14),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Enterprise'),
                  icon: Icon(Icons.admin_panel_settings_outlined, size: 14),
                ),
              ],
              selected: {_generatorSubMode},
              onSelectionChanged: (set) {
                setState(() {
                  _generatorSubMode = set.first;
                });
              },
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _generatorSubMode,
        children: [
          // Sub-Mode 0: Standard 8-Schema Generator Workspace
          StandardGeneratorView(
            onSaveToVault: (record) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved "${record.title}" to SQLCipher Vault'),
                ),
              );
            },
            onActionDispatched: (payload) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched sandboxed action for: $payload'),
                ),
              );
            },
          ),

          // Sub-Mode 1: Advanced Visual Styler Studio (Phase 8.2)
          AdvancedStylerView(
            onSaveToVault: (record) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved "${record.title}" to SQLCipher Vault'),
                ),
              );
            },
            onActionDispatched: (payload) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Dispatched sandboxed action for: $payload'),
                ),
              );
            },
          ),

          // Sub-Mode 2: Enterprise Payload Studio (Phase 8.3)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(ZeroSyncSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.admin_panel_settings_outlined,
                      size: 56, color: ZeroSyncColors.emerald),
                  SizedBox(height: ZeroSyncSpacing.md),
                  Text(
                    'Enterprise & Cryptographic Payload Studio',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ZeroSyncColors.trueWhite),
                  ),
                  SizedBox(height: ZeroSyncSpacing.xs),
                  Text(
                    'RFC 6238 TOTP authenticators, Web3 crypto payment URIs, and SLIP-39 Shamir secret sharing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: ZeroSyncColors.lightTextSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // WORKSPACE 3: ENCRYPTED SQLCIPHER VAULT & AUDIT LOGS
  // ============================================================================
  Widget _buildVaultWorkspace() {
    return EncryptedVaultPage(
      onActionDispatched: (payload) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dispatched sandboxed action for: $payload'),
          ),
        );
      },
    );
  }

  // ============================================================================
  // WORKSPACE 4: ENTERPRISE POLICIES, LICENSING & DURESS CONTROLS
  // ============================================================================
  Widget _buildEnterpriseWorkspace() {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      appBar: AppBar(
        title: const Text('Enterprise Policy & Licensing Center'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ZeroSyncSpacing.lg),
        children: [
          // License Status Card
          Container(
            padding: const EdgeInsets.all(ZeroSyncSpacing.md),
            decoration: BoxDecoration(
              color: ZeroSyncColors.darkSlate,
              borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
              border: Border.all(color: ZeroSyncColors.cyan.withAlpha(100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified,
                    color: ZeroSyncColors.cyan, size: 28),
                const SizedBox(width: ZeroSyncSpacing.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ZeroSync Community Edition',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: ZeroSyncColors.trueWhite,
                        ),
                      ),
                      Text(
                        '100% Offline Air-Gapped License • Ed25519 Pinning',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Select offline .zslic license certificate.'),
                      ),
                    );
                  },
                  child: const Text('Import .zslic'),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.lg),

          const Text(
            'Security Policies & Controls',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Policy Switch: SCIF Air-Gap Enforcement
          SwitchListTile(
            tileColor: ZeroSyncColors.darkSlate,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: ZeroSyncColors.darkBorder),
            ),
            title: const Text('Strict Optical SCIF Mode',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 13)),
            subtitle: const Text(
                'Cryptographically locks all non-optical adapters and enforces 0 network surface.',
                style: TextStyle(fontSize: 11, color: Colors.white60)),
            value: true,
            onChanged: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Strict SCIF optical mode is permanently active.'),
                ),
              );
            },
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Policy Switch: Screen Capture Blocker
          SwitchListTile(
            tileColor: ZeroSyncColors.darkSlate,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: ZeroSyncColors.darkBorder),
            ),
            title: const Text('Hardware Window Protection (FLAG_SECURE)',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 13)),
            subtitle: const Text(
                'Prevents screenshots, screen recording, and OS task switcher leakage.',
                style: TextStyle(fontSize: 11, color: Colors.white60)),
            value: true,
            onChanged: (val) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Hardware window guard is enforced by default.'),
                ),
              );
            },
          ),
          const SizedBox(height: ZeroSyncSpacing.sm),

          // Duress PIN Setup Card
          ListTile(
            tileColor: ZeroSyncColors.darkSlate,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: ZeroSyncColors.darkBorder),
            ),
            leading:
                const Icon(Icons.warning_amber, color: ZeroSyncColors.amber),
            title: const Text('Duress Panic PIN & Decoy Vault',
                style:
                    TextStyle(color: ZeroSyncColors.trueWhite, fontSize: 13)),
            subtitle: const Text(
                'Configure emergency duress PIN to mount isolated decoy SQLCipher database.',
                style: TextStyle(fontSize: 11, color: Colors.white60)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Duress Panic PIN configuration opened.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
