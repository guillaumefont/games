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

const LEN := 2100.0
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

## The passage: [u, centre x, half width], eased between keys. Wide (off screen) at both ends.
const PATH := [[-400.0, 63.0, 100.0], [0.0, 63.0, 100.0], [160.0, 63.0, 32.0], [300.0, 52.0, 30.0], [460.0, 76.0, 30.0],
	[600.0, 63.0, 30.0], [1040.0, 63.0, 30.0], [1130.0, 50.0, 21.0], [1220.0, 84.0, 20.0], [1310.0, 44.0, 20.0],
	[1420.0, 80.0, 22.0], [1520.0, 63.0, 30.0], [1880.0, 63.0, 32.0], [2030.0, 63.0, 100.0], [2800.0, 63.0, 100.0]]

## Obstacles: pillars (dodge sideways), arches (dive under: rock above z), spines (climb over:
## rock below z) and windows (a wall with one hole to thread). dx is from the passage centre.
const OBS := [
	{u = 250.0, k = "pillar", dx = -11.0, r = 7.0},
	{u = 340.0, k = "pillar", dx = 12.0, r = 7.0},
	{u = 430.0, k = "pillar", dx = -10.0, r = 7.0},
	{u = 560.0, k = "arch", z = -12.0},
	{u = 650.0, k = "arch", z = -18.0},
	{u = 750.0, k = "spine", z = -8.0},
	{u = 840.0, k = "spine", z = 2.0},
	{u = 930.0, k = "arch", z = -6.0},
	{u = 1010.0, k = "spine", z = -4.0},
	{u = 1265.0, k = "arch", z = -10.0},
	{u = 1360.0, k = "spine", z = -14.0},
	{u = 1630.0, k = "window", dx = 10.0, z = -12.0, hw = 9.0, hh = 8.0},
	{u = 1770.0, k = "window", dx = -11.0, z = 8.0, hw = 9.0, hh = 8.0},
]


## Stage x to world x (as `X()` in vgame.gd).
static func sx(x: float) -> float:
	return x - 63.0


## Canyon speed (course units per tick) at `u`: builds up through the run, eases off at the exit
## so the stage's own scroll can take over.
static func speed(u: float) -> float:
	if u > LEN - 220.0:
		return lerpf(3.3, 1.2, clampf((u - (LEN - 220.0)) / 220.0, 0.0, 1.0))
	return lerpf(2.2, 3.3, clampf(u / 1500.0, 0.0, 1.0))


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
	return smoothstep(-150.0, 30.0, u) * (1.0 - smoothstep(LEN - 250.0, LEN - 40.0, u))


## The hole of a window obstacle: centre x, centre z.
static func hole(o: Dictionary) -> Vector2:
	return Vector2(passage(o.u).x + o.dx, o.z)


## What the ship (a point, padded by `pad`) hits between `u0` and `u1`: "" for nothing, "wall",
## or the obstacle's kind.
static func hit(x: float, z: float, u0: float, u1: float, pad: float) -> String:
	var p := passage(u1)
	if x - pad < p.x - p.y or x + pad > p.x + p.y:
		return "wall"
	for o in OBS:
		if o.u + DEPTH / 2.0 < u0 or o.u - DEPTH / 2.0 > u1:
			continue
		if _solid(o, x, z, pad):
			return o.k
	return ""


static func _solid(o: Dictionary, x: float, z: float, pad: float) -> bool:
	match o.k:
		"pillar":
			return absf(x - (passage(o.u).x + o.dx)) < o.r + pad
		"arch":
			return z + pad > o.z
		"spine":
			return z - pad < o.z
		"window":
			var h := hole(o)
			return absf(x - h.x) > o.hw - pad or absf(z - h.y) > o.hh - pad
	return false


## Distance from the ship to the nearest rock at `u` (walls and obstacles it is passing), for the
## scrape bonus.
static func clearance(x: float, z: float, u: float) -> float:
	var p := passage(u)
	var d := minf(x - (p.x - p.y), p.x + p.y - x)
	d = minf(d, z - FLOOR)
	for o in OBS:
		if absf(o.u - u) > DEPTH:
			continue
		match o.k:
			"pillar":
				d = minf(d, absf(x - (p.x + o.dx)) - o.r)
			"arch":
				d = minf(d, o.z - z)
			"spine":
				d = minf(d, z - o.z)
			"window":
				var h := hole(o)
				d = minf(d, minf(o.hw - absf(x - h.x), o.hh - absf(z - h.y)))
	return d


## A safe racing line at `u`: (x, z) set up for the next obstacle well before it and held
## until the ship is through it.
static func line(u: float) -> Vector2:
	var p := passage(u)
	var dx := 0.0
	var z := -4.0
	for o in OBS:
		if o.u + DEPTH / 2.0 + 3.0 < u:
			continue
		if o.u - u < 100.0:
			match o.k:
				"pillar":
					dx = 9.0 if o.dx < 0.0 else -9.0
				"arch":
					z = o.z - 9.0
				"spine":
					z = o.z + 9.0
				"window":
					dx = o.dx
					z = o.z
		break
	return Vector2(clampf(p.x + dx, p.x - p.y + 7.0, p.x + p.y - 7.0), z)


