# Project Velocity (Godot 4.6.3 — Neon 4 Release)

A third-person open-world 3D speedster action RPG set in the city of **Calder**, built in **Godot 4.6.3 stable** (Compatibility / WebGL 2 single-thread). Features an 8-operation campaign, two bespoke speedster boss encounters (**Nullstride** and **Afterlight**), 9 Speed Force powers, deterministic 8-second temporal rewind, streaming multi-district architecture, live traffic & pedestrian crowds, offline progression & Rift cache salvage exchange, and full desktop, gamepad, and landscape touchscreen support.

## Play the Web Export

Extract `project-velocity-final-web.zip` into a directory (keeping `index.html`, `index.js`, `index.wasm`, `index.pck`, and audio worklets together) and serve over HTTP with `application/wasm` MIME type:

```sh
python3 -m http.server 8080 --directory project-velocity-web
```

Open `http://localhost:8080/` in any WebGL 2 browser (no Cross-Origin-Opener-Policy / SharedArrayBuffer headers required). Click or tap the canvas to enable Web Audio, and open **Ops → Settings** for graphics presets (**Low / Medium / High / Ultra**), reduced motion/flash accessibility, and audio levels.

## Midnight Circuit

Open **Ops → Midnight Circuit** or launch the web game with `?mode=midnight`. Race twelve gates across Calder and both canal bridges. Drive across lime chevrons for a speed burst; release boost before the pink turn gates. The standard suit keeps attempts comparable, and rewind is disabled. Your best run and checkpoint splits save locally without replacing your Calder Circuit record or story checkpoint.

**Gold:** 14 seconds · **Silver:** 20 seconds · **Bronze:** 29 seconds. Press **R** to restart, or select **Race Again** on the results screen.

## Controls

| Action | Touch (Landscape) | Keyboard & Mouse | Gamepad |
| :--- | :--- | :--- | :--- |
| Move & Look | Left virtual stick & right-half drag | WASD / Arrows & mouse drag | Left & Right sticks |
| Sprint & Boost | Sprint & Boost buttons | `Shift` & `F` | `LB` & `RT` |
| Jump, Dodge, Slide | Jump, Dodge, Slide buttons | `Space`, `X`, `C` | `A`, `B`, `R3` |
| Light & Heavy Strike | Strike & Heavy buttons | `J` & `K` | `X` & `Y` |
| Counter & Lock-On | Counter & Lock buttons | `L` & `Tab` | `LT` & D-pad Right |
| Interact | Context Use button | `E` | D-pad Up |
| Speed Force Powers | Powers wheel & Rewind button | `Q` wheel or `1`–`9` direct cast | `RB` wheel + D-pad + `A` |
| Operations & Pause | `OPS` & Pause toolbar | `M` & `Esc` | `Start` / `Menu` |

Use **Ops → Touch layout** to drag/resize any touch control, toggle left-handed mirrored placement, or enable tap-to-sprint. Use **Ops → Rift cache** or **Inventory** to open trail caches and exchange duplicate materials (`3 materials → 1 SFC`).

## Open, Test, and Build from Source

Requires **Godot 4.6.3 stable** and official matching 4.6.3 Web export templates.

```sh
# 1. Import assets
godot --headless --editor --path project-velocity-godot --import

# 2. Run all 9 automated native test suites
GODOT_BIN=godot bash project-velocity-godot/tools/test_native.sh

# 3. Export multi-file WebGL 2 release build
mkdir -p velocity-web
godot --headless --path project-velocity-godot --export-release Web "$(pwd)/velocity-web/index.html"
```

Optional procedural asset regeneration (checked-in GLBs & WAVs are ready to use out of the box):

```sh
python3 project-velocity-godot/tools/build_characters.py
python3 project-velocity-godot/tools/create_audio.py
```

## Documentation

- `RELEASE_NOTES.md` — Summary of all Neon 4 visual, animation, audio, combat, HUD, and performance improvements.
- `FINAL_QA_REPORT.md` — Verified native & Chromium WebGL 2 test evidence, 4-preset benchmarks, visual QA rounds, and honest hardware limitations.
- `CHECKPOINTS.md` — Complete CP01–CP18 execution ledger.
- `ASSET_CREDITS.md` — 100% original asset provenance and Godot engine license notices.
