// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ZeroSync AirDrop-QR';

  @override
  String get scannerTabTitle => 'Scanner';

  @override
  String get vaultTabTitle => 'Vault';

  @override
  String get transferTabTitle => 'ZeroSync Transfer';

  @override
  String get settingsTabTitle => 'Settings';

  @override
  String get scannerAimingGuidance =>
      'Align QR or Barcode inside the optical reticle';

  @override
  String get scannerSuspendedMessage =>
      'Camera suspended due to inactivity. Tap screen to resume.';

  @override
  String get scanSuccessTitle => 'Code Decoded';

  @override
  String batchScanCounter(int count) {
    return 'Captured Items: $count';
  }

  @override
  String streamTransferProgress(int percent, int current, int total) {
    return 'Receiving stream: $percent% ($current of $total chunks)';
  }

  @override
  String get streamVerificationSuccess =>
      'Cryptographic file verification successful. SHA-256 integrity matched.';

  @override
  String get securityThreatDetected =>
      'Malicious URL or security threat blocked!';

  @override
  String get offlineAirGapGuaranteed =>
      'Zero network permissions active. 100% offline air-gapped security.';
}
