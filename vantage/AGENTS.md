# Notes for coding agents

Vantage is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7 that blends the
classic genre with third-person chase episodes. Guillaume asked for something "akin to Sky
Force" (2026-11-23): take only the feel (tilted top-down camera, polished arcade action, permanent
upgrades bought with collected currency). Never use Sky Force's name, art, enemies, levels or look,
and no recreation of any existing game. Star Breaker (`../star-breaker`) is a separate shmup; don't
merge the two.

Design so far (first prototype, 2026-11-23):
- One sector (Glass Coast): vertical waves, a carrier episode in the middle, more waves, a boss.
- The chase episode is the same world as the vertical stage: the camera blends between poses
  (`Game.pose()`: `top`, `chase`) instead of switching scenes. Keep it that way, it is the game's hook.
- Guillaume's call (2026-11-23, after the first version flew into a tunnel in first person): the
  episode stays **outside** and in **third person**. The ship chases the carrier on rails
  (`Rules.RAIL`, `GAP_FAR`/`GAP_NEAR`); the drag moves the ship across the view (`Rules.POV_REACH`,
  `POV_DRAG`), which is how you dodge; guns fire ahead with aim assist (`Game.aim_point`). Turrets and
  the reactor are mounted on the carrier (`Obj.anchor`, relative to its stern). The carrier is tall and
  narrow (Guillaume, 2026-11-23: targets on a wide ship's sides were hard to hit on a portrait screen),
  so every mount (`Rules.MOUNTS`) is within the ship's reach; the ship climbs high to reach the tower. Orbs inherit the rail
  speed (they fly with the ship's frame) and can be shot down.
- The sector boss (Guillaume, 2026-11-23: "bigger boss, addressed by sections") is a battleship wider
  than the screen taken apart in order: bow guns, wing batteries, then the bridge (`Rules.BOSS_SECTIONS`).
  The hull can't be hurt; each cleared section breaks off its mesh (`bow`, `wings`) and the ship pushes
  closer. Boss targets and the carrier's reactor have generous hit radii (Guillaume found them too small).
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
  set to a test file, then call `step(dt)` themselves. `run()` in the test has an autopilot that lines up
  with the nearest foe in the chase.

```
godot --headless --path . --import
godot --headless --path . --script tests/game_test.gd   # rules, controls, carrier chase, boss, death, results
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
  `prism`, `box`, `octa`), cached by name. The carrier is one mesh, stern (open hangar) at z = 0, the
  hangar centred on the flight altitude `Rules.PY`.
- `scripts/game.gd` (`Game`): phases (`hangar`, `vert`, `approach`, `pov`, `core`, `escape`, `exit`,
  `down`, `clear`, `results`), every moving thing as a `Game.Obj`, collisions, effects, camera.
  Vertical objects with `rel = true` move with the scroll frame (`frame_z`); collisions are flat (x, z)
  in the vertical stage and 3D in the chase.
- `scripts/hud.gd` (`Hud`): HUD, chase reticle and target brackets (drawn in `_draw`), hangar, results.

## Gotchas

- Android and Web use the Compatibility renderer. Take screenshots with `--rendering-method gl_compatibility`.
- Vertex colours are sRGB: the shared material sets `vertex_color_is_srgb`.
- `Models.ground_chunk` caps terrain height so the ground stays well under the flight altitude.
- Place HUD controls with anchors and offsets (`Hud.place`), not `position`: the HUD is stretched.
- In a `SceneTree` script, `await process_frame` after `add_child` before stepping the game, or
  `_ready` hasn't run yet.
