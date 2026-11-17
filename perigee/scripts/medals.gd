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


## What the next speed tier needs, for the clear card: "Silver under 20.2 s", or "" at gold.
static func next_speed_text(sec: Dictionary, tier: int) -> String:
	if tier >= GOLD:
		return ""
	return "%s under %.1f s" % [TIER_NAMES[tier + 1], speed_marks(sec)[tier]]


## What the next points tier needs: "Gold at 90", or "" at gold.
static func next_points_text(marks: Array, tier: int) -> String:
	if tier >= GOLD:
		return ""
	return "%s at %d" % [TIER_NAMES[tier + 1], int(marks[tier])]
