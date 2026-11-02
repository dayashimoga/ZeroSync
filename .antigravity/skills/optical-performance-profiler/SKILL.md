---
name: optical-performance-profiler
description: Optimize 60-120 FPS rendering, zero-copy Isolate workers, thermal throttling, and low-memory footprints across all platforms.
---
# Optical Performance & Resource Profiler Skill
1. **Sub-8ms Frame Budget:** Keep UI thread frame rasterization under 8ms by pre-calculating QR bit matrices and LT fountain droplets inside `FountainCodecIsolate` using `TransferableTypedData`.
2. **Zero Idle CPU Drain:** Automatically pause camera sensors, laser scanline `AnimationController`s, and periodic timers when the app is backgrounded, minimized, or switched to a non-optical workspace.
3. **Thermal & Memory Discipline:** Bind `ThermalThrottleManager` to dynamically step down emitter FPS under thermal load and enforce bounded ring buffers in `ChunkAccumulatorEngine`.

