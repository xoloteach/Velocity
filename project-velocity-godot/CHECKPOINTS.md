# Project Velocity — Neon 4 Checkpoints Ledger

| ID | Checkpoint | Status | Verification Summary |
| :--- | :--- | :--- | :--- |
| CP01 | Baseline Audit & Visual Capture | **DONE** | Cloned repo on local branch `neon4-improvements`; captured baseline Chromium WebGL 2 screenshots and documented findings in `docs/NEON4_AUDIT.md`. |
| CP02 | Stability, Cleanup & Compatibility Hygiene | **DONE** | Added `_exit_tree()` teardown cleanup in `game.gd`, guarded fixture property access in `combat.gd` and `powers.gd`, removed Forward+-only `screen_space_aa` warning under Compatibility renderer. |
| CP03 | Hero, Boss & Enemy 3D Models & Skinning | **DONE** | Generated and imported smooth-skinned `velocity-runner.glb` (9,400 tris), bespoke `nullstride-boss.glb` (9,580 tris), and bespoke `afterlight-boss.glb` (9,086 tris) plus enemy tactical gear & contact shadows. |
| CP04 | Grounded Locomotion & Combat Animations | **DONE** | Rebuilt all 29 skeletal animation clips across all 3 GLBs + subtle forward sprint pitch and grounded `RunnerShadow` height scaling. |
| CP05 | Movement, Speed Fantasy & Camera Polish | **DONE** | Multi-strand crackling Speed Force lightning trails, Mach radial speed-lines, water/wall wake rings; `traversal_test` verified 134.47 m/s peak physical speed. |
| CP06 | Landscape Touchscreen HUD & Controller Polish | **DONE** | Tightened Operation card, Vital RWD gauge, `RANK · <TIER>` + Mach display, left-handed Mirror touch layout preset, non-blocking Web Audio unlock hint; `hud_spec` 46/46 PASS. |
| CP07 | City Architecture, Grounding & Lighting | **DONE** | Golden-dusk start (`18.35h`), upgraded world shaders, High/Ultra real-time directional shadows, setback tiers, rooftop props, branching trees, planters, hydrants, bins, bollards, contact shadows. |
| CP08 | Traffic, Crowds, Police & Crime Polish | **DONE** | 4 civilian car silhouettes + vans + Calder PD interceptors with solid outward bodywork, satin paint, rotating 5-spoke wheels, mirrors, headlight cones, and sculpted articulated pedestrians. |
| CP09 | Speed Force Powers VFX & Feedback | **DONE** | Fresnel `hero_phase.gdshader` override with clean restore, dual-layer lightning arcs, counter-rotating Rift portal vortex, slow-time border glow; `powers_test` 54/54 PASS. |
| CP10 | Rewind Visual, Audio & HUD Polish | **DONE** | Cyan-violet Rewind edge vignette, scanlines, `<< REWINDING -X.XS >>` badge, reverse cyan trail, Vital RWD bar, touch Rewind charge arc; `progress_rewind_test` 86/86 PASS. |
| CP11 | Combat Feel & Telegraph Polish | **DONE** | Pulsing 3D danger telegraphs, animated overhead `CounterHalo` rings, crisp `counter.wav` feedback; `combat_integration` PASS. |
| CP12 | Boss Encounters (Nullstride & Afterlight) | **DONE** | Bespoke boss models + matching displaced echo rigs + `boss_score.wav` combat music crossfade; both boss fights verified in `campaign_flow_test`. |
| CP13 | 8-Mission Campaign & Postgame Polish | **DONE** | Sleek diegetic 3D objective sky-beacon & chevron; full 8-chapter + postgame + replay + Calder Circuit + Rift Relay verified 49/49 PASS. |
| CP14 | Economy, Gacha & Progression Polish | **DONE** | Atomic `3 materials = 1 SFC` Salvage Exchange in Rift Cache & Inventory, rarity-tinted cache reveal with Skip Reveal, durable SHA-256 dual-slot saves. |
| CP15 | Upgraded Multi-Layered SFX & Dynamic Score | **DONE** | Rebuilt 19 32 kHz WAV cues (`create_audio.py`), including new `counter.wav`, `boss_score.wav`, and `rift_ambience.wav` with smooth bus crossfades. |
| CP16 | Performance Tuning & 4-Preset Benchmark | **DONE** | Calibrated Low/Med/High/Ultra render scales, draw distances, and shadows; verified deterministic 4-preset metrics in `tests/preset_benchmark.gd`. |
| CP17 | End-to-End Native & Chromium Regression QA | **DONE** | All 9 native suites (including 79/79 `neon4_regression_test.gd`) pass; 2 Chromium visual critique/fix rounds completed with 0 console errors. |
| CP18 | Port-3000 Host & Final Zip Packaging | **DONE** | Port-3000 AI Studio host serves live Godot 4.6.3 Web export with `application/wasm`; final Web & Source ZIPs packaged, extraction-verified, and documented. |
