# Notes for coding agents

Vantage is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7 that blends the
classic genre with first-person (cockpit) episodes. Guillaume asked for something "akin to Sky
Force" (2026-11-23): take only the feel (tilted top-down camera, polished arcade action, permanent
upgrades bought with collected currency). Never use Sky Force's name, art, enemies, levels or look,
and no recreation of any existing game. Star Breaker (`../star-breaker`) is a separate shmup; don't
merge the two.

Design so far (first prototype, 2026-11-23):
- One sector (Glass Coast): vertical waves, a carrier episode in the middle, more waves, a boss.
- The POV episode is the same world as the vertical stage: the camera blends between poses
  (`Game.pose()`: `top`, `chase`, `cockpit`) instead of switching scenes. Keep it that way, it is the
  game's hook.
- In the cockpit, the drag moves a reticle; the ship drifts towards it within the tunnel
  (`Rules.POV_REACH`), which is how you dodge. Energy orbs can be shot down.
- Scrap is the only currency and is kept even when shot down. Upgrades apply in both modes.

## Pull requests

- **Merging:** see the root [`AGENTS.md`](../AGENTS.md).
- Every PR body lists its preview builds near the top, under a `## Preview` heading:

  ```
  ## Preview
  - Play in the browser: https://guillaumefont.github.io/games/vantage/pr/<N>/
  - Android APK: https://guillaumefont.github.io/games/vantage/pr/<N>/vantage.apk
  ```
- All APKs share one app id (`io.github.guillaumefont.vantage`) and one test keystore
  (`.github/android/debug.keystore`), so a PR build installs over the `main` build.
- No self-update (`boot.gd`) yet, unlike the other games.

## Keeping this file up to date

When you learn something a future agent would need, add it here in your PR, short and lasting, and say so
under an `## AGENTS.md` heading in the PR body.

## Tests

- Every change comes with a test; a bug fix gets a regression test. A new test file gets a step in
  `.github/workflows/vantage-test.yml` (at the repo root) and a line below.
- Game tests load `scenes/main.tscn` with `driven = true` (so `_process` doesn't run) and `save_path`
  set to a test file, then call `step(dt)` themselves. `run()` in the test has an autopilot that aims at
  the nearest foe inside the carrier.

```
godot --headless --path . --import
godot --headless --path . --script tests/game_test.gd   # rules, controls, carrier episode, boss, death, results
godot --headless --path . --script tests/icon_test.gd   # project icon and Android launcher layers
```

Screenshots (needs a display; one per key moment of a full run):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/shots.gd -- /tmp/shots`

Icons: `python3 tools/icon.py` (Pillow) writes `icon.png`, `icons/` and `store/icon-512.png`.

## Code map

- `scripts/rules.gd` (`Rules`): every number (field size, scroll, upgrades and costs, guns, foes, the
  stage's waves by time, the carrier's waves by rail distance), pure functions on the save dictionary.
  Save: `user://save.json`.
- `scripts/models.gd` (`Models`): flat-shaded vertex-coloured meshes built in code (`Models.Builder`:
  `prism`, `box`, `octa`), cached by name. The carrier is one mesh, stern (hangar mouth) at z = 0, its
  tunnel centred on the flight altitude `Rules.PY`.
- `scripts/game.gd` (`Game`): phases (`hangar`, `vert`, `approach`, `pov`, `core`, `escape`, `exit`,
  `down`, `clear`, `results`), every moving thing as a `Game.Obj`, collisions, effects, camera.
  Vertical objects with `rel = true` move with the scroll frame (`frame_z`); collisions are flat (x, z)
  in the vertical stage and 3D in the cockpit.
- `scripts/hud.gd` (`Hud`): HUD, cockpit canopy and reticle (drawn in `_draw`), hangar, results.

## Gotchas

- Android and Web use the Compatibility renderer. Take screenshots with `--rendering-method gl_compatibility`.
- Vertex colours are sRGB: the shared material sets `vertex_color_is_srgb`.
- The ground must stay below the carrier's tunnel floor (y = 3), or trees poke into the cockpit view:
  `Models.ground_chunk` caps terrain height.
- Place HUD controls with anchors and offsets (`Hud.place`), not `position`: the HUD is stretched.
- In a `SceneTree` script, `await process_frame` after `add_child` before stepping the game, or
  `_ready` hasn't run yet.
