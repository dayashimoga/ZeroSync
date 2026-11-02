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

# ZEROSYNC (AIRDROP-QR) — GLOBAL ENGINEERING CONTRACT (v3.0 ADDENDUM)
**Effective Date:** 2026-11-02  
**Governance Scope:** Unified Platform Architecture (Scanner, Generator, Air-Gapped Optical Transfer, Enterprise Policy & 5-Platform Native Parity)

## 3. CORE ENGINEERING PRINCIPLES & ANTI-PLACEHOLDER INVARIANTS
1. **ZERO PLACEHOLDERS OR HARDCODED DEMO TELEMETRY:**
   - NEVER instantiate UI widgets with fabricated, static, or hardcoded telemetry (e.g., hardcoded `totalChunks: 32`, `progressPercentage: 100.0`, `transferSpeedKbps: 45.2`, or dummy strings).
   - NEVER ship dead callbacks (`onPressed: () {}`) in production widgets. Every interactive control MUST dispatch a typed `Bloc` event or invoke a verified domain/platform service.
   - All session telemetry MUST initialize to a deterministic idle state (`TransferProgressMetrics.initial()`, `0 / 0 Chunks`, `0.0%`, `Idle / Ready`) until real frame headers or file payloads are processed.
2. **FULL DOMAIN-TO-PRESENTATION WIRING:**
   - Every domain service in `lib/domain/services/` MUST be reachable from the Presentation layer via dedicated BLoCs/Cubits and user-accessible workspaces (`Scanner`, `Generator`, `Optical Transfer`, `Encrypted Vault`, `Enterprise Policy & Licensing`).
3. **FIVE-PLATFORM CONSISTENCY & NATIVE UX (ANDROID, WINDOWS, LINUX, MACOS, iOS):**
   - Desktop targets (`Windows`, `Linux`, `macOS`) and wide tablets ($\ge 720\text{dp}$) MUST render an ergonomic `NavigationRail` + split-pane workspace with keyboard shortcuts (`Ctrl+1..5`, `Ctrl+O`, `Ctrl+S`), hiding mobile-only hardware controls (Torch, Camera Flip) when unsupported by the host hardware.
   - Mobile targets (`Android`, `iOS` $< 720\text{dp}$) MUST render a persistent `NavigationBar` with `IndexedStack` preservation.
4. **SPEC-DRIVEN & TEST-DRIVEN DEVELOPMENT (TDD):**
   - No feature or UI workspace may be merged without unit tests (BLoC/Domain) and widget tests verifying initial idle states, active transitions, error states, and license/policy enforcement.
5. **NON-BREAKING INCREMENTAL EVOLUTION:**
   - Existing contracts (`contracts/*`), agent rules (`.antigravity/rules.md`), and agent skills (`.antigravity/skills/*`, `.agent/skills/*`) MUST NEVER be overwritten or deleted; all evolutions are strictly additive.

## 4. NON-FUNCTIONAL REQUIREMENTS (NFRs)
- **Security:** 0 network permissions (`INTERNET`, `ACCESS_NETWORK_STATE`), XChaCha20-Poly1305 AEAD encryption, Argon2id KDF, Ed25519 offline `.zslic` verification, SQLCipher AES-256 storage, FFI `SecureMemoryArena` zeroization within $< 1\text{ms}$ of disposal.
- **Performance:** $\le 8\text{ms}$ frame render budget (120 FPS capable UI thread), $100\%$ of LT Fountain encoding/decoding and image matrix decoding offloaded to background `Isolate` workers via `TransferableTypedData`.
- **Resource Footprint:** Idle CPU $< 1\%$ on desktop/mobile when camera sensor is paused; baseline RAM footprint $< 85\text{MB}$; zero memory leaks across 10,000-frame optical soak sessions.
- **Accessibility:** WCAG 2.1 AAA high-contrast OLED token compliance ($\ge 7:1$ contrast ratio), full screen-reader `Semantics` tree (`AccessibleQrSemantics`), keyboard navigation, and RTL support (`en`, `es`, `ar`).

## 5. DEFINITION OF DONE (DoD) & RELEASE CRITERIA
A Subphase is considered `COMPLETED` only when ALL of the following objective gates pass with zero errors:
1. **Formatting Gate:** `dart format --output=none --set-exit-if-changed lib/ test/ tool/`
2. **Static Analysis Gate:** `dart analyze --fatal-infos --fatal-warnings`
3. **Air-Gap, Clean Architecture & Anti-Placeholder AST Gate:** `dart run tool/verify_airgap.dart`
4. **Automated Test & Coverage Gate:** `flutter test` ($100\%$ pass rate, $\ge 85\%$ domain coverage, zero placeholder/dead-callback regressions)
5. **State & Tracker Synchronization:** Subphase status updated in `contracts/STAGED_EXECUTION_TRACKER.md` and `.project_state.json` with atomic Git commit.

## 6. ADAPTIVE MULTI-MODAL TRANSPORT & TOPOLOGY GOVERNANCE (v3.1 ADDENDUM)
1. **INTELLIGENT TRANSPORT RECOMMENDATION ENGINE (`TransportAdvisorService`):**
   - Automatically evaluate payload size, Shannon entropy, security policy posture (`strictOpticalScif`, `proximityHybridOob`, `enterpriseLocalLan`), hardware capabilities, and topology (`1:1`, `1:N` multicast fountain broadcast, `M:N` mesh, simultaneous multi-device) to recommend the optimal transport mode:
     - *Offline Air-Gapped Optical Modes:* Standard Animated QR Streaming, High-Speed RGB 3-Channel QR Burst Mode, Static Segmented QR Deck.
     - *Hybrid Proximity & Local Modes (Policy-Gated, Offline Zero-Internet):* Hybrid QR + Wi-Fi Direct, Hybrid QR + Bluetooth BLE, Local Wi-Fi / LAN Peer Transfer (using QR for out-of-band X25519 key exchange & SHA-256 manifest verification while keeping `AndroidManifest.xml` 100% free of `android.permission.INTERNET` in strict air-gap builds).
2. **RESUMABLE CHECKPOINTS, ADAPTIVE COMPRESSION & BENCHMARKING:**
   - All multi-chunk transfers MUST support deterministic checkpoint serialization (`TransferCheckpointService`) to resume interrupted sessions from the exact chunk index.
   - All payloads MUST pass through Shannon-entropy-aware `AdaptiveCompressionService` prior to XChaCha20-Poly1305 encryption and Castagnoli CRC-32C / SHA-256 integrity validation.
   - Real-time benchmarking (`TransferBenchmarkService`) MUST profile encode/decode goodput and auto-tune QR density and FPS pacing.
