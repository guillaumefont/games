# Notes for coding agents

Mer des Brumes is an original low poly pirate naval battle game in Godot 4.7, portrait only. It is a port of
Guillaume's web prototype (`web/index.html`, a single Three.js page, published under `prototype/`; the design
doc lives in the project, not in this repo). The mood is inspired by Bad North (muted misty palette, minimal
UI): take the mood only, never that game's assets, look or names. The game's text is in French.

Guillaume's decisions so far (keep them unless he changes his mind):
- The joystick appears under the thumb; its direction is the heading, its reach the speed. The sail stays
  set when the thumb lifts. Edge-of-screen arrows point to the port, the treasure and the foe (no compass).
- Broadside combat: guns fire within arcs to the sides (plus bow/stern chasers on some hulls). The tactic is
  to get behind the enemy; the AI (`Rules.ai_choose`) also manoeuvres for this.
- Manual aim (2026-11-23): a connected player fires only with the green aim stick (bottom right, in a
  fight): only its direction counts (2026-11-23: "uniquement la direction, pas la distance"). While
  aiming, a red line runs from the ship until the first ship or island it meets (2026-11-25); letting go
  fires every loaded battery that bears that way at what the line meets (nothing if it's beyond range,
  the guns' range if it meets nothing). Balls fly fast (`Game.BALL_SPM`, `BALL_T0`, `BALL_ARC`).
- Grapple and boarding (2026-11-25): a purple stick (bottom left) and purple line, same handling; letting
  go throws the grapple at the first ship on the line within `st.grapple` (10 m + 4 per Grappins level).
  Caught: the ships are pulled side by side, guns stop, and the crews and captains fight
  (`Rules.fighters` / `Rules.melee`: blows hit the crew first, the captain last). All of theirs down:
  treasure ×2 (coins and map chance) and a prompt to take the ship (`Rules.take_hull`, your old hull is
  left) or sink it. All of ours down: the ship is lost like a sinking. The dead are lost for good.
  Attacking (online) enemies grapple too; ones that only defend never do. "Couper les cordes" ends it.
  The old automatic crew damage when ships touched is gone. The ship defends itself (manoeuvres and fires alone) **only while the player is
  disconnected** (`Game.connected`, false on app pause / focus loss), never while connected.
- No oars (2026-11-27): every hull sails from the start (the chaloupe with one sail); the "Voiles" upgrade
  adds visible sails (a jib, then topsails: `Models.extra_sails`). Old saves get the rowers' price back.
- The grapple is a paid option (2026-11-27), bought once with coins (`Rules.buy_hook`, never real money) in
  the Équipage tab; it stays from hull to hull. Without it there is no purple stick; "Grappin plus long" in
  the Chantier lengthens it. Small enemies (level 1) have none and never grapple.
- The crew is seen and moves on deck (2026-11-27, `scripts/crew.gd`): each kind has its own figure and moves
  (sabres brandish and slash, pistols and muskets aim with recoil, grenadiers toss and throw, the captain
  holds the wheel); they face the foe in a fight and the fallen lie on deck during a boarding.
- Ship styles (2026-11-27, `Rules.SKINS`, colours in `scripts/looks.gd`): Classique, Forêt, Glace, Magie,
  Abysses, Volcan. They change the hull, sails, crew clothes and weapons, the balls (snowballs, fireballs...)
  and the boarding puffs. Never bought: each unlocks by a feat (`need`, counted in `s.stats`) when you next
  enter the port, then is chosen for free in the Chantier. Some enemies (level 2+) show styles too.
- Upgrades are capped per hull; past the caps you buy a new hull (Sloop: fast; Frégate: better armed, bow
  and stern guns; Galion). A new hull starts without upgrades.
- Coins only: the diamond currency was dropped ("stupide"); never reintroduce a premium storage currency.
  Old saves pay diamonds back as 100 coins each.
- Treasure maps come only from sunk ships (no buying). Being sunk costs half the coins on board; the port's
  coffre is safe.
- The port is a parchment menu of constant size (tabs on one row) with a turning 3D preview of the ships.

## Pull requests

- **Merging:** see the root [`AGENTS.md`](../AGENTS.md).
- Every PR body lists its preview builds near the top, under a `## Preview` heading:

  ```
  ## Preview
  - Play in the browser: https://guillaumefont.github.io/games/mer-des-brumes/pr/<N>/
  - Android APK: https://guillaumefont.github.io/games/mer-des-brumes/pr/<N>/mer-des-brumes.apk
  ```
- All APKs share one app id (`io.github.guillaumefont.merdesbrumes`) and one test keystore
  (`.github/android/debug.keystore`), so a PR build installs over the `main` build.

## Keeping this file up to date

When you learn something a future agent would need, add it here in your PR, short and lasting, and say so
under an `## AGENTS.md` heading in the PR body.

## Tests

- Every change comes with a test; a bug fix gets a regression test. A new test file gets a step in
  `.github/workflows/mer-des-brumes-test.yml` (at the repo root) and a line below.
- Game tests load `scenes/main.tscn` with `driven = true` (so `_process` doesn't read real input) and
  `save_path` set to a test file, then call `step(dt)` themselves. Simulated touches go through
  `root.push_input(event, true)` as mouse events (touch is emulated as mouse).

```
godot --headless --path . --import
godot --headless --path . --script tests/game_test.gd    # rules, joystick, aim and grapple sticks, boarding, crew, styles, broadsides, AI, sinking, treasure, port
godot --headless --path . --script tests/update_test.gd  # self-update: pack download, checks, APK offer
godot --headless --path . --script tests/icon_test.gd    # project icon and Android launcher layers
```

Screenshots (needs a display):
`xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/shots.gd -- /tmp/shots`
Close-ups of every style and of a boarding: same command with `tools/style_shots.gd`. Tools must `await` a
frame after `root.add_child(game)` before touching `game.s` (`_ready` hasn't run yet; an error there hangs
the tool silently).

## Code map

- `scripts/rules.gd` (`Rules`): every number and rule (hulls and caps, upgrades, crew, port, enemies, the
  islands' seed, the AI's choice of heading), pure functions on the save dictionary. Save: `user://save.json`.
- `scripts/models.gd` (`Models`): flat-shaded, vertex-coloured meshes built in code (`Models.Builder` merges
  parts into one mesh). The hull is lofted from frames; sails billow and the sea waves in shaders, which
  take flat normals from screen derivatives. Heading h faces (sin h, cos h); `rotation.y = h`.
- `scripts/game.gd` (`Game`): world, player, enemies (`Game.Boat`), combat, balls, effects, treasure, camera.
- `scripts/crew.gd` (`Crew`): the men on deck (figures per kind and style, places, animation, the port lineup).
- `scripts/looks.gd` (`Looks`): the colours and weapon shapes of each ship style.
- `scripts/hud.gd` (`Hud`): glass HUD, gauge, joystick, edge arrows, labels, toasts, prompt, the port.

## Self-update (Android)

Same scheme as star-breaker: `scenes/boot.tscn` (`scripts/boot.gd`) checks `update.json` at launch and loads
a newer `mer-des-brumes.pck` built for the same shell; a new shell (engine, `project.godot`,
`export_presets.cfg`, the updater) offers the new APK instead, so avoid needless edits to those files.
`boot.gd` must not use any game class. The port's Fort tab shows the running build and, after a quiet check,
a "Nouvelle version N : relancer" button (`Game.refresh_game()`).

## Gotchas

- Android and Web use the Compatibility renderer (set in `project.godot`). Take screenshots with
  `--rendering-method gl_compatibility`.
- Vertex colours are sRGB: the shared material sets `vertex_color_is_srgb` (without it everything washes out).
- Text outlines on small labels render badly at phone scale: use a font shadow instead.
- Particles shrink instead of fading, so they need no transparency sorting.
- Don't run GDScript on worker threads, and no looping `AudioStreamWAV` (both crashed star-breaker on Android).
- UI is built in code: use `set_anchors_and_offsets_preset()`.
- Two sticks at once: `Hud._on_touch` follows each finger by its touch index and skips the mouse events
  Godot makes up from touches (`device == InputEvent.DEVICE_ID_EMULATION`); a real mouse is one more finger.
  Headless tests can't use `Input.parse_input_event`, so they push both events themselves (`finger()`).
- GDScript can't infer types from Dictionary fields: write `var k: float = d.x`, not `:=`.

## App icon

`tools/icon_shots.gd` renders the game's own sloop to `store/ship.png`, then `python3 tools/icon.py` (Pillow)
writes `icon.png`, `icons/` and `store/icon-512.png`. Commit the PNGs; CI runs neither. A new icon only shows
after installing a new APK.
