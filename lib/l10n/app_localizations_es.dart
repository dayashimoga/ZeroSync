// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'ZeroSync AirDrop-QR';

  @override
  String get scannerTabTitle => 'Escáner';

  @override
  String get vaultTabTitle => 'Bóveda';

  @override
  String get transferTabTitle => 'Transferencia ZeroSync';

  @override
  String get settingsTabTitle => 'Ajustes';

  @override
  String get scannerAimingGuidance =>
      'Alinee el código dentro de la retícula óptica';

  @override
  String get scannerSuspendedMessage =>
      'Cámara suspendida por inactividad. Toque la pantalla para reanudar.';

  @override
  String get scanSuccessTitle => 'Código Decodificado';

  @override
  String batchScanCounter(int count) {
    return 'Elementos Capturados: $count';
  }

  @override
  String streamTransferProgress(int percent, int current, int total) {
    return 'Recibiendo transmisión: $percent% ($current de $total fragmentos)';
  }

  @override
  String get streamVerificationSuccess =>
      'Verificación criptográfica exitosa. Coincidencia de integridad SHA-256.';

  @override
  String get securityThreatDetected =>
      '¡URL maliciosa o amenaza de seguridad bloqueada!';

  @override
  String get offlineAirGapGuaranteed =>
      'Cero permisos de red activos. Seguridad 100% aislada fuera de línea.';
}
