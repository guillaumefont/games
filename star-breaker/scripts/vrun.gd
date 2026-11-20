class_name VRun
extends RefCounted
## The canyon run: a ~15 second set piece in the middle of a stage. A crevasse slides in from the
## top of the screen, the camera swings down behind the ship and the thumb steers it through the
## rock at speed: left/right AND up/down (climb over spines, dive under arches, thread windows),
## the one thing the top-down view can't show. Then the canyon opens and the camera swings back.
## A clean run (no touch) earns the gold medal, which also fills the ultimate.
##
## Course coordinates: `u` runs along the canyon (0 = its mouth), `x` is the stage's x
## (0..126), `z` is the world height (the play plane is z = 0, the canyon floor is FLOOR).
## The course is a pure function of `u`, so the same numbers drive the collision, the mesh and
## the tests.

## The course in use (see `use()`): stage 1's long hand-made run by default, a short generated
## one in every other stage (`generate()`).
static var LEN := 2400.0
## Past here the ship only glides back to the play plane while the camera swings out.
static var OUT := 2000.0
static var PATH: Array = BASE_PATH
static var TURN: Array = BASE_TURN
static var OBS: Array = BASE_OBS
const FLOOR := -40.0
const RIM := 34.0
## The ship's height range inside the canyon (it scrapes the floor, never digs in).
const ZMIN := -36.0
const ZMAX := 24.0
## How close to rock counts as a touch, and the scrape zone just outside it that pays points.
const PAD := 2.6
const SCRAPE := 6.0
## Where the ship sits on the stage (y) while the canyon streams past it.
const SHIP_Y := 44.0
## Thumb travel to ship travel once the camera is behind the ship.
const GAIN := 0.7
## Obstacle thickness along the canyon.
const DEPTH := 8.0
const MEDALS := [["Gold", 5000], ["Silver", 2000], ["Bronze", 500]]

## The passage: [u, centre x, half width], eased between keys. Wide (off screen) at both ends,
## and once wide inside: a basin split by a mesa.
const BASE_PATH := [[-400.0, 63.0, 100.0], [0.0, 63.0, 100.0], [160.0, 63.0, 32.0], [290.0, 53.0, 30.0], [430.0, 74.0, 30.0],
	[540.0, 63.0, 30.0], [1080.0, 63.0, 30.0], [1180.0, 63.0, 52.0], [1380.0, 63.0, 52.0], [1460.0, 63.0, 30.0],
	[1520.0, 63.0, 30.0], [1580.0, 52.0, 23.0], [1660.0, 78.0, 22.0], [1740.0, 50.0, 23.0], [1820.0, 63.0, 30.0],
	[2020.0, 63.0, 32.0], [2240.0, 63.0, 100.0], [2900.0, 63.0, 100.0]]

## Where the canyon heads: [u, degrees to the left], eased between keys. It runs straight where
## the camera swings (so the moon's floor lines up with it) and turns no tighter than a radius of
## ~230 units, so the rim's back (180 units out) never folds over on the inside of a bend.
const BASE_TURN := [[-400.0, 0.0], [520.0, 0.0], [740.0, 35.0], [860.0, 35.0], [1160.0, -15.0], [1260.0, -15.0],
	[1380.0, 0.0], [1490.0, 0.0], [1640.0, 22.0], [1790.0, 0.0], [2900.0, 0.0]]

## Obstacles, laid out for movement more than precision (Guillaume, 2026-11-20): every gap is big,
## but each one sits across the canyon or up/down from the last, so the ship is always on the move.
## Concretion columns (dodge to the open side), natural bridges (dive under: their underside
## arches up towards the middle), saddle ridges (climb over: lowest in the middle) and eroded
## walls with one oval hole. dx is from the passage centre; an arch's or ridge's z is its height at
## the walls.
const BASE_OBS := [
	{u = 230.0, k = "pillar", dx = -10.0, r = 14.0},
	{u = 350.0, k = "pillar", dx = 10.0, r = 14.0},
	{u = 470.0, k = "pillar", dx = -10.0, r = 14.0},
	{u = 610.0, k = "arch", z = -20.0},
	{u = 730.0, k = "spine", z = 6.0},
	{u = 850.0, k = "arch", z = -22.0},
	{u = 970.0, k = "spine", z = 4.0},
	{u = 1280.0, k = "mesa", dx = 12.0, r = 20.0, len = 140.0},
	{u = 1540.0, k = "window", dx = -8.0, z = -16.0, hw = 17.0, hh = 15.0},
	{u = 1650.0, k = "arch", z = -18.0},
	{u = 1760.0, k = "window", dx = 8.0, z = 5.0, hw = 17.0, hh = 15.0},
	{u = 1860.0, k = "spine", z = 2.0},
	{u = 1965.0, k = "window", dx = -8.0, z = -12.0, hw = 17.0, hh = 15.0},
]

## Stage 1's hand-made course.
static func handmade() -> Dictionary:
	return {len = 2400.0, path = BASE_PATH, turn = BASE_TURN, obs = BASE_OBS}


## Makes `c` (from `handmade()` or `generate()`) the course in use.
static func use(c: Dictionary) -> void:
	LEN = c.len
	OUT = c.len - 400.0
	PATH = c.path
	TURN = c.turn
	OBS = c.obs
	_ctr = PackedVector2Array()


