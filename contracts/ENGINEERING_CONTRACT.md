# ENGINEERING CONTRACT & ARCHITECTURAL SPECIFICATION
**System Identity:** AirDrop-QR / ZeroSync (Offline Optical Air-Gap Toolkit)  
**Document Version:** 1.0.0-PROD  
**Classification:** Confidential / Zero-Trust Air-Gapped Mobile System  
**Target Environments:** Android (API 26+) & iOS (iOS 15.0+) | Form Factors: Phone, Foldable, Tablet  

---

## 1. ARCHITECTURAL TOPOLOGY & CLEAN DDD BOUNDARIES

The ZeroSync platform strictly enforces **Uncle Bob's Clean Architecture** combined with **Domain-Driven Design (DDD)** tactical patterns. Absolute boundary isolation guarantees that zero hardware, framework, or third-party dependencies infect the core business domain.

```
+-----------------------------------------------------------------------------+
|                           PRESENTATION LAYER                                |
|  - Feature UI Pages (Phone / Tablet Dual-Pane)                              |
|  - Reusable Reactive Canvas Widgets (High-FPS QR Streamer, Camera Scanner)  |
|  - State Management: BLoC (Business Logic Component) via flutter_bloc       |
|  - Presentation Models & ViewStates (Immutable, Equatable, Freezed-ready)   |
+-----------------------------------------------------------------------------+
                                      |
                                      v  [Depends only inward]
+-----------------------------------------------------------------------------+
|                              DOMAIN LAYER                                   |
|  - Pure Dart (ZERO Flutter UI, zero platform plugins, zero disk/network IO) |
|  - Entities & Aggregates: TransmissionSession, StreamFrame, SanitizedPayload|
|  - Value Objects: CRC32Checksum, ChunkHeader, EccLevel, PayloadDescriptor   |
|  - Domain Engines: Fountain/RaptorQ FEC Engine, Chunking Pipeline           |
|  - Repository Interfaces (Ports): ISecureStorageRepository, IFrameBuffer    |
|  - Use Cases / Interactors: StreamPayloadUseCase, IngestCameraFrameUseCase  |
+-----------------------------------------------------------------------------+
                                      ^
                                      |  [Inverted Dependency]
+-----------------------------------------------------------------------------+
|                                DATA LAYER                                   |
|  - Data Transfer Objects (DTOs): FramePacketDto, VCardDto, WifiConfigDto    |
|  - Local Data Sources: SQLCipher Encrypted SQLite, Keystore/Keyring Store   |
|  - Hardware Drivers / Camera Stream Source (Camera MLKit Platform Adapter)  |
|  - Repository Implementations: SecureStorageRepositoryImpl                  |
+-----------------------------------------------------------------------------+
```

### 1.1 Architectural Invariants (Non-Negotiables)
1. **Unidirectional Dependency Flow:**  
   `Presentation -> Domain <- Data`. Under no circumstances may `Domain` import `flutter/*`, `package:sqflite*`, `package:camera`, or any external I/O library.
2. **Deterministic State Progression (BLoC):**  
   Every presentation state transition must be triggered by an immutable `Event` yielding an immutable `State`. State emission is strictly unidirectional.
3. **Value Object Invariance:**  
   Value objects (e.g., `ChunkHeader`, `CRC32Checksum`, `SanitizedUrl`) must validate their internal constraints at construction time. If invariant checks fail, an uncatchable domain validation failure (`DomainValidationException`) is thrown.
4. **Pure Functional Domain Engines:**  
   Algorithms responsible for chunk slicing, parity calculation (RaptorQ / Fountain codes), and bitwise CRC32 calculation must be pure functions with zero side effects. They must run identically in a Dart VM CLI test as in the mobile runtime.

---

## 2. ZERO-TRUST SECURITY & AIR-GAP PRIVACY MODEL

AirDrop-QR operates under a **Zero-Trust, Completely Air-Gapped Threat Model**. It assumes that local radio bands (Wi-Fi, Bluetooth, NFC, Cellular) may be monitored, compromised, or intentionally jammed, and that the OS runtime must be hardened against data exfiltration.

```
       Air-Gapped Sender Device                     Air-Gapped Receiver Device
 +----------------------------------+         +----------------------------------+
 |  - No Network Permissions        |         |  - No Network Permissions        |
 |  - Camera Output (Screen Canvas) |  Light  |  - Camera Ingestion Sensor       |
 |  - Animated Sequential QR Codes  | ------> |  - Edge Vision Frame Parsing     |
 |  - High-FPS Adaptive Brightness  | (Photons|  - Local FEC Reassembly          |
 |  - Zero Telemetry / No Analytics |   Only) |  - In-Memory Malicious Sandboxing|
 +----------------------------------+         +----------------------------------+
```

### 2.1 OS Manifest Network Privileges: ZERO TOLERANCE
- **Android:** The permission `android.permission.INTERNET` and `android.permission.ACCESS_NETWORK_STATE` are **explicitly prohibited**. Automated CI checks will reject any build where the merged `AndroidManifest.xml` contains internet permissions.
- **iOS:** `Info.plist` will explicitly contain `NSAppTransportSecurity` with `NSAllowsArbitraryLoads: false` and declare no networking entitlements.
- **Third-Party Telemetry:** Zero integration of Firebase, Crashlytics, Sentry, Mixpanel, Datadog, or Google Analytics. Crash handling and logging are strictly confined to an ephemeral, user-inspectable, encrypted local circular buffer.

