class_name VStage
extends RefCounted
## Stages of the portrait game: six worlds of eight stages, generated from seeds.
## A stage is a list of events placed at a distance `d` along the scroll (stage units, the
## screen is 126 wide and 224 tall). Each stage is open ground with enemy waves, a fortress
## section of barriers, then a mid-boss (stages 1 to 7) or the world's boss (stage 8).
## Seeded, so a stage is always the same.

const W := 126.0
const H := 224.0

## Each world: its flyer groups in the order they appear (a stage of index j draws from the
## first 3 + j / 2 of them), a group borrowed from elsewhere from stage 5 on, the big flyer its
## mid-bosses are made of, and the eight stage names.
const WORLDS := [
	{pool = ["sine", "dive", "turrets", "shell", "snakes", "dive"], late = "wasps", big = "shell",
		names = ["Spore Fields", "Crystal Gate", "Pale Craters", "Glow Marsh", "Spore Wake", "Hollow Rim", "Rift Garden", "Bloom Heart"]},
	{pool = ["shards", "sine", "turrets", "flake", "hulk", "shards"], late = "seekers", big = "hulk",
		names = ["Frost Shelf", "Glass Steppe", "Rime Gate", "Shard Storm", "Icefall", "White Hollow", "Cold Spire", "Prism Vault"]},
	{pool = ["wasps", "sine", "turrets", "nest", "wasps", "dive"], late = "shards", big = "nest",
		names = ["Amber Rows", "Comb Ridge", "Drone Meadow", "Sting Valley", "Honey Deep", "Brood Halls", "Royal Comb", "Queen's Chamber"]},
	{pool = ["drones", "turrets", "shell", "drones", "seekers", "dive"], late = "lancers", big = "sentinel",
		names = ["Slag Yards", "Rivet Line", "Smelter Row", "Gear Pits", "Ash Furnace", "Crucible", "Forge Gate", "Titan Hall"]},
	{pool = ["lancers", "drones", "turrets", "bulwark", "lancers", "sine"], late = "seekers", big = "bulwark",
		names = ["Outer Ring", "Signal Spokes", "Neon Gate", "Hull Breach", "Armour Belt", "Inner Ring", "Command Spine", "Bastion Core"]},
	{pool = ["seekers", "shards", "turrets", "drones", "sentinel", "wasps", "lancers"], late = "nest", big = "sentinel",
		names = ["Corona Fields", "Ember Sea", "Solar Wind", "Flare Gate", "Magma Shelf", "Fusion Deep", "Last Light", "Star Heart"]},
]
## World bosses, by world (the final stage of each world).
const BOSSES := ["bloom", "prism", "queen", "titan", "bastion", "heart"]
## Mid-boss names: [one big flyer, a pair of them].
const BIG_NAMES := {shell = ["Shell Matriarch", "Shell Twins"], hulk = ["Rime Hulk", "Hulk Pair"], nest = ["Brood Nest", "Twin Nests"],
	sentinel = ["Gold Sentinel", "Sentinel Pair"], bulwark = ["Bulwark", "Bulwark Pair"]}
const PER_WORLD := 8
## Rock set pieces: walls slide in from the screen edges for a canyon, then slide out. A canyon
## is [start, end, gap]: the passage `gap` wide wanders from side to side. An island is
## [start, length, x, half-width]: a lozenge of rock in the open that splits the way in two.
## Where the walls rest when there is no canyon: just off screen.
const OFF := -30.0
const EASE := 70.0

## The 48 stages (6 worlds x 8), generated: see `_make()`.
static var STAGES: Array = _make()
static var CANYONS: Array = STAGES.map(func(s): return s.canyons)
static var ISLANDS: Array = STAGES.map(func(s): return s.islands)


static func world_of(i: int) -> int:
	return i / PER_WORLD


