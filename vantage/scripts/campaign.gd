class_name Campaign
extends RefCounted
## The campaign: worlds of three levels each, played in order. Clearing a level opens the next
## one; the last level of a world opens the next world. Each world has its own terrain theme
## (`Models.THEMES`), its own mix of foes, and gets tougher (foe hull, bullet speed) and richer
## (scrap) than the last.
##
## Every level plays the same way (Guillaume, 2026-11-23: "mid bosses and final fortresses for
## every level"): waves, a mid-boss (top-down), more waves, then a fortress chased in third
## person, which ends the level. The first level of a world is the shortest, the third the
## longest; each level has its own mid-boss (`midboss_of`), never the same twice in a world.
## Glass Coast's third level is the hand-made sector (`Rules.STAGE`); the other levels are
## built from their world's mix by `waves()`, the same every time (seeded by the level).

const PER_WORLD := 3
## Seconds of waves before the mid-boss and after it, by level in the world.
const LENGTHS := [[12.0, 10.0], [15.0, 14.0], [17.0, 17.0]]
## The mid-bosses' hull (hp of their parts), by level in the world: the first is a little quicker.
const BOSS_HP := [0.75, 0.9, 1.0]
## The order the mid-bosses come in (`Rules.MIDBOSSES`): level k of world w gets (w + k)th, so a
## world's three levels have three different ones and each world starts on a new one.
const MIDBOSS_ORDER := ["mantis", "halo", "bastion", "twin", "hammer"]
## The fortresses' order (`Rules.FORTRESSES`): level k of world w gets the (w + 2k)th, so a world's
## three levels end on three different fortresses, and no two levels have the same pair of bosses.
const FORTRESS_ORDER := ["talon", "wyvern", "zephyr", "leviathan", "goliath"]

## name, terrain theme, the foes' hull and bullet speed and the scrap they drop (multipliers),
## how many seconds between waves, the mix of waves (weights), the bosses' tint, and the names
## of its three levels.
const WORLDS := [
	{"name": "Glass Coast", "theme": "coast", "tough": 1.0, "fire": 1.0, "scrap": 1.0, "beat": 2.7,
		"mix": {"dart": 4, "sweep": 2, "back": 1, "swing": 3, "turret": 2, "heavy": 1},
		"tint": Color(1, 1, 1), "levels": ["Landfall", "Tide Line", "Fortress Run"]},
	{"name": "Ember Dunes", "theme": "dunes", "tough": 1.3, "fire": 1.07, "scrap": 1.4, "beat": 2.5,
		"mix": {"dart": 2, "sweep": 2, "back": 1, "swing": 2, "turret": 4, "heavy": 2},
		"tint": Color(1.0, 0.86, 0.66), "levels": ["Dry Wash", "Mesa Gate", "Sandstorm Run"]},
	{"name": "Iron Sprawl", "theme": "city", "tough": 1.65, "fire": 1.14, "scrap": 1.9, "beat": 2.3,
		"mix": {"dart": 3, "sweep": 3, "back": 2, "swing": 3, "turret": 4, "heavy": 2},
		"tint": Color(0.8, 0.86, 1.0), "levels": ["Outskirts", "Canal Line", "Spire Run"]},
	{"name": "Frost Shelf", "theme": "ice", "tough": 2.0, "fire": 1.2, "scrap": 2.5, "beat": 2.15,
		"mix": {"dart": 3, "sweep": 4, "back": 3, "swing": 4, "turret": 2, "heavy": 2},
		"tint": Color(0.82, 0.95, 1.05), "levels": ["Pack Ice", "Glacier Pass", "Whiteout Run"]},
	{"name": "Cinder Reach", "theme": "volcano", "tough": 2.4, "fire": 1.26, "scrap": 3.2, "beat": 2.0,
		"mix": {"dart": 3, "sweep": 3, "back": 3, "swing": 3, "turret": 4, "heavy": 3},
		"tint": Color(1.05, 0.72, 0.62), "levels": ["Ash Fields", "Lava Gate", "Last Run"]},
]


static func count() -> int:
	return WORLDS.size() * PER_WORLD


static func world_of(lv: int) -> Dictionary:
	return WORLDS[clampi(lv, 0, count() - 1) / PER_WORLD]


## The level's mid-boss id (a key of `Rules.MIDBOSSES`).
static func midboss_of(lv: int) -> String:
	return MIDBOSS_ORDER[(lv / PER_WORLD + lv % PER_WORLD) % MIDBOSS_ORDER.size()]


static func midboss(lv: int) -> Dictionary:
	return Rules.MIDBOSSES[midboss_of(lv)]


