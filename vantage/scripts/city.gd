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
## - every block is filled (Guillaume, 2026-11-27): mostly towers, now and then a park (paths, a
##   fountain, trees, a water tower landmark), a stadium, a shopping mall (car park on the roof,
##   glass skylights), a domed capitol on its lawn or a columned hall on its steps;
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
## Every third street is a boulevard (Guillaume, 2026-11-27: "some city streets should be made
## wider to allow tanks passing"): BLVD_W wide, two lanes each way; the city's tanks drive along them.
const BLVD_W := 6.0
## How often a 2 x 2 tile of blocks is one big superblock, or has two of its blocks joined across
## an avenue or across a street (the road between them stops): see `superblock`.
const MERGE_QUAD := 0.14
const MERGE_U := 0.16
const MERGE_V := 0.16
## How far the city's streets lie below the other worlds' plain (Guillaume, 2026-11-26: "the city
## world is very flat... it doesn't go as high as a city should"). Nothing may rise past the ship,
## so the city goes down instead, like the canyons: its towers rise from deep streets.
const SINK := 5.0
## The skyline: each SKY_SEG m of the course has its downtown, a cluster of the tallest towers
## (SKY_R m across) that falls away to low streets round it.
const SKY_SEG := 96.0
const SKY_R := 34.0
## Midtown (Guillaume, 2026-11-26: "I want 80% of blocks to be high towers"): the share of blocks
## left low (mid-rises, shops, courtyards), and how high the others' towers climb, near downtown's
## (see `midtown`). A tower block is all towers, bar the odd ruin.
const MIDTOWN_LOW := 0.2
const MIDTOWN_LO := 0.8
const MIDTOWN_HI := 1.0
## The blocks that aren't towers, and their shares (see `block_kind`).
const BLOCK_KINDS := [["park", 0.035], ["square", 0.035], ["mall", 0.025], ["hall", 0.035]]
## What two joined blocks hold, and what a whole 2 x 2 superblock holds (towers otherwise).
const PAIR_KINDS := [["mall", 0.25], ["square", 0.12], ["park", 0.1]]
const QUAD_KINDS := [["capitol", 0.3], ["stadium", 0.25], ["park", 0.25], ["square", 0.2]]
## The share of a block's lots left as ruins (broken walls, rubble): the war shows, but the block
## still reads as built.
const RUINS := 0.07
## The share of mid-rise and shop lots turned into towers on the low blocks.
const TOWER_MORE := 0.35
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
## The lit windows and neon signs of the chunk last built, drawn unshaded (so the city's calming
## leaves their warmth) in `fx_mesh`: [[4 corners (world)], colour, neon (pulses)].
static var glows: Array = []
## Lit windows (Guillaume, 2026-11-26: a few dim lit windows and neon signs against the grey): a
## dim warm light, and the odd neon in colours that stay apart from the foes' magenta shots and
## the player's blue ones. Dim and sparse: they're accents, the foes stay the brightest things.
const LAMP := Color8(0xe0, 0xae, 0x6a)
const NEONS := [Color8(0xd0, 0x8a, 0x3c), Color8(0x6c, 0xb0, 0x78), Color8(0xc0, 0x58, 0x44), Color8(0xb8, 0xb0, 0x70)]
## The share of a calm building's windows lit, and of buildings with a neon sign.
const LIT := 0.16
const NEON := 0.22
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


## How tall block (k, m)'s towers stand outside the downtowns, on the skyline's 0..1 scale: most
## blocks MIDTOWN_LO..MIDTOWN_HI, a few (MIDTOWN_LOW of them) left low so the skyline still varies.
static func midtown(k: int, m: int) -> float:
	var h := Models.hash2(k * 2.31 + 0.7, m * 1.93 + 3.1)
	if h < MIDTOWN_LOW:
		return 0.0
	return lerpf(MIDTOWN_LO, MIDTOWN_HI, (h - MIDTOWN_LOW) / (1.0 - MIDTOWN_LOW))


static func to_local(x: float, z: float) -> Vector2:
	return Vector2(x * _ca - z * _sa, x * _sa + z * _ca)


## City coordinates (u, v) to the world (y = 0): Basis(UP, ANGLE) * (u, 0, v).
static func to_world(u: float, v: float) -> Vector3:
	return Vector3(u * _ca + v * _sa, 0.0, -u * _sa + v * _ca)


## On (or within `margin` of) a road.
static func on_road(x: float, z: float, margin := 0.0) -> bool:
	var l := to_local(x, z)
	var k := col_of(l.x)
	var m := row_of(l.y)
	return l.x - ave_u(k) < AVE_W * 0.5 + margin or ave_u(k + 1) - l.x < AVE_W * 0.5 + margin \
		or l.y - str_v(m) < str_hw(m) + margin or str_v(m + 1) - l.y < str_hw(m + 1) + margin


# ---------------------------------------------------------------- the grid
# Not a perfect grid (Guillaume, 2026-11-27: "not like a perfect grid but like a proper city"):
# the avenues and streets wander a little off their lines, every third street is a boulevard,
# and here and there a road stops so blocks join into bigger ones (a capitol's grounds, a
# stadium, a park, a square, a mall). Roads stay on even metres so they keep their 2 m steps.

## Avenue k's centre line (u): 2 m either side of its place, the expressways' kept straight.
static func ave_u(k: int) -> float:
	if elevated(k):
		return k * AVE
	return k * AVE + (floorf(Models.hash2(k * 0.91 + 0.3, 4.7) * 3.0) - 1.0) * 2.0


static func boulevard(m: int) -> bool:
	return posmod(m, 3) == 0


## Street m's centre line (v): 2 m either side of its place; a boulevard keeps its own and the
## streets beside it only move away from it, so the blocks along it stay deep.
static func str_v(m: int) -> float:
	if boulevard(m):
		return m * STR
	var j := floorf(Models.hash2(m * 1.13 + 0.7, 2.9) * 3.0) - 1.0
	if boulevard(m - 1):
		j = maxf(j, 0.0)
	if boulevard(m + 1):
		j = minf(j, 0.0)
	return m * STR + j * 2.0


static func str_hw(m: int) -> float:
	return (BLVD_W if boulevard(m) else STR_W) * 0.5


## The column (k) holding u: between avenues k and k + 1.
static func col_of(u: float) -> int:
	var k := floori(u / AVE)
	if u < ave_u(k):
		return k - 1
	if u >= ave_u(k + 1):
		return k + 1
	return k


## The row (m) holding v: between streets m and m + 1.
static func row_of(v: float) -> int:
	var m := floori(v / STR)
	if v < str_v(m):
		return m - 1
	if v >= str_v(m + 1):
		return m + 1
	return m


## The (super)block that the cell (k, m) belongs to: Rect2i(first cell, cells across). The cells
## go in 2 x 2 tiles; a tile is one big block, or two of its cells join across the avenue or the
## street between them, or it stays four blocks. Never across an expressway or a boulevard.
static func superblock(k: int, m: int) -> Rect2i:
	var tk := floori(k / 2.0) * 2
	var tm := floori(m / 2.0) * 2
	var h := Models.hash2(Models.hash2(tk * 0.37 + 0.6, tm * 0.53 + 0.2) * 61.7, tk * 0.07 + tm * 0.13)
	var g := Models.hash2(h * 13.1, tk * 0.21 + 1.0)
	var across_u := not elevated(tk + 1)
	var across_v := not boulevard(tm + 1)
	if h < MERGE_QUAD and across_u and across_v:
		return Rect2i(tk, tm, 2, 2)
	h -= MERGE_QUAD
	if h >= 0.0 and h < MERGE_U and across_u:
		var row := tm + (0 if g < 0.5 else 1)
		if m == row:
			return Rect2i(tk, row, 2, 1)
	h -= MERGE_U
	if h >= 0.0 and h < MERGE_V and across_v:
		var col := tk + (0 if g < 0.5 else 1)
		if k == col:
			return Rect2i(col, tm, 1, 2)
	return Rect2i(k, m, 1, 1)


