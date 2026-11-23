# Notes for coding agents

Vantage is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7 that blends the
classic genre with third-person chase episodes. Guillaume asked for something "akin to Sky
Force" (2026-11-23): take only the feel (tilted top-down camera, polished arcade action, permanent
upgrades bought with collected currency). Never use Sky Force's name, art, enemies, levels or look,
and no recreation of any existing game. Star Breaker (`../star-breaker`) is a separate shmup; don't
merge the two.

Design so far (prototype, 2026-11-23; Guillaume's calls in the PR #122 thread):
- The original sector, now level 1-3 (see Campaign below): vertical waves, the **mid-boss** (top-down), more waves, then the **final boss**
  fought in the third-person chase, which ends the sector. Guillaume swapped these on purpose: mid-boss
  top-down, final boss in the chase.
- Bosses are bigger than the screen and taken apart **section by section**; each cleared section breaks
  off its mesh. Mid-bosses (`Rules.MIDBOSSES`, five designs: Bastion battleship, Mantis gunship, Halo
  platform, Corsair twin hull, Hammerhead dreadnought): each section lists its parts (kinds in
  `Rules.BOSS_PART_KINDS`, patterns in `Game.think_part`) and a `piece` (`Models.midboss_piece`) that
  breaks off; the last section is the heart (`BOSS_HEARTS`), shielded until then. Each flies its own way
  (`move`, `Game.think_boss`); the hull comes down far enough that the section's deepest gun shows on a
  short screen. Parts stay within |x| <= 7, z -5..8 (tested). The hull can't be hurt; it holds the wave
  clock until it's down. Its part hp scales by `Campaign.BOSS_HP` (first level of a world quicker). Final boss, a flying
  fortress (Guillaume turned the sea carrier into one, 2026-11-23): a huge armoured aircraft. Five designs
  (`Rules.FORTRESSES`: Goliath, Zephyr airship, Talon jet, Leviathan, Wyvern), each with its hull section
  (`hull`: box, round, hex), wings (`Models.WINGS`: propellers, stubs, jets; a jet's "props" are nozzles that
  don't spin), tail (`fins`), `paint`, `accent` and drone rate (`drones` s). Its sections' gun mounts sit on a
  `piece` that breaks off (`plating`, `collar`, `tower`, `fin`: `Models.fortress_piece`; z from
  `Models.mount_z`); the last is the reactor behind four shield panels (phase `core`). The bay, `FORTRESS_HW`
  and the mount limits (|x| <= 4.6, y 2..19.6) are shared, so every gun stays within the chase's reach.
- The chase is the same world as the vertical stage: the camera blends between poses (`Game.pose()`:
  `top`, `chase`) instead of switching scenes. Keep it that way, it is the game's hook. It stays
  **outside** and in **third person** (Guillaume rejected a first-person tunnel). The fortress grows to
  `FORTRESS_SCALE` during the swoop (`fort_s`, `fort_lift`; `Game.fort_point()` maps model points to the
  world) and flies `GAP_FAR`/`GAP_NEAR` ahead, far enough that its whole stern, the inner wings and
  their engines show while the wing tips run off the screen (Guillaume: "you don't see much of the
  spaceship"); the chase camera sits a little high and looks far ahead. Its body is narrow so every
  target is within the ship's reach (Guillaume found a wide ship's sides hard to hit).
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
godot --headless --path . --script tests/game_test.gd   # rules, controls, readable bullets, mid-boss sections, fortress chase (final boss), ramming, death, results, world edges
godot --headless --path . --script tests/campaign_test.gd  # worlds and levels, unlocks, level select, world looks, a full level, every mid-boss and fortress
godot --headless --path . --script tests/foes_test.gd   # campaign foes: one new kind a level, kept after; each comes in off-screen, attacks, flashes, goes down
godot --headless --path . --script tests/update_test.gd  # self-update: pack download, checks, APK offer
godot --headless --path . --script tests/icon_test.gd   # project icon and Android launcher layers
godot --headless --path . --script tests/blasts_test.gd # explosions: pieces by size, pool, budget, chains, carry, shake
```

Screenshots (needs a display; one per key moment of a full run):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/shots.gd -- /tmp/shots`

Explosions over time, from both cameras: same command with `tools/blast_shots.gd -- /tmp/blasts`.

Every mid-boss as it arrives and after its first section: same command with `tools/midboss_shots.gd -- /tmp/midbosses`.

The final boss alone, without playing the stage (arrival, swoop, each section, an overview with no fog, the
fall): same command with `tools/fortress_shots.gd -- /tmp/fortress`. Every fortress side by side (from above, on its
tail, an overview, after its first section): `tools/fortress_lineup.gd -- /tmp/fortresses`.

Scenery close-ups with no HUD or foes (top view and a low view per stretch of coast):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/scenery.gd -- /tmp/scenery [theme]`

Every campaign foe in play over its world: same command with `tools/foe_shots.gd -- /tmp/foes`.

Every world (hangar, play, battleship): `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/worlds.gd -- /tmp/worlds`

Icons: `python3 tools/icon.py` (Pillow) writes `icon.png`, `icons/` and `store/icon-512.png`.

## Campaign (Guillaume, 2026-11-23: "a real timeline, with worlds and levels")

- `scripts/campaign.gd` (`Campaign`): five worlds (Glass Coast, Ember Dunes, Iron Sprawl, Frost Shelf,
  Cinder Reach) of three levels each, played in order. Guillaume (2026-11-23): "mid bosses and final
  fortresses for every level", so every level is waves, a mid-boss, waves, the fortress chase
  (`LENGTHS`: the first level of a world shortest). Each level has its own mid-boss (`midboss_of`:
  three different ones per world, `MIDBOSS_ORDER`); 1-3 is the hand-made `Rules.STAGE` and keeps the
  Bastion. Every other level's waves come from its world's `mix`, seeded by the level (same every time).
  The hangar's level buttons name the level's mid-boss. (`Game.level_clear` and the `end` wave remain
  for a level without a fortress, though none uses them now.)
- Each world has a terrain `theme` (`Models.THEMES`: sky, fog, light, `lift` of the land out of the
  water; `Models.ground_col` and `Models.theme_prop` per theme; Glass Coast keeps the original props in
  `ground_chunk`), and multipliers on foe hull (`tough`), bullet speed (`fire`) and `scrap`. Boss hulls
  take the world's `tint`. `Models.theme` is a static var set by `Game.apply_theme`.
- Save: `sel` (selected level), `open` (furthest open level), `grades` ("1-1" → best grade).
  Clearing a level opens and selects the next. Old saves with a clear start in world 2.
- The hangar's timeline (`Hud.build_campaign`): ‹ world › and the world's three levels; selecting one
  shows its world behind the menu. `Game.launch(lv)` plays a level (default: the selected one).
- Each level also has its own fortress (`fortress_of`, `FORTRESS_ORDER`: three different ones per world,
  and no two levels with the same pair of bosses); 1-3 keeps the Goliath.
- Foes (Guillaume, 2026-11-23: "I keep meeting the same enemies", then "staggered types", added on
  top of the first ones, never replacing them): `scripts/foes.gd` (`Foes`). Each level debuts one new kind
  (`Foes.INTRO`, a world's three are its own: seaplanes, gyrocopters and pillboxes on the coast; scarab
  skimmers, tanks and sand borers in the dunes; kamikaze quadcopters, flak guns and gunships in the city;
  lancers, hovercraft and spiral crystals on the ice; magma drones, mortar walkers and a segmented wyrm in the
  cinders). The debut opens its level (`Campaign.waves`) with a "NEW FOE" banner; later levels keep every kind
  met (`Campaign.mix_of`: this world's 4, earlier worlds' 2, the first foes from the world's `mix`). Each kind
  has its model, entry, movement and attack in `Foes` (`spawn`, `think`); moving parts are child meshes tagged
  `part` (they flash with the hit). Hold positions are offsets from `view_top`, so they work on every screen
  ratio. Static ground foes look for dry land (`Foes.dry_x`, `Game.land`). Flak shells (`Game.shell`) burst into
  rings; a borer under the sand (`Obj.under`) can't be hit.

## Code map

- `scripts/rules.gd` (`Rules`): every number (field size, scroll, upgrades and costs, guns, foes, the
  stage's waves by time, the fortress's waves by rail distance), pure functions on the save dictionary.
  Save: `user://save.json`.
- `scripts/models.gd` (`Models`): flat-shaded vertex-coloured meshes built in code (`Models.Builder`:
  `prism`, `box`, `octa`), cached by name. The fortresses are smooth instead (Guillaume found the boxy
  ones "too blocky"): `Builder.loft` skins rings of points (`Models.oval`, superellipse sections) with
  smooth normals, so fuselages, airfoils (`Models.airfoil`), nacelles, domes and capsules are lofts.
  A fortress's fuselage is one mesh (`fortress_hull`), stern (open bay, its edge rounded off by
  `STERN_IN`) at z = 0, the bay centred on the flight altitude
  `Rules.PY`; each wing (`wing_l`, `wing_r` nodes, built round its `WINGS` root) carries its engines, exhaust
  glow and propellers or nozzles (`Game.fort_props`, spun by `Game.spin_props`).
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
  ground. Every prop, in every world (`theme_prop` too), is placed with `place()` and drawn comically big,
  as Guillaume asked: `PROP_SCALE` (2.5x) wide and `PROP_V` (1.8x) tall, so the tallest stay under the
  flight altitude (tested per world). Densities are low to match; houses keep to one per 8 x 8 lot, city
  towers to two per block. Landmark hit heights go through `Models.mark_h`. `Models.scenery` counts
  what was built (tested).
- Landmarks (Guillaume, 2026-11-23: prominent scenery can be destroyed): lighthouses, boats and the
  two-storey houses are not baked into the chunk. `scatter` lists them in `Models.marks`; `Game.update_chunks`
  gives each its own node (`Models.landmark`, centred `MARK_H` above its base) under the chunk, and
  `spawn_marks` makes it a ground foe (`Rules.LANDMARKS`, stats in `Rules.FOES`) as it scrolls into view in
  the vertical stage only. Shot down: explosion, score and scrap (not a kill), a `Models.ruin` left on the
  chunk, which `to_hangar` rebuilds (`ruined`). Missiles, aim assist and the chase ignore them; leaving
  play (`let_go`, culling) keeps the node, since the chunk owns it.
- Fun landmarks per world (Guillaume asked for "funny features like Aztec pyramids"): a stepped pyramid in the
  dunes, giant rubber ducks in the sea and the city's canals, water towers in city parks, giant snowmen on the
  ice, carved stone heads in the cinders. All destroyable. Landmarks are sturdy (Guillaume saw some fall before
  they showed): hp in `Rules.FOES`, and shots only hurt them `Rules.LANDMARK_IN` inside the top of the screen
  (`Game.well_in_view`; tested).
- `scripts/city.gd` (`City`): Iron Sprawl's city (Guillaume wanted many varied buildings per block, angled
  roads and features to spot: towers, bridges...). `City.build` is called from `ground_chunk` for the "city"
  theme. The grid is turned by `City.ANGLE`; `to_local`/`to_world` convert. Avenues (4 m, every 16 m) and streets
  (2 m, every 14 m) are laid in 2 m steps into the ground's own surface, ramping up onto bridges (railings,
  piers) over the canals; every third avenue carries an elevated expressway (deck at `HWY_Y` on pillars).
  Blocks are split into lots of setback towers, glass towers, brick mid-rises and shop rows (or a courtyard
  ring); roofs get antennas, spires, helipads, water tanks, gardens or AC units, picked to fit under the
  flight altitude (`Ctx.cap`). Some blocks are parks (fountain, water tower landmark), plazas (obelisk or
  fountain, kiosks) or a stadium. Each road step, span and block is built by the chunk holding its centre.
  Builds ~40 ms a chunk on desktop: watch the cost (`Builder.bevels = false` for small parts).
