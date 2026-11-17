class_name Medals
extends RefCounted
## Medals, Guillaume's ask of 2026-11-17: for a fast run, for collecting every star, and for points.
##
## Each Voyage sector (level) has three medals:
## - Speed: bronze, silver or gold by clear time, under the par time and two faster marks
##   (SPEED_FACTORS of par; gold is about the test bot's best line, so it takes a clean run or leaps).
## - Points: bronze, silver or gold by the score of a cleared run, the sector's `points` marks
##   (tools/par_times.gd suggests them from the bot's all-perigee score; gold needs leaps or a big combo).
## - Stars: all three of the sector's stars. One medal, no tiers: 100% is all or nothing.
## Each system has an all-stars medal too (every star of every sector), and Drift has points medals
## by the best single run (DRIFT_POINTS).
##
## Medals are rewards: the first time a tier is won it pays bonus sparks (REWARD_SPARKS, banked on the
## unlock track like collected sparks), and the system all-stars medal also unlocks a cosmetic that
## is only won this way (Unlocks.REWARD_ITEMS). Claimed reward ids go in save.data.rewards, so each
## pays once. Ids: "<sector>:<kind>:<tier>", "<system>:stars", "drift:points:<tier>".
##
## Medals come only from how a run was played (time, score, stars), read from the best records the
## save already keeps (save.data.voyage[id] = {stars, score, time}, save.data.best). Nothing bought can
## ever earn, upgrade or skip one.

const NONE := 0
const BRONZE := 1
const SILVER := 2
const GOLD := 3
const TIER_NAMES: Array[String] = ["None", "Bronze", "Silver", "Gold"]

## Speed marks as fractions of par: bronze at par, silver and gold faster.
const SPEED_FACTORS: Array[float] = [1.0, 0.88, 0.76]
## Drift points medals: the score of one run.
const DRIFT_POINTS: Array[int] = [100, 300, 750]

## Bonus sparks the first time each tier is won (index = tier): winning gold straight away pays all three.
## Balanced against the unlock track (Unlocks.TRACK ends at 420): with 18 levels, every medal of the
## route pays 18 x (6 + 6 + 3) + 3 x 20 = 330 sparks, so medals carry most of the track and the sparks
## collected in runs finish it. (Until 2026-11-17, with 6 levels: 2/3/5, 5 and 25.)
const REWARD_SPARKS: Array[int] = [0, 1, 2, 3]
const ALL_STARS_SPARKS := 3 ## a sector's three stars
const SYSTEM_STARS_SPARKS := 20 ## every star of a system, with its cosmetic


