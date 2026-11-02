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
  String get generatorTabTitle => 'Generator';

  @override
  String get transferTabTitle => 'Optical Transfer';

  @override
  String get vaultTabTitle => 'Encrypted Vault';

  @override
  String get enterpriseTabTitle => 'Enterprise Policy';

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

  @override
  String get cameraScannerTitle => 'Real-Time Camera Scanner';

  @override
  String get imageScannerTitle => 'Image & File Preprocessor';

  @override
  String get batchScannerTitle => 'Batch Continuous Scanner';

  @override
  String get standardGeneratorTitle => 'Universal QR Generator';

  @override
  String get advancedStylerTitle => 'Advanced QR Styler & Vector Studio';

  @override
  String get enterpriseStudioTitle => 'Enterprise Cryptographic Studio';

  @override
  String get transmitterModeTitle => 'Visual ZeroSync Transmitter';

  @override
  String get receiverModeTitle => 'Visual ZeroSync Receiver';

  @override
  String get duressPanicTitle => 'Duress Panic Guard & Decoy Mode';

  @override
  String get offlineTrialTitle => '14-Day Offline Enterprise Trial';
}
