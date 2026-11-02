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
  String get generatorTabTitle => 'Generador';

  @override
  String get transferTabTitle => 'Transferencia Óptica';

  @override
  String get vaultTabTitle => 'Bóveda Cifrada';

  @override
  String get enterpriseTabTitle => 'Políticas Empresariales';

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

  @override
  String get cameraScannerTitle => 'Escáner de Cámara en Tiempo Real';

  @override
  String get imageScannerTitle => 'Preprocesador de Imágenes y Archivos';

  @override
  String get batchScannerTitle => 'Escáner Continuo por Lotes';

  @override
  String get standardGeneratorTitle => 'Generador Universal de QR';

  @override
  String get advancedStylerTitle => 'Estilizador Avanzado y Estudio Vectorial';

  @override
  String get enterpriseStudioTitle => 'Estudio Criptográfico Empresarial';

  @override
  String get transmitterModeTitle => 'Transmisor Óptico ZeroSync';

  @override
  String get receiverModeTitle => 'Receptor Óptico ZeroSync';

  @override
  String get duressPanicTitle => 'Protección contra Coacción y Modo Señuelo';

  @override
  String get offlineTrialTitle =>
      'Prueba Empresarial Fuera de Línea de 14 Días';
}
