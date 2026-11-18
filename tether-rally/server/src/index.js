// Tether Rally Special Stages boards (Cloudflare Worker + D1).
//
//   POST /v1/boards/<board>   {"player": "<32 hex>", "time": 12.345}
//        keeps the player's best time on that board and answers with their ranks
//   GET  /v1/boards/<board>?player=<32 hex>
//        the player's ranks now (others may have passed them); 404 if they have no time
//
// <board> is "<layout version>/<track name>", URL-encoded (the game's Ranking.board()).
// Answer: {"best": 12.345, "ranks": {"world": {"rank", "total"},
//          "continent"|"country"|"zip": {"rank", "total", "name"}}}
// The player's region comes from their connection (request.cf), never from the game. Narrower
// boards are always answered; the game decides when one has enough players to show
// (Ranking.OPEN_AT in scripts/ranking.gd).

const CONTINENTS = {
  AF: "Africa", AN: "Antarctica", AS: "Asia", EU: "Europe",
  NA: "North America", OC: "Oceania", SA: "South America",
};
const MIN_TIME = 3;     // s: no lap on any stage is this short
const MAX_TIME = 900;   // s
const BOARD_RE = /^\d{1,4}\/[\p{L}\p{N} '.\-]{1,40}$/u;
const PLAYER_RE = /^[0-9a-f]{32}$/;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...CORS },
  });
}

export function regionOf(cf) {
  const c = cf || {};
  return {
    continent: String(c.continent || "").toUpperCase().slice(0, 2),
    country: String(c.country || "").toUpperCase().slice(0, 2),
    zip: String(c.postalCode || "").slice(0, 12),
  };
}

export function countryName(code) {
  if (!code) return "";
  try {
    return new Intl.DisplayNames(["en"], { type: "region" }).of(code) || code;
  } catch {
    return code;
  }
}

// the player's rank in each scope, from their stored row
export async function ranksFor(db, board, row) {
  const scopes = [
    ["world", "", []],
    ["continent", " AND continent = ?", [row.continent]],
    ["country", " AND country = ?", [row.country]],
    ["zip", " AND country = ? AND zip = ?", [row.country, row.zip]],
  ].filter(([s]) => s === "world" || (s === "continent" ? row.continent : s === "country" ? row.country : row.country && row.zip));
  const stmts = [];
  for (const [, where, args] of scopes) {
    stmts.push(db.prepare(`SELECT COUNT(*) AS n FROM times WHERE board = ?${where} AND time < ?`).bind(board, ...args, row.time));
    stmts.push(db.prepare(`SELECT COUNT(*) AS n FROM times WHERE board = ?${where}`).bind(board, ...args));
  }
  const res = await db.batch(stmts);
  const ranks = {};
  scopes.forEach(([s], i) => {
    const r = { rank: res[2 * i].results[0].n + 1, total: res[2 * i + 1].results[0].n };
    if (s === "continent") r.name = CONTINENTS[row.continent] || row.continent;
    if (s === "country") r.name = countryName(row.country);
    if (s === "zip") r.name = row.zip;
    ranks[s] = r;
  });
  return { best: row.time, ranks };
}

async function getRow(db, board, player) {
  return db.prepare("SELECT time, continent, country, zip FROM times WHERE board = ? AND player = ?").bind(board, player).first();
}

export async function handle(request, env) {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  const url = new URL(request.url);
  const m = url.pathname.match(/^\/v1\/boards\/([^/]+)$/);
  if (!m) return json({ error: "not found" }, 404);
  let board;
  try {
    board = decodeURIComponent(m[1]);
  } catch {
    return json({ error: "bad board" }, 400);
  }
  if (!BOARD_RE.test(board)) return json({ error: "bad board" }, 400);
  const db = env.DB;

  if (request.method === "GET") {
    const player = url.searchParams.get("player") || "";
    if (!PLAYER_RE.test(player)) return json({ error: "bad player" }, 400);
    const row = await getRow(db, board, player);
    if (!row) return json({ error: "no time" }, 404);
    return json(await ranksFor(db, board, row));
  }

  if (request.method === "POST") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "bad json" }, 400);
    }
    const player = String(body?.player || "");
    const time = Number(body?.time);
    if (!PLAYER_RE.test(player)) return json({ error: "bad player" }, 400);
    if (!Number.isFinite(time) || time < MIN_TIME || time > MAX_TIME) return json({ error: "bad time" }, 400);
    const reg = regionOf(request.cf);
    await db.prepare(
      `INSERT INTO times (board, player, time, continent, country, zip, at) VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (board, player) DO UPDATE SET
         time = MIN(times.time, excluded.time),
         continent = excluded.continent, country = excluded.country, zip = excluded.zip,
         at = CASE WHEN excluded.time < times.time THEN excluded.at ELSE times.at END`
    ).bind(board, player, Math.round(time * 1000) / 1000, reg.continent, reg.country, reg.zip, Date.now()).run();
    const row = await getRow(db, board, player);
    return json(await ranksFor(db, board, row));
  }

  return json({ error: "method" }, 405);
}

export default { fetch: (request, env) => handle(request, env) };
