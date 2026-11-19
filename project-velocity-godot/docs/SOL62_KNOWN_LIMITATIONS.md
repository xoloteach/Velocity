# Sol 6.2 known limitations

- Physical Android tablet, mobile GPU, and hardware gamepad: NOT RUN / PHYSICAL HARDWARE UNAVAILABLE.
- Do not distribute an interim archive as a final build. Track remaining software and visual acceptance in `CHECKPOINTS_SOL62.md`.

- Existing 1280×800 Chromium touch suite passed on the local candidate. A separate 800×500 probe observed a saved joystick record in IndexedDB but did not reproduce the expected rendered location after reload; the cause was not established. Do not interpret one desktop-browser run as physical tablet validation.
- Hero and boss rig playback coverage does not substitute for a new realistic hero, cinematic materials and mocap. Art, audio, playable end-to-end campaign QA and the preset performance matrix are not signed off.
- No GitHub workflow run, push, Pages change, or release packaging was performed for Sol 6.2.
