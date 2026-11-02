---
name: enterprise-ux-system-designer
description: Design and validate OLED Zero-Trust UI workspaces, adaptive desktop/mobile navigation, honest empty states, and interactive telemetry.
---
# Enterprise UX System Designer Skill
1. **Zero False Telemetry:** Never display completed transfer heatmaps (`32/32 Chunks`, `100%`) or fake throughput numbers prior to an active session. Render contextual empty/idle states guiding the operator.
2. **Unified 5-Workspace IA:** Structure navigation across 5 primary modules: (1) Scanner (Camera, Image, Batch), (2) Generator (Standard, Advanced Styler, Enterprise), (3) Optical Air-Gap Transfer (Transmitter & Receiver), (4) Encrypted Vault & History, and (5) Enterprise Policy & Licensing.
3. **Adaptive Navigation:** Use `NavigationRail` + resizable dual-pane master-detail on Desktop/Tablet ($\ge 720\text{dp}$) and `NavigationBar` + `IndexedStack` on compact mobile ($< 720\text{dp}$).
4. **No Dead Actions:** Every button, chip, and menu item must trigger a live BLoC event or feedback dialog. Empty `onPressed: () {}` handlers are strictly forbidden.