### 2.2 Cryptographic Storage & Key Lifecycle
- **At-Rest Encryption:** Scanned history, temporary frame buffers, and exported keys are stored in an encrypted **SQLCipher (AES-256-CBC)** database with 256,000 PBKDF2 iterations.
- **Master Key Derivation:**  
  - Android: Master key is generated via `AndroidKeyStore` using AES-256-GCM hardware security module (StrongBox where available).
  - iOS: Master key is stored in the iOS Secure Enclave Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- **Memory Sanitation:** Cryptographic keys, decrypted payloads, and frame byte-buffers implement explicit zeroization patterns (`Uint8List.fillRange(0, length, 0)`) upon disposal to prevent cold-boot memory dumps.

### 2.3 Optical Stream Sandboxing & Malicious URL Stripping
Prior to exposing any scanned payload to the presentation layer or OS intent system:
1. **Tracker & Fingerprint Stripping:** All URI strings are scrubbed of marketing identifiers (`utm_*`, `fbclid`, `gclid`, `mc_eid`, `msclkid`, `igshid`, `_hsenc`).
2. **Scheme Whitelisting:** Permitted schemes: `https`, `http`, `mailto`, `tel`, `wifi`, `vcard`, `otpauth`. Forbidden schemes: `file:`, `javascript:`, `data:`, `content:`, `intent:`.
3. **Punycode / Homograph Defense:** Internationalized domain names (IDN) are normalized and flagged if homoglyphic substitutions are detected.
4. **Isolated Sandboxed Execution:** External browser launch is never automatic; the user is presented with a deconstructed preview showing the canonical domain, IP resolution status (if ever connected elsewhere), and stripped parameters.

---

## 3. AIR-GAPPED OPTICAL DATA PROTOCOL (ZSP-V1)

Optical transmission relies on the **ZeroSync Optical Data Streaming Protocol Specification Version 1 (ZSP-V1)**.

### 3.1 Packet Wire Format
Every individual QR code in an animated transmission represents a single self-describing datagram:

```
+---------------------------------------------------------------------------------------+
| PREAMBLE | VERSION | SESSION_ID | SEQ_NUM | TOTAL_CHUNKS | FEC_TYPE | CRC32 | PAYLOAD |
|  4 Bytes |  1 Byte |   8 Bytes  |  2 Bytes|    2 Bytes   |  1 Byte  | 4 Byte| N Bytes |
+---------------------------------------------------------------------------------------+
```

- **Preamble:** Magic bytes `0x5A 0x53 0x50 0x31` (`ZSP1`).
- **Version:** `0x01`.
- **Session ID:** 64-bit random session identifier to prevent frame interleaving from competing displays.
- **Sequence Number (M of N):** 16-bit unsigned integer (`0x0001` through `0xFFFF`).
- **Total Chunks:** 16-bit unsigned integer representing original un-encoded payload chunk count.
- **FEC Payload Type:** 
  - `0x00`: Systematic Chunk (Direct slice of original payload).
  - `0x01`: Parity / RaptorQ Repair Chunk (Enables reconstruction of dropped frames).
- **CRC32 Checksum:** IEEE 802.3 CRC32 calculated over the payload bytes for instant corruption drop.
- **Payload:** Raw binary compressed payload slice (Base45 or raw binary encoded per QR Byte Mode).

### 3.2 Error Correction Strategy: Systematic RaptorQ / Fountain
- **Optical Dropout Inevitability:** Frame dropping occurs due to display refresh sync mismatch, optical shutter roll, and user hand jitter (typical packet loss: 10%–25%).
- **Fountain Codes:** The transmitter continuously broadcasts systematic chunks followed by on-the-fly generated repair chunks. The receiver does not need to send an ACK; once it collects any $K + \epsilon$ independent symbols (where $\epsilon \approx 2$ to $5$ packets), it decodes the complete file.

---

## 4. STRICT STATIC ANALYSIS, LINTING & TESTING GATES

Every PR, subphase completion, and CI build must pass the following non-negotiable gates:

| Gate | Requirement | Tooling / Check |
|---|---|---|
| **Domain Test Coverage** | **>= 85.0% Line Coverage** | `flutter test --coverage` + `lcov` parser |
| **Compiler Warnings** | **Zero (0) Warnings / Hints** | `dart analyze --fatal-warnings --fatal-infos` |
| **Lint Ruleset** | **Strict Pedantic / Very Good Analysis** | `analysis_options.yaml` with 120+ strict rules |
| **Security Audit** | **Zero Network Permissions** | Shell/PowerShell XML Manifest Verification |
| **Mutation Testing** | **Passed on FEC & CRC32** | Boundary fuzzing unit tests |
| **Commit Integrity** | **Conventional Commits & Clean Tree** | Pre-commit hook & automated subphase tagger |

---

## 5. SUBPHASE TRANSITION CHECKLIST TEMPLATE
Any subphase transition must be executed through the orchestration engine with the following deterministic checklist:
- [ ] 1. All previous subphases marked `[COMPLETED]` in `.project_state.json`.
- [ ] 2. Architectural layer boundaries respected (no leaked imports).
- [ ] 3. Unit and domain test suite passes with zero failures.
- [ ] 4. Code coverage exceeds threshold for modified domain packages.
- [ ] 5. Manifest security audit confirms zero external permissions.
- [ ] 6. Atomic Git commit generated with SHA256 recorded in state engine.