## The level's fortress id (a key of `Rules.FORTRESSES`).
static func fortress_of(lv: int) -> String:
	return FORTRESS_ORDER[(lv / PER_WORLD + 2 * (lv % PER_WORLD)) % FORTRESS_ORDER.size()]


static func fortress(lv: int) -> Dictionary:
	return Rules.FORTRESSES[fortress_of(lv)]


## "2-3" for the third level of the second world.
static func code(lv: int) -> String:
	return "%d-%d" % [lv / PER_WORLD + 1, lv % PER_WORLD + 1]


static func level_name(lv: int) -> String:
	return world_of(lv).levels[lv % PER_WORLD]


# ---------------------------------------------------------------- progress (in the save)

## The save's campaign fields: the selected level, the furthest level open, best grades.
static func fresh_into(s: Dictionary) -> void:
	s["sel"] = 0
	s["open"] = 0
	s["grades"] = {}


static func migrate_into(s: Dictionary, d: Dictionary) -> void:
	if d.has("open"):
		s.open = clampi(int(d.open), 0, count() - 1)
	elif int(d.get("clears", 0)) > 0:
		# a pilot from before the campaign cleared the old sector, Glass Coast's fortress run
		s.open = PER_WORLD
	s.sel = clampi(int(d.get("sel", s.open)), 0, s.open)
	if typeof(d.get("grades")) == TYPE_DICTIONARY:
		for k: String in d.grades:
			if str(d.grades[k]) in ["S", "A", "B", "C"]:
				s.grades[k] = str(d.grades[k])


static func is_open(s: Dictionary, lv: int) -> bool:
	return lv >= 0 and lv <= int(s.open)


## A level cleared with a grade: keeps the best grade, opens the next level and selects it.
## Returns true when that opened a level that wasn't open before.
static func cleared(s: Dictionary, lv: int, grade: String) -> bool:
	var k := code(lv)
	var order := ["S", "A", "B", "C"]
	if not s.grades.has(k) or order.find(grade) < order.find(s.grades[k]):
		s.grades[k] = grade
	var nxt := mini(lv + 1, count() - 1)
	var opened: bool = nxt > int(s.open)
	s.open = maxi(int(s.open), nxt)
	if lv + 1 < count():
		s.sel = lv + 1
	return opened


# ---------------------------------------------------------------- the waves of a level

## The waves of a level, by stage time, in the shape of `Rules.STAGE`: waves, the mid-boss,
## waves, the fortress.
static func waves(lv: int) -> Array:
	if lv == PER_WORLD - 1:
		return Rules.STAGE
	var w: Dictionary = world_of(lv)
	var span: Array = LENGTHS[lv % PER_WORLD]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("vantage level %d" % lv)
	var out: Array = []
	var mix := mix_of(lv)
	# the level's new kind opens it, so it is met (and announced) straight away
	var t := beats(out, rng, w, {debut(lv): 1}, 1.5, 1.6)
	t = beats(out, rng, w, mix, t, float(span[0]), debut(lv))
	out.append({"t": t + 2.5, "kind": "boss", "n": 1, "x": 0.0, "gap": 0.0})
	# after the mid-boss, the kind met in the level before comes back first
	t = beats(out, rng, w, {debut(lv - 1): 1}, t + 4.0, t + 4.1) if lv > 0 else t + 4.0
	t = beats(out, rng, w, mix, t, t + float(span[1]), debut(lv - 1) if lv > 0 else "")
	out.append({"t": t + 3.5, "kind": "fortress", "n": 1, "x": 0.0, "gap": 0.0})
	return out


## The kind of foe level lv brings in (`Foes.INTRO`).
static func debut(lv: int) -> String:
	return Foes.INTRO[clampi(lv, 0, Foes.INTRO.size() - 1)]


## The waves a level draws from (weights): its world's first foes (`mix`), and every kind met so
## far (Guillaume: "staggered types"): the level's new one the most, then its world's earlier ones,
## then those of earlier worlds, a little each.
static func mix_of(lv: int) -> Dictionary:
	var mix: Dictionary = world_of(lv).mix.duplicate()
	# gun towers come in several types now (`Towers`): more of them
	mix["turret"] = int(mix.get("turret", 0)) + 3
	var w := lv / PER_WORLD
	for k in range(lv + 1):
		var kind: String = Foes.INTRO[k]
		mix[kind] = 5 if k == lv else (4 if k / PER_WORLD == w else 2)
	return mix


