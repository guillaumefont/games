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
- Kinds of moon (`Planet.kind`): `twin` (a linked pair with the same `k`, sharing a figure-eight ring; catching
  either counts both), `retro` (the orbit reverses: `vt` starts negative and eases through zero), `pulsar` (the ring
  only catches while `lit(t)`). `sim.recipe.mix` weights them; an empty recipe is the endless mode and rolls nothing,
  so its worlds stay exactly as before. The lab buttons on the start and game over cards run one kind (never for
  the best score); they are for the vertical slice, not for release.
- Voyage (`scripts/voyage.gd`): systems of short sectors, each a fixed seed plus a recipe. Recipe keys the sim
  reads: `moons` (the waypoint is moon `k == moons`; catching it sets `state = "clear"`), `k_offset` (starts the
  difficulty curve further on), `zigzag` (for each `k`, moon k+1 sits off to the side and moon k+2 back in line with
  k, a shortcut line to leap), `mix`. Stars: clear, under `par`, the sector's goal. Pars come from
  `tools/par_times.gd` (bot best + 35%); rerun it after changing a sector or the rules, and keep `voyage_test.gd`
  green (the bot must clear every sector). Progress is `save.data.voyage[id] = {stars, score, time}`.
- Audio is original and generated: `tools/audio/compose.py` (numpy + ffmpeg) writes the music track and every
  sound effect to `audio/` as Ogg. Edit the script and rerun it rather than editing the files; keep the effects in
  D major pentatonic so they sit on the music. The music loops through `loop=true` in its `.import` file (a looping
  Ogg is fine on Android; looping WAVs are not). Music plays on the "Music" bus, effects on "Sfx" (`Sfx.ensure_buses()`).
- First run: until `save.data.tutorial_done`, the start card's tap starts the tutorial (`main.start_tutorial()`,
  a fixed seed and the recipe `{"moons": 6, "rescue": true}`; `rescue` turns a death into a return to the moon of the
  last fling, so the tutorial never ends in game over). Settings' "How to play" replays it. Tests that expect the start
  card to start Drift set `tutorial_done` from `main.ready` (see `game_test.gd`).
- Settings live in `save.data.settings` (volumes on the Music/Sfx buses, vibration, aim guide, reduced motion,
  high-contrast rings). Assists may change what you see, never how points are scored. The future Daily must record
  whether the aim guide was on.
- The spark unlock track (`scripts/unlocks.gd`): all-time sparks (`save.data.sparks`, banked by `main._bank_sparks()`
  at the end of every Drift and Voyage run) unlock cosmetics in a fixed order; `save.data.equipped` holds one id per
  kind (ship, trail, palette). No random rewards. Cosmetics are drawn by `scripts/looks.gd` and must stay looks-only;
  palettes keep four moon colours apart by lightness too. The Hangar card shows the track and equips items.
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

- `tests/sim_test.gd` (rules: bot, replay, difficulty ramp, momentum, game over), `tests/game_test.gd`
  (scene: input, HUD, save, pause/resume, settings) and `tests/voyage_test.gd` (sectors, stars, unlocks, Voyage
  screens) `tests/onboarding_test.gd` (tutorial, settings) and `tests/unlocks_test.gd` (unlock track, hangar) run in `perigee-test.yml` (check "Perigee headless test").
  Each prints `SIM TEST DONE` / `GAME TEST DONE` / `VOYAGE TEST DONE` / `ONBOARDING TEST DONE` / `UNLOCKS TEST DONE` last; CI greps for it. A new test file gets a step there.
- `tests/prototype_play_test.cjs` tests the web game in Chromium; CI greps for its last line, `PLAY TEST DONE`.
- Every change comes with a test of what it should do; a bug fix gets a regression test.
- Screenshots of the Godot game for reviews: `tools/screenshots.gd` (see README).
