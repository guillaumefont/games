# Notes for agents

## Pull requests

- Work on a branch and open a PR against `main`.
- **Merging:** see the root [`AGENTS.md`](../AGENTS.md): auto-merge only, once all checks are green
  (the required **CI gate** check).
- Add a **Try it** section to the PR body with the preview APK, once the PR number is known:

  ```
  ## Try it
  - Android APK: https://guillaumefont.github.io/games/aurite-front/pr/<N>/aurite-front.apk
  ```

## Layout

- `godot/`: the main version, Godot 4.7.2 (GDScript), exported to Android. Renderer: Mobile (Vulkan), with automatic fallback
  to GL Compatibility on devices without Vulkan (`rendering_device/fallback_to_opengl3`). Some phone GL drivers
  drew huge stretched triangles in Compatibility, so keep Mobile as the default and keep MultiMesh buffers fully
  initialised (`View3D._batch` uploads zeros first and hides empty batches).
  Test locally with `xvfb-run godot --path godot` (needs `mesa-vulkan-drivers`); add
  `--rendering-method gl_compatibility` to check the fallback.
  See `godot/README.md` for the scripts and controls.
- `web-3d/`: the low-poly 3D browser version the port is based on (one HTML file). Reference only.
- `android-webview/`: older Android WebView wrapper around `web-3d` (`build.sh`, no Gradle). Not built by CI.
- `web-2d/`: original 2D prototype. Archived.
- The game is called "Aurite Front". Team colours follow the faction (`D.FCOL`, set per match by `D.set_team_colors`):
  the Vanguard is blue `#3fb4e8`, the Ashen Pact red `#e0423a`, the Hollow Choir green `#3cc457`. Guillaume, 2026-11-14: the game is red themed, so
  campaign I is played as the (red) Ashen Pact and campaign II as the Vanguard.

## Hollow Choir (third faction; campaign III)

- The Choir's rules were rebuilt in the faction redesign: see "Hollow Choir (phase 5)" below. What follows here still holds.
- Faction-only types have `fac: "choir"`; shared types the Choir does without have `no: ["choir"]`, and
  `D.sub(fac, type)` gives the faction's stand-in (`refinery` → `garden`, `rifle` → `thrall`, `arty` → `geode`).
- Tunnels: `Sim.plan_tunnel` (from `group_move`), `tunnel_tick`, `_emerge`. A unit in a tunnel has `intun > 0`: it is
  hidden, unselectable and skipped by separation. `under` (tunnels and moving sappers) makes a unit untargetable and
  undamageable. Handle both in any new targeting or selection code.
- Shard fields are `Sim.fields`, drawn in `View3D.draw_parts`. Unit limits (`lim`, the Cantor) go through `Sim.at_limit`.
- New sounds (`shard`, `geode`, `burrow`, `ack_choir`) are in `tools/synth.py`. Re-rendering every sound on another
  numpy version changes the old files slightly, so copy only the new ones into `sfx/`.

## Faction redesign (Guillaume 2026-11-21: "Implement factions")

- Design: Claude Doc "Aurite Front: asymmetric factions proposal" (https://claude.ai/artifact/87i89SVadBBZEWp5AxmL81),
  with a Stats sheet tab. Flavour: Vanguard = high tech (flown in from the fleet), Pact = raw power, Choir = alien mutant.
  Order: groundwork, then Pact, Vanguard, Choir, then balance, each its own PR. Guillaume, 2026-11-21: "Finish the works
  don't ask at every step" and "Don't forget to show a preview" (screenshots in the project's faction-previews folder).
- Groundwork (phase 2): `D.RULES[fac]` holds each faction's rules (`power`, `place`, `cap`, `prod`); read them through
  `D.rule(fac, key)`, `D.producer(fac, cat)` or the Sim helpers `uses_power`, `producer(team, cat)`, `cap_max`,
  `cap_used`, `cap_full`. Never use `D.PRODUCER` directly. No faction runs on the old shared rules any more.
- Unit cap: buildings raise it with `capAdd`, units use `capCost` (defaults per category in `D.CAP_COST`). The HUD shows
  UNITS instead of POWER for factions with a cap and without power (`UI.cap_parts`, `UI.power_parts`).
- Living fields: `Sim.vit` (0..100 per ore tile), `ore0` (start amount), `touch_t`. Take ore only through
  `Sim.take_ore(i, n, drain)`: an earner's `drain` is the vitality lost for emptying a whole tile (harvester and garden
  20 today; negative heals). Rested tiles (`D.FIELD.rest`) regrow up to `ore0 * vit / 100`. At 0 a tile is dead for good
  (`field_dead`): grey stumps in `View3D.upd_ore`. `AF_MODE=fields` shoots fresh, tired and dead fields.
- `groundwork_tests()` in `tests/sim_test.gd` checks each faction's rules and field drain, death and regrowth. A test that
  changes `D.RULES` or `D.BLD` must restore them after itself.
