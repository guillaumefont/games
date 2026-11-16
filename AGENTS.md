# Notes for agents

Each game folder has its own `AGENTS.md` with game-specific notes. The rules below apply to every game.

## Merging pull requests

Rule from Guillaume, 2026-11-15. It replaces the older per-game merge rules.

- Agents may merge their own PRs into `main`, but **only through GitHub auto-merge** (squash). Never merge a
  PR directly and never bypass the `main` ruleset. GitHub then merges the PR itself once every required check
  is green. (A real merge queue needs an organization-owned repo, and this repo belongs to a personal account.)
- **All checks must be green.** The required check is **CI gate** (`.github/workflows/ci-gate.yml`), which
  waits for the build and headless test workflows of every game the PR touches and fails if any of them fails.
  Don't turn on auto-merge for a PR whose checks are red, and never skip, disable or weaken a test or the gate
  to get green.
- If a check fails after auto-merge is on, fix it with a new push (auto-merge stays on) or turn auto-merge off.
- This allows merging your own PRs only. A PR that Guillaume said to hold, or someone else's PR, still waits
  for Guillaume's go-ahead.
