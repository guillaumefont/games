class_name Leaderboards
extends RefCounted
## Drift's leaderboards (Guillaume, 2026-11-21): two boards of the best single runs.
## - Farthest: moons reached in one run (moons skipped by a leap count, as they do for the score).
## - Top score: points in one run.
## Every entry also carries the run's speed stars (Sim.rush_stars, laps under par) as a badge, with its
## perigees and leaps, so a board shows how a run was flown, not just how far.
##
## Local boards first: this class keeps them in the save (save.data.boards, one list per board, best
## first, SIZE entries each). Online boards come later: a subclass that overrides submit() and top()
## to talk to a server can replace this one without the HUD or main.gd changing, since they only use
## entry_of(), submit() and top(). Entries only come from how a run was played: nothing bought may
## ever add, change or lift one.

const BOARDS: Array[String] = ["farthest", "score"]
const NAMES := {"farthest": "Farthest", "score": "Top score"}
const SIZE := 10

## The save's boards dictionary ({board: [entry, ...]}), changed in place.
var data: Dictionary


func _init(boards: Dictionary) -> void:
	data = boards
	for b in BOARDS:
		if data.get(b) is not Array:
			data[b] = []


## A board entry for a finished Drift run. `when` is a Unix time (0: now).
static func entry_of(sim: Sim, when := 0) -> Dictionary:
	return {
		"moons": sim.hops,
		"score": sim.score,
		"stars": sim.rush_stars,
		"perigees": sim.perigees,
		"leaps": sim.leaps,
		"time": snappedf(sim.run_t, 0.1),
		"date": when if when > 0 else int(Time.get_unix_time_from_system()),
	}


## True when entry `a` ranks above `b` on `board`. Ties go to the other number, then to the older run
## (whoever got there first keeps the place).
static func better(board: String, a: Dictionary, b: Dictionary) -> bool:
	var main := "moons" if board == "farthest" else "score"
	var other := "score" if board == "farthest" else "moons"
	if int(a[main]) != int(b[main]):
		return int(a[main]) > int(b[main])
	if int(a[other]) != int(b[other]):
		return int(a[other]) > int(b[other])
	return int(a.get("date", 0)) < int(b.get("date", 0))


## Adds a run to every board it makes; returns {board: rank} (1 = top, 0 = not on that board).
## A run that reached no moon is never entered.
func submit(entry: Dictionary) -> Dictionary:
	var ranks := {}
	for b in BOARDS:
		ranks[b] = 0
		if int(entry.moons) <= 0:
			continue
		var list: Array = data[b]
		var at := list.size()
		for i in list.size():
			if better(b, entry, list[i]):
				at = i
				break
		if at >= SIZE:
			continue
		list.insert(at, entry.duplicate())
		if list.size() > SIZE:
			list.resize(SIZE)
		ranks[b] = at + 1
	return ranks


## The entries of `board`, best first (numbers as ints, whatever JSON did to them).
func top(board: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in data.get(board, []):
		if e is Dictionary:
			out.append({
				"moons": int(e.get("moons", 0)), "score": int(e.get("score", 0)), "stars": int(e.get("stars", 0)),
				"perigees": int(e.get("perigees", 0)), "leaps": int(e.get("leaps", 0)),
				"time": float(e.get("time", 0.0)), "date": int(e.get("date", 0)),
			})
	return out


## "New #1 Farthest · #3 Top score" for the boards a run made ("" when none).
static func ranks_text(ranks: Dictionary) -> String:
	var parts: Array[String] = []
	for b in BOARDS:
		var r := int(ranks.get(b, 0))
		if r > 0:
			parts.append("#%d %s" % [r, NAMES[b]])
	return ("New " + " · ".join(parts)) if not parts.is_empty() else ""
