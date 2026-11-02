---
name: deterministic-qa-gatekeeper
description: Enforce TDD, anti-placeholder AST linting, 100% test pass rate, and >= 85% domain coverage before sealing any subphase.
---
# Deterministic QA & Anti-Placeholder Gatekeeper Skill
1. **Four Mandatory Verification Gates:**
   - `dart format --output=none --set-exit-if-changed lib/ test/ tool/`
   - `dart analyze --fatal-infos --fatal-warnings`
   - `dart run tool/verify_airgap.dart`
   - `flutter test`
2. **Startup & Empty-State Assertions:** Every page/workspace widget test MUST assert that initial startup renders an honest idle state (`0 / 0 Chunks`, no fake completion banners) and that all interactive buttons invoke valid BLoC events.
3. **Fuzz & Loopback Regression:** Run `test/integration/optical_loopback_integration_test.dart` and `optical_fuzz_stress_test.dart` whenever modifying framing, chunking, or UI state machines.

