# Sol 6.2 performance

Use actual rendered Chromium WebGL 2 frames, not native fixed-tick simulation timing, for Web evidence. Baseline harness uses Chromium 153 with SwiftShader (software rendering), not an Android tablet. Record resolution, preset, p50/p95/p99 frame time, draw calls, startup, and long-run stability across the specified scenarios. Full matrix not yet verified.