## Where a tank at world x near world z drives: on the nearest boulevard (never more than half
## their spacing off, so still on the screen), `lane` metres off its middle. Returns the world z.
static func boulevard_z(x: float, z: float, lane: float) -> float:
	var l := to_local(x, z)
	var step := 3.0 * STR
	var v := roundf(l.y / step) * step + lane
	# the point at world x on the line v: x = u cos + v sin
	var u := (x - v * _sa) / _ca
	return to_world(u, v).z


## Avenue k runs past row m (it doesn't when the blocks either side are one).
static func avenue_at(k: int, m: int) -> bool:
	return superblock(k - 1, m) != superblock(k, m)


## Street m runs past column k.
static func street_at(m: int, k: int) -> bool:
	return superblock(k, m - 1) != superblock(k, m)


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
	## Only working out where the buildings stand (a neighbouring chunk's, for their shadows).
	var dry := false
	## The block being built, and the buildings that cast shadows, by block:
	## Vector2i(k, m) -> [[u0, u1, v0, v1, top (world)], ...].
	var km := Vector2i.ZERO
	var casters := {}
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
		if dry:
			return
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

	## Draw round (u, v) at height y, heights scaled by PROP_V (and by sy), widths by sxz.
	func at(u: float, v: float, y: float, sy := 1.0, sxz := 1.0) -> void:
		var w := City.to_world(u, v)
		b.xf = Transform3D(Basis(Vector3.UP, City.ANGLE) * Basis.from_scale(Vector3(sxz, Models.PROP_V * sy, sxz)), Vector3(w.x, y, w.z))
		b.occlude(Models.AO_H)


## Builds the city on one chunk: props into `b`; returns the road and paving triangles
## [vertices, normals, colours] for the ground's own surface.
static func build(b: Models.Builder, z0: float, size: Vector2, hgt: Callable, height: Callable) -> Array:
	var c := Ctx.new()
	c.b = b
	fires.clear()
	glows.clear()
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
	for k in range(floori(lo.x / AVE) - 2, ceili(hi.x / AVE) + 1):
		for m in range(floori(lo.y / STR) - 2, ceili(hi.y / STR) + 1):
			block(c, k, m)
	# the neighbouring chunks' buildings near the edges cast shadows over this one's streets too
	c.dry = true
	for k in range(floori(lo.x / AVE) - 2, ceili(hi.x / AVE) + 1):
		for m in range(floori(lo.y / STR) - 3, ceili(hi.y / STR) + 2):
			var sb := superblock(k, m)
			if sb.position != Vector2i(k, m):
				continue
			var mid := to_world((ave_u(k) + ave_u(sb.end.x)) * 0.5, (str_v(m) + str_v(sb.end.y)) * 0.5)
			if not c.owns(mid) and absf(mid.x) <= c.hw and mid.z < c.z0 + 2.0 * AVE + CAST_REACH and mid.z > c.z1 - 2.0 * AVE - CAST_REACH:
				block(c, k, m)
	c.dry = false
	shade_streets(c)
	b.xf = Transform3D.IDENTITY
	b.bevels = true
	return [c.gv, c.gn, c.gc]


# ---------------------------------------------------------------- shadows

## How far (m) a tower's shadow may reach across the streets, at most.
const CAST_REACH := 9.0
## How dark a street lies in a tower's full shadow, and over how much height the shadow's tip fades.
const CAST_DARK := 0.8
const CAST_SOFT := 1.1


## Towers cast their shadows across the streets, plazas and parks (Guillaume, 2026-11-26): every
## vertex of the city's ground surface that a building hides from the sun is darkened, blended
## over each 2 m step like the land's baked shadows, so they stay soft.
static func shade_streets(c: Ctx) -> void:
	var slide := Models.sun_slide
	var l := slide.length()
	if l < 0.01 or c.casters.is_empty():
		return
	var dir := to_local(-slide.x / l, -slide.y / l)
	var top := Rules.PY
	var memo := {}
	for i in c.gv.size():
		var p: Vector3 = c.gv[i]
		# road markings lie a hair over the road: one look serves every layer at a spot
		var key := Vector2i(roundi(p.x * 8.0), roundi(p.z * 8.0))
		var k: float = memo.get(key, -1.0)
		if k < 0.0:
			k = cast_at(c, to_local(p.x, p.z), p.y, dir, l, minf((top - p.y) * l, CAST_REACH))
			memo[key] = k
		if k > 0.0:
			var col: Color = c.gc[i]
			c.gc[i] = Color(col.r * (1.0 - CAST_DARK * k * 0.96), col.g * (1.0 - CAST_DARK * k * 0.98), col.b * (1.0 - CAST_DARK * k * 0.85), col.a)


## How deep (0..1) the point at city coordinates o, height y, lies in a building's shadow: the ray
## toward the sun (dir, rising 1/l a metre) runs into a building below its roof.
static func cast_at(c: Ctx, o: Vector2, y: float, dir: Vector2, l: float, reach: float) -> float:
	# the blocks the ray crosses: its two ends and its middle cover them (a block is 12 m or more)
	var q1 := o + dir * reach
	var a0 := Vector2i(col_of(o.x), row_of(o.y))
	var a1 := Vector2i(col_of(q1.x), row_of(q1.y))
	var cells: Array[Vector2i] = [a0]
	if a1 != a0:
		cells.append(a1)
		for e: Vector2i in [Vector2i(a0.x, a1.y), Vector2i(a1.x, a0.y)]:
			if e != a0 and e != a1:
				cells.append(e)
	var best := 0.0
	for cell: Vector2i in cells:
		for f: Array in c.casters.get(cell, []):
			var t0 := 0.0
			var t1 := reach
			for a in 2:
				var lo: float = f[a * 2]
				var hi: float = f[a * 2 + 1]
				var oo: float = o[a]
				var dd: float = dir[a]
				if absf(dd) < 1e-5:
					if oo < lo or oo > hi:
						t1 = -1.0
					continue
				var e0 := (lo - oo) / dd
				var e1 := (hi - oo) / dd
				t0 = maxf(t0, minf(e0, e1))
				t1 = minf(t1, maxf(e0, e1))
			if t1 < t0:
				continue
			# how far under the roof the ray passes where it enters
			best = maxf(best, smoothstep(0.0, CAST_SOFT, float(f[4]) - (y + t0 / l)))
			if best >= 1.0:
				return 1.0
	return best


# ---------------------------------------------------------------- roads

