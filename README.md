# games

Monorepo for Guillaume's games. Each game was imported from its original repository with its full `main` history.

| Folder | Original repository |
| --- | --- |
| [`tether-rally/`](tether-rally/) | [guillaumefont/tether-rally](https://github.com/guillaumefont/tether-rally) |
| [`star-breaker/`](star-breaker/) | [guillaumefont/star-breaker](https://github.com/guillaumefont/star-breaker) |
| [`aurite-front/`](aurite-front/) | [guillaumefont/aurite-front](https://github.com/guillaumefont/aurite-front) |

Use `git log -- <folder>` to see a game's history.

Note: each game's GitHub Actions workflows still live under `<game>/.github/workflows/` and do not run from there. They need to be moved to the root `.github/workflows/` with paths adjusted.
