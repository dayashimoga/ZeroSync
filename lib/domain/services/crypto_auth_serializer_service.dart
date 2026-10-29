import '../entities/crypto_auth_payload.dart';

/// Pure Domain Serializer for Secure Authentication (RFC 6238 TOTP) & Web3 Crypto Payment URIs.
class CryptoAuthSerializerService {
  // ===========================================================================
  // 1. RFC 6238 TOTP KEY URI SERIALIZER
  // ===========================================================================

  /// Serializes a [TotpPayload] into an RFC 6238 `otpauth://totp/...` Key URI.
  String serializeTotp(TotpPayload payload) {
    payload.validateInvariants();

    final cleanedSecret =
        payload.secret.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final account = payload.accountName.trim();
    final issuer = payload.issuer?.trim();

    // Construct label: [Issuer:]AccountName where ':' is literal separator per Key URI spec
    final encodedAccount = Uri.encodeComponent(account);
    final encodedLabel = (issuer != null && issuer.isNotEmpty)
        ? '${Uri.encodeComponent(issuer)}:$encodedAccount'
        : encodedAccount;

    final queryParams = <String, String>{
      'secret': cleanedSecret,
    };

    if (issuer != null && issuer.isNotEmpty) {
      queryParams['issuer'] = issuer;
    }

    if (payload.algorithm != TotpAlgorithm.sha1) {
      queryParams['algorithm'] = payload.algorithm.wireValue;
    }

    if (payload.digits != 6) {
      queryParams['digits'] = payload.digits.toString();
    }

    if (payload.period != 30) {
      queryParams['period'] = payload.period.toString();
    }

    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'otpauth://totp/$encodedLabel?$queryString';
  }