## A short course for a stage (Guillaume wants a run in every stage, 2026-11-20): ~12-15 s, built
## from the stage's seed so no two are alike, harder world by world (closer obstacles, a narrower
## passage, smaller holes, bigger spires, lower bridges, higher ridges). Same rules as stage 1's:
## every gap is big but sits across the canyon or up/down from the last one, so the ship keeps
## moving; one bend, straight while the camera swings in and out.
static func generate(seed: int, world: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var w := float(world)
	var n := 5 + (1 if world >= 3 else 0)
	var sp := 112.0 - 4.0 * w
	var hw := 30.0 - 0.8 * w
	var u0 := 230.0
	var obs := []
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var low := rng.randf() < 0.5
	var prev := ""
	for i in n:
		var kinds := ["pillar", "window", "arch", "spine"].filter(func(k): return k != prev)
		var k: String = kinds[rng.randi() % kinds.size()]
		var u := u0 + i * sp
		match k:
			"pillar":
				side = -side
				obs.append({u = u, k = k, dx = -side * 10.0, r = 14.0 + 0.4 * w})
			"window":
				side = -side
				low = not low
				var z := rng.randf_range(-17.0, -12.0) if low else rng.randf_range(2.0, 5.0)
				obs.append({u = u, k = k, dx = side * 8.0, z = z, hw = 17.0 - 0.5 * w, hh = 15.0 - 0.5 * w})
			"arch":
				low = true
				obs.append({u = u, k = k, z = -20.0 - 0.6 * w})
			"spine":
				low = false
				obs.append({u = u, k = k, z = 4.0 + 0.8 * w})
		prev = k
	var last: float = obs[-1].u
	var out := last + 45.0
	var length := out + 400.0
	# the passage sways a little between obstacles
	var path := [[-400.0, 63.0, 100.0], [0.0, 63.0, 100.0], [160.0, 63.0, hw + 2.0]]
	for i in n - 1:
		path.append([u0 + (i + 0.5) * sp, 63.0 + rng.randf_range(-7.0, 7.0), hw])
	path.append([out + 20.0, 63.0, hw + 2.0])
	path.append([length - 160.0, 63.0, 100.0])
	path.append([length + 500.0, 63.0, 100.0])
	# one bend (no tighter than ~260 units of radius) and back, straight again before the way out
	var a := rng.randf_range(22.0, 35.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	# 160 units of turn per 22 degrees keeps the tightest point (smoothstep's middle) wider than
	# ~250 units of radius; both turns must fit before the way out
	var b0 := 380.0
	var b3 := out - 40.0
	var tl := minf(160.0 * absf(a) / 22.0, (b3 - b0) / 2.0)
	a = signf(a) * minf(absf(a), 22.0 * tl / 160.0)
	var b1 := b0 + tl
	var b2 := b3 - tl
	var turn := [[-400.0, 0.0], [b0, 0.0], [b1, a], [b2, a], [b3, 0.0], [length + 500.0, 0.0]]
	return {len = length, path = path, turn = turn, obs = obs}


## How much a bridge's underside rises from the walls to its middle, and a ridge's crest dips.
const ARCH_RISE := 9.0


## A bridge's underside height at stage x: highest mid-canyon, curving down to the walls.
static func under(o: Dictionary, x: float) -> float:
	var p := passage(o.u)
	var t := clampf((x - p.x) / p.y, -1.0, 1.0)
	return o.z + ARCH_RISE * (1.0 - t * t)


## A ridge's crest height at stage x: a saddle, lowest mid-canyon.
static func crest(o: Dictionary, x: float) -> float:
	var p := passage(o.u)
	var t := clampf((x - p.x) / p.y, -1.0, 1.0)
	return o.z - ARCH_RISE * (1.0 - t * t)


## How far (x, z) is out of a window's oval hole shrunk by `pad`: < 1 inside, > 1 rock.
static func oval(o: Dictionary, x: float, z: float, pad: float, k := 1.0) -> float:
	var h := hole(o)
	var a := maxf(o.hw * k - pad, 0.5)
	var b := maxf(o.hh * k - pad, 0.5)
	return sqrt(pow((x - h.x) / a, 2.0) + pow((z - h.y) / b, 2.0))



## The way out, made a moment: past OUT the ship pulls up out of the canyon in an arc (peak
## height, units over the play plane) and settles back onto the play plane as the camera swings out.
const LIFT := 20.0


static func lift(u: float) -> float:
	var t := smoothstep(OUT - 20.0, LEN - 30.0, u)
	return LIFT * sin(PI * pow(t, 0.7))


## The way in: the ship swoops down into the canyon as the camera swings behind it and comes back
## up to fly it (an offset the steering adds to, not a hold on the controls).
static func dive(u: float) -> float:
	return -16.0 * sin(PI * smoothstep(-120.0, 60.0, u))


## Half an obstacle's length along the canyon (a mesa is long, the rest DEPTH thick).
static func half(o: Dictionary) -> float:
	if o.k == "pillar":
		return o.r * 0.6
	return o.get("len", DEPTH) / 2.0


## The canyon's heading at `u` (radians, positive turns left).
static func heading(u: float) -> float:
	for i in TURN.size() - 1:
		var a: Array = TURN[i]
		var b: Array = TURN[i + 1]
		if u <= b[0] or i == TURN.size() - 2:
			return deg_to_rad(lerpf(a[1], b[1], smoothstep(float(a[0]), float(b[0]), u)))
	return 0.0


const _C0 := -400.0
const _CSTEP := 2.0
static var _ctr := PackedVector2Array()


## Where the canyon's centre line (world x = 0 when straight) is at `u`, in the canyon node's
## plane: the heading integrated along the canyon. Straight, it is (0, u).
static func centre(u: float) -> Vector2:
	if _ctr.is_empty():
		var c := Vector2(0.0, _C0)
		var uu := _C0
		while uu <= LEN + 600.0:
			_ctr.append(c)
			var h := heading(uu + _CSTEP / 2.0)
			c += Vector2(-sin(h), cos(h)) * _CSTEP
			uu += _CSTEP
	var f := clampf((u - _C0) / _CSTEP, 0.0, _ctr.size() - 1.001)
	var i := int(f)
	return _ctr[i].lerp(_ctr[i + 1], f - i)


## A point in canyon coordinates (world x across, y = u along, z up), as built straight, to where
## it sits in the bent canyon. All gameplay stays in canyon coordinates; only the mesh bends.
static func warp(p: Vector3) -> Vector3:
	var h := heading(p.y)
	var c := centre(p.y)
	return Vector3(c.x + p.x * cos(h), c.y + p.x * sin(h), p.z)


## Bends a straight-built mesh: every vertex to its place, every normal turned with it.
static func _bend(acc: Terrain.Acc) -> void:
	for i in acc.v.size():
		var h := heading(acc.v[i].y)
		acc.n[i] = acc.n[i].rotated(Vector3.BACK, h)
		acc.v[i] = warp(acc.v[i])


## Stage x to world x (as `X()` in vgame.gd).
static func sx(x: float) -> float:
	return x - 63.0


## The stage's own scroll speed (SCROLL in vgame.gd): the run starts and ends at it, so the
## ground never jumps in speed on the way in or out.
const STAGE_SPEED := 0.6


## Canyon speed (course units per tick) at `u`: picks up from the stage's scroll as the mouth
## comes down the screen, builds through the run, and eases back to the stage's scroll at the exit.
static func speed(u: float) -> float:
	var up := lerpf(STAGE_SPEED, 2.5, smoothstep(-240.0, 250.0, u))
	return lerpf(up, STAGE_SPEED, smoothstep(LEN - 360.0, LEN, u))


## Height of the drawn canyon floor at `u`: it starts and ends well under the moon's own ground (below its rivers and craters)
## (so the moon shows through the open mouth and exit) and rises to FLOOR inside.
static func floor_z(u: float) -> float:
	var k := smoothstep(-40.0, 200.0, u) * (1.0 - smoothstep(LEN - 330.0, LEN - 120.0, u))
	return lerpf(-100.0, FLOOR, k)


## Passage centre (x) and half width (y) at `u`.
static func passage(u: float) -> Vector2:
	for i in PATH.size() - 1:
		var a: Array = PATH[i]
		var b: Array = PATH[i + 1]
		if u <= b[0] or i == PATH.size() - 2:
			var t := smoothstep(float(a[0]), float(b[0]), u)
			return Vector2(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))
	return Vector2(63.0, 100.0)


## How far the camera has swung behind the ship (0 top-down .. 1 behind) at `u`.
static func swing(u: float) -> float:
	# the way out is as long and gentle as the way in: it starts once the last obstacle is passed
	return smoothstep(-150.0, 30.0, u) * (1.0 - smoothstep(OUT, LEN - 30.0, u))


## The hole of a window obstacle: centre x, centre z.
## A hole's rock funnel: each ring of the worn face (times the hole's size) and how far before
## the wall's front it sits, so the rock flares out towards the ship and eases it into the hole.
const HOLE_RINGS := [1.0, 1.25, 1.65, 2.3, 3.3, 5.0]
const FUNNEL := [0.0, 5.0, 12.0, 21.0, 31.0, 42.0]


## How much wider than the hole the funnel is at `u` (1 in the hole itself).
static func flare(o: Dictionary, u: float) -> float:
	var d: float = o.u - DEPTH / 2.0 - u
	if d <= 0.0:
		return 1.0
	for i in FUNNEL.size() - 1:
		if d <= FUNNEL[i + 1]:
			return lerpf(HOLE_RINGS[i], HOLE_RINGS[i + 1], (d - FUNNEL[i]) / (FUNNEL[i + 1] - FUNNEL[i]))
	return 99.0


## How far before `o.u` an obstacle's rock starts (a hole's funnel reaches further out).
static func front(o: Dictionary) -> float:
	return DEPTH / 2.0 + FUNNEL[-1] if o.k == "window" else half(o)


static func hole(o: Dictionary) -> Vector2:
	return Vector2(passage(o.u).x + o.dx, o.z)


## What the ship (a point, padded by `pad`) hits between `u0` and `u1`: "" for nothing, "wall",
## or the obstacle's kind.
static func hit(x: float, z: float, u0: float, u1: float, pad: float) -> String:
	var p := passage(u1)
	if x - pad < p.x - p.y or x + pad > p.x + p.y:
		return "wall"
	for o in OBS:
		if o.u + half(o) < u0 or o.u - front(o) > u1:
			continue
		if o.k == "pillar":
			# a rock spire: an oval footprint, r across and half(o) along the canyon
			var du := 0.0 if (o.u >= u0 and o.u <= u1) else minf(absf(o.u - u0), absf(o.u - u1))
			var px: float = passage(o.u).x + o.dx
			if pow((x - px) / (o.r + pad), 2.0) + pow(du / (half(o) + pad), 2.0) < 1.0:
				return o.k
			continue
		if _solid(o, x, z, pad, u1):
			return o.k
	return ""


static func _solid(o: Dictionary, x: float, z: float, pad: float, u := 0.0) -> bool:
	match o.k:
		"pillar", "mesa":
			return absf(x - (passage(o.u).x + o.dx)) < o.r + pad
		"arch":
			return z + pad > under(o, x)
		"spine":
			return z - pad < crest(o, x)
		"window":
			return oval(o, x, z, pad, flare(o, u)) > 1.0
	return false


## Distance from the ship to the nearest rock at `u` (walls and obstacles it is passing), for the
## scrape bonus.
static func clearance(x: float, z: float, u: float) -> float:
	var p := passage(u)
	var d := minf(x - (p.x - p.y), p.x + p.y - x)
	d = minf(d, z - FLOOR)
	for o in OBS:
		if u > o.u + half(o) + DEPTH / 2.0 or u < o.u - front(o) - DEPTH / 2.0:
			continue
		match o.k:
			"pillar", "mesa":
				d = minf(d, absf(x - (p.x + o.dx)) - o.r)
			"arch":
				d = minf(d, under(o, x) - z)
			"spine":
				d = minf(d, z - crest(o, x))
			"window":
				var k := flare(o, u)
				d = minf(d, (1.0 - oval(o, x, z, 0.0, k)) * minf(o.hw, o.hh) * k)
	return d


## A safe racing line at `u`: (x, z) set up for the next obstacle well before it and held
## until the ship is through it.
static func line(u: float) -> Vector2:
	var p := passage(u)
	var dx := 0.0
	var z := -4.0
	for o in OBS:
		# held until the ship is well through (a thumb a little ahead of it must not leave early)
		if o.u + half(o) + 10.0 < u:
			continue
		if o.u - half(o) - u < 100.0:
			var po := passage(o.u)
			match o.k:
				"pillar", "mesa":
					# the open side: the wider one, or for the mesa the tight one (motes go there)
					var l: float = po.x + o.dx - o.r - (po.x - po.y)
					var r: float = po.x + po.y - (po.x + o.dx + o.r)
					var left := l > r if o.k == "pillar" else l < r
					dx = (o.dx - o.r - l / 2.0) if left else (o.dx + o.r + r / 2.0)
				"arch":
					z = under(o, po.x) - 10.0
				"spine":
					z = crest(o, po.x) + 10.0
				"window":
					dx = o.dx
					z = o.z
		break
	return Vector2(clampf(p.x + dx, p.x - p.y + 6.0, p.x + p.y - 6.0), clampf(z, ZMIN + 2.0, ZMAX - 2.0))


## Crystal motes along the racing line: they show the way and pay points. [u, x, z] each.
static func motes() -> Array:
	var out := []
	var u := 180.0
	while u < OUT:
		var l := line(u)
		if hit(l.x, l.y, u - 6.0, u + 6.0, 2.0) == "":
			out.append([u, l.x, l.y])
		u += 30.0
	return out


# ---------- the mesh ----------

## Builds the whole canyon a slice per call (call `step()` once a frame until it returns true),
## so a stage that has a run builds it while the player is flying, without a hitch.
class Builder:
	var node := Node3D.new()
	var _u := -300.0
	var _pal: Dictionary
	var _mats: Dictionary
	## Obstacles waiting to be built, one per call (a faceted one costs as much as a slice).
	var _todo: Array = []
	const SLICE := 40.0
	const ROW := 10.0

	func _init(pal: Dictionary, mats: Dictionary) -> void:
		_pal = pal
		_mats = mats
		node.name = "CanyonRun"

	func step() -> bool:
		if not _todo.is_empty():
			_build_obstacle(_todo.pop_front())
			return _done()
		if _u >= VRun.LEN + 300.0:
			return true
		var rock := Terrain.Acc.new()
		var lip := Terrain.Acc.new()
		var glow := Terrain.Acc.new()
		var u := _u
		while u < _u + SLICE - 0.01:
			VRun._rows(rock, lip, glow, u, u + ROW, _pal)
			u += ROW
		for o in VRun.OBS:
			if o.u >= _u and o.u < _u + SLICE:
				_todo.append(o)
		for acc in [rock, lip, glow]:
			VRun._bend(acc)
		if rock.count() > 0:
			node.add_child(Terrain._mi(rock.mesh(), _mats.ground, true))
		if lip.count() > 0:
			node.add_child(Terrain._mi(lip.mesh(), _mats.lip, false))
		if glow.count() > 0:
			node.add_child(Terrain._mi(glow.mesh(), _mats.glow, false))
		_u += SLICE
		return _done()

	func _done() -> bool:
		return _u >= VRun.LEN + 300.0 and _todo.is_empty()

	## Each obstacle gets its own meshes and materials: a bridge, ridge or wall fades once the
	## ship is through and goes once the camera reaches it (from under a bridge the camera
	## would otherwise lose the ship climbing out beyond it).
	func _build_obstacle(o: Dictionary) -> void:
		var orock := Terrain.Acc.new()
		var olip := Terrain.Acc.new()
		VRun._obstacle(orock, olip, o, _pal)
		VRun._bend(orock)
		VRun._bend(olip)
		var fades: bool = o.k in ["arch", "spine", "window"]
		for pair in [[orock, _mats.ground, true], [olip, _mats.lip, false]]:
			if (pair[0] as Terrain.Acc).count() == 0:
				continue
			var mi := Terrain._mi((pair[0] as Terrain.Acc).mesh(), (pair[1] as Material).duplicate() if fades else pair[1], pair[2])
			if fades:
				mi.set_meta("obs_u", o.u)
			node.add_child(mi)
		var gl := VRun.gap_light(o)
		if gl.size.x > 0.0:
			gl.node.rotation.y = VRun.heading(o.u)
			gl.node.position = VRun.warp(gl.node.position)
			gl.node.set_meta("gap_u", o.u)
			node.add_child(gl.node)


## Heights of the wall's bands, floor to rim, and how far each juts back into the rock.
const BANDS := [-104.0, -26.0, -12.0, 2.0, 18.0, RIM]


## One row of canyon (walls, rim tops, floor) between u0 and u1.
static func _rows(rock: Terrain.Acc, lip: Terrain.Acc, glow: Terrain.Acc, u0: float, u1: float, pal: Dictionary) -> void:
	var pa := passage(u0)
	var pb := passage(u1)
	for s in [-1.0, 1.0]:
		var ea := sx(pa.x + s * pa.y)
		var eb := sx(pb.x + s * pb.y)
		# the face: banded strata, jittered only outwards (into the rock), never into the passage
		for m in BANDS.size() - 1:
			var za: float = BANDS[m]
			var zb: float = BANDS[m + 1]
			var ja := VStage.hash(Vector2(u0, m * 3.0 + s)) * 2.2 if m > 0 else 0.0
			var jb := VStage.hash(Vector2(u1, m * 3.0 + s)) * 2.2 if m > 0 else 0.0
			var ka := VStage.hash(Vector2(u0, m * 3.0 + 3.0 + s)) * 2.2 if m + 1 < BANDS.size() - 1 else 0.0
			var kb := VStage.hash(Vector2(u1, m * 3.0 + 3.0 + s)) * 2.2 if m + 1 < BANDS.size() - 1 else 0.0
			var a := _crag(Vector3(ea + s * ja, u0, za), s, m)
			var b := _crag(Vector3(eb + s * jb, u1, za), s, m)
			var c := _crag(Vector3(ea + s * ka, u0, zb), s, m + 1)
			var d := _crag(Vector3(eb + s * kb, u1, zb), s, m + 1)
			if m + 1 == BANDS.size() - 1:
				c.z = rim_z(u0, s)
				d.z = rim_z(u1, s)
			# each facet its own shade (light from above, plus a little drift), no bands of colour:
			# stripes of equal bands are what made the walls read as stacked blocks
			var base := Color(pal.c_face).lightened(0.12).darkened(float(BANDS.size() - 2 - m) * 0.08)
			var out := Vector3(-s, 0, 0)
			for t in [[a, b, d], [a, d, c]]:
				rock.tri(t[0], t[1], t[2], _facet(base, t[0], t[1], t[2], out), out)
		# beyond the rim: mountains, not a plateau. Ridges climb away from the edge to jagged peaks
		# 40 to 80 units up, then fall away over the moon, so nothing shows past them
		for k in MOUNT.size() - 1:
			var a := _mount(ea, u0, s, k)
			var b := _mount(eb, u1, s, k)
			var c := _mount(ea, u0, s, k + 1)
			var d := _mount(eb, u1, s, k + 1)
			for t in [[a, b, d], [a, d, c]]:
				var hgt: float = (t[0].z + t[1].z + t[2].z) / 3.0
				rock.tri(t[0], t[1], t[2], _facet(_mount_col(pal, hgt), t[0], t[1], t[2], Vector3.BACK), Vector3.BACK)
		# alien crystal outcrops: at the foot of the walls (in the rock, leaning away from the
		# passage, never into it) and on the mountains' flanks
		if VStage.hash(Vector2(u0 * 0.137, s * 7.3)) > 0.78:
			var w := 1.2 + VStage.hash(Vector2(u0, s)) * 1.2
			var base := Vector3(ea + s * (w + 1.5), u0 + 5.0, FLOOR + VStage.hash(Vector2(u0, s + 2.0)) * 8.0)
			_crystals(glow, base, s, w, 7.0 + VStage.hash(Vector2(u0, s + 4.0)) * 9.0, u0)
		if VStage.hash(Vector2(u0 * 0.211, s * 3.1)) > 0.7:
			var mk := 3 + int(VStage.hash(Vector2(u0, s * 9.0)) * 2.0)
			var mp := _mount(ea, u0 + 5.0, s, mk)
			_crystals(glow, mp - Vector3(0, 0, 3.0), s, 2.5, 12.0 + VStage.hash(Vector2(u0, s + 6.0)) * 14.0, u0 + 0.5)
		# the glowing lip on the rim edge (what the top-down view reads as the wall)
		var la := rim_z(u0, s) + 0.3
		var lb := rim_z(u1, s) + 0.3
		lip.tri(Vector3(ea, u0, la), Vector3(eb, u1, lb), Vector3(eb + s * 0.9, u1, lb), Color.WHITE, Vector3.BACK)
		lip.tri(Vector3(ea, u0, la), Vector3(eb + s * 0.9, u1, lb), Vector3(ea + s * 0.9, u0, la), Color.WHITE, Vector3.BACK)
	# the floor, a little wider than the passage so its edges tuck under the walls
	var cols := 6
	for i in cols:
		var ta := float(i) / cols
		var tb := float(i + 1) / cols
		var xa0 := sx(pa.x - pa.y - 10.0 + (pa.y * 2.0 + 20.0) * ta)
		var xa1 := sx(pa.x - pa.y - 10.0 + (pa.y * 2.0 + 20.0) * tb)
		var xb0 := sx(pb.x - pb.y - 10.0 + (pb.y * 2.0 + 20.0) * ta)
		var xb1 := sx(pb.x - pb.y - 10.0 + (pb.y * 2.0 + 20.0) * tb)
		var h := func(uu: float, ii: int) -> float: return VRun.floor_z(uu) + (VStage.hash(Vector2(uu * 0.1, ii)) - 0.5) * 1.6
		var a := Vector3(xa0, u0, h.call(u0, i))
		var b := Vector3(xb0, u1, h.call(u1, i))
		var c := Vector3(xa1, u0, h.call(u0, i + 1))
		var d := Vector3(xb1, u1, h.call(u1, i + 1))
		var jf := VStage.hash(Vector2(u0 * 0.13, i * 1.7))
		var col := Color(pal.t_low).lerp(Color(pal.t_mid), 0.25 + jf * 0.3)
		rock.tri(a, b, d, col, Vector3.BACK)
		rock.tri(a, d, c, col.darkened(0.04 + VStage.hash(Vector2(u0, i)) * 0.06), Vector3.BACK)
	# glowing fissures across the floor every 60 units: they rush past and sell the speed
	if fmod(u0 + 1000.0, 60.0) < 0.5:
		for s in [-1.0, 1.0]:
			var x0 := sx(pa.x + s * (pa.y - 2.0))
			var x1 := sx(pa.x + s * (pa.y * 0.45))
			var z := floor_z(u0) + 1.0
			glow.tri(Vector3(x0, u0, z), Vector3(x1, u0, z), Vector3(x1, u0 + 1.4, z), Color.WHITE, Vector3.BACK)
			glow.tri(Vector3(x0, u0, z), Vector3(x1, u0 + 1.4, z), Vector3(x0, u0 + 1.4, z), Color.WHITE, Vector3.BACK)


## The height of the canyon's rim edge on side `s` at `u`: it rises and dips along the canyon
## (a ragged skyline from inside, not a ruler-straight top), always well over the ship's ceiling.
static func rim_z(u: float, s: float) -> float:
	return RIM + (0.5 + 0.5 * sin(u * 0.029 + s * 2.1)) * 6.0 - 2.0 + (VStage.hash(Vector2(u * 0.1, s)) - 0.5) * 3.0


## The mountains' profile out from the rim edge: how far out each step is.
const MOUNT := [0.0, 6.0, 16.0, 32.0, 55.0, 85.0, 125.0, 180.0]


## Ridged noise in 0..1 with sharp crests, along the canyon.
static func _ridge(u: float, s: float, i: int) -> float:
	var f := 0.017 + 0.005 * i
	var a := 1.0 - absf(sin(u * f + s * 1.3 * i + 0.6 * sin(u * f * 0.37 + i)))
	var b := 1.0 - absf(sin(u * f * 2.7 + s * 2.1 + i * 3.3))
	return pow(a, 3.0) * 0.75 + pow(b, 3.0) * 0.25


## The mountain point `k` steps out from the rim edge at `e` (world x of the edge), on side `s`.
static func _mount(e: float, u: float, s: float, k: int) -> Vector3:
	var z: float
	match k:
		0:
			return Vector3(e, u, rim_z(u, s))
		1:
			z = rim_z(u, s) + 2.0 + VStage.hash(Vector2(u, s + 11.0)) * 4.0
		2:
			z = RIM + 8.0 + _ridge(u, s, 1) * 18.0
		3:
			z = RIM + 14.0 + _ridge(u, s, 2) * 36.0
		4:
			z = RIM + 18.0 + _ridge(u, s, 3) * 50.0
		5:
			z = RIM + 10.0 + _ridge(u, s, 4) * 40.0
		6:
			z = RIM + _ridge(u, s, 5) * 20.0
		_:
			z = RIM - 6.0
	var j := VStage.hash(Vector2(u * 0.31, k * 7.0 + s)) - 0.5
	var gap: float = MOUNT[k] - MOUNT[k - 1]
	return Vector3(e + s * (MOUNT[k] + j * gap * 0.5), u, z + j * 4.0)


## Mountain rock's colour by height: dark foothills to pale crags, with a faint alien sheen on
## the peaks.
static func _mount_col(pal: Dictionary, z: float) -> Color:
	var t := clampf((z - RIM) / 60.0, 0.0, 1.0)
	var c := Color(pal.c_top2).lerp(Color(pal.c_top), t).lightened(t * 0.12)
	return c.lerp(Color(pal.get("river_a", pal.c_top)), smoothstep(0.6, 1.0, t) * 0.12)


## A cluster of three glowing crystals growing from `base`, leaning away from the passage (side s).
static func _crystals(acc: Terrain.Acc, base: Vector3, s: float, w: float, l: float, seed: float) -> void:
	for i in 3:
		var lean := Vector3(s * (0.25 + VStage.hash(Vector2(seed, i)) * 0.5), (VStage.hash(Vector2(seed, i + 3.0)) - 0.5) * 0.6, 1.0).normalized()
		var c := base + Vector3(s * i * w * 0.9, (i - 1) * w * 1.3, 0.0)
		var len := l * (1.0 - i * 0.25)
		var ww := w * (1.0 - i * 0.2)
		var tip := c + lean * len
		var bot := c - lean * len * 0.2
		var side := lean.cross(Vector3.FORWARD).normalized()
		var side2 := lean.cross(side).normalized()
		var ring := [c + side * ww, c + side2 * ww, c - side * ww, c - side2 * ww]
		for q in 4:
			var a: Vector3 = ring[q]
			var b: Vector3 = ring[(q + 1) % 4]
			acc.convex(a, b, tip, Color.WHITE, c)
			acc.convex(b, a, bot, Color.WHITE, c)


## A pseudo-random 3D offset in -1..1 per axis, the same wherever the same point is asked for
## (points are snapped first, so faces that share an edge stay joined).
static func _jit(p: Vector3, seed: float) -> Vector3:
	var q := (p * 4.0).round() / 4.0
	var k := Vector2(q.x * 0.731 + q.z * 1.37 + seed, q.y * 0.593 - q.z * 0.41)
	return Vector3(VStage.hash(k), VStage.hash(k + Vector2(17.3, 3.1)), VStage.hash(k + Vector2(5.7, 29.9))) * 2.0 - Vector3.ONE


## A wall vertex pushed back into the rock (never into the passage) by a crag field: big, slow
## alcoves and buttresses plus small breaks, and band heights broken up so no line runs level.
static func _crag(p: Vector3, s: float, m: int) -> Vector3:
	if m == 0 or m >= BANDS.size() - 1:
		return p
	var j := _jit(p, 3.0 + s)
	var slow := 0.5 + 0.5 * sin(p.y * 0.045 + s * 1.7 + float(m) * 0.6)
	var slow2 := 0.5 + 0.5 * sin(p.y * 0.013 + s * 0.9 + float(m) * 1.3)
	# the walls lean back as they rise (a canyon is a V, not a slot), with alcoves and buttresses
	var lean := maxf(0.0, p.z - FLOOR) * 0.14
	return p + Vector3(s * (absf(j.x) * 3.5 + slow * 5.0 + slow2 * 6.0 + lean), j.y * 1.2, j.z * 3.5)


## A facet's shade: lit from above (and a little from the front), with a per-facet drift, so
## neighbouring faces of one rock never share a flat colour.
static func _facet(base: Color, a: Vector3, b: Vector3, c: Vector3, dir: Vector3) -> Color:
	var n := (b - a).cross(c - a).normalized()
	if n.dot(dir) < 0.0:
		n = -n
	var lit := clampf(n.z * 0.5 + 0.5, 0.0, 1.0) * 0.22 - 0.08
	var drift := VStage.hash(Vector2((a.x + b.y) * 0.71, (c.z + a.y) * 0.37)) * 0.1 - 0.05
	var k := lit + drift
	return base.lightened(k) if k > 0.0 else base.darkened(-k)


## A box of rock from `a` to `b` broken into irregular facets (cells of about `cell` units, every
## corner nudged by up to `amp`), then `keep` moves each point back out of the way through, so
## what you see never reaches into the space you can fly. Low poly, but no flat slab faces.
static func _rock(acc: Terrain.Acc, a: Vector3, b: Vector3, col: Color, seed: float, keep: Callable, cell := 7.0, amp := 2.4) -> void:
	var c := (a + b) / 2.0
	var size := b - a
	var n := Vector3i(maxi(1, ceili(size.x / cell)), maxi(1, ceili(size.y / cell)), maxi(1, ceili(size.z / cell)))
	var pt := func(v: Vector3) -> Vector3:
		var on_edge := Vector3(float(is_equal_approx(v.x, a.x) or is_equal_approx(v.x, b.x)), float(is_equal_approx(v.y, a.y) or is_equal_approx(v.y, b.y)), float(is_equal_approx(v.z, a.z) or is_equal_approx(v.z, b.z)))
		var j := VRun._jit(v, seed) * amp
		# the box's corners and edges round off a little more than its faces
		var out := (v - c).normalized() * amp * 0.35 * (on_edge.x + on_edge.y + on_edge.z - 1.0)
		return keep.call(v + j - out)
	# faces: axis it faces along, the sign, and the two axes across it
	for f in [[0, -1.0], [0, 1.0], [1, -1.0], [1, 1.0], [2, -1.0], [2, 1.0]]:
		var ax: int = f[0]
		# never seen: the back (the camera always looks along the canyon) and an underside buried
		# in the floor
		if (ax == 1 and f[1] > 0.0) or (ax == 2 and f[1] < 0.0 and a.z < FLOOR):
			continue
		var u_ax := (ax + 1) % 3
		var v_ax := (ax + 2) % 3
		var dir := Vector3.ZERO
		dir[ax] = f[1]
		var plane: float = b[ax] if f[1] > 0.0 else a[ax]
		var nu: int = n[u_ax]
		var nv: int = n[v_ax]
		for i in nu:
			for k in nv:
				var q := []
				for e in [[i, k], [i + 1, k], [i + 1, k + 1], [i, k + 1]]:
					var v := Vector3.ZERO
					v[ax] = plane
					v[u_ax] = lerpf(a[u_ax], b[u_ax], float(e[0]) / nu)
					v[v_ax] = lerpf(a[v_ax], b[v_ax], float(e[1]) / nv)
					q.append(pt.call(v))
				for t in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
					acc.tri(t[0], t[1], t[2], _facet(col, t[0], t[1], t[2], dir), dir)


## A box of rock from `a` to `b` (min and max corners), shaded per face.
static func _box(acc: Terrain.Acc, a: Vector3, b: Vector3, col: Color) -> void:
	var c := (a + b) / 2.0
	var p := func(i: int) -> Vector3: return Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z)
	for f in [[0, 1, 3, 2, 0.0], [4, 5, 7, 6, 0.0], [0, 1, 5, 4, 0.12], [2, 3, 7, 6, 0.0], [0, 2, 6, 4, 0.06], [1, 3, 7, 5, 0.06]]:
		var k: Color = col.darkened(f[4])
		acc.convex(p.call(f[0]), p.call(f[1]), p.call(f[2]), k, c)
		acc.convex(p.call(f[0]), p.call(f[2]), p.call(f[3]), k, c)


