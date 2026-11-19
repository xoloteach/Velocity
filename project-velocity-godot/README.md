# Project Velocity

A third-person Godot speedster game set in Calder. The campaign follows eight operations across the city and Rift. Postgame includes street patrol, two time trials, chapter replay, and offline progression.

## Play the Web export

Extract the Web archive into a directory. Keep all the `index.*` files together and serve the directory over HTTP.

```sh
python3 -m http.server 8080 --directory velocity-web
```

Open `http://localhost:8080/` in a WebGL 2 browser. For a tablet on the same network, use the server's LAN address. Existing static hosting also works when it serves `.wasm` as `application/wasm`. The matching Godot single-thread export requires no cross-origin isolation headers. Start in landscape, tap the canvas to enable audio, and use **Ops → Settings** for performance and comfort. Match the URL, origin, and browser profile between sessions to keep the same local save.

## Controls

| Action | Touch | Keyboard or mouse | Controller |
| --- | --- | --- | --- |
| Move and look | Move pad and right drag | WASD or arrows and right-mouse drag | Sticks |
| Sprint and boost | Run and boost buttons | Shift and F | LB and RT |
| Jump, dodge, slide | Jump, dodge, slide | Space, X, C | A, B, right stick click |
| Light and heavy | Strike and heavy | J and K | X and Y |
| Counter and lock | Counter and lock | L and Tab | LT and D-pad right |
| Interact | Context button | E | D-pad up |
| Abilities | Wheel and dedicated rewind | Q or 1–9 | RB wheel; D-pad rewind and lightning |
| Pause and settings | Pause and Ops | Esc and M | Menu and View |

Use Ops for mission clues, the map, cache odds, upgrades, and the touch layout editor. Customize the slider if a high speed makes a turn or rescue difficult. Save settings and awards are stored on this browser. Read `docs/PROGRESSION_REWIND.md` for the difference between reversible world state and permanent rewards.

## Open or build the source

Use Godot **4.6.3 stable**, Compatibility rendering, and the official matching Web export templates. Blender **4.3.2** and Python 3 can regenerate original art and WAV files. The build uses the checked-in GLB and WAV files, so regeneration is optional.

```sh
godot --headless --editor --path . --import
mkdir -p ../velocity-web
godot --headless --path . --export-release Web ../velocity-web/index.html
```

The Web preset produces a single-thread, multi-file export. It runs GDScript without native extensions or internet requests for game assets. WebGL capability checks are built into Godot's export page.

```sh
blender -b -t 4 -P tools/create_runner.py
python3 tools/create_audio.py
```

The current repository includes the main scene in `scenes/game.tscn`, subsystem code under `systems/`, project data under `shared/`, and scoped tests under `tests/`. See `CHECKPOINTS.md`, `QA_REPORT.md`, and `ASSET_CREDITS.md` for validation and provenance.

Godot references

- [Exporting for the Web](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_web.html)
- [CharacterBody3D](https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html)
- [JavaScriptBridge filesystem synchronization](https://docs.godotengine.org/en/4.6/classes/class_javascriptbridge.html)
