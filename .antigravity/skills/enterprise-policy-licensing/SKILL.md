---
name: enterprise-policy-licensing
description: Manage offline Ed25519 .zslic licensing, Free/Pro/Enterprise feature flags, deterministic offline trials, and enterprise security policies.
---
# Enterprise Policy & Offline Licensing Skill
1. **Three-Tier Entitlement Matrix:**
   - `Free`: Camera/Image Scanner, Standard QR Generator (Text, URL, Wi-Fi, Contact, Email, SMS, Geo), Standard Vault History.
   - `Pro`: Batch Scanner, Advanced Visual QR Styler & Vector SVG/PDF Export, High-Speed Optical File Transfer (up to 50MB), RGB 3x Multiplexing.
   - `Enterprise`: Unlimited Air-Gapped Optical Transfer, SLIP-39 Shamir Secret Split, Duress Panic Vault, Forensic Audit PDF/JSON Export, Custom Policy Locks.
2. **100% Offline Verification:** Validate `.zslic` certificates strictly via pinned Ed25519 public keys in `LicenseVerifierService` with zero network calls.
3. **Policy Controls & Feature Flags:** Allow administrators to toggle feature flags, enforce mandatory XChaCha20-Poly1305 payload encryption, and activate time-bounded local trials deterministically.

