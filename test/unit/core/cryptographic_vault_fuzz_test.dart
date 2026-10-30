import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

// Data Layer Encrypted Storage
import 'package:airdrop_qr/data/datasources/encrypted_vault_datasource.dart';

// Domain Serializers & Parsers
import 'package:airdrop_qr/domain/services/crypto_auth_serializer_service.dart';
import 'package:airdrop_qr/domain/services/domain_inspector_service.dart';
import 'package:airdrop_qr/domain/services/infrastructure_serializer_service.dart';
import 'package:airdrop_qr/domain/services/qr_matrix_generator_service.dart';
import 'package:airdrop_qr/domain/services/tracker_stripper_service.dart';
import 'package:airdrop_qr/domain/services/vcard_serializer_service.dart';

// Memory & Lifecycles
import 'package:airdrop_qr/core/utils/disposal_auditor.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockDatabase extends Mock implements Database {}

void main() {
  group('Cryptographic Key Derivation & Vault Encryption Specs', () {
    late MockFlutterSecureStorage mockSecureStorage;
    late MockDatabase mockDb;
    late EncryptedVaultDataSourceImpl vaultDataSource;

    setUp(() {
      mockSecureStorage = MockFlutterSecureStorage();
      mockDb = MockDatabase();
      vaultDataSource =
          EncryptedVaultDataSourceImpl(secureStorage: mockSecureStorage);

      when(() => mockDb.isOpen).thenReturn(true);
      when(() => mockDb.close()).thenAnswer((_) async {});
      when(() => mockDb.execute(any())).thenAnswer((_) async {});
    });

    test(
        'Derives 256-bit cryptographically secure master key and persists to keystore',
        () async {
      when(() => mockSecureStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => null);
      when(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'))).thenAnswer((_) async {});

      final String masterKey = await vaultDataSource.getOrGenerateMasterKey();

      expect(masterKey.isNotEmpty, isTrue);
      // 32 bytes base64Url encoded length is 43-44 characters
      expect(masterKey.length, greaterThanOrEqualTo(43));

      // Verify key decodes to exactly 32 bytes (256 bits)
      final Uint8List rawKeyBytes =
          base64Url.decode(base64Url.normalize(masterKey));
      expect(rawKeyBytes.length, equals(32));

      // Verify persistent write to hardware keystore
      verify(() => mockSecureStorage.write(
          key: 'zerosync_vault_master_key_v1', value: masterKey)).called(1);

      // Subsequent retrieval returns persisted key
      when(() => mockSecureStorage.read(key: 'zerosync_vault_master_key_v1'))
          .thenAnswer((_) async => masterKey);

      final String cachedKey = await vaultDataSource.getOrGenerateMasterKey();
      expect(cachedKey, equals(masterKey));
    });

    test('Verifies SQLCipher AES-256 database cipher integrity', () async {
      await vaultDataSource.initialize(injectedDb: mockDb);

      when(() => mockDb.rawQuery(any())).thenAnswer((_) async => [
            {'value': 'AES-256-CBC'}
          ]);

      final bool isIntegrityVerified =
          await vaultDataSource.verifyCipherIntegrity();
      expect(isIntegrityVerified, isTrue);

      verify(() => mockDb.rawQuery(
              "SELECT value FROM vault_metadata WHERE key = 'cipher_standard'"))
          .called(1);
    });

    test('Securely scrubs sensitive master keys and decrypted buffers in RAM',
        () {
      final keyBuffer = Uint8List.fromList(<int>[
        0x5F,
        0x1A,
        0x9B,
        0xC3,
        0x4D,
        0x8E,
        0x22,
        0xF0,
        0xAA,
        0xBB,
        0xCC,
        0xDD,
        0xEE,
        0xFF,
        0x01,
        0x23,
      ]);

      expect(keyBuffer.every((b) => b == 0), isFalse);

      DisposalAuditor.scrubBuffer(keyBuffer);

      // Memory page completely overwritten with zeroes
      expect(keyBuffer.every((b) => b == 0), isTrue);
    });
  });

  group('Parser & QR Scanner Payload Fuzzing Specs', () {
    late VCardSerializerService vcardSerializer;
    late InfrastructureSerializerService infraSerializer;
    late CryptoAuthSerializerService cryptoSerializer;
    late QrMatrixGeneratorService matrixGenerator;
    late DomainInspectorService domainInspector;
    late TrackerStripperService trackerStripper;

    setUp(() {
      vcardSerializer = VCardSerializerService();
      infraSerializer = InfrastructureSerializerService();
      cryptoSerializer = CryptoAuthSerializerService();
      matrixGenerator = QrMatrixGeneratorService();
      domainInspector = DomainInspectorService();
      trackerStripper = TrackerStripperService();
    });

    test(
        'Fuzzing 1: Malformed & Invalid UTF-8 Byte Sequences in QR Matrix Engine',
        () {
      final invalidUtf8Bytes = <Uint8List>[
        Uint8List.fromList([0xC3, 0x28]), // Invalid 2-byte continuation
        Uint8List.fromList([0xE0, 0x80, 0xAF]), // Overlong encoding
        Uint8List.fromList([0xF4, 0xBF, 0xBF, 0xFF]), // Out of Unicode range
        Uint8List.fromList(List<int>.generate(
            128, (i) => 0x80 + i)), // Pure non-ASCII high bits
      ];

      for (final badBytes in invalidUtf8Bytes) {
        // Raw byte matrix generation must succeed without crashing
        final matrix = matrixGenerator.generateMatrix(
          payload: badBytes,
          eccLevel: QrErrorCorrectionLevel.low,
        );
        expect(matrix.size, greaterThan(0));
      }
    });

    test(
        'Fuzzing 2: Oversized Payloads Exceeding Maximum QR Specification Limits',
        () {
      // 5,000 bytes exceeds Version 40 Low ECC max capacity (2,953 bytes)
      final oversizedBytes = Uint8List(5000);

      expect(
        () => matrixGenerator.generateMatrix(payload: oversizedBytes),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Fuzzing 3: Malformed RFC 6238 TOTP Key URIs and Secret Padding', () {
      final malformedTotpUris = <String>[
        'otpauth://unknown/test?secret=JBSWY3DPEHPK3PXP', // Invalid type (not totp)
        'otpauth://totp/alice?secret=1903847', // Non-Base32 numeric secret (1, 8, 9, 0 are invalid)
        'otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&digits=10', // Invalid digits (must be 6 or 8)
        'otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP&period=0', // Invalid period (must be > 0)
        'otpauth://totp/?secret=JBSWY3DPEHPK3PXP', // Missing account name
      ];

      for (final badUri in malformedTotpUris) {
        expect(
          () => cryptoSerializer.deserializeTotp(badUri),
          throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
        );
      }
    });

    test('Fuzzing 4: Malformed Wi-Fi Configuration Wire Payloads', () {
      final malformedWifiStrings = <String>[
        'WIFI:;', // Missing SSID
        'WIFI:T:WPA;P:short;;', // WPA password < 8 characters
        'WIFI:T:UNKNOWN;S:TestNet;;', // Unsupported security type
        'INVALID_WIFI_STRING', // Missing WIFI: prefix
      ];

      for (final badWifi in malformedWifiStrings) {
        expect(
          () => infraSerializer.deserializeWifi(badWifi),
          throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
        );
      }
    });

    test('Fuzzing 5: Malformed Geolocation and iCalendar Payloads', () {
      // Coordinates out of bounds
      expect(
        () => infraSerializer.deserializeGeo('geo:95.0,180.0'), // Latitude > 90
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );
      expect(
        () => infraSerializer
            .deserializeGeo('geo:45.0,-195.0'), // Longitude < -180
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );
      expect(
        () => infraSerializer.deserializeGeo('geo:not_a_number,12.0'),
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );

      // Malformed iCalendar
      expect(
        () => infraSerializer
            .deserializeCalendar('BEGIN:VCALENDAR\nEND:VCALENDAR'),
        throwsA(anyOf(
            isA<ArgumentError>(), isA<FormatException>())), // Missing VEVENT
      );
    });

    test(
        'Fuzzing 6: SQL Injection, XSS & Directory Traversal in Domain Inspector',
        () {
      const maliciousPayloads = <String>[
        "https://example.com/search?q='; DROP TABLE scans; --",
        'javascript:alert(document.cookie)',
        'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
        'https://evil.com/../../../etc/passwd',
        'file:///etc/shadow',
      ];

      for (final payload in maliciousPayloads) {
        final report = domainInspector.inspect(payload);
        // Non-http schemes (javascript, file, data) are caught as suspicious or high risk
        if (payload.startsWith('javascript') ||
            payload.startsWith('file') ||
            payload.startsWith('data')) {
          expect(report.isHighRisk || !report.isSafe, isTrue);
        }

        // Sanitizer strips trackers without crashing on injection characters
        final sanitized = trackerStripper.sanitize(payload);
        expect(sanitized.sanitizedUrl.isNotEmpty, isTrue);
      }
    });

    test('Fuzzing 7: Malformed vCard 4.0 Contact Payloads', () {
      final badVCards = <String>[
        'BEGIN:VCARD\nVERSION:4.0\nEND:VCARD', // Missing FN (Formatted Name)
        '', // Empty content
        'NOT_A_VCARD_PAYLOAD', // Missing mandatory FN property
      ];

      for (final badVCard in badVCards) {
        expect(
          () => vcardSerializer.deserializeVCard4(badVCard),
          throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
        );
      }
    });
  });
}