static func _make() -> Array:
	var out: Array = []
	for w in WORLDS.size():
		var wd: Dictionary = WORLDS[w]
		for j in PER_WORLD:
			var last := j == PER_WORLD - 1
			var rng := RandomNumberGenerator.new()
			rng.seed = 7919 * (w + 1) + 131 * j
			var length := 2300.0 if last else 2600.0 + 50.0 * j + 40.0 * w
			# the fortress sits early on odd stages and late on even ones, longer as you go
			var flen := 600.0 + 40.0 * j + (100.0 if w >= 4 else 0.0)
			var fa := roundf(length * (0.36 if j % 2 else 0.48) / 10.0) * 10.0
			if last:
				fa = 900.0
				flen = 600.0
			var fb := fa + flen
			var end := ""
			if last:
				end = BOSSES[w]
			else:
				end = ("twins:" if j % 2 else "big:") + wd.big
			if w == 0 and j == 0:
				end = "big:shell"
			# rock: one canyon in the longer open stretch, islands in the other (or both in one)
			var a0 := 320.0
			var a1 := fa - 150.0
			var b0 := fb + 150.0
			var b1 := length - 320.0
			var gap := maxf(58.0, 68.0 - j * 1.5 - w)
			var canyons := []
			var islands := []
			var can_len := 260.0 + rng.randf_range(0.0, 40.0)
			var long_a := (a1 - a0) >= (b1 - b0)
			var c0: float = (a0 + EASE if long_a else b0 + EASE)
			canyons.append([c0, c0 + can_len, gap])
			var spots: Array = []
			var rest0 := c0 + can_len + EASE + 60.0
			var rest1 := a1 if long_a else b1
			if rest1 - rest0 > 200.0:
				spots.append(rest0)
			if long_a and b1 - b0 > 180.0:
				spots.append(b0)
			elif not long_a and a1 - a0 > 180.0:
				spots.append(a0)
			if spots.size() < 2 and rest1 - rest0 > 420.0:
				spots.append(rest0 + 230.0)
			for k in mini(2, spots.size()):
				var isl_len := 150.0 + rng.randf_range(0.0, 20.0)
				var x := 63.0 + rng.randf_range(-14.0, 14.0)
				islands.append([roundf(spots[k]), isl_len, roundf(x), 13.0 + rng.randf_range(0.0, 2.0)])
			var st := {id = "w%ds%d" % [w + 1, j + 1], name = wd.names[j], sub = "%s · %d" % [Worlds.LIST[w].name, j + 1], world = w, j = j, length = length,
				seed = rng.seed, fort = [fa, fb], end = end, canyons = canyons, islands = islands}
			if w == 0 and j == 0:
				# the canyon run (VRun) takes the place of rock in the stretch before the fortress
				st.run = fa - 130.0
				st.islands = islands.filter(func(isl): return isl[0] + isl[1] < st.run - 300.0 or isl[0] > st.run + 300.0)
			out.append(st)
	return out


## The events of stage `i`, sorted by distance.
static func build(i: int) -> Array:
	var s: Dictionary = STAGES[i]
	var wd: Dictionary = WORLDS[s.world]
	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed
	var ev: Array = []
	var fa: float = s.fort[0]
	var fb: float = s.fort[1]
	var j: int = s.j
	var pool: Array = wd.pool.slice(0, mini(wd.pool.size(), 3 + j / 2))
	if j >= 4:
		pool.append(wd.late)
	# open ground: a group of enemies every ~130 units (closer each stage and world), and from
	# the third stage on every third group comes with a second one on top of it
	var lv: int = j + 2 * s.world
	var d := 220.0
	var k := j
	var run: float = s.get("run", -9999.0)
	while d < s.length - 120:
		if d >= run - 240 and d < run + 40:
			d = run + 40
			continue
		if d >= fa - 80 and d < fb + 60:
			d = fb + 140
			continue
		_group(ev, pool[k % pool.size()], d, rng, lv)
		if j >= 2 and k % 3 == 2:
			_group(ev, pool[(k + 2) % pool.size()], d + 40.0, rng, lv)
		k += 1
		d += maxf(80.0, rng.randf_range(115, 145) - 3.0 * j - 4.0 * s.world)
	# item carriers: a laser item early and one after the fortress
	ev.append({d = fa * 0.45, type = "carrier", x = 20.0, dir = 1.0, item = "L"})
	ev.append({d = fb + 60, type = "carrier", x = W - 20, dir = -1.0, item = "L"})
	_fortress(ev, fa, fb, rng, i)
	if s.has("run"):
		# the canyon run (see VRun): its mouth appears at the top of the screen here
		ev.append({d = run, type = "run"})
	ev.append({d = s.length, type = "end", kind = s.end})
	_clear_shots(ev)
	ev.sort_custom(func(a, b): return a.d < b.d)
	return ev


## A ground target in the screen above a barrier would sit behind its wall, out of reach of the
## ship's shots: move it into line with the barrier's opening (its middle, for a sliding one).
static func _clear_shots(ev: Array) -> void:
	var bars := ev.filter(func(e): return e.type == "barrier")
	for e in ev:
		if e.type != "turret" and e.type != "generator":
			continue
		var below: Dictionary = {}
		for b in bars:
			if b.d < e.d and e.d - b.d < H + 10.0 and (below.is_empty() or b.d > below.d):
				below = b
		if not below.is_empty() and absf(e.x - below.gx) > below.gw / 2.0 - 6.0:
			e.x = below.gx


## True when ground target `e` (an event) lines up with the opening of the barrier under it.
static func in_reach(ev: Array, e: Dictionary) -> bool:
	var below: Dictionary = {}
	for b in ev:
		if b.type == "barrier" and b.d < e.d and e.d - b.d < H + 10.0 and (below.is_empty() or b.d > below.d):
			below = b
	return below.is_empty() or absf(e.x - below.gx) <= below.gw / 2.0 - 6.0


