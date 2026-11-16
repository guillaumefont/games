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
  `io.github.guillaumefont.perigee`, portrait, minSdk 23, targets Android 16 / API 36 as Google Play requires).
  A Gradle project (`./gradlew assembleRelease` for the APK, `bundleRelease` for the Play bundle).
- `web/privacy.html`: the privacy policy, published at https://guillaumefont.github.io/games/perigee/privacy.html.
- `store/`: the Google Play listing text, Play Console answers, store graphics and the launch steps
  ([store/README.md](store/README.md)).
- `tests/play_test.cjs`: headless play test in Chromium (Playwright).
- `tools/make_icons.py`: draws `web/icon.png` and the launcher icons (Pillow).
- `tools/store_assets.cjs`: captures the store screenshots and feature graphic from the real game (Playwright).

## Run locally

```
node perigee/tests/play_test.cjs          # needs the playwright package and its Chromium
cd perigee/android && ./gradlew assembleRelease   # needs JDK 17 and the Android SDK (ANDROID_HOME)
# -> perigee/android/build/outputs/apk/release/perigee-release.apk
```

## debug.keystore

`android/debug.keystore` is a **test-only** key (alias `androiddebugkey`, passwords `android`), committed on
purpose: Android only installs an update over an installed app signed with the same key. Do not use it for
a Play Store release: Play builds are signed with the upload key from the repository's secrets
(see [store/README.md](store/README.md)).
