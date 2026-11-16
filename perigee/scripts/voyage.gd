class_name Voyage
extends RefCounted
## Voyage: a route of star systems, each a row of short sectors with a fixed layout (a seed and a
## recipe, see Sim.recipe), ending at a waypoint moon. Each system brings in one new kind of moon.
## Up to 3 stars per sector: clear it, beat the par time, and the sector's goal.
##
## Par times come from tools/par_times.gd (the test bot's best time plus 35%) until real play
## sets them. tests/voyage_test.gd checks that the bot clears every sector and that the data is sound.

const SYSTEMS: Array[Dictionary] = [
	{
		"name": "Cradle",
		"intro": "Twin moons: catch either one",
		"sectors": [
			{"id": "1-1", "seed": 1101, "moons": 10, "k_offset": 0, "zigzag": [3],
				"goal": {"type": "perigees", "count": 4}, "par": 20.0},
			{"id": "1-2", "seed": 1202, "moons": 12, "k_offset": 3, "mix": {"moon": 3.0, "twin": 1.0}, "zigzag": [6],
				"goal": {"type": "sparks", "count": 6}, "par": 23.0},
			{"id": "1-3", "seed": 1304, "moons": 12, "k_offset": 6, "mix": {"moon": 2.0, "twin": 1.0}, "zigzag": [2, 7],
				"goal": {"type": "perigees", "count": 6}, "par": 28.0},
			{"id": "1-4", "seed": 1404, "moons": 12, "k_offset": 6, "zigzag": [1, 4, 7],
				"goal": {"type": "leaps", "count": 2}, "par": 24.0},
			{"id": "1-5", "seed": 1505, "moons": 14, "k_offset": 10, "mix": {"moon": 1.0, "twin": 1.0}, "zigzag": [5],
				"goal": {"type": "combo", "count": 8}, "par": 31.0},
			{"id": "1-6", "seed": 1608, "moons": 15, "k_offset": 14, "mix": {"moon": 2.0, "twin": 1.0}, "zigzag": [4, 10],
				"goal": {"type": "perigees", "count": 8}, "par": 35.0},
		],
	},
]


static func all_sectors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sys in SYSTEMS:
		for sec in sys.sectors:
			out.append(sec)
	return out


static func sector(id: String) -> Dictionary:
	for sec in all_sectors():
		if sec.id == id:
			return sec
	return {}


## The sector after `id`, or {} at the end of the route.
static func next_sector(id: String) -> Dictionary:
	var all := all_sectors()
	for i in all.size() - 1:
		if all[i].id == id:
			return all[i + 1]
	return {}


static func system_of(id: String) -> Dictionary:
	for sys in SYSTEMS:
		for sec in sys.sectors:
			if sec.id == id:
				return sys
	return {}


## The recipe Sim builds the sector from.
static func recipe(sec: Dictionary) -> Dictionary:
	var r := {"moons": sec.moons, "k_offset": sec.get("k_offset", 0), "zigzag": sec.get("zigzag", [])}
	if sec.has("mix"):
		r["mix"] = sec.mix
	return r


## "Reach moon 10", "4 perigees", ... for the sector card and the star list.
static func goal_text(goal: Dictionary) -> String:
	var n: int = goal.count
	match goal.type:
		"perigees":
			return "%d perigees" % n
		"sparks":
			return "%d sparks" % n
		"leaps":
			return "%d %s" % [n, "leap" if n == 1 else "leaps"]
		"combo":
			return "Combo %d" % n
	return ""


static func goal_met(goal: Dictionary, s: Sim) -> bool:
	var n: int = goal.count
	match goal.type:
		"perigees":
			return s.perigees >= n
		"sparks":
			return s.sparks_got >= n
		"leaps":
			return s.leaps >= n
		"combo":
			return s.best_combo >= n
	return false


## The three stars of a cleared run: [cleared, under par, goal met].
static func stars(sec: Dictionary, s: Sim) -> Array[bool]:
	var cleared := s.state == "clear"
	return [cleared, cleared and s.run_t <= float(sec.par), cleared and goal_met(sec.goal, s)]


## A sector is open once the one before it has been cleared.
static func unlocked(id: String, progress: Dictionary) -> bool:
	var all := all_sectors()
	for i in all.size():
		if all[i].id == id:
			return i == 0 or int(progress.get(all[i - 1].id, {}).get("stars", 0)) > 0
	return false
