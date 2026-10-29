---
name: zerosync-orchestrator
description: >-
  Guides autonomous execution, verification, and governance of the AirDrop-QR / ZeroSync
  air-gapped mobile application across its 6-stage Clean Architecture lifecycle. Use this skill
  whenever managing, implementing, testing, or auditing subphases in the ZeroSync project.
---

# ZeroSync Orchestrator: Autonomous Agent Skill & Execution Runbook

This skill equips any AI coding agent or DevSecOps engineer with the procedural knowledge, architectural invariants, and command harnesses required to autonomously build and verify the **AirDrop-QR / ZeroSync** air-gapped mobile toolkit.

---

## 1. PROJECT IDENTITY & DOMAIN ARCHITECTURE

- **Domain:** Air-gapped optical communication, vector QR compilation, high-speed camera scanning, and zero-trust mobile vaults.
- **Architecture:** Clean Architecture + Domain-Driven Design (DDD).
- **Core Principle:** **Zero Network Permissions**. No `android.permission.INTERNET`, no `NSAppTransportSecurity` exceptions, zero remote telemetry, zero analytics.
- **Layers:**
  - `presentation/`: Blocs, pages, adaptive widgets, design tokens.
  - `domain/`: Pure Dart models, value objects, mathematical engines (RaptorQ FEC, CRC32, Reed-Solomon, URL sanitizer). **Zero Flutter UI or external I/O imports.**
  - `data/`: SQLCipher local encrypted database, Keystore/Keychain bindings, camera frame stream platform adapters.
  - `platform/`: Native Kotlin (Android) and Swift (iOS) platform channels.

---

## 2. STATE MACHINE PROTOCOL (`.project_state.json`)

The single source of truth for the codebase is `.project_state.json` at the repository root.

### Subphase Statuses:
- `LOCKED`: Dependencies are not yet satisfied. Cannot be started.
- `PENDING`: Dependencies satisfied; queued for execution.
- `IN_PROGRESS`: Actively being worked on by the agent.
- `VERIFYING`: Automated linting, tests, and air-gap audits are currently evaluating.
- `COMPLETED`: All verification criteria satisfied, git commit sealed, commit hash recorded.

### Crucial Orchestration Rule: Single-Subphase Sequential Locking
1. An agent **must only work on ONE subphase at a time** (indicated by `active_pointer.subphase_id`).
2. An agent **must not modify files outside the current subphase scope**.
3. An agent cannot complete subphase $N$ until all tests pass, zero lint warnings remain, and domain coverage is $\ge 85\%$.

---

## 3. COMMAND HARNESS (POWERSHELL CORE)

Always use the cross-platform PowerShell Core (`pwsh` or `powershell`) commands in `scripts/`:

### 3.1 Initializing Workspace
```powershell
pwsh -File ./scripts/bootstrap-init.ps1
```
Verifies toolchains (Flutter, Dart, Git, OpenJDK, Android SDK), creates the DDD directory archetype, and initializes `.project_state.json`.

### 3.2 Activating a Subphase
```powershell
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action start
```
Transitions status to `IN_PROGRESS`, records UTC start timestamp, and prints required artifacts.

### 3.3 Verifying a Subphase
```powershell
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action verify
```
Runs 4 automated gates:
- **Gate 1:** Checks presence of all `required_artifacts`.
- **Gate 2:** `dart analyze --fatal-infos --fatal-warnings`.
- **Gate 3:** `flutter test` (all unit & widget tests).
- **Gate 4:** Air-gap manifest audit (checks zero `android.permission.INTERNET`).

### 3.4 Sealing & Committing a Subphase
```powershell
pwsh -File ./scripts/bootstrap-subphase.ps1 -Stage STAGE_1 -Phase PHASE_1_1 -Subphase SUBPHASE_1_1_1 -Action complete
```
Runs full verification, stages all changes (`git add -A`), commits with message:
`feat(phase-<X-Y>): complete <SUBPHASE_ID> - <Title>`, records the SHA commit hash in `.project_state.json`, and queues the next subphase.

### 3.5 Viewing the Progress Dashboard
```powershell
pwsh -File ./scripts/bootstrap-verify.ps1
```
Renders the visual ASCII tree and validates dependency integrity across all 47 subphases.

---

## 4. AGENT OPERATIONAL WORKFLOW

When assigned to a subphase:
1. **Read State:** Inspect `active_pointer` in `.project_state.json`.
2. **Start Subphase:** Run `bootstrap-subphase.ps1 -Action start`.
3. **Implement Artifacts:** Write pure, production-grade Dart/Flutter code. No placeholders, no `// TODO` shortcuts.
4. **Implement Tests:** Write comprehensive unit/widget tests in `test/unit/` or `test/widget/`. Ensure domain line coverage $\ge 85\%$.
5. **Run Verification:** Run `bootstrap-subphase.ps1 -Action verify`. If any gate fails, inspect the error output and correct the root cause.
6. **Complete & Seal:** Run `bootstrap-subphase.ps1 -Action complete`.
7. **Advance:** Re-run `bootstrap-verify.ps1` to observe the dashboard and verify the next active target.

---

## 5. RECOVERY & TROUBLESHOOTING

- **Linter Error / Warning:** Run `dart analyze` to see exact file line numbers. All warnings are treated as fatal.
- **Dependency Issue:** Ensure `flutter pub get` has been run.
- **Test Failure:** Run `flutter test test/path/to/specific_test.dart` to isolate failures.
- **State Inconsistency:** Run `pwsh ./scripts/bootstrap-verify.ps1` to detect circular or unmet dependencies.