- Ashen Pact (phase 3): `RULES.ashen` has `cap` (Hearths +10, the Yard +20) and `swap`. With `swap` on, the shared type
  names (`rifle`, `barracks`, `refinery`, `harv`, ...) mean the faction's own (`FACS.ashen.sub`) everywhere: `Sim.tr_t`
  translates in `spawn_unit`, `add_building`, `count` and mission tech lists, and `req_of` drops a requirement the faction
  has no stand-in for (`""`). So missions and the AI can keep saying "barracks". Use `d.dock` (ore drop-off) and `d.door`
  (units roll out) instead of literal type names. Mechanics: Furnace `burn` (aurite per second; a cold one makes no
  power, `Sim.fuel_reserve` keeps `D.FUEL_KEEP` seconds of fuel out of spending), Hearth `muster` (`Sim.muster`, once a
  match), unit `tough` (less bullet damage), `pack` (trained as several), `charge` (boars: x3 first hit, knockdown via
  `e.stun`), `ram` (Ram Bike runs infantry over), `bldOnly` (Kettle Ram), `salvo`, `w2` (second weapon with its own
  target and `cd2`). Wrecks: `Sim.wrecks` (`D.WRECK`), left by destroyed ground vehicles, drawn charred by
  `View3D.sync_wrecks`; a Scrapper (`scrap`) revives one above `revive` or strips it for aurite. `pact_tests()` checks all
  of it plus a 10 minute Pact AI game. `AF_MODE=pact` shoots the base, every unit, a charge, a wreck and the MUSTER button.

## Building upgrades (Guillaume 2026-11-14: "allow structure upgrade, for example the reactor to a superreactor")

- `D.UPG[type]` holds each upgrade (cost, time, req, say, plus the stats it replaces); `D.BLD2[type]` is the merged
  upgraded def. An upgraded building keeps its `type` (so counts, requirements and the AI build order still work) and
  gets `b.lv = 2`, `b.d = D.BLD2[type]`. Read stats from `b.d`, not `D.BLD[b.type]`, in any new building code.
