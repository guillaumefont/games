class_name City
extends RefCounted
## Iron Sprawl's city, built into each terrain chunk (one mesh with the ground's props, plus the
## roads in the ground's own matte surface). Guillaume wanted a rich city, not one building to a
## block, with roads at a slight angle and features to spot from the air:
## - the street grid is turned by ANGLE: avenues (AVE_W wide, every AVE) run up the screen,
##   streets (STR_W wide, every STR) across it, with kerbs, centre lines and zebra crossings;
## - every third avenue carries an elevated expressway on pillars, passing over the streets;
## - roads cross the canals on real bridges (a deck that ramps up, railings, piers);
## - blocks are split into lots of varied buildings: setback towers, glass towers, brick
##   mid-rises with window grids, little shops with awnings, courtyard blocks; roofs carry
##   antennas, spires, helipads, water tanks, gardens and air-conditioning units;
## - some blocks are parks (paths, a fountain, trees, a water tower landmark), paved plazas
##   (chequered paving, an obelisk, kiosks) or, now and then, a stadium;
## - comically big cars on the avenues, the streets and the expressway.
## Then Guillaume said "this is war, the city should be grey, dark and on fire": the palette is
## ash and soot, a share of the buildings burn (glowing windows, flames and smoke on the roof),
## some are ruins of broken walls and rubble, shell craters pock the roads, burnt-out wrecks sit
## among the traffic, tank traps block the odd junction and the parks are scorched. The flames and
## smoke are listed in `fires` and drawn by `fx_mesh` (animated in its shaders, one node a chunk).
## All horizontal sizes are in world metres; heights are scaled by Models.PROP_V like every prop.

const ANGLE := 0.13
const AVE := 16.0
const STR := 14.0
const AVE_W := 4.0
const STR_W := 2.0
## How far the city's streets lie below the other worlds' plain (Guillaume, 2026-11-26: "the city
## world is very flat... it doesn't go as high as a city should"). Nothing may rise past the ship,
## so the city goes down instead, like the canyons: its towers rise from deep streets.
const SINK := 5.0
## The skyline: each SKY_SEG m of the course has its downtown, a cluster of the tallest towers
## (SKY_R m across) that falls away to low streets round it.
const SKY_SEG := 96.0
const SKY_R := 34.0
## The expressway deck's height (world), above the highest ground and under the flight altitude.
const HWY_Y := 1.9 - SINK
const HWY_W := 4.0

const CONCRETE := Color8(0x6e, 0x6e, 0x70)
const PAVING := Color8(0x7a, 0x76, 0x70)
const PARK := Color8(0x4e, 0x4c, 0x3a)   # scorched grass
const WATER := Color8(0x2a, 0x34, 0x38)
const YELLOW := Color8(0xb8, 0x9a, 0x3a)
const DARK := Color8(0x2a, 0x2c, 0x30)
const SOOT := Color8(0x26, 0x24, 0x24)
const RUBBLE := [Color8(0x6a, 0x66, 0x62), Color8(0x58, 0x54, 0x52), Color8(0x80, 0x7a, 0x72), Color8(0x4a, 0x44, 0x40)]
## Windows lit by the fire inside.
const BLAZE := Color8(0xff, 0x8a, 0x2a)
const WALLS := [Color8(0x8e, 0x8c, 0x88), Color8(0x76, 0x78, 0x7c), Color8(0x9a, 0x94, 0x8a), Color8(0x62, 0x64, 0x6a),
	Color8(0x84, 0x7a, 0x6e), Color8(0x6c, 0x6c, 0x6e)]
const GLASS_WALLS := [Color8(0x3c, 0x48, 0x52), Color8(0x34, 0x40, 0x46), Color8(0x46, 0x4e, 0x58)]
const BRICKS := [Color8(0x6e, 0x48, 0x40), Color8(0x78, 0x58, 0x4a), Color8(0x5c, 0x42, 0x3e)]
const PASTELS := [Color8(0x8c, 0x82, 0x7a), Color8(0x7e, 0x84, 0x7e), Color8(0x86, 0x7e, 0x84), Color8(0x90, 0x8a, 0x74),
	Color8(0x7a, 0x80, 0x8a), Color8(0x8a, 0x76, 0x6e)]
const SHOPS := [Color8(0x8a, 0x3a, 0x34), Color8(0x3a, 0x52, 0x70), Color8(0x8e, 0x7a, 0x3a), Color8(0x40, 0x5e, 0x44),
	Color8(0x8a, 0x5a, 0x34)]

## The flames and smoke of the chunk last built: {"p": base (world), "s": size, "smoke": bool}.
static var fires: Array = []
## The highest point smoke may reach (world), so it never hides the shots at the flight altitude.
const SMOKE_TOP := 5.3


static var _ca := cos(ANGLE)
static var _sa := sin(ANGLE)


## World (x, z) to city coordinates (u, v): the grid turned back by ANGLE.
## The city's colours, calmed: much less saturated, and every shade drawn in towards one muted
## mid grey, so the streets read as a quiet backdrop under the foes (their own colours untouched).
const CALM_TO := Color8(0x7a, 0x7c, 0x80)
const CALM_GREY := 0.5
const CALM_MID := 0.5


static func calm(col: Color) -> Color:
	var l := col.get_luminance()
	var c := col.lerp(Color(l, l, l, col.a), CALM_GREY).lerp(Color(CALM_TO, col.a), CALM_MID)
	c.a = col.a
	return c


## How far into a downtown (u, v) lies, 0 on the outskirts to 1 at its heart: the skyline's
## shape, so the towers build up to a peak and fall away instead of standing at random heights.
static func skyline(u: float, v: float) -> float:
	var p := to_world(u, v)
	var n := floori(-p.z / SKY_SEG)
	var t := 0.0
	for i in range(n - 1, n + 2):
		var at := Vector2((Models.hash2(i * 1.7 + 0.3, 2.1) - 0.5) * 22.0, -(i + 0.35 + Models.hash2(i * 0.9, 5.3) * 0.3) * SKY_SEG)
		var d := Vector2(p.x, p.z).distance_to(at) * (0.85 + Models.hash2(u * 0.11, v * 0.13) * 0.3)
		t = maxf(t, smoothstep(SKY_R, SKY_R * 0.15, d))
	return t


static func to_local(x: float, z: float) -> Vector2:
	return Vector2(x * _ca - z * _sa, x * _sa + z * _ca)


## City coordinates (u, v) to the world (y = 0): Basis(UP, ANGLE) * (u, 0, v).
static func to_world(u: float, v: float) -> Vector3:
	return Vector3(u * _ca + v * _sa, 0.0, -u * _sa + v * _ca)


## On (or within `margin` of) a road.
static func on_road(x: float, z: float, margin := 0.0) -> bool:
	var l := to_local(x, z)
	return absf(l.x - roundf(l.x / AVE) * AVE) < AVE_W * 0.5 + margin or absf(l.y - roundf(l.y / STR) * STR) < STR_W * 0.5 + margin


static func elevated(k: int) -> bool:
	return posmod(k, 3) == 1


