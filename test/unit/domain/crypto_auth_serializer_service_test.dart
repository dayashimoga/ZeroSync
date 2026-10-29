import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/entities/crypto_auth_payload.dart';
import 'package:airdrop_qr/domain/services/crypto_auth_serializer_service.dart';

void main() {
  late CryptoAuthSerializerService service;

  setUp(() {
    service = CryptoAuthSerializerService();
  });

  group('RFC 6238 TOTP Authentication Key URI Serializer', () {
    test('Serializes and deserializes standard TOTP URI with SHA1 and 6 digits',
        () {
      const payload = TotpPayload(
        secret: 'JBSWY3DPEHPK3PXP', // Base32 for "Hello!"
        accountName: 'alice@zerosync.local',
        issuer: 'ZeroSync',
        algorithm: TotpAlgorithm.sha1,
        digits: 6,
        period: 30,
      );

      final uri = service.serializeTotp(payload);
      expect(
        uri,
        equals(
            'otpauth://totp/ZeroSync:alice%40zerosync.local?secret=JBSWY3DPEHPK3PXP&issuer=ZeroSync'),
      );

      final restored = service.deserializeTotp(uri);
      expect(restored, equals(payload));
    });

    test('Serializes high-security TOTP with SHA512, 8 digits and 60s period',
        () {
      const payload = TotpPayload(
        secret: 'MZXW633PN5XW6MZX',
        accountName: 'ops-admin',
        issuer: 'VaultSecurity',
        algorithm: TotpAlgorithm.sha512,
        digits: 8,
        period: 60,
      );

      final uri = service.serializeTotp(payload);
      expect(uri, contains('algorithm=SHA512'));
      expect(uri, contains('digits=8'));
      expect(uri, contains('period=60'));

      final restored = service.deserializeTotp(uri);
      expect(restored.algorithm, equals(TotpAlgorithm.sha512));
      expect(restored.digits, equals(8));
      expect(restored.period, equals(60));
      expect(restored.accountName, equals('ops-admin'));
      expect(restored.issuer, equals('VaultSecurity'));
    });

    test('Throws on invalid Base32 characters or parameters', () {
      // Invalid characters in Base32 (8 and 9 are prohibited in RFC 4648 Base32)
      const invalidBase32 = TotpPayload(
        secret: 'INVALID890',
        accountName: 'test',
      );
      expect(() => service.serializeTotp(invalidBase32), throwsArgumentError);

      // Invalid digits
      const invalidDigits = TotpPayload(
        secret: 'JBSWY3DPEHPK3PXP',
        accountName: 'test',
        digits: 7,
      );
      expect(() => service.serializeTotp(invalidDigits), throwsArgumentError);

      // Negative period
      const invalidPeriod = TotpPayload(
        secret: 'JBSWY3DPEHPK3PXP',
        accountName: 'test',
        period: -10,
      );
      expect(() => service.serializeTotp(invalidPeriod), throwsArgumentError);
    });
  });

  group('BIP-0021 Bitcoin Payment Serializer', () {
    test('Serializes Legacy, P2SH, and Bech32 Bitcoin payment requests', () {
      const bech32Payload = BitcoinPaymentPayload(
        address: 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        amount: 0.0525,
        label: 'Air-Gap Vault Deposit',
        message: 'Encrypted transfer fee',
      );

      final uri = service.serializeBitcoin(bech32Payload);
      expect(
        uri,
        equals(
            'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.0525&label=Air-Gap%20Vault%20Deposit&message=Encrypted%20transfer%20fee'),
      );

      final restored = service.deserializeBitcoin(uri);
      expect(restored, equals(bech32Payload));
    });

    test('Throws on invalid Bitcoin address or negative amount', () {
      const invalidAddress = BitcoinPaymentPayload(
        address: 'not_a_bitcoin_address_123',
        amount: 1.0,
      );
      expect(
          () => service.serializeBitcoin(invalidAddress), throwsArgumentError);

      const negativeAmt = BitcoinPaymentPayload(
        address: '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
        amount: -0.1,
      );
      expect(() => service.serializeBitcoin(negativeAmt), throwsArgumentError);
    });
  });

  group('EIP-681 Ethereum Payment Serializer', () {
    test('Serializes Ethereum payment request with chainId and value in ETH',
        () {
      const payload = EthereumPaymentPayload(
        address: '0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe',
        valueEth: 1.5,
        chainId: 1,
      );

      final uri = service.serializeEthereum(payload);
      expect(
          uri,
          equals(
              'ethereum:0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe?value=1.5e18'));

      final restored = service.deserializeEthereum(uri);
      expect(restored.address,
          equals('0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe'));
      expect(restored.valueEth, equals(1.5));
      expect(restored.chainId, equals(1));
    });

    test('Serializes Polygon payment with custom chainId and gas parameters',
        () {
      final payload = EthereumPaymentPayload(
        address: '0x71C7656EC7ab88b098defB751B7401B5f6d8976F',
        valueWei: BigInt.from(1000000000000000),
        chainId: 137, // Polygon
        gasPrice: BigInt.from(30000000000),
        gasLimit: BigInt.from(21000),
      );

      final uri = service.serializeEthereum(payload);
      expect(uri, contains('@137?'));
      expect(uri, contains('value=1000000000000000'));
      expect(uri, contains('gasPrice=30000000000'));
      expect(uri, contains('gasLimit=21000'));

      final restored = service.deserializeEthereum(uri);
      expect(restored.chainId, equals(137));
      expect(restored.valueWei, equals(BigInt.from(1000000000000000)));
      expect(restored.gasLimit, equals(BigInt.from(21000)));
    });

    test('Throws on invalid Ethereum address format', () {
      const invalidEth = EthereumPaymentPayload(
        address: '0x12345', // Too short
      );
      expect(() => service.serializeEthereum(invalidEth), throwsArgumentError);
    });
  });

  group('Solana Pay Serializer', () {
    test('Serializes Solana Pay URI with Base58 recipient and parameters', () {
      const payload = SolanaPaymentPayload(
        recipient: 'mvines9iiHiQTysrwkJjGNT2ecPdAggfdhTKEGLGQA4',
        amount: 2.75,
        label: 'ZeroSync Hardware Token',
        message: 'Order #4092 AirGap Secure',
        memo: 'MEMO-99124',
      );

      final uri = service.serializeSolana(payload);
      expect(
        uri,
        equals(
            'solana:mvines9iiHiQTysrwkJjGNT2ecPdAggfdhTKEGLGQA4?amount=2.75&label=ZeroSync%20Hardware%20Token&message=Order%20%234092%20AirGap%20Secure&memo=MEMO-99124'),
      );

      final restored = service.deserializeSolana(uri);
      expect(restored, equals(payload));
    });

    test('Throws on invalid Solana Base58 characters', () {
      const invalidBase58 = SolanaPaymentPayload(
        recipient: '0OIlInvalidSolanaPublicKeyCharactersHere12345',
        amount: 1.0,
      );
      expect(() => service.serializeSolana(invalidBase58), throwsArgumentError);
    });
  });
}
