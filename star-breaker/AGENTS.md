# Notes for coding agents

Star Breaker is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7. It
started as a landscape side-scroller in the genre of R-Type II; all content stays original:
never use R-Type names, art, enemies or levels, and no recreation of existing games.
Guillaume wants a modern mobile-game look (glass HUD, bloom, Rubik font), not retro.
Portrait only since 2026-11-17 (Guillaume: "switch the whole game to portrait now that we are
committed"); the landscape game was removed, its history is in git before that date.
Controls: drag anywhere to fly 1:1 (fires while the thumb is down), lift = the ship's release
(Lance: charge beam; Warden: fling or recall the pod), double tap = ultimate (a second finger or the ULT button work too).

## Pull requests

- **Merging:** see the root [`AGENTS.md`](../AGENTS.md): auto-merge only, once all checks are green
  (the required **CI gate** check).
- Every PR body lists its preview builds near the top, under a `## Preview` heading:

  ```
  ## Preview
  - Play in the browser: https://guillaumefont.github.io/games/star-breaker/pr/<N>/
  - Android APK: https://guillaumefont.github.io/games/star-breaker/pr/<N>/star-breaker.apk
  ```

  The **Builds** workflow publishes them on every push to the PR and deletes them when it
  closes. `main` is at https://guillaumefont.github.io/games/star-breaker/ (needs Settings > Pages >
  Source = GitHub Actions).
- All APKs share one app id (`io.github.guillaumefont.starbreaker`) and one test keystore
  (`.github/android/debug.keystore`), so a PR build installs over the `main` build.

## Keeping this file up to date

- When you learn something a future agent would need (a convention, a gotcha, a check to run),
  add it here in your PR. Keep entries short and lasting. Say what you added under an
  `## AGENTS.md` heading in the PR body and mention it in your reply to Guillaume.

## Tests

- Every change comes with a test of what it should do; a bug fix gets a regression test.
- A new test file gets a step in `.github/workflows/star-breaker-test.yml` (at the repo root) and a line below.
- Test logic headlessly: load `scenes/main.tscn`, turn physics and process off, set
  `driven = true` (otherwise `_physics_process` overwrites `inp` from real input) and call
  `update()` / `_process()` yourself with your own `inp` (see `tests/vertical_test.gd`).

## Checks to run before pushing

```
godot --headless --path . --import
godot --headless --path . --script tests/vertical_test.gd # the game: drag, charge beam, pod, ultimates, barriers, rock, bosses
godot --headless --path . --script tests/screen_test.gd  # crash report, safe graphics, menu device row, bests, screen shapes
godot --headless --path . --script tests/audio_test.gd   # songs build on the main thread, sound effects exist
godot --headless --path . --script tests/update_test.gd  # self-update: pack download, checks, APK offer
godot --headless --path . --script tests/icon_test.gd    # project icon and Android launcher icon layers
godot --headless --path . --script tests/visuals_test.gd # shadows, ground chunks, laser strands, explosions
```

Screenshots (needs a display): `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/vertical_shots.gd -- /tmp/vshots`

## App icon

