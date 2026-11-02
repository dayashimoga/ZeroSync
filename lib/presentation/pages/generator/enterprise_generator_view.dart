import 'dart:convert';

import 'package:airdrop_qr/domain/entities/crypto_auth_payload.dart';
import 'package:airdrop_qr/domain/entities/scan_record.dart';
import 'package:airdrop_qr/domain/services/crypto_auth_serializer_service.dart';
import 'package:airdrop_qr/domain/services/payload_encryption_service.dart';
import 'package:airdrop_qr/domain/services/slip39_secret_sharer.dart';
import 'package:airdrop_qr/presentation/theme/zerosync_design_tokens.dart';
import 'package:airdrop_qr/presentation/widgets/threat_inspector_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Supported Enterprise Schema Modes.
enum EnterpriseSchemaType {
  totp('TOTP Authenticator', Icons.lock_clock),
  web3('Web3 Crypto Payment', Icons.currency_bitcoin),
  slip39('SLIP-39 Shamir Deck', Icons.pie_chart_outline),
  encrypted('XChaCha20 Envelope', Icons.security);

  final String label;
  final IconData icon;
  const EnterpriseSchemaType(this.label, this.icon);
}

/// Supported Cryptocurrencies in Web3 Mode.
enum CryptoCurrency {
  bitcoin('Bitcoin (BIP-21)'),
  ethereum('Ethereum (EIP-681)'),
  solana('Solana Pay');

  final String label;
  const CryptoCurrency(this.label);
}

/// Workspace for enterprise-grade cryptographic QR payload authoring:
/// - RFC 6238 TOTP Authenticator Keys (Google Authenticator, Aegis, YubiKey)
/// - Web3 Payment URIs (Bitcoin BIP-21, Ethereum EIP-681, Solana Pay)
/// - SLIP-39 Shamir Secret Sharing M-of-N threshold multi-share recovery decks
/// - XChaCha20-Poly1305 + Argon2id encrypted optical binary envelopes
class EnterpriseGeneratorView extends StatefulWidget {
  final ValueChanged<ScanRecord>? onSaveToVault;
  final ValueChanged<String>? onActionDispatched;
  final PayloadEncryptionService? encryptionServiceOverride;

  const EnterpriseGeneratorView({
    super.key,
    this.onSaveToVault,
    this.onActionDispatched,
    this.encryptionServiceOverride,
  });

  @override
  State<EnterpriseGeneratorView> createState() =>
      _EnterpriseGeneratorViewState();
}

class _EnterpriseGeneratorViewState extends State<EnterpriseGeneratorView> {
  final CryptoAuthSerializerService _cryptoSerializer =
      CryptoAuthSerializerService();
  late final PayloadEncryptionService _encryptionService;

  EnterpriseSchemaType _activeSchema = EnterpriseSchemaType.totp;
  CryptoCurrency _activeCrypto = CryptoCurrency.bitcoin;

  // TOTP Controllers
  final TextEditingController _totpAccountController =
      TextEditingController(text: 'sec-admin@zerosync.corp');
  final TextEditingController _totpSecretController =
      TextEditingController(text: 'JBSWY3DPEHPK3PXP');
  final TextEditingController _totpIssuerController =
      TextEditingController(text: 'ZeroSync Defense');
  TotpAlgorithm _totpAlgorithm = TotpAlgorithm.sha1;
  int _totpDigits = 6;
  int _totpPeriod = 30;

