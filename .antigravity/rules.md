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


---

## 3. GLOBAL AGENT RULES (v3.0 — ZERO-TOLERANCE OPERATIONAL GOVERNANCE)
1. **NO PLACEHOLDERS OR HARDCODED DEMO PAYLOADS:**
   - Never hardcode simulated progress metrics (`totalChunks: 32`, `progressPercentage: 100.0`, `transferSpeedKbps: 45.2`), fake scan records, or dummy strings into production widgets.
   - Never commit empty callback stubs (`onPressed: () {}`). Every UI action must wire to a real BLoC event or domain/platform use case.
2. **NO SECURITY COMPROMISES:**
   - Never bypass `LicenseVerifierService`, `EnterprisePolicyService`, `PayloadEncryptionService`, `DomainInspectorService`, or `SecureMemoryArena` zeroization.
3. **NO PLATFORM REGRESSIONS:**
   - All changes must maintain compilation and runtime parity across Android, Windows, Linux, macOS, and iOS. Desktop layouts must never expose non-functional mobile-only camera overlays when hardware is absent.
4. **NO UNTESTED CHANGES:**
   - Every new or modified BLoC, domain service, or presentation workspace must be accompanied by deterministic unit/widget tests verifying both idle startup states and active workflows.
5. **NO BREAKING CHANGES WITHOUT MIGRATION PLANS:**
   - Wire protocol headers (`ZSP1`), SQLCipher database schemas, and `.zslic` certificate formats must preserve backward compatibility or include an explicit versioned migration path.
6. **STRICT SINGLE-SUBPHASE SEQUENTIAL EXECUTION:**
   - Execute exactly ONE subphase at a time. Never overwrite existing contracts, rules, or agent definitions. Validate all 4 quality gates before marking any subphase complete.
