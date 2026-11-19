# Project Velocity — Final QA Report (Neon 4 Release)

- **Engine**: Godot `4.6.3.stable.official.7d41c59c4` (`gl_compatibility` / WebGL 2 single-thread)
- **Branch**: Local branch `neon4-improvements` (no commits pushed to remote)
- **Deliverables**:
  - `project-velocity-final-web.zip` — multi-file Godot 4.6.3 Web export (`index.html`, `index.js`, `index.wasm`, `index.pck`, audio worklets, icons)
  - `project-velocity-final-source.zip` — complete editable Godot 4.6.3 source repository (excluding `.godot/` cache & temp artifacts)
  - Live preview host on `http://localhost:3000` serving `/game/index.html` with `Content-Type: application/wasm` (`200 OK`)

## 1. Automated Native Test Suite (9 / 9 Passing)

Executed via `GODOT_BIN=/tmp/godot-tools/Godot_v4.6.3-stable_linux.x86_64 bash project-velocity-godot/tools/test_native.sh`:

| Suite | Result | Verified Scope |
| :--- | :--- | :--- |
| `tests/world_test.gd` | **PASS** (`seed=68137 resident=4 cap=20 parcels_built=60`) | Deterministic chunk layout, streaming cap, building & parcel generation |
| `tests/population_test.gd` | **PASS** (`0 failure(s)`) | Traffic flow, pedestrian sidewalks, police pursuit, rewind snapshot stability |
| `tests/powers_test.gd` | **PASS** (`54/54, failures: 0`) | All 9 Speed Force powers, energy/cooldowns, Phase barrier crossing, Slow Time, Portal, Mirage, Tornado, Shockwave, Redirect |
| `tests/progress_rewind_test.gd` | **PASS** (`86/86, failures: 0`) | SHA-256 dual-slot saves, anti-duplication ledger, 8s deterministic rewind ring, gacha odds & duplicate salvage |
| `tests/combat_integration.gd` | **PASS** (`COMBAT_CHECKS_PASSED`) | Melee combos, lock-on, occlusion, counters, boss phases, swept attacks, arena gates, restore |
| `tests/hud_spec.gd` | **PASS** (`46/46`) | 4-finger independent multi-touch, 9-ability wheel, speed limiter persistence, touch layout editor, 16:9 non-overlapping regions, gamepad navigation, cache reveal & postgame ending |
| `tests/traversal_test.gd` | **PASS** (peak physical speed `134.47 m/s`) | Monotonic limiter, independent speed/accel/turn upgrades, extreme transit corridor, 22cm swept collision, wall-run tangent, water run & safe recovery |
| `tests/campaign_flow_test.gd` | **PASS** (`49/49, 0 failed`) | Full 8-chapter campaign from Calder spawn through Rift, Nullstride defeat, Afterlight defeat, postgame persistence, chapter replay, Calder Circuit race, Rift Relay trial |
| `tests/neon4_regression_test.gd` | **PASS** (`79/79, 0 failed, 0 warnings`) | All 3 bespoke GLBs (`velocity-runner`, `nullstride-boss`, `afterlight-boss`), 29 imported animation clips per GLB, 19 WAV audio cues, 6 shaders, 4 vehicle wheel pivots + contact shadows, sculpted humans, combat archetypes & CounterHalo, Phase shader override/restore, 3-material-to-1-SFC salvage exchange, and 4 quality presets |

## 2. Deterministic 4-Preset Benchmark (`tests/preset_benchmark.gd`)

Measured on headless Godot 4.6.3 Linux (`--fixed-fps 60`, 45 sampled frames after warmup per preset):

| Preset | `quality` | `scaling_3d_scale` | Sun Shadows | `camera.far` | Avg Frame Time | p95 Frame Time | Resident / Cap Chunks |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **Low** | 0 | `0.65` | `false` | `165 m` | `1.05 ms` | `1.73 ms` | `10 / 20` |
| **Medium** | 1 | `0.85` | `false` | `240 m` | `1.10 ms` | `1.67 ms` | `10 / 20` |
| **High** | 2 | `0.95` | `true` | `340 m` | `1.13 ms` | `1.62 ms` | `10 / 20` |
| **Ultra** | 3 | `1.00` | `true` | `440 m` | `1.33 ms` | `2.46 ms` | `10 / 20` |

## 3. Headless Chromium WebGL 2 Verification (2 Visual QA Rounds)

Tested via `playwright-cli` against the live port-3000 host (`http://localhost:3000` -> `/game/index.html`, `1280×800`, SwiftShader WebGL 2):

- **HTTP & WASM Serving**: `GET /game/index.wasm` verified `HTTP/1.1 200 OK` with `Content-Type: application/wasm` (`37,700,666` bytes); `index.pck` (`1.9 MB`), `index.js` (`309 KB`), and `index.html` load cleanly with **0 console errors** and **0 page errors**.
- **Round 1 Visual Captures & Defects Caught**:
  - Verified smooth crimson-and-gold hero GLB, translucent cyan Fresnel Phase shader + phase rings, golden-dusk skyline, multi-tier setbacks, branching trees, street props, sculpted pedestrians, 9-ability wheel with live cooldowns, and Operations panel.
  - Caught & fixed 4 visual defects: (1) dark/metallic car appearance & vehicle bodywork solidity; (2) overly bright/tall objective sky-beacon occluding the moon; (3) wide primary speed ribbon; (4) bottom Web Audio unlock pill sitting too close to dialogue subtitles.
- **Round 2 Visual Captures & Final Polish Fixes**:
  - Verified sleeker Speed Force lightning filaments, subtle objective beam leaving the moon unobstructed, clean audio pill below the Vital card, cyan-violet Rewind border vignette + scanlines + reverse cyan trail, and Rift Cache salvage exchange UI.
  - Caught & fixed 3 remaining visual polish items: (1) restored outward-facing `_bodywork()` triangle winding + solid lower chassis fill box on cars; (2) replaced unsupported Unicode `U+2192` arrow glyph in Salvage exchange caption with `=`; (3) offset the `<< REWINDING >>` badge below active enemy/boss health bars (`y = 180` when boss bar visible).

## 4. Honest Hardware & Scope Limitations

- **Physical Android Tablet (Touch / Mobile GPU)**: `NOT RUN` (verified touch input routing, 4-finger ownership, layout editor, and 16:9 responsiveness in Godot `hud_spec` and desktop Chromium; no physical Android device or Android APK built per mandate).
- **Physical Gamepad Hardware**: `NOT RUN` (verified gamepad menu/wheel/button inputs synthetically via `InputEventJoypadButton` in `hud_spec`; no physical Bluetooth/USB controller attached in container).
- **Dedicated Desktop GPU Profiling**: Headless Chromium WebGL 2 runs on CPU SwiftShader in this container; GPU shader fill-rate on discrete hardware was not profiled here.
- **Native Headless `campaign_flow_test.gd` Exit Notice**: One Godot engine exit notice (`ObjectDB instances leaked at exit`) remains in the original `campaign_flow_test.gd` test harness when it spawns two sequential `Level` instances without freeing the first scene tree child before `quit()`; `neon4_regression_test.gd` (which cleanly calls `game.queue_free()`) exits with zero leak warnings.