static func avenue(c: Ctx, k: int, v_lo: float, v_hi: float) -> void:
	var u := ave_u(k)
	var hw := AVE_W * 0.5
	# 2 m steps centred on even metres: a street (on even metres, an odd number of steps wide)
	# gets whole steps
	var v := floorf(v_lo / 2.0) * 2.0 - 1.0
	while v < v_hi:
		var vm := v + 1.0
		v += 2.0
		var m := row_of(vm)
		# crossing street xs? where the avenue stops, or the street does, the crossing is a T
		var xs := m
		var crossing := vm - str_v(m) < str_hw(m)
		if not crossing and str_v(m + 1) - vm < str_hw(m + 1):
			xs = m + 1
			crossing = true
		var open_l := crossing and street_at(xs, k - 1)
		var open_r := crossing and street_at(xs, k)
		if crossing:
			if not (open_l or open_r or avenue_at(k, xs - 1) or avenue_at(k, xs)):
				continue
		elif not avenue_at(k, m):
			continue
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
		# how far from the nearest street's middle, as if it were a plain 2 m street
		var to_street := minf(vm - str_v(m) - str_hw(m), str_v(m + 1) - str_hw(m + 1) - vm) + 1.0
		if not open_l:
			c.lay(quad.call(-hw, -hw + 0.3), across.call(-hw, -hw + 0.3), 0.11, Models.KERB)
		if not open_r:
			c.lay(quad.call(hw - 0.3, hw), across.call(hw - 0.3, hw), 0.11, Models.KERB)
		if not open_l and not open_r:
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
	var v := str_v(m)
	var hw := str_hw(m)
	var wide := boulevard(m)
	# 2 m steps from even metres: each wholly in or out of an avenue (whose edges are on even metres)
	var u := floorf(u_lo / 2.0) * 2.0
	while u < u_hi:
		var um := u + 1.0
		u += 2.0
		var k := col_of(um)
		if um - ave_u(k) < AVE_W * 0.5 or ave_u(k + 1) - um < AVE_W * 0.5:
			continue   # the avenue covers the junction
		if not street_at(m, k):
			continue   # the street stops: the blocks either side are one
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
			var f0 := (a0 + hw) / (hw * 2.0)
			var f1 := (a1 + hw) / (hw * 2.0)
			return [lerpf(hs[0], hs[3], f0), lerpf(hs[1], hs[2], f0), lerpf(hs[1], hs[2], f1), lerpf(hs[0], hs[3], f1)]
		c.lay(quad.call(-hw, hw), hs, 0.08, Models.ASPHALT)
		c.lay(quad.call(-hw, -hw + 0.25), across.call(-hw, -hw + 0.25), 0.11, Models.KERB)
		c.lay(quad.call(hw - 0.25, hw), across.call(hw - 0.25, hw), 0.11, Models.KERB)
		if wide:
			# a boulevard: a double yellow line down the middle, a dashed one between each pair of lanes
			c.lay(quad.call(-0.1, -0.04), across.call(-0.1, -0.04), 0.1, YELLOW)
			c.lay(quad.call(0.04, 0.1), across.call(0.04, 0.1), 0.1, YELLOW)
			if posmod(um, 4.0) < 2.0:
				for lane in [-1.45, 1.45]:
					c.lay(quad.call(lane - 0.05, lane + 0.05), across.call(lane - 0.05, lane + 0.05), 0.1, Models.PAINT)
		elif posmod(um, 4.0) < 2.0:
			c.lay(quad.call(-0.06, 0.06), across.call(-0.06, 0.06), 0.1, Models.PAINT)
		var y: float = (hs[0] + hs[1] + hs[2] + hs[3]) * 0.25
		if c.raw(mid.x, mid.z) < 0.02:
			bridge_bits(c, false, v, um, hw, y)
		var r := Models.hash2(um * 2.3, v * 0.7 + 0.4)
		if r < 0.035:
			var side := (0.55 if r < 0.018 else -0.55) * (3.9 if wide else 1.0)
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
	var u := ave_u(k)
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
	var sb := superblock(k, m)
	if sb.position != Vector2i(k, m):
		return   # built with the superblock's first cell
	var u0 := ave_u(k) + AVE_W * 0.5
	var u1 := ave_u(sb.end.x) - AVE_W * 0.5
	var v0 := str_v(m) + str_hw(m)
	var v1 := str_v(sb.end.y) - str_hw(sb.end.y)
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	var mid := to_world(cu, cv)
	if not c.dry and not c.owns(mid):
		return
	c.km = Vector2i(k, m)
	if c.raw(mid.x, mid.z) < 0.03:
		if c.dry:
			return
		canal(c, k, m, u0, u1, v0, v1)
		return
	var dry := true
	for q: Vector2 in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
		var w := to_world(q.x, q.y)
		dry = dry and c.raw(w.x, w.z) > 0.02
	var kind := block_kind(k, m, sb.size)
	if kind != "towers" and kind != "park" and not dry:
		kind = "towers"   # the big buildings need firm ground under every corner
	match kind:
		"park":
			if not c.dry:
				park(c, u0, u1, v0, v1, Models.hash2(k * 0.37, m * 0.61))
		"stadium":
			if not c.dry:
				stadium(c, u0, u1, v0, v1)
		"mall":
			mall(c, u0, u1, v0, v1, Models.hash2(k * 0.53, m * 0.29))
		"capitol":
			capitol(c, u0, u1, v0, v1, Models.hash2(k * 0.71, m * 0.43))
		"hall":
			hall(c, u0, u1, v0, v1, Models.hash2(k * 0.19, m * 0.83))
		"square":
			if not c.dry:
				square(c, u0, u1, v0, v1, Models.hash2(k * 0.83, m * 0.17))
		_:
			lots(c, k, m, u0, u1, v0, v1)
	# the shadows a superblock casts are looked up by any of its cells
	if sb.size != Vector2i.ONE and c.casters.has(c.km):
		for i in sb.size.x:
			for j in sb.size.y:
				c.casters[Vector2i(k + i, m + j)] = c.casters[c.km]


## A block the canals run through: stone quays along the roads where they meet the water, barges
## and boats moored on it (so it reads as a canal basin, not an empty block), trees on its banks.
static func canal(c: Ctx, k: int, m: int, u0: float, u1: float, v0: float, v1: float) -> void:
	Models.count("canal")
	var wy := Models.SEA_Y - SINK
	var top := 0.5 - SINK
	c.frame()
	var b := c.b
	var stone := CONCRETE.lightened(0.08)
	for e in 4:
		var along_u := e < 2
		var fixed: float = [v0 + 0.3, v1 - 0.3, u0 + 0.3, u1 - 0.3][e]
		var a0: float = u0 if along_u else v0
		var a1: float = u1 if along_u else v1
		var a := a0
		while a < a1 - 0.01:
			var a2 := minf(a + 2.0, a1)
			var am := (a + a2) * 0.5
			var w := to_world(am, fixed) if along_u else to_world(fixed, am)
			if c.raw(w.x, w.z) < 0.02:
				var cen := Vector3(am, (wy - 0.3 + top) * 0.5, fixed) if along_u else Vector3(fixed, (wy - 0.3 + top) * 0.5, am)
				var sz := Vector3(a2 - a + 0.02, top - wy + 0.3, 0.6) if along_u else Vector3(0.6, top - wy + 0.3, a2 - a + 0.02)
				b.box(cen, sz, stone)
				# a bollard now and then on the quay's edge
				if posmod(am, 6.0) < 2.0:
					var bp := cen + (Vector3(0, top - cen.y + 0.1, (0.2 if e == 0 else -0.2)) if along_u else Vector3((0.2 if e == 2 else -0.2), top - cen.y + 0.1, 0))
					b.box(bp, Vector3(0.14, 0.2, 0.14), DARK)
			a = a2
	# barges and boats moored along the water
	var long_u := u1 - u0 >= v1 - v0
	for i in 3:
		var h := Models.hash2(k * 2.7 + i * 1.9, m * 1.7 + i * 0.3)
		var bu := lerpf(u0 + 3.0, u1 - 3.0, Models.hash2(h * 9.0, i * 1.1))
		var bv := lerpf(v0 + 3.0, v1 - 3.0, Models.hash2(i * 2.3, h * 7.0))
		var big := i == 0 or h < 0.4
		var ln := 4.6 if big else 1.8
		var half := Vector2(ln * 0.5, 0.0) if long_u else Vector2(0.0, ln * 0.5)
		var ok := true
		for q: Vector2 in [Vector2(bu, bv) - half, Vector2(bu, bv), Vector2(bu, bv) + half]:
			var w := to_world(q.x, q.y)
			ok = ok and c.raw(w.x, w.z) < -0.03
		if not ok:
			continue
		Models.count("barge" if big else "boat")
		c.at(bu, bv, wy, 1.0 / Models.PROP_V)
		if not long_u:
			b.xf = b.xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		if big:
			b.box(Vector3(0, 0.12, 0), Vector3(4.6, 0.5, 1.3), Color8(0x3a, 0x34, 0x30))   # the hull
			b.box(Vector3(0, 0.38, 0), Vector3(4.4, 0.04, 1.14), Color8(0x5a, 0x50, 0x46))   # the deck
			for j in 3:
				var cc: Color = SHOPS[int(h * 31.0 + j) % SHOPS.size()].darkened(0.15)
				if Models.hash2(h * 5.0 + j, 2.0) < 0.75:
					b.box(Vector3(-1.3 + j * 0.95, 0.62, 0), Vector3(0.85, 0.45, 0.95), cc)   # containers
			b.box(Vector3(1.85, 0.75, 0), Vector3(0.7, 0.7, 0.9), Color8(0xd8, 0xd4, 0xcc))   # the wheelhouse
			b.box(Vector3(1.85, 1.13, 0), Vector3(0.8, 0.06, 1.0), DARK)
		else:
			b.box(Vector3(0, 0.1, 0), Vector3(1.8, 0.3, 0.7), Color8(0xd8, 0xd4, 0xcc))
			b.box(Vector3(-0.2, 0.32, 0), Vector3(0.6, 0.2, 0.5), Color8(0x3a, 0x48, 0x58))
	b.xf = Transform3D.IDENTITY
	# trees on its grassy banks
	for i in 6:
		var tu := lerpf(u0 + 1.0, u1 - 1.0, Models.hash2(k * 1.1 + i, m * 0.9))
		var tv := lerpf(v0 + 1.0, v1 - 1.0, Models.hash2(m * 1.3 + i, k * 0.7 + i))
		var w := to_world(tu, tv)
		if c.raw(w.x, w.z) > 0.06:
			tree(c, tu, tv, c.ground(w.x, w.z), 0.9, tu)


