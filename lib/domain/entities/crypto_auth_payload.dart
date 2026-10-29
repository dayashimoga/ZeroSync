import 'package:equatable/equatable.dart';

/// Supported HMAC Algorithms for TOTP (RFC 6238).
enum TotpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  final String wireValue;
  const TotpAlgorithm(this.wireValue);

  static TotpAlgorithm fromWireValue(String value) {
    final upper = value.toUpperCase().trim();
    if (upper == 'SHA256') return TotpAlgorithm.sha256;
    if (upper == 'SHA512') return TotpAlgorithm.sha512;
    return TotpAlgorithm.sha1;
  }
}

/// Pure Domain Entity representing an RFC 6238 TOTP (Time-Based One-Time Password) secret.
class TotpPayload extends Equatable {
  final String secret;
  final String accountName;
  final String? issuer;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  const TotpPayload({
    required this.secret,
    required this.accountName,
    this.issuer,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  });

  /// Invariant validations according to RFC 6238 and Google Authenticator Key URI specs.
  void validateInvariants() {
    if (accountName.trim().isEmpty) {
      throw ArgumentError('Account name cannot be empty in TOTP payload');
    }

    final cleanedSecret = secret.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (cleanedSecret.isEmpty) {
      throw ArgumentError('TOTP secret cannot be empty');
    }

    // RFC 4648 Base32 alphabet: A-Z and 2-7, optional '=' padding
    final base32Regex = RegExp(r'^[A-Z2-7=]+$');
    if (!base32Regex.hasMatch(cleanedSecret)) {
      throw ArgumentError(
          'TOTP secret contains invalid Base32 characters: $secret');
    }

    if (digits != 6 && digits != 8) {
      throw ArgumentError('TOTP digits must be either 6 or 8 (got $digits)');
    }

    if (period <= 0 || period > 300) {
      throw ArgumentError(
          'TOTP period must be between 1 and 300 seconds (got $period)');
    }
  }

  @override
  List<Object?> get props => [
        secret,
        accountName,
        issuer,
        algorithm,
        digits,
        period,
      ];
}

/// Pure Domain Entity representing a BIP-0021 Bitcoin Payment Request.
class BitcoinPaymentPayload extends Equatable {
  final String address;
  final double? amount; // In BTC
  final String? label;
  final String? message;

  const BitcoinPaymentPayload({
    required this.address,
    this.amount,
    this.label,
    this.message,
  });

  /// Validates Bitcoin address format per BIP-0021 / Bech32 / Base58Check.
  void validateInvariants() {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Bitcoin address cannot be empty');
    }

    // Legacy (1...), P2SH (3...), or Native SegWit / Taproot (bc1...)
    final btcRegex = RegExp(
        r'^(1[a-km-zA-HJ-NP-Z1-9]{25,34}|3[a-km-zA-HJ-NP-Z1-9]{25,34}|bc1[a-z0-9]{11,71})$',
        caseSensitive: false);
    if (!btcRegex.hasMatch(trimmed)) {
      throw ArgumentError('Invalid Bitcoin address format: $address');
    }

    if (amount != null && amount! < 0.0) {
      throw ArgumentError('Bitcoin amount must be non-negative: $amount');
    }
  }

  @override
  List<Object?> get props => [address, amount, label, message];
}

/// Pure Domain Entity representing an EIP-681 Ethereum Payment Request.
class EthereumPaymentPayload extends Equatable {
  final String address;
  final double? valueEth; // Value in Ether
  final BigInt? valueWei; // Optional exact value in Wei
  final int? chainId; // 1 for Mainnet, 137 for Polygon, etc.
  final BigInt? gasPrice;
  final BigInt? gasLimit;

  const EthereumPaymentPayload({
    required this.address,
    this.valueEth,
    this.valueWei,
    this.chainId = 1,
    this.gasPrice,
    this.gasLimit,
  });

  /// Invariant validations per EIP-681 and standard EVM 0x-hex format.
  void validateInvariants() {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Ethereum address cannot be empty');
    }

    // 0x prefix followed by 40 hexadecimal characters
    final ethRegex = RegExp(r'^0x[0-9a-fA-F]{40}$');
    if (!ethRegex.hasMatch(trimmed)) {
      throw ArgumentError(
          'Invalid Ethereum address format (expected 0x + 40 hex): $address');
    }

    if (valueEth != null && valueEth! < 0.0) {
      throw ArgumentError('Ethereum value must be non-negative: $valueEth');
    }

    if (chainId != null && chainId! <= 0) {
      throw ArgumentError('Invalid chain ID: $chainId');
    }
  }

  @override
  List<Object?> get props => [
        address,
        valueEth,
        valueWei,
        chainId,
        gasPrice,
        gasLimit,
      ];
}

/// Pure Domain Entity representing a Solana Pay URI (Base58 Recipient).
class SolanaPaymentPayload extends Equatable {
  final String recipient;
  final double? amount; // In SOL
  final String? label;
  final String? message;
  final String? memo;

  const SolanaPaymentPayload({
    required this.recipient,
    this.amount,
    this.label,
    this.message,
    this.memo,
  });

  /// Invariant validations per Solana Pay Specification.
  void validateInvariants() {
    final trimmed = recipient.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Solana recipient cannot be empty');
    }

    // Base58 public key string: 32 to 44 characters (excluding 0, O, I, l)
    final solRegex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
    if (!solRegex.hasMatch(trimmed)) {
      throw ArgumentError(
          'Invalid Solana Base58 public key format: $recipient');
    }

    if (amount != null && amount! < 0.0) {
      throw ArgumentError('Solana amount must be non-negative: $amount');
    }
  }

  @override
  List<Object?> get props => [recipient, amount, label, message, memo];
}
