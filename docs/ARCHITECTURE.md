# ZeroSync System Architecture & Technical Specifications

**Document Version:** 1.0.0  
**Target Standard:** Clean Architecture & Domain-Driven Design (DDD)  
**Security Classification:** Air-Gapped / EAL4+ Compliant  

---

## 1. Architectural Principles

AirDrop-QR / ZeroSync is engineered upon four non-negotiable architectural tenets:

1. **Strict Clean Architecture Layering:** The dependency rule strictly flows inward. Inner layers (Domain, Core) have zero knowledge of outer layers (Data, Presentation, Platform).
2. **Pure-Dart Domain Boundary:** The `lib/domain/` module is 100% pure Dart. It contains zero Flutter UI imports (`package:flutter/*`), zero platform channel code, and zero filesystem or network dependencies.
3. **Air-Gap Zero-Trust Execution:** Remote networking libraries (`http`, `dio`, `websockets`) and internet permissions (`android.permission.INTERNET`) are permanently omitted from code and descriptors.
4. **Deterministic Resource Lifecycle:** All stateful allocations, native image buffers, cryptographic key material, and camera subscriptions are wrapped in deterministic disposal pipelines with active RAM scrubbing.

---

## 2. Layered Component Breakdown

```
+------------------------------------------------------------------------------+
|                          PRESENTATION LAYER                                  |
|   - BLoCs: BatchScannerBloc, OpticalReceiverBloc, OpticalTransmitterBloc      |
|   - Widgets: AdaptiveSplitPaneScaffold, CameraViewportWidget, CanvasStyler    |
|   - Design System: ZeroSyncTheme, Design Tokens, High-Contrast OLED Amber     |
+------------------------------------------------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
|                            DOMAIN LAYER (Pure Dart)                          |
|   - Entities: StreamFrame, VCardPayload, InfrastructurePayload, CryptoAuth   |
|   - Value Objects: PackedTransportHeader, ChunkHeader, QrMatrix               |
|   - Services: LubyTransformFecService, ChunkerService, DynamicEccAllocator   |
|   - Security: DomainInspectorService, PrivacyTrackerStripper                 |
|   - Exporters: VectorExportService (SVG, PDF, PNG)                           |
+------------------------------------------------------------------------------+
                                       ^
                                       |
+------------------------------------------------------------------------------+
|                              DATA LAYER                                      |
|   - EncryptedVaultDataSource: SQLCipher AES-256 Database                     |
|   - Key Management: FlutterSecureStorage (Keystore / Secure Enclave)         |
|   - OpticalScannerDataSource: 60 FPS Ring Buffer & Decoded Frame Dispatcher  |
+------------------------------------------------------------------------------+
                                       |
                                       v
+------------------------------------------------------------------------------+
|                             CORE INFRASTRUCTURE                              |
|   - Memory Management: DisposalAuditor (RAM Zero-Scrubbing & LIFO Bag)       |
|   - Mathematical Engines: Pure-Dart CRC32, SHA-256 Digest                     |
|   - Platform Utilities: ThermalThrottleManager, SyntheticChimeGenerator      |
+------------------------------------------------------------------------------+
```

---

## 3. Domain Layer Specifications (`lib/domain/`)

The Domain layer encapsulates all enterprise business rules, mathematical algorithms, and payload serializations:

### 3.1 Entities & Payloads
- **`VCardPayload` (`vcard_payload.dart`):** RFC 6350 compliant contact serialization supporting UTF-8 names, multi-line street addresses, base64 photo sanitization, and structured telephone/email mapping.
- **`InfrastructurePayload` (`infrastructure_payload.dart`):** Wi-Fi WPA2/WPA3 configuration payloads (`WIFI:S:MySSID;T:WPA;P:Pass;;`), RFC 5870 Geolocation coordinates (`geo:lat,lng?q=label`), and iCalendar VEVENT objects.
- **`CryptoAuthPayload` (`crypto_auth_payload.dart`):** RFC 6238 TOTP authentication URIs (`otpauth://totp/...`) with algorithm selection (SHA1, SHA256, SHA512), and Web3 payment URIs (BIP-0021 Bitcoin, EIP-681 Ethereum, Solana Pay).
- **`StreamFrame` (`stream_frame.dart`):** Encapsulates single-frame datagrams with packed binary headers, sequence indices, chunk byte slices, and frame-level CRC32 checksums.

### 3.2 Pure Domain Services
- **`LubyTransformFecService`:** Rateless erasure fountain code implementation using the Robust Soliton Distribution. Computes dynamic droplet degrees and XORs source chunks to provide infinite streaming redundancy.
- **`ChunkerService` & `ChunkAccumulatorEngine`:** Splits arbitrary binary payloads into uniform chunk slices and reconstructs received packets using an $O(1)$ `ChunkBitSet` deduplication bitmap.
- **`QrMatrixGeneratorService` & `EccAllocatorService`:** Generates QR Version 1 to 40 matrices, executes 8-pattern penalty evaluations to find the optimal contrast mask, and tunes Reed-Solomon error correction (L, M, Q, H).
- **`DomainInspectorService` & `TrackerStripperService`:** Inspects scanned URLs for phishing signatures, punycode spoofing, and dangerous schemes, while stripping commercial tracking parameters (`utm_*`, `fbclid`, `gclid`).
- **`VectorExportService`:** Exports generated QR designs to lossless XML-based SVG, vector PDF with print crop marks, and multi-resolution PNG (1024px to 4096px).