## What one chunk of city is built from.
class Ctx:
	var b: Models.Builder
	var hgt: Callable
	var height: Callable
	var z0 := 0.0
	var z1 := 0.0
	var hw := 0.0
	## How tall (raw, before PROP_V) the building being built may reach, roof and all, so it stays
	## under the flight altitude.
	var cap := 9.0
	## The building being built is on fire (its windows glow).
	var burning := false
	var gv := []
	var gn := []
	var gc := []

	## The land's noise value, and its height (the sea and canals at 0).
	func raw(x: float, z: float) -> float:
		return hgt.call(x, z)

	func ground(x: float, z: float) -> float:
		return maxf(height.call(hgt.call(x, z)), -City.SINK)

	## A road's height: on the land, or up on a bridge deck over (and ramping off) the water.
	func road(x: float, z: float) -> float:
		var h: float = hgt.call(x, z)
		return maxf(maxf(height.call(h), -City.SINK), 0.55 * (1.0 - smoothstep(-0.03, 0.12, h)) - City.SINK)

	## Owns what is centred at world p: each chunk builds only its own, so nothing is doubled.
	func owns(p: Vector3) -> bool:
		return p.z <= z0 and p.z > z1 and absf(p.x) <= hw

	## A flat quad on the ground surface, corners in city coordinates (u, v), at heights hs (+ up).
	func lay(c: Array, hs: Array, up: float, col: Color) -> void:
		var p := []
		for k in 4:
			var w := City.to_world(c[k].x, c[k].y)
			p.append(Vector3(w.x, hs[k] + up, w.z))
		for t: Array in [[0, 1, 2], [0, 2, 3]]:
			var n: Vector3 = (p[t[1]] - p[t[0]]).cross(p[t[2]] - p[t[0]])
			# Godot's front faces wind clockwise seen from the front (as the ground's do)
			var order: Array = t if n.y < 0.0 else [t[0], t[2], t[1]]
			for k: int in order:
				gv.append(p[k])
				gn.append(Vector3.UP)
				gc.append(col)

	## A rectangle u0..u1 x v0..v1 draped on the ground in tiles of about `tile` metres.
	func pad(u0: float, u1: float, v0: float, v1: float, up: float, col: Color, tile := 2.5, col2 := Color(0, 0, 0, 0)) -> void:
		var nu := maxi(1, ceili((u1 - u0) / tile))
		var nv := maxi(1, ceili((v1 - v0) / tile))
		for i in nu:
			for j in nv:
				var a := u0 + (u1 - u0) * i / nu
				var bb := u0 + (u1 - u0) * (i + 1) / nu
				var c := v0 + (v1 - v0) * j / nv
				var d := v0 + (v1 - v0) * (j + 1) / nv
				var hs := []
				for q: Vector2 in [Vector2(a, c), Vector2(bb, c), Vector2(bb, d), Vector2(a, d)]:
					var w := City.to_world(q.x, q.y)
					hs.append(ground(w.x, w.z))
				var cc := col2 if col2.a > 0.0 and (i + j) % 2 == 1 else col
				lay([Vector2(a, c), Vector2(bb, c), Vector2(bb, d), Vector2(a, d)], hs, up, cc)

	## Draw into the city's frame at height y (world); `tall` scales heights by PROP_V.
	func frame(y := 0.0, tall := false) -> void:
		var bs := Basis(Vector3.UP, City.ANGLE)
		if tall:
			bs = bs * Basis.from_scale(Vector3(1, Models.PROP_V, 1))
		b.xf = Transform3D(bs, Vector3(0, y, 0))

	## Draw round (u, v) at height y, heights scaled by PROP_V.
	func at(u: float, v: float, y: float) -> void:
		var w := City.to_world(u, v)
		b.xf = Transform3D(Basis(Vector3.UP, City.ANGLE) * Basis.from_scale(Vector3(1, Models.PROP_V, 1)), Vector3(w.x, y, w.z))
		b.occlude(Models.AO_H)


## Builds the city on one chunk: props into `b`; returns the road and paving triangles
## [vertices, normals, colours] for the ground's own surface.
static func build(b: Models.Builder, z0: float, size: Vector2, hgt: Callable, height: Callable) -> Array:
	var c := Ctx.new()
	c.b = b
	fires.clear()
	b.bevels = false   # only the buildings' own walls get the bevelled edge
	c.hgt = hgt
	c.height = height
	c.z0 = z0
	c.z1 = z0 - size.y
	c.hw = size.x * 0.5
	# the chunk's corners in city coordinates bound what to visit
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in [Vector2(-c.hw, c.z0), Vector2(c.hw, c.z0), Vector2(-c.hw, c.z1), Vector2(c.hw, c.z1)]:
		var l := to_local(p.x, p.y)
		lo = Vector2(minf(lo.x, l.x), minf(lo.y, l.y))
		hi = Vector2(maxf(hi.x, l.x), maxf(hi.y, l.y))
	for k in range(floori(lo.x / AVE) - 1, ceili(hi.x / AVE) + 2):
		avenue(c, k, lo.y - 2.0, hi.y + 2.0)
		if elevated(k):
			expressway(c, k, lo.y - 2.0, hi.y + 2.0)
	for m in range(floori(lo.y / STR) - 1, ceili(hi.y / STR) + 2):
		street(c, m, lo.x - 2.0, hi.x + 2.0)
	for k in range(floori(lo.x / AVE) - 1, ceili(hi.x / AVE) + 1):
		for m in range(floori(lo.y / STR) - 1, ceili(hi.y / STR) + 1):
			block(c, k, m)
	b.xf = Transform3D.IDENTITY
	b.bevels = true
	return [c.gv, c.gn, c.gc]


# ---------------------------------------------------------------- roads

static func avenue(c: Ctx, k: int, v_lo: float, v_hi: float) -> void:
	var u := k * AVE
	var hw := AVE_W * 0.5
	# 2 m steps centred on even metres: a street (every STR, an even number) gets one whole step
	var v := floorf(v_lo / 2.0) * 2.0 - 1.0
	while v < v_hi:
		var vm := v + 1.0
		v += 2.0
		var mid := to_world(u, vm)
		if not c.owns(mid):
			continue
		var hs := []
		for q: Vector2 in [Vector2(u - hw, vm - 1.0), Vector2(u + hw, vm - 1.0), Vector2(u + hw, vm + 1.0), Vector2(u - hw, vm + 1.0)]:
			var w := to_world(q.x, q.y)
			hs.append(c.road(w.x, w.z))
		var quad := func(a0: float, a1: float) -> Array:
			return [Vector2(u + a0, vm - 1.0), Vector2(u + a1, vm - 1.0), Vector2(u + a1, vm + 1.0), Vector2(u + a0, vm + 1.0)]
		var across := func(a0: float, a1: float) -> Array:   # heights at a0..a1 across the road
			var f0 := (a0 + hw) / AVE_W
			var f1 := (a1 + hw) / AVE_W
			return [lerpf(hs[0], hs[1], f0), lerpf(hs[0], hs[1], f1), lerpf(hs[3], hs[2], f1), lerpf(hs[3], hs[2], f0)]
		c.lay(quad.call(-hw, hw), hs, 0.08, Models.ASPHALT)
		var to_street := absf(vm - roundf(vm / STR) * STR)
		if to_street > 1.0:
			c.lay(quad.call(-hw, -hw + 0.3), across.call(-hw, -hw + 0.3), 0.11, Models.KERB)
			c.lay(quad.call(hw - 0.3, hw), across.call(hw - 0.3, hw), 0.11, Models.KERB)
			c.lay(quad.call(-0.1, -0.04), across.call(-0.1, -0.04), 0.1, YELLOW)
			c.lay(quad.call(0.04, 0.1), across.call(0.04, 0.1), 0.1, YELLOW)
		var y: float = (hs[0] + hs[1] + hs[2] + hs[3]) * 0.25
		if c.raw(mid.x, mid.z) < 0.02:
			bridge_bits(c, true, u, vm, hw, y)
		var r := Models.hash2(u * 3.1 + 0.3, vm * 1.7)
		var dry := c.raw(mid.x, mid.z) >= 0.02
		# few cars on the roads: they were clutter under the foes
		if r < 0.05:
			var side: float = [1.4, 0.55, -0.55, -1.4][int(r * 307.0) % 4]
			var w := to_world(u + side, vm)
			if r < 0.018:
				wreck(c, Vector3(w.x, y + 0.08, w.z), ANGLE + r * 40.0, r * 22.0)
			else:
				Models.car(c.b, Vector3(w.x, y + 0.08, w.z), ANGLE + (0.0 if side > 0.0 else PI), r)
		elif r > 0.965 and dry and to_street > 3.0:
			crater(c, u + (r - 0.98) * 60.0, vm, 1.1, r)
		elif r > 0.9 and r < 0.94 and to_street > 1.0 and to_street < 3.0 and dry:
			# tank traps across the mouth of the junction
			for t in 2:
				hedgehog(c, u - 0.9 + t * 1.8, vm, y + 0.08, r + t)


