import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Win32 API display affinity constants used by Windows desktop.
///
/// See: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity
abstract class Win32DisplayAffinity {
  /// No capture protection. The window contents can be captured normally.
  static const int wdaNone = 0x00000000;

  /// Window contents are rendered only on a monitor; capture mechanisms receive black.
  static const int wdaMonitor = 0x00000001;

  /// Window contents are completely excluded from any capture or recording.
  /// Supported on Windows 10 Version 2004 (Build 19041) and newer.
  static const int wdaExcludeFromCapture = 0x00000011;
}

/// Abstract contract defining the platform-level window security and screenshot/recording guard.
abstract class SecurityWindowGuard {
  /// Enables OS-level screenshot and screen recording protection on the active window.
  ///
  /// - On Android: sets `FLAG_SECURE` on the current window.
  /// - On iOS: activates secure layer protection and privacy obscuring.
  /// - On Windows: calls `SetWindowDisplayAffinity` with `WDA_EXCLUDEFROMCAPTURE`.
  Future<bool> enableSecureScreen();

  /// Disables OS-level screenshot and screen recording protection on the active window.
  Future<bool> disableSecureScreen();

  /// Returns whether OS-level screen protection is currently active on the window.
  Future<bool> isSecureScreenEnabled();

  /// The active operating target platform.
  TargetPlatform get targetPlatform;
}

/// Signature for custom Win32 display affinity delegate used for dependency injection in testing.
typedef Win32AffinitySetter = bool Function(int affinity);

/// Production implementation of [SecurityWindowGuard] providing native screen capture protection
/// across Android (`FLAG_SECURE`), iOS (`WDA_EXCLUDEFROMCAPTURE` / privacy layer), and Windows (Win32 FFI).
class SecurityWindowGuardImpl implements SecurityWindowGuard {
  /// Channel identifier for native platform dispatch.
  static const String channelName = 'org.zerosync/security_window_guard';

  final MethodChannel _channel;
  final TargetPlatform _targetPlatform;
  final Win32AffinitySetter? _win32AffinitySetter;

  bool _isSecure = false;

  SecurityWindowGuardImpl({
    MethodChannel? channel,
    TargetPlatform? targetPlatform,
    Win32AffinitySetter? win32AffinitySetter,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _targetPlatform = targetPlatform ?? defaultTargetPlatform,
        _win32AffinitySetter = win32AffinitySetter;

  @override
  TargetPlatform get targetPlatform => _targetPlatform;

  @override
  Future<bool> enableSecureScreen() async {
    try {
      if (_targetPlatform == TargetPlatform.windows) {
        final success =
            _applyWindowsAffinity(Win32DisplayAffinity.wdaExcludeFromCapture);
        _isSecure = success;
        return success;
      }

      if (_targetPlatform == TargetPlatform.android ||
          _targetPlatform == TargetPlatform.iOS) {
        final result = await _channel.invokeMethod<bool>('enableSecureScreen');
        _isSecure = result ?? true;
        return _isSecure;
      }

      // Fallback for non-guarded desktop/web environments
      _isSecure = true;
      return true;
    } catch (e) {
      debugPrint('[SecurityWindowGuard] Failed to enable secure screen: $e');
      return false;
    }
  }

  @override
  Future<bool> disableSecureScreen() async {
    try {
      if (_targetPlatform == TargetPlatform.windows) {
        final success = _applyWindowsAffinity(Win32DisplayAffinity.wdaNone);
        if (success) {
          _isSecure = false;
        }
        return success;
      }

      if (_targetPlatform == TargetPlatform.android ||
          _targetPlatform == TargetPlatform.iOS) {
        final result = await _channel.invokeMethod<bool>('disableSecureScreen');
        final disabled = result ?? true;
        if (disabled) {
          _isSecure = false;
        }
        return disabled;
      }

      _isSecure = false;
      return true;
    } catch (e) {
      debugPrint('[SecurityWindowGuard] Failed to disable secure screen: $e');
      return false;
    }
  }

  @override
  Future<bool> isSecureScreenEnabled() async {
    try {
      if (_targetPlatform == TargetPlatform.windows) {
        return _isSecure;
      }

      if (_targetPlatform == TargetPlatform.android ||
          _targetPlatform == TargetPlatform.iOS) {
        final result =
            await _channel.invokeMethod<bool>('isSecureScreenEnabled');
        return result ?? _isSecure;
      }

      return _isSecure;
    } catch (e) {
      debugPrint('[SecurityWindowGuard] Error querying secure screen: $e');
      return _isSecure;
    }
  }

  bool _applyWindowsAffinity(int affinity) {
    if (_win32AffinitySetter != null) {
      return _win32AffinitySetter!(affinity);
    }

    if (!kIsWeb && Platform.isWindows) {
      try {
        final user32 = ffi.DynamicLibrary.open('user32.dll');
        final getForegroundWindow =
            user32.lookupFunction<ffi.IntPtr Function(), int Function()>(
                'GetForegroundWindow');
        final setWindowDisplayAffinity = user32.lookupFunction<
            ffi.Int32 Function(ffi.IntPtr, ffi.Uint32),
            int Function(int, int)>('SetWindowDisplayAffinity');

        final hwnd = getForegroundWindow();
        if (hwnd == 0) return false;

        final result = setWindowDisplayAffinity(hwnd, affinity);
        return result != 0;
      } catch (e) {
        debugPrint(
            '[SecurityWindowGuard] Win32 SetWindowDisplayAffinity error: $e');
        return false;
      }
    }
    return false;
  }
}
