class_name Terrain
extends RefCounted
## The moon's surface under the play plane: a faceted height field with craters, ridges rising
## at both sides, crystal clusters, boulders and glowing fissures. Everything is a pure function
## of the world position, so chunks meet seamlessly and a stage always looks the same.
##
## Each chunk is baked into a handful of meshes (one draw call per material): the ground with
## per-face vertex colours, the crystals, the boulders and the fissures. Flat shading plus the
## low sun and its shadows do the rest of the work.

## Width of the ground strip (wider than the stage so wide screens and parallax stay covered).
const X0 := -170.0
const X1 := 170.0
## Column edges: dense in the middle where craters sit, coarse on the side ridges.
const COLS := [-300.0, -230.0, -170.0, -140.0, -116.0, -96.0, -80.0, -68.0, -58.0, -48.0, -40.0, -32.0, -24.0, -16.0, -8.0, 0.0,
	8.0, 16.0, 24.0, 32.0, 40.0, 48.0, 58.0, 68.0, 80.0, 96.0, 116.0, 140.0, 170.0, 230.0, 300.0]
const ROWS := 10
## The premium look (a look with `premium`): smooth ground, no triangle shows (Guillaume,
## 2026-11-22: "I don't want to see triangles"). A finer, regular grid with no jitter; every
## corner has its own normal (from the height field) and colour, shared by the faces round it,
## so light and colour flow across the faces instead of picking them out.
const COLS_P := [-300.0, -250.0, -205.0, -170.0, -145.0, -124.0, -106.0, -92.0, -80.0, -70.0, -62.0, -58.0,
	-54.0, -50.0, -46.0, -42.0, -38.0, -34.0, -30.0, -26.0, -22.0, -18.0, -14.0, -10.0, -6.0, -2.0, 2.0, 6.0, 10.0,
	14.0, 18.0, 22.0, 26.0, 30.0, 34.0, 38.0, 42.0, 46.0, 50.0, 54.0, 58.0, 62.0, 70.0, 80.0, 92.0, 106.0, 124.0,
	145.0, 170.0, 205.0, 250.0, 300.0]
const ROWS_P := 16
## Crater cells: one chance of a crater per this many world units.
const CRATER_CELL := 52.0