## A thin glowing seam (the edge of the way through) on an obstacle's near face.
static func _bar(lip: Terrain.Acc, a: Vector3, b: Vector3) -> void:
	_box(lip, a, b, Color.WHITE)


static var _sphere_tris: Array = []


## A unit sphere as 32 flat facets (an octahedron split once).
static func _sphere() -> Array:
	if not _sphere_tris.is_empty():
		return _sphere_tris
	var v := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]
	var oct := []
	for a in [0, 1]:
		for b in [2, 3]:
			for c in [4, 5]:
				oct.append([v[a], v[b], v[c]])
	for t in oct:
		var ab: Vector3 = (t[0] + t[1]).normalized()
		var bc: Vector3 = (t[1] + t[2]).normalized()
		var ca: Vector3 = (t[2] + t[0]).normalized()
		_sphere_tris.append_array([[t[0], ab, ca], [ab, t[1], bc], [ca, bc, t[2]], [ab, bc, ca]])
	return _sphere_tris


## A rock concretion: a lumpy, flat-shaded ellipsoid centred on `c` with radii `r`. The lumps only
## dent it inwards, so it never pokes past its radii (what you see is never bigger than the rock
## you can hit).
static func _blob(acc: Terrain.Acc, c: Vector3, r: Vector3, col: Color, seed: float) -> void:
	for t in _sphere():
		var q := []
		for v in t:
			var j := 0.8 + 0.2 * VStage.hash(Vector2(v.x * 7.1 + v.z * 3.3 + seed, v.y * 5.7 - v.z + seed * 0.37))
			q.append(c + Vector3(v.x * r.x, v.y * r.y, v.z * r.z) * j)
		var tone := col.darkened(VStage.hash(Vector2(seed, (t[0] + t[1]).x * 3.0 + t[2].z)) * 0.12)
		acc.convex(q[0], q[1], q[2], tone, c)


