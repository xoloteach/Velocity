# Velocity Sol 6.2 local development plan

Baseline `b1586695ff044fd5285b0f3530e48a25dcb72b22`, cloned from `xoloteach/Velocity`; branch `sol62-realism-overhaul`. Project: Godot 4.6.3 Compatibility, single-threaded WebGL 2. The published site deploys the checked-in Web ZIP with Actions; the separate React wrapper does not build the Godot game. Keep all changes local.

1. Recreate a cache-free baseline, run unchanged suites and a clean Web export, capture the startup camera and tablet HUD before editing. Keep independent test saves.
2. Audit collisions, input ownership, current animation tracks, visual asset and audio provenance. Validate first, then fix camera clipping and wheel input leakage without changing control mappings, scene layouts, progression or save version. Extend native integration coverage to run animations on all three rigs.
3. Improve hero anatomy, topology, materials and animation together, then bosses, pedestrians, vehicles and Calder architecture. Validate with fixed-camera comparisons. For third-party models, textures or mocap, record the exact asset license, origin, conversion and credits before bundling. Do not treat the historical Neon 4 report as proof of Sol 6.2.
4. Validate and polish powers, rewind, combat, boss encounters, campaign, economy, touch controls and audio. Add scenario-specific tests without weakening prior assertions. Keep rewind separate from permanent awards.
5. Profile the specified scenarios on each quality preset, verify fresh and migrated saves, repeat full campaign and tablet-browser interaction, complete three visual review rounds, and test a clean unpack/rebuild. Separate CPU SwiftShader results from physical tablet performance.
6. Do not package or distribute a final build until CP24; no push, release or deployment.
