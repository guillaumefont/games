# Perigee

An original one-button arcade game for iOS and Android: hop from moon to moon without drifting into
the dark.

- **Release** to fling off along your orbit.
- **Hold** while you cross a dotted ring to get caught by that moon.
- **Sparks** between moons are worth a bonus point.

Play the Godot build at https://guillaumefont.github.io/games/perigee/ or install its Android APK from
https://guillaumefont.github.io/games/perigee/perigee.apk. Once installed, the APK updates itself at launch
(as Star Breaker does), and the start card says when a newer build is out. The original web game stays playable at
https://guillaumefont.github.io/games/perigee/prototype/ (as an APK: `perigee-webview.apk`), the reference
for how the hop should feel.

## Layout

The folder is a Godot 4.7 project (2D, Compatibility renderer, portrait), next to the original web game.

- `scripts/sim.gd`: the game rules, deterministic (fixed 120 Hz step, one seeded RNG), no nodes.
- `scripts/main.gd`: runs the sim, draws it, handles the button, sound, haptics and pausing.
- `scripts/hud.gd`: score, sound toggle, hints and the start, game over and pause cards.
- `scripts/save_data.gd`: the versioned save file (`user://save.json`).
- `scripts/sfx.gd` and `scripts/music.gd`: sound effects and the looping music track, from `audio/`.
- `tools/audio/compose.py`: composes and renders all the audio (`python3 perigee/tools/audio/compose.py`).
- `fonts/`: Unbounded and Manrope (SIL OFL 1.1, licences next to them).
- `icon.png`, `icons/`: the icon and Android launcher layers, drawn by `tools/make_icons.py` (which also draws
  `web/icon.png` and the WebView app's launcher icons).
- `tests/`: headless tests (see below).
- `web/index.html`: the original web game (HTML5 canvas, no libraries), with its fonts in `web/fonts/`.
- `android/`: the WebView app around a copy of `web/`, the reference APK (a Gradle project,
  `./gradlew assembleRelease`). The Google Play bundle is the Godot game (export preset "Android Play", built in CI).
- `web/privacy.html`: the privacy policy, published at https://guillaumefont.github.io/games/perigee/privacy.html.
- `store/`: the Google Play listing text, Play Console answers, store graphics and the launch steps
  ([store/README.md](store/README.md)).
- `tools/store_assets.cjs`: captures the store screenshots and feature graphic from the web game (Playwright).

## Run locally

```
godot --headless --path perigee --import
godot --headless --path perigee --script tests/sim_test.gd   # rules, replay, difficulty
godot --headless --path perigee --script tests/game_test.gd  # scene, HUD, save, pause
godot --headless --path perigee --script tests/update_test.gd  # self-update
xvfb-run -a godot --path perigee --rendering-method gl_compatibility --resolution 824x1720 \
  --script tools/screenshots.gd -- /tmp/perigee-shots    # review screenshots
node perigee/tests/prototype_play_test.cjs              # the web game (needs playwright)
cd perigee/android && ./gradlew assembleRelease         # WebView APK (JDK 17 and the Android SDK)
```

## debug.keystore

`android/debug.keystore` is a **test-only** key (alias `androiddebugkey`, passwords `android`), committed on
purpose: Android only installs an update over an installed app signed with the same key. Both the Godot and the
WebView preview APKs use it. Do not use it for a Play Store release: Play builds are signed with the upload key
from the repository's secrets (see [store/README.md](store/README.md)).
