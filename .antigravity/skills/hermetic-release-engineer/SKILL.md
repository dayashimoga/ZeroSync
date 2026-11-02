---
name: hermetic-release-engineer
description: Orchestrate reproducible, air-gapped CI/CD release builds and SHA-256 artifact attestations across Android, Windows, Linux, macOS, and iOS.
---
# Hermetic Release Engineer Skill
1. **Multi-Platform Matrix:** Build and package deterministic artifacts across Android (Split APKs + AAB with `--android-skip-build-dependency-validation`), iOS (Unsigned IPA), Windows (x64 Release ZIP), Linux (x64 Bundle), and macOS (Release APP/ZIP).
2. **Cryptographic Attestation:** Compute SHA-256 digests (`SHA256SUMS.txt`) for every release binary and verify zero telemetry (`flutter config --no-analytics`) prior to packaging.
3. **Atomic Git & Tag Governance:** Synchronize `contracts/STAGED_EXECUTION_TRACKER.md` and `.project_state.json` before sealing any release tag.

