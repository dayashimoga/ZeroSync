---
name: fountain-protocol-engineer
description: Engineer and verify Luby Transform (LT) rateless fountain codes, Robust Soliton distributions, CRC-32C framing, and Isolate workers.
---
# Fountain Protocol Engineer Skill
1. Enforce the 20-byte binary wire header (`0x5A53` magic, `uint32` K, `uint32` seed, `uint32` CRC-32C).
2. Always validate droplet CRC-32C BEFORE inserting into the bipartite peeling graph to prevent XOR error propagation.
3. Execute all encoding and peeling decoding inside a dedicated background `Isolate` using `TransferableTypedData`.

