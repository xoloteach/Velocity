# Project Velocity QA at the work pause

This report describes the current build. The complete-production acceptance checklist remains open.

## Verified

- Godot 4.6.3 Compatibility exported the multi-file, single-threaded Web build.
- Chromium loaded the actual release artifacts over HTTP with WebGL 2 and no runtime errors. A real keyboard sprint reached the first objective and earned currency. Browser process restart restored the mission step, currency, and graphics setting. The audio context started after a user gesture.
- Separate native tests passed for city streaming, population, powers (54 assertions), progression and rewind (86), combat, HUD (46), movement (9), and campaign flow (49).
- The integrated native campaign test reached postgame and restored all eight mission reward transactions on reload. Its harness uses controlled placement and combat contacts between tested interactions. Separate combat tests defeated both rivals with actual player commands.
- Chromium touchscreen emulation handled four simultaneous inputs and restored the adjusted touch layout and speed limiter after page reload. This was a separate export iteration before the final graphics-only pass.
- The traversal test reached 134.5 m/s physically, blocked a swept capsule on a 22 cm collider, and checked wall and water running.
- The Chromium SwiftShader capture at 1280 × 800 measured 10.2 FPS on Medium and 8.6 FPS on Low in separate gameplay windows. The city resident count stayed at 10 of a cap of 20. The two measurements represent different gameplay moments and cannot establish a per-preset performance delta.

## Open

- Redmi Pad Pro hardware, actual Android browser GPU frame times, physical controller inputs, and extended play stability still need measurement. The 60 FPS target is unverified.
- The whole campaign has not been played through from browser input. Visual realism, full motion review, and the brief's final presentation checks remain open.
- No external site deployment was made.

See the included browser evidence JSON for the software-rendered measurements.