## What fills block (k, m) (Guillaume, 2026-11-27: "all city blocks should be filled with
## something... mainly Manhattan like buildings... bigger buildings like a capitol"): mostly
## "towers" (lots of towers and mid-rises), now and then a "park", a "stadium", a shopping "mall",
## a domed "capitol" or a columned "hall". Never an empty plaza or a bare block.
static func block_kind(k: int, m: int, size := Vector2i.ONE) -> String:
	# hashed twice: one pass of the sine hash runs in streaks down a column of blocks
	var h := Models.hash2(Models.hash2(k * 0.73 + 0.1, m * 1.31 + 0.2) * 57.1, k * 0.11 + m * 0.07)
	var kinds: Array = BLOCK_KINDS if size == Vector2i.ONE else (QUAD_KINDS if size == Vector2i(2, 2) else PAIR_KINDS)
	for kd: Array in kinds:
		if h < kd[1]:
			return kd[0]
		h -= kd[1]
	return "towers"


## A built block: a sidewalk all round, then a grid of lots (or a courtyard ring) of buildings.
static func lots(c: Ctx, k: int, m: int, u0: float, u1: float, v0: float, v1: float) -> void:
	c.pad(u0, u1, v0, v1, 0.16, Models.KERB.darkened(0.08), 2.0)
	var i0 := u0 + 0.5
	var i1 := u1 - 0.5
	var j0 := v0 + 0.5
	var j1 := v1 - 0.5
	# the skyline: towers climb to each stretch's downtown, lower streets round it
	var tall := skyline((u0 + u1) * 0.5, (v0 + v1) * 0.5)
	# and midtown (Guillaume, 2026-11-26: "I want more tall buildings in the city"): away from the
	# downtowns most blocks still hold a few high towers, so the whole city stands tall, not just its peaks
	var rise := maxf(tall, midtown(k, m))
	var towers := midtown(k, m) > 0.0
	if boulevard(m):
		# the row just below a boulevard (on the camera's side) stays low, mid-rises and shops, so
		# the tanks driving along it aren't hidden behind towers
		rise = minf(rise, 0.15)
		towers = false
	var sd := Models.hash2(k * 1.7 + 4.0, m * 5.3 + 1.0)
	if sd < 0.14 and not towers:
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
	# lots about 5-6 m across, so a joined block holds more towers, not fatter ones
	var nu := maxi(2, roundi((i1 - i0) / 5.5)) + int(sd * 7.0) % 2
	var nv := maxi(2, roundi((j1 - j0) / 5.5)) + int(sd * 13.0) % 2
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
			# on the low blocks the odd lot is a little square with a tree, or a car park
			if r < 0.07 and not towers:
				c.pad(a, bb, cc, d, 0.19, PARK, 2.0)
				var g := to_world((a + bb) * 0.5, (cc + d) * 0.5)
				tree(c, (a + bb) * 0.5, (cc + d) * 0.5, c.ground(g.x, g.z), 0.8, r * 9.0)
				continue
			if r < 0.11 and not towers:
				car_park(c, a, bb, cc, d, r)
				continue
			if Models.hash2(r * 17.0, k * 0.3 + m) < RUINS:
				ruin(c, (a + bb) * 0.5, (cc + d) * 0.5, bb - a, d - cc, r)
				continue
			var style := int(r * 41.0) % 4
			if style >= 2 and (towers or Models.hash2(r * 23.0, k * 0.7 + m * 1.3) < TOWER_MORE):
				style = int(r * 7.0) % 2   # more of the lots are towers
			var h := 0.35 + r * 0.5 + rise * 0.9
			if style < 2:
				h = 0.8 + rise * (3.4 + r * 1.4) + r * 0.4   # towers rise higher downtown
			building(c, (a + bb) * 0.5, (cc + d) * 0.5, bb - a, d - cc, h, r, style, Color(0, 0, 0, 0))


