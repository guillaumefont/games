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
  short screen. Parts stay within |x| <= 7, z -5..8 (tested). A boss never just vanishes (Guillaume,
  2026-11-24): the mid-boss's scorched husk (`Game.make_husk`, `step_husk`) loses way against the scroll,
  sinks, turns and burns until it's off the bottom of the screen; the fortress breaks up and drifts off. The hull can't be hurt; it holds the wave
  clock until it's down. Its part hp scales by `Campaign.BOSS_HP` (first level of a world quicker). Final boss: a capital ship
  (Guillaume, 2026-11-23, after rejecting the flying fortress as "a glorified transport with the same useless
  tunnel": "a huge fortress class ship, you clear it sections per sections as you advance along the ship").
  One for each level (Guillaume, 2026-11-24: "I want a different boss per level. You can advance over it, on
  the sides..."; `Campaign.FORTRESS_ORDER`), 15 in `Rules.FORTRESSES`, 98-124 m long (Guillaume, 2026-11-24: "start by designing a fortress, then choose a
  path that would clear it by sections": each ship is one dense object, its sections placed on it by `at`
  and overlapping, and their order is the path round the hull that clears it): plated-deck ships
  (`hull`: slab, wedge, round, keel: Goliath, Zephyr, Talon, Leviathan, Wyvern, Sirocco galleon, Narwhal
  icebreaker) and ships of smooth lofted `bodies` (`Capital.body_at`: Albatross airship, Marlin catamaran,
  Scarab beetle, Manta flying wing, Trident trimaran, Aurora pod chain, Basilisk serpent, Behemoth with
  nacelles), with `extras` (fins, masts and sails, tusk, crystals, legs and horn, spines, rings). No blocky
  shapes, no tunnels. Each section has a `route`, the lane the ship takes past it (`Capital.lane`): `stern`
  (behind it), `top`, `left`/`right` (along a flank, `FLANK` out from its widest), `under` (`UNDER` below it,
  guns slung upside down, the lane's guns dip up) or `gap` (between two hulls); `x`/`y` place it. Guns are
  given by route and stand on the hull where the lane meets it (`Capital.mount`: on the top with a ring, on a
  sponson in one line out from a flank, hung under the belly). Between sections the ship glides the shortest
  way round that stays `GLIDE_M` clear of the hull (`Capital.glide`: straight, across first, over the top,
  round a flank; longer ways take longer), the camera and the guns' dip blend to the next lane, and the reach
  is drawn in on the way. The deck flies higher for ships fought from beneath (`Rules.deck_of`), so the ship
  stays `Rules.LOW` m off the ground. Sections from stern to bow: `engines`, `hangar`, `guns`, `missiles`,
  `lances`, `battery`, `bays`, `spires`, then the heart: the `bridge` (on top) or a `gondola` (the reactor
  slung under the hull), whose armour breaks off to show the reactor (`core`, behind four shield panels).
  Each section lists its guns (`Rules.SHIP_GUNS`: nozzle, twin, quad, pod, mast, dish, pylon, hatch; looks in
  `Capital.gun`, patterns in `Game.think_gun`); a `pylon` shields the rest of its section until it falls
  (`Game.fort_guarded`), a `hatch` launches drones. The ships are compact and the sections overlap
  (Guillaume, 2026-11-24: "you already see the next section, receive its bullets"; no dead time on the
  sides): the current section and the next (`Game.live_sec`) fire, take hits and get brackets, the next one
  `Rules.AHEAD_FIRE` times slower, and the current one fires during the glide onto it too. From every lane
  the next section's guns are within 62 m and in sight round the hull (tested): a path winds round the
  hull (under, up a flank, over, down the other flank), never straight across it. No gun fires through
  its own hull (`Capital.sees`); the other sections' guns hold fire. The hull is cut into segments at the
  distinct section starts (`Capital.cuts`, `hull_count`); a section's guns and piece ride the segment it
  starts on (`Capital.home`; `Game.seg_body` vs `hull_body`). `tools/fortress_plan.gd [id]` prints each
  ship's plan (lanes, guns in sight, glides) headless. The lanes and glides keep clear of the hull and
  of a galleon's masts and sails (`Capital.rigging`, in `inside`; shots and sight pass through sails,
  `in_hull`). After the kill the ship climbs over the tallest thing on the hull (`Capital.crest`) and
  only comes down to its cruise once the wreck has slid back past it (`esc_down`); beneath, it slips out
  past the hull's widest (`Capital.widest`). The ship can't be hit on its way between sections (the swoop, a glide, the climb away;
  `Game.transit`; Guillaume, 2026-11-24): shots and drones pass through. `tests/clearance_test.gd` flies every whole fight and checks
  the ship never passes through any mesh and neither it nor the camera jumps. Clearing a section breaks off its superstructure (`Capital.piece`), leaves that stretch burning
  and glides the ship on to the next section's station (`Rules.station`, `ADVANCE` s). No tunnel, ever.
- The chase is the same world as the vertical stage: the camera blends between poses (`Game.pose()`:
  `top`, `chase`) instead of switching scenes. Keep it that way, it is the game's hook. It stays
  **outside** and in **third person** (Guillaume rejected a first-person tunnel). Seen from above the
  fortress is `TOP_SCALE` of its size; during the swoop it grows to full size and climbs to `CHASE_DECK`
  (`fort_s`, `deck_y`; `Game.fort_point()` maps model points to the world). In the chase the ship flies with
  it at the rail speed, `along` metres ahead of its stern and `fly` above its deck (`chase_y` is that line's
  height); the camera looks a little down at the deck. The hull runs off both sides of the screen, but every
  gun stands within |x| <= `GUN_X` and within the reach of the ship's dipped guns from its station (tested).
- In the chase the drag moves the ship across the view (`POV_REACH`, `POV_DRAG`), which is how you
  dodge; guns fire ahead and a little down (`AIM_DIP`) with aim assist (`Game.aim_point`). Orbs inherit the
  rail speed and can be shot; a pod's rockets home in for a while (`Obj.homing`).
- Foes that fly in and hold (rotor, scarab, lancer, prism, heavy, gunship, darts) stop a few metres above
  the **centre of the screen** (`Game.hold_z`, from `view_mid`), not below the top edge: Guillaume
  (2026-11-24) found they stopped "much too far from the ship" on tall phones. When the way down from the
  top edge to the hold is longer than `Game.SIDE_ENTRY`, they come in from a side, level with their hold
  (`Game.enter_toward`).
- Gun towers (`Towers`) stand on a pole (`Towers.POLE`) between their footing and the gun: Guillaume
  (2026-11-24) couldn't tell a flak tower from a flying foe. A tower only stands where its whole footing
  (`FOOT_R`) is on level ground (`Foes.dry_x`/`footed`): firm land first, then a dry canyon floor, then a
  level riverbed; never hanging over a rim. Flying foes that could pass for a tower from above must spin.
- Seaplanes (`gull`) are collateral, not foes (Guillaume, 2026-11-24: "Hydro planes should be a collateral
  damage, not an enemy. It should stroll by (alone) waiting to be shot"): one at a time, it crosses the
  upper screen slowly from one side in a lazy wave, never fires and can't be rammed (`Foes.HARMLESS`), and
  pays nothing when shot down (see civilians below). No formations.
- Civilians (`Rules.CIVILIANS`: seaplanes, boats, houses, lighthouses; Guillaume, 2026-11-24): shooting a
  real one down scores nothing (no penalty or notice either, Guillaume, 2026-11-25: "The game is too
  dense to be able to avoid killing them"); a downed seaplane's pilot bails out under a parachute that
  sways off and shrinks away (`Blasts.chute`). It drops no scrap, isn't a kill and isn't in the kill total; missiles
  and the guns' assist never lock onto them (`Game.shy`). Some are hacked (`Obj.hacked`: a seaplane after
  the level's opening, `Foes.HACK_P`; a lighthouse, `Rules.HACK_LIGHTHOUSE`): "a lighthouse that opens to
  show a turret, a hydro plane that unveils a minigun". A hacked one blinks and sparks red for
  `Foes.HACK_TELL` s before its gun unfolds (`Foes.unveil`) and fires, then is a foe paying `HACK_PAY` x.
- Groups keep their spacing: seekers and darts from behind keep apart (`Foes.keep_apart`), and the darts
  hold in a line across the screen. Every air foe that comes in a row (`Foes.ROWS`, from the top, a side or
  behind) keeps `Foes.ROW_GAP` (1 m) between hulls (`Foes.space`; Guillaume, 2026-11-25: rows from the
  top and the sides bunched up). Foes flying to a goal move the goal with the nudge, and scarabs and
  lancers pick dash spots clear of the others' (`Foes.clear_x`). A dart sweeping in from a side is never
  taken for one from behind (they used to join the back darts' line in the middle: a clump).
- Boss targets have generous hit radii (Guillaume found them too small).
- Scrap is the only currency and is kept even when shot down. Upgrades apply in both modes.
- In-level power (Guillaume, 2026-11-24: with everything bought "it was too easy"; after a reset it was
  exciting again; "how about keeping an in level progress"): every level starts on the bare twin gun
  (`Game.power` 0). Kills in the vertical stage leave power cores (`Game.drop_core`, pick kind `power`), each step
  taking more kills than the last (`Rules.POWER_KILLS`: 116 in all, about a whole long level), and the mid-boss leaves one as it goes down; kills in the
  chase don't count. Each core widens the spread a step up to `Rules.POWER_MAX` (7 guns, faster fire). A hit costs
  a power step, the kills towards the next core and hull. Guillaume found the first pace (a core every 6 kills
  and one per mid-boss section) far too quick: max power early, then "OP and you cannot lose". Keep it slow. The hangar's Cannon upgrade only raises damage per shot (`Rules.cannon_dmg`), never the spread, so
  bought upgrades can't make a run's start easy (tested). HUD: the power bar under the hull pips.
- The hangar has a "Reset progress" button (two taps within `Hud.RESET_ARM` s) that wipes the save back to
  `Rules.fresh()`, so Guillaume can replay the difficulty curve from scratch.
- Battery (Guillaume, 2026-11-24: "the game is draining the battery"): `Game.fps_cap()` sets `Engine.max_fps`
  every frame: 60 in flight (`PLAY_FPS`; 90-120 Hz phones would otherwise draw every refresh), 30 in the
  hangar, the results and a full pause (`IDLE_FPS`). The 3D view is drawn at most `MAX_3D_W` (1260) px wide
  (`Game.render_scale`, bilinear upscale). Set these in scripts, not project.godot: a project setting
  needs a new APK shell, a script ships in the game pack. Per-frame script time is small (about 1 ms a
  step, `tools/perf.gd` prints it with draw calls); the cost is on the GPU, so watch fill (full-screen
  passes, see-through layers) before adding more.
- The pause screen (finger lifted) has a "Main menu" button (Guillaume, 2026-11-24), shown only once time has
  fully stopped, under the PAUSED title and its hint. Two taps (`RESET_ARM` s) quit the run
  to the hangar (`Game.quit_run`): scrap picked up is kept, nothing else counts.
- A level starts on "Touch to start" (`Game.started` false until the first touch), not on the pause screen
  (Guillaume, 2026-11-24): no dimming, no PAUSED, no Main menu.

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
godot --headless --path . --script tests/game_test.gd   # rules, controls, pause menu, in-level power, readable bullets, mid-boss sections, fortress chase (final boss), ramming, death, results, world edges
godot --headless --path . --script tests/campaign_test.gd  # worlds and levels, unlocks, level select, progress reset, world looks, a full level, every mid-boss and fortress
godot --headless --path . --script tests/foes_test.gd   # campaign foes: one new kind a level, kept after; each comes in off-screen, attacks, flashes, goes down
godot --headless --path . --script tests/update_test.gd  # self-update: pack download, checks, APK offer
godot --headless --path . --script tests/icon_test.gd   # project icon and Android launcher layers
godot --headless --path . --script tests/blasts_test.gd # explosions: pieces by size, pool, budget, chains, carry, shake
godot --headless --path . --script tests/look_test.gd   # the look: baked occlusion, contact shadows, liquids by world, vignette
godot --headless --path . --script tests/bosses_test.gd # final bosses: one a level, lanes and glides clear of the hull, guns on it, fire that can't be shot down, a fight from beneath
godot --headless --path . --script tests/clearance_test.gd # every fortress's whole fight: the ship never passes through its meshes, ship and camera never jump
godot --headless --path . --script tests/relief_test.gd # the land's set pieces: course, seams, depth, moving parts, ground foes' footing
godot --headless --path . --script tests/power_test.gd  # battery: frame rate cap by moment, 3D resolution cap
```

Screenshots (needs a display; one per key moment of a full run):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/shots.gd -- /tmp/shots`

Explosions over time, from both cameras: same command with `tools/blast_shots.gd -- /tmp/blasts`.

Every mid-boss as it arrives and after its first section: same command with `tools/midboss_shots.gd -- /tmp/midbosses`.

The final boss alone, without playing the stage (arrival, swoop, each section and the glide to it, overviews
with no fog, the break-up): same command with `tools/fortress_shots.gd -- /tmp/fortress [id]`. Every fortress
side by side (from above, behind its stern, an overview, over its second and third sections):
`tools/fortress_lineup.gd -- /tmp/fortresses [id]` (from above, the chase, overviews from above and below, each
section from its lane).

Scenery close-ups with no HUD or foes (top view and a low view per stretch of coast):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/scenery.gd -- /tmp/scenery [theme]`

In-level power (start, a core, full power): same command with `tools/power_shots.gd -- /tmp/power`.

Every campaign foe in play over its world: same command with `tools/foe_shots.gd -- /tmp/foes`. Every
gun tower in every world: `tools/tower_shots.gd -- /tmp/towers`.

Every world (hangar, play, battleship): `xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/worlds.gd -- /tmp/worlds`

Icons: `python3 tools/icon.py` (Pillow) writes `icon.png`, `icons/` and `store/icon-512.png`.

## Campaign (Guillaume, 2026-11-23: "a real timeline, with worlds and levels")

- `scripts/campaign.gd` (`Campaign`): five worlds (Glass Coast, Ember Dunes, Iron Sprawl, Frost Shelf,
  Cinder Reach) of three levels each, played in order. Guillaume (2026-11-23): "mid bosses and final
  fortresses for every level", so every level is waves, a mid-boss, waves, the fortress chase
  (`LENGTHS`: the first level of a world shortest; Guillaume, 2026-11-24, wanted longer runs between bosses, so about twice what they were). Each level has its own mid-boss (`midboss_of`:
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
- Each level also has its own fortress (`fortress_of`, `FORTRESS_ORDER`: fifteen, one a level); 1-3 keeps the
  Goliath.
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
- Gun towers (Guillaume, 2026-11-23: "different types of towers", "customize tower for each world, snowy,
  sandy, on a building"): `scripts/towers.gd` (`Towers`). Four types (`TYPES`: flak `turret`, `rocket`
  battery, `howitzer`, `pulse` mast), fielded by world (`BY_WORLD`; a level's "turret" waves take them in
  turn). Each stands on its world's footing (`Towers.base`): sandbagged pad, sandstone block in a drift, a
  whole building in the city, snowed-over pad (snow on the gun too), basalt crag with magma. The node sits at
  the gun's height (`Towers.height`) so it's hit where the gun shows; the gun is a `top` part that turns.

## Code map

- `scripts/rules.gd` (`Rules`): every number (field size, scroll, upgrades and costs, guns, foes, the
  stage's waves by time, the fortress's waves by rail distance), pure functions on the save dictionary.
  Save: `user://save.json`.
- `scripts/models.gd` (`Models`): flat-shaded vertex-coloured meshes built in code (`Models.Builder`:
  `prism`, `box`, `octa`, and `loft`, which skins rings of points like `Models.oval` with smooth normals),
  cached by name.
- `scripts/capital.gd` (`Capital`): the capital ships' meshes, in their model frame (stern at z = 0, bow at
  -`Rules.fortress_len`, deck at y = 0). The hull is one flat-shaded `segment` a section (plated deck in
  lanes, edge parapets, armour belt, keel; `hw` gives the deck's half width along the hull), each with its
  deck fittings and its breakaway `piece`; `gun` builds each kind of gun round its hit point, facing aft.
  In the game each segment is a node `segN` at its `pivot` with a `body` child undoing it, so guns (foes with
  `on_fort`, their nodes children of the body at `anchor`) ride it and it can turn when the ship breaks up.
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
- The land's relief (Guillaume, 2026-11-24: "the ground is mostly flat and uneventful"): `scripts/relief.gd`
  (`Relief`). The course is cut into `Relief.SEG` m stretches, each a set piece (`FEATURES` per world, then a
  `stream` stretch, in a level's own `course()` order past the hangar's two stretches): winding canyons/gorges
  with terraced walls, a river (lava in the cinders) and a horseshoe head with a fall; a rift across the course;
  `cliffs`/`shelf` (the sea or lava drops ~7 m, every shore a cliff, tabular icebergs); desert `mesas` (the floor
  sinks round buttes); a `crater` (meteorite in the dunes, sinkhole lake on the ice, erupting caldera in the
  cinders). Land can't rise (props must stay under the ship), so the drama goes down, to ~9 m below the plain.
  `Relief.at(x, z, h)` gives every ground height (`ground_chunk`, `Game.ground_y`, `Game.land`); the city keeps its
  flat ground. Steep faces are flagged in vertex alpha and get strata in the ground shader (`Models.ground_mat`).
  Rivers and lava are an animated surface over the ground; falls (draped curtains), lava bombs, fountains, smoke,
  steam, spray, geysers, avalanches and dust devils are shader "movers" (`Relief.MOVERS`, capped under the ship),
  one fx mesh a chunk like the city's fires. Ground foes avoid rivers, lava, cliffs and deep floors
  (`Relief.firm`). Stretches fade to the plain at their ends (tested). A chunk builds in ~40 ms on desktop
  (like the city's): watch it. Look at every stretch with `tools/scenery.gd` (its shots land on each stretch).
  Falls follow the upper hull of the rock under them (`Relief.drape`), so they never pour through a ledge (tested),
  and nothing stands in their way (`Relief.near_fall`); `tools/fall_shots.gd` looks at them. Every fall is fed
  (Guillaume: "no waterfall without a water body where it can come from"): a pool behind its lip and a stream
  notched over the rim (`Relief.fed`), so the fall starts at the water's level (tested). The 2 m ground grid
  can't draw a 3 m stream true (Guillaume, 2026-11-25: "waterfall is not aligned"), so the pool, the stream (as
  wide as the curtain) and a plunge pool at the foot are laid as sheets over it (`Relief.sheet`, tested). Ember Dunes is a desert:
  no water anywhere, its canyon a dry wadi with sand slides (tested). Glass Coast's bare rocky heights break into
  crags (`Relief.crag`: blocks at stepped heights, gullies at their joints, the odd tarn), cut into the land only;
  set pieces start from `Relief.plain` (the plain with its crags). `tools/crag_shots.gd` looks at them.
- Baked shadows (Guillaume, 2026-11-24: "bake shadows, ao... even for moving objects"): no shadow maps (they cost on
  phones and wash out vertex colours on the web). The ground bakes the sun's shadow into its vertex colours: each
  vertex below the plain marches toward the sun (`Models.sun_margin`, `sun_slide` from Game's sun; inside the chunk it
  reads the grid's own heights) and carries how far the ground stands above the sun's ray (UV2.x); the ground shader
  thresholds it per pixel (`shade_edge`, `shade_k`), so shadows under cliffs, canyon walls, rims and mesas end in crisp
  lines (Guillaume, 2026-11-25: "more defined"). The land never rises past `LAND_TOP`, so vertices near the plain
  skip the test (that keeps chunk builds cheap). Props' contact discs (`ao_blobs`) stretch away from the sun as far as
  the prop is tall (`CAST`). Moving things keep their silhouette shadows, now flattened onto the real ground under the
  sun's ray (`Game.land_shadow_y`, looked up every few frames on a remembered 1 m grid), so a shadow in a canyon lands
  on its floor. Tested in `relief_test.gd`.
- The city is a calm backdrop (Guillaume, 2026-11-24: "too messy... not very easy to see the enemies"): every
  colour of a city chunk goes through `City.calm` (desaturated, drawn in towards one mid grey; `Builder.tone`), with
  few fires, cars and road markings, and no helipads. Foes keep their own colours. Tested in `relief_test.gd`;
  `tools/city_shots.gd` shows foes over it. Keep new city props in that muted band.
- Towns (Guillaume, 2026-11-24: "too sparse, elements scattered without real character... a pyramid in a city
  like structure with small houses around it"; then "on top of the existing evolutions, like cliffs in glass coast"):
  `scripts/towns.gd` (`Towns`). Each world's town crowns one of its set pieces (`Relief.TOWN_HOST`: the coast's sea
  cliffs, the desert mesas, the ice shelf, the cinders' lava cliffs): `Relief.at` levels a plateau (`GROUND_Y`) over the
  set piece's own shape (`Relief.shape`), its edge a cliff, with a causeway carrying the avenue down. The town: paved square and centrepiece (pyramid, church, giant snowman, fire altar), an avenue running
  down towards the player with its furniture (palms, trees, pines, stone heads), a grid of houses facing the square
  (adobes, cottages and tall houses, igloos and cabins, glowing huts), a wall with towers (hedges, fences). Each chunk builds the pieces whose spot it holds; landmarks go through `Models.mark`. The land's own
  props keep out (`Relief.in_town`), and elsewhere they come in groups: groves and fields in some 12 m cells, rocks
  as outcrops (`Models.rocks`: one big rock about the ship's size, smaller ones on its sides; Guillaume found lone
  mid-size boulders unrealistic). Look at them with `tools/town_shots.gd -- /tmp/towns`.
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
- Lifting the finger pauses (Guillaume, 2026-11-23): in flight (`Game.pausable()`; not once the fortress is
  destroyed: its break-up plays through, Guillaume 2026-11-24) time eases to a stop over
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
  scenery pass under the ship; in the chase the ship flies over the fortress's deck, clear of it and short of its superstructure, so it can't be rammed.
- The mid-boss and its guns are never culled (`Game.gone`): it spawns far above the top on a tall phone, and
  a culled gun left its section unbeatable (Guillaume stuck on 2-1, tested).
- Hits flash: `Obj.hit` puts `Models.hit_mat()` over the foe's mesh for a moment.
- Every fortress gun must be within the chase's reach from its section's lane (tested in `aiming`), every lane
  and glide clear of the hull, and no gun may hide a shield pylon from the lane (tests/bosses_test.gd).
- Bosses are a real challenge (Guillaume, 2026-11-24: "I can shoot down their bullets, there is some form of
  auto aim"): the fortress's shots can't be shot down (only rockets, 3 hits), the aim assist is only
  `Rules.AIM_ASSIST` (1 m), its guns are tougher and fire faster (`BOSS_FIRE`).
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
- Baked occlusion (Guillaume, 2026-11-24: "keep improving the graphics, like baked AO"): no SSAO in
  the Compatibility renderer, so it is baked into the meshes. `Models.place` (and `City.Ctx.at` for
  buildings) calls `Builder.occlude`: until the next `xf`, vertex colours darken towards the
  placement's base over `AO_H` m (down to `AO_BASE`), except faces open to the sky and parts lying
  flat on the ground (foam rings, paths). Unplaced models (ships, bosses, landmarks) are untouched.
  Each placement's footprint (what stands over `AO_TALL`) becomes a soft see-through disc on the
  ground (`Models.ao_blobs`, one mesh a chunk, the chunk's `ao` child). Costs ~10% of a chunk's build.
- Models are baked too: every mesh built through `Models.cached` (ships, foes, boss hulls and pieces,
  fortress segments and guns, towers, landmarks) goes through `Models.bake_ao`, a coarse voxel grid
  (`AO_CELLS` along its longest side) and a few short rays per vertex over its hemisphere; creases and
  feet of parts darken by up to `AO_STRENGTH`. Glows and effects are skipped (`NO_AO`). It costs ~5-35 ms
  a mesh on desktop, once; the fortress is built at `launch`. Separate meshes don't shade each other,
  so a fortress deck gun gets a contact disc on the deck (`Models.contact`, the gun's `ao` child).
- Per-world colour grading (`adjustment_color_correction`, split toning) was tried on 2026-11-24 and
  dropped: in the Compatibility renderer it lifted the blacks and washed every world out.
- The ground is a shader (`Models.GROUND_SHADER`): where it lies flat at the water line (`SEA_Y`) it
  turns liquid by world (`LIQUIDS`): glossy water with drifting crest glints, or crusted, glowing
  lava. The dunes' dry washes sit at the same height and stay dry. Vertex colours are converted from
  sRGB in `vertex()` only when `!OUTPUT_IS_SRGB` (as the standard material does), or the colours go dark.
- A soft vignette (`Game.add_vignette`, a CanvasLayer under the HUD) frames the view.
- After its reactor the fortress breaks up in the air for `Rules.BREAKUP_TIME` (`Game.step_breakup`; Guillaume:
  "die in the air and drift out of screen, not into the ground"): the reactor blows, blasts run aft along the
  spine, the seams part bow first (`SEAM_GAP`), each segment drifts apart, turns, sinks a little, scorched and
  burning, while the wreck loses way (`DRIFT`) and slides back under the ship, which climbs away (`CLIMB`) with
  the camera, but no higher than `CRUISE_Y` (Guillaume: from high up "you can see the limited decor"; the
  city is also built `Models.CITY_MORE` wider than the core strip for that). No piece comes near the ground and all are off the screen by the end (tested).
- In the chase one swipe across `Rules.POV_SWIPE` of the screen crosses the whole reach
  (`Game.pov_drag`), so the ship gets from one side of the fortress's guns to the other in one move.
- The world has no visible edge: each ground chunk is `CHUNK_W` wide at fine cells plus `CHUNK_FLANK` per
  side in ever wider cells (`Models.ground_cols`, bare of trees), and `CHUNKS_AHEAD` chunks are kept, so the
  ground runs past the fog's end from the chase camera in every direction (tested in `world_edges`).
- `Models.ground_chunk` caps terrain height so the ground stays well under the flight altitude.
- Place HUD controls with anchors and offsets (`Hud.place`), not `position`: the HUD is stretched.
- In a `SceneTree` script, `await process_frame` after `add_child` before stepping the game, or
  `_ready` hasn't run yet.
