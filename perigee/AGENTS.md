# Notes for agents

Perigee is an original one-button orbit-hopping game for iOS and Android. It started as a single HTML canvas
file (`web/index.html`), wrapped as an Android WebView app (`android/`). On 2026-11-16 Guillaume decided to
build the full game in Godot 4.7: the folder is now also a Godot project (`project.godot`, `scripts/`), a port
of the web game. Until the port is confirmed to feel the same on a phone, both are built: the Godot game is the
main preview, and the WebView app is still the Google Play build.

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

- Build number = 1000 + run number of the **Perigee builds** workflow, as for the other games. It is the
  `versionCode` of both APKs (Godot: stamped into `export_presets.cfg` by CI, the committed value is a placeholder;
  WebView: read from the `BUILD` environment variable by `android/build.gradle`). Don't hard-code one.
- All APKs share one app id (`io.github.guillaumefont.perigee`) and `android/debug.keystore`, so a PR build installs
  over the main build, and the Godot and WebView APKs install over each other.
- There is no self-update: a new build means installing the new APK.

## Godot game

- `scripts/sim.gd` holds every rule and must stay deterministic: advance only with `step()` (fixed `DT`,
  120 Hz), and take every random choice that changes the game from `sim.rng`. Looks-only randomness
  (particles, stars, shake) uses `main._vis`. Never read the frame time or `randf()` in the sim.
- Leaving the screen kills, so the play area (`sim.W`, `sim.H`, the viewport in world units) is part of the
  rules. Replays and the future daily run must fix it.
- Moons are numbered by `sim.moons_made`, a running counter. (The web game numbers them by the list length,
  which repeats once far moons are culled, so its difficulty stops ramping after ~12 moons; `sim_test.gd`
  guards against that in the port.)
- The view interpolates between the last two steps (`px/py`, `cam_px/cam_py`). New moving things need
  their previous position kept the same way.
- `main.advance(delta)` is the whole frame; tests call it with process turned off.
- Game input goes through `_unhandled_input` (left mouse button, emulated from touch, plus Space/Enter), so
  HUD buttons that take the tap must not pass it on. Keep `focus_mode = FOCUS_NONE` on buttons so Space
  never activates them.
- The save file is `scripts/save_data.gd`: add new fields to `DEFAULTS`; to change a field's meaning bump
  `VERSION` and add a step to `_migrate()`.
- Scoring (perigee combo and leaps, Guillaume's picks of 2026-11-16) is in `sim.gd` with the same numbers as
  the options page demos: a catch at depth >= `PERIGEE_DEPTH` (0.6) is a perigee worth `2 x mult`; perigees,
  sparks and skipped moons raise `combo`, a shallow catch resets it; `mult = 1 + combo / 2`, up to 5. Catching a
  moon past the next one is a leap (`LEAP_POINTS` 3/9/18 by moons skipped, times `mult`); skipped moons count as
  passed. A graze (within `INNER_GAP` of a surface, not caught) is +1 once per moon per flight.
- `web/`, `android/` and `store/` have a `.gdignore`, so Godot never imports them.
- Android uses the Compatibility renderer, like Star Breaker (the Vulkan Mobile renderer hitched and crashed
  on Guillaume's Pixel). Don't run GDScript on worker threads, and don't use looping `AudioStreamWAV`s or
  `AudioStreamPolyphonic` (both crashed Star Breaker on Android).

## Web prototype

- Everything is inside one IIFE in `web/index.html`. `window.perigeeTest` is a read-only view of the game
  state for the play test; keep its fields (`state`, `score`, `hops`, `holding`, `player`, `planets`) working.
- It must stay self-contained and work offline: no CDN scripts or remote fonts (the play test fails on
  any network request). Add assets under `web/`; the Gradle build copies all of `web/` into the APK.
- Known quirk, kept on purpose as the reference: the difficulty stops ramping after ~12 moons (see above).

## Android and Google Play

- `android/` is a Gradle project (AGP 8.11, compileSdk/targetSdk 36, which Google Play requires). Cloud sessions
  can't reach Google's Maven repository, so the Android build is only checked by the **Perigee builds** workflow.
- Release builds are signed with the Play upload key when `PERIGEE_UPLOAD_KEYSTORE` is set (CI, on `main`),
  otherwise with `debug.keystore`. Never commit the upload key.
- `web/privacy.html` must describe what the app really collects; update it with any new SDK or data. CI also
  publishes it at the site root (`/perigee/privacy.html`), the URL the Play listing uses.
  The Play listing text and Data safety answers are in `store/listing.md`; launch steps in `store/README.md`.

## Tests

- `tests/sim_test.gd` (rules: bot, replay, difficulty ramp, momentum, game over) and `tests/game_test.gd`
  (scene: input, HUD, save, pause/resume, settings) run in `perigee-test.yml` (check "Perigee headless test").
  Each prints `SIM TEST DONE` / `GAME TEST DONE` last; CI greps for it. A new test file gets a step there.
- `tests/prototype_play_test.cjs` tests the web game in Chromium; CI greps for its last line, `PLAY TEST DONE`.
- Every change comes with a test of what it should do; a bug fix gets a regression test.
- Screenshots of the Godot game for reviews: `tools/screenshots.gd` (see README).
