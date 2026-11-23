# Notes for coding agents

Vantage is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7 that blends the
classic genre with third-person chase episodes. Guillaume asked for something "akin to Sky
Force" (2026-11-23): take only the feel (tilted top-down camera, polished arcade action, permanent
upgrades bought with collected currency). Never use Sky Force's name, art, enemies, levels or look,
and no recreation of any existing game. Star Breaker (`../star-breaker`) is a separate shmup; don't
merge the two.

Design so far (prototype, 2026-11-23; Guillaume's calls in the PR #122 thread):
- One sector (Glass Coast): vertical waves, the **mid-boss** (top-down), more waves, then the **final boss**
  fought in the third-person chase, which ends the sector. Guillaume swapped these on purpose: mid-boss
  top-down, final boss in the chase.
- Bosses are bigger than the screen and taken apart **section by section**; each cleared section breaks
  off its mesh. Mid-boss, the Bastion battleship (`Rules.BOSS_SECTIONS`): bow guns, wing batteries,
  bridge; its hull can't be hurt; it holds the wave clock until it's down. Final boss, the carrier
  (`Rules.CARRIER_SECTIONS`): stern guns (on the `plating` mesh), tower guns (the `tower` mesh), then the
  reactor behind four shield panels (phase `core`). Drones launch from its hangar every `DRONE_EVERY` s.
- The chase is the same world as the vertical stage: the camera blends between poses (`Game.pose()`:
  `top`, `chase`) instead of switching scenes. Keep it that way, it is the game's hook. It stays
  **outside** and in **third person** (Guillaume rejected a first-person tunnel). The carrier grows to
  `CARRIER_SCALE` during the swoop (`car_s`, `car_lift`; `Game.carrier_point()` maps model points to the
  world) and flies `GAP_FAR`/`GAP_NEAR` ahead, so it overflows the screen. It is tall and narrow so
  every target is within the ship's reach (Guillaume found a wide ship's sides hard to hit).
- In the chase the drag moves the ship across the view (`POV_REACH`, `POV_DRAG`), which is how you
  dodge; guns fire ahead with aim assist (`Game.aim_point`). Orbs inherit the rail speed and can be shot.
- Boss targets have generous hit radii (Guillaume found them too small).
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
godot --headless --path . --script tests/game_test.gd   # rules, controls, mid-boss sections, carrier chase (final boss), death, results, world edges
godot --headless --path . --script tests/update_test.gd  # self-update: pack download, checks, APK offer
godot --headless --path . --script tests/icon_test.gd   # project icon and Android launcher layers
godot --headless --path . --script tests/blasts_test.gd # explosions: pieces by size, pool, budget, chains, carry, shake
```

Screenshots (needs a display; one per key moment of a full run):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/shots.gd -- /tmp/shots`

Explosions over time, from both cameras: same command with `tools/blast_shots.gd -- /tmp/blasts`.

Scenery close-ups with no HUD or foes (top view and a low view per stretch of coast):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/scenery.gd -- /tmp/scenery`

Icons: `python3 tools/icon.py` (Pillow) writes `icon.png`, `icons/` and `store/icon-512.png`.

## Code map

- `scripts/rules.gd` (`Rules`): every number (field size, scroll, upgrades and costs, guns, foes, the
  stage's waves by time, the carrier's waves by rail distance), pure functions on the save dictionary.
  Save: `user://save.json`.
- `scripts/models.gd` (`Models`): flat-shaded vertex-coloured meshes built in code (`Models.Builder`:
  `prism`, `box`, `octa`), cached by name. The carrier is one mesh, stern (open hangar) at z = 0, the
  hangar centred on the flight altitude `Rules.PY`.