static func street(c: Ctx, m: int, u_lo: float, u_hi: float) -> void:
	var v := m * STR
	var hw := STR_W * 0.5
	# 2 m steps from even metres: each wholly in or out of an avenue (whose edges are at 16k +- 2)
	var u := floorf(u_lo / 2.0) * 2.0
	while u < u_hi:
		var um := u + 1.0
		u += 2.0
		if absf(um - roundf(um / AVE) * AVE) < AVE_W * 0.5:
			continue   # the avenue covers the junction
		var mid := to_world(um, v)
		if not c.owns(mid):
			continue
		var hs := []
		for q: Vector2 in [Vector2(um - 1.0, v - hw), Vector2(um + 1.0, v - hw), Vector2(um + 1.0, v + hw), Vector2(um - 1.0, v + hw)]:
			var w := to_world(q.x, q.y)
			hs.append(c.road(w.x, w.z))
		var quad := func(a0: float, a1: float) -> Array:
			return [Vector2(um - 1.0, v + a0), Vector2(um + 1.0, v + a0), Vector2(um + 1.0, v + a1), Vector2(um - 1.0, v + a1)]
		var across := func(a0: float, a1: float) -> Array:
			var f0 := (a0 + hw) / STR_W
			var f1 := (a1 + hw) / STR_W
			return [lerpf(hs[0], hs[3], f0), lerpf(hs[1], hs[2], f0), lerpf(hs[1], hs[2], f1), lerpf(hs[0], hs[3], f1)]
		c.lay(quad.call(-hw, hw), hs, 0.08, Models.ASPHALT)
		c.lay(quad.call(-hw, -hw + 0.25), across.call(-hw, -hw + 0.25), 0.11, Models.KERB)
		c.lay(quad.call(hw - 0.25, hw), across.call(hw - 0.25, hw), 0.11, Models.KERB)
		if posmod(um, 4.0) < 2.0:
			c.lay(quad.call(-0.06, 0.06), across.call(-0.06, 0.06), 0.1, Models.PAINT)
		var y: float = (hs[0] + hs[1] + hs[2] + hs[3]) * 0.25
		if c.raw(mid.x, mid.z) < 0.02:
			bridge_bits(c, false, v, um, hw, y)
		var r := Models.hash2(um * 2.3, v * 0.7 + 0.4)
		if r < 0.035:
			var side := 0.55 if r < 0.018 else -0.55
			var w := to_world(um, v + side)
			if r < 0.012:
				wreck(c, Vector3(w.x, y + 0.08, w.z), ANGLE + r * 50.0, r * 15.0)
			else:
				Models.car(c.b, Vector3(w.x, y + 0.08, w.z), ANGLE + (PI * 0.5 if side > 0.0 else -PI * 0.5), r)
		elif r > 0.96 and c.raw(mid.x, mid.z) >= 0.02:
			crater(c, um, v, 0.9, r)


## Railings along a bridge deck and, every few metres, a pier down into the water.
## `along_v`: the road runs along v at u = `c0` (an avenue), else along u at v = `c0` (a street).
static func bridge_bits(c: Ctx, along_v: bool, c0: float, s: float, hw: float, y: float) -> void:
	Models.count("bridge")
	c.frame()
	for side in [-1.0, 1.0]:
		var o: float = c0 + side * (hw + 0.06)
		var p := Vector3(o, y + 0.26, s) if along_v else Vector3(s, y + 0.26, o)
		var sz := Vector3(0.12, 0.3, 2.02) if along_v else Vector3(2.02, 0.3, 0.12)
		c.b.box(p, sz, Color8(0xd8, 0xdc, 0xe2))
	if posmod(s + 1.0, 4.0) < 2.0:
		# a pier down to the canal's bed, under the sunken streets
		var bed := -0.5 - SINK
		var p := Vector3(c0, (y + bed) * 0.5, s) if along_v else Vector3(s, (y + bed) * 0.5, c0)
		var sz := Vector3(hw * 1.6, y - bed, 0.5) if along_v else Vector3(0.5, y - bed, hw * 1.6)
		c.b.box(p, sz, CONCRETE.darkened(0.15))


## The expressway over avenue k: a deck on pillars at HWY_Y, barriers, lane lines and traffic,
## in 8 m spans (each owned by the chunk holding its middle).
static func expressway(c: Ctx, k: int, v_lo: float, v_hi: float) -> void:
	var u := k * AVE
	var v := floorf(v_lo / 8.0) * 8.0
	while v < v_hi:
		var v0 := v
		var vm := v + 4.0
		v += 8.0
		var mid := to_world(u, vm)
		if not c.owns(mid):
			continue
		Models.count("expressway")
		c.frame()
		var b := c.b
		b.box(Vector3(u, HWY_Y - 0.14, vm), Vector3(HWY_W, 0.28, 8.02), CONCRETE)
		flat(c, u - HWY_W * 0.5 + 0.25, u + HWY_W * 0.5 - 0.25, v0, v0 + 8.0, HWY_Y + 0.005, Models.ASPHALT)
		flat(c, u - 0.1, u - 0.04, v0, v0 + 8.0, HWY_Y + 0.01, YELLOW)
		flat(c, u + 0.04, u + 0.1, v0, v0 + 8.0, HWY_Y + 0.01, YELLOW)
		for side in [-1.0, 1.0]:
			b.box(Vector3(u + side * (HWY_W * 0.5 - 0.1), HWY_Y + 0.1, vm), Vector3(0.2, 0.22, 8.02), Color8(0xd4, 0xd6, 0xda))
			for d in [1.0, 5.0]:
				flat(c, u + side * 0.8 - 0.04, u + side * 0.8 + 0.04, v0 + d, v0 + d + 2.0, HWY_Y + 0.01, Models.PAINT)
		var g := c.ground(mid.x, mid.z)
		b.box(Vector3(u, (g + HWY_Y - 0.3) * 0.5 - 0.15, vm), Vector3(0.7, HWY_Y - g, 0.7), CONCRETE.darkened(0.08))
		b.box(Vector3(u, HWY_Y - 0.36, vm), Vector3(HWY_W - 0.4, 0.2, 0.6), CONCRETE.darkened(0.12))
		for i in 4:
			var r := Models.hash2(u * 1.9 + 7.0, (v0 + i * 2.0) * 2.9)
			if r < 0.22:
				var lane: float = [-1.25, -0.45, 0.45, 1.25][int(r * 18.0) % 4]
				var w := to_world(u + lane, v0 + 1.0 + i * 2.0)
				Models.car(c.b, Vector3(w.x, HWY_Y + 0.01, w.z), ANGLE + (0.0 if lane > 0.0 else PI), r)
				c.frame()


## A flat level rectangle u0..u1 x v0..v1 at world height y (top face only).
static func flat(c: Ctx, u0: float, u1: float, v0: float, v1: float, y: float, col: Color) -> void:
	c.b.quad(Vector3(u0, y, v0), Vector3(u1, y, v0), Vector3(u1, y, v1), Vector3(u0, y, v1), col, Vector3.UP)


# ---------------------------------------------------------------- blocks

