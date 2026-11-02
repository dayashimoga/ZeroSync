# ZEROSYNC (AIRDROP-QR) — STAGED EXECUTION TRACKER

**Master Plan Version:** v2.0 (First-Time-Right)  
**Tracking Invariant:** One subphase executed, verified, and audited at a time. All 4 quality gates must pass before marking a subphase `COMPLETED`.

---

## Progress Dashboard

| Stage | Total Subphases | Completed | Status |
|:---|:---:|:---:|:---|
| **Stage 1: Android Build Recovery & Air-Gap Gate** | 3 | 3 | 🟢 COMPLETED |
| **Stage 2: Core Protocol Engine v2 & Isolates** | 3 | 3 | 🟢 COMPLETED |
| **Stage 3: Zero-Trust Security, FFI & Crypto** | 4 | 4 | 🟢 COMPLETED |
| **Stage 4: Windows, iOS & Android Hardware Parity** | 2 | 2 | 🟢 COMPLETED |
| **Stage 5: UX, DevSecOps Tools & Release Matrix** | 3 | 3 | 🟢 COMPLETED |
| **Total** | **15** | **15** | **100% Completed** |

---

## Stage Breakdown & Subphase Status

### STAGE 1: Android Build Recovery, Toolchain Hardening & CI Air-Gap Gate
- [x] **Phase 1.1: Gradle Kotlin DSL & Flutter Plugin Resolution Fix**
  - [x] **Subphase 1.1.1:** Fix `android/settings.gradle.kts` & `android/build.gradle.kts` (Resilient `flutterSdkPath` resolver, fallback to `FLUTTER_ROOT`, `compileSdk = 34`, `flutter { source = "../.." }`). `[COMPLETED]`
  - [x] **Subphase 1.1.2:** Harden `.github/workflows/build-android.yml` (Analytics opt-out, explicit `flutter.sdk=$FLUTTER_ROOT` injection, deterministic SHA-256 sums). `[COMPLETED]`
- [x] **Phase 1.2: Multi-Platform Air-Gap AST & Manifest Gate**
  - [x] **Subphase 1.2.1:** Build `tool/verify_airgap.dart` Static Analyzer and wire into `.github/workflows/quality-gate.yml`. `[COMPLETED]`

---

### STAGE 2: Core Protocol Engine v2 & Isolate Acceleration
- [x] **Phase 2.1: 20-Byte Wire Header & Per-Droplet CRC-32C Validation**
  - [x] **Subphase 2.1.1:** Upgrade `TransportHeader` Value Object to 20 bytes (CRC-32C, encryption flag, RGB color mode). `[COMPLETED]`
  - [x] **Subphase 2.1.2:** Graph Peeling Poisoning Protection & Early Termination in `ChunkAccumulatorEngine`. `[COMPLETED]`
- [x] **Phase 2.2: Zero-Copy Worker Isolate Pipeline**
  - [x] **Subphase 2.2.1:** Background `FountainCodecIsolate` Service with `TransferableTypedData`. `[COMPLETED]`

---

### STAGE 3: Zero-Trust Security, Native FFI Scrubbing & Encrypted Optical Channel
- [x] **Phase 3.1: Native FFI Secure Buffer & DisposalAuditor v2**
  - [x] **Subphase 3.1.1:** `SecureMemoryArena` via `dart:ffi` (`calloc<Uint8>`, byte wiping barrier, zero-state tests). `[COMPLETED]`
- [x] **Phase 3.2: Encrypted Optical Transport & ECDH / Passcode Handshake**
  - [x] **Subphase 3.2.1:** XChaCha20-Poly1305 Payload Encryption Service with Argon2id & ephemeral X25519. `[COMPLETED]`
- [x] **Phase 3.3: Air-Gapped Ed25519 Licensing & Duress Vault Protection**
  - [x] **Subphase 3.3.1:** Offline `.zslic` License Verifier & Feature Gate (Ed25519 public key pinning). `[COMPLETED]`
  - [x] **Subphase 3.3.2:** Duress Panic PIN & Decoy SQLCipher Database mount. `[COMPLETED]`