- The city is at war (Guillaume: "grey, dark and on fire"): an ash and soot palette, a smoky sky, and magenta
  enemy shots that stand apart from the flames. About 30% of buildings burn (orange windows, roof fires).
  There are also ruins (`City.ruin`), road craters, burnt-out wrecks, tank traps, dead trees and rubble.
  `City.fire` lists flames in `City.fires` and caps them so their tallest flicker stays under the ship.
  `City.fx_mesh` turns the list into one mesh a chunk, which `update_chunks` hangs under the chunk.
  It has two surfaces animated in their shaders, flickering flame tongues and smoke puffs that rise to
  `SMOKE_TOP` and loop, with no particles and no per-frame script.
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
- Lifting the finger pauses (Guillaume, 2026-11-23): in flight (`Game.pausable()`) time eases to a stop over
  `Rules.SLOW_STOP` s (2 s, gradual: Guillaume asked for a slower slowdown) once no finger (or direction key) is down, and back up over `SLOW_RESUME` s on touch.
  `Game.tick(dt)` (called by `_process`) scales `step`'s dt by `time_speed()` and skips `step` when fully
  paused; the HUD dims and shows "PAUSED · Touch to fly". A run starts paused (the launch tap is already
  lifted). Tests and tools that call `step` directly are unaffected; `tick` is what the pause test drives.