- `Sim.start_upgrade` / `cancel_upgrade` / `upd_upgrade` (paid over time like a queue) / `finish_upgrade`; `upg_block`
  gives the reason a building cannot upgrade. Effects: `d.pwr`, `d.yield` (refinery deliveries, garden harvests),
  `d.speed` via `Sim.prod_speed` (training speed of the producer's category), weapon stats.
- Models: `Models.get_model(..., lv)` adds `_upgraded()` parts; the view rebuilds a building's model when `e.lv`
  changes and plays a reveal (`View3D._anim_upgrade`). `AF_MODE=up AF_SHOT=dir` shoots every base/upgraded pair per
  faction, a running upgrade, the reveal and the button.
- AI: upgrades in skirmish, in campaigns only on Hard (`ai_ups` in `ai_think`), to keep Normal beatable.
  `upgrade_tests()` in `tests/sim_test.gd` checks this and each effect.

## Self-update (`godot/scripts/updater.gd`, Guillaume 2026-11-14)

- Installed games update themselves: the `Updater` autoload (listed FIRST in `project.godot`) fetches `version.json`
  from the build's Pages folder on launch and on resume, downloads the newer `aurite-front.pck` into `user://update/`,
  and mounts it at the next launch in its `_init`, before any other game script loads. The menu's top-right line shows
  the build and status; tapping it restarts into a downloaded update. Saves in `user://` are untouched.
- A pack only fits its "shell": the engine version, `project.godot`, `export_presets.cfg`, `updater.gd`, the icons and
  the splash (CI hashes them into `build.json`/`version.json`). Changing any of them means installed games ask for the
  new APK instead, so avoid touching them casually. `updater.gd` must not use other game scripts or classes.
- A pack that fails to start twice is dropped (back to the APK). Locally `build.json` has build 0, so the updater is
  off; `AF_UPDATE=1` forces it on (with a `url` in `build.json`), `AF_UPDATE=0` turns it off.

## CI (`.github/workflows/`)

- **Headless sim** (`sim.yml`): `godot --headless --path godot tests/sim_test.tscn`. Godot exits 0 on script
  errors, so the job greps the log for script/parse errors and for `SIM TEST DONE`, the test's last line.
  Keep that line last when you change the test, and add a step there for any new test.
- **Builds** (`build.yml`): exports `godot/` with the Android preset as a release APK, signed with the committed
  `android-webview/debug.keystore` (or an `ANDROID_DEBUG_KEYSTORE_BASE64` secret). versionCode is
  `100 + run number`, so do not bump `version/code` by hand. It publishes to the `gh-pages` branch with
  `.github/publish-pages.sh` (at the repo root): `main` under `aurite-front/` on the games site, PR N under `aurite-front/pr/N/` (removed when the PR closes),
  each with `aurite-front.apk`, a download page (`.github/pages/index.html`) and `web-3d/`.
  The APK is also a run artifact.
- **Deploy Pages** (`pages.yml`): deploys `gh-pages`, one run at a time. Builds dispatches it from `main`.
  It needs Settings > Pages > Source = "GitHub Actions" and skips until then.

## Before pushing

```
cd godot
godot --headless --import
godot --headless tests/sim_test.tscn   # must end with SIM TEST DONE and no SCRIPT ERROR
```

## Building animations

- Build and sell reveal a building with `Models.cut_material()` (a copy of the lit shader that discards above `cut_y`),
  set as `material_override` only while the animation runs, so finished buildings keep the shared material.
  Sold and destroyed buildings stay in `View3D.recs` until their animation ends (`Ent.end_kind`, `end_t`).
- Check them with `AF_SHOT=<dir> AF_MODE=b xvfb-run godot --path godot`. The test pauses the sim, so it moves
  `S.time` by hand between shots.

## Campaigns

- Missions live in `godot/scripts/campaign.gd` (three campaigns, 8 missions each). Each one draws its own map with
  `MapGen` (rivers, lakes, ridges, mesas, sea, roads, ore) in one of the landscapes in `D.THEMES`, optionally at dusk.
- Goals run in order (`Sim.mission_tick`): destroy_all, kill (types and/or tag), mine, survive, reach, hold, escort,
  rescue, capture. `keep` loses the mission when a hero or the Command Yard is gone. Heroes (`vey`, `furnace`, `harrow`,
  `saint`) and the Convoy Truck are mission-only units (`req: ["never"]`).
- `tests/sim_test.gd` sets up every mission, runs it a minute, then wins it goal by goal by cheating (`solve()`).
  Add a branch there for any new goal kind.
- `AF_MODE=camp AF_SHOT=<dir>` shoots the campaign menu, every briefing, every opening view and a wide map view.
- Campaign III, *The Hollow Song* (Guillaume 2026-11-15: "a third campaign for the burrow", meaning the Hollow Choir),
  is played as the Choir during the Iron Tide war. Since the 2026-11 overhaul it is locked behind II (story order; it was `"free"` before) and each
  mission names its enemy army with `efac` (Vanguard or Pact; default is the old rule). The Cantor is its hero (required in
  1, 4, 6, 8; trainable from mission 7); the Deepmaw (`deepmaw`, mission-only) joins in 6 to 8 and is never required.
  Enemy waves sent at `"harv"` also go for Crystal Gardens. Use Choir types in its data (`garden`, `thrall`), not `D.sub`.
  It has no cutscenes yet (Guillaume has not judged the style of the first batch).
- Story mood (overhaul, 2026-11-17): `Campaign.mood(camp, idx)` is 0 pulpy (I), 1 cracked (II from mission 5,
  `Campaign.CRACK`), 2 grim (III); each mission carries `mood`. `main.menu_stage()` picks the menu and logo stage from
  progress and `UI.set_stage()` restyles the menus (`UI.stage`, read by WarBG, Insignia, TitleMark, DoorArt, Hazard).
  `AF_STAGE=0|1|2` forces a stage for screenshots.
- Progress is saved per campaign in `user://campaigns.json`. Campaign II (the story sequel) stays locked until campaign I is won
  (Guillaume, 2026-11-14); `main.camp_open()`.
- Wave plans spawn the units they name whatever the mission's `aiTech` says (it is often empty). The test jumps to
  each wave of a wave goal and checks enemies really arrive.
- Heroes are only in some missions (Guillaume, 2026-11-14: not Vey in every mission). Campaign I: Vey in 1, 4, 6, 8
  (required), The Furnace in 6 to 8. Campaign II: Harrow in 1, 2, 7, 8 (required in 1, 2, 7), Iron Saint in 6 to 8
  (required only in 8). Other missions are plain army or base missions; keep `heroes`, `pheroes`, `keep` and the
  "must survive" line in `obj` in step.
- Campaign difficulty (Easy / Normal / Hard on the briefing, saved as `_level` in `user://campaigns.json`):
  `D.LEVELS` shifts the mission's AI tier (`D.DIFF_ORDER`, Easy can reach `recruit`), scales enemy start credits and
  wave sizes (`Sim.scaled`) and delays or advances the first attack. Balance target: Normal must be beatable on a phone
  (Guillaume could not beat Kettleford, 2026-11-14), so early missions keep the enemy off tanks and give the player a
  head start. Check a change with an AI-vs-AI soak (player side driven by `ai_think`) before raising enemy pressure.

## Cutscenes (Guillaume 2026-11-14: "Can you do cutscenes?")

- In-engine, no video: `scripts/cutscenes.gd` holds each scene as data (map borrowed from a mission, cast, shots with
  camera moves, subtitle lines, title cards, actions); `scripts/cutscene.gd` (`CutscenePlayer`, on top of the UI) draws
  the letterbox, subtitles, Skip and fades and drives the camera; `main.start_cutscene` / `play_reel` build the world.
- `Sim.cine` turns off AI, goals and win checks and shows the whole map; `"bare"` skips the mission's units (`gi = 99`, no marks).
  `View3D.cine` is a free orbit camera ({yaw, pitch}); `set_cine_look` swaps the black void for the menus' dusk sky.
- Scene ids: `<camp>_open` plays before the campaign's first mission the first time (seen ids in `_seen` of
  `user://campaigns.json`; the campaign screen has an OPENING button to replay it); `<camp>_<n>` is mission n's intro,
  played on every Begin. First batch: both openings and Embers mission 1. Guillaume wants to judge the style before more.