- Icon (Guillaume's pick 2026-11-15, after many rounds): the game's crystal pod at a three
  quarter angle (ring and pink shards) with the ship docked behind it at true scale (only its
  nose and cockpit show), the group pulled back and moved right (`ZOOM`, `SHIFT` in
  tools/icon.py), on a dark violet gradient with white warp lines along the flight: ten lines in
  evenly spaced lanes, listed in `WARP` (30 random ones were "too clustered"; thin white streaks
  were rejected). He wants it clean: no frame, no scenery, no clutter, and a preview picture of
  every icon change before it ships.
- Two steps: `tools/icon_shots.gd` renders the game's own models to `store/pod.png` (pod alone)
  and `store/ship-pod.png` (ship and pod on a 3x wider canvas, same projection); rerun after
  changing a model:
  `xvfb-run -a -s "-screen 0 3200x3200x24" godot --path . --rendering-method gl_compatibility --resolution 3072x3072 --script tools/icon_shots.gd`,
  then `python3 tools/icon.py` (Pillow) rewrites `icon.png` (project icon and web favicon),
  `icons/` (launcher icon and adaptive background, foreground and monochrome layers) and
  `store/icon-512.png`. Commit the PNGs; CI runs neither.
- A launcher icon lives in the APK, not the game pack: a new icon only shows after installing
  a new APK.

## Self-update (Android)

- The main scene is `scenes/boot.tscn` (`scripts/boot.gd`): at launch it fetches `update.json`
  from Pages and, if a newer build was made for the same **shell**, downloads
  `star-breaker.pck` (the whole game, ~200 KB), checks its SHA-256 and loads it over the bundled
  game with `ProjectSettings.load_resource_pack()`. No reinstall needed.
- The shell id (set by CI) hashes what a pack can't change: Godot version, `project.godot`,
  `export_presets.cfg` and the updater (`boot.gd`, `boot.tscn`). Editing any of those makes
  the app offer a new APK download instead, so avoid needless changes to them.
- `boot.gd` must not use any game class (`Diag`, `Models`, ...): touching one before the pack
  loads would keep the bundled version. Tests and tools load `scenes/main.tscn` directly.
- PR APKs follow `pr/N/update.json`, then main once the preview is gone.
- The menu's build line (`hud.btn_build` in `vhud.gd`) shows the running build and, after a quiet check of
  `update.json`, "New build N". Tapping it restarts the game (`refresh_game()` in `vgame.gd`): on
  Android `OS.set_restart_on_exit()` + `quit()` relaunches the app (Godot's activity rebirth),
  so boot.gd's launch check loads the newest pack; the web page just reloads. A pack can't be
  swapped in without a restart: scripts already loaded stay cached.

## Gotchas

- Don't run GDScript on worker threads (`WorkerThreadPool`, `Thread`): song synthesis on a
  worker thread was the suspected cause of the Android build crashing seconds after start-up.
  Spread heavy work over frames on the main thread instead (see `scripts/audio.gd`).
- The Android build still crashed a few seconds into a run after that. It runs fine on desktop
  (debug and release templates, Mobile renderer), so the next suspects were Android-only paths:
  sounds now use a pool of `AudioStreamPlayer`s (no `AudioStreamPolyphonic`) and stars are
  MultiMesh quads (no GL point sprites). Keep it that way unless a phone test proves otherwise.
- Crash reports from phones: `scripts/diag.gd` writes breadcrumbs to `user://diag.log` (a TICK
  line every second, FIRST line for each new enemy/sound/effect). If the last session didn't end
  with SUSPEND or QUIT, the menu shows where it stopped with a "Copy crash report" button,
  and safe graphics turn on (no glow/MSAA). Ask Guillaume for that report instead of guessing. Add `Diag.once()`
  breadcrumbs to new features.
- No looping `AudioStreamWAV` (`loop_mode`): the Android build crashed when the stage song first
  hit its loop point. Songs restart from the player's `finished` signal instead.
- Android uses the Compatibility (OpenGL ES) renderer: on Guillaume's Pixel (PowerVR GPU) the
  Vulkan Mobile renderer hitched each time a new kind of object appeared and then crashed. An
  `override.cfg` renderer switch was ignored there, so it is set in `project.godot`.
- `_warm_up()` in `vgame.gd` draws every model and material once behind the menu; add any
  new model or material to it so its first appearance in a stage doesn't hitch.
- The game fills any screen (base canvas 720 x 1280, stretch aspect `expand`); the camera
  always fits the whole 126-unit stage width (`_on_resize`).

- UI is built in code: use `set_anchors_and_offsets_preset()`; plain `set_anchors_preset()`
  keeps the old (zero) size.
- Simulated touches in headless tests must go through `root.push_input(event, true)`.
- GDScript can't infer types from Dictionary fields: write `var k: float = d.x * 2`, not `:=`.

## The look (2026-11-17 visual upgrade)

- A low sun (`sun` in `vgame.gd`) casts real shadows (one 2048 orthogonal map); safe graphics turn
  them off. `Models.mesh()` makes lit opaque parts cast and glows/see-through parts not: keep
  glows unshaded so they never throw shadows. Depth fog sinks the floor into violet; the camera
  sits closer (`CAM_D`) for parallax between the play plane and the ground 68 units below.
- The ground is `scripts/terrain.gd`: a pure function of world position (craters, mesas, ridges,
  crystals, boulders, fissures), vertex coloured, one draw call per material per chunk. Chunks are
  built a slice per frame ahead of time (`Terrain.Builder`, `_building` in `vgame.gd`); building
  one in a single frame cost ~3 ms on desktop, so keep new terrain work inside the builder.
  Canyon walls and islands use `Terrain.cliff()` (faceted top, banded face) plus the glowing lip.
- Weapon effects are `scripts/vfx.gd`: the laser-strand charge and Nova twister come from the
  landscape game's beam (git history before 2026-11-17, `main.gd` `sync_charge_fx`/`fire_beam`),
  turned to fly up the screen. Lights are few on purpose (Compatibility renders each omni light as
  an extra pass): one for the charge/beam, two pooled for explosions, all off in safe graphics.
- Clear `user://diag.log` / `settings.cfg` before taking screenshots: a killed run counts as a
  crash and the next launch turns safe graphics on (no glow, no shadows).

## The game

- `scenes/main.tscn` runs `scripts/vgame.gd` (game, menu flow, save, updates), with
  `vhud.gd` (HUD and menus), `vships.gd` (ship kits and models) and `vstage.gd` (seeded stage
  events, rock). The `v` names are from the portrait slice; there is no other game now.
- Stage units are 126 x 224 with y up, 60 ticks a second; `X()` / `Y()` in `vgame.gd` map them
  to 3D. Side-view models are turned top-down by `VShips.upright()`.
- Portrait is set in `project.godot` (orientation and a 720 x 1280 base canvas): that's a shell
  change, so it came with a new APK.
- Content today: world 1 (The Hollow Moon) as three stages, Lance and Warden. Best score per
  stage is saved under `[portrait] bests` in `user://save.cfg`.
- The menu's device row: sound, graphics (safe = no glow/MSAA), and the build line; the crash
  notice with "Copy crash report" sits above it after a session that didn't end cleanly.
- Back on the menu quits the app; on a result it goes to the menu; in play it pauses.
- Rock is an occasional set piece, not the whole stage (Guillaume found the always-on corridor
  of the Edge experiment boring): one short canyon (`VStage.CANYONS`, walls slide in and out)
  and two islands (`VStage.ISLANDS`, a lozenge of rock in the open) per stage. Rock costs a
  hull point, stops shots and bullets, and pays a scrape bonus for flying close. Spawns go
  through `_fit()` so nothing starts inside a canyon wall; keep rock away from barriers and
  the boss (the test checks every stage). Charging stays free (Edge's silent guns read as
  broken).
