# games

Monorepo for Guillaume's games. The first three games were imported from their original repositories with their full `main` history.

| Folder | Original repository |
| --- | --- |
| [`tether-rally/`](tether-rally/) | [guillaumefont/tether-rally](https://github.com/guillaumefont/tether-rally) |
| [`star-breaker/`](star-breaker/) | [guillaumefont/star-breaker](https://github.com/guillaumefont/star-breaker) |
| [`aurite-front/`](aurite-front/) | [guillaumefont/aurite-front](https://github.com/guillaumefont/aurite-front) |
| [`perigee/`](perigee/) | None: started here (2026-11-16) |

Use `git log -- <folder>` to see a game's history.

## Play

All the games are published on one GitHub Pages site: https://guillaumefont.github.io/games/

| Game | Main build | Pull request N |
| --- | --- | --- |
| Tether Rally | [`/games/tether-rally/`](https://guillaumefont.github.io/games/tether-rally/) | `/games/tether-rally/pr/N/` |
| Star Breaker | [`/games/star-breaker/`](https://guillaumefont.github.io/games/star-breaker/) | `/games/star-breaker/pr/N/` |
| Aurite Front | [`/games/aurite-front/`](https://guillaumefont.github.io/games/aurite-front/) | `/games/aurite-front/pr/N/` |
| Perigee | [`/games/perigee/`](https://guillaumefont.github.io/games/perigee/) | `/games/perigee/pr/N/` |

## CI

Each game has its own workflows in `.github/workflows/`, named after its folder, and they only run when a
change touches that game's folder (or its workflows):

- `<game>-build.yml` exports Web and/or Android, publishes the build to its folder on the `gh-pages` branch,
  and comments a preview link on pull requests (removed when the PR closes).
- `tether-rally-sim.yml`, `star-breaker-test.yml`, `aurite-front-sim.yml`, `perigee-test.yml` run the headless tests.
- `ci-gate.yml` (check **CI gate**) waits for the workflows a PR triggers and passes only if all of them pass.
  It is the one required check on `main`.
- `pages.yml` deploys the whole `gh-pages` branch, plus the site's root pages from `.github/pages/`
  (the list of games and the shared 404 page). It needs Settings > Pages > Source = "GitHub Actions".

Build numbers start at 1001, so APKs from here install over the ones built in the old repositories.
