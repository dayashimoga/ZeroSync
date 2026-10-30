import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:airdrop_qr/core/localization/zerosync_localization.dart';

void main() {
  group('ZeroSyncLocalizations & ARB Structure Specs', () {
    test('Resolves supported locales and detects text direction (LTR vs RTL)',
        () {
      expect(ZeroSyncLocale.en.direction, equals(TextDirection.ltr));
      expect(ZeroSyncLocale.en.isRtl, isFalse);

      expect(ZeroSyncLocale.ar.direction, equals(TextDirection.rtl));
      expect(ZeroSyncLocale.ar.isRtl, isTrue);

      expect(ZeroSyncLocale.es.direction, equals(TextDirection.ltr));
      expect(ZeroSyncLocale.es.isRtl, isFalse);

      expect(ZeroSyncLocale.fromLanguageCode('en'), equals(ZeroSyncLocale.en));
      expect(ZeroSyncLocale.fromLanguageCode('ar'), equals(ZeroSyncLocale.ar));
      expect(ZeroSyncLocale.fromLanguageCode('es'), equals(ZeroSyncLocale.es));
      expect(ZeroSyncLocale.fromLanguageCode('unknown'),
          equals(ZeroSyncLocale.en));
    });

    test('Validates English (LTR) string localization and parameter formatting',
        () {
      final strings = ZeroSyncStrings.of(ZeroSyncLocale.en);

      expect(strings.appTitle, equals('ZeroSync AirDrop-QR'));
      expect(strings.scannerTabTitle, equals('Scanner'));
      expect(strings.vaultTabTitle, equals('Vault'));
      expect(strings.batchScanCounter(12), equals('Captured Items: 12'));
      expect(
        strings.streamTransferProgress(75, 15, 20),
        equals('Receiving stream: 75% (15 of 20 chunks)'),
      );
      expect(strings.streamVerificationSuccess.isNotEmpty, isTrue);
      expect(strings.securityThreatDetected.isNotEmpty, isTrue);
      expect(strings.offlineAirGapGuaranteed.isNotEmpty, isTrue);
    });

    test('Validates Arabic (RTL) string localization and parameter formatting',
        () {
      final strings = ZeroSyncStrings.of(ZeroSyncLocale.ar);

      expect(strings.appTitle, contains('زيرو سينك'));
      expect(strings.scannerTabTitle, equals('الماسح الضوئي'));
      expect(strings.vaultTabTitle, equals('الخزنة'));
      expect(strings.batchScanCounter(7), equals('العناصر الملتقطة: 7'));
      expect(
        strings.streamTransferProgress(50, 10, 20),
        contains('50٪'),
      );
      expect(strings.offlineAirGapGuaranteed, contains('100٪'));
    });

    test('Validates Spanish (LTR) string localization and parameter formatting',
        () {
      final strings = ZeroSyncStrings.of(ZeroSyncLocale.es);

      expect(strings.scannerTabTitle, equals('Escáner'));
      expect(strings.vaultTabTitle, equals('Bóveda'));
      expect(strings.batchScanCounter(3), equals('Elementos Capturados: 3'));
      expect(
        strings.streamTransferProgress(100, 20, 20),
        equals('Recibiendo transmisión: 100% (20 de 20 fragmentos)'),
      );
      expect(strings.offlineAirGapGuaranteed, contains('100%'));
    });
  });
}