  /// Deserializes an `otpauth://totp/...` Key URI into a [TotpPayload].
  TotpPayload deserializeTotp(String uriString) {
    final uri = Uri.parse(uriString.trim());
    if (uri.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException('Invalid URI scheme: expected otpauth');
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw FormatException(
          'Unsupported OTP type: ${uri.host} (only totp supported)');
    }

    // Path represents /Label
    var path = uri.path;
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    final rawLabel = Uri.decodeComponent(path);
    if (rawLabel.isEmpty) {
      throw const FormatException('Missing account label in otpauth URI');
    }

    String? issuerFromLabel;
    String accountName = rawLabel;
    if (rawLabel.contains(':')) {
      final parts = rawLabel.split(':');
      issuerFromLabel = parts[0].trim();
      accountName = parts.sublist(1).join(':').trim();
    }

    final query = uri.queryParameters;
    final secret = query['secret'];
    if (secret == null || secret.isEmpty) {
      throw const FormatException('Missing required secret query parameter');
    }

    final issuer = query['issuer'] ?? issuerFromLabel;
    final algoStr = query['algorithm'] ?? 'SHA1';
    final digitsStr = query['digits'] ?? '6';
    final periodStr = query['period'] ?? '30';

    final algorithm = TotpAlgorithm.fromWireValue(algoStr);
    final digits = int.tryParse(digitsStr) ?? 6;
    final period = int.tryParse(periodStr) ?? 30;

    final payload = TotpPayload(
      secret: secret,
      accountName: accountName,
      issuer: issuer,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // 2. BIP-0021 BITCOIN PAYMENT SERIALIZER
  // ===========================================================================

  /// Serializes a [BitcoinPaymentPayload] into a standard BIP-0021 URI:
  /// `bitcoin:address[?amount=x&label=y&message=z]`
  String serializeBitcoin(BitcoinPaymentPayload payload) {
    payload.validateInvariants();

    final buffer = StringBuffer('bitcoin:${payload.address.trim()}');
    final params = <String>[];

    if (payload.amount != null) {
      params.add('amount=${payload.amount}');
    }
    if (payload.label != null && payload.label!.isNotEmpty) {
      params.add('label=${Uri.encodeComponent(payload.label!)}');
    }
    if (payload.message != null && payload.message!.isNotEmpty) {
      params.add('message=${Uri.encodeComponent(payload.message!)}');
    }

    if (params.isNotEmpty) {
      buffer.write('?${params.join('&')}');
    }

    return buffer.toString();
  }

  /// Deserializes a BIP-0021 URI into a [BitcoinPaymentPayload].
  BitcoinPaymentPayload deserializeBitcoin(String uriString) {
    final trimmed = uriString.trim();
    if (!trimmed.toLowerCase().startsWith('bitcoin:')) {
      throw const FormatException(
          'Invalid Bitcoin URI: must start with bitcoin:');
    }

    final body = trimmed.substring(8);
    final qIdx = body.indexOf('?');
    final address = qIdx == -1 ? body : body.substring(0, qIdx);

    double? amount;
    String? label;
    String? message;

    if (qIdx != -1) {
      final queryString = body.substring(qIdx + 1);
      final queryParams = Uri.splitQueryString(queryString);
      if (queryParams.containsKey('amount')) {
        amount = double.tryParse(queryParams['amount']!);
      }
      label = queryParams['label'];
      message = queryParams['message'];
    }

    final payload = BitcoinPaymentPayload(
      address: address,
      amount: amount,
      label: label,
      message: message,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // 3. EIP-681 ETHEREUM PAYMENT SERIALIZER
  // ===========================================================================

  /// Serializes an [EthereumPaymentPayload] into standard EIP-681 syntax:
  /// `ethereum:address[@chainId][?value=x&gasPrice=y&gasLimit=z]`
  String serializeEthereum(EthereumPaymentPayload payload) {
    payload.validateInvariants();

    final buffer = StringBuffer('ethereum:${payload.address.trim()}');
    if (payload.chainId != null && payload.chainId != 1) {
      buffer.write('@${payload.chainId}');
    }

    final params = <String>[];
    if (payload.valueWei != null) {
      params.add('value=${payload.valueWei}');
    } else if (payload.valueEth != null) {
      params.add('value=${payload.valueEth}e18');
    }

    if (payload.gasPrice != null) {
      params.add('gasPrice=${payload.gasPrice}');
    }
    if (payload.gasLimit != null) {
      params.add('gasLimit=${payload.gasLimit}');
    }

    if (params.isNotEmpty) {
      buffer.write('?${params.join('&')}');
    }

    return buffer.toString();
  }

  /// Deserializes an EIP-681 URI into an [EthereumPaymentPayload].
  EthereumPaymentPayload deserializeEthereum(String uriString) {
    final trimmed = uriString.trim();
    if (!trimmed.toLowerCase().startsWith('ethereum:')) {
      throw const FormatException(
          'Invalid Ethereum URI: must start with ethereum:');
    }

    var body = trimmed.substring(9);
    final qIdx = body.indexOf('?');
    final target = qIdx == -1 ? body : body.substring(0, qIdx);

    String address = target;
    int? chainId = 1;
    if (target.contains('@')) {
      final parts = target.split('@');
      address = parts[0];
      chainId = int.tryParse(parts[1]) ?? 1;
    }

    double? valueEth;
    BigInt? valueWei;
    BigInt? gasPrice;
    BigInt? gasLimit;

    if (qIdx != -1) {
      final queryString = body.substring(qIdx + 1);
      final queryParams = Uri.splitQueryString(queryString);
      final rawVal = queryParams['value'];
      if (rawVal != null) {
        if (rawVal.toLowerCase().endsWith('e18')) {
          final prefix = rawVal.substring(0, rawVal.length - 3);
          valueEth = double.tryParse(prefix);
        } else {
          valueWei = BigInt.tryParse(rawVal);
        }
      }
      if (queryParams.containsKey('gasPrice')) {
        gasPrice = BigInt.tryParse(queryParams['gasPrice']!);
      }
      if (queryParams.containsKey('gasLimit')) {
        gasLimit = BigInt.tryParse(queryParams['gasLimit']!);
      }
    }

    final payload = EthereumPaymentPayload(
      address: address,
      valueEth: valueEth,
      valueWei: valueWei,
      chainId: chainId,
      gasPrice: gasPrice,
      gasLimit: gasLimit,
    );
    payload.validateInvariants();
    return payload;
  }

  // ===========================================================================
  // 4. SOLANA PAY SERIALIZER
  // ===========================================================================

  /// Serializes a [SolanaPaymentPayload] into a standard Solana Pay URI:
  /// `solana:recipient[?amount=x&label=y&message=z&memo=w]`
  String serializeSolana(SolanaPaymentPayload payload) {
    payload.validateInvariants();

    final buffer = StringBuffer('solana:${payload.recipient.trim()}');
    final params = <String>[];

    if (payload.amount != null) {
      params.add('amount=${payload.amount}');
    }
    if (payload.label != null && payload.label!.isNotEmpty) {
      params.add('label=${Uri.encodeComponent(payload.label!)}');
    }
    if (payload.message != null && payload.message!.isNotEmpty) {
      params.add('message=${Uri.encodeComponent(payload.message!)}');
    }
    if (payload.memo != null && payload.memo!.isNotEmpty) {
      params.add('memo=${Uri.encodeComponent(payload.memo!)}');
    }

    if (params.isNotEmpty) {
      buffer.write('?${params.join('&')}');
    }

    return buffer.toString();
  }

  /// Deserializes a Solana Pay URI into a [SolanaPaymentPayload].
  SolanaPaymentPayload deserializeSolana(String uriString) {
    final trimmed = uriString.trim();
    if (!trimmed.toLowerCase().startsWith('solana:')) {
      throw const FormatException(
          'Invalid Solana URI: must start with solana:');
    }

    final body = trimmed.substring(7);
    final qIdx = body.indexOf('?');
    final recipient = qIdx == -1 ? body : body.substring(0, qIdx);

    double? amount;
    String? label;
    String? message;
    String? memo;

    if (qIdx != -1) {
      final queryString = body.substring(qIdx + 1);
      final queryParams = Uri.splitQueryString(queryString);
      if (queryParams.containsKey('amount')) {
        amount = double.tryParse(queryParams['amount']!);
      }
      label = queryParams['label'];
      message = queryParams['message'];
      memo = queryParams['memo'];
    }

    final payload = SolanaPaymentPayload(
      recipient: recipient,
      amount: amount,
      label: label,
      message: message,
      memo: memo,
    );
    payload.validateInvariants();
    return payload;
  }
}
