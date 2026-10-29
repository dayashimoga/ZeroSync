// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'زيرو سينك AirDrop-QR';

  @override
  String get scannerTabTitle => 'الماسح الضوئي';

  @override
  String get vaultTabTitle => 'الخزنة';

  @override
  String get transferTabTitle => 'نقل زيرو سينك';

  @override
  String get settingsTabTitle => 'الإعدادات';

  @override
  String get scannerAimingGuidance =>
      'قم بمحاذاة الرمز داخل إطار الشبكة البصرية';

  @override
  String get scannerSuspendedMessage =>
      'تم إيقاف الكاميرا مؤقتًا بسبب الخمول. انقر على الشاشة للاستئناف.';

  @override
  String get scanSuccessTitle => 'تم فك تشفير الرمز';

  @override
  String batchScanCounter(int count) {
    return 'العناصر الملتقطة: $count';
  }

  @override
  String streamTransferProgress(int percent, int current, int total) {
    return 'جارٍ استقبال التدفق: $percent٪ ($current من $total قطعة)';
  }

  @override
  String get streamVerificationSuccess =>
      'نجح التحقق الأمني من الملف. تطابقت سلامة SHA-256.';

  @override
  String get securityThreatDetected => 'تم حظر رابط ضار أو تهديد أمني!';

  @override
  String get offlineAirGapGuaranteed =>
      'أذونات الشبكة معطلة بالكامل. أمان معزول دون اتصال بنسبة 100٪.';
}