static func block(c: Ctx, k: int, m: int) -> void:
	var u0 := k * AVE + AVE_W * 0.5
	var u1 := (k + 1) * AVE - AVE_W * 0.5
	var v0 := m * STR + STR_W * 0.5
	var v1 := (m + 1) * STR - STR_W * 0.5
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	var mid := to_world(cu, cv)
	if not c.owns(mid):
		return
	if c.raw(mid.x, mid.z) < 0.03:
		# a canal runs through it: trees on its grassy banks
		for i in 6:
			var tu := lerpf(u0 + 1.0, u1 - 1.0, Models.hash2(k * 1.1 + i, m * 0.9))
			var tv := lerpf(v0 + 1.0, v1 - 1.0, Models.hash2(m * 1.3 + i, k * 0.7 + i))
			var w := to_world(tu, tv)
			if c.raw(w.x, w.z) > 0.06:
				tree(c, tu, tv, c.ground(w.x, w.z), 0.9, tu)
		return
	var hb := Models.hash2(k * 7.31 + 0.5, m * 3.17 + 0.5)
	var dry := true
	for q: Vector2 in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
		var w := to_world(q.x, q.y)
		dry = dry and c.raw(w.x, w.z) > 0.02
	if hb < 0.1:
		park(c, u0, u1, v0, v1, hb * 10.0)
	elif hb < 0.16:
		plaza(c, u0, u1, v0, v1, (hb - 0.1) / 0.06)
	elif hb < 0.2 and dry:
		stadium(c, u0, u1, v0, v1)
	else:
		lots(c, k, m, u0, u1, v0, v1, hb)


## A built block: a sidewalk all round, then a grid of lots (or a courtyard ring) of buildings.
static func lots(c: Ctx, k: int, m: int, u0: float, u1: float, v0: float, v1: float, hb: float) -> void:
	c.pad(u0, u1, v0, v1, 0.16, Models.KERB.darkened(0.08), 2.0)
	var i0 := u0 + 0.5
	var i1 := u1 - 0.5
	var j0 := v0 + 0.5
	var j1 := v1 - 0.5
	# the skyline: towers climb to each stretch's downtown, lower streets round it
	var tall := skyline((u0 + u1) * 0.5, (v0 + v1) * 0.5)
	var sd := Models.hash2(k * 1.7 + 4.0, m * 5.3 + 1.0)
	if sd < 0.22:
		# a courtyard block: four wings round a green court with a tree
		var d := 2.6
		var col: Color = (BRICKS + PASTELS)[int(sd * 97.0) % (BRICKS.size() + PASTELS.size())]
		var hh := 0.7 + tall * 1.1
		building(c, (i0 + i1) * 0.5, j1 - d * 0.5, i1 - i0, d, hh, sd, 2, col)
		building(c, (i0 + i1) * 0.5, j0 + d * 0.5, i1 - i0, d, hh, sd * 1.3, 2, col)
		building(c, i0 + d * 0.5, (j0 + j1) * 0.5, d, j1 - j0 - 2.0 * d - 0.2, hh * 0.9, sd * 1.7, 2, col)
		building(c, i1 - d * 0.5, (j0 + j1) * 0.5, d, j1 - j0 - 2.0 * d - 0.2, hh * 0.9, sd * 1.9, 2, col)
		c.pad(i0 + d, i1 - d, j0 + d, j1 - d, 0.19, PARK, 2.0)
		var g := to_world((i0 + i1) * 0.5, (j0 + j1) * 0.5)
		dead_tree(c, (i0 + i1) * 0.5, (j0 + j1) * 0.5, c.ground(g.x, g.z), sd)
		Models.count("courtyard")
		return
	var nu := 2 + int(sd * 7.0) % 2
	var nv := 2 + int(sd * 13.0) % 2
	var us := [i0]
	for i in range(1, nu):
		us.append(lerpf(i0, i1, (i + (Models.hash2(sd * 9.0, i) - 0.5) * 0.35) / nu))
	us.append(i1)
	var vs := [j0]
	for j in range(1, nv):
		vs.append(lerpf(j0, j1, (j + (Models.hash2(j, sd * 11.0) - 0.5) * 0.35) / nv))
	vs.append(j1)
	for i in nu:
		for j in nv:
			var r := Models.hash2(k * 3.3 + i * 1.7 + 0.1, m * 2.1 + j * 2.9 + 0.7)
			var a: float = us[i] + 0.22
			var bb: float = us[i + 1] - 0.22
			var cc: float = vs[j] + 0.22
			var d: float = vs[j + 1] - 0.22
			# the odd lot is a little square with a tree, or a car park
			if r < 0.07:
				c.pad(a, bb, cc, d, 0.19, PARK, 2.0)
				var g := to_world((a + bb) * 0.5, (cc + d) * 0.5)
				tree(c, (a + bb) * 0.5, (cc + d) * 0.5, c.ground(g.x, g.z), 0.8, r * 9.0)
				continue
			if r < 0.11:
				car_park(c, a, bb, cc, d, r)
				continue
			if Models.hash2(r * 17.0, k * 0.3 + m) < 0.16:
				ruin(c, (a + bb) * 0.5, (cc + d) * 0.5, bb - a, d - cc, r)
				continue
			var style := int(r * 41.0) % 4
			var h := 0.35 + r * 0.5 + tall * 0.9
			if style < 2:
				h = 0.8 + tall * (3.4 + r * 1.4) + r * 0.4   # towers rise higher downtown
			building(c, (a + bb) * 0.5, (cc + d) * 0.5, bb - a, d - cc, h, r, style, Color(0, 0, 0, 0))


