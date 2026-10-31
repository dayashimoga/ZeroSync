# ZEROSYNC (AIRDROP-QR) — GLOBAL ENGINEERING CONTRACT (v2.0)

## 1. INVIOLABLE SECURITY & AIR-GAP INVARIANTS
1. **ZERO NETWORK SURFACE:**
   - NEVER add `android.permission.INTERNET` or `ACCESS_NETWORK_STATE` to any `AndroidManifest.xml`.
   - NEVER import `http`, `dio`, `web_socket_channel`, or invoke `dart:io` `Socket`, `ServerSocket`, `HttpClient`, or `RawDatagramSocket` in `lib/`.
   - All dependencies in `pubspec.yaml` MUST function 100% offline with zero telemetry.
2. **CLEAN ARCHITECTURE LAYER ISOLATION:**
   - `lib/domain/` MUST be 100% Pure Dart (+ `dart:ffi` for native memory zeroization). ZERO imports of `package:flutter/*`, platform channels, or `lib/data/*` / `lib/presentation/*`.
   - `lib/data/` implements `lib/domain/` repository and datasource interfaces.
   - `lib/presentation/` communicates with `lib/domain/` strictly via BLoCs and immutable Value Objects / Entities.
3. **CRYPTOGRAPHIC & MEMORY HYGIENE:**
   - All cryptographic keys, raw seed phrases, and decrypted payloads MUST reside in native FFI `Pointer<Uint8>` buffers or explicitly tracked `Uint8List` buffers registered with `DisposalAuditor`.
   - Buffers MUST be overwritten with `0x00` and verified before scope exit.
4. **CROSS-PLATFORM PARITY (ANDROID, iOS, WINDOWS):**
   - Every native feature (Camera ingestion, SQLCipher Hardware Keystore, Screen Capture Prevention) MUST provide concrete implementations for Android (Kotlin), iOS (Swift), and Windows (C++ Win32) behind a unified platform interface in `lib/core/platform/`.

## 2. MANDATORY QUALITY GATES (ZERO-TOLERANCE)
Before marking any Subphase complete, the Agent MUST run and pass:
1. `dart format --output=none --set-exit-if-changed lib/ test/`
2. `dart analyze --fatal-infos --fatal-warnings`
3. `dart run tool/verify_airgap.dart`
4. `flutter test` (100% pass rate, >= 85% domain coverage)