- Bullets must read on every world (Guillaume, 2026-11-23: invisible on sand; then "black lined
  bullets are ugly", so no outlines). Every shot is `Models.shot_node`: a body, a soft camera-facing halo
  (`HALO_SHADER`, mixed over the ground, not added) and for enemy fire a white-hot core. Enemy fire takes the
  world's `fire` colour in `Models.THEMES` (violet on the dunes, red-orange on ice, magenta on lava), which
  must stay clear of that world's ground colours (tested in `readable_fire`). Close-ups over each world:
  `tools/bullet_shots.gd -- /tmp/bullets` (same command as the screenshots).
- Ramming (Guillaume, 2026-11-23: collisions between the ship and enemies damage the ship): `Game.ram`.
  Flying into an air foe (`Rules.RAMMABLE`) costs a hit and throws the ship back (`Game.knock`, eased off);
  darts, swings and drones break up, heavies take `RAM_DMG`. During the blink after a hit the ship passes
  through. Every mid-boss's hull is a wall (`Game.boss_rammed`, tested against its outlines from above,
  `Models.midboss_shapes`, built from the same points as its meshes where it can; a piece stops counting
  once broken off, and a spinning hull is turned). Ground targets and
  scenery pass under the ship; the fortress always flies ahead of the ship, so it can't be rammed.