## A colour for concretion `i` of an obstacle: the canyon's face with a little drift.
static func _tone(pal: Dictionary, seed: float) -> Color:
	return Color(pal.c_face).lerp(Color(pal.c_top), 0.4 + VStage.hash(Vector2(seed, 1.3)) * 0.4).lightened(0.12)


## Soft light shining through an obstacle's way through, seen from behind the ship: the brightest
## thing ahead is always the gap, so you know early whether to climb, dive or slide. Returns
## {node, size} (size 0 for obstacles you dodge sideways).
static func gap_light(o: Dictionary) -> Dictionary:
	var p := passage(o.u)
	var at := Vector3.ZERO
	var size := Vector2.ZERO
	match o.k:
		"arch":
			var top := under(o, p.x)
			at = Vector3(sx(p.x), o.u + DEPTH, (FLOOR + top) / 2.0)
			size = Vector2(p.y * 2.2, (top - FLOOR) * 1.5)
		"spine":
			var low := crest(o, p.x)
			at = Vector3(sx(p.x), o.u + DEPTH, (low + RIM) / 2.0)
			size = Vector2(p.y * 2.2, (RIM - low) * 1.5)
		"window":
			var h := hole(o)
			at = Vector3(sx(h.x), o.u + DEPTH, h.y)
			size = Vector2(o.hw * 3.4, o.hh * 3.4)
	if size.x <= 0.0:
		return {node = null, size = size}
	var g := Models.glow("b89a74", 1.0)
	g.scale = Vector3(size.x, size.y, 1.0)
	g.rotation.x = PI / 2.0
	g.position = at
	return {node = g, size = size}


