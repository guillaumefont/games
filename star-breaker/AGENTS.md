# Notes for coding agents

Star Breaker is an original low poly 3D vertical (portrait) shoot 'em up in Godot 4.7. It
started as a landscape side-scroller in the genre of R-Type II; all content stays original:
never use R-Type names, art, enemies or levels, and no recreation of existing games.
Guillaume wants a modern mobile-game look (glass HUD, bloom, Rubik font), not retro.
Portrait only since 2026-11-17 (Guillaume: "switch the whole game to portrait now that we are
committed"); the landscape game was removed, its history is in git before that date.
Controls: drag anywhere to fly 1:1 (fires while the thumb is down), lift = the ship's release
(Lance: charge beam; Warden: fling or recall the pod). Each ship loads its ultimate its own way, and
never with a double tap (Guillaume's calls 2026-11-20/21). Lance's is the last stage of its charge
bar, `ULT_AT` (7 s) of holding, then lift: LV 1-3, the Nova, then the Storm (chain lightning on every
enemy on screen; the hold length and lighter `STORM_DMG` are its price); the Starbreak sweeping beam
it replaced is in git history. Warden's hold loads nothing (so a lift is always a pod command): the
Shatter meter `P.shat` fills from the pod's rams, blocked bullets, shot hits and kills (`SHAT_*`,
`SHATTER_FULL`), stays stored, and fires when the pod is recalled while out (it bursts where it is).
Holding to charge Warden's ult conflicted with the pod, which is why it changed.

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
godot --headless --path . --script tests/run_test.gd     # canyon run: course is fair, racing line earns gold, camera swings back
godot --headless --path . --script tests/runs_test.gd    # a canyon run in every stage: all 48 courses fair and flyable, gold in one stage per world, built a little per frame
godot --headless --path . --script tests/popin_test.gd   # every stage on a tall phone: no model or shadow appears inside the screen (-- <stages> vp=WxH)
godot --headless --path . --script tests/progress_test.gd # replay tiers, medals, medal track, ship colours, flux, ship levels
```

Screenshots (needs a display): `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/vertical_shots.gd -- /tmp/vshots`
(`tools/worlds_shots.gd` takes the stage map and one shot per world.)

## Replay progress (tiers, medals, colours)

- `scripts/progress.gd` (`Progress`) holds it, saved in `user://save.cfg` under `[progress]`, keyed by
  a stage's `id` ("w1s1"), never its index. Tiers scale the game only through `vgame.tier_mul(key)`
  (bullet, fire, hp, score) and `Progress.TIERS[t].ships`; new enemy fire cooldowns should
  decrement by `tier_mul("fire")`. A new stage-end kind needs a `Progress.PAR` entry (else
  `DEFAULT_PAR`). Flux (`Progress.flux`) is banked once per run in `finish()` (score / 100 plus
  `MEDAL_FLUX` per new medal) and buys ship levels; a level scales every hit through `G.power`,
  applied only in `dmg_e` and `boss_damage`, so new damage paths must go through those. Screens: `tools/progress_shots.gd` (same command as below, other script).
- Stage order (Guillaume, 2026-11-21): on Normal a stage opens once the stage before it is
  cleared (world 2 stage 1 needs world 1 stage 8), up to one past the furthest Normal clear
  (`reach(0)`), so saves from before the rule keep what they reached. Above Normal a stage opens
  once that same stage is cleared on the tier just below (Nova stage 5 needs Normal stage 5, not
  Nova stage 4; changed later the same day), or once it is already cleared on that tier.
  Cleared = finished with ships left; medals don't count. `Progress.open(i, t)` is the rule.
  Only the map and the
  result's Next enforce it; `start_stage()` plays any stage (tests and tools rely on that).

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

- Every path that leaves the app (back button, refresh-to-update restart) must call
  `Diag.note("QUIT")` first. Android restarts by killing the process, and a log that doesn't end
  in QUIT or SUSPEND is reported as a crash on the next launch (and turns safe graphics on).
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

- Frame budget (2026-11-21, "the game recently started lagging"): anything built ahead of time
  during play goes in small units under a time budget (`VRun.Builder.step()`, `BUDGET_MS`), never
  a whole slice per frame. Every stage builds its canyon run over its first seconds, and a whole
  slice or obstacle per frame cost 5-13 ms on a desktop. Check with `tools/perf_bench.gd`
  (per-stretch CPU, draw calls, primitives; command at its top), comparing against a worktree of
  an older commit.
- Don't write into another object's packed array element by element (`acc.v[i] = ...`): GDScript
  copies the whole array on each write. Take a local copy, change it, assign it back (`VRun._bend`).

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
  Ridged peaks everywhere (Guillaume, 2026-11-20): the side ridges, cliff tops (`TOP_PEAK`) and
  the odd range crossing under the play field (`mountain()`, `RANGE_CELL`) use `Terrain.crest()`
  (sharp crests, wide saddles) instead of smooth swells or flat plateaus. The floor must stay
  below the ship's plane (68 under it) inside the play width; ranges top out around 55.
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
- Content today: six worlds of eight stages (48), generated by `VStage._make()` / `build()` from
  each world's flyer groups (`VStage.WORLDS`), Lance and Warden. Stage ids are "w1s1".."w6s8".
  The menu (Guillaume, 2026-11-21): home (Play, the ship button with level/flux/medals, the
  device row), the level map (`scripts/vmap.gd`) and the hangar (`medals_scr`: pick the ship,
  level it, paint it, the medal legend). The map is one trail of all 48 stages climbing bottom up
  (drag to scroll; a banner sits between worlds, `sky()` blends each world's colours into the next).
  It reads as a tactical map (Guillaume, 2026-11-21: "more irregular"): stages sit at seeded, uneven
  places (`VMap._LAYOUT`, `stage_u()` / `stage_x()`), each leg of the route bends its own way, and a
  survey grid with sector numbers and terrain contours sits under the trail; the next stage gets a
  target reticle, world bosses a danger ring. Labels go on the roomier side of a stage. It follows the Normal chain; three pips under a stage show
  its cleared tiers. Your ship waits by the next stage, and the top bar's ship button opens the
  hangar (its Back returns to where it came from). The tier is picked after the stage, on the
  stage panel (`VHud.open_stage()`, `pick_tier()`, `play_picked()`), which shows only open tiers
  as playable. `VHud.back()` closes the panel, then goes home; Android back quits only on home.
  Leaving a stage lands on the map at that stage. Screens and a scroll GIF: `tools/map_shots.gd`. Each world has
  its own colours (`LOOKS` in `vgame.gd`, applied by `apply_world()`) and song. Stage 8 ends with
  the world boss, stages 1-7 with mid-bosses made of big flyers (`_spawn_end`). The scroll keeps going
  through every boss fight (Guillaume, 2026-11-21): bosses live in screen units on the play
  plane, so the ground just moves on under them, past the stage's `length` (terrain is endless;
  no rock or props are placed beyond `length - 320`). Only the canyon run stops `G.scroll`. The Bloom Mother
  has its own code (`spawn_boss`); the bosses of worlds 2-6 share one parts system
  (`spawn_gboss`, `_update_gboss`, `_sync_gboss`), ported from the landscape game and turned a
  quarter turn: their models are rotated, so part positions go through `_bl()`. Best score per stage is
  saved under `[portrait] bests` in `user://save.cfg` (an Array of 48).
- All 13 flyers from the landscape game are in, turned to come down the screen (`_update_enemies`,
  `_update_big`). Embers and hoppers stay cut: they enter from the bottom edge, under the thumb.
- Ground targets (turrets, generators) are moved into line with the opening of the barrier just
  below them (`VStage._clear_shots`): Guillaume hated towers he couldn't shoot behind walls. Enemy
  bullets stop on barrier walls too. The test checks every stage (`VStage.in_reach`).
- Fortress barriers are full walls standing on the ground (`Models.fort_wall`, one per side of
  the opening, the right one turned half a turn: a mirrored node shows black back faces), not
  floating beams (Guillaume: "strange"). Fortresses are futuristic, not medieval (Guillaume,
  2026-11-20): no battlements, merlons or buttresses. Walls are battered armour modules with
  seams and inset panels, a lit conduit in the deck, sparse emitter nodes, and a leaning blade
  pylon at each side of the opening; outposts are domes, hex plinths and lit rings. Screens:
  `tools/fort_shots.gd`. Walls carry
  guns on their front edge (`wallgun`, from stage 2), `shutter` barriers close and reopen their
  opening, and outpost pieces (`Models.prop`: bunkers, radars, pads, tanks, masts, hangars) stand
  on the ground, more every stage and crowding round the fortress (`VStage._outpost`).
- Guillaume wants dense stages ("the ships can handle much more"): keep the group spacing and
  sizes in `VStage.build()` / `_group()` rising with stage and world.
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
- The canyon run (`scripts/vrun.gd`, prototype 2026-11-18) is a ~15 s set piece in stage 1
  (`run` in `VStage.STAGES`): the stage's scroll stops, a separate course streams past the ship
  and the camera swings behind it (`_camera()` in `vgame.gd`); the thumb steers x and height
  (`P.z`). The course is a pure function of `u` (`VRun.passage`, `VRun.OBS`), shared by the
  collision, the mesh and `VRun.line()` (the racing line the motes follow and the test flies).
  Glows are flat quads facing the top-down camera: stand new ones up by `G.run.k` during a run.
  The moon floor keeps the run's distance in `G.foff`.
  Guillaume wants the way in and out seamless (2026-11-18): the canyon's speed starts and ends
  at the stage's scroll (`VRun.STAGE_SPEED`) and its floor dips under the moon's ground at both
  ends (`VRun.floor_z`), so the moon shows through the mouth and exit; the test checks both.
  Readability (Guillaume found it too hard, 2026-11-18): every way through has a soft light behind
  it (`VRun.gap_light`) and the fog brightens in the run, so the gap is the brightest thing ahead;
  up/down moves come in same-direction pairs with ~1 s before a change; peak speed 3.0. Obstacles
  are rock concretions (`VRun._blob`), never bigger than their collision shape.
  No auto-pause during the run (lifting the thumb there paused the game "for no reason"). The way
  out mirrors the way in: every obstacle is passed before `VRun.OUT`, then the camera swings back
  at most as fast as it swung in. GIF frames: `tools/run_shots.gd`.
  The swing orbits the ship, so it stays in the same place on screen (2026-11-19).
  Bends, basin, fork (2026-11-20): gameplay stays in straight canyon coordinates. Only the mesh
  is bent (`VRun.warp`, `VRun.heading`), and `_sync_run` turns the node so the canyon runs up
  the screen at the ship. Keep the turns no tighter than a 220-unit radius (the rim's back folds
  over otherwise), and keep them straight while the camera swings. The chase camera dodges rock
  it passes (`_cam_dodge`). Bridges, ridges and windows fade once the ship is through, and hide
  when the camera reaches them, so they never hide the ship. Wide spots go in `PATH`, and a
  `mesa` obstacle (with `len`) splits one, with motes on the tight side.
  Low poly without the blocky look (Guillaume, 2026-11-20): no plain boxes or level stripes.
  Rock is built with `VRun._rock`, a box broken into irregular facets, with `keep` holding every
  point out of the flyable space. Walls use `_crag` (pushed into the rock only). The rim's skyline
  rises and dips (`rim_z`). Each facet gets its own shade (`_facet`). Concretions are kept to the
  edges of the gaps. The Builder does one slice or one obstacle per frame (its worst frame is
  about 16 ms on a desktop). Keep it that way.
  No aim frame: Guillaume found it made the run too easy (2026-11-20). He wants more movement and
  less precision, so the gaps are big but each one sits across the canyon or up/down from the
  last (`OBS`).
  Natural, alien rock: obstacle collision follows the rock's shapes, and the mesh never goes past
  it.
  - Spires (`pillar`): an oval footprint, r across and `half()` along the canyon.
  - Bridges: their underside arches up mid-canyon (`under`).
  - Ridges: a saddle crest (`crest`).
  - Windows: an oval hole (`oval`, mesh `_eroded`).
  The walls lean back into a V (`_crag`). Mountains replace the flat plateaus beside the canyon
  (`MOUNT`, `_mount`, `_ridge`). Glowing crystal outcrops sit in the rock, never in the passage
  (`_crystals`). Transitions: the ship swoops in (`VRun.dive`) and pulls up
  on the way out (`VRun.lift`), and the camera rolls and widens mid-swing. The ship must stay in
  sight throughout, and run_test checks that.
  Don't run two Godot instances at once for shots: they share the game's settings file, and a
  test changes the ship.
  Holes (Guillaume, 2026-11-20): bigger (hw 17, hh 15) and each one opens into a rock funnel
  towards the ship (`HOLE_RINGS` at `FUNNEL` units before the wall). Collision follows it:
  `flare(o, u)` widens the oval before the wall and `front(o)` is how far the rock reaches.
  A run in every stage (Guillaume, 2026-11-20): `VStage` gives each stage `run` (130 before the
  fortress) and `course`: stage 1 keeps `VRun.handmade()`, the others get `VRun.generate(seed,
  world)` (~20 s since 2026-11-21, 14-15 obstacles, a 35-60 degree bend then an S or a hold, harder each
  world; Guillaume wanted longer runs that really turn, but the level itself keeps scrolling up). `VRun.use(course)` swaps the course
  in (LEN, OUT, PATH, TURN, OBS are static vars). Outpost props and islands stay out of the ground
  the camera sees behind the ship as it swings. tests/runs_test.gd checks all 48 courses and flies
  every one in the game for gold, camera out of rock (holes' funnels included) and ship in sight. tools/run_shots.gd takes a stage index as a second argument.