- `scripts/hud.gd` (`Hud`): the hangar panel is sized by its content and pinned to the bottom
  (`fit_hangar`: grows upwards, clears the gesture bar via the display safe area, scales down on
  short screens to stay under `HANGAR_TOP` + `SHIP_ROOM`); the hangar ship idles centred in the sky
  above it (`Game.hangar_ship_z`). Test layouts at several phone ratios in a SubViewport (a headless
  root window can't be resized).
- Scenery (`Models.scatter`, called per terrain cell from `ground_chunk`): villages of three kinds of
  house (gabled cottage, two-storey with hipped roof, L-shaped farmhouse; windows, doors, chimneys,
  fences or hedges), round-crowned trees, bushes and hay on the grass; pines in the woods; palms,
  driftwood, pebbles, dune grass and parasols on the beaches; rocks with a ring of surf, lighthouses and
  fishing boats along the coast. All of it goes into the chunk's one mesh (no extra draw calls), built
  round its own origin and placed with `Builder.xf`; `Builder.bottoms = false` skips faces under the
  ground. Everything placed with `place()` is drawn `PROP_SCALE` (1.5x) larger so it reads on a phone
  (Guillaume found life size too small); houses keep to one per 4 x 4 lot. `Models.scenery` counts
  what was built (tested).
- `scripts/game.gd` (`Game`): phases (`hangar`, `vert`, `approach`, `pov`, `core`, `escape`,
  `down`, `clear`, `results`), every moving thing as a `Game.Obj`, collisions, effects, camera.
  Vertical objects with `rel = true` move with the scroll frame (`frame_z`); collisions are flat (x, z)
  in the vertical stage and 3D in the chase.
- `scripts/blasts.gd` (`Blasts`, `Game.blasts`): explosions. `Game.pop(at, size, col, ground)` is the one entry
  point for a blast; `blasts.chain`/`later` stagger blasts across a boss section, `burn` keeps a fire going,
  `splash` throws up water. See Gotchas.
- `scripts/hud.gd` (`Hud`): HUD, chase reticle and target brackets (drawn in `_draw`), hangar, results.

## Audio

All original and generated: `tools/audio/compose.py` (numpy + ffmpeg, DSP after perigee's) writes the two music
tracks (`audio/music/sortie.ogg` for the hangar and stage, `carrier.ogg` for both bosses) and every effect in
`audio/sfx/`. Edit the script and rerun it rather than editing the files. Music loops through `loop=true` in its
`.import` file. `scripts/sound.gd` (`Sound`, `Game.sound`) crossfades the tracks on the "Music" bus and plays
effects from a pool on "Sfx", each with its own level and a minimum gap (the cannon fires many times a second).

## Self-update (Android)

Same scheme as mer-des-brumes and star-breaker: `scenes/boot.tscn` (`scripts/boot.gd`) is the main scene. It
checks `update.json` at launch and loads a newer `vantage.pck` built for the same shell; a new shell (engine,
`project.godot`, `export_presets.cfg`, the updater) offers the new APK instead, so avoid needless edits to those
files. `boot.gd` must not use any game class. The hangar also checks quietly and shows a "New version N ·
restart" button (`Game.refresh_game()`). Tests load `scenes/main.tscn` directly.

## Gotchas

- Foes spawn past the edges the camera actually shows (`Game.update_view`: a tall phone sees more than
  the play field), from the top, the sides or the back (`from` in `Rules.STAGE`). Tested.


- Android and Web use the Compatibility renderer. Take screenshots with `--rendering-method gl_compatibility`.
- Vertex colours are sRGB: the shared material sets `vertex_color_is_srgb`.
- The vertical camera looks down at an angle, so anything off the flight plane (ground
  turrets, the battleship's guns) shows somewhere other than straight above it. Collisions,
  missiles and muzzles use `Game.seen(pos)`, the point on the flight plane where it shows.
- Explosions (Guillaume asked for better ones, 2026-11-23): flash, faceted fireball puffs that cool from
  yellow to red into lit grey smoke, embers, tumbling chunks (big ones trail smoke), a shockwave ring, a
  short omni light (at most `Blasts.LIGHTS`), a brief brightness lift for huge ones. Nothing fades with
  alpha except the additive flash/ring/embers: puffs shrink away (cheap and opaque on phones). Nodes are
  pooled and past `Blasts.CAP` live pieces a blast is only its flash. Blasts are carried
  (`Game.fx_carry`): with the scroll in the stage (ground targets' stay put), with the rail in the chase,
  or they'd be left behind the camera. Shake is smooth (sines, not per-frame noise), scaled `shake^1.5`.
- Hits flash: `Obj.hit` puts `Models.hit_mat()` over the foe's mesh for a moment.
- The chase reach (`POV_REACH.x`) must cover every carrier mount at `CARRIER_SCALE` (tested).
- No shadow maps. With `shadow_enabled` on the sun, the Compatibility renderer ignores
  `vertex_color_is_srgb` in the shadowed light pass and every colour washes out to cyan (and shadow
  maps cost on phones). Models get silhouette shadows instead: `Game.cast_shadow_of` adds a flattened
  copy of the mesh, projected along the sun onto `SHADOW_Y` each frame. Those copies are drawn white
  on layer `SHADOW_LAYER` into a half-size mask (`shadow_view`, `shadow_cam` follows `cam`), and one
  see-through plane under the camera (`shadow_plane`, `Models.SHADOW_SHADER`) darkens the ground from
  the blurred mask. Don't draw the flattened copies see-through in the main view: their faces overlap
  and stack into dark patches (Guillaume: "the shadow is not smooth"), and neither the depth pre-pass
  nor the material stencil (a no-op in Compatibility, tested on 4.7) can stop that.
- The look (premium pass): gradient sky shader, filmic tonemap, a cool fill light, rim light on the
  model material, chamfered top edges on straight `prism`s (automatic). The terrain is low poly but
  soft (Guillaume found hard facets too triangular): normals are 80% the land's broad shape (from the
  height field, so chunks meet seamlessly) and 20% facet, colours blend per vertex in narrow bands,
  hollows are darkened. No random per-facet shade.
- After its reactor the carrier noses over, rolls and sinks into the sea for `Rules.CRASH_TIME`
  (`Game.step_crash`, `car_fall`) before the sector clears; it stays in sight (tested).
- In the chase one swipe across `Rules.POV_SWIPE` of the screen crosses the whole reach
  (`Game.pov_drag`), so the ship gets from one flank of the carrier to the other in one move.
- The world has no visible edge: each ground chunk is `CHUNK_W` wide at fine cells plus `CHUNK_FLANK` per
  side in ever wider cells (`Models.ground_cols`, bare of trees), and `CHUNKS_AHEAD` chunks are kept, so the
  ground runs past the fog's end from the chase camera in every direction (tested in `world_edges`).
- `Models.ground_chunk` caps terrain height so the ground stays well under the flight altitude.
- Place HUD controls with anchors and offsets (`Hud.place`), not `position`: the HUD is stretched.
- In a `SceneTree` script, `await process_frame` after `add_child` before stepping the game, or
  `_ready` hasn't run yet.