---

### STAGE 4: Windows, iOS & Android Native Platform Parity
- [x] **Phase 4.1: Unified Cross-Platform Hardware Keystore & Screen Guard**
  - [x] **Subphase 4.1.1:** Native `SecurityWindowGuard` (`FLAG_SECURE`, `WDA_EXCLUDEFROMCAPTURE`, Secure Enclave). `[COMPLETED]`
- [x] **Phase 4.2: Windows, iOS & Android High-Speed Camera Ingestion Pipeline**
  - [x] **Subphase 4.2.1:** Abstracted Multi-Platform `OpticalCameraDatasource` (MobileScanner + Windows FFI ZXing). `[COMPLETED]`

---

### STAGE 5: High-Speed Optical UX, Air-Gapped Crypto Suite & Release Packaging
- [x] **Phase 5.1: RGB Color-Multiplexed QR & Adaptive Frame Pacing**
  - [x] **Subphase 5.1.1:** RGB 3-Channel `CustomPainter` & Receiver Channel Splitter (3x throughput). `[COMPLETED]`
- [x] **Phase 5.2: Air-Gapped DevSecOps & Cryptographic Tooling Entities**
  - [x] **Subphase 5.2.1:** Binary File Chunker, SLIP-39 Shamir Split & Forensic PDF/JSON Export. `[COMPLETED]`
- [x] **Phase 5.3: Unified Cross-Platform CI/CD Release Matrix**
  - [x] **Subphase 5.3.1:** Windows MSIX/ZIP, iOS IPA & Android APK/AAB Release Workflows. `[COMPLETED]`


---

# ZEROSYNC v3.0 — UNIFIED PLATFORM COMPLETION ROADMAP (STAGES 6–10)

**Roadmap Objective:** Bridge the Presentation-to-Domain integration gap, eliminate the Windows startup hardcoded telemetry defect (`home_page.dart`), and expose all 36 domain/data engines across a unified, 5-platform (**Android, Windows, Linux, macOS, iOS**) commercial-grade application.

## v3.0 Expansion Progress Dashboard

| Stage | Scope | Subphases | Completed | Status |
|:---|:---|:---:|:---:|:---|
| **Stage 6: Presentation Remediation & Unified Shell** | Fix Windows startup hardcoded telemetry, Anti-Placeholder AST gate, 5-Workspace Adaptive Navigation Shell | 2 | 2 | 🟢 COMPLETED |
| **Stage 7: Multi-Modal QR Scanner Suite** | Camera Scanner, Image/Clipboard Scanner, Batch Scanner UI, Encrypted Vault History & Threat Inspector | 4 | 4 | 🟢 COMPLETED |
| **Stage 8: Universal, Advanced & Enterprise QR Generator** | Standard QR Generator (8 types), Advanced Visual Styler + SVG/PDF Vector Export, Enterprise Payload Studio | 3 | 3 | 🟢 COMPLETED |
| **Stage 9: Live Optical Data Transfer & Enterprise Licensing** | Real File/Payload Optical Transmitter & Receiver (Mono + 3x RGB), Free/Pro/Enterprise Licensing, Trial & Policy Controls | 2 | 0 | 🟡 IN PROGRESS (Next: `9.1.1`) |
| **Stage 10: 5-Platform Native Parity & Commercial Certification** | Linux & macOS Desktop Runners, WCAG AAA Semantics, Full Localization & Production Readiness Attestation | 2 | 0 | 🔒 LOCKED |
| **v3.0 Subtotal** | **Unified Commercial Platform Expansion** | **13** | **9** | **Ready for Subphase 9.1.1** |

---

## Detailed Stage → Phase → Subphase Execution Specification

### STAGE 6: Presentation Architecture Remediation, Startup Bug Fix & Unified Navigation Shell