- Subtitles: short (the test fails over 64 characters), one per shot, large, in the bottom bar. Speakers in `Cutscenes.WHO`.
- Check with `AF_SHOT=dir AF_MODE=cine [AF_CINE=id,id] xvfb-run godot --path godot --fixed-fps 20` (one shot per camera cut).
  `cutscene_tests()` in `tests/sim_test.gd` runs every timeline on the sim.
- New scripts use `preload` constants, not `class_name`: the global class list comes from the installed APK's shell,
  so a class added in a self-update pack would be unknown on phones (cutscene.gd and cutscenes.gd do this).
- Boats: `mob` is a unit's movement class (0 land, 1 water, 2 hover; three A* grids). `shore` buildings need water beside
  them and may go on any seen bank. A finished boat is set down on the nearest open water (`Sim.roll_out`).
- Vanguard (phase 4): `RULES.vanguard` = no power, `place: "signal"`, cap from Command. Signal comes from the Yard and
  Signal Masts (`d.signal`, `Sim.in_signal`, `calc_signal`); a building outside it is `b.dark` (no production, no fire).
  Prefabs take `D.AEGIS.prefab` seconds whatever they cost. Deep Drill: `d.pump`, `d.onore`, `Sim.upd_drill` kills tiles
  and ends `b.dry`. Vehicles and aircraft are ordered at a Landing Zone (`d.pad`) and flown in (`send_dropship`,
  `upd_dropship`; packages are units with `cargo`). Aegis shields: `sh` in a def, `e.sh`/`sh_max`/`sh_t`, `Sim.aegis`,
  the Shield Dome (`d.dome`). Also `cloak`, `jump`, `detect`, `mark`, `pierce`, recovery beacons on wrecks.
  `vanguard_tests()`; `AF_MODE=vanguard`. Not built from the sheet: Kite as a player transport, Engineers planting
  Masts, the Walker crossing cliffs.
- Hollow Choir (phase 5): `RULES.choir` = no power, no cap, `place: "hum"`, `pods`, everything made by `garden`.
  The Hum (`d.hum` on the Yard, Gardens and the Carillon unit; `Sim.calc_hum`, `in_hum`, numbers in `D.HUM`): growths go
  only inside it, Choir units heal and hurry there (`Sim.hum_tick`, `u.inhum`), a Wretch (`wither`) fades outside it.
  A Garden (`grow`, `field`: roots beside live ore, anywhere seen) pays `d.rate` a second, ripens Pods (`b.pods`,
  `Sim.take_pod` when a unit starts), spreads crystal (`spread_crystal`) and ages twice: `D.UPG.garden` then
  `D.UPG3.garden` (`BLD3`, `b.lv` 3). `count(team, "bloom"|"cathedral")` counts aged Gardens, so forms use them as `req`.
  The Hollowing: `Sim.risers` (set in `kill`, raised by `upd_risers`). Mutation: `mut` in a def, `u.kills`, `Sim.mutate`
  (the unit gets its own def copy and `lv` 2, which the view shows as crystal on the model). Fusion: `fuse` in a def,
  `Sim.fuse`, the FUSE button. Keener `cry` sets `jam_t` (no firing) and drops shields. Burster `suicide`. Weapons
  `toll` (infantry only, round the target) and `crush`. Thornglass `thorn`. Units with `free` or `retired` are never
  ordered. `Sim.lacks(team, type)`: the army has no stand-in for a shared type. `choir_tests()`; `AF_MODE=choir`.
- Balance: `AF_ONLY=duel AF_A=ashen AF_B=choir AF_N=4 AF_MIN=14 godot --headless --path godot tests/sim_test.tscn` plays
  AI against AI and prints the score. Team 0 has a small edge, so run every pairing both ways. Each faction can have
  its own `ai_order` in `D.FACS`. Other partial runs: `AF_ONLY=vanguard|choir|choirsoak|missions|cards`.

## Unit tutorial (Guillaume 2026-11-19: "Add a full in campaign tutorial for each unit")
- All words and rules live in `godot/scripts/tutorial_data.gd` (`CARDS`, `ENEMY`, `LESSONS`, `MISSIONS`, `TXT`), kept in one
  place for i18n later. Behaviour is `godot/scripts/tutorial.gd` (a Node made by `main.gd`, field `main.tut`). Both are
  preloaded, no `class_name`.
- A card opens when a unit/building with a card first appears on the player's side and its `home` mission is reached, or
  earlier when the player trains/builds it. Cards pause the game; enemy cards are a small corner panel that does not.
  `LESSON_ONLY` (hq, power, barracks) are taught by the "base" lesson instead of a card.
