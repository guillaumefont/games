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


## Large-scale tint between the two hues of the floor (0..1).
static func tint(x: float, wy: float) -> float:
	return 0.5 + 0.5 * sin(wy * 0.006 + x * 0.01) * cos(wy * 0.0041 - 1.1)


## Ground height at stage-wide x (centred, -63..63 is the play width) and world distance `wy`.
static func height(x: float, wy: float) -> float:
	var ax := absf(x)
	# side ridges: the ground climbs into mountains beyond the stage edges
	var edge := smoothstep(52.0, 132.0, ax)
	var ridge := edge * (40.0 + 14.0 * sin(wy * 0.023 + signf(x) * 2.0) + 8.0 * sin(wy * 0.071 + x * 0.05))
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
	return {low = Color(pal.t_low), low2 = Color(pal.t_low2), mid = Color(pal.t_mid), high = Color(pal.t_high), cliff = Color(pal.t_cliff),
		river = [Color(pal.river_a), Color(pal.river_b)]}


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

	func _init(c_: int, len_: float, pal_: Dictionary, mats_: Dictionary) -> void:
		c = c_
		len = len_
		pal = pal_
		pc = Terrain.colors(pal)
		mats = mats_
		y0 = c * len

	## Does the next slice of work; true once `node` is ready.
	func step() -> bool:
		if pts.size() < ROWS + 1:
			for k in 4:
				if pts.size() < ROWS + 1:
					pts.append(_row(pts.size()))
			return false
		if row_t < ROWS:
			for k in 4:
				if row_t < ROWS:
					_tris(row_t)
					row_t += 1
			return false
		node = Terrain._features(c, len, pal, mats, ground, y0)
		return true

	func _row(j: int) -> Array:
		var row := []
		var ly := len * j / ROWS
		for i in COLS.size():
			var x: float = COLS[i]
			# jitter inner vertices so the grid never reads as a grid (same in every chunk)
			var jx := 0.0
			var jy := 0.0
			if i > 0 and i < COLS.size() - 1:
				jx = (Terrain.h2(x, y0 + ly) - 0.5) * 3.0
			if j > 0 and j < ROWS:
				jy = (Terrain.h2(x + 7.0, y0 + ly) - 0.5) * 2.4
			row.append(Vector3(x + jx, ly + jy, Terrain.height(x + jx, y0 + ly + jy)))
		return row

	func _tris(j: int) -> void:
		for i in COLS.size() - 1:
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
				var nz := absf((p1 - p0).cross(p2 - p0).normalized().z)
				var jit := Terrain.h2(p0.x + p2.y, y0 + p1.y) - 0.5
				var col := Terrain.face_color(pc, (p0.z + p1.z + p2.z) / 3.0, nz, jit, tn)
				# the river's light spills onto its banks
				var cx := (p0.x + p1.x + p2.x) / 3.0
				var cwy := y0 + (p0.y + p1.y + p2.y) / 3.0
				var rv := Terrain.river_dy(cx, cwy)
				var rd := absf(rv.x)
				if rd < 30.0:
					var rc: Color = pc.river[int(rv.y)]
					col = col.lerp(rc, exp(-pow(rd / 15.0, 2.0)) * 0.55)
				ground.tri(p0, p1, p2, col, Vector3.BACK)


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

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = col
		if uv.size() == v.size() and uv.size() > 0:
			arrays[Mesh.ARRAY_TEX_UV] = uv
		var m := ArrayMesh.new()
		if v.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


## Offsets of a cliff top from its edge into the rock, and their heights above the edge.
const TOP_OFF := [0.0, 2.5, 9.0, 20.0, 38.0, 70.0, 130.0]
const TOP_Z := [0.0, 0.8, 2.6, 2.0, 4.5, 3.0, 5.0]
## Bands of a cliff face: depth below the edge and how far the face leans out at that depth.
const FACE_Z := [0.0, -9.0, -22.0, -38.0, -62.0]
const FACE_OUT := [0.0, 1.2, 3.4, 5.0, 8.0]


## Rock with a faceted top and a banded cliff face. `rows` are [edge point (z = 0 is the
## ship's plane), how far the rock reaches inwards]; the rock lies on side `s` of the edge
## (-1: towards -x). The top and face are added to `acc` with per-face colours.
static func cliff(acc: Acc, rows: Array, s: float, pal: Dictionary, wy0: float) -> void:
	var tops := []
	var faces := []
	for r in rows:
		var e: Vector3 = r[0]
		var lim: float = r[1]
		var wy := wy0 + e.y
		var top := []
		for k in TOP_OFF.size():
			var o: float = minf(TOP_OFF[k], lim)
			var jz := (h2(wy, k * 3.1 + s) - 0.5) * 2.2 if k > 0 else 0.0
			var jy := (h2(wy + 1.0, k * 1.7 + s) - 0.5) * 2.0 if k > 0 else 0.0
			top.append(Vector3(e.x + s * o, e.y + jy, float(TOP_Z[k]) * (o / maxf(0.001, TOP_OFF[k]) if k > 0 else 0.0) + jz))
		tops.append(top)
		var face := []
		for m in FACE_Z.size():
			var jx := (h2(wy, m * 5.3 - s) - 0.5) * 2.6 if m > 0 else 0.0
			face.append(Vector3(e.x - s * (float(FACE_OUT[m]) + jx), e.y, FACE_Z[m]))
		faces.append(face)
	for j in rows.size() - 1:
		var wy := wy0 + (rows[j][0] as Vector3).y
		for k in TOP_OFF.size() - 1:
			var a: Vector3 = tops[j][k]
			var b: Vector3 = tops[j][k + 1]
			var c: Vector3 = tops[j + 1][k]
			var d: Vector3 = tops[j + 1][k + 1]
			var jit := h2(wy, k * 2.0) - 0.5
			var col := Color(pal.c_top).lerp(Color(pal.c_top2), float(k) / TOP_OFF.size())
			col = col.lightened(jit * 0.1) if jit > 0.0 else col.darkened(-jit * 0.12)
			acc.tri(a, b, d, col, Vector3.BACK)
			acc.tri(a, d, c, col.darkened(0.04), Vector3.BACK)
		for m in FACE_Z.size() - 1:
			var a: Vector3 = faces[j][m]
			var b: Vector3 = faces[j][m + 1]
			var c: Vector3 = faces[j + 1][m]
			var d: Vector3 = faces[j + 1][m + 1]
			var jit := h2(wy, m * 4.0 + 1.0) - 0.5
			# strata: alternate bands are lighter and darker, deeper bands sink into shadow
			var col := Color(pal.c_face).darkened(float(m) * 0.12)
			if m % 2 == 1:
				col = col.lightened(0.07)
			col = col.lightened(jit * 0.08) if jit > 0.0 else col.darkened(-jit * 0.1)
			var out := Vector3(-s, 0, 0.35)
			acc.tri(a, b, d, col, out)
			acc.tri(a, d, c, col.darkened(0.05), out)
