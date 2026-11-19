# Project Velocity — Neon 4 Baseline Audit

## 1. Repository & Toolchain Verification
- **Source of Truth**: `https://github.com/waqira8766/project-velocity-godot.git` (cloned cleanly onto local branch `neon4-improvements` from commit `8f4c48b`).
- **Engine**: Godot `4.6.3.stable.official.7d41c59c4` (`gl_compatibility`, WebGL 2 single-thread Web export).
- **Missing Reference Files Noted**: The Neon 4 improvement brief referenced `docs/PRODUCTION_BRIEF.txt` and `docs/browser-evidence.json`, neither of which exists in the cloned repository (`docs/` contains `COMBAT.md`, `INTERFACES.md`, and `PROGRESSION_REWIND.md`). All audit findings below are grounded directly in the actual repository files, native Godot tests, and real Chromium WebGL 2 renders.

## 2. Baseline Automated Test Results (Unmodified Repo)
Executed via `GODOT_BIN=/tmp/godot-tools/Godot_v4.6.3-stable_linux.x86_64 bash tools/test_native.sh`:
- `tests/world_test.gd`: **PASS** (`seed=68137 resident=4 cap=20 parcels_built=60`)
- `tests/population_test.gd`: **PASS** (`0 failure(s)`)
- `tests/powers_test.gd`: **PASS** (`54 assertions, 0 failures`)
- `tests/progress_rewind_test.gd`: **PASS** (`86 assertions, 0 failures`)
- `tests/combat_integration.gd`: **PASS** (melee, occlusion, lock, combo, group pressure, counters, dodge, mirage, slow, Nullstride & Afterlight 3-phase boss wins, restore)
- `tests/hud_spec.gd`: **PASS** (`46/46`)
- `tests/traversal_test.gd`: **PASS** (limiter monotonic, upgrades independent, peak physical speed `134.47 m/s`, 22 cm swept collision, wall-run tangent, water-run & recovery)
- `tests/campaign_flow_test.gd`: **PASS** (`49 passed, 0 failed`) — **Defect noted**: emits `WARNING: ObjectDB instances leaked at exit` on shutdown.
- **Baseline Web Export**: `--export-release Web` succeeded (`index.html`, `index.js`, `index.wasm`, `index.pck` 1.1 MB, audio worklets). Booted in headless Chromium (SwiftShader WebGL 2) with zero console errors on spawn.

## 3. Feature-by-Feature Baseline Status Matrix

