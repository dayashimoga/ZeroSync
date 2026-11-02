---
name: airgap-compliance-governor
description: Audit and certify NIST SP 800-53, ISO 27001, and SCIF zero-network air-gap compliance, forensic chain-of-custody, and memory sanitization.
---
# Air-Gap Compliance & Regulatory Governor Skill
1. **Zero-Network Attestation:** Verify that `AndroidManifest.xml`, `Info.plist`, and desktop entitlements contain zero network sockets or permissions via `dart run tool/verify_airgap.dart`.
2. **Forensic Chain of Custody:** Ensure all optical transfers and batch scans produce tamper-evident SHA-256 / CRC-32C audit logs exportable via `ForensicAuditExporter`.
3. **RAM & Vault Sanitization:** Certify that `DisposalAuditor` and `SecureMemoryArena` zeroize all sensitive key material and that `DuressManagerService` cryptographically isolates primary and decoy vaults.

