# ORCHESTRATION RULES & STATE MACHINE SPECIFICATION
**System Identity:** AirDrop-QR / ZeroSync Autonomous Execution Harness  
**State File:** `.project_state.json` (Workspace Root)  
**Execution Model:** Single-Subphase Sequential Locking with Cryptographic Gate Checks  

---

## 1. STATE MACHINE SCHEMA (`.project_state.json`)

The state machine is stored in the workspace root at `.project_state.json`. It acts as the single source of truth for all human developers, autonomous agents, and CI/CD pipelines.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "project_name": "AirDrop-QR / ZeroSync",
  "contract_version": "1.0.0",
  "last_updated": "2026-10-29T11:30:00Z",
  "active_pointer": {
    "stage_id": "STAGE_1",
    "phase_id": "PHASE_1_1",
    "subphase_id": "SUBPHASE_1_1_1"
  },
  "metrics": {
    "total_subphases": 11,
    "completed_subphases": 0,
    "progress_percentage": 0.0,
    "domain_test_coverage": 0.0
  },
  "stages": [
    {
      "id": "STAGE_1",
      "name": "Workspace, Contract & CI/CD Bootstrap",
      "phases": [
        {
          "id": "PHASE_1_1",
          "name": "Environment Initialization",
          "subphases": [
            {
              "id": "SUBPHASE_1_1_1",
              "title": "Directory Structure, Analysis Options & Pubspec Scaffolding",
              "status": "PENDING",
              "dependencies": [],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "analysis_options.yaml exists with zero-warning configuration",
                "pubspec.yaml configured with required dependencies and zero-network policy",
                "Directory tree matches Clean Architecture specification",
                "Git repository initialized with main branch"
              ],
              "required_artifacts": [
                "contracts/ENGINEERING_CONTRACT.md",
                "contracts/ORCHESTRATION_RULES.md",
                "analysis_options.yaml",
                "pubspec.yaml",
                ".gitignore"
              ]
            }
          ]
        },
        {
          "id": "PHASE_1_2",
          "name": "Automation Scaffolding",
          "subphases": [
            {
              "id": "SUBPHASE_1_2_1",
              "title": "PowerShell Core Bootstrap & State Tracker Tooling",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_1_1_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "scripts/bootstrap-init.ps1 executes cleanly",
                "scripts/bootstrap-subphase.ps1 supports start, verify, and complete actions",
                "scripts/bootstrap-verify.ps1 renders ASCII dashboard",
                "PowerShell syntax validates under pwsh and Windows PowerShell"
              ],
              "required_artifacts": [
                "scripts/bootstrap-init.ps1",
                "scripts/bootstrap-subphase.ps1",
                "scripts/bootstrap-verify.ps1"
              ]
            }
          ]
        },
        {
          "id": "PHASE_1_3",
          "name": "GitHub CI/CD Workflows",
          "subphases": [
            {
              "id": "SUBPHASE_1_3_1",
              "title": "Cross-Platform CI Matrix, Static Analysis & Artifact Packaging",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_1_2_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                ".github/workflows/build-artifacts.yml validated against GitHub Actions syntax",
                "Android matrix configured for split APKs and AAB",
                "iOS matrix configured for unsigned IPA extraction",
                "Air-gap audit check integrated into CI job",
                "Artifact retention policy set to 14 days"
              ],
              "required_artifacts": [
                ".github/workflows/build-artifacts.yml"
              ]
            }
          ]
        }
      ]
    },
    {
      "id": "STAGE_2",
      "name": "Core Domain Engines & Data Protocols",
      "phases": [
        {
          "id": "PHASE_2_1",
          "name": "Optical Data Streaming Engine",
          "subphases": [
            {
              "id": "SUBPHASE_2_1_1",
              "title": "Binary Chunking, ZSP-V1 Wire Protocol & CRC32 Integrity Layer",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_1_3_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Chunker breaks arbitrary binary payloads into uniform MTU frames",
                "Wire protocol serializes and deserializes ZSP1 headers without data loss",
                "IEEE 802.3 CRC32 verifies frame integrity and flags bit flips",
                "Unit tests achieve >= 95% line coverage on domain chunking"
              ],
              "required_artifacts": [
                "lib/domain/entities/stream_frame.dart",
                "lib/domain/value_objects/chunk_header.dart",
                "lib/domain/services/chunker_service.dart",
                "test/unit/domain/chunker_service_test.dart"
              ]
            },
            {
              "id": "SUBPHASE_2_1_2",
              "title": "Fountain/RaptorQ Forward Error Correction (FEC) & Reassembly State Machine",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_2_1_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Fountain encoder generates repair symbols from systematic chunks",
                "Reassembly engine reconstructs full payload under 20% random packet loss",
                "Duplicate and corrupted frames are discarded without crashing stream",
                "Stress tests simulate 1000-packet transmission with jitter"
              ],
              "required_artifacts": [
                "lib/domain/services/fountain_fec_service.dart",
                "lib/domain/services/reassembly_state_machine.dart",
                "test/unit/domain/fountain_fec_service_test.dart"
              ]
            }
          ]
        },
        {
          "id": "PHASE_2_2",
          "name": "Payload Serialization Engine",
          "subphases": [
            {
              "id": "SUBPHASE_2_2_1",
              "title": "Air-Gapped Offline Serialization (vCard, Wi-Fi, TOTP, Crypto)",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_2_1_2"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "vCard 3.0/4.0 parser and serializer with contact sanitization",
                "Wi-Fi network configuration generator supporting WPA2/WPA3",
                "TOTP URI generator conforming to RFC 6238",
                "Gzip compression pipeline for payloads > 256 bytes",
                "Unit tests cover all serialization variants"
              ],
              "required_artifacts": [
                "lib/domain/services/payload_serialization_service.dart",
                "lib/domain/entities/offline_payload.dart",
                "test/unit/domain/payload_serialization_service_test.dart"
              ]
            }
          ]
        },
        {
          "id": "PHASE_2_3",
          "name": "Security Sandbox Layer",
          "subphases": [
            {
              "id": "SUBPHASE_2_3_1",
              "title": "Malicious URL Stripper, Tracker Cleaner & Intent Sandboxing",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_2_2_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "URL cleaner strips UTM, fbclid, gclid, and marketing tracking parameters",
                "Scheme validator rejects dangerous URIs (file, javascript, data, intent)",
                "Homoglyph and punycode analyzer warns on spoofed domains",
                "Zero platform network APIs invoked during sanitization"
              ],
              "required_artifacts": [
                "lib/domain/services/url_sanitizer_service.dart",
                "lib/domain/entities/sanitized_url.dart",
                "test/unit/domain/url_sanitizer_service_test.dart"
              ]
            }
          ]
        }
      ]
    },
    {
      "id": "STAGE_3",
      "name": "UI/UX Presentation & Hardware Interop",
      "phases": [
        {
          "id": "PHASE_3_1",
          "name": "High-FPS QR Stream Renderer",
          "subphases": [
            {
              "id": "SUBPHASE_3_1_1",
              "title": "High-FPS Animated Optical Emitter & Dynamic Canvas Renderer",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_2_3_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "CustomPainter renders raw QR matrices at configurable 15-60 FPS",
                "Adaptive brightness booster triggers maximum contrast during transmission",
                "Visual progress ring indicates transmission cycle and parity ratio",
                "Zero UI lag or dropped frames on 60Hz and 120Hz displays"
              ],
              "required_artifacts": [
                "lib/presentation/widgets/optical_emitter_canvas.dart",
                "lib/presentation/blocs/optical_transmitter/optical_transmitter_bloc.dart"
              ]
            }
          ]
        },
        {
          "id": "PHASE_3_2",
          "name": "Multi-Code & High-Speed Optical Scanner",
          "subphases": [
            {
              "id": "SUBPHASE_3_2_1",
              "title": "Edge Camera Stream Ingestion, Multi-Code Detection & Deduplication",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_3_1_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Camera frame ingestion handles 30+ FPS optical input stream",
                "Deduplication ring buffer ignores identical consecutive frames",
                "Visual reassembly HUD shows real-time packet matrix filling",
                "Haptic feedback triggers upon successful transmission reconstruction"
              ],
              "required_artifacts": [
                "lib/presentation/widgets/optical_scanner_hud.dart",
                "lib/presentation/blocs/optical_receiver/optical_receiver_bloc.dart"
              ]
            }
          ]
        },
        {
          "id": "PHASE_3_3",
          "name": "Tablet & Dual-Pane UI Optimization",
          "subphases": [
            {
              "id": "SUBPHASE_3_3_1",
              "title": "Adaptive Dual-Pane Master-Detail & Foldable Layout Engine",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_3_2_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Layout adapts dynamically across Phone, Foldable, and Tablet breakpoints",
                "Dual-pane layout displays scanner alongside historical air-gap transfers",
                "High-contrast monochrome dark theme optimized for low-light optical scans",
                "Widget tests verify responsive resizing without layout overflows"
              ],
              "required_artifacts": [
                "lib/presentation/pages/home_adaptive_scaffold.dart",
                "lib/presentation/widgets/dual_pane_split_view.dart",
                "test/widget/presentation/home_adaptive_scaffold_test.dart"
              ]
            }
          ]
        }
      ]
    },
    {
      "id": "STAGE_4",
      "name": "Verification, Benchmarking & Release Hardening",
      "phases": [
        {
          "id": "PHASE_4_1",
          "name": "Optical Loopback Stress Testing",
          "subphases": [
            {
              "id": "SUBPHASE_4_1_1",
              "title": "Loopback Simulation, Packet Dropout Fuzzing & Throughput Profiler",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_3_3_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Simulated optical loopback benchmark transmits 100KB file across virtual optical link",
                "Benchmark measures effective throughput (Target: > 5.0 KB/sec under 10% packet drop)",
                "Fuzz tests subject receiver to random corrupt bits and truncated payloads",
                "Stress suite completes with zero uncaught exceptions"
              ],
              "required_artifacts": [
                "test/integration/optical_loopback_stress_test.dart",
                "benchmark/throughput_profiler.dart"
              ]
            }
          ]
        },
        {
          "id": "PHASE_4_2",
          "name": "Cryptographic Audit & Release Packaging",
          "subphases": [
            {
              "id": "SUBPHASE_4_2_1",
              "title": "Hermetic Build Check, Zero-Network Audit & Checksum Manifest Generation",
              "status": "PENDING",
              "dependencies": ["SUBPHASE_4_1_1"],
              "started_at": null,
              "completed_at": null,
              "commit_hash": null,
              "verification_criteria": [
                "Binary build produces reproducible SHA256 hashes",
                "Automated audit verifies AndroidManifest.xml and Info.plist contain zero network scopes",
                "Release checklist fully verified across all subphases",
                "State machine reflects 100% completion across all 11 subphases"
              ],
              "required_artifacts": [
                "contracts/RELEASE_AUDIT_REPORT.md",
                ".project_state.json"
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

---

## 2. STRICT EXECUTION RULES FOR AUTONOMOUS AGENTS

Any agent operating in this codebase MUST follow these operational boundaries:

### Rule 1: Single-Subphase Sequential Locking
- The agent must work on **EXACTLY ONE subphase at a time**.
- Attempting to modify, create, or commit code for a subphase other than the currently active pointer is a fatal protocol violation.
- A subphase cannot be marked `IN_PROGRESS` unless **ALL** of its declared dependencies have status `COMPLETED`.

### Rule 2: Non-Negotiable Gate Verification Before Completion
Before transitioning any subphase from `IN_PROGRESS` to `COMPLETED`:
1. Every file declared in `required_artifacts` must exist and be completely implemented.
2. The domain test suite must pass with zero failures: `flutter test`.
3. Code analysis must report zero warnings and zero info hints: `dart analyze --fatal-infos --fatal-warnings`.
4. Domain layer line coverage must be `>= 85.0%`.
5. The Android and iOS manifest files must be audited for zero network permissions.

### Rule 3: Atomic Git Commits
When a subphase is completed, the automation script `scripts/bootstrap-subphase.ps1 -Action complete` must be invoked. It will:
1. Verify all criteria.
2. Stage all modifications (`git add -A`).
3. Commit with the standard message: `feat(phase-<X.Y>): complete <SUBPHASE_ID> - <Title>`.
4. Extract the resulting Git commit hash and persist it in `.project_state.json`.

---

## 3. STATE PROGRESSION HOOK & AGENT PROMPTS

When interacting with an automated agent, use the following standardized operational prompts:

### Starting a Subphase:
```bash
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action start
```
*Agent Prompt:*
> "You are currently assigned to SUBPHASE_1_1_1: Directory Structure, Analysis Options & Pubspec Scaffolding. Do not touch any code outside this subphase scope. Complete the required artifacts, ensure linting and test passes, and execute verify when ready."

### Verifying a Subphase:
```bash
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action verify
```
*Agent Prompt:*
> "Run verification on SUBPHASE_1_1_1. If any test or lint gate fails, fix it immediately within the subphase boundary. Report the exact test output."

### Completing a Subphase:
```bash
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action complete
```
*Agent Prompt:*
> "All verification checks have passed. Seal SUBPHASE_1_1_1, generate the atomic git commit, record the commit hash in .project_state.json, advance the active_pointer to the next dependent subphase, and display the project state dashboard."