## The three speed marks of a sector in seconds, rounded down to a tenth: [bronze, silver, gold].
static func speed_marks(sec: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for f in SPEED_FACTORS:
		out.append(floorf(float(sec.par) * f * 10.0 + 0.001) / 10.0)
	return out


## The three points marks of a sector: [bronze, silver, gold].
static func points_marks(sec: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for v in sec.get("points", []):
		out.append(int(v))
	return out


## The tier a clear time earns (NONE for no clear).
static func speed_tier(sec: Dictionary, time: float) -> int:
	var tier := NONE
	var marks := speed_marks(sec)
	for i in marks.size():
		if time <= marks[i]:
			tier = i + 1
	return tier


## The tier a cleared run's score earns.
static func points_tier(sec: Dictionary, score: int) -> int:
	return _up_tier(points_marks(sec), score)


static func drift_tier(score: int) -> int:
	return _up_tier(DRIFT_POINTS, score)


static func _up_tier(marks: Array, v: int) -> int:
	var tier := NONE
	for i in marks.size():
		if v >= int(marks[i]):
			tier = i + 1
	return tier


## A sector's best medals from its save record ({stars, score, time}, missing until cleared):
## {"speed": tier, "points": tier, "stars": GOLD or NONE}.
static func of_sector(sec: Dictionary, rec: Dictionary) -> Dictionary:
	if rec.is_empty() or int(rec.get("stars", 0)) <= 0:
		return {"speed": NONE, "points": NONE, "stars": NONE}
	return {
		"speed": speed_tier(sec, float(rec.get("time", INF))),
		"points": points_tier(sec, int(rec.get("score", 0))),
		"stars": GOLD if int(rec.get("stars", 0)) >= 3 else NONE,
	}


## The medals of one cleared run, from its three stars, time and score.
static func of_run(sec: Dictionary, stars: Array, time: float, score: int) -> Dictionary:
	return of_sector(sec, {"stars": stars.count(true), "time": time, "score": score})


## [stars got, stars in the system] for a system's all-stars medal.
static func system_stars(sys: Dictionary, progress: Dictionary) -> Array[int]:
	var got := 0
	for sec in sys.sectors:
		got += int(progress.get(sec.id, {}).get("stars", 0))
	return [got, 3 * sys.sectors.size()]


## Medals won in all of Voyage and Drift, counted by tier: {BRONZE: n, SILVER: n, GOLD: n}.
static func tally(progress: Dictionary, drift_best: int) -> Dictionary:
	var out := {BRONZE: 0, SILVER: 0, GOLD: 0}
	for sys in Voyage.SYSTEMS:
		for sec in sys.sectors:
			var m := of_sector(sec, progress.get(sec.id, {}))
			for kind in m:
				if m[kind] != NONE:
					out[m[kind]] += 1
		var ss := system_stars(sys, progress)
		if ss[0] >= ss[1]:
			out[GOLD] += 1
	var d := drift_tier(drift_best)
	if d != NONE:
		out[d] += 1
	return out


## Every reward earned so far: [{id, sparks, kind, tier, sector}], in route order. A tier pays
## its own step, and the ones below it are earned too.
static func rewards(progress: Dictionary, drift_best: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sys in Voyage.SYSTEMS:
		for sec in sys.sectors:
			var m := of_sector(sec, progress.get(sec.id, {}))
			for kind in ["speed", "points"]:
				for t in range(1, int(m[kind]) + 1):
					out.append({"id": "%s:%s:%d" % [sec.id, kind, t], "sparks": REWARD_SPARKS[t], "kind": kind, "tier": t, "sector": sec.id})
			if m.stars != NONE:
				out.append({"id": "%s:stars:3" % sec.id, "sparks": ALL_STARS_SPARKS, "kind": "stars", "tier": GOLD, "sector": sec.id})
		var ss := system_stars(sys, progress)
		if ss[0] >= ss[1]:
			out.append({"id": "%s:stars" % sys.name, "sparks": SYSTEM_STARS_SPARKS, "kind": "system", "tier": GOLD, "sector": ""})
	for t in range(1, drift_tier(drift_best) + 1):
		out.append({"id": "drift:points:%d" % t, "sparks": REWARD_SPARKS[t], "kind": "drift", "tier": t, "sector": ""})
	return out


## The rewards earned but not yet in `claimed`.
static func unclaimed(progress: Dictionary, drift_best: int, claimed: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rewards(progress, drift_best):
		if not claimed.has(r.id):
			out.append(r)
	return out


## Bonus sparks a sector's next tier of `kind` pays, for "Gold at 165 · +5 sparks".
static func next_reward_sparks(tier: int) -> int:
	return REWARD_SPARKS[mini(tier + 1, GOLD)]


## What the next speed tier needs, for the clear card: "Silver under 20.2 s", or "" at gold.
static func next_speed_text(sec: Dictionary, tier: int) -> String:
	if tier >= GOLD:
		return ""
	return "%s under %.1f s · +%d" % [TIER_NAMES[tier + 1], speed_marks(sec)[tier], next_reward_sparks(tier)]


## What the next points tier needs: "Gold at 90", or "" at gold.
static func next_points_text(marks: Array, tier: int) -> String:
	if tier >= GOLD:
		return ""
	return "%s at %d · +%d" % [TIER_NAMES[tier + 1], int(marks[tier]), next_reward_sparks(tier)]
