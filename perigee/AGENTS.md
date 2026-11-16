# Notes for agents

Perigee is an original one-button orbit-hopping game for iOS and Android, built in Godot 4.7
(decided by Guillaume, 2026-11-16). It started as a single HTML canvas file, kept in `web/` as
the reference for the feel; the Godot port replaced the Android WebView app on 2026-11-16.

The full-game plan (Claude Doc): https://claude.ai/artifact/5FQoqmDzx2NUVddVyQR8by. Check its
"Decisions and open questions" before assuming platform, business model or online features.

## Pull requests

- Merge via auto-merge (squash) once the required **CI gate** check is green (root `AGENTS.md`).
- Add a **Try it** section to the PR body once the PR number is known:

  ```
  ## Try it
  - Play in the browser: https://guillaumefont.github.io/games/perigee/pr/<N>/
  - Android APK: https://guillaumefont.github.io/games/perigee/pr/<N>/perigee.apk
  - Web prototype (reference): https://guillaumefont.github.io/games/perigee/pr/<N>/prototype/
  ```

## Build numbers

- Build number = 1000 + run number of the **Perigee builds** workflow, as for the other games. It is the APK's
  `versionCode` (stamped into `export_presets.cfg` by CI; the committed value is a placeholder, do not bump it).
- All APKs share one app id (`io.github.guillaumefont.perigee`) and `.github/android/debug.keystore`, so a PR
  build installs over the main build, and the Godot builds install over the old WebView ones.
- No self-update yet: a new build means installing the new APK.

## Game code

- `scripts/sim.gd` holds every rule and must stay deterministic: advance only with `step()` (fixed `DT`,
  120 Hz), and take every random choice that changes the game from `sim.rng`. Looks-only randomness
  (particles, stars, shake) uses `main._vis`. Never read the frame time or `randf()` in the sim.
- Leaving the screen kills, so the play area (`sim.W`, `sim.H`, the viewport in world units) is part of the
  rules. Replays and the future daily run must fix it.
- Moons are numbered by `sim.moons_made`, a running counter. (The prototype numbered them by the list
  length, which repeats once far moons are culled, so its difficulty stopped ramping after ~12 moons;
  `sim_test.gd` guards against that.)
- The view interpolates between the last two steps (`px/py`, `cam_px/cam_py`). New moving things need
  their previous position kept the same way.
- `main.advance(delta)` is the whole frame; tests call it with process turned off.
- Game input goes through `_unhandled_input` (mouse button left, emulated from touch, plus Space/Enter), so
  HUD buttons that take the tap must not pass it on. Keep `focus_mode = FOCUS_NONE` on buttons so Space
  never activates them.
- The save file is `scripts/save_data.gd`: add new fields to `DEFAULTS`; to change a field's meaning bump
  `VERSION` and add a step to `_migrate()`.
- Android uses the Compatibility renderer, like Star Breaker (the Vulkan Mobile renderer hitched and crashed
  on Guillaume's Pixel). Don't run GDScript on worker threads, and don't use looping `AudioStreamWAV`s or
  `AudioStreamPolyphonic` (both crashed Star Breaker on Android).

## Tests

- `tests/sim_test.gd` (rules: bot, replay, difficulty ramp, momentum, game over) and `tests/game_test.gd`
  (scene: input, HUD, save, pause/resume, settings) run in `perigee-test.yml` (check "Perigee headless test").
  Each prints `SIM TEST DONE` / `GAME TEST DONE` last; CI greps for it. A new test file gets a step there.
- `tests/prototype_play_test.cjs` still tests the web prototype in Chromium.
- Every change comes with a test of what it should do; a bug fix gets a regression test.
- Screenshots for reviews: `tools/screenshots.gd` (see README).
