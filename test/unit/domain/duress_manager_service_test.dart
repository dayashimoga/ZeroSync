import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/domain/services/duress_manager_service.dart';

void main() {
  group('DuressSecurityConfig Unit Tests', () {
    test('fromPlaintextPins computes correct SHA-256 hashes', () {
      const primary = '1234';
      const duress = '9999';

      final config = DuressSecurityConfig.fromPlaintextPins(
        primaryPin: primary,
        duressPin: duress,
        autoScrubRealKeyOnDuress: true,
      );

      final expectedPrimaryHash =
          sha256.convert(utf8.encode(primary)).toString();
      final expectedDuressHash = sha256.convert(utf8.encode(duress)).toString();

      expect(config.primaryPinHash, equals(expectedPrimaryHash));
      expect(config.duressPinHash, equals(expectedDuressHash));
      expect(config.autoScrubRealKeyOnDuress, isTrue);
    });

    test('Throws ArgumentError if primary PIN is empty or whitespace', () {
      expect(
        () => DuressSecurityConfig.fromPlaintextPins(
          primaryPin: '   ',
          duressPin: '9999',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError if duress PIN is empty or whitespace', () {
      expect(
        () => DuressSecurityConfig.fromPlaintextPins(
          primaryPin: '1234',
          duressPin: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError if primary and duress PINs match', () {
      expect(
        () => DuressSecurityConfig.fromPlaintextPins(
          primaryPin: '1234',
          duressPin: ' 1234 ',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Equatable value equality specs', () {
      final config1 = DuressSecurityConfig.fromPlaintextPins(
        primaryPin: '1234',
        duressPin: '9999',
      );
      final config2 = DuressSecurityConfig.fromPlaintextPins(
        primaryPin: '1234',
        duressPin: '9999',
      );
      final config3 = DuressSecurityConfig.fromPlaintextPins(
        primaryPin: '1234',
        duressPin: '8888',
      );

      expect(config1, equals(config2));
      expect(config1 == config3, isFalse);
    });
  });

  group('DuressManagerService PIN Evaluation & State Machine Specs', () {
    late DuressManagerService service;
    late DuressSecurityConfig testConfig;

    setUp(() {
      testConfig = DuressSecurityConfig.fromPlaintextPins(
        primaryPin: '123456',
        duressPin: '999111',
        autoScrubRealKeyOnDuress: true,
      );
      service = DuressManagerService();
    });

    test('Initial unconfigured state checks', () {
      expect(service.isConfigured, isFalse);
      expect(service.isDuressActive, isFalse);
      expect(service.config, isNull);

      expect(
        () => service.evaluatePin('123456'),
        throwsA(isA<StateError>()),
      );
    });

    test('Configured state evaluates primary PIN correctly', () {
      service.configure(testConfig);
      expect(service.isConfigured, isTrue);
      expect(service.config, equals(testConfig));

      final result = service.evaluatePin('123456');
      expect(result, equals(PinAuthResult.primaryAccess));
      expect(service.isDuressActive, isFalse);
    });

    test('Duress PIN activates panic decoy mode', () {
      service.configure(testConfig);

      final result = service.evaluatePin(' 999111 ');
      expect(result, equals(PinAuthResult.duressPanicTriggered));
      expect(service.isDuressActive, isTrue);
    });

    test('Subsequent primary PIN deactivates duress state', () {
      service.configure(testConfig);
      service.evaluatePin('999111');
      expect(service.isDuressActive, isTrue);

      final secondResult = service.evaluatePin('123456');
      expect(secondResult, equals(PinAuthResult.primaryAccess));
      expect(service.isDuressActive, isFalse);
    });

    test('Invalid PIN returns invalidPin and does not toggle state', () {
      service.configure(testConfig);

      final result = service.evaluatePin('000000');
      expect(result, equals(PinAuthResult.invalidPin));
      expect(service.isDuressActive, isFalse);
    });

    test('Manual triggerDuressMode and resetDuressState operations', () {
      expect(service.isDuressActive, isFalse);
      service.triggerDuressMode();
      expect(service.isDuressActive, isTrue);
      service.resetDuressState();
      expect(service.isDuressActive, isFalse);
    });
  });

  group('Decoy Seed Records Specifications', () {
    test('generateDecoySeedRecords contains valid plausible records', () {
      final records = DuressManagerService.generateDecoySeedRecords();
      expect(records, isNotEmpty);
      expect(records.length, greaterThanOrEqualTo(3));

      for (final rec in records) {
        expect(rec['id'], isNotEmpty);
        expect(rec['raw_value'], isNotEmpty);
        expect(rec['format'], equals('qrCode'));
        expect(rec['content_type'], isNotEmpty);
        expect(rec['threat_severity'], equals('clean'));
        expect(rec['created_at'], isA<int>());
        expect(rec['updated_at'], isA<int>());
        expect(rec['title'], isNotEmpty);
      }
    });
  });
}

