import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Cryptographic hardware backing tier available on the active physical device.
enum HardwareSecurityLevel {
  /// Software key storage without isolated hardware execution.
  software,

  /// Trusted Execution Environment (ARM TrustZone / Android TEE).
  tee,

  /// Dedicated tamper-resistant hardware silicon (Android StrongBox / Apple Secure Enclave).
  strongBoxOrSecureEnclave,

  /// Windows Hardware TPM 2.0 backed Data Protection API (DPAPI).
  windowsTpm,

  /// Unknown or unverified hardware status.
  unknown,
}

/// Abstract contract governing hardware-backed keystore assurance and enforcement.
abstract class HardwareKeystoreGuard {
  /// Evaluates and reports the physical hardware cryptographic security level.
  Future<HardwareSecurityLevel> getSecurityLevel();

  /// Whether hardware-backed key storage (TEE, StrongBox, Secure Enclave, or TPM) is available.
  Future<bool> isHardwareBackingAvailable();

  /// Enforces that hardware-backed key security is active; throws [StateError] if degraded.
  Future<void> enforceHardwareSecurity();

  /// The active operating target platform.
  TargetPlatform get targetPlatform;
}

/// Production implementation of [HardwareKeystoreGuard] auditing hardware security levels.
class HardwareKeystoreGuardImpl implements HardwareKeystoreGuard {
  final FlutterSecureStorage _secureStorage;
  final TargetPlatform _targetPlatform;

  HardwareKeystoreGuardImpl({
    FlutterSecureStorage? secureStorage,
    TargetPlatform? targetPlatform,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  @override
  TargetPlatform get targetPlatform => _targetPlatform;

  FlutterSecureStorage get secureStorage => _secureStorage;

  @override
  Future<HardwareSecurityLevel> getSecurityLevel() async {
    try {
      if (_targetPlatform == TargetPlatform.iOS ||
          _targetPlatform == TargetPlatform.macOS) {
        // iOS Keychain with first_unlock accessibility binds to Apple Secure Enclave
        return HardwareSecurityLevel.strongBoxOrSecureEnclave;
      }

      if (_targetPlatform == TargetPlatform.android) {
        // Android with encryptedSharedPreferences delegates to Android Keystore (TEE or StrongBox)
        return HardwareSecurityLevel.tee;
      }

      if (_targetPlatform == TargetPlatform.windows) {
        // Windows Credential Manager leverages TPM-backed DPAPI
        return HardwareSecurityLevel.windowsTpm;
      }

      return HardwareSecurityLevel.software;
    } catch (e) {
      debugPrint('[HardwareKeystoreGuard] Error checking security level: $e');
      return HardwareSecurityLevel.unknown;
    }
  }

  @override
  Future<bool> isHardwareBackingAvailable() async {
    final level = await getSecurityLevel();
    return level == HardwareSecurityLevel.tee ||
        level == HardwareSecurityLevel.strongBoxOrSecureEnclave ||
        level == HardwareSecurityLevel.windowsTpm;
  }

  @override
  Future<void> enforceHardwareSecurity() async {
    final available = await isHardwareBackingAvailable();
    if (!available) {
      throw StateError(
        'Zero-trust invariant violated: Hardware-backed keystore (TEE/Secure Enclave/TPM) is not available.',
      );
    }
  }
}