## One building on a lot w x d (metres) centred on (u, v), `h` tall (before PROP_V), in a style:
## 0 a setback tower, 1 a glass tower, 2 a brick mid-rise, 3 a shop with an awning.
static func building(c: Ctx, u: float, v: float, w: float, d: float, h: float, r: float, style: int, col: Color) -> void:
	var base := INF
	for q: Vector2 in [Vector2(u - w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v - d * 0.5), Vector2(u + w * 0.5, v + d * 0.5),
			Vector2(u - w * 0.5, v + d * 0.5), Vector2(u, v)]:
		var p := to_world(q.x, q.y)
		base = minf(base, c.ground(p.x, p.z))
	if not c.dry:
		c.at(u, v, base)
	c.cap = (Rules.PY - 0.65 - base) / Models.PROP_V
	h = minf(h, c.cap - 0.25)   # room for the roof slab or AC units
	# its shadow over the streets (shops are a low row: about their mean height)
	var fw := w * (0.9 if style == 1 else 1.0)
	var fd := d * (0.9 if style == 1 else 1.0)
	var ft := base + (0.45 if style == 3 else h + (0.1 if style == 1 else 0.0)) * Models.PROP_V
	if not c.casters.has(c.km):
		c.casters[c.km] = []
	c.casters[c.km].append([u - fw * 0.5, u + fw * 0.5, v - fd * 0.5, v + fd * 0.5, ft])
	if c.dry:
		return
	Models.count("building")
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
				if not c.burning and q > 1.0 - NEON * 2.0:
					var nc: Color = NEONS[int(q * 53.0) % NEONS.size()]
					glow(c, Vector3(x - sw * 0.26, hh + 0.02, d * 0.5 - 0.025), Vector3(x + sw * 0.26, hh + 0.02, d * 0.5 - 0.025),
						Vector3(x + sw * 0.26, hh + 0.08, d * 0.5 - 0.025), Vector3(x - sw * 0.26, hh + 0.08, d * 0.5 - 0.025), nc, true)
				if q < 0.3:
					b.box(Vector3(x, hh + 0.04, -d * 0.15), Vector3(0.4, 0.08, 0.3), Color8(0xc4, 0xc8, 0xce))   # an AC unit
				top = maxf(top, hh)
	b.bevels = false
	if style < 2 and not c.burning and Models.hash2(u * 0.61 + 3.0, v * 0.47 + r) < NEON:
		# a tall neon sign down the tower's front corner
		var fx := w * (0.45 if style == 1 else 0.5) - 0.18
		var fz := d * (0.45 if style == 1 else 0.5) + 0.03
		var nc: Color = NEONS[int(r * 61.0) % NEONS.size()]
		var y1 := minf(top - 0.25, 0.4 + 1.6 * Models.hash2(r, u))
		if y1 > 0.7:
			glow(c, Vector3(fx - 0.07, 0.3, fz), Vector3(fx + 0.07, 0.3, fz), Vector3(fx + 0.07, y1, fz), Vector3(fx - 0.07, y1, fz), nc, true)
		# and a sign on the roof, leaning back to face the sky (seen from above, unlike a wall)
		if c.cap - top > 0.3:
			var sw := minf(w, d) * 0.3
			var z0 := d * 0.2
			var y0 := top + 0.05
			glow(c, Vector3(-sw, y0, z0), Vector3(sw, y0, z0), Vector3(sw, y0 + 0.14, z0 - 0.3), Vector3(-sw, y0 + 0.14, z0 - 0.3), nc, true)
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
	var o := b.xf.origin
	while y + 0.06 < y1:
		var a := y
		var e := y + 0.06
		b.quad(Vector3(-w * 0.46, a, d * 0.5 + 0.01), Vector3(w * 0.46, a, d * 0.5 + 0.01), Vector3(w * 0.46, e, d * 0.5 + 0.01),
			Vector3(-w * 0.46, e, d * 0.5 + 0.01), col, Vector3(0, 0, 1))
		if not c.burning:
			# a few lit offices along the front
			var n := maxi(1, int(w / 0.5))
			for i in n:
				if Models.hash2(o.x * 1.3 + i * 0.71, o.z * 0.9 + y * 3.1) < LIT:
					var x0 := -w * 0.46 + w * 0.92 * i / n
					var x1 := x0 + w * 0.92 / n * 0.85
					glow(c, Vector3(x0, a, d * 0.5 + 0.015), Vector3(x1, a, d * 0.5 + 0.015), Vector3(x1, e, d * 0.5 + 0.015),
						Vector3(x0, e, d * 0.5 + 0.015), LAMP.darkened(Models.hash2(i, y) * 0.25))
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
			if not c.burning and Models.hash2(x * 1.7 + r, y * 2.3) < LIT:
				glow(c, Vector3(x - 0.12, y + 0.01, d * 0.5 + 0.015), Vector3(x + 0.12, y + 0.01, d * 0.5 + 0.015),
					Vector3(x + 0.12, y + 0.07, d * 0.5 + 0.015), Vector3(x - 0.12, y + 0.07, d * 0.5 + 0.015), LAMP)
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
	if c.dry:
		return
	Models.count("city tree")
	c.at(u, v, y)
	var col := Models.LEAF.darkened(0.4 + fmod(r, 1.0) * 0.2).lerp(Color8(0x4a, 0x44, 0x34), 0.35)
	c.b.prism(Vector3.ZERO, Models.ngon(0.1, 4), -0.1, 0.35, Models.WOOD.darkened(0.4))
	c.b.prism(Vector3(0, 0.3, 0), Models.ngon(0.55 * s, 7, r), 0, 0.3, col, Vector2(1.05, 1.05))
	c.b.prism(Vector3(0, 0.6, 0), Models.ngon(0.6 * s, 7, r + 0.3), 0, 0.3, col.lightened(0.07), Vector2(0.35, 0.35))


## Parked cars in rows on a lot.
static func car_park(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	if c.dry:
		return
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


# ---------------------------------------------------------------- parks, stadiums, landmarks

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
	# trees fill each quarter of the park between its paths, mostly alive, the odd one burnt
	var su := (u1 - u0) * 0.5
	var sv := (v1 - v0) * 0.5
	for qu in [-1.0, 1.0]:
		for qv in [-1.0, 1.0]:
			var ni := maxi(2, int((su - 1.9) / 2.4))
			var nj := maxi(2, int((sv - 1.9) / 2.4))
			for i in ni:
				for j in nj:
					var a := Models.hash2(r * 17.0 + i + qu * 3.0, j * 1.3 + qv)
					var e := Models.hash2(i * 2.1 + qv, r * 5.0 + j + qu)
					var tu: float = cu + qu * (1.3 + (i + 0.25 + a * 0.5) * (su - 1.9) / ni)
					var tv: float = cv + qv * (1.3 + (j + 0.25 + e * 0.5) * (sv - 1.9) / nj)
					var w := to_world(tu, tv)
					if Models.hash2(a * 7.0, e * 3.0) < 0.15:
						dead_tree(c, tu, tv, c.ground(w.x, w.z), a)
					else:
						tree(c, tu, tv, c.ground(w.x, w.z), 0.9 + a * 0.5, a)
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


## A proper square (Guillaume, 2026-11-27: "some place here and there but that should look like a
## proper square, not an empty block"): bordered, patterned paving, lawns in its corners between
## a cross of paths, a monument (an obelisk, a column with a statue) or a big fountain at its heart
## on a round step, rows of trees all round its edge, lamps, benches and kiosks.
static func square(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	Models.count("square")
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	var w := u1 - u0
	var d := v1 - v0
	var stone := Color8(0xd8, 0xd2, 0xc4)
	c.pad(u0, u1, v0, v1, 0.16, PAVING.darkened(0.08), 2.0)
	c.pad(u0 + 1.6, u1 - 1.6, v0 + 1.6, v1 - 1.6, 0.17, PAVING, 1.6, PAVING.darkened(0.12))
	var pw := 1.0 + minf(w, d) * 0.04
	var rr := minf(w, d) * 0.1 + 0.9
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			var a: float = cu + su * pw
			var bb: float = u1 - 2.4 if su > 0.0 else u0 + 2.4
			var e: float = cv + sv * pw
			var f: float = v1 - 2.4 if sv > 0.0 else v0 + 2.4
			c.pad(minf(a, bb), maxf(a, bb), minf(e, f), maxf(e, f), 0.19, PARK, 2.0)
			# a few trees on each lawn
			var nl := clampi(int(absf(bb - a) / 3.5), 1, 3)
			for i in nl:
				for j in clampi(int(absf(f - e) / 3.5), 1, 3):
					var lu: float = lerpf(a, bb, (i + 0.5) / nl)
					var lv: float = lerpf(e, f, (j + 0.5) / clampi(int(absf(f - e) / 3.5), 1, 3))
					if Vector2(lu - cu, lv - cv).length() > rr + 0.8:
						var lw := to_world(lu, lv)
						tree(c, lu, lv, c.ground(lw.x, lw.z) + 0.05, 0.85, lu * 0.7 + lv * 0.3 + r)
			# a bench by each lawn, facing the middle
			var bu: float = cu + su * (pw + 0.5)
			var bv: float = cv + sv * (rr + 0.8)
			var bw := to_world(bu, bv)
			c.at(bu, bv, c.ground(bw.x, bw.z) + 0.16)
			c.b.box(Vector3(0, 0.06, 0), Vector3(0.12, 0.08, 0.9), Models.WOOD.darkened(0.2))
	var g := to_world(cu, cv)
	var y := c.ground(g.x, g.z)
	var b := c.b
	c.at(cu, cv, y)
	b.prism(Vector3.ZERO, Models.ngon(rr, 16), -0.1, 0.2, stone)   # the round step
	b.prism(Vector3.ZERO, Models.ngon(rr - 0.5, 16), 0.2, 0.24, PARK)
	# the monument grows with the square
	var ms := clampf(minf(w, d) / 11.0, 1.0, 1.8)
	c.at(cu, cv, y, fit(y, 3.0 * ms) * ms, ms)
	if r < 0.35:
		# an obelisk on a stepped plinth
		b.box(Vector3(0, 0.3, 0), Vector3(1.6, 0.2, 1.6), stone)
		b.prism(Vector3.ZERO, Models.ngon(0.42, 4, PI * 0.25), 0.4, 2.6, stone.lightened(0.06), Vector2(0.55, 0.55))
		b.prism(Vector3.ZERO, Models.ngon(0.24, 4, PI * 0.25), 2.6, 2.85, Color8(0xf2, 0xc4, 0x2e), Vector2(0.05, 0.05))
	elif r < 0.7:
		# a column topped with a bronze figure
		var bronze := Color8(0x5a, 0x6a, 0x5e)
		b.box(Vector3(0, 0.4, 0), Vector3(1.3, 0.4, 1.3), stone)
		b.prism(Vector3.ZERO, Models.ngon(0.3, 10), 0.6, 2.2, stone.lightened(0.06), Vector2(0.85, 0.85))
		b.box(Vector3(0, 2.25, 0), Vector3(0.7, 0.1, 0.7), stone)
		b.box(Vector3(0, 2.5, 0), Vector3(0.28, 0.4, 0.2), bronze)
		b.prism(Vector3(0, 0, 0), Models.ngon(0.1, 6), 2.7, 2.85, bronze, Vector2(0.6, 0.6))
		b.box(Vector3(0.18, 2.62, 0), Vector3(0.08, 0.08, 0.4), bronze)   # an arm, raised
	else:
		# a big fountain: a wide basin, a tiered bowl and a plume
		b.prism(Vector3.ZERO, Models.ngon(rr - 0.3, 16), 0.2, 0.36, stone)
		b.prism(Vector3.ZERO, Models.ngon(rr - 0.55, 16), 0.36, 0.37, WATER)
		b.prism(Vector3.ZERO, Models.ngon(0.4, 10), 0.36, 0.9, stone)
		b.prism(Vector3(0, 0.9, 0), Models.ngon(0.9, 12), 0.0, 0.12, stone, Vector2(1.2, 1.2))
		b.prism(Vector3.ZERO, Models.ngon(0.14, 6), 1.0, 1.6, Color8(0xe8, 0xf6, 0xff), Vector2(0.3, 0.3))
	# rows of trees round the edge, lamps between them
	var n := maxi(3, int(w / 3.0))
	for i in n:
		var tu := lerpf(u0 + 0.9, u1 - 0.9, float(i) / (n - 1))
		for tv: float in [v0 + 0.9, v1 - 0.9]:
			if absf(tu - cu) > pw + 0.3:
				var tw := to_world(tu, tv)
				tree(c, tu, tv, c.ground(tw.x, tw.z), 0.75, tu * 0.3 + tv)
	var nn := maxi(3, int(d / 3.0))
	for j in range(1, nn - 1):
		var tv := lerpf(v0 + 0.9, v1 - 0.9, float(j) / (nn - 1))
		for tu: float in [u0 + 0.9, u1 - 0.9]:
			if absf(tv - cv) > pw + 0.3:
				var tw := to_world(tu, tv)
				tree(c, tu, tv, c.ground(tw.x, tw.z), 0.75, tu + tv * 0.3)
	for q: Vector2 in [Vector2(cu - pw - 0.3, v1 - 1.8), Vector2(cu + pw + 0.3, v1 - 1.8), Vector2(cu - pw - 0.3, v0 + 1.8),
			Vector2(cu + pw + 0.3, v0 + 1.8)]:
		var lw := to_world(q.x, q.y)
		c.at(q.x, q.y, c.ground(lw.x, lw.z) + 0.16)
		b.prism(Vector3.ZERO, Models.ngon(0.05, 4), 0.0, 0.9, DARK)
		b.box(Vector3(0, 0.92, 0), Vector3(0.18, 0.08, 0.18), Color8(0xf4, 0xe2, 0xa8))
	# two kiosks with striped awnings by the paths
	for i in 2:
		var ku: float = cu + (i * 2 - 1) * (pw + 1.4)
		var kv: float = cv + (1 - i * 2) * (minf(d * 0.5, rr + 3.0) - 0.4)
		var kw := to_world(ku, kv)
		c.at(ku, kv, c.ground(kw.x, kw.z) + 0.16)
		b.box(Vector3(0, 0.15, 0), Vector3(0.9, 0.4, 0.7), Color8(0xf4, 0xf0, 0xe6))
		b.box(Vector3(0, 0.38, 0), Vector3(1.1, 0.05, 0.9), SHOPS[(i + int(r * 9.0)) % SHOPS.size()])
	b.xf = Transform3D.IDENTITY


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


## The lowest ground under u0..u1 x v0..v1, where a big building stands.
static func site(c: Ctx, u0: float, u1: float, v0: float, v1: float) -> float:
	var base := INF
	for q: Vector2 in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), Vector2((u0 + u1) * 0.5, (v0 + v1) * 0.5)]:
		var w := to_world(q.x, q.y)
		base = minf(base, c.ground(w.x, w.z))
	return base


