# Notes for agents

Each game folder has its own `AGENTS.md` with game-specific notes. The rules below apply to every game.

## Merging pull requests

Rule from Guillaume, 2026-11-15. It replaces the older per-game merge rules.

- Agents may merge their own PRs into `main` (squash) **only when all checks are green**. While checks are still
  running, turn on GitHub auto-merge (squash) so GitHub merges the PR once every required check is green. If the
  checks are already green, GitHub refuses auto-merge, so merge the PR directly (squash); Guillaume allowed this
  on 2026-11-16. Never bypass the `main` ruleset. (A real merge queue needs an organization-owned repo, and this
  repo belongs to a personal account.)
- **All checks must be green.** The required check is **CI gate** (`.github/workflows/ci-gate.yml`), which
  waits for the build and headless test workflows of every game the PR touches and fails if any of them fails.
  Don't turn on auto-merge for a PR whose checks are red, and never skip, disable or weaken a test or the gate
  to get green.
- If a check fails after auto-merge is on, fix it with a new push (auto-merge stays on) or turn auto-merge off.
- This allows merging your own PRs only. A PR that Guillaume said to hold, or someone else's PR, still waits
  for Guillaume's go-ahead.

## Showing a preview of the result

Rule from Guillaume, 2026-11-16.

Whenever a change has a result that can be seen or tried, show a preview of it when you report the work. Don't
make Guillaume open the branch to find out what changed.

- **Visual changes** (graphics, UI, layout, effects): include screenshots, and before/after images side by side
  when the change alters something that already existed. Capture them from the real game (for example the web
  build in headless Chromium), not mock-ups.
- **Pull requests that touch a game**: link the PR's web preview (`https://guillaumefont.github.io/games/<game>/pr/<n>/`)
  and its APK (`.../<game>/pr/<n>/<apk name>`), with the build number (version code) of each game's APK.
  The preview comment the build workflow posts on the PR has the exact links once the build is done.
- **Behaviour you can't capture in a still image** (motion, timing, controls): a short GIF or video when
  practical, otherwise say exactly where in the preview to look.
- If no preview applies (docs, CI or tooling changes with nothing to see), say so in one line instead.