---

## 4. Data Layer Specifications (`lib/data/`)

The Data layer bridges domain entities with persistent encrypted storage and optical camera inputs:

### 4.1 SQLCipher Encrypted Vault (`encrypted_vault_datasource.dart`)
- **Engine:** SQLite with AES-256 cipher encryption via `sqflite_sqlcipher`.
- **Key Derivation:** Hardware-backed master key generated via `crypto.secureRandom` (256-bit entropy) and stored in Android Keystore / iOS Keychain. Key expansion utilizes PBKDF2 with 64,000 iterations.
- **Schema:** Strict relational tables for `scans`, `scan_tags`, and `transfer_sessions` with foreign-key cascades and indexed search columns.

### 4.2 Optical Scanner Data Source (`optical_scanner_datasource.dart`)
- **Zero-Allocation Ring Buffer:** A pre-allocated circular ring buffer holding native camera frames to eliminate Garbage Collection (GC) pauses during sustained 60 FPS scanning.
- **Dual Optical Engine:** Interfaces Google ML Kit Barcode Scanning on Android and Apple Vision Framework on iOS with sub-16ms latency per frame.

---

## 5. Presentation Layer Specifications (`lib/presentation/`)

### 5.1 Reactive State Architecture (BLoC)
- **`BatchScannerBloc`:** Manages continuous camera feed, deduplicating incoming scans, throttling vibrational feedback, and committing scans to the encrypted vault.
- **`OpticalReceiverBloc`:** Governs Visual ZeroSync reception, driving chunk accumulation, missing block heatmap updates, CRC verification, and file decompression.
- **`OpticalTransmitterBloc`:** Controls the high-speed transmitter animation loop, dynamic FPS rate adjustments, frame stepping, and OLED contrast inversion.

### 5.2 Adaptive Viewport & Tablet Ergonomics (`adaptive_split_pane_scaffold.dart`)
- **Breakpoint Logic:** 720px breakpoint dynamically switches between a mobile `IndexedStack` layout and a tablet persistent dual-pane master-detail view.
- **Sensor Retention:** The mobile navigation stack preserves camera sensor memory across tab switches without unmounting camera streams or triggering hardware renegotiation.

### 5.3 Theme Engine & Accessibility (`zerosync_design_tokens.dart`, `accessible_qr_semantics.dart`)
- **Visual Profiles:** Cyber Pitch Black (`#000000` surface for zero OLED power consumption), High-Contrast Amber, and Neon Cyberpunk.
- **WCAG 2.1 AA Compliance:** Mathematical relative luminance checks ($L = 0.2126R + 0.7152G + 0.0722B$) verify minimum contrast ratios ($\ge 4.5:1$ text, $\ge 7.0:1$ QR modules).
- **Screen Reader Semantics:** QR widgets expose accessible semantic descriptions while redacting sensitive TOTP secrets and private keys.

---

## 6. Core Infrastructure & Security Controls (`lib/core/`)

### 6.1 Memory Scrubbing & Resource Disposal (`disposal_auditor.dart`)
- **`DeterministicDisposalBag`:** Enforces strict Last-In, First-Out (LIFO) cleanup for stream subscriptions, animation controllers, timer handles, and native frame pointers.
- **`DisposalAuditor.scrubBuffer(Uint8List buffer)`:** Overwrites raw decrypted byte buffers and key material with zeros in RAM prior to garbage collection, mitigating cold-boot memory dumps.

### 6.2 Pure-Dart CRC32 Engine (`crc32.dart`)
- Implements the standard IEEE 802.3 polynomial (`0xEDB88320`) using an optimized 256-entry lookup table for wire-speed datagram checksum verification.

### 6.3 In-Memory Synthetic Audio Synthesizer (`feedback_haptics_service.dart`)
- Generates 16-bit PCM RIFF/WAV audio tones algorithmically in RAM using Hann-windowed mono sine waves (880 Hz scan chime, 1760 Hz packet tick, 220 Hz alert). Eliminates disk asset dependencies and avoids external audio player attack surfaces.

### 6.4 Thermal Throttle Manager (`thermal_throttle_manager.dart`)
- Maps device operating temperatures to camera sampling frequencies:
  - **Nominal (<39°C):** 60 FPS, 1x downsampling.
  - **Fair (39–43°C):** 30 FPS, 2x downsampling.
  - **Serious (43–47°C):** 15 FPS, 4x downsampling.
  - **Critical ($\ge$47°C):** 5 FPS, 8x downsampling.
- Auto-suspends camera sensor stream after 3 minutes of continuous optical inactivity.