## One building on a lot w x d (metres) centred on (u, v), `h` tall (before PROP_V), in a style:
## 0 a setback tower, 1 a glass tower, 2 a brick mid-rise, 3 a shop with an awning.
static func building(c: Ctx, u: float, v: float, w: float, d: float, h: float, r: float, style: int, col: Color) -> void:
	Models.count("building")
	var base := INF
	for q: Vector2 in [Vector2(u - w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v + d * 0.5),
			Vector2(u - w * 0.5, v + d * 0.5), Vector2(u, v)]:
		var p := to_world(q.x, q.y)
		base = minf(base, c.ground(p.x, p.z))
	c.at(u, v, base)
	c.cap = (Rules.PY - 0.65 - base) / Models.PROP_V
	h = minf(h, c.cap - 0.12)
	# a few roofs burn: fire and smoke everywhere made the foes hard to see
	c.burning = Models.hash2(u * 0.37 + 1.0, v * 0.53) < 0.08
	var glow := BLAZE if c.burning else Models.GLASS
	var b := c.b
	b.bevels = true
	var top := h
	match style:
		0:
			if col.a == 0.0:
				col = WALLS[int(r * 59.0) % WALLS.size()]
			var tiers := 2 + int(r * 17.0) % 2
			var y := -0.3
			var f := 1.0
			for t in tiers:
				var th: float = (h + 0.3) * ([0.55, 0.3, 0.15][t] if tiers == 3 else [0.65, 0.35][t])
				var tw := w * f
				var td := d * f
				b.box(Vector3(0, y + th * 0.5, 0), Vector3(tw, th, td), col.darkened(t * 0.04))
				bands(c, tw, td, y + 0.25, y + th - 0.05, 0.22, glow)
				b.box(Vector3(0, y + th, 0), Vector3(tw + 0.1, 0.04, td + 0.1), col.lightened(0.15))
				y += th
				f *= 0.72
			top = y
			b.bevels = false
			roof(c, w * f / 0.72, d * f / 0.72, top, r)
		1:
			if col.a == 0.0:
				col = GLASS_WALLS[int(r * 31.0) % GLASS_WALLS.size()]
			b.box(Vector3(0, (h - 0.3) * 0.5, 0), Vector3(w * 0.9, h + 0.3, d * 0.9), col)
			bands(c, w * 0.9, d * 0.9, 0.15, h - 0.05, 0.2, BLAZE if c.burning else col.lightened(0.25))
			b.bevels = false
			b.box(Vector3(0, h + 0.05, 0), Vector3(w * 0.7, 0.1, d * 0.7), DARK)
			roof(c, w * 0.7, d * 0.7, h + 0.1, r)
			top = h + 0.1
		2:
			if col.a == 0.0:
				col = BRICKS[int(r * 23.0) % BRICKS.size()]
			b.box(Vector3(0, (h - 0.3) * 0.5, 0), Vector3(w, h + 0.3, d), col)
			b.bevels = false
			b.box(Vector3(0, h, 0), Vector3(w + 0.12, 0.06, d + 0.12), col.lightened(0.25))   # cornice
			grid(c, w, d, 0.15, h - 0.08, r)
			roof(c, w, d, h + 0.03, r * 0.5)
			top = h + 0.03
		_:
			# a row of little shops, each its own colour and height, awnings over the pavement
			Models.count("shops")
			var n := maxi(1, int(w / 1.8))
			var sw := w / n
			top = 0.0
			for i in n:
				var q := Models.hash2(r * 13.0 + i, i * 0.7 + r)
				var sc: Color = PASTELS[int(q * 97.0) % PASTELS.size()]
				var hh := 0.3 + q * 0.3
				var x := -w * 0.5 + (i + 0.5) * sw
				b.bevels = true
				b.box(Vector3(x, (hh - 0.3) * 0.5, 0), Vector3(sw - 0.06, hh + 0.3, d), sc)
				b.bevels = false
				var aw: Color = SHOPS[int(q * 71.0) % SHOPS.size()]
				b.box(Vector3(x, 0.2, d * 0.5 + 0.2), Vector3(sw * 0.86, 0.04, 0.4), aw)   # the awning
				b.quad(Vector3(x - sw * 0.38, 0.03, d * 0.5 + 0.01), Vector3(x + sw * 0.38, 0.03, d * 0.5 + 0.01),
					Vector3(x + sw * 0.38, 0.18, d * 0.5 + 0.01), Vector3(x - sw * 0.38, 0.18, d * 0.5 + 0.01), glow, Vector3(0, 0, 1))
				b.box(Vector3(x, hh + 0.05, d * 0.5 - 0.06), Vector3(sw * 0.6, 0.1, 0.06), aw.lightened(0.3))   # the sign
				if q < 0.3:
					b.box(Vector3(x, hh + 0.04, -d * 0.15), Vector3(0.4, 0.08, 0.3), Color8(0xc4, 0xc8, 0xce))   # an AC unit
				top = maxf(top, hh)
	b.bevels = false
	b.xf = Transform3D.IDENTITY
	if c.burning:
		# flames on the roof, as big as fits under the ship; soot streaks the roof round them
		var roof_y := base + top * Models.PROP_V
		var fs := minf(clampf(minf(w, d) * 0.22, 0.5, 1.3), (Rules.PY - 0.9 - roof_y) / 2.8)
		if fs > 0.3:
			var p := to_world(u, v)
			fire(Vector3(p.x, roof_y, p.z), fs)
			c.frame()
			flat(c, u - w * 0.3, u + w * 0.3, v - d * 0.3, v + d * 0.3, roof_y + 0.02, SOOT)


## Window bands round a box w x d, floor every `step` between y0 and y1 (raw heights).
static func bands(c: Ctx, w: float, d: float, y0: float, y1: float, step: float, col: Color) -> void:
	var b := c.b
	var y := y0
	while y + 0.06 < y1:
		var a := y
		var e := y + 0.06
		b.quad(Vector3(-w * 0.46, a, d * 0.5 + 0.01), Vector3(w * 0.46, a, d * 0.5 + 0.01), Vector3(w * 0.46, e, d * 0.5 + 0.01),
			Vector3(-w * 0.46, e, d * 0.5 + 0.01), col, Vector3(0, 0, 1))
		for sx in [-1.0, 1.0]:
			b.quad(Vector3(sx * (w * 0.5 + 0.01), a, -d * 0.46), Vector3(sx * (w * 0.5 + 0.01), a, d * 0.46),
				Vector3(sx * (w * 0.5 + 0.01), e, d * 0.46), Vector3(sx * (w * 0.5 + 0.01), e, -d * 0.46), col, Vector3(sx, 0, 0))
		y += step


## A grid of windows on the front, for brick buildings.
static func grid(c: Ctx, w: float, d: float, y0: float, y1: float, r: float) -> void:
	var b := c.b
	var cols := maxi(2, int(w / 0.75))
	var y := y0
	while y + 0.07 < y1:
		for i in cols:
			var x := -w * 0.5 + (i + 0.5) * w / cols
			b.quad(Vector3(x - 0.13, y, d * 0.5 + 0.01), Vector3(x + 0.13, y, d * 0.5 + 0.01), Vector3(x + 0.13, y + 0.08, d * 0.5 + 0.01),
				Vector3(x - 0.13, y + 0.08, d * 0.5 + 0.01), Color8(0x22, 0x26, 0x2c) if Models.hash2(x + r, y) > (0.6 if c.burning else 0.08) else BLAZE,
				Vector3(0, 0, 1))
		y += 0.22


## Something on the roof (w x d at raw height y): an antenna, a spire, a helipad, a water tank,
## a garden or air-conditioning units.
static func roof(c: Ctx, w: float, d: float, y: float, r: float) -> void:
	var b := c.b
	var s := minf(w, d)
	var kind := int(r * 89.0) % 6
	# what fits under the ship: tall roofs get flat features
	if [0.66, 0.52, 0.06, 0.53, 0.3, 0.13][kind] > c.cap - y:
		kind = 2 if s > 1.2 else 5
	match kind:
		0:
			Models.count("roof antenna")
			b.box(Vector3(s * 0.2, y + 0.3, -s * 0.1), Vector3(0.08, 0.6, 0.08), Color8(0xc8, 0xcc, 0xd2))
			b.box(Vector3(s * 0.2, y + 0.62, -s * 0.1), Vector3(0.12, 0.05, 0.12), Color8(0xe0, 0x3c, 0x3c))
			b.box(Vector3(-s * 0.2, y + 0.15, 0.1), Vector3(0.05, 0.3, 0.05), Color8(0xc8, 0xcc, 0xd2))
		1:
			Models.count("roof spire")
			b.prism(Vector3.ZERO, Models.ngon(s * 0.3, 4, PI * 0.25), y, y + 0.5, Color8(0xc8, 0xd4, 0xe0), Vector2(0.06, 0.06))
		2:
			# a plain roof slab (helipads' rings and letters read like targets)
			Models.count("roof slab")
			b.box(Vector3(0, y + 0.03, 0), Vector3(w * 0.75, 0.06, d * 0.75), DARK.lightened(0.2))
		3:
			Models.count("water tank")
			for i in 4:
				var a := Vector3(cos(i * PI * 0.5 + 0.8), 0, sin(i * PI * 0.5 + 0.8)) * 0.22
				b.box(a + Vector3(s * 0.15, y + 0.1, 0), Vector3(0.04, 0.2, 0.04), DARK)
			b.prism(Vector3(s * 0.15, 0, 0), Models.ngon(0.3, 8), y + 0.2, y + 0.42, Models.WOOD)
			b.prism(Vector3(s * 0.15, 0, 0), Models.ngon(0.32, 8), y + 0.42, y + 0.52, Models.WOOD.darkened(0.2), Vector2(0.1, 0.1))
		4:
			Models.count("roof garden")
			b.box(Vector3(0, y + 0.03, 0), Vector3(w * 0.8, 0.06, d * 0.8), PARK)
			for i in 3:
				var p := Vector3((i - 1) * w * 0.25, y + 0.06, (Models.hash2(r, i) - 0.5) * d * 0.4)
				b.prism(p, Models.ngon(0.28, 7), 0, 0.22, Models.LEAF.darkened(0.1 * i), Vector2(0.5, 0.5))
		_:
			ac_units(c, w, d, y, r)