## How much a big building `h` tall (raw) standing at `base` is squashed to stay under the ship.
static func fit(base: float, h: float) -> float:
	return minf(1.0, ((Rules.PY - 0.65 - base) / Models.PROP_V - 0.1) / h)


## A big building's shadow over the streets: its footprint u0..u1 x v0..v1 up to `top` (world).
static func casts(c: Ctx, u0: float, u1: float, v0: float, v1: float, top: float) -> void:
	if not c.casters.has(c.km):
		c.casters[c.km] = []
	c.casters[c.km].append([u0, u1, v0, v1, top])


## A shopping mall filling the block: a broad low box with a glass shopfront and shop signs all
## round, a canopy over its doors, a car park on one half of the roof and glass skylights over
## the arcade on the other.
static func mall(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	var w := u1 - u0 - 0.8
	var d := v1 - v0 - 0.8
	var h := 1.2 + r * 0.4
	var base := site(c, u0, u1, v0, v1)
	var sy := fit(base, h + 0.5)
	casts(c, cu - w * 0.5, cu + w * 0.5, cv - d * 0.5, cv + d * 0.5, base + h * Models.PROP_V * sy)
	if c.dry:
		return
	Models.count("mall")
	c.pad(u0, u1, v0, v1, 0.16, Models.KERB.darkened(0.08), 2.0)
	c.at(cu, cv, base, sy)
	var b := c.b
	var col: Color = PASTELS[int(r * 31.0) % PASTELS.size()].lightened(0.1)
	b.bevels = true
	b.box(Vector3(0, (h - 0.3) * 0.5, 0), Vector3(w, h + 0.3, d), col)
	b.bevels = false
	# the glass shopfront round the ground floor, a band of signs over it
	for sz in [-1.0, 1.0]:
		b.box(Vector3(0, 0.3, sz * (d * 0.5 + 0.02)), Vector3(w * 0.94, 0.36, 0.04), Models.GLASS)
		b.box(Vector3(sz * (w * 0.5 + 0.02), 0.3, 0), Vector3(0.04, 0.36, d * 0.94), Models.GLASS)
	for i in 4:
		var x := (i - 1.5) * w * 0.24
		var q := Models.hash2(r * 7.0 + i, i * 1.3)
		var sc: Color = SHOPS[int(q * 71.0) % SHOPS.size()]
		var z := d * 0.5 + 0.05
		b.box(Vector3(x, 0.66, z - 0.02), Vector3(w * 0.17, 0.16, 0.06), sc)
		if q < 0.45:
			var nc: Color = NEONS[int(q * 53.0) % NEONS.size()]
			glow(c, Vector3(x - w * 0.07, 0.62, z + 0.015), Vector3(x + w * 0.07, 0.62, z + 0.015),
				Vector3(x + w * 0.07, 0.7, z + 0.015), Vector3(x - w * 0.07, 0.7, z + 0.015), nc, true)
	b.box(Vector3(0, 0.52, d * 0.5 + 0.45), Vector3(2.6, 0.06, 0.9), DARK.lightened(0.3))   # the entrance canopy
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 1.2, 0.2, d * 0.5 + 0.82), Vector3(0.08, 0.6, 0.08), DARK)
	# the roof: a parapet, a car park deck on one side, stepped glass skylights on the other
	b.box(Vector3(0, h + 0.03, 0), Vector3(w + 0.1, 0.06, d + 0.1), col.lightened(0.15))
	var side := -1.0 if r < 0.5 else 1.0
	var pw := w * 0.5 - 0.5
	var px := side * w * 0.25
	b.box(Vector3(px, h + 0.07, 0), Vector3(pw, 0.03, d - 0.8), Models.ASPHALT.lightened(0.12))
	var rows := int((d - 0.8) / 1.0)
	for j in rows + 1:
		var z := -(d - 0.8) * 0.5 + j * (d - 0.8) / rows
		b.box(Vector3(px - pw * 0.25, h + 0.09, z), Vector3(pw * 0.35, 0.01, 0.04), Models.PAINT)
		b.box(Vector3(px + pw * 0.25, h + 0.09, z), Vector3(pw * 0.35, 0.01, 0.04), Models.PAINT)
	for t in 3:
		b.box(Vector3(-side * w * 0.25, h + 0.1 + t * 0.1, 0), Vector3(w * (0.3 - t * 0.08), 0.1, d * 0.78),
			Models.GLASS.lightened(0.12 + t * 0.06))
	for i in 2:
		b.box(Vector3(-side * w * 0.25 + (i - 0.5) * w * 0.32, h + 0.15, -d * 0.36), Vector3(0.5, 0.18, 0.4), Color8(0xc4, 0xc8, 0xce))
	# a few cars parked on the deck, nose in to the bays
	for j in rows:
		for sx in [-1.0, 1.0]:
			var q := Models.hash2(r * 11.0 + j, sx + r)
			if q < 0.55:
				var cu2: float = cu + px + sx * pw * 0.25
				var cv2 := cv - (d - 0.8) * 0.5 + (j + 0.5) * (d - 0.8) / rows
				var p := to_world(cu2, cv2)
				Models.car(b, Vector3(p.x, base + (h + 0.08) * Models.PROP_V * sy, p.z), ANGLE + PI * 0.5, q)
	b.xf = Transform3D.IDENTITY


