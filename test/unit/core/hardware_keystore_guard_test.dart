import 'package:airdrop_qr/core/platform/hardware_keystore_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HardwareKeystoreGuard Platform Evaluation Specs', () {
    test('iOS evaluates to strongBoxOrSecureEnclave and enforces successfully',
        () async {
      final guard = HardwareKeystoreGuardImpl(
        targetPlatform: TargetPlatform.iOS,
      );

      final level = await guard.getSecurityLevel();
      expect(level, equals(HardwareSecurityLevel.strongBoxOrSecureEnclave));
      expect(await guard.isHardwareBackingAvailable(), isTrue);
      expect(() => guard.enforceHardwareSecurity(), returnsNormally);
    });

    test('Android evaluates to tee and enforces successfully', () async {
      final guard = HardwareKeystoreGuardImpl(
        targetPlatform: TargetPlatform.android,
      );

      final level = await guard.getSecurityLevel();
      expect(level, equals(HardwareSecurityLevel.tee));
      expect(await guard.isHardwareBackingAvailable(), isTrue);
      expect(() => guard.enforceHardwareSecurity(), returnsNormally);
    });

    test('Windows evaluates to windowsTpm and enforces successfully', () async {
      final guard = HardwareKeystoreGuardImpl(
        targetPlatform: TargetPlatform.windows,
      );

      final level = await guard.getSecurityLevel();
      expect(level, equals(HardwareSecurityLevel.windowsTpm));
      expect(await guard.isHardwareBackingAvailable(), isTrue);
      expect(() => guard.enforceHardwareSecurity(), returnsNormally);
    });

    test('Linux evaluates to software and throws StateError on enforcement',
        () async {
      final guard = HardwareKeystoreGuardImpl(
        targetPlatform: TargetPlatform.linux,
      );

      final level = await guard.getSecurityLevel();
      expect(level, equals(HardwareSecurityLevel.software));
      expect(await guard.isHardwareBackingAvailable(), isFalse);
      expect(
        () => guard.enforceHardwareSecurity(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

