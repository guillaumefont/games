class_name Voyage
extends RefCounted
## Voyage: a route of star systems, each a row of short sectors (levels) with a fixed layout (a seed
## and a recipe, see Sim.recipe), ending at a waypoint moon. Each system brings in one new kind of moon:
## Cradle twins, Backwash retro moons, Lantern pulsars. The map (scripts/voyage_map.gd) numbers the
## levels 1, 2, 3... along the whole route (level_number).
## Up to 3 stars per sector: clear it, beat the par time, and the sector's goal.
##
## Par times come from tools/par_times.gd (the test bot's best time plus 35%) until real play
## sets them. `points` are the sector's bronze, silver and gold points medals (see Medals), from the
## same tool. tests/voyage_test.gd checks that the bot clears every sector and that the data is sound.

const SYSTEMS: Array[Dictionary] = [
	{
		"name": "Cradle",
		"intro": "Twin moons: catch either one",
		"sectors": [
			{"id": "1-1", "seed": 1101, "moons": 10, "k_offset": 0, "zigzag": [3],
				"goal": {"type": "perigees", "count": 4}, "par": 20.0, "points": [35, 60, 90]},
			{"id": "1-2", "seed": 1202, "moons": 12, "k_offset": 3, "mix": {"moon": 3.0, "twin": 1.0}, "zigzag": [6],
				"goal": {"type": "sparks", "count": 6}, "par": 23.0, "points": [40, 80, 115]},
			{"id": "1-3", "seed": 1304, "moons": 12, "k_offset": 6, "mix": {"moon": 2.0, "twin": 1.0}, "zigzag": [2, 7],
				"goal": {"type": "perigees", "count": 6}, "par": 28.0, "points": [35, 70, 100]},
			{"id": "1-4", "seed": 1404, "moons": 12, "k_offset": 6, "zigzag": [1, 4, 7],
				"goal": {"type": "leaps", "count": 2}, "par": 24.0, "points": [60, 110, 165]},
			{"id": "1-5", "seed": 1505, "moons": 14, "k_offset": 10, "mix": {"moon": 1.0, "twin": 1.0}, "zigzag": [5],
				"goal": {"type": "combo", "count": 8}, "par": 31.0, "points": [50, 95, 135]},
			{"id": "1-6", "seed": 1608, "moons": 15, "k_offset": 14, "mix": {"moon": 2.0, "twin": 1.0}, "zigzag": [4, 10],
				"goal": {"type": "perigees", "count": 8}, "par": 35.0, "points": [55, 100, 150]},
		],
	},
	{
		"name": "Backwash",
		"intro": "Retro moons: the orbit turns back",
		"sectors": [
			{"id": "2-1", "seed": 2101, "moons": 12, "k_offset": 8, "mix": {"moon": 3.0, "retro": 1.0}, "zigzag": [5],
				"goal": {"type": "perigees", "count": 5}, "par": 25.0, "points": [40, 80, 115]},
			{"id": "2-2", "seed": 2206, "moons": 13, "k_offset": 10, "mix": {"moon": 2.0, "retro": 1.0}, "zigzag": [3, 8],
				"goal": {"type": "leaps", "count": 1}, "par": 26.0, "points": [55, 100, 150]},
			{"id": "2-3", "seed": 2311, "moons": 14, "k_offset": 12, "mix": {"moon": 2.0, "retro": 1.0, "twin": 1.0}, "zigzag": [9],
				"goal": {"type": "sparks", "count": 8}, "par": 28.0, "points": [50, 95, 140]},
			{"id": "2-4", "seed": 2409, "moons": 14, "k_offset": 14, "mix": {"moon": 1.0, "retro": 1.0}, "zigzag": [2, 6, 10],
				"goal": {"type": "leaps", "count": 2}, "par": 30.0, "points": [55, 100, 150]},
			{"id": "2-5", "seed": 2510, "moons": 15, "k_offset": 16, "mix": {"moon": 1.0, "retro": 1.0, "twin": 1.0}, "zigzag": [7],
				"goal": {"type": "combo", "count": 10}, "par": 31.0, "points": [60, 110, 160]},
			{"id": "2-6", "seed": 2611, "moons": 16, "k_offset": 18, "mix": {"moon": 1.0, "retro": 2.0}, "zigzag": [4, 11],
				"goal": {"type": "perigees", "count": 9}, "par": 32.0, "points": [65, 120, 175]},
		],
	},
	{
		"name": "Lantern",
		"intro": "Pulsars: the ring only catches while lit",
		"sectors": [
			{"id": "3-1", "seed": 3130, "moons": 12, "k_offset": 10, "mix": {"moon": 3.0, "pulsar": 1.0}, "zigzag": [6],
				"goal": {"type": "perigees", "count": 5}, "par": 26.0, "points": [55, 100, 145]},
			{"id": "3-2", "seed": 3209, "moons": 13, "k_offset": 12, "mix": {"moon": 2.0, "pulsar": 1.0}, "zigzag": [3, 9],
				"goal": {"type": "sparks", "count": 8}, "par": 24.0, "points": [50, 95, 140]},
			{"id": "3-3", "seed": 3311, "moons": 14, "k_offset": 14, "mix": {"moon": 2.0, "pulsar": 1.0, "retro": 1.0}, "zigzag": [5],
				"goal": {"type": "leaps", "count": 1}, "par": 27.0, "points": [55, 100, 150]},
			{"id": "3-4", "seed": 3438, "moons": 15, "k_offset": 16, "mix": {"moon": 1.0, "pulsar": 1.0, "twin": 1.0}, "zigzag": [2, 7, 11],
				"goal": {"type": "leaps", "count": 2}, "par": 32.0, "points": [65, 120, 175]},
			{"id": "3-5", "seed": 3517, "moons": 16, "k_offset": 18, "mix": {"moon": 1.0, "pulsar": 1.0, "retro": 1.0}, "zigzag": [8],
				"goal": {"type": "combo", "count": 10}, "par": 30.0, "points": [75, 140, 205]},
			{"id": "3-6", "seed": 3620, "moons": 18, "k_offset": 20, "mix": {"moon": 1.0, "pulsar": 1.0, "retro": 1.0, "twin": 1.0}, "zigzag": [4, 10, 14],
				"goal": {"type": "perigees", "count": 10}, "par": 41.0, "points": [75, 140, 205]},
		],
	},
]


static func all_sectors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sys in SYSTEMS:
		for sec in sys.sectors:
			out.append(sec)
	return out


## The level's number on the map, counted along the whole route from 1 (0 for an unknown id).
static func level_number(id: String) -> int:
	var all := all_sectors()
	for i in all.size():
		if all[i].id == id:
			return i + 1
	return 0


## The furthest open level: where the player is on the route.
static func current_id(progress: Dictionary) -> String:
	var out := ""
	for sec in all_sectors():
		if unlocked(sec.id, progress):
			out = sec.id
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
