---
name: wcag-accessibility-auditor
description: Enforce WCAG 2.1 AAA contrast ratios, screen-reader Semantics trees, keyboard traversal, and multi-locale RTL layout fidelity.
---
# WCAG Accessibility & Localization Auditor Skill
1. **Screen-Reader Semantics:** Wrap all QR matrices, scanner viewports, and telemetry badges with `AccessibleQrSemantics` (`Semantics(label: ..., value: ..., liveRegion: true)`).
2. **Contrast & Color-Blind Safety:** Maintain $\ge 7:1$ AAA contrast ratio on OLED surfaces and never rely solely on color (pair emerald/amber/crimson indicators with distinct icons and text labels).
3. **Keyboard & RTL Support:** Ensure full `FocusTraversalGroup` / `Shortcuts` navigation on desktop and verify layout symmetry across `en`, `es`, and RTL `ar` locales.

