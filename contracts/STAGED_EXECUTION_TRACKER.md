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
| **Stage 5: UX, DevSecOps Tools & Release Matrix** | 3 | 2 | 🟡 IN_PROGRESS |
| **Total** | **15** | **14** | **93% Completed** |

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
- [ ] **Phase 5.3: Unified Cross-Platform CI/CD Release Matrix**
  - [ ] **Subphase 5.3.1:** Windows MSIX/ZIP, iOS IPA & Android APK/AAB Release Workflows. `[PENDING]`