static func ac_units(c: Ctx, w: float, d: float, y: float, r: float) -> void:
	Models.count("ac units")
	for i in 2 + int(r * 5.0) % 2:
		var p := Vector3((Models.hash2(r * 3.0, i) - 0.5) * w * 0.6, y + 0.05, (Models.hash2(i, r * 7.0) - 0.5) * d * 0.6)
		c.b.box(p, Vector3(0.45, 0.1, 0.35), Color8(0xc4, 0xc8, 0xce))
		c.b.prism(p, Models.ngon(0.12, 5), 0.1, 0.12, Color8(0x5a, 0x60, 0x6a))


## A round tree on a stubby trunk at (u, v), ground height y.
static func tree(c: Ctx, u: float, v: float, y: float, s: float, r: float) -> void:
	Models.count("city tree")
	c.at(u, v, y)
	var col := Models.LEAF.darkened(0.4 + fmod(r, 1.0) * 0.2).lerp(Color8(0x4a, 0x44, 0x34), 0.35)
	c.b.prism(Vector3.ZERO, Models.ngon(0.1, 4), -0.1, 0.35, Models.WOOD.darkened(0.4))
	c.b.prism(Vector3(0, 0.3, 0), Models.ngon(0.55 * s, 7, r), 0, 0.3, col, Vector2(1.05, 1.05))
	c.b.prism(Vector3(0, 0.6, 0), Models.ngon(0.6 * s, 7, r + 0.3), 0, 0.3, col.lightened(0.07), Vector2(0.35, 0.35))


## Parked cars in rows on a lot.
static func car_park(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	Models.count("car park")
	c.pad(u0, u1, v0, v1, 0.19, Models.ASPHALT.lightened(0.08), 2.0)
	var n := int((u1 - u0) / 1.4)
	for i in n:
		for row in [v0 + 1.2, v1 - 1.2]:
			if Models.hash2(i + r * 13.0, row) < 0.6:
				var uu := u0 + (i + 0.5) * (u1 - u0) / n
				var w := to_world(uu, row)
				var q := Models.hash2(uu, row + r)
				if q < 0.3:
					wreck(c, Vector3(w.x, c.ground(w.x, w.z) + 0.12, w.z), ANGLE + q * 9.0, q * 3.0)
				else:
					Models.car(c.b, Vector3(w.x, c.ground(w.x, w.z) + 0.12, w.z), ANGLE, q)


# ---------------------------------------------------------------- parks, plazas, stadiums

static func park(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	Models.count("park")
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	c.pad(u0, u1, v0, v1, 0.16, PARK, 2.0)
	c.pad(cu - 0.4, cu + 0.4, v0, v1, 0.19, PAVING, 2.0)
	c.pad(u0, u1, cv - 0.4, cv + 0.4, 0.19, PAVING, 2.0)
	var g := to_world(cu, cv)
	var y := c.ground(g.x, g.z)
	fountain(c, cu, cv, y)
	for i in 10:
		var a := Models.hash2(r * 17.0 + i, i * 1.3)
		var e := Models.hash2(i * 2.1, r * 5.0 + i)
		var tu := lerpf(u0 + 1.0, u1 - 1.0, a)
		var tv := lerpf(v0 + 1.0, v1 - 1.0, e)
		if absf(tu - cu) < 1.2 or absf(tv - cv) < 1.2:
			continue
		var w := to_world(tu, tv)
		if a < 0.6:
			dead_tree(c, tu, tv, c.ground(w.x, w.z), a)
		else:
			tree(c, tu, tv, c.ground(w.x, w.z), 0.8 + a * 0.5, a)
	# a shell landed in the park
	var hu := lerpf(u0 + 2.0, u1 - 2.0, Models.hash2(r * 3.0, 1.0))
	var hv := lerpf(v0 + 2.0, v1 - 2.0, Models.hash2(2.0, r * 3.0))
	crater(c, hu, hv, 1.3, r)
	if r < 0.5:
		var w := to_world(u0 + 1.6, v0 + 1.6)
		Models.mark("water tower", Vector3(w.x, c.ground(w.x, w.z), w.z), ANGLE, r)


static func fountain(c: Ctx, u: float, v: float, y: float) -> void:
	Models.count("fountain")
	c.at(u, v, y)
	c.b.prism(Vector3.ZERO, Models.ngon(1.3, 12), -0.1, 0.12, Color8(0xd8, 0xd2, 0xc4))
	c.b.prism(Vector3.ZERO, Models.ngon(1.1, 12), 0.12, 0.13, WATER)
	c.b.prism(Vector3.ZERO, Models.ngon(0.35, 8), 0.1, 0.3, Color8(0xd8, 0xd2, 0xc4))
	c.b.prism(Vector3.ZERO, Models.ngon(0.12, 6), 0.3, 0.62, Color8(0xe8, 0xf6, 0xff), Vector2(0.3, 0.3))


static func plaza(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	Models.count("plaza")
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	c.pad(u0, u1, v0, v1, 0.16, PAVING, 1.6, PAVING.darkened(0.12))
	var g := to_world(cu, cv)
	var y := c.ground(g.x, g.z)
	c.at(cu, cv, y)
	if r < 0.5:
		# an obelisk on a stepped plinth
		c.b.box(Vector3(0, 0.0, 0), Vector3(2.0, 0.2, 2.0), Color8(0xd8, 0xd2, 0xc4))
		c.b.box(Vector3(0, 0.12, 0), Vector3(1.4, 0.12, 1.4), Color8(0xe4, 0xde, 0xd0))
		c.b.prism(Vector3.ZERO, Models.ngon(0.4, 4, PI * 0.25), 0.18, 1.5, Color8(0xe8, 0xe2, 0xd4), Vector2(0.55, 0.55))
		c.b.prism(Vector3.ZERO, Models.ngon(0.23, 4, PI * 0.25), 1.5, 1.7, Color8(0xf2, 0xc4, 0x2e), Vector2(0.05, 0.05))
	else:
		fountain(c, cu, cv, y)
	rubble(c, cu + (u1 - u0) * 0.25, cv - (v1 - v0) * 0.2, y + 0.1, 1.4, 7, r)
	# kiosks with striped awnings, trees in planters at the corners
	for i in 2:
		var ku := cu + (i * 2 - 1) * (u1 - u0) * 0.3
		var w := to_world(ku, v1 - 1.4)
		c.at(ku, v1 - 1.4, c.ground(w.x, w.z))
		c.b.box(Vector3(0, 0.1, 0), Vector3(1.0, 0.4, 0.8), Color8(0xf4, 0xf0, 0xe6))
		c.b.box(Vector3(0, 0.33, 0), Vector3(1.2, 0.05, 1.0), SHOPS[(i + int(r * 9.0)) % SHOPS.size()])
	for q: Vector2 in [Vector2(u0 + 1.0, v0 + 1.0), Vector2(u1 - 1.0, v0 + 1.0), Vector2(u0 + 1.0, v1 - 1.0), Vector2(u1 - 1.0, v1 - 1.0)]:
		var w := to_world(q.x, q.y)
		var gy := c.ground(w.x, w.z)
		c.at(q.x, q.y, gy)
		c.b.box(Vector3(0, 0.02, 0), Vector3(0.9, 0.14, 0.9), Color8(0xb0, 0xa8, 0x98))
		tree(c, q.x, q.y, gy + 0.1, 0.8, q.x * 0.1)


## A stadium: an oval of stepped stands in two colours round a pitch, floodlights at the corners.
static func stadium(c: Ctx, u0: float, u1: float, v0: float, v1: float) -> void:
	Models.count("stadium")
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	c.pad(u0, u1, v0, v1, 0.16, Models.KERB.darkened(0.08), 2.0)
	# set on the highest ground under it (so the paving never shows through), its footings down to the lowest
	var lo := INF
	var hi := -INF
	for q: Vector2 in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), Vector2(cu, cv),
			Vector2(cu, v0), Vector2(cu, v1), Vector2(u0, cv), Vector2(u1, cv)]:
		var w := to_world(q.x, q.y)
		lo = minf(lo, c.ground(w.x, w.z))
		hi = maxf(hi, c.ground(w.x, w.z))
	c.at(cu, cv, hi)
	var dip := -(hi - lo) / Models.PROP_V - 0.15
	var b := c.b
	var ax := (u1 - u0) * 0.5 - 0.3
	var az := (v1 - v0) * 0.5 - 0.3
	var n := 20
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		for tier in 2:
			var ri := 0.66 + tier * 0.17
			var ro := ri + 0.17
			var pts := PackedVector2Array([Vector2(cos(a0) * ax * ri, sin(a0) * az * ri), Vector2(cos(a0) * ax * ro, sin(a0) * az * ro),
				Vector2(cos(a1) * ax * ro, sin(a1) * az * ro), Vector2(cos(a1) * ax * ri, sin(a1) * az * ri)])
			var col := Color8(0x7a, 0x3a, 0x34) if (i / 2) % 2 == 0 else Color8(0x9a, 0x96, 0x8e)
			if tier == 1:
				col = Color8(0x3a, 0x4a, 0x62) if (i / 2) % 2 == 0 else Color8(0x9a, 0x96, 0x8e)
			b.prism(Vector3.ZERO, pts, dip, 0.3 + tier * 0.2, col)
	var field := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		field.append(Vector2(cos(a) * ax * 0.66, sin(a) * az * 0.66))
	b.prism(Vector3.ZERO, field, dip, 0.14, Color8(0x4e, 0x56, 0x3a))
	b.box(Vector3(0, 0.145, 0), Vector3(0.08, 0.01, az * 1.1), Models.PAINT)
	b.prism(Vector3.ZERO, Models.ngon(az * 0.2, 14), 0.14, 0.145, Models.PAINT)
	b.prism(Vector3.ZERO, Models.ngon(az * 0.2 - 0.08, 14), 0.145, 0.15, Color8(0x4e, 0x56, 0x3a))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * ax * 0.9, 0, sz * az * 0.9)
			b.box(p + Vector3(0, 0.6 + dip * 0.5, 0), Vector3(0.2, 1.4 - dip, 0.2), Color8(0xc8, 0xcc, 0xd2))
			b.box(p + Vector3(0, 1.32, 0), Vector3(0.9, 0.3, 0.3), Color8(0xff, 0xf2, 0xb0))