static func h2(x: float, y: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return s - floorf(s)


## Crater `k` (by cell): [x, world y, radius, depth], or an empty array.
static func crater(k: int) -> Array:
	if _craters.has(k):
		return _craters[k]
	var out := []
	if h2(k, 1.7) >= 0.3:
		var r := 8.0 + h2(k, 4.1) * 13.0
		out = [lerpf(-62.0, 62.0, h2(k, 2.3)), (k + 0.15 + h2(k, 3.9) * 0.7) * CRATER_CELL, r, r * 0.45]
	_craters[k] = out
	return out


static var _craters := {}
static var _mesas := {}


const MESA_CELL := 150.0


## Mesa `k` (by cell): [x, world y, half width, half length, height], or an empty array.
static func mesa(k: int) -> Array:
	if _mesas.has(k):
		return _mesas[k]
	var out := []
	if h2(k, 5.3) >= 0.4:
		var side := -1.0 if h2(k, 6.1) < 0.5 else 1.0
		out = [side * lerpf(20.0, 58.0, h2(k, 7.7)), (k + 0.3 + h2(k, 8.3) * 0.4) * MESA_CELL, 14.0 + h2(k, 9.1) * 12.0,
			22.0 + h2(k, 2.9) * 22.0, 9.0 + h2(k, 4.4) * 8.0]
	_mesas[k] = out
	return out


## A ridgeline's height (0..1) along world y: sharp crests and wide saddles, the sharpness of
## ridged noise from two folded sines. `s` is the side, `i` picks the ridge.
static func crest(wy: float, s: float, i: int) -> float:
	var f := 0.017 + 0.006 * i
	var a := 1.0 - absf(sin(wy * f + s * 1.3 * i + 0.6 * sin(wy * f * 0.37 + i)))
	var b := 1.0 - absf(sin(wy * f * 2.7 + s * 2.1 + i * 3.3))
	return pow(a, 3.0) * 0.75 + pow(b, 3.0) * 0.25


const RANGE_CELL := 560.0


## Mountain range `k` (by cell): [world y of its crest at x = 0, slope, half width, height], or [].
static func mountain(k: int) -> Array:
	if _ranges.has(k):
		return _ranges[k]
	var out := []
	if h2(k, 11.3) >= 0.35:
		out = [(k + 0.3 + h2(k, 12.7) * 0.4) * RANGE_CELL, (h2(k, 13.1) - 0.5) * 0.7, 26.0 + h2(k, 14.9) * 14.0,
			30.0 + h2(k, 15.3) * 14.0]
	_ranges[k] = out
	return out


static var _ranges := {}


## Large-scale tint between the two hues of the floor (0..1).
static func tint(x: float, wy: float) -> float:
	return 0.5 + 0.5 * sin(wy * 0.006 + x * 0.01) * cos(wy * 0.0041 - 1.1)


## Ground height at stage-wide x (centred, -63..63 is the play width) and world distance `wy`.
static func height(x: float, wy: float) -> float:
	var ax := absf(x)
	# side ridges: the ground climbs into ridged peaks beyond the stage edges, sharp crests
	# with saddles between them rather than a smooth swell
	var edge := smoothstep(52.0, 132.0, ax)
	var sd := signf(x)
	var ridge := edge * (26.0 + 6.0 * sin(wy * 0.023 + sd * 2.0) + crest(wy + x * 0.6, sd, 1) * 16.0)
	ridge += smoothstep(90.0, 230.0, ax) * crest(wy - x * 0.35, sd, 2) * 70.0
	# rolling floor
	var roll := sin(wy * 0.031 + x * 0.045) * 3.2 + sin(wy * 0.013 - x * 0.027 + 1.3) * 4.0
	var h := ridge + roll
	# a raised mesa now and then: a flat top with steep faceted sides
	var km := floori(wy / MESA_CELL)
	for k in range(km - 1, km + 2):
		var me := mesa(k)
		if me.is_empty():
			continue
		var q := Vector2((x - float(me[0])) / float(me[2]), (wy - float(me[1])) / float(me[3]))
		if absf(q.x) > 1.2 or absf(q.y) > 1.6:
			continue
		var d := absf(q.x) + absf(q.y) * 0.8 + 0.25 * q.length()
		h += float(me[4]) * (1.0 - smoothstep(0.82, 1.0, d))
	# now and then a ridged range crosses under the play field: sharp peaks and saddles along
	# a crest line, steep flanks either side
	var kr := floori(wy / RANGE_CELL)
	for k in range(kr - 1, kr + 2):
		var rg := mountain(k)
		if rg.is_empty():
			continue
		var dy := wy - (float(rg[0]) + x * float(rg[1]))
		var w: float = rg[2]
		if absf(dy) > w:
			continue
		var along := x + float(k) * 37.0
		var peak := 0.35 + 0.65 * crest(along * 1.7, float(k), 3)
		var side := 1.0 - absf(dy) / w
		h += float(rg[3]) * peak * pow(side, 1.6)
	var kc := floori(wy / CRATER_CELL)
	for k in range(kc - 1, kc + 2):
		var cr := crater(k)
		if cr.is_empty():
			continue
		var dx := x - float(cr[0])
		var dy := (wy - float(cr[1])) * 1.1
		var rr := float(cr[2]) * 1.8
		if dx * dx + dy * dy > rr * rr:
			continue
		var d := sqrt(dx * dx + dy * dy) / float(cr[2])
		if d < 1.0:
			h -= float(cr[3]) * (1.0 - d * d)
		h += float(cr[3]) * 0.55 * exp(-pow((d - 1.0) / 0.28, 2.0))
	# neon rivers cut their beds right across the floor
	var rd := river_dy(x, wy)
	if absf(rd.x) < 40.0:
		# a flat bed between sloping banks
		var carve := 1.0 - smoothstep(RIVER_BANK * 0.55, RIVER_BANK * 1.5, absf(rd.x))
		h = lerpf(h, RIVER_BED, carve)
	return h


## Neon rivers run across the screen, so the ship flies over them as the moon scrolls by:
## one chance of a river per RIVER_CELL units, meandering a little from side to side, cyan or
## pink.
const RIVER_BED := -9.0
const RIVER_BANK := 11.0
const RIVER_W := 4.2
const RIVER_CELL := 380.0
static var _rivers := {}


## River `k` (by cell): [world y of its centre line, phase, kind (0 cyan, 1 pink)], or [].
static func river(k: int) -> Array:
	if _rivers.has(k):
		return _rivers[k]
	var out := []
	if k >= 1 and h2(k, 11.3) < 0.8:
		out = [(k + 0.25 + h2(k, 12.7) * 0.5) * RIVER_CELL, h2(k, 13.1) * TAU, int(h2(k, 14.9) * 2.0) % 2]
	_rivers[k] = out
	return out


## Where river `r` crosses stage-wide x (its centre line's world y).
static func river_y(r: Array, x: float) -> float:
	var ph: float = r[1]
	return float(r[0]) + 16.0 * sin(x * 0.028 + ph) + 6.0 * sin(x * 0.071 + ph * 2.3)


## Distance (world y) from the nearest river's centre line, and that river's kind.
static func river_dy(x: float, wy: float) -> Vector2:
	var k0 := floori(wy / RIVER_CELL)
	var best := Vector2(1e9, 0)
	for k in range(k0 - 1, k0 + 2):
		var r := river(k)
		if r.is_empty():
			continue
		var d := wy - river_y(r, x)
		if absf(d) < absf(best.x):
			best = Vector2(d, float(r[2]))
	return best


## Colour of a ground face from its height and slope (sRGB). `pc` is `colors(pal)`.
static func face_color(pc: Dictionary, zc: float, up: float, jit: float, tn := 0.5) -> Color:
	var low: Color = (pc.low as Color).lerp(pc.low2, tn)
	var c := low.lerp(pc.mid, clampf((zc + 8.0) / 20.0, 0.0, 1.0))
	c = c.lerp(pc.high, smoothstep(16.0, 52.0, zc))
	# steep faces are a little darker and cooler, like exposed rock
	c = c.lerp(pc.cliff, (1.0 - clampf(up, 0.0, 1.0)) * 0.55)
	return c.lightened(jit * 0.06) if jit > 0.0 else c.darkened(-jit * 0.08)


static func colors(pal: Dictionary) -> Dictionary:
	var out := {low = Color(pal.t_low), low2 = Color(pal.t_low2), mid = Color(pal.t_mid), high = Color(pal.t_high), cliff = Color(pal.t_cliff),
		river = [Color(pal.river_a), Color(pal.river_b)]}
	# a graded look paints light into the ground itself (see `grade`)
	if pal.has("warm"):
		out.warm = Color(pal.warm)
		out.cool = Color(pal.cool)
	if pal.get("premium", false):
		out.premium = true
	return out


## Where the sun stands, for the light painted into a graded ground (it matches the game's sun).
const TO_SUN := Vector3(-0.376, 0.457, 0.806)


## Paints light into a face of a graded look: slopes that face the sun go warm, slopes turned
## away go cool and dark, hollows sink and crests catch the light. It costs nothing to draw.
## `n`: the normal of the ground's broad shape there (up), `hollow`: how far the ground
## around stands above it.
static func grade(pc: Dictionary, c: Color, n: Vector3, hollow: float) -> Color:
	var d := n.dot(TO_SUN) - TO_SUN.z
	# the premium look pushes light and shade further apart: warm sunlit slopes, deep cool hollows
	var p := 1.5 if pc.has("premium") else 1.0
	if d > 0.0:
		c = c.lerp(pc.warm, clampf(d * 2.8 * p, 0.0, 0.5 * p)).lightened(clampf(d * (p - 1.0) * 0.6, 0.0, 0.12))
	else:
		c = c.lerp(pc.cool, clampf(-d * 1.6 * p, 0.0, 0.7))
	if hollow > 0.0:
		c = c.lerp(pc.cool, clampf(hollow / 10.0, 0.0, 0.45)).darkened(clampf(hollow / 14.0 * p, 0.0, 0.35 * p))
	else:
		c = c.lightened(clampf(-hollow / 16.0, 0.0, 0.22))
	return c


## Builds chunk `c` (CHUNK units long) in chunk space: x across, y along (0..len), z up.
static func build_chunk(c: int, len: float, pal: Dictionary, mats: Dictionary) -> Node3D:
	var b := Builder.new(c, len, pal, mats)
	while not b.step():
		pass
	return b.node


## Builds a chunk a few rows at a time (`step()` until it returns true), so the game can
## spread the work over frames instead of hitching when a new strip of ground appears.
class Builder:
	var c: int
	var len: float
	var pal: Dictionary
	var pc: Dictionary
	var mats: Dictionary
	var y0: float
	var pts := []
	var ground := Acc.new()
	var row_t := 0
	var node: Node3D
	var _shape := {}  ## corner (x, y) -> [the ground's broad normal there, how hollow it is]
	var premium := false
	var cols: Array = COLS
	var rows := ROWS
	var pn := []  ## premium: each corner's normal, by row
	var pk := []  ## premium: each corner's colour, by row

	func _init(c_: int, len_: float, pal_: Dictionary, mats_: Dictionary) -> void:
		c = c_
		len = len_
		pal = pal_
		pc = Terrain.colors(pal)
		mats = mats_
		y0 = c * len
		premium = pal.get("premium", false)
		if premium:
			cols = COLS_P
			rows = ROWS_P

	## Does the next slice of work; true once `node` is ready.
	func step() -> bool:
		if premium:
			return _step_smooth()
		if pts.size() < rows + 1:
			for k in 4:
				if pts.size() < rows + 1:
					pts.append(_row(pts.size()))
			return false
		if row_t < rows:
			for k in 4:
				if row_t < rows:
					_tris(row_t)
					row_t += 1
			return false
		node = Terrain._features(c, len, pal, mats, ground, y0)
		return true

	func _row(j: int) -> Array:
		var row := []
		var ly := len * j / rows
		var amp := 1.0
		for i in cols.size():
			var x: float = cols[i]
			# jitter inner vertices so the grid never reads as a grid (same in every chunk)
			var jx := 0.0
			var jy := 0.0
			if i > 0 and i < cols.size() - 1:
				jx = (Terrain.h2(x, y0 + ly) - 0.5) * 3.0 * amp
			if j > 0 and j < rows:
				jy = (Terrain.h2(x + 7.0, y0 + ly) - 0.5) * 2.4 * amp
			row.append(Vector3(x + jx, ly + jy, Terrain.height(x + jx, y0 + ly + jy)))
		return row

	## The smooth ground is built from a grid of heights reaching PAD rows past each end of the
	## chunk (normals, the broad shape and the occlusion all read neighbours from it), so every
	## height is worked out once, and both chunks at a seam see the same numbers.
	const PAD := 7
	var hg := []

	func _step_smooth() -> bool:
		var need := rows + 1 + 2 * PAD
		if hg.size() < need:
			for k in 2:
				if hg.size() < need:
					var wy := y0 + (hg.size() - PAD) * len / rows
					var r := PackedFloat32Array()
					r.resize(cols.size())
					for i in cols.size():
						r[i] = Terrain.height(cols[i], wy)
					hg.append(r)
			return false
		if pts.size() < rows + 1:
			for k in 2:
				if pts.size() < rows + 1:
					pts.append(_row_smooth(pts.size()))
					if pts.size() >= 2:
						_tris_smooth(pts.size() - 2)
			return false
		node = Terrain._features(c, len, pal, mats, ground, y0)
		return true

	func _h(j: int, i: int) -> float:
		return (hg[clampi(j, -PAD, rows + PAD) + PAD] as PackedFloat32Array)[clampi(i, 0, cols.size() - 1)]

	## The slope (dh/dx, dh/dy) at corner (j, i) measured `k` cells either side.
	func _slope(j: int, i: int, k: int) -> Vector2:
		var i0 := maxi(0, i - k)
		var i1 := mini(cols.size() - 1, i + k)
		var dy := len / rows
		return Vector2((_h(j, i1) - _h(j, i0)) / (float(cols[i1]) - float(cols[i0])), (_h(j + k, i) - _h(j - k, i)) / (2.0 * k * dy))

	## A row of the smooth ground: the corners on a regular grid, each with its normal from the
	## height field's slope and its colour (height, slope, the painted light, the river's glow).
	func _row_smooth(j: int) -> Array:
		var row := []
		var nr := []
		var kr := []
		var ly := len * j / rows
		var wy := y0 + ly
		for i in cols.size():
			var x: float = cols[i]
			var h := _h(j, i)
			var sl := _slope(j, i, 1)
			var nrm := Vector3(-sl.x, -sl.y, 1.0).normalized()
			var col := Terrain.face_color(pc, h, nrm.z, 0.0, Terrain.tint(x, wy))
			# the broad shape (about 12 units round) for the painted light, and occlusion from
			# the ground standing round it, near and far
			var sb := _slope(j, i, 3)
			var broad := Vector3(-sb.x, -sb.y, 1.0).normalized()
			var hollow := (_h(j, i - 3) + _h(j, i + 3) + _h(j - 3, i) + _h(j + 3, i)) / 4.0 - h
			var far := (_h(j, i - 7) + _h(j, i + 7) + _h(j - 7, i) + _h(j + 7, i) + _h(j - 5, i - 5) + _h(j - 5, i + 5) + _h(j + 5, i - 5) + _h(j + 5, i + 5)) / 8.0
			hollow = maxf(hollow, (far - h) * 0.8)
			col = Terrain.grade(pc, col, broad, hollow)
			var rv := Terrain.river_dy(x, wy)
			var rd := absf(rv.x)
			var rk := exp(-pow(rd / 15.0, 2.0)) * 0.55 if rd < 30.0 else 0.0
			row.append(Vector3(x, ly, h))
			nr.append(nrm)
			kr.append(col.lerp(pc.river[int(rv.y)], rk))
		pn.append(nr)
		pk.append(kr)
		return row

	func _tris_smooth(j: int) -> void:
		var uvs := []
		for jj in [j, j + 1]:
			var r := []
			for p: Vector3 in pts[jj]:
				r.append(Vector2(p.x, y0 + p.y) / 32.0)
			uvs.append(r)
		for i in cols.size() - 1:
			var q := [[j, i], [j, i + 1], [j + 1, i], [j + 1, i + 1]]
			# split each cell along the diagonal that follows the ground's fold
			var za: float = pts[j][i].z + pts[j + 1][i + 1].z
			var zb: float = pts[j][i + 1].z + pts[j + 1][i].z
			var tris := [[q[0], q[1], q[3]], [q[0], q[3], q[2]]] if absf(za - zb) < 0.01 or za < zb else [[q[0], q[1], q[2]], [q[1], q[3], q[2]]]
			for t in tris:
				var a: Array = t[0]
				var b: Array = t[1]
				var cc: Array = t[2]
				ground.tri3n(pts[a[0]][a[1]], pts[b[0]][b[1]], pts[cc[0]][cc[1]], pk[a[0]][a[1]], pk[b[0]][b[1]], pk[cc[0]][cc[1]],
						pn[a[0]][a[1]], pn[b[0]][b[1]], pn[cc[0]][cc[1]], uvs[a[0] - j][a[1]], uvs[b[0] - j][b[1]], uvs[cc[0] - j][cc[1]])

	## A face's colour with the light painted in at corner `p` (chunk space). What the ground
	## does there is worked out once per corner and shared by the faces round it.
	func _graded(col: Color, p: Vector3) -> Color:
		var key := Vector2(p.x, p.y)
		if not _shape.has(key):
			var wy := y0 + p.y
			var hw := Terrain.height(p.x - 13.0, wy)
			var he := Terrain.height(p.x + 13.0, wy)
			var hs := Terrain.height(p.x, wy - 13.0)
			var hn := Terrain.height(p.x, wy + 13.0)
			var hollow := (hw + he + hs + hn) / 4.0 - p.z
			if premium:
				# occlusion: a wider ring as well, so crater floors, river beds and the feet
				# of ridges sink into soft shadow (baked: costs nothing to draw)
				var far := 0.0
				for a in 6:
					var ang := a * TAU / 6.0 + 0.4
					far += Terrain.height(p.x + cos(ang) * 30.0, wy + sin(ang) * 30.0)
				hollow = maxf(hollow, (far / 6.0 - p.z) * 0.8)
			_shape[key] = [Vector3((hw - he) / 26.0, (hs - hn) / 26.0, 1.0).normalized(), hollow]
		var sh: Array = _shape[key]
		return Terrain.grade(pc, col, sh[0], sh[1])

	func _tris(j: int) -> void:
		for i in cols.size() - 1:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var d: Vector3 = pts[j + 1][i]
			var e: Vector3 = pts[j + 1][i + 1]
			# alternate the diagonal so the facets don't line up
			var flip := (i + j + c) % 2 == 0
			var tris := [[a, b, e], [a, e, d]] if flip else [[a, b, d], [b, e, d]]
			var tn := Terrain.tint(a.x, y0 + a.y)
			for t in tris:
				var p0: Vector3 = t[0]
				var p1: Vector3 = t[1]
				var p2: Vector3 = t[2]
				var nrm := (p1 - p0).cross(p2 - p0).normalized()
				var nz := absf(nrm.z)
				var jit := Terrain.h2(p0.x + p2.y, y0 + p1.y) - 0.5
				var zc := (p0.z + p1.z + p2.z) / 3.0
				var col := Terrain.face_color(pc, zc, nz, jit, tn)
				var cx := (p0.x + p1.x + p2.x) / 3.0
				var cwy := y0 + (p0.y + p1.y + p2.y) / 3.0
				# the river's light spills onto its banks
				var rv := Terrain.river_dy(cx, cwy)
				var rd := absf(rv.x)
				var rc: Color = pc.river[int(rv.y)]
				var rk := exp(-pow(rd / 15.0, 2.0)) * 0.55 if rd < 30.0 else 0.0
				if not pc.has("warm"):
					ground.tri(p0, p1, p2, col.lerp(rc, rk), Vector3.BACK)
				else:
					# the painted light is worked out at each corner and blends across the
					# face, so it models hills and hollows without picking out the triangles
					ground.tri3(p0, p1, p2, _graded(col, p0).lerp(rc, rk), _graded(col, p1).lerp(rc, rk), _graded(col, p2).lerp(rc, rk), Vector3.BACK)


## The chunk's node: the ground mesh plus crystals, boulders and the odd fissure.
static func _features(c: int, len: float, pal: Dictionary, mats: Dictionary, ground: Acc, y0: float) -> Node3D:
	var g := Node3D.new()
	g.add_child(_mi(ground.mesh(), mats.ground, true))
	_river(g, len, y0, mats)
	var rng := RandomNumberGenerator.new()
	rng.seed = c * 7919 + 13
	# crystal clusters on the slopes and crater rims
	var cry := [Acc.new(), Acc.new()]
	for k in 3:
		var side := -1.0 if (k + c) % 2 == 0 else 1.0
		var cx := side * rng.randf_range(58.0, 104.0) if k < 2 else rng.randf_range(-50.0, 50.0)
		if k == 2 and rng.randf() < 0.55:
			continue
		var cy := rng.randf_range(6.0, len - 6.0)
		_cluster(cry[rng.randi() % 2], Vector3(cx, cy, height(cx, y0 + cy) - 1.0), rng, 1.0 if k < 2 else 0.7)
	for i in 2:
		if cry[i].count() > 0:
			g.add_child(_mi(cry[i].mesh(), mats.crystals[i], true))
	# boulders strewn over the floor
	var rocks := Acc.new()
	for k in 5:
		var bx := rng.randf_range(-72.0, 72.0)
		var by := rng.randf_range(3.0, len - 3.0)
		var r := rng.randf_range(1.6, 4.2)
		_boulder(rocks, Vector3(bx, by, height(bx, y0 + by) + r * 0.25), r, rng, pal)
	g.add_child(_mi(rocks.mesh(), mats.ground, true))
	# a glowing fissure now and then, winding across the floor
	if h2(c, 9.1) < 0.22:
		var fis := Acc.new()
		var fx := rng.randf_range(-48.0, 48.0)
		var p := Vector3(fx, 0.0, 0.0)
		var steps := 9
		var ang := rng.randf_range(-0.5, 0.5)
		var prev := Vector3.INF
		for s in steps + 1:
			var fy := len * float(s) / steps
			if s > 0:
				ang += rng.randf_range(-0.9, 0.9)
				p.x += sin(ang) * len / steps
			var q := Vector3(p.x, fy, height(p.x, y0 + fy) + 0.35)
			if prev != Vector3.INF:
				var w := 0.3 + 0.35 * sin(float(s) / steps * PI)
				var side_v := Vector3(q.y - prev.y, -(q.x - prev.x), 0).normalized() * w
				fis.tri(prev - side_v, prev + side_v, q + side_v, Color.WHITE, Vector3.BACK)
				fis.tri(prev - side_v, q + side_v, q - side_v, Color.WHITE, Vector3.BACK)
			prev = q
		g.add_child(_mi(fis.mesh(), mats.fissure_a if h2(c, 3.3) < 0.5 else mats.fissure_b, false))
	return g


## The rivers whose centre crosses this chunk: a bright flowing core and a wide soft glow,
## running across the whole ground strip.
static func _river(g: Node3D, len: float, y0: float, mats: Dictionary) -> void:
	var core := Acc.new()
	var wide := Acc.new()
	var k0 := floori(y0 / RIVER_CELL)
	for k in range(k0 - 1, k0 + 2):
		var r := river(k)
		if r.is_empty() or float(r[0]) < y0 or float(r[0]) >= y0 + len:
			continue
		var steps := 60
		var prev := []
		for i in steps + 1:
			var x := lerpf(X0 - 130.0, X1 + 130.0, float(i) / steps)
			var y := river_y(r, x) - y0
			var ty := river_y(r, x + 0.5) - river_y(r, x - 0.5)
			var side := Vector3(-ty, 1.0, 0).normalized()
			var p := Vector3(x, y, RIVER_BED + 1.2)
			if not prev.is_empty():
				for spec in [[core, RIVER_W], [wide, RIVER_W * 3.4]]:
					var acc: Acc = spec[0]
					var w: float = spec[1]
					var a0: Vector3 = prev[0] - prev[1] * w
					var a1: Vector3 = prev[0] + prev[1] * w
					var b0: Vector3 = p - side * w
					var b1: Vector3 = p + side * w
					var v0: float = prev[2] * 0.1
					var v1: float = x * 0.1
					acc.quad_uv(a0, a1, b1, b0, Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1), Color(float(r[2]), 0, 0))
			prev = [p, side, x]
	if core.count() == 0:
		return
	g.add_child(_mi(wide.mesh(), mats.river_glow, false))
	g.add_child(_mi(core.mesh(), mats.river, false))