  // Web3 Bitcoin Controllers
  final TextEditingController _btcInfoAddressController =
      TextEditingController(text: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq');
  final TextEditingController _btcAmountController =
      TextEditingController(text: '0.05');
  final TextEditingController _btcLabelController =
      TextEditingController(text: 'Cold Storage Vault Fund');
  final TextEditingController _btcMessageController =
      TextEditingController(text: 'ZeroSync Optical Rebalance');

  // Web3 Ethereum Controllers
  final TextEditingController _ethAddressController =
      TextEditingController(text: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F');
  final TextEditingController _ethValueController =
      TextEditingController(text: '1.25');
  final TextEditingController _ethChainIdController =
      TextEditingController(text: '1');

  // Web3 Solana Controllers
  final TextEditingController _solRecipientController = TextEditingController(
      text: '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU');
  final TextEditingController _solAmountController =
      TextEditingController(text: '10.5');
  final TextEditingController _solLabelController =
      TextEditingController(text: 'Treasury Cold Reserve');

  // SLIP-39 Shamir Controllers
  final TextEditingController _slip39SecretController = TextEditingController(
      text: 'shield-alpha-bravo-tango-7782-classified-core-recovery-key');
  int _slip39Threshold = 2;
  int _slip39TotalShares = 3;
  List<Slip39Share> _generatedShares = [];
  int _currentShareIndex = 0;

  // Encrypted Payload Controllers
  final TextEditingController _encPlaintextController = TextEditingController(
      text: 'CLASSIFIED_DEFENSE_DIRECTIVE_ZEROSYNC_AIRGAP_TRANSPORT_OK');
  final TextEditingController _encPassphraseController =
      TextEditingController(text: 'HardenedAirGapPassphrase99!');
  bool _obscurePassphrase = true;
  bool _isEncrypting = false;
  EncryptedPayloadEnvelope? _encryptedEnvelope;

  String _computedPayload = '';
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _encryptionService = widget.encryptionServiceOverride ??
        PayloadEncryptionService(
          kdfMemory: 4 * 1024,
          kdfIterations: 1,
        );
    _recomputeActivePayload();
  }

  @override
  void dispose() {
    _totpAccountController.dispose();
    _totpSecretController.dispose();
    _totpIssuerController.dispose();
    _btcInfoAddressController.dispose();
    _btcAmountController.dispose();
    _btcLabelController.dispose();
    _btcMessageController.dispose();
    _ethAddressController.dispose();
    _ethValueController.dispose();
    _ethChainIdController.dispose();
    _solRecipientController.dispose();
    _solAmountController.dispose();
    _solLabelController.dispose();
    _slip39SecretController.dispose();
    _encPlaintextController.dispose();
    _encPassphraseController.dispose();
    super.dispose();
  }

  void _recomputeActivePayload() {
    setState(() {
      _validationError = null;
      try {
        switch (_activeSchema) {
          case EnterpriseSchemaType.totp:
            final payload = TotpPayload(
              secret: _totpSecretController.text.trim(),
              accountName: _totpAccountController.text.trim(),
              issuer: _totpIssuerController.text.trim().isEmpty
                  ? null
                  : _totpIssuerController.text.trim(),
              algorithm: _totpAlgorithm,
              digits: _totpDigits,
              period: _totpPeriod,
            );
            _computedPayload = _cryptoSerializer.serializeTotp(payload);
            break;

          case EnterpriseSchemaType.web3:
            _computedPayload = _serializeActiveCrypto();
            break;

          case EnterpriseSchemaType.slip39:
            if (_generatedShares.isEmpty) {
              _generateShamirShares();
            }
            if (_generatedShares.isNotEmpty &&
                _currentShareIndex < _generatedShares.length) {
              final share = _generatedShares[_currentShareIndex];
              _computedPayload =
                  'slip39://${share.identifier.toRadixString(16).padLeft(4, '0')}/${share.index}?T=${share.threshold}&N=${share.totalShares}&D=${base64UrlEncode(share.data)}';
            } else {
              _computedPayload = 'slip39://uninitialized';
            }
            break;

          case EnterpriseSchemaType.encrypted:
            if (_encryptedEnvelope != null) {
              _computedPayload =
                  'ze://${base64UrlEncode(_encryptedEnvelope!.toWireBytes())}';
            } else {
              _computedPayload =
                  'ze://unencrypted?prompt=tap_encrypt_button_below';
            }
            break;
        }
      } catch (e) {
        _validationError = e.toString().replaceAll('Exception: ', '');
        _computedPayload = 'error://invalid_payload';
      }
    });
  }

  String _serializeActiveCrypto() {
    switch (_activeCrypto) {
      case CryptoCurrency.bitcoin:
        final btc = BitcoinPaymentPayload(
          address: _btcInfoAddressController.text.trim(),
          amount: double.tryParse(_btcAmountController.text.trim()),
          label: _btcLabelController.text.trim().isEmpty
              ? null
              : _btcLabelController.text.trim(),
          message: _btcMessageController.text.trim().isEmpty
              ? null
              : _btcMessageController.text.trim(),
        );
        return _cryptoSerializer.serializeBitcoin(btc);

      case CryptoCurrency.ethereum:
        final eth = EthereumPaymentPayload(
          address: _ethAddressController.text.trim(),
          valueEth: double.tryParse(_ethValueController.text.trim()),
          chainId: int.tryParse(_ethChainIdController.text.trim()) ?? 1,
        );
        return _cryptoSerializer.serializeEthereum(eth);

      case CryptoCurrency.solana:
        final sol = SolanaPaymentPayload(
          recipient: _solRecipientController.text.trim(),
          amount: double.tryParse(_solAmountController.text.trim()),
          label: _solLabelController.text.trim().isEmpty
              ? null
              : _solLabelController.text.trim(),
        );
        return _cryptoSerializer.serializeSolana(sol);
    }
  }

  void _generateShamirShares() {
    final secretText = _slip39SecretController.text.trim();
    if (secretText.isEmpty) {
      setState(() => _validationError = 'Secret string cannot be empty');
      return;
    }
    final secretBytes = Uint8List.fromList(utf8.encode(secretText));

    final shares = Slip39SecretSharer.splitSecret(
      secret: secretBytes,
      threshold: _slip39Threshold,
      totalShares: _slip39TotalShares,
    );

    setState(() {
      _generatedShares = shares;
      _currentShareIndex = 0;
      _recomputeActivePayload();
    });
  }

  Future<void> _executePayloadEncryption() async {
    final plaintext = _encPlaintextController.text.trim();
    final pass = _encPassphraseController.text;

    if (plaintext.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plaintext payload cannot be empty.')),
      );
      return;
    }
    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passphrase cannot be empty.')),
      );
      return;
    }

    setState(() => _isEncrypting = true);

    try {
      final envelope = await _encryptionService.encryptWithPassphrase(
        plaintext: Uint8List.fromList(utf8.encode(plaintext)),
        passphrase: pass,
      );

      setState(() {
        _encryptedEnvelope = envelope;
        _isEncrypting = false;
        _recomputeActivePayload();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Payload encrypted (${envelope.ciphertext.length}B ciphertext, 16B MAC, 24B nonce).',
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isEncrypting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Encryption failed: $e')),
        );
      }
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _computedPayload));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enterprise payload copied to clipboard.'),
      ),
    );
  }

  void _saveToVault() {
    final record = ScanRecord.create(
      rawValue: _computedPayload,
      format: 'QR_CODE',
      contentType: 'ENTERPRISE_${_activeSchema.name.toUpperCase()}',
      title: 'Enterprise ${_activeSchema.label}',
      tags: [
        'Enterprise',
        _activeSchema.name,
        if (_activeSchema == EnterpriseSchemaType.web3) _activeCrypto.name,
      ],
    );

    widget.onSaveToVault?.call(record);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${record.title}" to SQLCipher vault.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZeroSyncColors.trueBlack,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: ListView(
                    primary: false,
                    padding: const EdgeInsets.all(ZeroSyncSpacing.md),
                    children: _buildControlsList(),
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  color: ZeroSyncColors.darkBorder,
                ),
                Expanded(
                  flex: 4,
                  child: ListView(
                    primary: false,
                    padding: const EdgeInsets.all(ZeroSyncSpacing.md),
                    children: [
                      _buildPreviewCard(),
                    ],
                  ),
                ),
              ],
            );
          } else {
            return ListView(
              primary: false,
              padding: const EdgeInsets.all(ZeroSyncSpacing.md),
              children: [
                ..._buildControlsList(),
                const SizedBox(height: ZeroSyncSpacing.lg),
                _buildPreviewCard(),
              ],
            );
          }
        },
      ),
    );
  }

  List<Widget> _buildControlsList() {
    return [
      _buildSchemaSelector(),
      const SizedBox(height: ZeroSyncSpacing.md),
      _buildActiveSchemaForm(),
    ];
  }

  Widget _buildSchemaSelector() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.sm),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enterprise Cryptographic Schema',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ZeroSyncColors.trueWhite,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: EnterpriseSchemaType.values.map((schema) {
              final isSelected = _activeSchema == schema;
              return ChoiceChip(
                avatar: Icon(
                  schema.icon,
                  size: 14,
                  color: isSelected ? ZeroSyncColors.trueBlack : Colors.white70,
                ),
                label: Text(
                  schema.label,
                  style: const TextStyle(fontSize: 11),
                ),
                selected: isSelected,
                selectedColor: ZeroSyncColors.emerald,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _activeSchema = schema;
                      _recomputeActivePayload();
                    });
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSchemaForm() {
    switch (_activeSchema) {
      case EnterpriseSchemaType.totp:
        return _buildTotpForm();
      case EnterpriseSchemaType.web3:
        return _buildWeb3Form();
      case EnterpriseSchemaType.slip39:
        return _buildSlip39Form();
      case EnterpriseSchemaType.encrypted:
        return _buildEncryptedForm();
    }
  }

  Widget _buildTotpForm() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_clock, size: 16, color: ZeroSyncColors.cyan),
              SizedBox(width: 8),
              Text(
                'RFC 6238 TOTP Authenticator Provisioning',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: ZeroSyncColors.trueWhite,
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          TextField(
            controller: _totpAccountController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Account / User Identifier',
              hintText: 'e.g. user@organization.com',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _recomputeActivePayload(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _totpSecretController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Shared Secret Key (Base32 RFC 4648)',
              hintText: 'e.g. JBSWY3DPEHPK3PXP',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _recomputeActivePayload(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _totpIssuerController,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Issuer / Organization (Optional)',
              hintText: 'e.g. ZeroSync Secure Network',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _recomputeActivePayload(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TotpAlgorithm>(
                  initialValue: _totpAlgorithm,
                  dropdownColor: ZeroSyncColors.darkGraphite,
                  style: const TextStyle(
                      fontSize: 12, color: ZeroSyncColors.trueWhite),
                  decoration: const InputDecoration(
                    labelText: 'HMAC Algorithm',
                    border: OutlineInputBorder(),
                  ),
                  items: TotpAlgorithm.values.map((algo) {
                    return DropdownMenuItem(
                      value: algo,
                      child: Text(algo.wireValue),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _totpAlgorithm = val;
                        _recomputeActivePayload();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _totpDigits,
                  dropdownColor: ZeroSyncColors.darkGraphite,
                  style: const TextStyle(
                      fontSize: 12, color: ZeroSyncColors.trueWhite),
                  decoration: const InputDecoration(
                    labelText: 'OTP Digits',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 6, child: Text('6 Digits')),
                    DropdownMenuItem(value: 8, child: Text('8 Digits')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _totpDigits = val;
                        _recomputeActivePayload();
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _totpPeriod,
                  dropdownColor: ZeroSyncColors.darkGraphite,
                  style: const TextStyle(
                      fontSize: 12, color: ZeroSyncColors.trueWhite),
                  decoration: const InputDecoration(
                    labelText: 'Period (Seconds)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('30 Seconds')),
                    DropdownMenuItem(value: 60, child: Text('60 Seconds')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _totpPeriod = val;
                        _recomputeActivePayload();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeb3Form() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: CryptoCurrency.values.map((crypto) {
              final isSelected = _activeCrypto == crypto;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label:
                      Text(crypto.label, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  selectedColor: ZeroSyncColors.cyan,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _activeCrypto = crypto;
                        _recomputeActivePayload();
                      });
                    }
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          if (_activeCrypto == CryptoCurrency.bitcoin) ...[
            TextField(
              controller: _btcInfoAddressController,
              style: const TextStyle(
                  fontSize: 12, color: ZeroSyncColors.trueWhite),
              decoration: const InputDecoration(
                labelText: 'Bitcoin Address (Legacy, P2SH, or Bech32)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _recomputeActivePayload(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _btcAmountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Amount (BTC)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _btcLabelController,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Recipient Label',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _btcMessageController,
              style: const TextStyle(
                  fontSize: 12, color: ZeroSyncColors.trueWhite),
              decoration: const InputDecoration(
                labelText: 'Payment Message / Reference',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _recomputeActivePayload(),
            ),
          ] else if (_activeCrypto == CryptoCurrency.ethereum) ...[
            TextField(
              controller: _ethAddressController,
              style: const TextStyle(
                  fontSize: 12, color: ZeroSyncColors.trueWhite),
              decoration: const InputDecoration(
                labelText: 'Ethereum Address (0x + 40 Hex)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _recomputeActivePayload(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ethValueController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Value (ETH)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ethChainIdController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'EVM Chain ID (1=Mainnet)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
              ],
            ),
          ] else if (_activeCrypto == CryptoCurrency.solana) ...[
            TextField(
              controller: _solRecipientController,
              style: const TextStyle(
                  fontSize: 12, color: ZeroSyncColors.trueWhite),
              decoration: const InputDecoration(
                labelText: 'Solana Recipient (Base58 Address)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _recomputeActivePayload(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _solAmountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Amount (SOL)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _solLabelController,
                    style: const TextStyle(
                        fontSize: 12, color: ZeroSyncColors.trueWhite),
                    decoration: const InputDecoration(
                      labelText: 'Label / Memo',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _recomputeActivePayload(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlip39Form() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline,
                  size: 16, color: ZeroSyncColors.emerald),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SLIP-39 Shamir Secret Sharing Multi-Share Deck',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          TextField(
            controller: _slip39SecretController,
            maxLines: 2,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Master Secret Key / Mnemonic Seed to Split',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _generateShamirShares(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Threshold (M): $_slip39Threshold Shares Required',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Slider(
                      value: _slip39Threshold.toDouble(),
                      min: 2,
                      max: _slip39TotalShares.toDouble(),
                      divisions: (_slip39TotalShares - 2).clamp(1, 10),
                      activeColor: ZeroSyncColors.emerald,
                      onChanged: (val) {
                        setState(() {
                          _slip39Threshold = val.toInt();
                          _generateShamirShares();
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Deck (N): $_slip39TotalShares Shares Generated',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    Slider(
                      value: _slip39TotalShares.toDouble(),
                      min: 2,
                      max: 8,
                      divisions: 6,
                      activeColor: ZeroSyncColors.cyan,
                      onChanged: (val) {
                        setState(() {
                          _slip39TotalShares = val.toInt();
                          if (_slip39Threshold > _slip39TotalShares) {
                            _slip39Threshold = _slip39TotalShares;
                          }
                          _generateShamirShares();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_generatedShares.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ZeroSyncColors.darkBorder),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 14),
                    onPressed: _currentShareIndex > 0
                        ? () {
                            setState(() {
                              _currentShareIndex--;
                              _recomputeActivePayload();
                            });
                          }
                        : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Share ${_currentShareIndex + 1} of ${_generatedShares.length} (Threshold: $_slip39Threshold-of-$_slip39TotalShares)',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: ZeroSyncColors.emerald),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 14),
                    onPressed: _currentShareIndex < _generatedShares.length - 1
                        ? () {
                            setState(() {
                              _currentShareIndex++;
                              _recomputeActivePayload();
                            });
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEncryptedForm() {
    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.security, size: 16, color: ZeroSyncColors.cyan),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'XChaCha20-Poly1305 + Argon2id Encrypted Envelope',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),
          TextField(
            controller: _encPlaintextController,
            maxLines: 2,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: const InputDecoration(
              labelText: 'Confidential Plaintext Payload',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _encPassphraseController,
            obscureText: _obscurePassphrase,
            style:
                const TextStyle(fontSize: 12, color: ZeroSyncColors.trueWhite),
            decoration: InputDecoration(
              labelText: 'Passphrase (Argon2id Memory-Hard Key Derivation)',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassphrase ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                ),
                onPressed: () {
                  setState(() => _obscurePassphrase = !_obscurePassphrase);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const ValueKey('encrypt_payload_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ZeroSyncColors.emerald,
                foregroundColor: ZeroSyncColors.trueBlack,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: _isEncrypting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.enhanced_encryption, size: 16),
              label: Text(
                _isEncrypting
                    ? 'Deriving Argon2id Key...'
                    : 'Encrypt Payload with Argon2id',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _isEncrypting ? null : _executePayloadEncryption,
            ),
          ),
          if (_encryptedEnvelope != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: ZeroSyncColors.trueBlack,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Envelope Preamble: 0x5A45 • Ciphertext: ${_encryptedEnvelope!.ciphertext.length}B • Nonce: 24B • Salt: 16B • MAC: 16B',
                style: const TextStyle(
                    fontSize: 10, color: ZeroSyncColors.emerald),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    final isValid = _validationError == null;

    return Container(
      padding: const EdgeInsets.all(ZeroSyncSpacing.md),
      decoration: BoxDecoration(
        color: ZeroSyncColors.darkGraphite,
        borderRadius: BorderRadius.circular(ZeroSyncRadii.md),
        border: Border.all(color: ZeroSyncColors.darkBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code, size: 18, color: ZeroSyncColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_activeSchema.label} Preview',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: ZeroSyncColors.trueWhite,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ZeroSyncColors.trueBlack,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${_computedPayload.length} Bytes',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: ZeroSyncColors.cyan),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // High-Contrast QR Viewport
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 10),
              ],
            ),
            child: isValid
                ? QrImageView(
                    data: _computedPayload,
                    version: QrVersions.auto,
                    size: 200,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    padding: const EdgeInsets.all(6),
                  )
                : const SizedBox(
                    width: 200,
                    height: 200,
                    child: Center(
                      child: Text(
                        'Invalid Payload',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          if (_validationError != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(40),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: Colors.redAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _validationError!,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Raw Payload Preview Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ZeroSyncColors.trueBlack,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ZeroSyncColors.darkBorder),
            ),
            child: SelectableText(
              _computedPayload,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: ZeroSyncColors.trueWhite,
              ),
              maxLines: 4,
            ),
          ),
          const SizedBox(height: ZeroSyncSpacing.md),

          // Action Buttons
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.cyan,
                  side: const BorderSide(color: ZeroSyncColors.cyan),
                ),
                icon: const Icon(Icons.copy, size: 14),
                label:
                    const Text('Copy Payload', style: TextStyle(fontSize: 11)),
                onPressed: isValid ? _copyToClipboard : null,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.darkSlate,
                  foregroundColor: ZeroSyncColors.amber,
                  side: const BorderSide(color: ZeroSyncColors.amber),
                ),
                icon: const Icon(Icons.security, size: 14),
                label: const Text('Inspect Threat',
                    style: TextStyle(fontSize: 11)),
                onPressed: isValid
                    ? () {
                        ThreatInspectorSheet.show(
                          context: context,
                          rawPayload: _computedPayload,
                          onActionDispatched: (String p) =>
                              widget.onActionDispatched?.call(p),
                        );
                      }
                    : null,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ZeroSyncColors.emerald,
                  foregroundColor: ZeroSyncColors.trueBlack,
                ),
                icon: const Icon(Icons.save, size: 14),
                label: const Text('Save to Vault',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: isValid ? _saveToVault : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