# ---------------------------------------------------------------- war

## A fire at p (world) of size s; smoke rises from it when there is room under the ship.
static func fire(p: Vector3, s: float, smoke := true) -> void:
	# the tallest flicker reaches 1.9 s x 1.45 above p: keep it clear of the ship
	s = minf(s, (Rules.PY - 0.9 - p.y) / 2.8)
	if s < 0.2:
		return
	Models.count("fire")
	fires.append({"p": p, "s": s, "smoke": smoke and p.y < SMOKE_TOP - 1.2})


## A pile of broken concrete round (u, v) (ground at y), `n` chunks over radius `rad` (metres).
static func rubble(c: Ctx, u: float, v: float, y: float, rad: float, n: int, r: float) -> void:
	Models.count("rubble")
	c.frame()
	for i in n:
		var a := Models.hash2(r * 7.0 + i, i * 1.9) * TAU
		var e := sqrt(Models.hash2(i * 3.1, r * 5.0 + i)) * rad
		var sz := 0.25 + Models.hash2(r + i * 0.7, 2.0 + i) * 0.45
		var col: Color = RUBBLE[(i + int(r * 13.0)) % RUBBLE.size()]
		c.b.octa(Vector3(u + cos(a) * e, y + sz * 0.15, v + sin(a) * e), sz, col, Vector3(1.0, 0.6, 0.8))


## A shell crater in the road at (u, v): a scorched ring round a dark pit, and thrown-up rubble.
static func crater(c: Ctx, u: float, v: float, rad: float, r: float) -> void:
	Models.count("crater")
	var n := 9
	var ring := []
	var pit := []
	for i in n:
		var a := TAU * i / n + r
		var k := 1.0 + (Models.hash2(r * 3.0, i) - 0.5) * 0.35
		ring.append(Vector2(u + cos(a) * rad * k, v + sin(a) * rad * k))
		pit.append(Vector2(u + cos(a) * rad * 0.55 * k, v + sin(a) * rad * 0.55 * k))
	var mid := to_world(u, v)
	var y := c.road(mid.x, mid.z) + 0.13
	for i in n:
		var j := (i + 1) % n
		c.lay([ring[i], ring[j], pit[j], pit[i]], [y, y, y, y], 0.0, Color8(0x2e, 0x2a, 0x28))
		c.lay([pit[i], pit[j], Vector2(u, v), Vector2(u, v)], [y, y, y, y], 0.005, Color8(0x16, 0x14, 0x14))
	for i in 4:
		var a := TAU * i / 4.0 + r * 3.0
		c.frame()
		c.b.octa(Vector3(u + cos(a) * rad * 1.15, y + 0.03, v + sin(a) * rad * 1.15), 0.3, RUBBLE[i % RUBBLE.size()], Vector3(1.0, 0.5, 0.8))


## A burnt-out wreck at world p, slewed across the road, sometimes still burning.
static func wreck(c: Ctx, p: Vector3, ang: float, r: float) -> void:
	Models.count("wreck")
	Models.car(c.b, p, ang, r, Color8(0x3a, 0x34, 0x30).lerp(Color8(0x5a, 0x40, 0x30), Models.hash2(r, 3.0)))
	if r < 0.12:
		fire(p + Vector3(0, 0.35, 0), 0.6, false)


## Steel tank traps (three crossed beams) at (u, v), ground at y.
static func hedgehog(c: Ctx, u: float, v: float, y: float, r: float) -> void:
	Models.count("tank trap")
	var w := to_world(u, v)
	for i in 3:
		var bs := Basis(Vector3.UP, r * 5.0 + i * 2.1) * Basis(Vector3(1, 0, 0), 0.9 + i * 0.4)
		c.b.xf = Transform3D(bs, Vector3(w.x, y + 0.35, w.z))
		c.b.box(Vector3.ZERO, Vector3(0.12, 1.0, 0.12), Color8(0x3a, 0x3a, 0x3c))


## A bare, burnt tree.
static func dead_tree(c: Ctx, u: float, v: float, y: float, r: float) -> void:
	Models.count("dead tree")
	c.at(u, v, y)
	var col := Color8(0x2e, 0x28, 0x24)
	c.b.prism(Vector3.ZERO, Models.ngon(0.1, 4), -0.1, 0.75, col, Vector2(0.4, 0.4))
	c.b.xf = c.b.xf * Transform3D(Basis(Vector3(0, 0, 1), 0.7).rotated(Vector3.UP, r * 6.0), Vector3(0, 0.35, 0))
	c.b.prism(Vector3.ZERO, Models.ngon(0.05, 4), 0.0, 0.4, col, Vector2(0.4, 0.4))


