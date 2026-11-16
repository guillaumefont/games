# Perigee

An original one-button arcade game for iOS and Android: hop from moon to moon without drifting
into the dark.

- **Release** to fling off along your orbit.
- **Hold** while you cross a dotted ring to get caught by that moon.
- **Sparks** between moons are worth a bonus point.

Play the current build at https://guillaumefont.github.io/games/perigee/ or install the Android APK
from https://guillaumefont.github.io/games/perigee/perigee.apk. The original web prototype stays
playable at https://guillaumefont.github.io/games/perigee/prototype/ as the reference for how the
hop should feel.

The plan to a full game (modes, scoring, content, roadmap) is a separate document; see
`AGENTS.md`.

## Layout

The folder is a Godot 4.7 project (2D, Compatibility renderer, portrait).

- `scripts/sim.gd`: the game rules, deterministic (fixed 120 Hz step, one seeded RNG), no nodes.
- `scripts/main.gd`: runs the sim, draws it, handles the button, sound, haptics and pausing.
- `scripts/hud.gd`: score, sound toggle, hints and the start, game over and pause cards.
- `scripts/save_data.gd`: the versioned save file (`user://save.json`).
- `scripts/sfx.gd`: placeholder synthesised sounds.
- `fonts/`: Unbounded and Manrope (SIL OFL 1.1, licences next to them).
- `icon.png`, `icons/`: the icon and Android launcher layers, drawn by `tools/make_icons.py`.
- `tests/`: headless tests (see below).
- `web/`: the original HTML5 canvas prototype (ignored by Godot).

## Run locally

```
godot --path perigee                                    # play in the editor's runner
godot --headless --path perigee --import
godot --headless --path perigee --script tests/sim_test.gd   # rules, replay, difficulty
godot --headless --path perigee --script tests/game_test.gd  # scene, HUD, save, pause
node perigee/tests/prototype_play_test.cjs              # the web prototype (Playwright)
xvfb-run -a godot --path perigee --rendering-method gl_compatibility --resolution 824x1720 \
  --script tools/screenshots.gd -- /tmp/perigee-shots    # review screenshots
```

## Test signing key

`.github/android/debug.keystore` is a **test-only** key (alias `androiddebugkey`, passwords
`android`), committed on purpose: Android only installs an update over an installed app signed
with the same key. It is the key the earlier WebView builds used, so the Godot APK installs over
them. Do not use it for a store release.