## Crystal motes along the racing line: they show the way and pay points. [u, x, z] each.
static func motes() -> Array:
	var out := []
	var u := 180.0
	while u < LEN - 240.0:
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
	const SLICE := 100.0
	const ROW := 10.0

	func _init(pal: Dictionary, mats: Dictionary) -> void:
		_pal = pal
		_mats = mats
		node.name = "CanyonRun"

	func step() -> bool:
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
				VRun._obstacle(rock, lip, o, _pal)
		if rock.count() > 0:
			node.add_child(Terrain._mi(rock.mesh(), _mats.ground, true))
		if lip.count() > 0:
			node.add_child(Terrain._mi(lip.mesh(), _mats.lip, false))
		if glow.count() > 0:
			node.add_child(Terrain._mi(glow.mesh(), _mats.glow, false))
		_u += SLICE
		return _u >= VRun.LEN + 300.0


## Heights of the wall's bands, floor to rim, and how far each juts back into the rock.
const BANDS := [FLOOR - 6.0, -26.0, -12.0, 2.0, 18.0, RIM]


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
			var a := Vector3(ea + s * ja, u0, za)
			var b := Vector3(eb + s * jb, u1, za)
			var c := Vector3(ea + s * ka, u0, zb)
			var d := Vector3(eb + s * kb, u1, zb)
			var col := Color(pal.c_face).lightened(0.12).darkened(float(BANDS.size() - 2 - m) * 0.1)
			if m % 2 == 1:
				col = col.lightened(0.08)
			var jit := VStage.hash(Vector2(u0 * 0.37, m + s)) - 0.5
			col = col.lightened(jit * 0.1) if jit > 0.0 else col.darkened(-jit * 0.12)
			var out := Vector3(-s, 0, 0)
			rock.tri(a, b, d, col, out)
			rock.tri(a, d, c, col.darkened(0.05), out)
		# the rim: a faceted top running back over the moon, so nothing shows past it
		var offs := [0.0, 6.0, 22.0, 60.0, 180.0]
		for k in offs.size() - 1:
			var za2 := RIM + (VStage.hash(Vector2(u0, k + s * 5.0)) - 0.5) * 3.0 if k > 0 else RIM
			var zb2 := RIM + (VStage.hash(Vector2(u1, k + s * 5.0)) - 0.5) * 3.0 if k > 0 else RIM
			var za3 := RIM + (VStage.hash(Vector2(u0, k + 1 + s * 5.0)) - 0.5) * 3.0
			var zb3 := RIM + (VStage.hash(Vector2(u1, k + 1 + s * 5.0)) - 0.5) * 3.0
			var a := Vector3(ea + s * offs[k], u0, za2)
			var b := Vector3(eb + s * offs[k], u1, zb2)
			var c := Vector3(ea + s * offs[k + 1], u0, za3)
			var d := Vector3(eb + s * offs[k + 1], u1, zb3)
			var col := Color(pal.c_top).lerp(Color(pal.c_top2), float(k) / offs.size())
			rock.tri(a, b, d, col, Vector3.BACK)
			rock.tri(a, d, c, col.darkened(0.05), Vector3.BACK)
		# the glowing lip on the rim edge (what the top-down view reads as the wall)
		lip.tri(Vector3(ea, u0, RIM + 0.3), Vector3(eb, u1, RIM + 0.3), Vector3(eb + s * 0.9, u1, RIM + 0.3), Color.WHITE, Vector3.BACK)
		lip.tri(Vector3(ea, u0, RIM + 0.3), Vector3(eb + s * 0.9, u1, RIM + 0.3), Vector3(ea + s * 0.9, u0, RIM + 0.3), Color.WHITE, Vector3.BACK)
	# the floor, a little wider than the passage so its edges tuck under the walls
	var cols := 6
	for i in cols:
		var ta := float(i) / cols
		var tb := float(i + 1) / cols
		var xa0 := sx(pa.x - pa.y - 4.0 + (pa.y * 2.0 + 8.0) * ta)
		var xa1 := sx(pa.x - pa.y - 4.0 + (pa.y * 2.0 + 8.0) * tb)
		var xb0 := sx(pb.x - pb.y - 4.0 + (pb.y * 2.0 + 8.0) * ta)
		var xb1 := sx(pb.x - pb.y - 4.0 + (pb.y * 2.0 + 8.0) * tb)
		var h := func(uu: float, ii: int) -> float: return FLOOR + (VStage.hash(Vector2(uu * 0.1, ii)) - 0.5) * 1.6
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
			var z := FLOOR + 1.0
			glow.tri(Vector3(x0, u0, z), Vector3(x1, u0, z), Vector3(x1, u0 + 1.4, z), Color.WHITE, Vector3.BACK)
			glow.tri(Vector3(x0, u0, z), Vector3(x1, u0 + 1.4, z), Vector3(x0, u0 + 1.4, z), Color.WHITE, Vector3.BACK)