## The river's material: additive, flowing stripes along it, brightest down the middle;
## vertex colour red picks cyan (0) or pink (1).
static func river_mat(energy: float, sharp: float, a: String, b: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 col_a : source_color;
uniform vec3 col_b : source_color;
uniform float energy = 2.0;
uniform float sharp = 1.5;
varying float kind;
void vertex() { kind = COLOR.r; }
void fragment() {
	float e = 1.0 - abs(UV.x * 2.0 - 1.0);
	float body = pow(e, sharp);
	float flow = 0.7 + 0.3 * sin(UV.y * 2.2 - TIME * 5.0) * sin(UV.y * 0.7 + TIME * 1.7);
	float glint = smoothstep(0.92, 1.0, sin(UV.y * 3.1 - TIME * 7.0)) * e;
	vec3 c = mix(col_a, col_b, step(0.5, kind));
	ALBEDO = c * energy * (body * flow + glint * 0.8);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("col_a", Color(a))
	m.set_shader_parameter("col_b", Color(b))
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("sharp", sharp)
	return m


## A cluster of 3-5 pointed hexagonal crystals leaning out from `at`.
static func _cluster(acc: Acc, at: Vector3, rng: RandomNumberGenerator, s: float) -> void:
	var n := rng.randi_range(3, 5)
	for i in n:
		var h := rng.randf_range(7.0, 16.0) * s * (1.25 if i == 0 else 1.0)
		var r := rng.randf_range(1.3, 2.4) * s
		var lean := Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.55, 0.55), 1.0).normalized()
		if i == 0:
			lean = Vector3(lean.x * 0.3, lean.y * 0.3, 1.0).normalized()
		var base := at + Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5), 0) * s
		var bas := Basis.looking_at(lean, Vector3.UP if absf(lean.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
		# Basis.looking_at points -Z at the target: map the crystal's +Z axis onto it
		var ax := -bas.z
		var u := bas.x
		var v := bas.y
		var ring_a := []
		var ring_b := []
		var sides := 6
		var tw := rng.randf() * TAU
		for k in sides:
			var a := tw + TAU * k / sides
			var off := (u * cos(a) + v * sin(a)) * r
			ring_a.append(base + off)
			ring_b.append(base + off * 0.9 + ax * h * 0.72)
		var tip := base + ax * h
		var ctr := base + ax * h * 0.45
		var col := Color.WHITE
		for k in sides:
			var k2 := (k + 1) % sides
			acc.convex(ring_a[k], ring_a[k2], ring_b[k2], col, ctr)
			acc.convex(ring_a[k], ring_b[k2], ring_b[k], col, ctr)
			acc.convex(ring_b[k], ring_b[k2], tip, col, ctr)


## A squashed faceted boulder (an icosahedron with jittered vertices).
static func _boulder(acc: Acc, at: Vector3, r: float, rng: RandomNumberGenerator, pal: Dictionary) -> void:
	var col := Color(pal.t_rock).darkened(rng.randf_range(0.0, 0.2))
	var jit := {}
	for t in Geo.ico(1.0):
		var tri := []
		for vv in t:
			var key: Vector3 = (vv * 100.0).round()
			if not jit.has(key):
				jit[key] = vv * (1.0 + rng.randf_range(-0.22, 0.22))
			var q: Vector3 = jit[key]
			tri.append(at + Vector3(q.x * r * 1.2, q.y * r, q.z * r * 0.7))
		acc.convex(tri[0], tri[1], tri[2], col, at)


static func _mi(m: ArrayMesh, mat: Material, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The ground material: lit, flat shaded, coloured per face.
static func ground_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.92
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The premium ground: the same, plus a fine cracked-plate relief from a tiling normal map, so
## the smooth ground has surface (fissures between plates) without showing a single triangle.
## Mapped by the chunk's own x and y over 32 units (a period that divides the chunk), so chunks meet.
static func ground_mat_premium() -> StandardMaterial3D:
	var m := ground_mat()
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_CELLULAR
	nz.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	nz.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	nz.frequency = 0.018
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	nz.seed = 7
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 10.0
	t.noise = nz
	m.normal_enabled = true
	m.normal_texture = t
	m.normal_scale = 1.5
	return m


## World 1 ground designs (Guillaume, 2026-11-22: the smooth ground looked "blurry"; "give me
## a few versions designed from scratch"). 0 is the smooth ground with its relief map; the
## others draw crisp detail per pixel on the same smooth mesh, so no triangle shows either way:
## 1 basalt plates split by sharp cracks, 2 strata (terraced bands with contour lines),
## 3 big polygon facets. Texture coordinates are world units / 32, continuous across chunks.
const DESIGNS := ["Smooth", "Basalt", "Strata", "Facets"]
static var design := 1

static var _design_shader: Shader


## The crisp ground for `design` d > 0 (`tri`: the canyon run's rock, which has no texture
## coordinates, maps by its own position instead).
static func ground_mat_design(d: int, pal: Dictionary, tri := false) -> ShaderMaterial:
	if _design_shader == null:
		_design_shader = Shader.new()
		_design_shader.code = DESIGN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _design_shader
	m.set_shader_parameter("style", d)
	m.set_shader_parameter("tri", tri)
	m.set_shader_parameter("crack", Color(pal.get("t_low", "0a1c4e")).darkened(0.55))
	m.set_shader_parameter("glow", Color((pal.get("fis", ["c0408a"]) as Array)[0]))
	return m


const DESIGN_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform int style = 1;
uniform bool tri = false;
uniform vec3 crack : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 glow : source_color = vec3(0.75, 0.25, 0.54);
varying vec3 op;
varying vec3 on;
varying float wz;

void vertex() {
	op = VERTEX;
	on = NORMAL;
	wz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// The cell of x and how far x is from the cell's nearest edge (in cells).
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) * 0.8 + 0.1 - f;
			vec2 dr = r - mr;
			if (dot(dr, dr) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(dr)));
			}
		}
	}
	return vec3(n + mg, md);
}