## A ruined building on a w x d lot at (u, v): broken walls, burnt floors and rubble, still burning.
static func ruin(c: Ctx, u: float, v: float, w: float, d: float, r: float) -> void:
	Models.count("ruin")
	var base := INF
	for q: Vector2 in [Vector2(u - w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v + d * 0.5),
			Vector2(u - w * 0.5, v + d * 0.5), Vector2(u, v)]:
		var p := to_world(q.x, q.y)
		base = minf(base, c.ground(p.x, p.z))
	c.at(u, v, base)
	var b := c.b
	var col: Color = WALLS[int(r * 37.0) % WALLS.size()].darkened(0.25)
	var tall := 0.5 + r * 1.2
	# two corner walls left standing, jagged in steps, and a stub of the floors between them
	for side in [-1.0, 1.0]:
		var n := 3
		for i in n:
			var hh := tall * (1.0 - i * 0.3) * (0.7 + Models.hash2(r * 9.0 + side, i) * 0.5)
			var x: float = side * (w * 0.5 - 0.15)
			var z: float = -d * 0.5 + (i + 0.5) * d / n
			b.box(Vector3(x, (hh - 0.3) * 0.5, z), Vector3(0.3, hh + 0.3, d / n), col.darkened(i * 0.08))
			if hh > 0.4:
				b.quad(Vector3(x - side * 0.16, hh * 0.45, z - d / n * 0.3), Vector3(x - side * 0.16, hh * 0.45, z + d / n * 0.3),
					Vector3(x - side * 0.16, hh * 0.6, z + d / n * 0.3), Vector3(x - side * 0.16, hh * 0.6, z - d / n * 0.3), SOOT, Vector3(-side, 0, 0))
	b.box(Vector3(0, 0.1, d * 0.5 - 0.15), Vector3(w * 0.7, 0.5, 0.3), col.darkened(0.1))
	b.box(Vector3(0, 0.35, 0), Vector3(w * 0.8, 0.06, d * 0.6), SOOT)   # a burnt floor slab
	b.box(Vector3(w * 0.2, 0.42, -d * 0.1), Vector3(w * 0.35, 0.05, d * 0.4), DARK)
	var mid := to_world(u, v)
	rubble(c, u, v, base + 0.1, minf(w, d) * 0.45, 9, r)
	if Models.hash2(r * 5.0, u * 0.3) < 0.3:
		fire(Vector3(mid.x, base + 0.4, mid.z), 0.9 + minf(w, d) * 0.12)


## The fire and smoke of the chunk just built (`fires`), in one mesh: a surface of flickering
## flame tongues and one of smoke puffs that billow up and drift off. Null when nothing burns.
static func fx_mesh() -> ArrayMesh:
	if fires.is_empty():
		return null
	var mesh := ArrayMesh.new()
	var fv := PackedVector3Array()
	var fc := PackedColorArray()
	var fu := PackedVector2Array()
	var fu2 := PackedVector2Array()
	var sv := PackedVector3Array()
	var sn := PackedVector3Array()
	var sc := PackedColorArray()
	var su := PackedVector2Array()
	var su2 := PackedVector2Array()
	for f: Dictionary in fires:
		var p: Vector3 = f.p
		var s: float = f.s
		var sd := Models.hash2(p.x, p.z)
		# flame tongues: little pyramids, red at the foot, yellow at the tip
		var nt := 3 + int(sd * 3.0)
		for i in nt:
			var a := TAU * i / nt + sd * 5.0
			var o := Vector3(cos(a), 0, sin(a)) * s * 0.35 * (0.3 + Models.hash2(sd, i))
			var base := p + o
			var hh := s * (1.0 + Models.hash2(i, sd) * 0.9)
			var rad := s * 0.32
			var tip := base + Vector3(0, hh, 0)
			for k in 5:
				var a0 := TAU * k / 5.0
				var a1 := TAU * (k + 1) / 5.0
				var q0 := base + Vector3(cos(a0), 0, sin(a0)) * rad
				var q1 := base + Vector3(cos(a1), 0, sin(a1)) * rad
				for e: Array in [[q0, Color8(0xff, 0x4a, 0x1a)], [tip, Color8(0xff, 0xe6, 0x7a)], [q1, Color8(0xff, 0x4a, 0x1a)]]:
					fv.append(e[0])
					fc.append(e[1])
					fu.append(Vector2(base.x, base.z))
					fu2.append(Vector2(base.y, Models.hash2(sd * 3.0, i)))
		if not f.smoke:
			continue
		# smoke: puffs (squashed double cones) spread along the column by their phase
		var np := 7
		for i in np:
			var ph := (i + Models.hash2(sd, i * 2.0) * 0.6) / np
			var pr := s * 0.7
			var top := p + Vector3(0, pr * 0.7, 0)
			var bot := p - Vector3(0, pr * 0.5, 0)
			var col := Color8(0x58, 0x56, 0x56).lerp(Color8(0x7e, 0x7c, 0x7a), Models.hash2(i, sd * 7.0))
			for k in 6:
				var a0 := TAU * k / 6.0 + i
				var a1 := TAU * (k + 1) / 6.0 + i
				var q0 := p + Vector3(cos(a0), 0, sin(a0)) * pr
				var q1 := p + Vector3(cos(a1), 0, sin(a1)) * pr
				for tri: Array in [[q0, top, q1], [q1, bot, q0]]:
					var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
					if n.dot((tri[0] + tri[1] + tri[2]) / 3.0 - p) < 0.0:
						n = -n
					var order: Array = [tri[0], tri[2], tri[1]] if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(n) > 0.0 else tri
					for q: Vector3 in order:
						sv.append(q)
						sn.append(n)
						sc.append(col)
						su.append(Vector2(p.x, p.z))
						su2.append(Vector2(p.y, ph))
	for e: Array in [[fv, null, fc, fu, fu2, fire_mat()], [sv, sn, sc, su, su2, smoke_mat()]]:
		if (e[0] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = e[0]
		if e[1] != null:
			arr[Mesh.ARRAY_NORMAL] = e[1]
		arr[Mesh.ARRAY_COLOR] = e[2]
		arr[Mesh.ARRAY_TEX_UV] = e[3]
		arr[Mesh.ARRAY_TEX_UV2] = e[4]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, e[5])
	return mesh


static var _fire_mat: ShaderMaterial
static var _smoke_mat: ShaderMaterial


## Flames: unshaded, each tongue (its foot in UV and UV2.x, its phase in UV2.y) flickering.
static func fire_mat() -> ShaderMaterial:
	if _fire_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
void vertex() {
	vec3 base = vec3(UV.x, UV2.x, UV.y);
	vec3 o = VERTEX - base;
	float ph = UV2.y * 6.283;
	o.y *= 1.0 + 0.3 * sin(TIME * 11.0 + ph) + 0.15 * sin(TIME * 23.0 + ph * 3.0);
	o.xz *= 1.0 + 0.18 * sin(TIME * 7.0 + ph * 2.0);
	o.x += o.y * 0.22 * sin(TIME * 5.0 + ph);
	VERTEX = base + o;
}
void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
}
"""
		_fire_mat = ShaderMaterial.new()
		_fire_mat.shader = sh
	return _fire_mat


## Smoke: each puff (the column's foot in UV and UV2.x, its phase in UV2.y) rises, swells and
## drifts downwind, then shrinks away and starts again at the fire; never above SMOKE_TOP.
static func smoke_mat() -> ShaderMaterial:
	if _smoke_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled;
varying float t;
varying float lit;
void vertex() {
	vec3 base = vec3(UV.x, UV2.x, UV.y);
	t = fract(TIME * 0.07 + UV2.y);
	float rise = max(%s - base.y - 1.0, 0.5);
	float s = mix(0.5, 1.7, t) * smoothstep(0.0, 0.1, t) * (1.0 - smoothstep(0.75, 1.0, t));
	VERTEX = base + (VERTEX - base) * s + vec3(t * 2.2, t * rise, -t * 1.2);
	// its own soft light from above, so the smoke reads as billows, not holes
	lit = 0.55 + 0.45 * clamp(NORMAL.y * 0.8 + NORMAL.x * 0.3 + 0.2, 0.0, 1.0);
}
void fragment() {
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * lit;
	// glowing orange where it leaves the fire, paler as it thins out higher up
	c = mix(c, vec3(0.9, 0.3, 0.06), (1.0 - smoothstep(0.0, 0.22, t)) * 0.7);
	ALBEDO = mix(c, c * 1.5 + 0.04, smoothstep(0.4, 1.0, t));
}
""" % SMOKE_TOP
		_smoke_mat = ShaderMaterial.new()
		_smoke_mat.shader = sh
	return _smoke_mat