static func _obstacle(rock: Terrain.Acc, lip: Terrain.Acc, o: Dictionary, pal: Dictionary) -> void:
	var p := passage(o.u)
	var col := Color(pal.c_face).darkened(0.1)
	var y0: float = o.u - DEPTH / 2.0
	var y1: float = o.u + DEPTH / 2.0
	var xl := sx(p.x - p.y - 10.0)
	var xr := sx(p.x + p.y + 10.0)
	# the seams sit in front of the lumps, on the exact edge of the way through
	var f := y0 - 2.6
	var sd: float = o.u * 0.173
	match o.k:
		"pillar":
			# a rock spire: a faceted column on an oval footprint (never outside the rock you can
			# hit), narrowing and leaning a little as it rises, with a broken top above the rim
			var cx := sx(p.x + o.dx)
			var r: float = o.r
			var hl := half(o)
			var top := RIM + 8.0 + VStage.hash(Vector2(sd, 3.0)) * 14.0
			var keep := func(v: Vector3) -> Vector3:
				var t := clampf((v.z - FLOOR) / (top - FLOOR), 0.0, 1.0)
				# bulges and necks up its height, like a hoodoo worn by wind
				var w := (1.0 - 0.3 * t * t) * (0.78 + 0.14 * sin(v.z * 0.21 + sd) + 0.08 * sin(v.z * 0.57 + sd * 3.0))
				var c := Vector2(cx + sin(t * 2.0 + sd) * r * 0.12 * t, o.u)
				var d := Vector2(v.x, v.y) - c
				var e := sqrt(pow(d.x / (r * w), 2.0) + pow(d.y / (hl * w), 2.0))
				if e > 1.0:
					d /= e
				return Vector3(c.x + d.x, c.y + d.y, v.z)
			_rock(rock, Vector3(cx - r, o.u - hl, FLOOR - 4.0), Vector3(cx + r, o.u + hl, top), Color(pal.c_face).lerp(Color(pal.c_top), 0.35), sd, keep, 4.0, 1.6)
		"mesa":
			# a tall island of rock splitting the basin in two: faceted crags leaning in towards
			# the top (never wider than the rock you can hit), the canyon's glowing lip on top
			var cx := sx(p.x + o.dx)
			var r: float = o.r
			var m0: float = o.u - o.len / 2.0
			var m1: float = o.u + o.len / 2.0
			var keep := func(v: Vector3) -> Vector3:
				var lean := clampf((v.z - FLOOR) / (RIM - FLOOR), 0.0, 1.0) * 3.0
				v.x = clampf(v.x, cx - r + lean * 0.3, cx + r - lean * 0.3)
				v.y = maxf(v.y, m0 - 1.5)
				return v
			_rock(rock, Vector3(cx - r, m0, FLOOR - 4.0), Vector3(cx + r, m1, RIM), col, sd, keep, 10.0, 3.0)
			# a few big concretions at its prow, where you choose a side
			for i in 5:
				var bz := lerpf(FLOOR + 6.0, RIM - 8.0, (i + 0.5) / 5.0)
				var br := 5.0 + VStage.hash(Vector2(sd, i * 2.3)) * 3.0
				var bx := cx + (VStage.hash(Vector2(sd * 1.7, i)) - 0.5) * (r - br) * 1.6
				_blob(rock, Vector3(bx, m0 + 1.0, bz), Vector3(br, 3.0, br * 1.2), _tone(pal, sd + i), sd + i * 1.3)
			for s in [-1.0, 1.0]:
				_bar(lip, Vector3(cx + s * r - 0.45, m0, RIM), Vector3(cx + s * r + 0.45, m1, RIM + 0.4))
			_bar(lip, Vector3(cx - r, m0 - 0.45, RIM), Vector3(cx + r, m0 + 0.45, RIM + 0.4))
		"arch":
			# a natural bridge: thinnest mid-canyon, its underside arching up there and its top
			# dipping, all broken into facets; nothing below the underside you can hit
			var keep := func(v: Vector3) -> Vector3:
				var t := clampf((v.x - sx(p.x)) / p.y, -1.0, 1.0)
				v.z = maxf(v.z, VRun.under(o, v.x + 63.0))
				v.z = minf(v.z, RIM + 6.0 - 14.0 * (1.0 - t * t) + VRun._jit(v, sd).z * 2.0)
				return v
			_rock(rock, Vector3(xl, y0, o.z), Vector3(xr, y1, RIM + 6.0), col, sd, keep, 6.0, 2.2)
			_seam(lip, o, f, xl, xr, func(x: float) -> float: return VRun.under(o, x + 63.0), 0.7)
		"spine":
			# a ridge rising from the floor, its crest a saddle that dips mid-canyon
			var keep := func(v: Vector3) -> Vector3:
				v.z = minf(v.z, VRun.crest(o, v.x + 63.0))
				return v
			_rock(rock, Vector3(xl, y0, FLOOR - 4.0), Vector3(xr, y1, o.z), col, sd, keep, 6.0, 2.2)
			_seam(lip, o, f, xl, xr, func(x: float) -> float: return VRun.crest(o, x + 63.0), -0.7)
		"window":
			_eroded(rock, lip, o, col, sd, xl, xr, y0, y1, f)

