class_name VStage
extends RefCounted
## Stages of the portrait game (vertical slice: world 1, The Hollow Moon, as three stages).
## A stage is a list of events placed at a distance `d` along the scroll (stage units, the
## screen is 126 wide and 224 tall). Each stage is open ground with enemy waves, a fortress
## section of barriers, then a mid-boss (stages 1 and 2) or the world's boss (stage 3).
## Seeded, so a stage is always the same.

const W := 126.0
const H := 224.0

const STAGES := [
	{name = "Spore Fields", sub = "The Hollow Moon · 1", length = 2600.0, seed = 11, fort = [1300.0, 1900.0], end = "matriarch"},
	{name = "Crystal Gate", sub = "The Hollow Moon · 2", length = 2700.0, seed = 23, fort = [1100.0, 2000.0], end = "twins"},
	{name = "Bloom Heart", sub = "The Hollow Moon · 3", length = 2300.0, seed = 37, fort = [900.0, 1500.0], end = "bloom"},
]


## The events of stage `i`, sorted by distance.
static func build(i: int) -> Array:
	var s: Dictionary = STAGES[i]
	var rng := RandomNumberGenerator.new()
	rng.seed = s.seed
	var ev: Array = []
	var fa: float = s.fort[0]
	var fb: float = s.fort[1]
	# open ground: a group of enemies every ~200 units
	var pool := ["sine", "dive", "turrets", "sine", "shell", "dive", "turrets"]
	var d := 260.0
	var k := i
	while d < s.length - 120:
		if d >= fa - 80 and d < fb + 60:
			d = fb + 140
			continue
		_group(ev, pool[k % pool.size()], d, rng, i)
		k += 1
		d += rng.randf_range(190, 240)
	# item carriers: a laser item early and one after the fortress
	ev.append({d = fa * 0.45, type = "carrier", x = 20.0, dir = 1.0, item = "L"})
	ev.append({d = fb + 60, type = "carrier", x = W - 20, dir = -1.0, item = "L"})
	_fortress(ev, fa, fb, rng, i)
	ev.append({d = s.length, type = "end", kind = s.end})
	ev.sort_custom(func(a, b): return a.d < b.d)
	return ev


static func _group(ev: Array, kind: String, d: float, rng: RandomNumberGenerator, stage: int) -> void:
	match kind:
		"sine":
			# a snake of spore drifters weaving down the screen
			var x := rng.randf_range(30, W - 30)
			var n := 6 + stage
			for j in n:
				ev.append({d = d + j * 14, type = "drifter", x = x, move = "sine", amp = 22.0, ph = j * 0.5})
		"dive":
			# drifters stop high up, take aim, then dive
			var n := 4 + stage
			for j in n:
				ev.append({d = d + j * 22, type = "drifter", x = 16 + (W - 32) * float(j) / maxf(1, n - 1), move = "dive", stop = rng.randf_range(150, 190)})
		"turrets":
			# a pair of ground turrets on the ridges
			ev.append({d = d, type = "turret", x = 22.0})
			ev.append({d = d + 50, type = "turret", x = W - 22})
			if stage > 0:
				ev.append({d = d + 100, type = "turret", x = W / 2})
		"shell":
			ev.append({d = d, type = "shell", x = rng.randf_range(40, W - 40)})


## Barriers across the screen: fixed, sliding, a wall to shoot through and one locked by a
## generator, with turrets between them.
static func _fortress(ev: Array, a: float, b: float, rng: RandomNumberGenerator, stage: int) -> void:
	var modes: Array = [["fixed", "slide", "wall", "locked"], ["slide", "locked", "wall", "slide"], ["locked", "wall", "slide"]][stage]
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
		ev.append({d = d - 40, type = "drifter", x = gx, move = "dive", stop = 175.0})


## Edge mode: the rock walls on both sides of the stage. Each canyon is [start, end, gap]:
## between start and end the walls close in to leave a `gap` wide passage that wanders from
## side to side. Elsewhere a thin rim of rock lines the screen. Rock spurs jut in from
## alternate sides every so often. Walls only open up for the boss.
const CANYONS := [
	[[420.0, 900.0, 74.0], [1960.0, 2140.0, 64.0]],
	[[330.0, 860.0, 66.0], [2060.0, 2250.0, 58.0]],
	[[260.0, 820.0, 60.0], [1540.0, 1850.0, 56.0]],
]
const RIM := 7.0
const FORT_RIM := 13.0
const SPUR_EVERY := 150.0
const SPUR := 15.0
const EASE := 70.0


## The inner edges of the rock walls at distance `d` of stage `i`: x of the left wall's face and
## of the right wall's face (the open passage is between them).
static func walls(i: int, d: float) -> Vector2:
	var s: Dictionary = STAGES[i]
	var l := RIM
	var r := RIM
	var fa: float = s.fort[0]
	var fb: float = s.fort[1]
	var fk := smoothstep(fa - EASE, fa, d) * (1.0 - smoothstep(fb, fb + EASE, d))
	l = lerpf(l, FORT_RIM, fk)
	r = lerpf(r, FORT_RIM, fk)
	var spur_on := 1.0 - fk
	for c in CANYONS[i]:
		var k := smoothstep(c[0] - EASE, c[0], d) * (1.0 - smoothstep(c[1], c[1] + EASE, d))
		if k <= 0.0:
			continue
		var gap: float = c[2]
		var room := (W - gap) / 2.0 - RIM
		var mid := W / 2.0 + sin((d - c[0]) * 0.011 + i * 1.7) * room * 0.8
		l = lerpf(l, mid - gap / 2.0, k)
		r = lerpf(r, W - (mid + gap / 2.0), k)
		spur_on *= 1.0 - k
	# rock spurs in open ground, alternating sides
	var n := floorf(d / SPUR_EVERY)
	var f := d / SPUR_EVERY - n
	var bump := maxf(0.0, 1.0 - absf(f - 0.5) / 0.14) * SPUR * spur_on
	if int(n) % 2 == 0:
		l += bump
	else:
		r += bump
	# the boss gets the whole screen (the scroll stops a screen short of the stage's end)
	var open := smoothstep(s.length - H - 200.0, s.length - H - 40.0, d)
	l = lerpf(l, 2.0, open)
	r = lerpf(r, 2.0, open)
	return Vector2(l, W - r)


## A repeatable pseudo-random number in 0..1 for a point (terrain jitter, decoration).
static func hash(p: Vector2) -> float:
	var s := sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453
	return s - floorf(s)