## A capitol: a domed hall on a stepped plinth, wings either side, a columned portico at the
## front, a ring of columns round the drum and a lantern on the dome, set back on its lawn.
static func capitol(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	# built for one block, scaled up to fill its grounds (Guillaume: "capitol should take a few
	# blocks"), a little less in height than across, and kept under the ship
	var s := clampf(minf((u1 - u0) / 12.0, (v1 - v0) / 12.4), 1.0, 2.2)
	var hs := 1.0 + (s - 1.0) * 0.45
	var bv := cv - 0.9 * s   # the building stands back, its lawn and walk in front
	var base := site(c, u0, u1, v0, v1)
	var sy := fit(base, 4.1 * hs) * hs
	casts(c, cu - 5.0 * s, cu + 5.0 * s, bv - 2.2 * s, bv + 2.2 * s, base + 1.1 * Models.PROP_V * sy)
	casts(c, cu - 1.4 * s, cu + 1.4 * s, bv - 1.7 * s, bv + 1.1 * s, base + 3.3 * Models.PROP_V * sy)
	if c.dry:
		return
	Models.count("capitol")
	c.pad(u0, u1, v0, v1, 0.16, PARK, 2.0)
	c.pad(cu - 0.6 * s, cu + 0.6 * s, bv + 3.4 * s, v1, 0.19, PAVING, 2.0)
	c.pad(cu - 3.0 * s, cu + 3.0 * s, v1 - 1.6 * s, v1 - 0.6, 0.19, PAVING, 2.0)
	if s > 1.4:
		# a long pool down the lawn to the steps, on a stone rim
		c.pad(cu - 1.3 * s, cu + 1.3 * s, bv + 3.9 * s, v1 - 2.2 * s, 0.2, Color8(0xc8, 0xc2, 0xb4), 2.0)
		c.pad(cu - 1.0 * s, cu + 1.0 * s, bv + 4.1 * s, v1 - 2.4 * s, 0.23, WATER, 2.0)
	c.at(cu, bv, base, sy, s)
	var b := c.b
	var stone: Color = [Color8(0xd8, 0xd2, 0xc4), Color8(0xcc, 0xc8, 0xbe), Color8(0xd4, 0xc8, 0xb0)][int(r * 7.0) % 3]
	var dome: Color = Color8(0x7e, 0xa0, 0x92) if r < 0.6 else Color8(0xb8, 0xa0, 0x5a)
	b.bevels = true
	b.box(Vector3(0, -0.05, 0), Vector3(10.6, 0.3, 5.0), stone.darkened(0.12))   # the plinth
	for i in 3:
		var top := 0.1 - i * 0.07
		b.box(Vector3(0, (top - 0.2) * 0.5, 2.5 + i * 0.3 + 0.15), Vector3(3.8 + i * 0.4, top + 0.2, 0.3 + 0.01), stone.darkened(0.06 * i))
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 3.4, 0.6, 0), Vector3(3.4, 1.0, 4.2), stone)   # a wing
		b.box(Vector3(sx * 3.4, 1.12, 0), Vector3(3.55, 0.05, 4.35), stone.lightened(0.12))
	b.box(Vector3(0, 0.75, -0.1), Vector3(3.4, 1.3, 4.4), stone)   # the central hall
	b.box(Vector3(0, 1.42, -0.1), Vector3(3.55, 0.05, 4.55), stone.lightened(0.12))
	b.bevels = false
	# tall windows along the wings' fronts
	for sx in [-1.0, 1.0]:
		for i in 5:
			var x: float = sx * (1.95 + i * 0.6)
			for y: float in [0.3, 0.72]:
				b.quad(Vector3(x - 0.1, y, 2.11), Vector3(x + 0.1, y, 2.11), Vector3(x + 0.1, y + 0.26, 2.11), Vector3(x - 0.1, y + 0.26, 2.11),
					Color8(0x2c, 0x30, 0x36), Vector3(0, 0, 1))
	# the portico: six columns, the entablature and a pediment
	for i in 6:
		b.prism(Vector3(-1.5 + i * 0.6, 0, 2.45), Models.ngon(0.1, 6), 0.1, 1.15, stone.lightened(0.08))
	b.box(Vector3(0, 1.22, 2.15), Vector3(3.6, 0.14, 1.0), stone)
	var fz := 2.65
	b.tri(Vector3(-1.8, 1.29, fz), Vector3(1.8, 1.29, fz), Vector3(0, 1.7, fz), stone.lightened(0.05), Vector3(0, 0, 1))
	for sx in [-1.0, 1.0]:
		b.quad(Vector3(sx * 1.8, 1.29, fz), Vector3(0, 1.7, fz), Vector3(0, 1.7, 1.65), Vector3(sx * 1.8, 1.29, 1.65), stone.darkened(0.1),
			Vector3(sx * 0.4, 1, 0))
	# the drum, ringed with columns, then the dome and its lantern
	var dz := -0.3
	b.prism(Vector3(0, 0, dz), Models.ngon(1.3, 16), 1.4, 2.05, stone)
	for i in 16:
		var a := TAU * (i + 0.5) / 16.0
		b.box(Vector3(cos(a) * 1.42, 1.72, dz + sin(a) * 1.42), Vector3(0.1, 0.6, 0.1), stone.lightened(0.1))
	b.prism(Vector3(0, 0, dz), Models.ngon(1.55, 16), 2.02, 2.1, stone.lightened(0.12))
	var rad := 1.3
	var steps := 5
	for i in steps:
		var a0 := 0.45 * PI * i / steps
		var a1 := 0.45 * PI * (i + 1) / steps
		var k := cos(a1) / cos(a0)
		b.prism(Vector3(0, 0, dz), Models.ngon(rad * cos(a0), 16), 2.1 + rad * sin(a0) * 0.95, 2.1 + rad * sin(a1) * 0.95,
			dome.lightened(0.04 * i), Vector2(k, k))
	var ly := 2.1 + rad * sin(0.45 * PI) * 0.95
	b.prism(Vector3(0, 0, dz), Models.ngon(0.22, 8), ly, ly + 0.35, stone.lightened(0.1))
	b.prism(Vector3(0, 0, dz), Models.ngon(0.26, 8), ly + 0.35, ly + 0.5, dome, Vector2(0.2, 0.2))
	b.prism(Vector3(0, 0, dz), Models.ngon(0.04, 4), ly + 0.5, ly + 0.75, Color8(0xf2, 0xc4, 0x2e), Vector2(0.3, 0.3))
	b.xf = Transform3D.IDENTITY
	# rows of trees down both sides of the lawn
	var tv := v1 - 1.1
	while tv > bv + 2.8 * s:
		for q: Vector2 in [Vector2(u0 + 1.0, tv), Vector2(u1 - 1.0, tv)]:
			var w := to_world(q.x, q.y)
			tree(c, q.x, q.y, c.ground(w.x, w.z), 0.8, q.x * 0.1 + tv * 0.37 + r)
		tv -= 2.6


