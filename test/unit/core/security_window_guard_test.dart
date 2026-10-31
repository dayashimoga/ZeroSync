import 'package:airdrop_qr/core/platform/security_window_guard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityWindowGuard Android & iOS MethodChannel Specs', () {
    const channelName = SecurityWindowGuardImpl.channelName;
    final List<MethodCall> methodCalls = [];
    bool channelSecureState = false;
    bool shouldThrow = false;

    setUp(() {
      methodCalls.clear();
      channelSecureState = false;
      shouldThrow = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(channelName),
        (MethodCall call) async {
          if (shouldThrow) {
            throw PlatformException(
              code: 'UNAVAILABLE',
              message: 'Window manager not accessible',
            );
          }
          methodCalls.add(call);
          switch (call.method) {
            case 'enableSecureScreen':
              channelSecureState = true;
              return true;
            case 'disableSecureScreen':
              channelSecureState = false;
              return true;
            case 'isSecureScreenEnabled':
              return channelSecureState;
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test('Android enables and disables FLAG_SECURE via method channel',
        () async {
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.android,
      );

      expect(guard.targetPlatform, equals(TargetPlatform.android));

      final enableResult = await guard.enableSecureScreen();
      expect(enableResult, isTrue);
      expect(methodCalls.last.method, equals('enableSecureScreen'));

      final isSecure = await guard.isSecureScreenEnabled();
      expect(isSecure, isTrue);

      final disableResult = await guard.disableSecureScreen();
      expect(disableResult, isTrue);
      expect(methodCalls.last.method, equals('disableSecureScreen'));

      final isSecureAfter = await guard.isSecureScreenEnabled();
      expect(isSecureAfter, isFalse);
    });

    test('iOS invokes platform channel and tracks state', () async {
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.iOS,
      );

      expect(guard.targetPlatform, equals(TargetPlatform.iOS));

      final enableResult = await guard.enableSecureScreen();
      expect(enableResult, isTrue);
      expect(methodCalls.last.method, equals('enableSecureScreen'));

      final disableResult = await guard.disableSecureScreen();
      expect(disableResult, isTrue);
      expect(methodCalls.last.method, equals('disableSecureScreen'));
    });

    test('Recovers gracefully on platform channel exception without crash',
        () async {
      shouldThrow = true;
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.android,
      );

      final enableResult = await guard.enableSecureScreen();
      expect(enableResult, isFalse);

      final disableResult = await guard.disableSecureScreen();
      expect(disableResult, isFalse);
    });
  });

  group('SecurityWindowGuard Windows Win32 FFI & Affinity Specs', () {
    test('Windows invokes affinity delegate with WDA_EXCLUDEFROMCAPTURE',
        () async {
      int? capturedAffinity;
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.windows,
        win32AffinitySetter: (affinity) {
          capturedAffinity = affinity;
          return true;
        },
      );

      expect(guard.targetPlatform, equals(TargetPlatform.windows));

      final enableSuccess = await guard.enableSecureScreen();
      expect(enableSuccess, isTrue);
      expect(
          capturedAffinity, equals(Win32DisplayAffinity.wdaExcludeFromCapture));
      expect(await guard.isSecureScreenEnabled(), isTrue);

      final disableSuccess = await guard.disableSecureScreen();
      expect(disableSuccess, isTrue);
      expect(capturedAffinity, equals(Win32DisplayAffinity.wdaNone));
      expect(await guard.isSecureScreenEnabled(), isFalse);
    });

    test('Windows returns false if affinity delegate fails', () async {
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.windows,
        win32AffinitySetter: (affinity) => false,
      );

      final enableSuccess = await guard.enableSecureScreen();
      expect(enableSuccess, isFalse);
      expect(await guard.isSecureScreenEnabled(), isFalse);
    });
  });

  group('SecurityWindowGuard Fallback Platform Specs', () {
    test('Fallback platforms track secure state locally', () async {
      final guard = SecurityWindowGuardImpl(
        targetPlatform: TargetPlatform.linux,
      );

      expect(await guard.enableSecureScreen(), isTrue);
      expect(await guard.isSecureScreenEnabled(), isTrue);
      expect(await guard.disableSecureScreen(), isTrue);
      expect(await guard.isSecureScreenEnabled(), isFalse);
    });
  });
}