## Fills `out` with waves from `mix` from time `t` to `until`; returns the time after. `last` is
## the kind of the wave before (never two of a kind in a row).
static func beats(out: Array, rng: RandomNumberGenerator, w: Dictionary, mix: Dictionary, t: float, until: float,
		last := "") -> float:
	var total := 0
	for k: String in mix:
		total += int(mix[k])
	var heavies := 0
	var towers := rng.randi_range(0, 3)
	while t < until:
		var pick := ""
		for tries in 4:
			var r := rng.randi_range(1, total)
			for k: String in mix:
				r -= int(mix[k])
				if r <= 0:
					pick = k
					break
			# no two of the same in a row, and no more than three heavies a level
			if (pick != last or mix.size() == 1) and not (pick == "heavy" and heavies > 2):
				break
		if pick == "heavy":
			heavies += 1
		last = pick
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var wave := {"t": snappedf(t, 0.5), "gap": 0.0}
		match pick:
			"dart":
				wave.merge({"kind": "dart", "n": rng.randi_range(5, 6), "x": snappedf(rng.randf_range(-4.0, 4.0), 0.5), "gap": 0.32})
			"sweep":
				wave.merge({"kind": "dart", "n": rng.randi_range(6, 8), "x": snappedf(rng.randf_range(-1.0, 2.5), 0.5), "gap": 0.27,
					"from": "left" if side < 0 else "right"})
			"back":
				wave.merge({"kind": "dart", "n": 6, "x": side * rng.randf_range(4.5, 5.5), "gap": 0.3, "from": "back"})
			"swing":
				wave.merge({"kind": "swing", "n": 6, "x": snappedf(rng.randf_range(-2.5, 2.5), 0.5), "gap": 0.37})
			"turret":
				var n := rng.randi_range(1, 3)
				# one of the gun towers the world fields (`Towers.BY_WORLD`)
				var types: Array = Towers.BY_WORLD[maxi(0, WORLDS.find(w))]
				var kind: String = types[towers % types.size()]   # in turn, so a level shows several
				towers += 1
				wave.merge({"kind": kind, "n": n, "x": 0.0 if n == 3 else side * rng.randf_range(2.0, 3.5)})
			"heavy":
				wave.merge({"kind": "heavy", "n": 1, "x": snappedf(rng.randf_range(-2.5, 2.5), 0.5)})
			_:
				wave.merge(new_wave(pick, rng, side))
		out.append(wave)
		t += float(w.beat) * rng.randf_range(0.85, 1.15) + (1.2 if pick in ["heavy", "gunship", "prism"] else 0.0)
	return t


## Count of foes in a level that can be shot down (for the results' kill rate).
static func foes_in(lv: int) -> int:
	var n := 0
	for w: Dictionary in waves(lv):
		if w.kind == "boss":
			n += Rules.boss_parts(midboss_of(lv))
		elif w.kind == "fortress":
			n += Rules.fortress_parts(fortress_of(lv))
		elif w.kind != "end":
			n += int(w.n)
	return n


## A wave of one of the campaign's own foes (`Foes`): how many, where, how far apart.
static func new_wave(kind: String, rng: RandomNumberGenerator, side: float) -> Dictionary:
	var x := snappedf(rng.randf_range(-3.0, 3.0), 0.5)
	match kind:
		"gull":
			return {"kind": kind, "n": 4, "x": x, "gap": 0.45}
		"rotor":
			return {"kind": kind, "n": rng.randi_range(2, 3), "x": 0.0, "gap": 0.5}
		"pillbox", "aa", "mortar":
			var n := rng.randi_range(1, 2)
			return {"kind": kind, "n": n, "x": side * rng.randf_range(1.5, 3.5) if n == 1 else snappedf(side * 1.0, 0.5), "gap": 0.0}
		"scarab", "lancer":
			return {"kind": kind, "n": rng.randi_range(2, 3), "x": snappedf(x * 0.5, 0.5), "gap": 0.6}
		"tank":
			return {"kind": kind, "n": 2, "x": side, "gap": 0.0, "from": "left" if side < 0 else "right"}
		"borer":
			return {"kind": kind, "n": rng.randi_range(1, 2), "x": x * 0.6, "gap": 0.0}
		"seeker":
			return {"kind": kind, "n": rng.randi_range(5, 6), "x": x, "gap": 0.28}
		"gunship":
			return {"kind": kind, "n": 1, "x": side, "gap": 0.0, "from": "left" if side < 0 else "right"}
		"hover":
			return {"kind": kind, "n": 2, "x": -side * 1.5, "gap": 0.0}
		"prism":
			return {"kind": kind, "n": rng.randi_range(1, 2), "x": x * 0.5, "gap": 1.0}
		"ember":
			return {"kind": kind, "n": rng.randi_range(3, 4), "x": x * 0.5, "gap": 0.5}
		"wyrm":
			return {"kind": kind, "n": 7, "x": snappedf(x * 0.5, 0.5), "gap": 0.2}
	return {"kind": kind, "n": 1, "x": x, "gap": 0.0}
