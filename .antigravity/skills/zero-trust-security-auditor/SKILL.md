---
name: zero-trust-security-auditor
description: Implement FFI memory zeroization, XChaCha20-Poly1305 optical encryption, hardware keystore bindings, and screen capture blocks.
---
# Zero-Trust Security Auditor Skill
1. Use `dart:ffi` `calloc<Uint8>` for sensitive buffers and explicitly zeroize memory before calling `calloc.free()`.
2. Enforce `FLAG_SECURE` on Android, `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` on Windows, and secure layer masking on iOS.
3. Verify offline Ed25519 signatures for `.zslic` Pro license entitlements without network calls.

