# Sol 6.2 checkpoint ledger

| Gate | Scope | Status | Evidence / remaining |
| --- | --- | --- | --- |
| CP01 | Clone and baseline | VERIFIED | Clean archive import and native regression in `baseline-native.log`; shipped Web 16:10 capture in `archive-hud/touch-hud-16x10.png`; baseline `b158669` |
| CP02 | Web boot | VERIFIED | Matching 4.6.3 nonthreaded export, local HTTP file loads and actual touch-controlled Chromium WebGL 2 canvas; `base-export.log`, `base-browser/browser.json`, `work-hud/` |
| CP03 | Native regression | VERIFIED | Original `tools/test_native.sh`: 9/9 process exits; campaign teardown warning recorded |
| CP04 | Asset provenance | IN PROGRESS | Existing original-asset credits inventoried; replacement licenses not selected |
| CP05 | Hero geometry | NOT STARTED | Final gate evidence not collected |
| CP06 | Mocap | IN PROGRESS | Existing hero and boss rigs: 87/87 sampled clips with valid bone paths and finite poses; no mocap replacement or foot-contact sign-off |
| CP07 | Camera and controls | IN PROGRESS | `ed291c7` adds swept clearance on damped camera motion, scoped wheel input and surface-aware contact shadow. `sol62_controls_test`: 10/10; browser touch movement exercised; sustained scenario coverage incomplete |
| CP08 | Boss art | NOT STARTED | Final gate evidence not collected |
| CP09 | Civilian art | NOT STARTED | Final gate evidence not collected |
| CP10 | Vehicle traffic | NOT STARTED | Final gate evidence not collected |
| CP11 | Architecture | NOT STARTED | Final gate evidence not collected |
| CP12 | Streaming and skyline | NOT STARTED | Final gate evidence not collected |
| CP13 | Speed and transit | NOT STARTED | Final gate evidence not collected |
| CP14 | Nine powers | NOT STARTED | Final gate evidence not collected |
| CP15 | Rewind | NOT STARTED | Final gate evidence not collected |
| CP16 | Combat | NOT STARTED | Final gate evidence not collected |
| CP17 | Boss fights | NOT STARTED | Final gate evidence not collected |
| CP18 | Campaign | NOT STARTED | Final gate evidence not collected |
| CP19 | Progression | NOT STARTED | Final gate evidence not collected |
| CP20 | HUD and audio | IN PROGRESS | Chromium SwiftShader: existing 1280×800 touch suite passed through four pointers, limiter, edited layout, reload, and 1280×720 resize after local changes (`work-hud.log`). A separate 800×500 probe saw the IndexedDB write but did not verify restored rendering at its expected coordinates. Full device/audio matrix remains unverified |
| CP21 | Performance | NOT STARTED | Final gate evidence not collected |
| CP22 | Visual QA rounds | NOT STARTED | Final gate evidence not collected |
| CP23 | Clean-room final QA | IN PROGRESS | All 11 native suites passed locally; internal Web build exported and booted; not a clean-room final sign-off |
| CP24 | Final handoff | NOT STARTED | Unmet acceptance gates; no release ZIP, push or deployment |

Raw command output and browser captures are held in the local `sol62-evidence` workspace directory; no evidence of a real Android performance pass.