- The mid-boss and its guns are never culled (`Game.gone`): it spawns far above the top on a tall phone, and
  a culled gun left its section unbeatable (Guillaume stuck on 2-1, tested).
- Hits flash: `Obj.hit` puts `Models.hit_mat()` over the foe's mesh for a moment.
- The chase reach (`POV_REACH.x`) must cover every fortress mount at `FORTRESS_SCALE` (tested).
- No shadow maps. With `shadow_enabled` on the sun, the Compatibility renderer ignores
  `vertex_color_is_srgb` in the shadowed light pass and every colour washes out to cyan (and shadow
  maps cost on phones). Models get silhouette shadows instead: `Game.cast_shadow_of` adds a flattened
  copy of the mesh, projected along the sun onto `SHADOW_Y` each frame. Those copies are drawn white
  on layer `SHADOW_LAYER` into a mask at the game's 720 px width (`shadow_view`, `shadow_cam` follows `cam`), and one
  see-through plane under the camera (`shadow_plane`, `Models.SHADOW_SHADER`) darkens the ground from
  the mask, blurred only to anti-alias the rim: Guillaume wants each shadow one uniform tone, so no
  soft penumbra (thin wings faded with it). Don't draw the flattened copies see-through in the main view: their faces overlap
  and stack into dark patches (Guillaume: "the shadow is not smooth"), and neither the depth pre-pass
  nor the material stencil (a no-op in Compatibility, tested on 4.7) can stop that.
- The look (premium pass): gradient sky shader, filmic tonemap, a cool fill light, rim light on the
  model material, chamfered top edges on straight `prism`s (automatic). The terrain is low poly but
  soft (Guillaume found hard facets too triangular): normals are 80% the land's broad shape (from the
  height field, so chunks meet seamlessly) and 20% facet, colours blend per vertex in narrow bands,
  hollows are darkened. No random per-facet shade.
- After its reactor the fortress goes down for `Rules.CRASH_TIME` (`Game.step_crash`, `fort_fall`): engines
  burn, propellers wind down, the left wing snaps off at `WING_SNAP` and tumbles away (`wing_off`, moved in the
  fortress's frame), it rolls onto that side, noses over and hits the sea or the shore; it stays in sight (tested).
- Seen from above before the swoop it cruises `FORTRESS_CRUISE` higher than its chase frame's base, so it
  flies clear of the land; the swoop blends that into `FORTRESS_LIFT`.
- In the chase one swipe across `Rules.POV_SWIPE` of the screen crosses the whole reach
  (`Game.pov_drag`), so the ship gets from one flank of the fortress to the other in one move.
- The world has no visible edge: each ground chunk is `CHUNK_W` wide at fine cells plus `CHUNK_FLANK` per
  side in ever wider cells (`Models.ground_cols`, bare of trees), and `CHUNKS_AHEAD` chunks are kept, so the
  ground runs past the fog's end from the chase camera in every direction (tested in `world_edges`).
- `Models.ground_chunk` caps terrain height so the ground stays well under the flight altitude.
- Place HUD controls with anchors and offsets (`Hud.place`), not `position`: the HUD is stretched.
- In a `SceneTree` script, `await process_frame` after `add_child` before stepping the game, or
  `_ready` hasn't run yet.