static func _group(ev: Array, kind: String, d: float, rng: RandomNumberGenerator, stage: int) -> void:
	var lv := mini(stage, 10)
	match kind:
		"sine":
			# a snake of drifters weaving down the screen
			var x := rng.randf_range(30, W - 30)
			var n := 8 + lv / 2
			for j in n:
				ev.append({d = d + j * 14, type = "drifter", x = x, move = "sine", amp = 22.0, ph = j * 0.5})
		"snakes":
			# two snakes weaving against each other
			for side in [-1.0, 1.0]:
				for j in 6 + lv / 3:
					ev.append({d = d + j * 14, type = "drifter", x = W / 2 + side * 28.0, move = "sine", amp = 18.0 * side, ph = j * 0.5})
		"dive":
			# drifters stop high up, take aim, then dive
			var n := 5 + lv / 2
			for j in n:
				ev.append({d = d + j * 22, type = "drifter", x = 16 + (W - 32) * float(j) / maxf(1, n - 1), move = "dive", stop = rng.randf_range(150, 190)})
		"turrets":
			# a pair of ground turrets on the ridges
			ev.append({d = d, type = "turret", x = 22.0})
			ev.append({d = d + 50, type = "turret", x = W - 22})
			if stage > 0:
				ev.append({d = d + 100, type = "turret", x = W / 2})
			if stage > 5:
				ev.append({d = d + 25, type = "turret", x = 44.0})
				ev.append({d = d + 75, type = "turret", x = W - 44.0})
		"shell", "hulk", "sentinel", "nest", "bulwark", "flake":
			ev.append({d = d, type = kind, x = rng.randf_range(40, W - 40)})
		"shards":
			ev.append({d = d, type = "shards", x = rng.randf_range(30, W - 30), n = rng.randi_range(3, 4) + lv / 4})
		"drones":
			ev.append({d = d, type = "drones", x = rng.randf_range(24, W - 24), n = rng.randi_range(4, 5) + lv / 4})
		"seekers":
			ev.append({d = d, type = "seekers", x = rng.randf_range(30, W - 30), n = rng.randi_range(2, 3) + lv / 6})
		"wasps":
			ev.append({d = d, type = "wasps", x = rng.randf_range(30, W - 30), n = rng.randi_range(5, 6) + lv / 4})
		"lancers":
			ev.append({d = d, type = "lancers", x = W / 2, n = rng.randi_range(2, 3)})


## Barriers across the screen: fixed, sliding, a wall to shoot through and one locked by a
## generator, with turrets between them.
static func _fortress(ev: Array, a: float, b: float, rng: RandomNumberGenerator, stage: int) -> void:
	var modes: Array = (["fixed", "slide", "wall", "locked"] if stage % 3 == 0 else (["slide", "locked", "wall", "slide"] if stage % 3 == 1 else ["locked", "wall", "slide"])).duplicate()
	if (b - a) > 760.0:
		modes.append("locked" if modes[-1] != "locked" else "slide")
	var n: int = modes.size()
	var span := (b - a) / float(n)
	for j in n:
		var d := a + span * (j + 0.6)
		var gx := rng.randf_range(34, W - 34)
		var m: String = modes[j]
		var e := {d = d, type = "barrier", mode = m, gx = gx, gw = 30.0 if m != "slide" else 34.0, key = "k%d" % j}
		ev.append(e)
		if m == "locked":
			# the generator sits on the ground just before its barrier
			ev.append({d = d - 70, type = "generator", x = W - gx if absf(W - gx - gx) > 30 else (20.0 if gx > W / 2 else W - 20), key = e.key})
		ev.append({d = d - 120, type = "turret", x = 20.0 if j % 2 else W - 20})
		# divers come through the opening, more of them deeper into the campaign
		for q in 2 + mini(4, stage / 6):
			ev.append({d = d - 40 + q * 18, type = "drifter", x = clampf(gx + (q - 1) * 10.0, 10.0, W - 10.0), move = "dive", stop = 175.0 - q * 6.0})


## The inner edges of the rock walls at distance `d` of stage `i`: x of the left wall's face and
## of the right wall's face (the open passage is between them). Off screen outside a canyon.
static func walls(i: int, d: float) -> Vector2:
	var l := OFF
	var r := OFF
	for c in CANYONS[i]:
		var k := smoothstep(c[0] - EASE, c[0], d) * (1.0 - smoothstep(c[1], c[1] + EASE, d))
		if k <= 0.0:
			continue
		var gap: float = c[2]
		var room := (W - gap) / 2.0
		var mid := W / 2.0 + sin((d - c[0]) * 0.011 + i * 1.7) * room * 0.75
		l = lerpf(l, mid - gap / 2.0, k)
		r = lerpf(r, W - (mid + gap / 2.0), k)
	return Vector2(l, W - r)


## The half-width of island `isl` at distance `d` (0 outside it): pointed at both ends.
static func island_half(isl: Array, d: float) -> float:
	var t := (d - float(isl[0])) / float(isl[1])
	if t <= 0.0 or t >= 1.0:
		return 0.0
	return float(isl[3]) * pow(sin(PI * t), 0.6)


## True when the point x at distance `d` of stage `i` is within `pad` of an island.
static func on_island(i: int, x: float, d: float, pad: float) -> bool:
	for isl in ISLANDS[i]:
		var h := island_half(isl, d)
		if h > 0.0 and absf(x - float(isl[2])) < h + pad:
			return true
	return false


## A repeatable pseudo-random number in 0..1 for a point (terrain jitter, decoration).
static func hash(p: Vector2) -> float:
	var s := sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453
	return s - floorf(s)