#### Phase 6.1: Elimination of Hardcoded Telemetry & Multi-Workspace Shell
- [x] **Subphase 6.1.1: Fix Windows Startup Hardcoded Green Payload Blocks, Reactive `OpticalSessionBloc` & Anti-Placeholder AST Linter** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/blocs/optical_session/optical_session_bloc.dart` (Manages honest `Idle`, `Preparing`, `Transmitting`, `Receiving`, `Verified`, and `Failed` states initialized to `TransferProgressMetrics.initial()`).
    - Remediate `lib/presentation/pages/home_page.dart` to remove hardcoded `totalChunks: 32, receivedChunks: 32, progressPercentage: 100.0` and dead `onPressed: () {}` callbacks.
    - Upgrade `tool/verify_airgap.dart` with `[4/4] Anti-Placeholder & Hardcoded Telemetry Audit` banning `onPressed: () {}` and hardcoded demo `TransferProgressMetrics(` in `lib/presentation/`.
    - `test/widget/presentation/home_page_test.dart` updated to assert zero pre-populated green chunks on startup.
  - **Acceptance Criteria:**
    - Launching the app on Windows/Android/iOS shows an honest `Idle — No Active Transfer (0 / 0 Chunks)` state with zero green payload blocks before file selection or scan.
    - `tool/verify_airgap.dart` fails immediately if any `onPressed: () {}` stub is introduced in `lib/presentation/`.
  - **Validation Commands:**
    - `dart format --output=none --set-exit-if-changed lib/ test/ tool/`
    - `dart analyze --fatal-infos --fatal-warnings`
    - `dart run tool/verify_airgap.dart`
    - `flutter test test/widget/presentation/home_page_test.dart`
  - **Handoff Requirements:** Clean git commit recorded; `Subphase 6.1.2` unlocked.

- [x] **Subphase 6.1.2: Unified 5-Workspace Adaptive Navigation Shell (`Scanner`, `Generator`, `Optical Transfer`, `Encrypted Vault`, `Enterprise & Licensing`)** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/unified_platform_shell.dart` with `NavigationRail` for Desktop/Tablet ($\ge 720\text{dp}$) and `NavigationBar` for Mobile ($< 720\text{dp}$), plus keyboard shortcuts (`Ctrl+1..5`).
    - Platform-aware capability detection in `CameraViewportWidget` hiding mobile-only Torch/Flip buttons on desktop workstations.
  - **Acceptance Criteria:**
    - Seamless navigation across all 5 core product pillars without widget tree state loss or layout overflow from $320\text{px}$ to $3840\text{px}$.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/unified_platform_shell_test.dart`.
  - **Handoff Requirements:** Stage 6 sealed; Stage 7 unlocked.

---

### STAGE 7: Unified Multi-Modal QR Scanner Suite (Camera, Image, Batch & Threat Inspector)

#### Phase 7.1: Camera & Static Image Scanner Workspaces
- [x] **Subphase 7.1.1: Camera Scanner Workspace & Pre-Action Threat Inspector Sheet** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/scanner/camera_scanner_view.dart` & `lib/presentation/widgets/threat_inspector_sheet.dart`.
    - Live wiring to `DomainInspectorService` (homoglyph/punycode/IP/scheme alerts), `TrackerStripperService` (UTM/fbclid/gclid stripping), and `NativeIntentDispatcher`.
  - **Acceptance Criteria:**
    - Every scanned payload displays a zero-trust inspection card with risk score, stripped URL comparison, copy/save-to-vault actions, and sandboxed intent dispatch.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/camera_scanner_view_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 7.1.2`.

- [x] **Subphase 7.1.2: Local Image File & Clipboard QR Decoder Workspace** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/scanner/image_scanner_view.dart` wired to `GalleryDecoderService` and `WindowsZxingDecoder`.
  - **Acceptance Criteria:**
    - Supports selecting or pasting PNG/JPG/BMP images on Windows, Linux, macOS, Android, and iOS, decoding single or multiple QR codes offline, and routing results through the Threat Inspector.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/image_scanner_view_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 7.2.1`.

#### Phase 7.2: High-Speed Batch Scanner & Encrypted Vault History
- [x] **Subphase 7.2.1: Batch Scanner Workspace UI Wired to `BatchScannerBloc`** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/scanner/batch_scanner_view.dart` exposing `BatchScannerBloc` controls (Start/Pause/Resume/Clear, debounce slider $500\text{ms}\text{–}3000\text{ms}$, custom batch tags, duplicate suppression counter, live item feed).
  - **Acceptance Criteria:**
    - High-throughput continuous scanning with real-time deduplication telemetry and one-click commit to SQLCipher vault.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/batch_scanner_view_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 7.2.2`.

- [x] **Subphase 7.2.2: Encrypted Vault History, Search/Tag Filter & Forensic Export UI** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/vault/encrypted_vault_page.dart` wired to `EncryptedVaultDataSource`, `VaultExportService` (JSON/CSV), and `ForensicAuditExporter` (PDF/JSON with SHA-256 chain of custody).
  - **Acceptance Criteria:**
    - Full CRUD, instant search, tag filtering, and deterministic export of scan history and transfer logs.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/encrypted_vault_page_test.dart`.
  - **Handoff Requirements:** Stage 7 sealed; Stage 8 unlocked.

---

### STAGE 8: Universal, Advanced Styled & Enterprise Payload QR Generator Suite

#### Phase 8.1: Standard Structured Payload Generator
- [x] **Subphase 8.1.1: Universal QR Generator Workspace (Text, URL, Wi-Fi, Contact, Email, SMS, Geo, Calendar)** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/generator/standard_generator_view.dart` & `lib/presentation/blocs/qr_generator/qr_generator_bloc.dart`.
    - Wired to `VcardSerializerService` (vCard 3.0/4.0), `InfrastructureSerializerService` (Wi-Fi WPA2/WPA3, Geo, iCalendar, Email, SMS), `TrackerStripperService`, and `QrMatrixGeneratorService`.
  - **Acceptance Criteria:**
    - Validated form inputs for all 8 standard payload types with real-time QR matrix rendering and byte capacity indicator.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/standard_generator_view_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 8.2.1`.

#### Phase 8.2: Advanced Visual Styler & Vector Export Studio
- [x] **Subphase 8.2.1: Advanced QR Styler Studio & SVG/PDF/PNG Vector Exporter** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/generator/advanced_styler_view.dart` mounting `QrCustomStylerCanvas`, `LogoClippingMaskService`, `EccAllocatorService`, and `VectorExportService`.
  - **Acceptance Criteria:**
    - Interactive customization of finder patterns, data module shapes, foreground/background palettes with contrast safety warnings, automatic ECC escalation to Level H when embedding logos, and offline SVG/PDF export.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/advanced_styler_view_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 8.3.1`.

#### Phase 8.3: Enterprise & Cryptographic Payload Generator
- [x] **Subphase 8.3.1: Enterprise Payload Studio (TOTP, Web3 Crypto, SLIP-39 Shamir Shares & Encrypted Binary Payloads)** `[COMPLETED]`
  - **Deliverables:**
    - `lib/presentation/pages/generator/enterprise_generator_view.dart` wired to `CryptoAuthSerializerService`, `Slip39SecretSharer` ($M$-of-$N$ threshold QR share carousel), and `PayloadEncryptionService`.
  - **Acceptance Criteria:**
    - Generates RFC 6238 TOTP provisioning QR codes, EIP-681/BIP-21 crypto URIs, multi-share SLIP-39 recovery QR decks, and XChaCha20-Poly1305 encrypted QR payloads with FFI memory zeroization on exit.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/enterprise_generator_view_test.dart`.
  - **Handoff Requirements:** Stage 8 sealed; Stage 9 unlocked.

---

### STAGE 9: End-to-End Air-Gapped Optical Data Transfer & Enterprise Licensing / Policy Engine

#### Phase 9.1: Live Optical Fountain Transmitter & Receiver Pipeline
- [x] **Subphase 9.1.1: End-to-End Optical Fountain Transmitter & Receiver Workspace (Monochrome & 3x RGB Multiplex)** `[COMPLETED]`
  - **Deliverables:**
    - `lib/domain/services/transport_advisor_service.dart`: Transport recommendation engine evaluating file size, optical speed, air-gap strictness, and hybrid protocol pathways.
    - `lib/presentation/pages/optical/optical_transfer_page.dart`: Wired to `OpticalSessionBloc`, `TransportAdvisorService`, `RgbMultiplexQrWidget` (3-channel spectral multiplexing), and `OpticalAnimationPlayer`.
    - Integrated as Workspace 2 in `UnifiedPlatformShell`.
  - **Acceptance Criteria:**
    - Selecting a real file or payload computes exact chunk counts, encrypts with XChaCha20-Poly1305, streams animated monochrome or 3x RGB fountain droplets at 5–30 FPS, and reassembles/verifies SHA-256 on the receiver.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/widget/presentation/optical_transfer_page_test.dart test/unit/domain/transport_advisor_service_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 9.2.1`.

#### Phase 9.2: Offline Licensing, Feature Flags, Trial & Enterprise Policy Controls
- [x] **Subphase 9.2.1: Enterprise Licensing, Offline Trial, Feature Flags & Policy Control Center** `[COMPLETED]`
  - **Deliverables:**
    - `lib/domain/entities/enterprise_policy.dart`: Enterprise policy snapshot, feature tier gates, and audit retention policies.
    - `lib/domain/services/enterprise_policy_service.dart`: Pure Dart enterprise engine managing tier capability evaluation, 14-day offline trial activation, granular feature toggles, security policy invariants, and DuressManagerService coordination.
    - `lib/presentation/pages/enterprise/enterprise_policy_page.dart`: Interactive control center with status badging, `.zslic` cryptographic import/revoke, trial activation, live feature toggles, full comparison matrix, and Duress Panic PIN evaluation sandbox.
    - Integrated as Workspace 4 in `UnifiedPlatformShell`.
  - **Acceptance Criteria:**
    - Complete Free vs Pro vs Enterprise comparison matrix, `.zslic` file/QR license import, deterministic offline trial activation, granular feature flag enable/disable toggles, mandatory encryption policy enforcement, and Duress Panic PIN configuration.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/unit/domain/enterprise_policy_service_test.dart test/widget/presentation/enterprise_policy_page_test.dart test/widget/presentation/unified_platform_shell_test.dart`.
  - **Handoff Requirements:** Stage 9 sealed; Stage 10 unlocked.

---

### STAGE 10: 5-Platform Native Parity (Android, Windows, Linux, macOS, iOS), Accessibility & Commercial Certification

#### Phase 10.1: Linux & macOS Desktop Runners + Cross-Platform Hardware Parity
- [ ] **Subphase 10.1.1: Scaffold & Harden `linux/` and `macos/` Desktop Runners & 5-Platform Native Guards** `[PENDING — ACTIVE NEXT]`
  - **Deliverables:**
    - `linux/` (GTK3 C++ runner) and `macos/` (Cocoa Swift runner with zero-network `DebugProfile.entitlements` / `Release.entitlements`).
    - Extend `tool/verify_airgap.dart` to audit `macos/Runner/*.entitlements` for `com.apple.security.network.client`.
    - Extend `.github/workflows/build-artifacts.yml` with `build-linux` and `build-macos` jobs.
  - **Acceptance Criteria:**
    - All 5 platforms (`Android`, `Windows`, `Linux`, `macOS`, `iOS`) pass zero-network manifest/entitlement audits and compile cleanly in CI.
  - **Validation Commands:** All 4 mandatory gates + `flutter test test/unit/core/hardware_keystore_guard_test.dart`.
  - **Handoff Requirements:** Unlocks `Subphase 10.2.1`.

#### Phase 10.2: WCAG AAA Accessibility, Localization & Final Production Certification
- [ ] **Subphase 10.2.1: Full `AccessibleQrSemantics` Integration, Multi-Locale (`en`, `es`, `ar`) Completion & v2.0 Production Certification** `[LOCKED — Depends on 10.1.1]`
  - **Deliverables:**
    - Complete `app_en.arb`, `app_es.arb`, and `app_ar.arb` translations for all 5 workspaces.
    - Full `AccessibleQrSemantics` screen-reader annotations and keyboard focus traversal across all interactive views.
    - Updated `contracts/PRODUCTION_RELEASE_MANIFEST.md` and `contracts/AIR_GAP_COMPLIANCE_ATTESTATION.md`.
  - **Acceptance Criteria:**
    - $100\%$ test pass rate across unit, widget, and integration suites; $\ge 85\%$ domain coverage; zero static analysis warnings; zero air-gap or placeholder violations.
  - **Validation Commands:** All 4 mandatory gates (`dart format`, `dart analyze`, `dart run tool/verify_airgap.dart`, `flutter test --coverage`).
  - **Handoff Requirements:** Stage 10 sealed; Commercial Production Release `v2.0.0` certified.


---

### STAGE 9 EXPANSION (v3.1): Adaptive Multi-Modal Transport, Topology & Benchmarking

- [ ] **Subphase 9.1.2: Intelligent Multi-Modal Transport Advisor (`TransportAdvisorService`), Topology Coordinator (`1:1`, `1:N` Broadcast, `M:N`), Transfer Resume Checkpoints & Benchmark Profiler** `[LOCKED — Depends on 9.1.1]`
  - **Deliverables:**
    - `lib/domain/services/transport_advisor_service.dart`: Evaluates file size, bandwidth, security policy (`strictOpticalScif` vs `proximityHybridOob` vs `localLan`), device capabilities, and environment to score and recommend:
      1. *Animated QR / LT Fountain Streaming*
      2. *High-Speed RGB 3-Channel QR Burst Mode*
      3. *Offline Air-Gapped Unidirectional Transfer*
      4. *Hybrid QR + Wi-Fi Direct / Local Wi-Fi / LAN Transfer* (QR Out-of-Band X25519 ECDH Handshake + Policy-Gated Peer Adapter)
      5. *Hybrid QR + Bluetooth BLE Transfer*
    - `lib/domain/services/multi_topology_coordinator.dart`: Orchestrates `OneToOne`, `OneToMany` (simultaneous rateless fountain multicast to unlimited receivers), `ManyToMany`, and simultaneous multi-device sessions.
    - `lib/domain/services/transfer_checkpoint_service.dart`: Persists and resumes partial `ChunkAccumulatorEngine` bitmasks and source blocks across sessions.
    - `lib/domain/services/adaptive_compression_service.dart`: Shannon byte-entropy analyzer ($H(X)$) selecting optimal compression level before XChaCha20-Poly1305 encryption.
    - `lib/domain/services/transfer_benchmark_service.dart`: Real-time throughput profiler and auto-tuner for QR version, ECC, and FPS.
  - **Acceptance Criteria:**
    - Automatic transport recommendation card rendered in the Optical Transfer workspace with estimated duration, KB/s goodput, security posture badge, and topology selector (`1:1`, `1:N`, `M:N`).
    - Interrupted transfers resume from exact percentage via checkpoint recovery without re-transmitting already peeled blocks.
    - Strict Air-Gap Policy (`strictOpticalScif`) cryptographically locks out non-optical RF/LAN modes when enforced by enterprise policy.
  - **Validation Commands:**
    - `dart format --output=none --set-exit-if-changed lib/ test/ tool/`
    - `dart analyze --fatal-infos --fatal-warnings`
    - `dart run tool/verify_airgap.dart`
    - `flutter test test/unit/domain/transport_advisor_service_test.dart test/unit/domain/transfer_checkpoint_service_test.dart`
  - **Handoff Requirements:** Unlocks `Subphase 9.2.1`.
