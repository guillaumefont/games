// Board server test with an in-memory SQLite standing in for D1:
//   node --experimental-sqlite server/test.mjs        (Node 22+)
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { handle } from "./src/index.js";

const sql = new DatabaseSync(":memory:");
sql.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
const stmt = (q, args = []) => ({
  bind: (...a) => stmt(q, a),
  first: async () => sql.prepare(q).get(...args) ?? null,
  run: async () => sql.prepare(q).run(...args),
  all: async () => ({ results: sql.prepare(q).all(...args) }),
});
const DB = { prepare: (q) => stmt(q), batch: async (list) => Promise.all(list.map((s) => s.all())) };
const env = { DB };

const id = (n) => n.toString(16).padStart(32, "0");
const board = encodeURIComponent("3/Lasso");
async function post(player, time, cf) {
  const r = new Request(`https://x/v1/boards/${board}`, { method: "POST", body: JSON.stringify({ player, time }) });
  Object.defineProperty(r, "cf", { value: cf });
  const res = await handle(r, env);
  return [res.status, res.status === 200 ? await res.json() : null];
}
const paris = { continent: "EU", country: "FR", postalCode: "75011" };
const lyon = { continent: "EU", country: "FR", postalCode: "69001" };
const tokyo = { continent: "AS", country: "JP", postalCode: "100-0001" };

let [s, a] = await post(id(1), 12.5, paris);
assert.equal(s, 200);
assert.deepEqual(a.ranks.world, { rank: 1, total: 1 });
await post(id(2), 11.0, tokyo);
await post(id(3), 12.0, lyon);
[s, a] = await post(id(1), 13.0, paris);   // slower: the best stays
assert.equal(a.best, 12.5);
assert.deepEqual(a.ranks.world, { rank: 3, total: 3 });
assert.deepEqual(a.ranks.continent, { rank: 2, total: 2, name: "Europe" });
assert.deepEqual(a.ranks.country, { rank: 2, total: 2, name: "France" });
assert.deepEqual(a.ranks.zip, { rank: 1, total: 1, name: "75011" });
[s, a] = await post(id(1), 10.5, paris);   // faster: first everywhere
assert.deepEqual(a.ranks.world, { rank: 1, total: 3 });

const g = await handle(new Request(`https://x/v1/boards/${board}?player=${id(3)}`), env);
assert.equal(g.status, 200);
assert.deepEqual((await g.json()).ranks.world, { rank: 3, total: 3 });
assert.equal((await handle(new Request(`https://x/v1/boards/${board}?player=${id(9)}`), env)).status, 404);
assert.equal((await post(id(4), 1.0, paris))[0], 400, "too fast to be real");
assert.equal((await post("nope", 12, paris))[0], 400, "bad player id");
assert.equal((await handle(new Request("https://x/v1/boards/" + encodeURIComponent("x/<script>")), env)).status, 400);
const o = await handle(new Request(`https://x/v1/boards/${board}`, { method: "OPTIONS" }), env);
assert.equal(o.headers.get("Access-Control-Allow-Origin"), "*");
console.log("board server test: PASS");
