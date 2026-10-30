import 'package:flutter/widgets.dart';

/// Supported locales across ZeroSync.
enum ZeroSyncLocale {
  en('en', 'English', TextDirection.ltr),
  ar('ar', 'العربية', TextDirection.rtl),
  es('es', 'Español', TextDirection.ltr);

  final String languageCode;
  final String displayName;
  final TextDirection direction;

  const ZeroSyncLocale(this.languageCode, this.displayName, this.direction);

  bool get isRtl => direction == TextDirection.rtl;

  static ZeroSyncLocale fromLanguageCode(String code) {
    return ZeroSyncLocale.values.firstWhere(
      (l) => l.languageCode.toLowerCase() == code.toLowerCase(),
      orElse: () => ZeroSyncLocale.en,
    );
  }
}

/// Strongly-typed string container providing zero-allocation localized access
/// across supported LTR and RTL locales.
class ZeroSyncStrings {
  final String appTitle;
  final String scannerTabTitle;
  final String vaultTabTitle;
  final String transferTabTitle;
  final String settingsTabTitle;
  final String scannerAimingGuidance;
  final String scannerSuspendedMessage;
  final String scanSuccessTitle;
  final String Function(int count) batchScanCounter;
  final String Function(int percent, int current, int total)
      streamTransferProgress;
  final String streamVerificationSuccess;
  final String securityThreatDetected;
  final String offlineAirGapGuaranteed;

  const ZeroSyncStrings({
    required this.appTitle,
    required this.scannerTabTitle,
    required this.vaultTabTitle,
    required this.transferTabTitle,
    required this.settingsTabTitle,
    required this.scannerAimingGuidance,
    required this.scannerSuspendedMessage,
    required this.scanSuccessTitle,
    required this.batchScanCounter,
    required this.streamTransferProgress,
    required this.streamVerificationSuccess,
    required this.securityThreatDetected,
    required this.offlineAirGapGuaranteed,
  });

  static const ZeroSyncStrings en = ZeroSyncStrings(
    appTitle: 'ZeroSync AirDrop-QR',
    scannerTabTitle: 'Scanner',
    vaultTabTitle: 'Vault',
    transferTabTitle: 'ZeroSync Transfer',
    settingsTabTitle: 'Settings',
    scannerAimingGuidance: 'Align QR or Barcode inside the optical reticle',
    scannerSuspendedMessage:
        'Camera suspended due to inactivity. Tap screen to resume.',
    scanSuccessTitle: 'Code Decoded',
    batchScanCounter: _enBatchCounter,
    streamTransferProgress: _enStreamProgress,
    streamVerificationSuccess:
        'Cryptographic file verification successful. SHA-256 integrity matched.',
    securityThreatDetected: 'Malicious URL or security threat blocked!',
    offlineAirGapGuaranteed:
        'Zero network permissions active. 100% offline air-gapped security.',
  );

  static const ZeroSyncStrings ar = ZeroSyncStrings(
    appTitle: 'زيرو سينك AirDrop-QR',
    scannerTabTitle: 'الماسح الضوئي',
    vaultTabTitle: 'الخزنة',
    transferTabTitle: 'نقل زيرو سينك',
    settingsTabTitle: 'الإعدادات',
    scannerAimingGuidance: 'قم بمحاذاة الرمز داخل إطار الشبكة البصرية',
    scannerSuspendedMessage:
        'تم إيقاف الكاميرا مؤقتًا بسبب الخمول. انقر على الشاشة للاستئناف.',
    scanSuccessTitle: 'تم فك تشفير الرمز',
    batchScanCounter: _arBatchCounter,
    streamTransferProgress: _arStreamProgress,
    streamVerificationSuccess:
        'نجح التحقق الأمني من الملف. تطابقت سلامة SHA-256.',
    securityThreatDetected: 'تم حظر رابط ضار أو تهديد أمني!',
    offlineAirGapGuaranteed:
        'أذونات الشبكة معطلة بالكامل. أمان معزول دون اتصال بنسبة 100٪.',
  );

  static const ZeroSyncStrings es = ZeroSyncStrings(
    appTitle: 'ZeroSync AirDrop-QR',
    scannerTabTitle: 'Escáner',
    vaultTabTitle: 'Bóveda',
    transferTabTitle: 'Transferencia ZeroSync',
    settingsTabTitle: 'Ajustes',
    scannerAimingGuidance: 'Alinee el código dentro de la retícula óptica',
    scannerSuspendedMessage:
        'Cámara suspendida por inactividad. Toque la pantalla para reanudar.',
    scanSuccessTitle: 'Código Decodificado',
    batchScanCounter: _esBatchCounter,
    streamTransferProgress: _esStreamProgress,
    streamVerificationSuccess:
        'Verificación criptográfica exitosa. Coincidencia de integridad SHA-256.',
    securityThreatDetected: '¡URL maliciosa o amenaza de seguridad bloqueada!',
    offlineAirGapGuaranteed:
        'Cero permisos de red activos. Seguridad 100% aislada fuera de línea.',
  );

  static String _enBatchCounter(int count) => 'Captured Items: $count';
  static String _enStreamProgress(int percent, int current, int total) =>
      'Receiving stream: $percent% ($current of $total chunks)';

  static String _arBatchCounter(int count) => 'العناصر الملتقطة: $count';
  static String _arStreamProgress(int percent, int current, int total) =>
      'جارٍ استقبال التدفق: $percent٪ ($current من $total قطعة)';

  static String _esBatchCounter(int count) => 'Elementos Capturados: $count';
  static String _esStreamProgress(int percent, int current, int total) =>
      'Recibiendo transmisión: $percent% ($current de $total fragmentos)';

  static ZeroSyncStrings of(ZeroSyncLocale locale) {
    switch (locale) {
      case ZeroSyncLocale.en:
        return en;
      case ZeroSyncLocale.ar:
        return ar;
      case ZeroSyncLocale.es:
        return es;
    }
  }
}