## A columned hall (a museum, a library, a court): a temple front on a stepped base, columns all
## round, a gabled roof with a pediment at each end, its forecourt with a fountain and trees.
static func hall(c: Ctx, u0: float, u1: float, v0: float, v1: float, r: float) -> void:
	var cu := (u0 + u1) * 0.5
	var cv := (v0 + v1) * 0.5
	var bv := cv - 1.35
	var hw := 3.3
	var hd := 3.6
	var base := site(c, u0, u1, v0, v1)
	var sy := fit(base, 2.3)
	casts(c, cu - hw, cu + hw, bv - hd, bv + hd, base + 1.8 * Models.PROP_V * sy)
	if c.dry:
		return
	Models.count("hall")
	c.pad(u0, u1, v0, v1, 0.16, PAVING, 1.6, PAVING.darkened(0.12))
	var b := c.b
	c.at(cu, bv, base, sy)
	var stone: Color = [Color8(0xd8, 0xd2, 0xc4), Color8(0xc8, 0xbe, 0xae), Color8(0xd0, 0xcc, 0xc4)][int(r * 11.0) % 3]
	var roof_col: Color = Color8(0x5a, 0x6e, 0x66) if r < 0.5 else Color8(0x4a, 0x4c, 0x52)
	b.bevels = true
	for i in 3:   # the stepped base
		var g := 0.3 * (3 - i)
		b.box(Vector3(0, -0.2 + 0.075 * (i + 1) * 0.5 + 0.0, 0), Vector3((hw + g) * 2.0, 0.075 * (i + 1) + 0.2, (hd + g) * 2.0),
			stone.darkened(0.12 - i * 0.04))
	b.box(Vector3(0, 0.8, 0), Vector3((hw - 0.7) * 2.0, 1.3, (hd - 0.7) * 2.0), stone.darkened(0.08))   # the walls behind
	b.bevels = false
	var y0 := 0.15
	var y1 := 1.45
	for i in 7:
		for sz in [-1.0, 1.0]:
			b.prism(Vector3(-hw + 0.3 + i * (hw - 0.3) * 2.0 / 6.0, 0, sz * (hd - 0.3)), Models.ngon(0.12, 6), y0, y1, stone.lightened(0.08))
	for i in range(1, 7):
		for sx in [-1.0, 1.0]:
			b.prism(Vector3(sx * (hw - 0.3), 0, -hd + 0.3 + i * (hd - 0.3) * 2.0 / 7.0), Models.ngon(0.12, 6), y0, y1, stone.lightened(0.08))
	b.box(Vector3(0, y1 + 0.09, 0), Vector3(hw * 2.0, 0.18, hd * 2.0), stone)   # the entablature
	b.box(Vector3(0, y1 + 0.05, 0), Vector3(hw * 2.0 + 0.02, 0.05, hd * 2.0 + 0.02), stone.darkened(0.15))   # its frieze
	var ey := y1 + 0.18
	var ry := ey + 0.55
	for sx in [-1.0, 1.0]:
		b.quad(Vector3(sx * (hw + 0.05), ey, -hd - 0.05), Vector3(0, ry, -hd - 0.05), Vector3(0, ry, hd + 0.05), Vector3(sx * (hw + 0.05), ey, hd + 0.05),
			roof_col, Vector3(sx * 0.4, 1, 0))
	for sz in [-1.0, 1.0]:
		b.tri(Vector3(-hw, ey, sz * hd), Vector3(hw, ey, sz * hd), Vector3(0, ry - 0.04, sz * hd), stone.lightened(0.05), Vector3(0, 0, sz))
	# a banner between the front columns
	var bc: Color = SHOPS[int(r * 13.0) % SHOPS.size()]
	b.quad(Vector3(-0.35, 0.5, hd - 0.2), Vector3(0.35, 0.5, hd - 0.2), Vector3(0.35, 1.25, hd - 0.2), Vector3(-0.35, 1.25, hd - 0.2), bc, Vector3(0, 0, 1))
	b.xf = Transform3D.IDENTITY
	# the forecourt: a fountain and trees in planters
	var fv := v1 - 1.45
	var w := to_world(cu, fv)
	fountain(c, cu, fv, c.ground(w.x, w.z))
	for su in [-1.0, 1.0]:
		var tu: float = cu + su * 4.4
		var tw := to_world(tu, fv)
		tree(c, tu, fv, c.ground(tw.x, tw.z), 0.8, tu * 0.1 + r)
	b.xf = Transform3D.IDENTITY


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
	if c.dry:
		return
	Models.count("dead tree")
	c.at(u, v, y)
	var col := Color8(0x2e, 0x28, 0x24)
	c.b.prism(Vector3.ZERO, Models.ngon(0.1, 4), -0.1, 0.75, col, Vector2(0.4, 0.4))
	c.b.xf = c.b.xf * Transform3D(Basis(Vector3(0, 0, 1), 0.7).rotated(Vector3.UP, r * 6.0), Vector3(0, 0.35, 0))
	c.b.prism(Vector3.ZERO, Models.ngon(0.05, 4), 0.0, 0.4, col, Vector2(0.4, 0.4))


## A ruined building on a w x d lot at (u, v): broken walls, burnt floors and rubble, still burning.
static func ruin(c: Ctx, u: float, v: float, w: float, d: float, r: float) -> void:
	if c.dry:
		return
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
## A glowing quad (corners in the builder's current frame), for fx_mesh.
static func glow(c: Ctx, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, neon := false) -> void:
	var xf := c.b.xf
	glows.append([[xf * a, xf * b, xf * cc, xf * d], col, neon])


static func fx_mesh() -> ArrayMesh:
	if fires.is_empty() and glows.is_empty():
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
	var gv := PackedVector3Array()
	var gc := PackedColorArray()
	var gu := PackedVector2Array()
	var gu2 := PackedVector2Array()
	for g: Array in glows:
		var q: Array = g[0]
		var ph := Models.hash2(q[0].x, q[0].z)
		for k: int in [0, 1, 2, 0, 2, 3]:
			gv.append(q[k])
			gc.append(g[1])
			gu.append(Vector2(1.0 if g[2] else 0.0, ph))
			gu2.append(Vector2.ZERO)
	for e: Array in [[fv, null, fc, fu, fu2, fire_mat()], [sv, sn, sc, su, su2, smoke_mat()], [gv, null, gc, gu, gu2, glow_mat()]]:
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
static var _glow_mat: ShaderMaterial


## Lit windows and neon: unshaded; a neon (UV.x 1) hums, now and then a slow flicker.
static func glow_mat() -> ShaderMaterial:
	if _glow_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
void fragment() {
	float ph = UV.y * 6.283;
	float hum = 1.0 - UV.x * (0.12 + 0.12 * sin(TIME * 1.7 + ph)) * step(0.0, sin(TIME * 0.4 + ph * 3.0));
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * hum;
}
"""
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = sh
	return _glow_mat
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
