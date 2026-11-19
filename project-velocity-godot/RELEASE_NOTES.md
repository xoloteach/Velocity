# Project Velocity — Neon 4 Release Notes

This release is a comprehensive visual, animation, gameplay-feel, audio, HUD, and performance overhaul of the existing **Project Velocity** Godot 4.6.3 open-world speedster action RPG (`neon4-improvements`), preserving all original systems, save compatibility, rewind determinism, anti-duplication ledger, and 8-chapter campaign structure.

## Character & Boss Upgrades
- **Rebuilt Playable Hero (`assets/velocity-runner.glb`)**: Smooth-skinned 19-bone, 9,400-triangle crimson-and-gold speedster with sculpted helmet ear-wings, luminous emblem & suit conduits, armored boots, dorsal spine detailing, and grounded contact shadow (`RunnerShadow`).
- **Bespoke Rival Boss Rigs**:
  - **Nullstride (`assets/nullstride-boss.glb`, 9,580 tris)**: 1.96m obsidian void predator with jagged pauldrons, horned visor, glowing violet conduit cores, and animated twin cloak ribbons.
  - **Afterlight (`assets/afterlight-boss.glb`, 9,086 tris)**: 1.88m ivory-and-gold temporal ace with twin aero-crown fins, forearm phase-blades, and animated split coattails.
- **Enemy Archetype Gear**: Tactical shoulder/chest armor for `guard` and aero-crest detailing for `speedster`, plus grounded `ContactShadow` discs and overhead pulsing `CounterHalo` rings during counter windows.
- **29 Upgraded Skeletal Animations**: Rebuilt biomechanical keyframe curves across idle, locomotion, wall/water runs, aerials, melee combos, counter, takedowns, and all Speed Force power casts across all 3 GLB rigs.

## World, Architecture, Traffic & Crowd Overhaul
- **Golden-Dusk Calder & Lighting**: Upgraded `world_sky.gdshader`, `world_facade.gdshader`, `world_asphalt.gdshader`, and `world_water.gdshader`; golden-dusk starting atmosphere (`18.35h`), slower 48-second day-night progression, and real-time `DirectionalLight3D` shadows on High and Ultra presets.
- **Skyline & Street Grounding**: Multi-tier architectural setbacks, belt courses, rooftop water towers, spires, warning beacons, tapered branching trees with 2-tone foliage & raised planters, red fire hydrants, street bins, crosswalk bollards, and soft shader contact shadows.
- **Solid Multi-Type Vehicles with Rotating Wheels**: Fixed vehicle `_bodywork()` outward face normals and upgraded satin paint/glass materials across 4 civilian silhouettes (executive sedan, sporty coupe with lip spoiler, urban SUV with roof rails, golden Calder Taxi with rooftop beacon), delivery vans, and two-tone Calder PD interceptors with front push-bars, side mirrors, license plates, soft headlight cones, and 4 independently spinning 5-spoke wheels tied to deterministic rewind state.
- **Sculpted Articulated Pedestrians**: Multi-part civilian characters with jackets, collars, sculpted heads, 4 hair/cap variants, optional backpacks, trousers, sneakers, articulated limbs, and grounded contact shadows.

## Speed Force VFX, Rewind & Audio
- **Multi-Strand Speed Force Lightning Trails**: Sleek luminous core ribbon flanked by 1–3 crackling electric filaments (scaling with quality preset), reverse cyan-violet temporal rewind trail, and water/wall wake rings.
- **Hero Phase Shader (`assets/hero_phase.gdshader`)**: Fresnel holographic translucent cyan phase material cleanly applied to hero meshes during Phase and automatically cleared on exit, realm transition, or rewind restore.
- **Dual-Layer Lightning & Rift Portal Vortex**: Outer plasma + white-gold inner arc cores and counter-rotating multi-ring Rift portals.
- **Upgraded 32 kHz Audio Bank (19 WAVs)**: Rebuilt all 16 original cues plus 3 new cues (`counter.wav`, `boss_score.wav`, `rift_ambience.wav`) with smooth boss-combat music crossfade and Rift ambience crossfade.

## HUD, Touchscreen, Gacha & Performance
- **Screen-Space Feedback**: Radial Mach speed-lines at high speed, cool cyan-violet Rewind edge vignette + scanlines + `« REWINDING -X.XS »` badge, icy-blue Time Dilation border, and pulsing Phase border (all respecting `effects`, `reduced_motion`, and `reduced_flash`).
- **HUD Clarity**: Tightened Current Operation card, Vital card with live Rewind history charge gauge (`RWD X.XS`), `RANK · <TIER>` + supersonic `MACH X.XX` readout, subtle diegetic 3D objective beacon, and non-blocking Web Audio unlock prompt.
- **Touchscreen & Gacha**: Added left-handed **Mirror layout** preset in **Touch layout**, violet rewind charge arc on the touch Rewind button, rarity glow reveal + Skip Reveal in **Rift cache**, and atomic `3 materials → 1 SFC` salvage exchange in both **Rift cache** and **Inventory**.
- **Compatibility WebGL 2 Tuning**: Calibrated Low/Medium/High/Ultra render scales (`0.65 / 0.85 / 0.95 / 1.0`), draw distances (`165m–440m`), real-time shadows (`High/Ultra`), and eliminated Forward+-only warnings and exit teardown leaks.
