# Special Stages boards

The world ranking behind Special Stages: a Cloudflare Worker with a D1 (SQLite) database, both on
Cloudflare's free tier. The game sends a player's best lap on a stage and gets back their rank in
the world, their continent, their country and their zip code. The game shows the world rank, and
a narrower one only once enough players share that region (`OPEN_AT` in `scripts/ranking.gd`), so
the ranking gets more local by itself as players come in.

No account or name: a player is a random id made on the device (`Ranking.player_id()`). Their
region is read from their connection by Cloudflare (`request.cf`: continent, country, postal
code) at each post; the game never sends a location.

## Deploy (once)

```
cd tether-rally/server
npx wrangler login
npx wrangler d1 create tether-boards          # paste the database_id it prints into wrangler.toml
npx wrangler d1 execute tether-boards --remote --file=schema.sql
npx wrangler deploy                            # prints https://tether-boards.<account>.workers.dev
```

Then set `URL` in `scripts/ranking.gd` to that address (no trailing slash). Until it is set, the
game sends nothing and ranks read "offline".

## Test

```
node --experimental-sqlite server/test.mjs     # Node 22+, an in-memory SQLite stands in for D1
```

## API

- `POST /v1/boards/<board>` with `{"player": "<32 hex>", "time": 12.345}`: keeps the best time.
- `GET /v1/boards/<board>?player=<32 hex>`: the player's ranks now (404 without a time).
- Both answer `{"best": 12.345, "ranks": {"world": {"rank", "total"}, "continent": {"rank",
  "total", "name"}, "country": {...}, "zip": {...}}}`.

`<board>` is `<layout version>/<track name>` URL-encoded, so bumping `Records.LAYOUT_VERSION`
starts fresh boards. Times under 3 s or over 900 s are refused; there is no other cheat check yet.
