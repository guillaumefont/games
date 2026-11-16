# Perigee

An original one-button arcade game: hop from moon to moon without drifting into the dark.

- **Release** to fling off along your orbit.
- **Hold** while you cross a dotted ring to get caught by that moon.
- **Sparks** between moons are worth a bonus point.

Play it at https://guillaumefont.github.io/games/perigee/ or install the Android APK from
https://guillaumefont.github.io/games/perigee/perigee.apk.

## Layout

- `web/index.html`: the whole game (HTML5 canvas, no libraries). `web/fonts/` holds the Unbounded and
  Manrope fonts (SIL OFL 1.1, licences next to them) so it also plays offline. `web/icon.png` is the icon.
- `android/`: the Android app, a full-screen WebView around a copy of `web/` (package
  `io.github.guillaumefont.perigee`, portrait, minSdk 23). `android/build.sh` builds it without Gradle.
- `tests/play_test.cjs`: headless play test in Chromium (Playwright).
- `tools/make_icons.py`: draws `web/icon.png` and the launcher icons (Pillow).

## Run locally

```
node perigee/tests/play_test.cjs          # needs the playwright package and its Chromium
sudo apt-get install android-sdk-platform-23 aapt dalvik-exchange zipalign apksigner
BUILD=1 perigee/android/build.sh          # -> perigee/android/build/perigee.apk
```

## debug.keystore

`android/debug.keystore` is a **test-only** key (alias `androiddebugkey`, passwords `android`), committed on
purpose: Android only installs an update over an installed app signed with the same key. Do not use it for
a Play Store release.
