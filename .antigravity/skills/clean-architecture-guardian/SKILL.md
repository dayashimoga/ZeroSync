---
name: clean-architecture-guardian
description: Enforce strict Clean Architecture & DDD boundaries, BLoC state wiring, and complete Domain-to-Presentation integration across ZeroSync.
---
# Clean Architecture & DDD Guardian Skill
1. **Strict Layer Dependency Rule:** `presentation -> domain <- data`. `lib/domain/` must never import `package:flutter/*`, `lib/data/*`, or `lib/presentation/*`.
2. **Complete Domain Wiring:** Every domain service in `lib/domain/services/` must be exposed through typed BLoCs/Cubits in `lib/presentation/blocs/` and connected to interactive views—never left as orphaned dead code.
3. **Immutable State & Value Objects:** All BLoC states and events must extend `Equatable` and initialize to honest idle states (`TransferProgressMetrics.initial()`) rather than fabricated demo metrics.
4. **Verification Gate:** Run `dart run tool/verify_airgap.dart` and `dart analyze --fatal-infos --fatal-warnings` after every structural edit.

