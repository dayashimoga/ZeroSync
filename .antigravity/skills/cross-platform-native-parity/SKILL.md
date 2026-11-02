---
name: cross-platform-native-parity
description: Ensure consistent native capability parity across Android, Windows, Linux, macOS, and iOS with platform-aware hardware fallbacks.
---
# Cross-Platform Native Parity Skill (Android, Windows, Linux, macOS, iOS)
1. **Capability-Aware Camera & Scanner:** On Android/iOS/macOS, bind hardware camera via `MobileScanner`; on Windows/Linux or camera-less workstations, automatically surface file/image decoding (`GalleryDecoderService` / `WindowsZxingDecoder`) and hide mobile-only Torch/Flip overlays.
2. **Hardware Security Abstraction:** Maintain concrete implementations of `HardwareKeystoreGuard` (Android StrongBox/TEE, iOS/macOS Secure Enclave, Windows DPAPI/TPM, Linux libsecret/TPM) and `SecurityWindowGuard` across all 5 OS targets.
3. **Desktop Ergonomics:** Support native file pickers, clipboard paste (`Ctrl+V`), keyboard shortcuts, and DPI-aware window sizing across Windows, Linux, and macOS.