void fragment() {
	vec2 p;
	vec3 ta;
	vec3 tb;
	if (tri) {
		vec3 an = abs(on);
		vec3 ax;
		vec3 bx;
		if (an.z >= an.x && an.z >= an.y) {
			p = op.xy; ax = vec3(1.0, 0.0, 0.0); bx = vec3(0.0, 1.0, 0.0);
		} else if (an.x >= an.y) {
			p = op.yz; ax = vec3(0.0, 1.0, 0.0); bx = vec3(0.0, 0.0, 1.0);
		} else {
			p = op.xz; ax = vec3(1.0, 0.0, 0.0); bx = vec3(0.0, 0.0, 1.0);
		}
		mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
		ta = normalize((mv * vec4(ax, 0.0)).xyz);
		tb = normalize((mv * vec4(bx, 0.0)).xyz);
	} else {
		p = UV * 32.0;
		ta = TANGENT;
		tb = BINORMAL;
	}
	vec3 n = NORMAL;
	vec3 alb = COLOR.rgb;
	vec3 em = vec3(0.0);
	float rough = 0.88;
	if (style == 1) {
		// basalt: plates about 9 units across, each tilted and shaded its own way, cut by sharp cracks
		float s = 9.0;
		vec3 v = voronoi(p / s);
		float e = v.z * s;
		vec2 r = hash2(v.xy * 1.37 + 3.1) - 0.5;
		n = normalize(n + (ta * r.x + tb * r.y) * 0.45);
		alb *= 0.8 + 0.4 * hash2(v.xy + 7.7).x;
		float w = fwidth(e);
		float cr = 1.0 - smoothstep(0.13 - w, 0.13 + w, e);
		// a lit chamfer along each plate's rim
		alb *= 1.0 + 0.28 * (1.0 - smoothstep(0.13, 0.9, e));
		alb = mix(alb, crack, cr);
		// a few cracks glow where a slow vein crosses them
		float vein = smoothstep(0.76, 0.8, vnoise(p / 45.0));
		em = glow * cr * vein * 1.4;
	} else if (style == 2) {
		// strata: bands every 2.5 units of height, a dark riser under each tread, a fine contour line
		float h = wz / 2.5;
		float f = fract(h);
		float b = floor(h);
		float wb = 1.0 - smoothstep(0.18, 0.4, fwidth(h));
		alb *= 1.0 + wb * (0.2 * fract(b * 0.618) - 0.1);
		alb *= mix(1.0, mix(0.72, 1.0, smoothstep(0.0, 0.3, f)), wb);
		alb *= 1.0 + 0.18 * wb * smoothstep(0.75, 1.0, f);
		float d = min(f, 1.0 - f);
		float w = fwidth(h);
		// where bands crowd (steep faces) they fade into plain rock instead of shimmering
		float fade = 1.0 - smoothstep(0.18, 0.4, w);
		float ln = (1.0 - smoothstep(w * 0.6, w * 1.6, d)) * fade;
		alb = mix(alb, crack, ln * 0.85);
		// the treads lie flatter than the smooth slope, the risers steeper
		vec3 up = (VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
		n = normalize(mix(n, up, 0.35 * wb * smoothstep(0.25, 0.6, f)));
	} else if (style == 3) {
		// facets: big flat polygons (5 to 8 sides, never triangles), lit each its own way
		float s = 13.0;
		vec3 v = voronoi(p / s);
		vec2 r = hash2(v.xy * 2.13 + 1.7) - 0.5;
		n = normalize(n + (ta * r.x + tb * r.y) * 0.8);
		alb *= 0.86 + 0.28 * hash2(v.xy + 4.4).x;
		float e = v.z * s;
		float w = fwidth(e);
		alb *= 1.0 + 0.25 * (1.0 - smoothstep(0.05, 0.05 + w * 1.5, e));
		rough = 0.7;
	}
	ALBEDO = alb;
	NORMAL = n;
	ROUGHNESS = rough;
	EMISSION = em;
}
"""


## The same relief mapped on any shape (the canyon run's rock, which has no texture
## coordinates): three samples of the map instead of one, so only the run uses it.
static func rock_mat_premium(ground: StandardMaterial3D) -> StandardMaterial3D:
	var m := ground.duplicate() as StandardMaterial3D
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE / 32.0
	return m


## Crystal material: lit facets with an inner glow that still feeds the bloom.
static func crystal_mat(c: String, e: String, ei: float) -> StandardMaterial3D:
	var m := Models.std(c, e, ei)
	m.roughness = 0.25
	m.metallic = 0.1
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


## Triangle accumulator: vertices, flat normals and colours for one ArrayMesh.
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()

	func count() -> int:
		return v.size()

	## Adds triangle a, b, c facing `dir`.
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, dir: Vector3) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(dir) < 0.0:
			nrm = -nrm
			var t := b
			b = c
			c = t
		_add(a, b, c, nrm, color)

	## Adds triangle a, b, c facing `dir`, with a colour at each corner.
	func tri3(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, dir: Vector3) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(dir) < 0.0:
			nrm = -nrm
			var t := b
			b = c
			c = t
			var tc := cb
			cb = cc
			cc = tc
		v.append(a)
		v.append(c)
		v.append(b)
		for i in 3:
			n.append(nrm)
		col.append(ca)
		col.append(cc)
		col.append(cb)

	## Adds triangle a, b, c (facing up) with a colour and a normal at each corner.
	func tri3n(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, na: Vector3, nb: Vector3, nc: Vector3,
			ua := Vector2.INF, ub := Vector2.INF, uc := Vector2.INF, dir := Vector3.BACK) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		if nrm.dot(dir) < 0.0:
			var t := b
			b = c
			c = t
			var tc := cb
			cb = cc
			cc = tc
			var tn := nb
			nb = nc
			nc = tn
			var tu := ub
			ub = uc
			uc = tu
		v.append(a)
		v.append(c)
		v.append(b)
		n.append(na)
		n.append(nc)
		n.append(nb)
		if ua != Vector2.INF:
			uv.append(ua)
			uv.append(uc)
			uv.append(ub)
		col.append(ca)
		col.append(cc)
		col.append(cb)

	## Adds triangle a, b, c facing away from `center`.
	func convex(a: Vector3, b: Vector3, c: Vector3, color: Color, center: Vector3) -> void:
		tri(a, b, c, color, (a + b + c) / 3.0 - center)

	func _add(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, color: Color) -> void:
		# Godot treats clockwise triangles as front faces
		v.append(a)
		v.append(c)
		v.append(b)
		for i in 3:
			n.append(nrm)
			col.append(color)

	## Adds quad a b c d (in order round it) with texture coordinates, facing up.
	func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, color: Color) -> void:
		for t in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
			v.append(t[0])
			v.append(t[2])
			v.append(t[1])
			uv.append(t[3])
			uv.append(t[5])
			uv.append(t[4])
			for i in 3:
				n.append(Vector3.BACK)
				col.append(color)

	## Smooth shading (the premium look: no triangle shows): every corner takes the area-weighted
	## average normal, and colour, of the faces that meet at its point and lean less than
	## `crease` degrees from its own face; sharper folds stay sharp. Colours blend only with
	## `colors`. Work on local copies: writing a packed array of another object element by
	## element copies it each time.
	func smooth(crease := 60.0, colors := true) -> void:
		var vv := v
		var nn := n
		var cc := col
		var cnt := vv.size()
		var groups := {}
		var fn := PackedVector3Array()
		fn.resize(cnt / 3)
		for t in cnt / 3:
			var a := vv[t * 3]
			var w := (vv[t * 3 + 1] - a).cross(vv[t * 3 + 2] - a).length() * 0.5
			fn[t] = nn[t * 3] * w
			for k in 3:
				var key := Vector3i((vv[t * 3 + k] * 64.0).round())
				if groups.has(key):
					(groups[key] as Array).append(t * 3 + k)
				else:
					groups[key] = [t * 3 + k]
		var cmin := cos(deg_to_rad(crease))
		var out_n := nn.duplicate()
		var out_c := cc.duplicate()
		for key in groups:
			var ids: Array = groups[key]
			if ids.size() < 2:
				continue
			for i in ids:
				var own := nn[i]
				var sum := Vector3.ZERO
				var csum := Color(0, 0, 0, 0)
				var wsum := 0.0
				for j in ids:
					if nn[j].dot(own) < cmin:
						continue
					var f: Vector3 = fn[j / 3]
					sum += f
					var w := f.length()
					csum += cc[j] * w
					wsum += w
				if sum.length_squared() > 1e-12:
					out_n[i] = sum.normalized()
				if colors and wsum > 0.0:
					out_c[i] = csum / wsum
		n = out_n
		col = out_c

	## Tangents for a relief map laid flat: u runs along x (v along y) on ground and cliff tops,
	## along y (v down z) on cliff faces. Each is that axis laid onto the corner's own normal, so
	## corners shared by several faces get the same tangent and no seam shows.
	func _tangents() -> PackedFloat32Array:
		var out := PackedFloat32Array()
		out.resize(v.size() * 4)
		var vv := v
		var nn := n
		var uu := uv
		for i in vv.size():
			var nr := nn[i]
			var along_x := absf(uu[i].x * 32.0 - vv[i].x) < 0.01
			var ax := Vector3.RIGHT if along_x else Vector3.UP
			var bx := Vector3.UP if along_x else Vector3.BACK
			var t := (ax - nr * nr.dot(ax)).normalized()
			out[i * 4] = t.x
			out[i * 4 + 1] = t.y
			out[i * 4 + 2] = t.z
			out[i * 4 + 3] = 1.0 if nr.cross(t).dot(bx) >= 0.0 else -1.0
		return out

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = col
		if uv.size() == v.size() and uv.size() > 0:
			arrays[Mesh.ARRAY_TEX_UV] = uv
			arrays[Mesh.ARRAY_TANGENT] = _tangents()
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


## Offsets of a cliff top from its edge into the rock, and their heights above the edge.
const TOP_OFF := [0.0, 2.5, 9.0, 20.0, 38.0, 70.0, 130.0]
const TOP_Z := [0.0, 0.8, 2.6, 2.0, 4.5, 3.0, 5.0]
## How far the top climbs into ridged peaks at each offset, deep in the rock (times `crest`).
const TOP_PEAK := [0.0, 0.0, 1.0, 7.0, 18.0, 34.0, 46.0]
## Bands of a cliff face: depth below the edge and how far the face leans out at that depth.
const FACE_Z := [0.0, -9.0, -22.0, -38.0, -62.0]
const FACE_OUT := [0.0, 1.2, 3.4, 5.0, 8.0]
## The premium cliff's foot (Guillaume, 2026-11-22: "smooth the limit between canyon walls and the
## ground"): below the face, a slope of scree flares out and dives under the floor, its colour
## turning to the ground's, so the wall settles into the ground instead of standing on a line.
const FOOT_Z := [-50.0, -60.0, -69.0, -80.0]
const FOOT_OUT := [8.5, 12.0, 17.0, 23.0]
## And its shoulder (Guillaume: "rocks are very rarely 90 degrees"): the top rolls over into the
## face instead of meeting it at a right angle. Points from the edge into the rock: how far in,
## and how far below the plateau's edge height. The edge itself stays where the ship collides.
const SHOULDER := [[0.0, -4.5], [0.8, -2.2], [2.2, -0.7]]


## Rock with a faceted top and a banded cliff face. `rows` are [edge point (z = 0 is the
## ship's plane), how far the rock reaches inwards]; the rock lies on side `s` of the edge
## (-1: towards -x). The top and face are added to `acc` with per-face colours.
static func cliff(acc: Acc, rows: Array, s: float, pal: Dictionary, wy0: float) -> void:
	var tops := []
	var faces := []
	# the premium look shades rock by its shape and light, not by a random shade per facet
	var jk := 0.25 if pal.get("premium", false) else 1.0
	for r in rows:
		var e: Vector3 = r[0]
		var lim: float = r[1]
		var wy := wy0 + e.y
		var top := []
		for k in TOP_OFF.size():
			var o: float = minf(TOP_OFF[k], lim)
			var jz := (h2(wy, k * 3.1 + s) - 0.5) * 2.2 if k > 0 else 0.0
			var jy := (h2(wy + 1.0, k * 1.7 + s) - 0.5) * 2.0 if k > 0 else 0.0
			var tz := float(TOP_Z[k]) + float(TOP_PEAK[k]) * crest(wy, s, k)
			top.append(Vector3(e.x + s * o, e.y + jy, tz * (o / maxf(0.001, TOP_OFF[k]) if k > 0 else 0.0) + jz))
		tops.append(top)
		var face := []
		var prem: bool = pal.get("premium", false)
		# the premium face stops a band early: its foot takes over from there
		for m in (FACE_Z.size() - 1 if prem else FACE_Z.size()):
			var jx := (h2(wy, m * 5.3 - s) - 0.5) * 2.6 if m > 0 else 0.0
			face.append(Vector3(e.x - s * (float(FACE_OUT[m]) + jx), e.y, FACE_Z[m]))
		if prem:
			for m in FOOT_Z.size():
				var jx := (h2(wy, m * 7.1 + s) - 0.5) * 4.0
				face.append(Vector3(e.x - s * (float(FOOT_OUT[m]) + jx), e.y, FOOT_Z[m]))
		faces.append(face)
	if pal.get("premium", false):
		_cliff_smooth(acc, rows, tops, faces, s, pal, wy0)
		return
	for j in rows.size() - 1:
		var wy := wy0 + (rows[j][0] as Vector3).y
		for k in TOP_OFF.size() - 1:
			var a: Vector3 = tops[j][k]
			var b: Vector3 = tops[j][k + 1]
			var c: Vector3 = tops[j + 1][k]
			var d: Vector3 = tops[j + 1][k + 1]
			var jit := (h2(wy, k * 2.0) - 0.5) * jk
			var col := Color(pal.c_top).lerp(Color(pal.c_top2), float(k) / TOP_OFF.size())
			col = col.lightened(jit * 0.1) if jit > 0.0 else col.darkened(-jit * 0.12)
			# crests catch the light, saddles sink into the rock's darker tone
			var hz := (a.z + b.z + c.z + d.z) * 0.25
			col = col.darkened(0.12).lightened(clampf(hz / 40.0, 0.0, 1.0) * 0.3)
			acc.tri(a, b, d, col, Vector3.BACK)
			acc.tri(a, d, c, col.darkened(0.04), Vector3.BACK)
		for m in FACE_Z.size() - 1:
			var a: Vector3 = faces[j][m]
			var b: Vector3 = faces[j][m + 1]
			var c: Vector3 = faces[j + 1][m]
			var d: Vector3 = faces[j + 1][m + 1]
			var jit := (h2(wy, m * 4.0 + 1.0) - 0.5) * jk
			# strata: alternate bands are lighter and darker, deeper bands sink into shadow
			var col := Color(pal.c_face).darkened(float(m) * 0.12)
			if m % 2 == 1:
				col = col.lightened(0.07)
			col = col.lightened(jit * 0.08) if jit > 0.0 else col.darkened(-jit * 0.1)
			var out := Vector3(-s, 0, 0.35)
			acc.tri(a, b, d, col, out)
			acc.tri(a, d, c, col.darkened(0.05), out)


## The premium cliff: the same rock as one smooth sheet from the floor up the face, over a
## rounded shoulder and across the top. Each corner takes its normal from its neighbours along
## and across the sheet and its own colour (the ground's at the foot, the face's, then the
## top's), shared by the faces round it, so no triangle and no right angle shows.
static func _cliff_smooth(acc: Acc, rows: Array, tops: Array, faces: Array, s: float, pal: Dictionary, wy0 := 0.0) -> void:
	var pc := colors(pal)
	var floor_c := grade(pc, face_color(pc, -2.0, 0.9, 0.0, 0.5), Vector3.BACK, 4.0)
	var face_c := Color(pal.c_face)
	var g := []  # rows of points, bottom of the foot first
	var cols := []
	for j in rows.size():
		var e: Vector3 = (rows[j] as Array)[0]
		var face: Array = faces[j]
		var top: Array = tops[j]
		var pr := []
		var cr := []
		var nf := face.size()
		for m in range(nf - 1, 0, -1):
			pr.append(face[m])
			# the foot and the low face turn to the ground's colour
			var f := clampf(float(m - 1) / float(nf - 2), 0.0, 1.0)
			cr.append(face_c.darkened(0.1).lerp(floor_c, pow(f, 1.3)))
		for sh in SHOULDER:
			var o: float = sh[0]
			pr.append(Vector3(e.x + s * o, e.y, float(sh[1])))
			cr.append(face_c.lerp(Color(pal.c_top), o / 2.2 * 0.6 + 0.2))
		for k in range(2, top.size()):
			var p: Vector3 = top[k]
			pr.append(p)
			var c := Color(pal.c_top).lerp(Color(pal.c_top2), float(k) / TOP_OFF.size())
			cr.append(c.darkened(0.12).lightened(clampf(p.z / 40.0, 0.0, 1.0) * 0.3))
		g.append(pr)
		cols.append(cr)
	var nj := g.size()
	var nk: int = (g[0] as Array).size()
	var nrm := []
	var uv := []
	for j in nj:
		var nr := []
		var ur := []
		var arc := 0.0
		for k in nk:
			var p: Vector3 = g[j][k]
			if k > 0:
				arc += p.distance_to(g[j][k - 1])
			var du: Vector3 = g[j][mini(k + 1, nk - 1)] - g[j][maxi(k - 1, 0)]
			var dv: Vector3 = g[mini(j + 1, nj - 1)][k] - g[maxi(j - 1, 0)][k]
			var n := du.cross(dv).normalized()
			# outwards: into the canyon low down, up on the top
			if n.dot(Vector3(-s, 0, 0) if k < nk / 2 else Vector3.BACK) < 0.0:
				n = -n
			nr.append(n)
			ur.append(Vector2((wy0 + p.y) / 32.0, arc / 32.0))
		nrm.append(nr)
		uv.append(ur)
	for j in nj - 1:
		for k in nk - 1:
			for t in [[[j, k], [j, k + 1], [j + 1, k + 1]], [[j, k], [j + 1, k + 1], [j + 1, k]]]:
				var a: Array = t[0]
				var b: Array = t[1]
				var c: Array = t[2]
				var dir: Vector3 = nrm[a[0]][a[1]] + nrm[b[0]][b[1]] + nrm[c[0]][c[1]]
				acc.tri3n(g[a[0]][a[1]], g[b[0]][b[1]], g[c[0]][c[1]], cols[a[0]][a[1]], cols[b[0]][b[1]], cols[c[0]][c[1]],
						nrm[a[0]][a[1]], nrm[b[0]][b[1]], nrm[c[0]][c[1]], uv[a[0]][a[1]], uv[b[0]][b[1]], uv[c[0]][c[1]], dir)