## A box of rock from `a` to `b` (min and max corners), shaded per face.
static func _box(acc: Terrain.Acc, a: Vector3, b: Vector3, col: Color) -> void:
	var c := (a + b) / 2.0
	var p := func(i: int) -> Vector3: return Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z)
	for f in [[0, 1, 3, 2, 0.0], [4, 5, 7, 6, 0.0], [0, 1, 5, 4, 0.12], [2, 3, 7, 6, 0.0], [0, 2, 6, 4, 0.06], [1, 3, 7, 5, 0.06]]:
		var k: Color = col.darkened(f[4])
		acc.convex(p.call(f[0]), p.call(f[1]), p.call(f[2]), k, c)
		acc.convex(p.call(f[0]), p.call(f[2]), p.call(f[3]), k, c)


## A thin glowing bar (the edges that read as "danger here") on an obstacle's near face.
static func _bar(lip: Terrain.Acc, a: Vector3, b: Vector3) -> void:
	_box(lip, a, b, Color.WHITE)


static func _obstacle(rock: Terrain.Acc, lip: Terrain.Acc, o: Dictionary, pal: Dictionary) -> void:
	var p := passage(o.u)
	var col := Color(pal.c_face).lightened(0.05)
	var y0: float = o.u - DEPTH / 2.0
	var y1: float = o.u + DEPTH / 2.0
	var xl := sx(p.x - p.y - 10.0)
	var xr := sx(p.x + p.y + 10.0)
	var f := y0 - 0.4
	match o.k:
		"pillar":
			var cx := sx(p.x + o.dx)
			var r: float = o.r
			# a hexagonal column, rim to floor
			var pts := []
			for j in 6:
				var a := TAU * (j + 0.5) / 6.0
				pts.append(Vector2(cx + cos(a) * r, o.u + sin(a) * r))
			var ctr := Vector3(cx, o.u, (FLOOR + RIM) / 2.0)
			for j in 6:
				var q0: Vector2 = pts[j]
				var q1: Vector2 = pts[(j + 1) % 6]
				var shade := col.darkened(0.1 * absf(sin(TAU * j / 6.0)))
				rock.convex(Vector3(q0.x, q0.y, FLOOR - 4), Vector3(q1.x, q1.y, FLOOR - 4), Vector3(q1.x, q1.y, RIM + 6), shade, ctr)
				rock.convex(Vector3(q0.x, q0.y, FLOOR - 4), Vector3(q1.x, q1.y, RIM + 6), Vector3(q0.x, q0.y, RIM + 6), shade, ctr)
			for s in [-1.0, 1.0]:
				_bar(lip, Vector3(cx + s * r * 0.87 - 0.5, o.u - r * 0.5 - 0.6, FLOOR), Vector3(cx + s * r * 0.87 + 0.5, o.u - r * 0.5, RIM))
		"arch":
			_box(rock, Vector3(xl, y0, o.z), Vector3(xr, y1, RIM + 4.0), col)
			_bar(lip, Vector3(xl, f, o.z), Vector3(xr, y0, o.z + 1.0))
		"spine":
			_box(rock, Vector3(xl, y0, FLOOR - 4.0), Vector3(xr, y1, o.z), col)
			_bar(lip, Vector3(xl, f, o.z - 1.0), Vector3(xr, y0, o.z))
		"window":
			var h := hole(o)
			var hx0 := sx(h.x - o.hw)
			var hx1 := sx(h.x + o.hw)
			var hz0: float = h.y - o.hh
			var hz1: float = h.y + o.hh
			_box(rock, Vector3(xl, y0, FLOOR - 4.0), Vector3(hx0, y1, RIM + 4.0), col)
			_box(rock, Vector3(hx1, y0, FLOOR - 4.0), Vector3(xr, y1, RIM + 4.0), col)
			_box(rock, Vector3(hx0, y0, FLOOR - 4.0), Vector3(hx1, y1, hz0), col)
			_box(rock, Vector3(hx0, y0, hz1), Vector3(hx1, y1, RIM + 4.0), col)
			# a glowing frame round the hole
			_bar(lip, Vector3(hx0 - 1.0, f, hz0 - 1.0), Vector3(hx1 + 1.0, y0, hz0))
			_bar(lip, Vector3(hx0 - 1.0, f, hz1), Vector3(hx1 + 1.0, y0, hz1 + 1.0))
			_bar(lip, Vector3(hx0 - 1.0, f, hz0), Vector3(hx0, y0, hz1))
			_bar(lip, Vector3(hx1, f, hz0), Vector3(hx1 + 1.0, y0, hz1))