- The sim calls `S.tut_cb` through `S._tut(kind, a, b)` for kills, heals, engineer fixes, launches, finished units and
  upgrades; `main.gd` sends input events (select, move, box, dbl, rally, group, queue5, placing...). New input that a
  lesson teaches must call `tut.ev(...)`.
- Saved in `user://tutorial.json` (`mode` full/cards/off, `seen` keys). Pause menu: "Tutorial:" mode and "Field manual";
  briefing: tips toggle; Campaigns header: "Reset tutorial" (two taps).
- Tests: `tutorial_tests` in `tests/sim_test.gd` checks line lengths for phones and that every unit/building the player
  owns at the start of a mission has a card due by that mission (buildable ones only need a card to exist).
- Screenshots: `AF_SHOT=dir AF_MODE=tut xvfb-run godot --path godot` (16 shots: cards, lessons, drills, manual, menus).
- Campaigns II and III have their own cards, enemy cards (`ENEMY.vanguard`, `ENEMY.choir`) and one pointer lesson each
  (`signal`, `hum`). They teach only what is new in that army. An enemy card shows once per type across all campaigns
  (`TD.enemy_card(type, camp)` picks the campaign's wording). Cards are drawn in their army's colours whatever match is
  on (`Turntable.show_model` builds outside the model cache). `AF_MODE=cards` shoots manual pages (`AF_KEYS=a,b`).

## Audio and UI on phones

- Sounds come from `godot/tools/synth.py` (`python3 tools/synth.py .` from `godot/`). Keep the current levels:
  Guillaume tried +9 to +20 dB louder (PR #4) and asked for the original levels back (2026-11-13).
  To check that the game makes sound without a sound card, record a run with `--write-movie out.avi --fixed-fps 20`
  and measure the audio track with ffmpeg.
- `main.gd _on_resize` scales the UI on mobile from the screen DPI (`content_scale_factor`, about 180 UI units per
  inch, so about ×1.25 on a 2410×1080 phone; Guillaume found ×1.5 too big). Test a phone layout with `AF_DPI=400 ... --resolution 2410x1080`.

## Keeping this file up to date

When you learn something a future agent would need (a convention, a gotcha, a check to run), add it here
in your PR, keep it short, and mention the change in the PR description.
- Keep buttons and text inside the safe area: `main.gd _apply_safe` feeds `UI.set_insets` from the display safe area
  (camera hole/notch, either landscape side) with at least 24 UI units at the sides and 8 at top/bottom on phones
  for rounded corners. Backgrounds still bleed to the edges. Simulate a cutout with `AF_SAFE=left,top,right,bottom` (pixels).
- Touch controls (Guillaume, 2026-11-14): one finger drags the map (he tried two-finger panning and did not like it),
  taps select/order, hold-then-drag boxes (or faces a formation when units are selected and the hold starts on open
  ground). Pinch zooms past a 12% dead zone. `main.gd PAN_FINGERS = 2` is the two-finger variant. The side panel
  hides with the `»` button in the top bar (`UI.set_panel`, `user://prefs.json`); use `U.panel_px()` for its width.
- Contextual side panel (Guillaume 2026-11-27: "build for workers, hire on barracks ... custom actions on units"; no
  worker units, the Command Yard stays the builder, C&C style): `main.show_ctx()` picks the panel's context from the
  selection (`ctx_key`: "yard" for nothing or the Yard, "b<id>" a building, "u" units, "e<id>" an enemy) and only then
  re-filters the items; `_ctx_head` fills the header (`UI.ctx_box`), `sel_line(e)` gives a selection's one-line hint.
  A producer lists the units whose `S.unit_from` is its type; `prod_cats(bt)` > 1 shows sub-tabs (`UI.tabs`, now only
  INF/VEH/AIR). Production is still one queue per category per team. Building and unit orders (upgrade, repair, muster,
  fuse, sell) live in `UI.ctx_acts` in the panel; the bottom-left `cmd_top` keeps Launch, Attack, Stop, deselect and the
  squad strip's type chips. With the panel hidden, selecting a building (or Thralls that can fuse) "peeks" it open
  (`peek`, `_show_panel`) until the selection clears. `AF_MODE=ctx` (AF_FAC=one) shoots every context per army.
- Unit orders in the panel (phase 2, same day): stances `Ent.hold` (Hold ground: auto-targets only within weapon range
  and walks back to its spot, via the leash in `Sim.upd_unit`) and `Ent.nofire` (no auto targets; an attack order still
  fires), Scatter, To base (the Yard's rally point), JUMP (`main.jump_aim`, then `Sim.jump_to`, 12 s cooldown shown on
  the button), STRIP (`Ent.strip`: a Scrapper strips even a revivable wreck) and FUSE. `main._unit_btns` shows the ones
  the selection can use; an army's own button acts only on the units that have it. The AI never sets these.
  `order_tests` in `tests/sim_test.gd` (`AF_ONLY=orders`).
- LOOP (Guillaume 2026-11-27, "build units loops"): a selected producer's LOOP button sets `tm.loop[building type]`;
  `Sim.upd_prod` puts a finished unit back at the end of its line while it is on (never one-of-a-kind units). Paid per
  unit as usual; waits when broke or capped (the header says UNIT CAP FULL). The top-bar chip shows a loop mark.
- Phone HUD extras (2026-11-14): producer chips in the top bar (`UI.ProdChip`, one per kind of producer you own,
  `main.producers` from `_setup_producers`, `_prod_chips`, `prod_chip_tap(bt)` selects it, 2026-11-27), army groups
  (`main.groups`, `group_btn`), objective auto-hide (`obj_t`, `OBJ_SHOW`), drag-to-build from `BuildItem`
  (`drag_build_*`, `GHOST_LIFT`), hold a unit item = queue five, corner ✕ cancels. `AF_INPUT=1` replays all of them.
- HUD look (2026-11-14, "UI too simple, keep low poly but increase quality"): HUD buttons are `UI.HudBtn` made by `mkbtn(text, cb, w, h, size, glyph)`;
  `restyle`/`set_on` give them cached chamfered olive plates (`hsb`) with brass ticks. Icons are vector glyphs in `UI.glyph`
  (aur, pwr, atk, stop, form, inf, veh, air, map, build, repair, sell, up, launch, obj, lock, ...), no image files.
  Readouts sit on `UI.Plate` (`plate_sb`, optional coloured left bar). Health bars: `main._hp_bar`; order prompts: `main._order_banner`.
  The UI is 600 units tall divided by `content_scale_factor` (capped at 1.5), so a high-DPI phone has only ~400 UI units
  of height: Guillaume's phone hits the cap (2026-11-14, menu was cut off). Check menus and HUD with `AF_DPI=520` as well
  as 400. Group chips are pinned under the OBJECTIVE button; the objective box opens over them.
- Menus (2026-11-14, "too much small text"): few words, nothing under 12-13 UI units except the build line; the start
  screen is title + two doors + field manual, the briefing is two columns with difficulty and Begin on one row.
- 3D look (2026-11-14): `Models.LOOK` is pasted into both lit shaders (hemisphere shading, drifting cloud shadows,
  silhouette rim; off when `fog_on` is 0, as for the build icons). Filmic tone, mild grading and bloom on emissive parts
  are in `View3D._ready`, and turned off on the GL Compatibility fallback, which already renders darker. Water depth and
  shore foam come from a heightmap texture of `S.H` (`height_tex`), not the depth buffer (it read empty here).
- Front-end overhaul (2026-11-16, brief and story bible in the Aurite project): terrain calm-down constants are
  `View3D.TERR_*` (vertex jitter, colour noise, grass desaturation, softened facet normals). On units, large
  team-coloured parts are painted with the faction hull (`Models.HULL`), tinted by `PAINT_TOP` (roofs) and
  `PAINT_SIDE`; parts thinner than `ACCENT_MAX` keep the full team colour. Buildings are unchanged.
  Effects go through an `Sfx` bus (glue compressor) and the Music bus ducks under it (sidechain compressor);
  nothing is louder.

## Premium low-poly look (Guillaume 2026-11-22: "go for b")

- Plan: Claude Doc "Aurite Front: premium low-poly plan" (https://claude.ai/artifact/XWgUVVi5rV7LVkCJt3QYdN), 7 phases,
  each its own PR with a before/after preview. Target: the "premium low-poly" concept render (rounded edges, clean calm
  paint, soft crease shadow, faceted tidy nature, warm sun with cool shadow). Everything stays built in code; CC0 assets
  are allowed but credited.
- Graphics levels live in `scripts/gfx.gd` (preloaded as `GFX`, no class_name): 1 Low, 2 Medium, 3 High (Pixel 11
  Pro). The old flat "Classic" look (level 0) was removed in phase 7; a saved 0 or any unknown value loads as High
  (`GFX._valid`). The pause menu cycles High, Medium, Low (`main.cycle_gfx`, saved as `prefs.gfx`); `AF_GFX=1..3`
  forces one for tests and screenshots. Changing the level calls `View3D.apply_gfx()`: materials, the model cache and
  the world are rebuilt. New look features read `GFX.level`; every level gets the premium look, levels only trade
  detail (rounding, fir tiers, shadows) for speed.
- Models: `Builder.add` rounds boxes (`Models.bevel_box`) and shades round cylinders smooth
  (`Models.smooth_cyl`); `Builder.finish` bakes a crease shadow from nearby parts and the ground into UV.x
  (`bake_creases`), and UV.y holds each part's bottom-to-top gradient. Write vertices only through `Builder.buf(par)`
  so the five buffers (verts, normals, colours, uvs, prim index) stay the same length. `gfx_tests()` in
  `tests/sim_test.gd` (`AF_ONLY=gfx`) checks every level builds the same named parts and High rounds more than Low.
- Ground (phase 2): `scripts/ground.gd` (preloaded as `Ground`) builds one smooth indexed terrain mesh
  over `S.H` and paints it per pixel from a splat texture (R soil, G sand/shore, B rock, A ore ground; 4 px per tile)
  with noise-wobbled borders and a darker rim, slope cliffs, wet banks, and a contact shadow from `S.bmap`
  (`Ground.update_occ`, called from `View3D.refresh_decor` whenever buildings change). `AF_MODE=themes` shoots the same map in all six themes, near, far and at the river.
- Nature (phase 3): `scripts/nature.gd` (preloaded as `Nature`) makes the decor meshes: tiered faceted
  firs (pine, snowpine with a snow cap instance), round faceted crowns (broad), bushes, rocks and five-crystal aurite
  clusters. Vertex colours hold only shade (and glow alpha on crystal tips); MultiMesh instance colours give the hue.
  `View3D.refresh_decor` places them; dead trees (ash) are bare trunk and branch sticks. `Nature.reset()`
  runs on a level change.
- Light and mood (phase 4): `GFX.MOOD[theme]` sets how warm the sun and how cool the shadows are, the
  ambient energy and tint, and the ground brightness; `GFX.GRADE` grades by chapter from the player's faction in a
  campaign mission (`GFX.mood_of`): Ashen Pact "pulp" (warm, punchy), Vanguard "neutral", Hollow Choir "grim" (cold,
  flat, dimmer sun). Saturation and contrast only apply on the Mobile renderer (GL Compatibility has no adjustments).
- Faction polish (phase 5): `Models.pal()` lifts the near-black paints (`PREMIUM_PAL`, keyed by MAT
  name) and `Models.HULL` holds the lighter unit hull colours, so Pact iron and Choir earth read as material; on buildings,
  big team-coloured slabs (second-largest side over 0.3) are toned 35% toward the faction metal. Use MAT colours (not
  hand-made ones) for new parts so the palette applies.
- Battle effects (phase 6): smoke, flashes and flames use `Nature.puff()` (a smooth round puff) with
  rims that fade by `dot(NORMAL, VIEW)`, so smoke reads soft and fire as glowing balls. `View3D.apply_gfx` rebuilds the
  effect batches. `AF_MODE=battle` shoots two armies trading fire.

## Squads (Guillaume 2026-11-27: "auto groups that would merge the bottom and numbered group")

- The squad chips (in the side column's dock since the two-thumb layout, see below) replace the old army groups 1-4
  (left edge, hold to store) and the ALL/INF/VEH/AIR/IDLE buttons. Rules live in `scripts/squads.gd` (preloaded as `Squads`, no class_name):
  a selection of 2+ units that gets an order (`main.command` calls `_squad_order`) becomes a squad; a unit is in one
  squad; part of a squad splits off, whole squads merge into the lowest number; five squads at most; deaths only shrink.
  A selection made by ALL (`main.sel_src == "all"`) never reshuffles squads.
- Chips: `UI.SquadChip` (key > 0 squad, 0 ALL, -1 NEW) in `U.cmd_bot`. JOIN (`U.btn.join`) and type chips
  (`U.type_btns`, `U.cmd_top`) sit above them. A box or a swipe sets `sel_src = ""`, so part of ALL picked by hand
  forms a squad on its next order. Tutorial drills use the `group_recall` event (a squad chip selecting squad i + 1).
- `squad_tests()` in `tests/sim_test.gd`; `AF_MODE=squads` shoots the strip, JOIN and type chips at phone size.

## Radar (Guillaume 2026-11-27: "a radar mode by zooming out, you can then handle units in bulk")

- It REPLACES the minimap and the MAP button (both removed), and opens by pinching only: Guillaume asked for no
  button. Proposal mock-up: project files `aurite-overhaul/radar/`.
- Camera (`view3d.gd`): `cam_z` now goes down to `Z_MIN` (whole 64x64 map in view). Past `Z_NEAR` (today's old limit)
  `radar_pull()` tilts the camera toward `PITCH_TOP` and `clamp_cam` draws it toward the map centre; `radar_k()` is 0 at
  `Z_NEAR` and 1 at `Z_RADAR`. From `radar_k() >= 0.6`, `radar_on`: `ents_root` (every unit and building model),
  trees, rocks, bushes and sun shadows are hidden, so the whole-map view is cheaper than normal play. A cutscene
  camera (`cine`) never counts as radar.
- Drawing: `scripts/radar.gd` (preloaded as `Radar`, no class_name), called from `main.draw_hud` (health bars are
  skipped in radar). `UI.radar_tint` is a screen-reading ColorRect under the HUD that greys the view by `k`.
  Icons: circle infantry, square vehicle, triangle air, diamond harvester; buildings are footprints (star = a `yard`);
  enemies follow the fog. Squads get a ring, a badge (`Radar.badges`, used for taps) and a heading line (red to an
  attacked enemy, pale to a move destination); hits pulse red; `S.ping` (the old minimap alert) pulses too.
- Input (`main.gd`, only while `radar_k() >= 0.5`): tapping a badge calls `radar_badge` (adds or drops that squad
  while the selection is whole squads, else selects it alone); a tap right on an enemy icon beats a badge. Squads
  picked together have `sel_src == "multi"`, and `_squad_order` skips "multi" like "all", so ordering them keeps
  their numbers (outside the radar, ordering whole squads together still merges them). Dragging a badge
  (`bpending`/`bdrag` gestures) sends that squad alone (`radar_send`) and keeps the selection. One finger on open
  ground draws a box (no hold needed); from one of your icons it swipes them up. No double-tap dive any more (its
  first tap had already sent the army there, 2026-11-28): pinch in to come back down.
  Picking uses small radii in radar (14 own, 20 enemy).
- `AF_MODE=radar AF_SHOT=dir` shoots near / blend / radar, then replays badge taps, an attack, a badge drag, a box
  a double-tap (no dive) and a swipe with real touch events, printing RADAR lines. Software rendering runs at ~4 fps here, so the dive is
  sent straight to `tap()`.

## Two-thumb controls (Guillaume 2026-11-28: "one thumb for moving and the other for actions")

- He ended up selecting ALL every time because picking part of the army was too hard. Plan and mock-ups: project
  files `aurite-overhaul/controls/`. Portrait was discussed and set aside (landscape first).
- Map thumb (`main.gd` input): no buttons on the map. One finger on open ground drags the map; a finger that lands on
  one of your units and moves is a swipe (`gest.mode == "paint"`, `_paint`): every unit within `BRUSH` (34 UI units,
  `BRUSH_RADAR` 18 in radar) of the finger's path is picked, live, harvesters only if nothing else was swept. Tap,
  double-tap, pinch and the radar badges are unchanged. Removed on touch: hold-then-drag box, hold-drag formation
  facing, hold-and-release deselect (`_check_long_press`), the radar double-tap dive. The mouse keeps left-drag box and
  right-drag facing. Formation is always on (its button is gone; `S.formation` stays for tests).
- Action thumb: radial controls (`scripts/radial.gd`; he asked for "radial controls on the bottom right corner",
  "sectors instead of points", "ring menus around structures", "the structure visible in the middle, 8 sectors max").
  - `Radial.Wheel` (`U.wheel`), a quarter circle in the BOTTOM-LEFT corner by default (Guillaume, after the first
    preview: commands under the left thumb, he selects and moves with the right; prefs `wheel`, Pause > Wheel: right
    mirrors it). Hub = ATTACK while units are picked (STOP for an unarmed pick), else YARD (READY when a structure
    waits; it selects the Yard). Inner ring: squads ALL, 1-5 (health arc, ! under fire); NEW is a plate over the
    wheel. Outer ring, the widest sectors (he found too many buttons near the corner): the pick's orders (Stop, Hold,
    No fire, Scatter, To base, Jump/Strip/Fuse), or with nothing picked the other producers (`prod_chip_tap`).
  - `Radial.Ring` (`U.ring`): around a single selected structure of yours, one ring of at most `MAX` (8) sectors with an
    open centre. Rule (`rebuild`): items + orders fit in 8 -> all on the ring; else 2+ orders fold into ORDERS; still
    more than 7 items -> the Yard splits into a first ring of basic structures plus an ADVANCED sector (`Radial.ADV` per faction, his "basic versus advanced"; a ready advanced structure rides on that sector and drags out of it), else categories (`_bld_groups` BASE / ARMY / DEFENCE; producers: INF / VEH / AIR; any group
    over 7 splits in parts), each opened with BACK; a READY building keeps its own sector on the first ring. Tap queues
    (`click_item`), hold 0.55 s queues five or cancels a building, the ✕ / ×N badge cancels one, a READY sector drags
    out (`drag_build_*`). The ring dims the map outside and NEVER moves the camera ("I don't want the map to jump"): near an edge or the
    wheel it slides onto the screen with a brass leader to the structure (`_place`). It hides in radar and
    while placing (but stays alive during its own drag so the drag keeps its events).
  - Both draw state they read from the old side column, which is built but never shown (`panel_px()` is 0,
    `set_panel` keeps it shut): `U.items` (BuildItem state from `refresh_panel`), `U.btn` visibility/on/cap from
    `update_cmd`, the SquadChips from `_squad_chips`, `U.prod_chips`. Game logic did not move.
  - Over the wheel (`U.plates`): the selection header (`ctx_box`, hidden for a mixed pick), the type chips, and a row of
    JOIN / Launch / "N PICKED ✕". While placing, `U.place_bar` (hint, Build here, Cancel) takes the wheel's corner.
  - Tutorial `{"item"}` pointers: the ring sector (or its category), else the producing building on the map, else its
    wheel sector, else the top chip.
- Pause > "Wheel: left/right" (`main.toggle_hand`, prefs `wheel`, default left) mirrors the wheel, plates and place
  bar (`U._place_radial`).
- `AF_MODE=ctx` shoots each faction's Yard ring, a category, producers' rings, an order-only building and a unit pick.
- `AF_INPUT=1 AF_SHOT=dir` prints INPUT lines for the swipe (from ALL), a hold-drag that now just pans, real touches on
  the wheel (hub ATTACK, ALL), a READY structure dragged out of the Yard's ring, and the rest.

