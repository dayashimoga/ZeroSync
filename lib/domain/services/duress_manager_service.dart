import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

/// Evaluation outcome when verifying an optical or vault access PIN.
enum PinAuthResult {
  /// Legitimate user authenticated to access primary secure vault.
  primaryAccess,

  /// User under duress entered panic PIN; decoy mode activated.
  duressPanicTriggered,

  /// PIN did not match primary or duress credentials.
  invalidPin,
}

/// Domain configuration defining primary and duress panic credentials.
class DuressSecurityConfig extends Equatable {
  final String primaryPinHash;
  final String duressPinHash;
  final bool autoScrubRealKeyOnDuress;

  const DuressSecurityConfig({
    required this.primaryPinHash,
    required this.duressPinHash,
    this.autoScrubRealKeyOnDuress = false,
  });

  /// Factory hashing plaintext PINs with SHA-256 before storing.
  factory DuressSecurityConfig.fromPlaintextPins({
    required String primaryPin,
    required String duressPin,
    bool autoScrubRealKeyOnDuress = false,
  }) {
    if (primaryPin.trim().isEmpty) {
      throw ArgumentError('Primary PIN cannot be empty');
    }
    if (duressPin.trim().isEmpty) {
      throw ArgumentError('Duress PIN cannot be empty');
    }
    if (primaryPin.trim() == duressPin.trim()) {
      throw ArgumentError('Duress PIN must be distinct from Primary PIN');
    }

    final primaryHash =
        sha256.convert(utf8.encode(primaryPin.trim())).toString();
    final duressHash = sha256.convert(utf8.encode(duressPin.trim())).toString();

    return DuressSecurityConfig(
      primaryPinHash: primaryHash,
      duressPinHash: duressHash,
      autoScrubRealKeyOnDuress: autoScrubRealKeyOnDuress,
    );
  }

  @override
  List<Object?> get props =>
      [primaryPinHash, duressPinHash, autoScrubRealKeyOnDuress];
}

/// Service managing panic duress detection, decoy database switching, and
/// plausible deniability under physical coercion.
class DuressManagerService {
  DuressSecurityConfig? _config;
  bool _isDuressActive = false;

  DuressManagerService({DuressSecurityConfig? config}) : _config = config;

  /// Whether the system is currently operating in decoy duress mode.
  bool get isDuressActive => _isDuressActive;

  /// Whether duress security has been configured.
  bool get isConfigured => _config != null;

  /// Active security configuration.
  DuressSecurityConfig? get config => _config;

  /// Configures or updates duress PIN credentials.
  void configure(DuressSecurityConfig config) {
    _config = config;
  }

  /// Evaluates an entered PIN against configured primary and duress credentials.
  PinAuthResult evaluatePin(String enteredPin) {
    if (_config == null) {
      throw StateError(
          'DuressManagerService has not been configured with PINs');
    }

    final enteredHash =
        sha256.convert(utf8.encode(enteredPin.trim())).toString();

    if (enteredHash == _config!.duressPinHash) {
      _isDuressActive = true;
      return PinAuthResult.duressPanicTriggered;
    }

    if (enteredHash == _config!.primaryPinHash) {
      _isDuressActive = false;
      return PinAuthResult.primaryAccess;
    }

    return PinAuthResult.invalidPin;
  }

  /// Manually resets duress state back to normal inactive mode.
  void resetDuressState() {
    _isDuressActive = false;
  }

  /// Manually activates duress mode (e.g. from an optical panic trigger datagram).
  void triggerDuressMode() {
    _isDuressActive = true;
  }

  /// Returns canonical decoy scan records seeded into the decoy database
  /// to provide realistic plausible deniability.
  static List<Map<String, dynamic>> generateDecoySeedRecords() {
    return [
      {
        'id': 'decoy-scan-wifi-001',
        'raw_value': 'WIFI:S:Guest_Network_5G;T:WPA;P:Welcome2026!;;',
        'raw_bytes': null,
        'format': 'qrCode',
        'content_type': 'wifi',
        'created_at': DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 1, 15).millisecondsSinceEpoch,
        'is_favorite': 1,
        'title': 'Coffee Shop Guest Wi-Fi',
        'notes': 'Public guest network configuration',
        'threat_severity': 'clean',
      },
      {
        'id': 'decoy-scan-vcard-002',
        'raw_value':
            'BEGIN:VCARD\nVERSION:4.0\nFN:Alex Taylor\nEMAIL:alex.taylor@example.com\nTEL:+1-555-0199\nEND:VCARD',
        'raw_bytes': null,
        'format': 'qrCode',
        'content_type': 'contact',
        'created_at': DateTime.utc(2026, 2, 20).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 2, 20).millisecondsSinceEpoch,
        'is_favorite': 0,
        'title': 'Alex Taylor Contact',
        'notes': 'Consulting business card',
        'threat_severity': 'clean',
      },
      {
        'id': 'decoy-scan-url-003',
        'raw_value': 'https://wikipedia.org/wiki/Air_gap_(networking)',
        'raw_bytes': null,
        'format': 'qrCode',
        'content_type': 'url',
        'created_at': DateTime.utc(2026, 3, 5).millisecondsSinceEpoch,
        'updated_at': DateTime.utc(2026, 3, 5).millisecondsSinceEpoch,
        'is_favorite': 0,
        'title': 'Air Gap Wikipedia Article',
        'notes': 'Reference documentation',
        'threat_severity': 'clean',
      },
    ];
  }
}