## A glowing seam along a curved edge (a bridge's underside or a ridge's crest) on the obstacle's
## near face, `w` thick on the rock's side of the edge.
static func _seam(lip: Terrain.Acc, o: Dictionary, f: float, x0: float, x1: float, edge: Callable, w: float) -> void:
	var x := x0
	while x < x1 - 0.01:
		var xb := minf(x + 4.0, x1)
		var za: float = edge.call(x)
		var zb: float = edge.call(xb)
		var d := Vector3(0, -1, 0)
		lip.tri(Vector3(x, f, za), Vector3(xb, f, zb), Vector3(xb, f, zb + w), Color.WHITE, d)
		lip.tri(Vector3(x, f, za), Vector3(xb, f, zb + w), Vector3(x, f, za + w), Color.WHITE, d)
		x = xb


## A wall of rock with one oval hole worn through it: rings of facets round the hole out to the
## canyon's walls, floor and rim, and the hole's own worn sides through the wall's depth. Nothing
## inside the oval you can fly through.
static func _eroded(rock: Terrain.Acc, lip: Terrain.Acc, o: Dictionary, col: Color, sd: float, xl: float, xr: float, y0: float, y1: float, f: float) -> void:
	var h := hole(o)
	var cx := sx(h.x)
	var cz: float = h.y
	const SEG := 20
	var rings := HOLE_RINGS
	# the worn face flares out towards the ship into a rock funnel (ring `r` sits FUNNEL[r]
	# before the wall); `y` past the front is measured from the ring's own place
	var pt := func(i: int, ring: int, y: float) -> Vector3:
		var a := TAU * float(i % SEG) / SEG
		var k: float = rings[ring]
		var yr: float = y - float(FUNNEL[ring]) if y < y1 - 0.1 else y
		var v := Vector3(cx + cos(a) * o.hw * k, yr, cz + sin(a) * o.hh * k)
		var j := VRun._jit(Vector3(v.x, y0, v.z), sd)
		# the rock only wears outwards, so it never sticks into the way the collision allows
		v += Vector3(cos(a), 0, sin(a)) * absf(j.x) * (1.6 if ring == 0 else 2.4)
		if ring > 0:
			v += Vector3(-sin(a), 0, cos(a)) * j.z * 1.5 + Vector3(0, j.y * 1.2, 0)
		v.x = clampf(v.x, xl, xr)
		v.z = clampf(v.z, FLOOR - 4.0, RIM + 6.0)
		return v
	var front := Vector3(0, -1, 0)
	for ring in rings.size() - 1:
		for i in SEG:
			var a: Vector3 = pt.call(i, ring, y0)
			var b: Vector3 = pt.call(i + 1, ring, y0)
			var c: Vector3 = pt.call(i + 1, ring + 1, y0)
			var d: Vector3 = pt.call(i, ring + 1, y0)
			# the funnel catches more light towards the hole, so its cone reads at a glance
			var fc := col.lightened(0.16 * (1.0 - float(ring) / (rings.size() - 1)))
			for t in [[a, b, c], [a, c, d]]:
				rock.tri(t[0], t[1], t[2], _facet(fc, t[0], t[1], t[2], front), front)
	# the hole's sides, through the wall
	for i in SEG:
		var a: Vector3 = pt.call(i, 0, y0)
		var b: Vector3 = pt.call(i + 1, 0, y0)
		var c: Vector3 = pt.call(i + 1, 0, y1)
		var d: Vector3 = pt.call(i, 0, y1)
		var inward := Vector3(cx, (y0 + y1) / 2.0, cz) - (a + b) / 2.0
		inward.y = 0.0
		for t in [[a, b, c], [a, c, d]]:
			rock.tri(t[0], t[1], t[2], _facet(col.lightened(0.08), t[0], t[1], t[2], inward), inward)
	# the outer edge of the wall, back into the canyon's sides (hidden in the walls, floor and rim)
	for i in SEG:
		var a: Vector3 = pt.call(i, rings.size() - 1, y0)
		var b: Vector3 = pt.call(i + 1, rings.size() - 1, y0)
		var bb := Vector3(b.x, y1, b.z)
		var ab := Vector3(a.x, y1, a.z)
		rock.tri(a, b, bb, col.darkened(0.2), Vector3(a.x - cx, 0, a.z - cz))
		rock.tri(a, bb, ab, col.darkened(0.2), Vector3(a.x - cx, 0, a.z - cz))
	# a glowing seam round the hole's rim
	for i in SEG:
		var a: Vector3 = pt.call(i, 0, y0)
		var b: Vector3 = pt.call(i + 1, 0, y0)
		var ao := cx + (a.x - cx) * 1.06
		var bo := cx + (b.x - cx) * 1.06
		var az := cz + (a.z - cz) * 1.06
		var bz := cz + (b.z - cz) * 1.06
		lip.tri(Vector3(a.x, f, a.z), Vector3(b.x, f, b.z), Vector3(bo, f, bz), Color.WHITE, front)
		lip.tri(Vector3(a.x, f, a.z), Vector3(bo, f, bz), Vector3(ao, f, az), Color.WHITE, front)


## A row of concretions along an edge at height `z`, from x0 to x1, on the near face (y0). `s` is
## the side the rock is on (1: above the edge, an underside; -1: below it, a crest): the lumps sit
## on that side and touch the edge at most.
static func _lumps(acc: Terrain.Acc, pal: Dictionary, x0: float, x1: float, y0: float, z: float, s: float, sd: float, k := 1.0) -> void:
	var x := x0
	var i := 0
	while x < x1:
		var rx := (4.0 + VStage.hash(Vector2(sd, i)) * 3.5 + VStage.hash(Vector2(sd, i + 21.0)) * 4.0) * k
		var rz := (3.0 + VStage.hash(Vector2(sd, i + 7.0)) * 2.5) * k
		var lift := VStage.hash(Vector2(sd, i + 13.0)) * 2.0
		_blob(acc, Vector3(x + rx, y0 - 0.2, z + s * (rz + lift)), Vector3(rx, 2.6, rz), _tone(pal, sd + i), sd + i * 1.9)
		x += rx * 1.6
		i += 1
