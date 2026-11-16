# Notes for agents

Perigee is an original one-button orbit-hopping game: a single HTML file (`web/index.html`) drawn on a
canvas, wrapped as an Android WebView app (`android/`). Added to the monorepo on 2026-11-16.

## Pull requests

- Merge via auto-merge (squash) once the required **CI gate** check is green (root `AGENTS.md`).
- Add a **Try it** section to the PR body once the PR number is known:

  ```
  ## Try it
  - Play in the browser: https://guillaumefont.github.io/games/perigee/pr/<N>/
  - Android APK: https://guillaumefont.github.io/games/perigee/pr/<N>/perigee.apk
  ```

## Build numbers

- Build number = 1000 + run number of the **Perigee builds** workflow, as for the other games. It is the APK's
  `versionCode` (read from the `BUILD` environment variable by `android/build.gradle`; don't hard-code one).
- All APKs share one app id and `android/debug.keystore`, so a PR build installs over the main build.
- There is no self-update: the game ships inside the APK, so a new build means installing the new APK.

## Game code

- Everything is inside one IIFE in `web/index.html`. `window.perigeeTest` is a read-only view of the game
  state for the play test; keep its fields (`state`, `score`, `hops`, `holding`, `player`, `planets`) working.
- The game must stay self-contained and work offline: no CDN scripts or remote fonts (the play test fails on
  any network request). Add assets under `web/`; the Gradle build copies all of `web/` into the APK.
- The moon index `k` (difficulty, `diff(k)`) is the `made` counter. It used to be `planets.length`, which stops
  growing once far moons are culled, so difficulty stalled around moon 17 until 2026-11-16.
- `window.PerigeeAndroid` exists only in the Android app (`Bridge.java`); the page calls it through `native()`
  and must work without it (the browser build has no ads, purchase or analytics). The app answers through
  `window.perigeeNative.onEvent(name, data)`.

## Android and Google Play

- `android/` is a Gradle project (AGP 8.11, compileSdk/targetSdk 36, which Google Play requires). Cloud sessions
  can't reach Google's Maven repository, so the Android build is only checked by the **Perigee builds** workflow.
- Release builds are signed with the Play upload key when `PERIGEE_UPLOAD_KEYSTORE` is set (CI, on `main`),
  otherwise with `debug.keystore`. Never commit the upload key.
- `web/privacy.html` must describe what the app really collects; update it with any new SDK or data.
  The Play listing text and Data safety answers are in `store/listing.md`; launch steps in `store/README.md`.

- Ads (`Ads.java`): Google's consent form (UMP) first, then AdMob: an interstitial on every 3rd "fly again"
  (at most every 90 s, none right after a rewarded ad) and a rewarded ad to continue a run once. AdMob ids live in
  `android/gradle.properties` (Google's test ids until the real ones are set).
- Purchase (`Store.java`): one-time product `remove_ads`, via Play Billing 8. It removes the interstitials and
  makes the continue free. No server check.
- Analytics (`Stats.java`): Firebase, only when `android/google-services.json` exists; events `run_start`,
  `run_end` (score, moons, continued), `ad_interstitial`, `ad_rewarded`, `continue_free`, `remove_ads`.

## Tests

- `tests/play_test.cjs` (workflow `perigee-test.yml`): loads the page offline in headless Chromium, checks fonts,
  lets a bot hop at least 3 moons, then checks game over, the best score and restarting, then fakes
  `window.PerigeeAndroid` to check the continue, remove-ads and privacy buttons. CI greps for its last
  line, `PLAY TEST DONE`; keep it last and add a check there for any new behaviour.