| Area | Status | Concrete Evidence & Defects Found |
| :--- | :--- | :--- |
| **Core Architecture & Scene Flow** (`game.gd`, `scenes/game.tscn`) | **IMPLEMENTED** | Clean modular coordinator; `ObjectDB instances leaked at exit` warning on teardown needs fixing. |
| **Hero 3D Model, Skinning & Animation** (`assets/velocity-runner.glb`, `tools/create_runner.py`) | **PARTIAL** | All 29 animation clips exist and play, **but** mesh uses rigid 1-bone-per-part lofted ellipsoids with visible seams (boxy pelvis, stiff idle stance, no smooth joint blending, no LODs, thin peg boots). |
| **Boss & Enemy Visual Identity** (`systems/combat.gd`) | **PARTIAL** | Nullstride (`rival_dark`), Afterlight (`rival_yellow`), `guard`, and `speedster` all reuse the exact same `velocity-runner.glb` mesh with only color/scale swaps. Lacks distinct silhouettes, armor pauldrons, visors, cloaks/fins, and bespoke boss visual presence. |
| **Movement, Wall/Water Run & Extreme Transit** (`game.gd`, `presentation.gd`) | **IMPLEMENTED / POLISH NEEDED** | Solid physics, coyote time, jump buffer, wall-run, water-run, and bounded extreme transit (`134.47 m/s`), **but** lacks dynamic speed-lines, multi-strand arcing body lightning, ground/water/wall contact VFX, forward pitch lean, and subtle camera recentering polish. |
| **Open-World City & Lighting** (`systems/world.gd`, `assets/world_*.gdshader`) | **PARTIAL** | Deterministic 7×6 parcel streaming, 5 districts, canal/bridges, Meridian elevated deck, and Rift realm work cleanly. **Visual defects observed in Chromium**: zero shadows (`sun.shadow_enabled = false`, no contact shadows anywhere, causing floating actors/cars), single-box buildings with repetitive flat window grids, blob-sphere trees, sparse street props, fast day-night clock (`1 hr / 19 s`), and soft `0.75` Medium render scale. |
| **Traffic, Crowds, Police & Crime** (`systems/population.gd`, `population_art.gd`) | **PARTIAL** | Real red/green intersection stops, crosswalk yielding, pedestrian fleeing, police pursuits, and dynamic crimes work. **Visual defects**: pedestrians are 8-segment sphere bean-dolls with stiff hinged limbs; vehicles are simple soap-bar wedges with static baked wheels, no pillars/mirrors/grilles, no contact shadows, and limited chassis variety (only sedan + van). |
| **9 Speed Force Powers & VFX** (`systems/powers.gd`, `power_fx.gd`) | **IMPLEMENTED / VFX BASIC** | All 9 powers (`lightning`, `phase`, `rewind`, `tornado`, `mirage`, `slow`, `portal`, `shockwave`, `redirect`) have real physics, occlusion, cooldowns, and rewind support. VFX are rudimentary (single torus rings, thin triangles, no layered lightning core/sparks, no hero phase translucency shader, no slow-time/rewind screen tint, simple portal hoop). |
| **8-Second Rewind System** (`systems/rewind.gd`) | **IMPLEMENTED / PRESENTATION BASIC** | 24 Hz, 193-sample ring buffer restores hero, population, combat, powers, and campaign without rolling back permanent wallet/awards. Needs dramatic reverse trail, screen-space temporal tint/scanlines, reverse audio sweep, and a live HUD rewind history meter. |
| **Combat & Boss Encounters** (`systems/combat.gd`) | **IMPLEMENTED / POLISH NEEDED** | Real hitboxes, occlusion, combo buffer, counters, takedowns, and 3-phase Nullstride & Afterlight fights pass integration tests. Needs distinct boss models/silhouettes, clearer animated 3D telegraph rings/arrows, hit sparks, directional knockback flair, and boss phase-shift shockwaves. |
| **8-Mission Campaign & Postgame** (`systems/campaign.gd`) | **IMPLEMENTED** | All 8 named chapters, ending, replay, Calder Circuit, Rift Relay, and free patrol pass 49/49 checks. Needs stronger 3D objective beacons/pillars, smoother pacing cues, and crisp mission banner presentation. |
| **Economy, Gacha & Durable Saves** (`systems/progress.gd`) | **IMPLEMENTED** | SHA-256 dual-slot atomic saves, migration, anti-farming travel ledger, 10,000-ticket 6-tier gacha odds, prestige, and material exchange pass 86/86 checks. Needs richer cache reveal feedback and clear rank-vs-physical-speed readout. |
| **Landscape Touch HUD & Controls** (`systems/hud.gd`) | **IMPLEMENTED / POLISH NEEDED** | Multi-touch pointer ownership, 9-ability wheel, touch layout editor, keyboard + gamepad parity pass 46/46 checks. Needs tighter top operation banner, live Rewind history gauge, clearer speed-tier vs km/h/Mach readout, left/right-handed touch preset, Web tap-to-unlock audio prompt, and crisper superhero styling. |
| **Audio & Dynamic Score** (`tools/create_audio.py`, `systems/presentation.gd`) | **PARTIAL** | 16 small 22 kHz mono sine+noise WAVs; functional but tinny and thin. Needs richer multi-layered sound design, harmonic superhero theme + boss intensity stem, Rift ambience, crisp footsteps/lightning/impacts/whooshes/UI cues, and reverse-rewind audio feel. |
| **Performance & Preset Scaling** (`game.gd`, `world.gd`, `population.gd`) | **IMPLEMENTED / BENCHMARK NEEDED** | Presets Low/Medium/High/Ultra exist; need deterministic benchmark capture across all 4 presets after visual upgrades, keeping draw calls and frame times tightly bounded. |
| **Physical Tablet & Gamepad Hardware** | **NOT AVAILABLE IN CONTAINER** | Container runs Linux headless Godot + headless Chromium (SwiftShader). Physical Android tablet and physical USB/Bluetooth gamepad tests must be explicitly reported as `NOT RUN`. |
