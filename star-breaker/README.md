# Star Breaker

**[▶ Play in the browser](https://guillaumefont.github.io/games/star-breaker/)** · **[⬇ Download the Android APK](https://guillaumefont.github.io/games/star-breaker/star-breaker.apk)**

<sub>Latest build of `main`, updated on every merge.</sub>

An original low poly 3D vertical shoot 'em up for phones (portrait, one thumb), built with
**Godot 4.7**. Cut back the blooming moon: three stages of The Hollow Moon so far, ending with
the Bloom Mother.

Every model, sound and song is generated from code (no imported meshes or audio files), and all
names, art and levels are original.

## Play

- **Browser:** every push to `main` is published on GitHub Pages
  (`https://guillaumefont.github.io/games/star-breaker/`), with the Android APK next to it
  (`star-breaker.apk`). Each pull request gets its own preview under `/pr/<number>/`, linked in a
  comment on the PR.
- **Godot:** open `project.godot` in Godot 4.7 and press Play.

## Controls

| Action | Touch | Keyboard / gamepad |
| --- | --- | --- |
| Fly | Drag anywhere: the ship follows your thumb 1:1 | Arrows / WASD, left stick |
| Fire | Automatic while your thumb is down | Automatic |
| Release | Lift your thumb. **Lance:** fires its charge beam (hold longer for LV 2, 3, the Nova, and at 7 s the Storm). **Warden:** flings or recalls its pod | C / K (hold, release), B |
| Ultimate | Keep holding until the charge bar is full (7 s), then lift. **Lance:** the Storm. **Warden:** Shatter | C / K (hold, release), B |
| Pause | Pause button, Android back, or just lift your thumb for 3 s | Esc / P, Start |

## Game

- **Ships:** **Lance** (charge beam; the Storm sends chain lightning through every enemy on screen) and
  **Warden** (a pod that blocks bullets, rams and fires; Shatter breaks the pod into shards and
  shields the ship).
- **Stages:** Spore Fields, Crystal Gate and Bloom Heart, each with enemy waves, a fortress of
  barriers (fixed, sliding, breakable, or locked until you destroy their generator), the
  occasional rock canyon or island, and a boss: the Shell Matriarch, the Shell Twins and the
  Bloom Mother.
- **Damage:** three hull points a ship, three ships a stage. Rock costs a hull point; skimming
  it without touching pays points.
- Best score per stage is saved.

## Project layout

| Path | What it holds |
| --- | --- |
| `scenes/main.tscn` | The game scene (everything else is built in code); `scenes/boot.tscn` runs the self-update first |
| `scripts/vgame.gd` | Game loop: fixed 60 Hz logic on a 126 x 224 playfield, enemies, barriers, rock, bosses, save, updates |
| `scripts/vstage.gd` | The stages: seeded enemy waves, fortresses, canyons and islands |
| `scripts/vships.gd` | Ship kits (release, ultimate) and the Lance model |
| `scripts/vhud.gd` | HUD and menus |
| `scripts/models.gd` | Materials and low poly models |
| `scripts/geo.gd` | Flat-shaded mesh builders |
| `scripts/audio.gd` | Chiptune synth: sound effects and songs rendered at start-up |
| `tests/` | Headless tests run in CI |
| `tools/` | Icon generator, screenshot script |
| `AGENTS.md` | Notes and rules for coding agents |

## Tests

```sh
godot --headless --path . --import
godot --headless --path . --script tests/vertical_test.gd # the game
godot --headless --path . --script tests/screen_test.gd  # crash report, safe graphics, menu, screen shapes
godot --headless --path . --script tests/audio_test.gd   # songs build on the main thread, all sound effects exist
godot --headless --path . --script tests/update_test.gd  # self-update
godot --headless --path . --script tests/icon_test.gd    # app icons
```

Screenshots (needs a display, e.g. `xvfb-run`):

```sh
godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/vertical_shots.gd -- /tmp/shots
```

## CI and builds

- `.github/workflows/star-breaker-test.yml` (at the repo root) runs the headless tests on every pull request and on `main`.
- `.github/workflows/star-breaker-build.yml` (at the repo root) exports Web and Android (release template, arm64) for `main` and
  every pull request, uploads the APK as a run artifact, and publishes both to the `gh-pages`
  branch; `pages.yml` deploys that branch. A closed PR's preview is deleted.
- Every APK is signed with the fixed test keystore in `.github/android/debug.keystore` (or the
  `ANDROID_DEBUG_KEYSTORE_BASE64` secret), so a new build installs over the previous one.
  `versionCode` is `100 + run number`, so it always goes up.
- One-time setup: **Settings > Pages > Source = GitHub Actions**.

## Licences

Code: see `LICENSE`. Rubik font (`assets/fonts/`) by the Rubik Project Authors, SIL Open Font
License 1.1 (`assets/fonts/OFL.txt`).
