class_name Models
extends RefCounted
## Low poly models built in code: flat shaded, vertex coloured, one mesh per object where
## possible (one draw call). Ported from the web prototype's Three.js models.

const WOOD := Color8(0x5e, 0x45, 0x32)
const PLANK := Color8(0x8c, 0x6a, 0x48)
const IRON := Color8(0x2d, 0x31, 0x34)
const RUST := Color8(0xb4, 0x53, 0x2f)
const SAIL := Color8(0xe9, 0xe4, 0xd8)
const FOG := Color8(0xa7, 0xb8, 0xb9)

static var _mat: StandardMaterial3D
static var _mat2: StandardMaterial3D
static var _sail_shader: Shader
static var _sea_shader: Shader
static var _cache := {}


## The shared vertex-coloured material (one for the whole game).
static func mat(double_sided := false) -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.95
		_mat2 = _mat.duplicate()
		_mat2.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mat2 if double_sided else _mat


static func flat_mat(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "flat%s%s" % [c.to_html(), alpha]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c, alpha)
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache[key] = m
	return _cache[key]


static func hash3(x: float, y: float, z: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453
	return s - floor(s)


## Collects coloured triangles from many parts into one flat-shaded mesh.
class Builder:
	var st := SurfaceTool.new()
	var n := 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)

	## One triangle given in the prototype's (Three.js, counter-clockwise) order.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		st.set_color(col)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
		n += 3

	## A Godot primitive, placed by `xf`, optionally jittered (deterministic per vertex position,
	## so shared corners stay joined).
	func prim(p: PrimitiveMesh, xf: Transform3D, col: Color, jitter := 0.0, seed_x := 0.0, seed_z := 0.0) -> void:
		var arr := p.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var pts := PackedVector3Array()
		pts.resize(v.size())
		for i in v.size():
			var q := v[i]
			if jitter > 0.0:
				var x := q.x
				var y := q.y
				var z := q.z
				q = Vector3(x + (Models.hash3(x + seed_x, y, z + seed_z) - 0.5) * jitter,
					y + (Models.hash3(y, z + seed_z, x + seed_x) - 0.5) * jitter * 0.5,
					z + (Models.hash3(z + seed_z, x + seed_x, y) - 0.5) * jitter)
			pts[i] = xf * q
		st.set_color(col)
		for i in idx.size():
			st.add_vertex(pts[idx[i]])
		n += idx.size()

	## A triangle with UVs (sails: the billow reads them).
	func tri_uv(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color) -> void:
		st.set_color(col)
		st.set_uv(ua)
		st.add_vertex(a)
		st.set_uv(uc)
		st.add_vertex(c)
		st.set_uv(ub)
		st.add_vertex(b)
		n += 3

	func commit() -> ArrayMesh:
		st.generate_normals()
		return st.commit()


static func cyl(rt: float, rb: float, h: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 0
	return c


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func ball(r: float, segs := 6, rings := 3) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = segs
	s.rings = rings
	return s


static func at(x: float, y: float, z: float, rot := Vector3.ZERO, sc := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(sc), Vector3(x, y, z))


static func instance(m: Mesh, material: Material = null, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material if material else mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- sea

static func sea_shader() -> Shader:
	if _sea_shader == null:
		_sea_shader = Shader.new()
		_sea_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float t = 0.0;
uniform vec3 deep : source_color = vec3(0.29, 0.43, 0.47);
uniform vec3 crest : source_color = vec3(0.42, 0.57, 0.6);
uniform vec3 foamc : source_color = vec3(0.86, 0.91, 0.9);
varying float hgt;
varying vec3 wpos;
float wave(float x, float z) {
	return sin(x * 0.13 + t * 0.9) * 0.3 + cos(z * 0.11 + t * 0.7) * 0.3 + sin((x + z) * 0.07 + t * 1.3) * 0.16;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = wave(w.x, w.z);
	hgt = VERTEX.y;
	wpos = w;
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	vec3 col = mix(deep, crest, clamp((hgt + 0.2) * 0.9, 0.0, 1.0) * 0.55);
	// wide slow patches of darker water
	float patch = sin(wpos.x * 0.031 + t * 0.05) * cos(wpos.z * 0.027 - t * 0.04);
	col = mix(col, deep * 0.82, clamp(patch, 0.0, 1.0) * 0.3);
	// streaks of foam on the highest crests
	float streak = sin(wpos.x * 0.9 + wpos.z * 0.35 + t * 1.5) * sin(wpos.z * 0.7 - wpos.x * 0.2 - t * 1.1);
	float foam = smoothstep(0.4, 0.65, hgt) * smoothstep(0.45, 0.85, streak);
	col = mix(col, foamc, foam * 0.45);
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.45;
}
"""
	return _sea_shader


## A faceted sea grid that follows the camera, its waves made on the GPU.
static func sea(size := 360.0, segs := 54) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	p.subdivide_width = segs - 1
	p.subdivide_depth = segs - 1
	var m := ShaderMaterial.new()
	m.shader = sea_shader()
	var mi := MeshInstance3D.new()
	mi.mesh = p
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- islands

static func _tree(b: Builder, x: float, z: float, y: float, s: float, rng: RandomNumberGenerator) -> void:
	b.prim(cyl(0.12 * s, 0.18 * s, 0.9 * s, 5), at(x, y + 0.45 * s, z), Color8(0x6b, 0x50, 0x38))
	var greens := [Color8(0x4d, 0x6a, 0x4b), Color8(0x5a, 0x7a, 0x52), Color8(0x43, 0x5f, 0x47)]
	var gc: Color = greens[rng.randi() % 3]
	var ry := rng.randf() * 3
	b.prim(cyl(0.0, 0.95 * s, 1.7 * s, 6), at(x, y + 1.6 * s, z, Vector3(0, ry, 0)), gc)
	b.prim(cyl(0.0, 0.7 * s, 1.4 * s, 6), at(x, y + 2.4 * s, z, Vector3(0, ry + 0.5, 0)), gc.lightened(0.06))


## A palm: a leaning trunk in rings and drooping fronds.
static func _palm(b: Builder, x: float, z: float, y: float, s: float, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.18
	var p := Vector3(x, y, z)
	for i in 6:
		var q := p + (Vector3.UP + lean * (1.0 + i * 0.3)) * 0.5 * s
		beam(b, p, q, (0.2 - i * 0.015) * s, Color8(0x8a, 0x6a, 0x48) if i % 2 else Color8(0x7a, 0x5c, 0x3e))
		p = q
	var green := Color8(0x5f, 0x8a, 0x4a)
	for k in 7:
		var a := k * TAU / 7 + rng.randf() * 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var mid := p + d * 0.8 * s + Vector3(0, 0.15 * s, 0)
		var end := p + d * 1.6 * s + Vector3(0, -0.45 * s, 0)
		b.prim(box(0.5 * s, 0.05, 0.95 * s), Transform3D(Basis.looking_at(mid - p, Vector3.UP), (p + mid) / 2), green if k % 2 else green.darkened(0.12))
		b.prim(box(0.36 * s, 0.05, 0.95 * s), Transform3D(Basis.looking_at(end - mid, Vector3.UP), (mid + end) / 2), green.darkened(0.06))
	for k in 3:
		b.prim(ball(0.12 * s, 5, 3), at(p.x + cos(k * 2.1) * 0.15 * s, p.y - 0.1 * s, p.z + sin(k * 2.1) * 0.15 * s), Color8(0x6a, 0x4e, 0x30))


## A fisher's hut on stilts, with a thatched roof.
static func _hut(b: Builder, x: float, z: float, y: float, a: float) -> void:
	for c in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
		b.prim(cyl(0.1, 0.1, 1.2, 5), at(x + c[0] * 1.0, y + 0.3, z + c[1] * 0.8), Color8(0x6b, 0x50, 0x38))
	b.prim(box(2.4, 0.15, 2.0), at(x, y + 0.9, z, Vector3(0, a, 0)), Color8(0x8c, 0x6a, 0x48))
	b.prim(box(1.9, 1.1, 1.5), at(x, y + 1.5, z, Vector3(0, a, 0)), Color8(0xb5, 0x9b, 0x78))
	b.prim(box(0.4, 0.7, 0.05), at(x + sin(a) * 0.76, y + 1.35, z + cos(a) * 0.76, Vector3(0, a, 0)), Color8(0x4a, 0x36, 0x28))
	b.prim(cyl(0.0, 1.7, 1.2, 4), at(x, y + 2.6, z, Vector3(0, a + PI / 4, 0)), Color8(0xc8, 0xa8, 0x5c))


## Old ruins: a broken ring of columns.
static func _ruins(b: Builder, x: float, z: float, y: float, rng: RandomNumberGenerator) -> void:
	var stone := Color8(0xb8, 0xb4, 0xa6)
	b.prim(cyl(2.0, 2.2, 0.3, 8), at(x, y + 0.1, z), stone.darkened(0.1))
	for k in 6:
		var a := k * TAU / 6
		var h := 0.8 + rng.randf() * 1.8 if k % 3 else 0.4
		b.prim(cyl(0.22, 0.25, h, 6), at(x + cos(a) * 1.6, y + 0.25 + h / 2, z + sin(a) * 1.6), stone)
	b.prim(box(2.4, 0.3, 0.5), at(x + 0.3, y + 2.4, z - 0.8, Vector3(0, 0.5, 0.1)), stone.lightened(0.05))
	b.prim(cyl(0.25, 0.25, 1.6, 6), at(x - 1.0, y + 0.4, z + 2.1, Vector3(0, 0.6, PI / 2)), stone.darkened(0.05))


## A wreck run aground on the beach: half a hull, a broken mast.
static func _wreck(b: Builder, x: float, z: float, y: float, a: float) -> void:
	var ship_b := Builder.new()
	var L := Looks.of("classique").duplicate()
	L.hull = Color8(0x6a, 0x52, 0x40)
	L.band = Color8(0x5a, 0x48, 0x3a)
	hull_into(ship_b, L)
	var m := ship_b.commit()
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var xf := Transform3D(Basis.from_euler(Vector3(0.25, a, 0.5)).scaled(Vector3.ONE * 0.8), Vector3(x, y - 0.3, z))
	for i in range(0, v.size(), 3):
		if v[i].z > 0.6 or v[i + 1].z > 0.6 or v[i + 2].z > 0.6:
			continue
		b.st.set_color(cols[i])
		b.st.add_vertex(xf * v[i])
		b.st.add_vertex(xf * v[i + 1])
		b.st.add_vertex(xf * v[i + 2])
		b.n += 3
	b.prim(cyl(0.08, 0.12, 2.6, 5), Transform3D(Basis.from_euler(Vector3(0.9, a, 0.3)), xf * Vector3(0, 1.6, -0.6)), Color8(0x5e, 0x45, 0x32))


## An island at (x, z) of radius r, with its seed: rocks, sand, grass, maybe a hill, trees,
## palms, and now and then a hut, ruins or a wreck.
static func island(x: float, z: float, r: float, port := false) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x) * 131 + absf(z) * 17 + r * 7)
	var b := Builder.new()
	var segs := 7 + rng.randi() % 3
	b.prim(cyl(r * 1.0, r * 1.12, 1.4, segs), at(0, -0.6, 0, Vector3(0, 0.3, 0)), Color8(0x8b, 0x86, 0x7a), 0.9, x + 7, z)
	b.prim(cyl(r * 0.92, r * 1.06, 2.8, segs), at(0, 0.1, 0), Color8(0xd5, 0xc7, 0xa2), 0.9, x, z)
	b.prim(cyl(r * 0.6, r * 0.8, 1.6, segs), at(0, 1.9, 0), Color8(0x7c, 0x96, 0x68), 0.8, x + 3, z)
	b.prim(cyl(r * 0.45, r * 0.62, 0.5, segs), at(0, 2.8, 0, Vector3(0, 0.4, 0)), Color8(0x6c, 0x88, 0x5c), 0.7, x, z + 3)
	if r > 9 and not port:
		b.prim(cyl(0.0, r * 0.42, r * 0.45, segs), at(0, 2.7 + r * 0.22, 0), Color8(0x8a, 0x9a, 0x86), 0.6, x, z + 5)
		b.prim(cyl(0.0, r * 0.2, r * 0.18, segs), at(0, 2.7 + r * 0.4, 0, Vector3(0, 0.6, 0)), Color8(0xa4, 0xae, 0xa0), 0.4, x + 1, z + 5)
	var nt := int(r * 0.45) - (3 if port else 0)
	for i in nt:
		var a := rng.randf() * TAU
		var d := r * (0.2 + rng.randf() * 0.4)
		_tree(b, cos(a) * d, sin(a) * d, 2.6, 0.8 + rng.randf() * 0.5, rng)
	# palms on the beach
	for i in 2 + rng.randi() % 3:
		var a := rng.randf() * TAU
		if port and absf(wrapf(a - PI / 2, -PI, PI)) < 0.8:
			continue
		var d := r * (0.74 + rng.randf() * 0.12)
		_palm(b, cos(a) * d, sin(a) * d, 1.45, 0.9 + rng.randf() * 0.4, rng)
	# bushes
	for i in 4:
		var a := rng.randf() * TAU
		var d := r * (0.55 + rng.randf() * 0.2)
		b.prim(ball(0.5 + rng.randf() * 0.4, 6, 3), at(cos(a) * d, 2.65, sin(a) * d, Vector3.ZERO, Vector3(1, 0.7, 1)), Color8(0x58, 0x7a, 0x4c))
	for i in 5:
		var a := rng.randf() * TAU
		var rr := 0.5 + rng.randf() * 1.1
		b.prim(ball(rr, 5, 2), at(cos(a) * r * 1.04, 0.3, sin(a) * r * 1.04, Vector3(rng.randf() * 3, rng.randf() * 3, 0)), Color8(0x8b, 0x8f, 0x8c).darkened(rng.randf() * 0.15))
	if port:
		_port(b)
	elif r > 6.5:
		var a := rng.randf() * TAU
		match rng.randi() % 4:
			0:
				_hut(b, cos(a) * r * 0.45, sin(a) * r * 0.45, 2.6, a)
			1:
				_ruins(b, cos(a) * r * 0.3, sin(a) * r * 0.3, 2.6, rng)
			2:
				_wreck(b, cos(a) * r * 0.86, sin(a) * r * 0.86, 1.4, a + PI / 2)
	var g := Node3D.new()
	g.position = Vector3(x, 0, z)
	g.add_child(instance(b.commit()))
	# the shallows: a pale halo of turquoise water around the island
	var sh := Builder.new()
	var n := 18
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		sh.tri(p0 * r * 1.0, p0 * r * 1.75, p1 * r * 1.75, Color.WHITE)
		sh.tri(p0 * r * 1.0, p1 * r * 1.75, p1 * r * 1.0, Color.WHITE)
	var shm := instance(sh.commit(), flat_mat(Color8(0x7f, 0xc4, 0xbc), 0.22), false)
	shm.position.y = 0.05
	g.add_child(shm)
	# a ring of foam
	var foam := Builder.new()
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		foam.tri(p0 * r * 1.02, p0 * r * 1.3, p1 * r * 1.3, Color.WHITE)
		foam.tri(p0 * r * 1.02, p1 * r * 1.3, p1 * r * 1.02, Color.WHITE)
	var fm := instance(foam.commit(), flat_mat(Color8(0xf3, 0xf6, 0xf4), 0.2), false)
	fm.position.y = 0.35
	g.add_child(fm)
	if port:
		# the lighthouse's lamp
		var lb := Builder.new()
		lb.prim(ball(0.75, 6, 3), at(-9.5, 12.6, -5.5), Color8(0xff, 0xe0, 0x9a))
		lb.prim(box(1.2, 0.8, 0.5), at(-2, 4.2, 3.72), Color8(0xff, 0xd2, 0x7a))
		g.add_child(instance(lb.commit(), glow_mat(), false))
	return g


## The player's port: houses, a tavern, a lighthouse, the jetty with its cargo, a flag.
static func _port(b: Builder) -> void:
	var r := Rules.BASE_R
	# the tavern (where the crew is hired)
	b.prim(box(4.4, 2.6, 3.4), at(-2, 4, 2), Color8(0xb5, 0x9b, 0x78))
	b.prim(box(4.6, 0.3, 3.6), at(-2, 2.75, 2), Color8(0x8a, 0x76, 0x60))
	b.prim(cyl(0.0, 3.6, 2.2, 4), at(-2, 6.4, 2, Vector3(0, PI / 4, 0)), Color8(0x7a, 0x45, 0x36))
	b.prim(box(0.9, 1.5, 0.1), at(-2.9, 3.4, 3.72), Color8(0x4a, 0x36, 0x28))
	b.prim(box(0.6, 1.4, 0.6), at(-0.6, 7.2, 1.6), Color8(0x8a, 0x86, 0x7e))
	# houses of the village
	var roofs := [Color8(0x5e, 0x6e, 0x7a), Color8(0x8a, 0x4a, 0x36), Color8(0x6e, 0x5a, 0x44)]
	var walls := [Color8(0xd8, 0xcc, 0xb4), Color8(0xc4, 0xb0, 0x90), Color8(0xe0, 0xd6, 0xc2)]
	var houses := [[5.5, -3.5, 0.3], [-6.5, -2.0, -0.4], [2.0, -7.0, 0.1], [-3.0, -7.5, 0.8], [6.5, 3.0, -0.2]]
	for i in houses.size():
		var hx: float = houses[i][0]
		var hz: float = houses[i][1]
		var ha: float = houses[i][2]
		b.prim(box(2.6, 1.8, 2.2), at(hx, 3.5, hz, Vector3(0, ha, 0)), walls[i % 3])
		b.prim(cyl(0.0, 2.2, 1.4, 4), at(hx, 5.1, hz, Vector3(0, ha + PI / 4, 0)), roofs[i % 3])
		b.prim(box(0.5, 0.5, 0.1), at(hx + sin(ha) * 1.12, 3.6, hz + cos(ha) * 1.12, Vector3(0, ha, 0)), Color8(0x4a, 0x5a, 0x66))
	# the lighthouse
	b.prim(cyl(1.1, 1.6, 8.5, 8), at(-9.5, 6.8, -5.5), Color8(0xee, 0xea, 0xe0))
	for k in 3:
		b.prim(cyl(1.3 - k * 0.15, 1.45 - k * 0.15, 0.7, 8), at(-9.5, 4.3 + k * 2.6, -5.5), Color8(0xb4, 0x53, 0x2f))
	b.prim(cyl(1.4, 1.4, 0.3, 8), at(-9.5, 11.2, -5.5), Color8(0x3a, 0x3c, 0x3e))
	b.prim(cyl(0.0, 1.2, 1.2, 8), at(-9.5, 13.8, -5.5), Color8(0x3a, 0x3c, 0x3e))
	# the jetty, its posts and cargo
	for i in 6:
		b.prim(box(3, 0.25, 1.5), at(0, 1.1, r - 1 + i * 1.6), Color8(0x8c, 0x6a, 0x48).darkened(0.06 * (i % 2)))
	for pk in [[-1.4, 0], [1.4, 0], [-1.4, 1], [1.4, 1]]:
		b.prim(cyl(0.18, 0.18, 2.6, 5), at(pk[0], 0.2, r + 2 + pk[1] * 5), WOOD)
	for i in 3:
		b.prim(cyl(0.3, 0.3, 0.7, 7), at(-0.9, 1.6, r + 0.5 + i * 0.7), Color8(0x8a, 0x5e, 0x36))
	b.prim(box(0.8, 0.7, 0.8), at(0.9, 1.6, r + 1.2, Vector3(0, 0.3, 0)), Color8(0x9a, 0x74, 0x48))
	b.prim(box(0.6, 0.5, 0.6), at(0.9, 2.2, r + 1.2, Vector3(0, -0.2, 0)), Color8(0xa8, 0x82, 0x52))
	# a crane to load the ships
	b.prim(box(0.3, 4.0, 0.3), at(1.3, 3.0, r - 1.2), WOOD)
	beam(b, Vector3(1.3, 4.9, r - 1.2), Vector3(1.3, 5.2, r + 1.5), 0.2, WOOD)
	beam(b, Vector3(1.3, 5.1, r + 1.4), Vector3(1.3, 3.0, r + 1.4), 0.04, Color8(0x4a, 0x3c, 0x2e))
	b.prim(box(0.5, 0.4, 0.5), at(1.3, 2.8, r + 1.4), Color8(0x9a, 0x74, 0x48))
	# the flag
	b.prim(cyl(0.1, 0.12, 6, 5), at(3.5, 5.5, 3), WOOD)
	b.prim(box(1.8, 1.1, 0.06), at(4.4, 8, 3), RUST)


## Towers and the coffre, which grow with the port's upgrades.
static func port_deco(defense: int, coffre: int) -> MeshInstance3D:
	var b := Builder.new()
	var spots := [[-8, -6], [8, -6], [0, -10]]
	for i in mini(defense, 3):
		var tx: float = spots[i][0]
		var tz: float = spots[i][1]
		b.prim(cyl(1.2, 1.5, 4.5, 6), at(tx, 4.6, tz), Color8(0x9a, 0x9c, 0x94))
		b.prim(cyl(1.5, 1.5, 0.6, 6), at(tx, 7.1, tz), Color8(0x7d, 0x7f, 0x78))
		b.prim(cyl(0.25, 0.25, 1.6, 6), at(tx, 7.6, tz + 0.6, Vector3(PI / 2, 0, 0)), IRON)
	var s := 0.8 + coffre * 0.18
	b.prim(box(1.6 * s, 1 * s, 1 * s), at(3, 3.2, -2), Color8(0x8a, 0x5a, 0x2b))
	b.prim(box(1.7 * s, 0.3 * s, 1.1 * s), at(3, 3.2 + 0.6 * s, -2), Color8(0xb0, 0x8a, 0x3a))
	return instance(b.commit())


# ---------------------------------------------------------------- ships

## Height of the raised quarterdeck (aft) above the main deck.
const QD_H := 0.32

## The hull: U-shaped frames along the boat, a pointed stem, a transom and sheer. Planked in
## strakes of two shades, with a painted band under the black wale and a dark bottom.
static func hull_into(b: Builder, L: Dictionary) -> void:
	var ZS := [-2.9, -2.6, -2.2, -1.8, -1.35, -0.9, -0.45, 0.0, 0.45, 0.9, 1.3, 1.7, 2.05, 2.4, 2.7, 2.95, 3.18, 3.35]
	var PROF := [[0.0, 0.0], [0.5, 0.1], [0.84, 0.36], [0.97, 0.56], [1.0, 0.72], [0.98, 0.86], [0.95, 1.0]]
	var H := PROF.size()
	var sections := []
	for z in ZS:
		var w := _half_w(z)
		var bo := _bottom(z)
		var hh := _top(z) - bo
		var half := []
		for f in PROF:
			half.append(Vector3(f[0] * w, bo + f[1] * hh, z))
		var sec := []
		for j in range(half.size() - 1, 0, -1):
			sec.append(Vector3(-half[j].x, half[j].y, half[j].z))
		sec.append_array(half)
		sections.append(sec)
	var hull: Color = L.hull
	var hull2 := hull.darkened(0.12)
	for i in sections.size() - 1:
		var A: Array = sections[i]
		var B: Array = sections[i + 1]
		for j in A.size() - 1:
			var k := mini(absi(j - (H - 1)), absi(j + 1 - (H - 1)))
			var cy: float = (A[j].y + A[j + 1].y + B[j].y + B[j + 1].y) / 4.0
			var cc: Color = L.wale if k == H - 2 else (L.band if k == H - 3 else (hull if k % 2 else hull2))
			if cy < 0.0 and k < H - 3:
				cc = L.bottom
			b.tri(A[j], B[j], B[j + 1], cc)
			b.tri(A[j], B[j + 1], A[j + 1], cc)
		# the deck, a little below the gunwale, in planks
		var n := A.size() - 1
		var kk := 0.92
		var dy := -0.12
		var al := Vector3(A[0].x * kk, A[0].y + dy, A[0].z)
		var ar := Vector3(A[n].x * kk, A[n].y + dy, A[n].z)
		var bl := Vector3(B[0].x * kk, B[0].y + dy, B[0].z)
		var br := Vector3(B[n].x * kk, B[n].y + dy, B[n].z)
		var deck: Color = L.deck
		for p in 4:
			var u0 := p / 4.0
			var u1 := (p + 1) / 4.0
			var dc := deck if (p + i) % 2 else deck.darkened(0.07)
			b.tri(al.lerp(ar, u0), bl.lerp(br, u0), bl.lerp(br, u1), dc)
			b.tri(al.lerp(ar, u0), bl.lerp(br, u1), al.lerp(ar, u1), dc)
	# transom
	var S0: Array = sections[0]
	var top0 := _top(ZS[0])
	var cen := Vector3(0, (_bottom(ZS[0]) + top0) / 2.0, ZS[0])
	for j in S0.size() - 1:
		var y: float = (S0[j].y + S0[j + 1].y) / 2.0
		b.tri(cen, S0[j + 1], S0[j], L.bottom if y < 0.0 else (L.wale if y > top0 - 0.18 else hull2))
	b.tri(S0[0], S0[S0.size() - 1], cen, L.wale)


## The bulwark: a low wall along the gunwale with a capping rail, open at the gunports.
static func _bulwark(b: Builder, L: Dictionary, qd: bool) -> void:
	var zs := []
	var z := -2.9
	while z < 3.3:
		zs.append(z)
		z += 0.3
	zs.append(3.35)
	for side in [-1, 1]:
		for i in zs.size() - 1:
			var z0: float = zs[i]
			var z1: float = zs[i + 1]
			var h0 := 0.26 + (QD_H if qd and z0 < -1.5 else 0.0)
			var h1 := 0.26 + (QD_H if qd and z1 < -1.5 else 0.0)
			var a0 := Vector3(side * _half_w(z0) * 0.97, _top(z0) - 0.02, z0)
			var a1 := Vector3(side * _half_w(z1) * 0.97, _top(z1) - 0.02, z1)
			var c0 := a0 + Vector3(-side * 0.04, h0, 0)
			var c1 := a1 + Vector3(-side * 0.04, h1, 0)
			b.tri(a0, a1, c1, L.wale)
			b.tri(a0, c1, c0, L.wale)
			# the capping rail
			beam(b, c0 + Vector3(0, 0.02, 0), c1 + Vector3(0, 0.02, 0), 0.07, L.wood.lightened(0.15))
	# the transom's upper part
	var t0 := _top(-2.9) - 0.02
	var hw := _half_w(-2.9) * 0.97
	var th := 0.26 + (QD_H if qd else 0.0)
	b.tri(Vector3(-hw, t0, -2.9), Vector3(-hw + 0.04, t0 + th, -2.9), Vector3(hw - 0.04, t0 + th, -2.9), L.wale)
	b.tri(Vector3(-hw, t0, -2.9), Vector3(hw - 0.04, t0 + th, -2.9), Vector3(hw, t0, -2.9), L.wale)
	beam(b, Vector3(-hw, t0 + th + 0.02, -2.9), Vector3(hw, t0 + th + 0.02, -2.9), 0.07, L.wood.lightened(0.15))


## The deck's height at z (where the men stand), on the main deck.
static func deck_y(z: float) -> float:
	return _top(z) - 0.12


static func _half_w(z: float) -> float:
	if z < -0.4:
		return 1.2 * (0.7 + 0.3 * sin(minf(1.0, (z + 2.9) / 2.5) * PI / 2))
	return 1.2 * pow(maxf(0.0, cos((z + 0.4) / 3.75 * PI / 2)), 0.75)


static func _bottom(z: float) -> float:
	return -0.45 + 0.75 * pow(maxf(0.0, (z - 1.1) / 2.25), 2) + 0.3 * pow(maxf(0.0, (-1.6 - z) / 1.3), 2)


static func _top(z: float) -> float:
	return 0.95 + 0.4 * pow(maxf(0.0, (z - 1.4) / 1.95), 2) + 0.28 * pow(maxf(0.0, (-1.4 - z) / 1.5), 2)


## A thin square beam from p0 to p1 (ropes, rails, spars).
static func beam(b: Builder, p0: Vector3, p1: Vector3, th: float, col: Color) -> void:
	var d := p1 - p0
	var l := d.length()
	if l < 0.001:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var bs := Basis.looking_at(d, up)
	b.prim(box(th, th, l), Transform3D(bs, (p0 + p1) / 2), col)


## The glowing bits (lanterns, windows, lava, magic): vertex colours, unlit.
static func glow_mat() -> StandardMaterial3D:
	if not _cache.has("glow"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		_cache["glow"] = m
	return _cache["glow"]


static func sail_shader() -> Shader:
	if _sail_shader == null:
		_sail_shader = Shader.new()
		_sail_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float depth = 0.35;
uniform float t = 0.0;
uniform vec3 bdir = vec3(0.0, 0.0, 1.0);
void vertex() {
	float u = UV.x * 2.0 - 1.0;
	float v = UV.y;
	float belly = (1.0 - u * u) * (0.55 + 0.45 * sin(3.14159 * min(1.0, v * 1.15)));
	float flutter = sin(t * 7.0 + u * 3.0 + v * 2.0) * 0.03 * (1.0 - v);
	VERTEX += bdir * (depth * belly + flutter);
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 1.0;
}
"""
	return _sail_shader


static var _flag_shader: Shader

static func flag_shader() -> Shader:
	if _flag_shader == null:
		_flag_shader = Shader.new()
		_flag_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float t = 0.0;
void vertex() {
	float u = UV.x;
	VERTEX.x += sin(t * 8.0 - u * 5.0) * 0.13 * u;
	VERTEX.y += sin(t * 5.0 - u * 4.0) * 0.04 * u;
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 1.0;
}
"""
	return _flag_shader


## A square sail: cloths of two shades, a coloured foot; UV gives the billow its shape.
static func sail_mesh(w: float, h: float, col: Color, col2: Color, trim: Color, foot := true) -> ArrayMesh:
	var key := "sail%.2f%.2f%s%s%s%s" % [w, h, col.to_html(), col2.to_html(), trim.to_html(), foot]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var NI := 6
	var NJ := 4
	for i in NI:
		for j in NJ:
			var u0 := float(i) / NI
			var u1 := float(i + 1) / NI
			var v0 := float(j) / NJ
			var v1 := float(j + 1) / NJ
			var c := trim if foot and j == 0 else (col if i % 2 else col2)
			var p00 := Vector3(-w / 2 + w * u0, -h / 2 + h * v0, 0)
			var p10 := Vector3(-w / 2 + w * u1, -h / 2 + h * v0, 0)
			var p11 := Vector3(-w / 2 + w * u1, -h / 2 + h * v1, 0)
			var p01 := Vector3(-w / 2 + w * u0, -h / 2 + h * v1, 0)
			b.tri_uv(p00, p10, p11, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), c)
			b.tri_uv(p00, p11, p01, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), c)
	_cache[key] = b.commit()
	return _cache[key]


## A triangular sail (jib): tack A, head B, clew C (all at x = 0, in the ship's frame).
static func jib_mesh(A: Vector3, B: Vector3, C: Vector3, col: Color, col2: Color) -> ArrayMesh:
	var b := Builder.new()
	var N := 4
	var pt := func(u: float, v: float) -> Vector3: return A + (B - A) * v + (C - A) * u * (1.0 - v)
	for i in N:
		for j in N:
			var u0 := float(i) / N
			var u1 := float(i + 1) / N
			var v0 := float(j) / N
			var v1 := float(j + 1) / N
			var c := col if (i + j) % 2 else col2
			b.tri_uv(pt.call(u0, v0), pt.call(u1, v0), pt.call(u1, v1), Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), c)
			b.tri_uv(pt.call(u0, v0), pt.call(u1, v1), pt.call(u0, v1), Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1), c)
	return b.commit()


## A flag streaming aft from (0, 0, 0): its colour with the emblem in the middle.
static func flag_mesh(col: Color, emblem: Color) -> ArrayMesh:
	var key := "flag%s%s" % [col.to_html(), emblem.to_html()]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var W := 1.0
	var Hh := 0.62
	for i in 5:
		for j in 3:
			var u0 := i / 5.0
			var u1 := (i + 1) / 5.0
			var y0 := -Hh / 2 + Hh * j / 3.0
			var y1 := -Hh / 2 + Hh * (j + 1) / 3.0
			var c := emblem if j == 1 and (i == 1 or i == 2) else col
			b.tri_uv(Vector3(0, y0, -W * u0), Vector3(0, y0, -W * u1), Vector3(0, y1, -W * u1), Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), c)
			b.tri_uv(Vector3(0, y0, -W * u0), Vector3(0, y1, -W * u1), Vector3(0, y1, -W * u0), Vector2(u0, 0), Vector2(u1, 1), Vector2(u0, 1), c)
	_cache[key] = b.commit()
	return _cache[key]


## The look of a ship: its hull, upgrades, crew (kinds, in Rules.CREW order), style and grapple.
static func ship_cfg(hk: String, up: Dictionary, crew: Array, colors: Dictionary, skin := "classique", hook := false) -> Dictionary:
	var H: Dictionary = Rules.HULLS[hk]
	var st := Rules.ship_stats(hk, up, 0)
	var look: Dictionary = Looks.of(skin).duplicate()
	look.merge(colors, true)
	return {"hull_k": hk, "masts": H.masts, "sail_lv": int(up.get("voiles", 0)), "side": st.side, "bow": st.bow,
		"stern": st.stern, "grappin": hook, "crew": crew, "scale": H.scale, "skin": skin, "look": look}


static func crew_kinds(counts: Dictionary) -> Array:
	var out := []
	for c in Rules.CREW:
		for i in int(counts.get(c.k, 0)):
			out.append(c.k)
	return out


static func player_cfg(s: Dictionary) -> Dictionary:
	return ship_cfg(s.ship, s.up, crew_kinds(s.crew), {}, str(s.get("skin", "classique")), bool(s.get("hook", false)))


## The sails the "voiles" upgrade adds, in order, for a ship of n masts.
static func extra_sails(n: int, lv: int) -> Array:
	var order: Array = [["jib", "top0", "jib2"], ["jib", "top0", "top1"], ["jib", "top1", "top0", "top2"]][clampi(n, 1, 3) - 1]
	return order.slice(0, mini(lv, order.size()))


## Where each gun of a battery sits on the hull (before the hull's scale), so balls can leave
## from the guns themselves. bab = +x (port, bearing +PI/2), tri = -x, av = bow (+z), ar = stern.
static func gun_spots(c: Dictionary, k: String) -> Array:
	var out := []
	var hk: String = str(c.get("hull_k", c.get("hull", "chaloupe")))
	var qd: bool = hk != "chaloupe"
	match k:
		"bab", "tri":
			var ng: int = clampi(int(c.side), 1, 8)
			var side := 1.0 if k == "bab" else -1.0
			for i in ng:
				var gz: float = 0.4 if ng == 1 else 1.6 - i * (3.0 / (ng - 1))
				out.append(Vector3(side * (_half_w(gz) + 0.05), _top(gz) + 0.1, gz))
		"av":
			for i in int(c.bow):
				out.append(Vector3((i - (c.bow - 1) / 2.0) * 0.4, 1.45, 2.85))
		"ar":
			for i in int(c.stern):
				out.append(Vector3((i - (c.stern - 1) / 2.0) * 0.4, 1.3 + (QD_H if qd else 0.0), -2.95))
	return out


## A ship: root (turned by heading) > body (scaled, rolls) > one mesh for the wood and guns,
## one for its glowing bits, the sails and flag (each with its own shader) and the crew.
static func ship(c: Dictionary) -> Node3D:
	var L: Dictionary = c.look
	var g := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var b := Builder.new()
	var gl := Builder.new()
	var n: int = clampi(c.masts, 1, 3)
	var qd: bool = n >= 2 or c.hull_k == "sloop"
	hull_into(b, L)
	_bulwark(b, L, qd)
	var iron: Color = L.iron
	var wood: Color = L.wood
	var rope: Color = L.rope
	# bowsprit and figurehead
	var tip := Vector3(0, 1.93, 4.8)
	b.prim(cyl(0.05, 0.09, 2.2, 6), at(0, 1.6, 3.75, Vector3(PI / 2 - 0.3, 0, 0)), wood)
	b.prim(ball(0.13, 6, 3), at(0, 1.22, 3.48), L.trim)
	b.prim(box(0.1, 0.22, 0.18), at(0, 1.05, 3.42, Vector3(0.4, 0, 0)), L.trim.darkened(0.2))
	var zs: Array = [0.2] if n == 1 else ([1.0, -0.9] if n == 2 else [1.5, 0.0, -1.5])
	var main_i := 0 if n < 3 else 1
	var extras := extra_sails(n, int(c.sail_lv))
	var sails := []
	var flags := []
	var mast_tops := []
	for i in zs.size():
		var z: float = zs[i]
		var tall := i == main_i
		var top_y := 6.0 if tall else 5.4
		var base_y := deck_y(z)
		b.prim(cyl(0.07, 0.13, top_y - base_y, 6), at(0, (top_y + base_y) / 2, z), wood)
		b.prim(cyl(0.16, 0.16, 0.12, 8), at(0, base_y + 0.06, z), rope)
		mast_tops.append(Vector3(0, top_y, z))
		var w := (2.5 if n < 3 else 2.2) * (0.86 if n == 3 and i == 2 else 1.0)
		var sh := 1.75
		var cy := 2.05 + sh / 2
		sails.append(_sail(body, w, sh, Vector3(0, cy, z + 0.14), L, true))
		beam(b, Vector3(-w / 2 - 0.2, cy + sh / 2 + 0.02, z + 0.14), Vector3(w / 2 + 0.2, cy + sh / 2 + 0.02, z + 0.14), 0.09, wood)
		beam(b, Vector3(-w / 2 - 0.15, cy - sh / 2 - 0.02, z + 0.14), Vector3(w / 2 + 0.15, cy - sh / 2 - 0.02, z + 0.14), 0.07, wood)
		var nest_y := cy + sh / 2 + 0.12
		if tall:
			b.prim(cyl(0.34, 0.24, 0.16, 8), at(0, nest_y, z), wood.lightened(0.1))
		if extras.has("top%d" % i):
			var tw := w * 0.78
			var th := 1.25
			var ty := cy + sh / 2 + 0.25 + th / 2
			sails.append(_sail(body, tw, th, Vector3(0, ty, z + 0.12), L, false))
			beam(b, Vector3(-tw / 2 - 0.15, ty + th / 2 + 0.02, z + 0.12), Vector3(tw / 2 + 0.15, ty + th / 2 + 0.02, z + 0.12), 0.07, wood)
		# shrouds down to the rails
		for side in [-1, 1]:
			for k in 3:
				var zk: float = z - 0.15 - k * 0.28
				beam(b, Vector3(side * _half_w(zk) * 0.97, _top(zk) + 0.26, zk), Vector3(side * 0.1, nest_y, z), 0.028, rope)
		# lanterns of light on the yard ends for glowing styles
		if L.get("ball_glow", false):
			for side in [-1, 1]:
				gl.prim(ball(0.08, 5, 3), at(side * (w / 2 + 0.2), cy + sh / 2 + 0.02, z + 0.14), L.glow)
	# stays: fore to the bowsprit, main to the stern
	beam(b, mast_tops[0] + Vector3(0, -0.3, 0), tip, 0.03, rope)
	beam(b, mast_tops[main_i] + Vector3(0, -0.2, 0), Vector3(0, _top(-2.9) + 0.3 + (QD_H if qd else 0.0), -2.85), 0.03, rope)
	if n > 1:
		for i in n - 1:
			beam(b, mast_tops[i + 1] + Vector3(0, -0.4, 0), Vector3(0, 4.0, zs[i]), 0.025, rope)
	var z0: float = zs[0]
	if extras.has("jib"):
		sails.append(_jib(body, Vector3(0, 1.86, 4.55), Vector3(0, 4.7, z0 + 0.3), Vector3(0, 2.0, z0 + 0.75), L))
	if extras.has("jib2"):
		sails.append(_jib(body, Vector3(0.03, 1.7, 3.7), Vector3(0.03, 3.9, z0 + 0.35), Vector3(0.03, 1.85, z0 + 1.0), L))
	# the flag on the tallest mast
	var fm := ShaderMaterial.new()
	fm.shader = flag_shader()
	var flag := instance(flag_mesh(L.flag, L.emblem), fm, false)
	flag.position = mast_tops[main_i] + Vector3(0, 0.25, -0.05)
	body.add_child(flag)
	flags.append(fm)
	b.prim(cyl(0.02, 0.02, 0.6, 4), at(0, mast_tops[main_i].y + 0.2, mast_tops[main_i].z), wood)
	# guns in their ports
	for bk in ["bab", "tri"]:
		for gs: Vector3 in gun_spots(c, bk):
			var sd := signf(gs.x)
			var hw := _half_w(gs.z)
			b.prim(box(0.06, 0.24, 0.32), at(sd * (hw * 0.97 + 0.01), gs.y + 0.01, gs.z), Color8(0x14, 0x12, 0x10))
			b.prim(cyl(0.11, 0.14, 0.75, 6), at(gs.x, gs.y, gs.z, Vector3(0, 0, PI / 2)), iron)
			b.prim(box(0.3, 0.12, 0.36), at(sd * (hw - 0.3), deck_y(gs.z) + 0.06, gs.z), wood)
	for bk in ["av", "ar"]:
		for gs: Vector3 in gun_spots(c, bk):
			b.prim(cyl(0.11, 0.14, 0.8, 6), at(gs.x, gs.y, gs.z, Vector3(PI / 2, 0, 0)), iron)
	# the stern: quarterdeck, cabin, lit windows, lantern; the wheel
	var dq := deck_y(-2.2)
	if qd:
		var qw := _half_w(-2.2) * 1.8
		b.prim(box(qw, 0.4, 1.4), at(0, dq + QD_H - 0.2, -2.2), L.deck.darkened(0.05))
		b.prim(box(qw * 0.98, QD_H, 0.06), at(0, dq + QD_H / 2, -1.5), L.hull.darkened(0.2))
		b.prim(box(0.26, QD_H * 0.85, 0.07), at(0, dq + QD_H * 0.45, -1.49), Color8(0x24, 0x1a, 0x14))
		for x in [-0.55, 0.55]:
			gl.prim(box(0.16, 0.12, 0.07), at(x, dq + QD_H * 0.55, -1.48), L.glow)
	var wy := dq + (QD_H if qd else 0.0)
	b.prim(box(0.08, 0.5, 0.08), at(0, wy + 0.25, -1.88), wood)
	b.prim(cyl(0.25, 0.25, 0.05, 8), at(0, wy + 0.55, -1.84, Vector3(PI / 2, 0, 0)), wood.lightened(0.2))
	for a in 4:
		b.prim(box(0.04, 0.62, 0.03), at(0, wy + 0.55, -1.81, Vector3(0, 0, a * PI / 4)), wood.lightened(0.25))
	var t0 := _top(-2.9) + (QD_H if qd else 0.0)
	for x in ([-0.5, 0.0, 0.5] if qd else [-0.3, 0.3]):
		gl.prim(box(0.22, 0.17, 0.05), at(x, t0 - 0.22, -2.93), L.glow)
		b.prim(box(0.28, 0.04, 0.07), at(x, t0 - 0.11, -2.94), wood)
	b.prim(box(1.6 if qd else 1.0, 0.06, 0.18), at(0, t0 - 0.34, -2.97), wood)
	b.prim(box(0.06, 0.55, 0.06), at(0, t0 + 0.5, -2.88), wood)
	gl.prim(box(0.16, 0.22, 0.16), at(0, t0 + 0.86, -2.88), L.glow)
	b.prim(cyl(0.0, 0.13, 0.12, 4), at(0, t0 + 1.03, -2.88), iron)
	# deck furniture: hatch, barrels, crates, anchors
	b.prim(box(0.55, 0.06, 0.45), at(0, deck_y(0.65) + 0.03, 0.65), Color8(0x3a, 0x2c, 0x20))
	for bz in [[-0.85, -1.15], [0.85, -1.2], [0.75, 2.35]]:
		var bx: float = bz[0]
		var bzz: float = bz[1]
		b.prim(cyl(0.13, 0.13, 0.3, 7), at(bx * minf(1.0, _half_w(bzz) / 1.15), deck_y(bzz) + 0.15, bzz), Color8(0x8a, 0x5e, 0x36))
		b.prim(cyl(0.135, 0.135, 0.03, 7), at(bx * minf(1.0, _half_w(bzz) / 1.15), deck_y(bzz) + 0.22, bzz), iron)
	b.prim(box(0.3, 0.26, 0.3), at(0, deck_y(2.7) + 0.13, 2.7, Vector3(0, 0.3, 0)), Color8(0x9a, 0x74, 0x48))
	for side in [-1, 1]:
		var az := 2.75
		var ax: float = side * (_half_w(az) + 0.04)
		b.prim(box(0.04, 0.5, 0.06), at(ax, _top(az) - 0.25, az), iron)
		b.prim(box(0.04, 0.06, 0.34), at(ax, _top(az) - 0.48, az, Vector3(0.5, 0, 0)), iron)
	if c.grappin:
		b.prim(cyl(0.12, 0.12, 0.1, 8), at(-0.75, deck_y(1.6) + 0.05, 1.6), Color8(0x8a, 0x70, 0x4a))
		b.prim(cyl(0.03, 0.03, 0.45, 4), at(-0.75, deck_y(1.6) + 0.3, 1.6), Color8(0x3b, 0x3f, 0x42))
		b.prim(box(0.32, 0.05, 0.05), at(-0.75, deck_y(1.6) + 0.52, 1.6, Vector3(0, 0, 0.4)), Color8(0x3b, 0x3f, 0x42))
		b.prim(box(0.32, 0.05, 0.05), at(-0.75, deck_y(1.6) + 0.52, 1.6, Vector3(0, 0, -0.4)), Color8(0x3b, 0x3f, 0x42))
	_style_extras(b, gl, c.skin, L, zs, qd)
	var hull := instance(b.commit(), mat(true))
	hull.name = "Hull"
	body.add_child(hull)
	if gl.n > 0:
		body.add_child(instance(gl.commit(), glow_mat(), false))
	body.scale = c.scale
	var men := Crew.man_ship(body, c.crew, c.skin, zs, qd, c.scale)
	g.set_meta("body", body)
	g.set_meta("sails", sails)
	g.set_meta("flags", flags)
	g.set_meta("men", men)
	g.set_meta("skin", c.skin)
	return g


static func _sail(body: Node3D, w: float, h: float, pos: Vector3, L: Dictionary, foot: bool) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = sail_shader()
	var s := instance(sail_mesh(w, h, L.sail, L.sail2, L.trim, foot), sm)
	s.position = pos
	body.add_child(s)
	return sm


static func _jib(body: Node3D, A: Vector3, B: Vector3, C: Vector3, L: Dictionary) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = sail_shader()
	sm.set_shader_parameter("bdir", Vector3(0.7, 0, 0))
	body.add_child(instance(jib_mesh(A, B, C, L.sail, L.sail2), sm))
	return sm


## What makes each style more than a paint job.
static func _style_extras(b: Builder, gl: Builder, skin: String, L: Dictionary, zs: Array, qd: bool) -> void:
	match skin:
		"glace":
			# icicles under the rails, snow on the yards, ice spikes at the bow
			for side in [-1, 1]:
				var z := -2.6
				var k := 0
				while z < 2.9:
					var hgt := 0.12 + Models.hash3(z, side, 1.0) * 0.2
					b.prim(cyl(0.035, 0.0, hgt, 4), at(side * _half_w(z) * 1.0, _top(z) - 0.05 - hgt / 2, z), L.blade)
					z += 0.38
					k += 1
			for z in zs:
				b.prim(ball(0.2, 6, 3), at(0, 4.0, z + 0.14, Vector3.ZERO, Vector3(5.5, 0.5, 1.2)), Color8(0xfa, 0xfc, 0xff))
			for i in 3:
				gl.prim(cyl(0.0, 0.09, 0.5, 4), at((i - 1) * 0.18, 1.55 + i % 2 * 0.1, 3.4, Vector3(0.5, 0, (i - 1) * 0.4)), L.glow)
		"volcan":
			# glowing cracks in the black hull, braziers
			for side in [-1, 1]:
				for i in 7:
					var z := -2.4 + i * 0.78 + Models.hash3(i, side, 2.0) * 0.3
					var y := 0.2 + Models.hash3(z, i, 5.0) * 0.4
					gl.prim(box(0.03, 0.05, 0.42), at(side * (_half_w(z) * 1.01 + 0.01), y, z, Vector3(0.6 * (Models.hash3(i, z, 1.0) - 0.5), 0, 0)), L.glow)
			for z in [2.2, -1.1]:
				b.prim(cyl(0.18, 0.1, 0.18, 6), at(0.7 * signf(z), deck_y(z) + 0.09, z), L.iron)
				gl.prim(cyl(0.0, 0.14, 0.26, 5), at(0.7 * signf(z), deck_y(z) + 0.3, z), L.glow)
		"foret":
			# leaves on the yards and rails, vines up the masts
			var greens := [Color8(0x5a, 0x8a, 0x3c), Color8(0x6f, 0x9a, 0x44), Color8(0x4a, 0x7a, 0x34)]
			for z in zs:
				for side in [-1, 1]:
					b.prim(ball(0.28, 6, 3), at(side * 1.25, 3.85, z + 0.14), greens[(side + 1) / 2])
				for k in 6:
					b.prim(box(0.08, 0.3, 0.08), at(sin(k * 1.4) * 0.12, 1.4 + k * 0.45, z + cos(k * 1.4) * 0.12, Vector3(0, k * 1.4, 0.3)), greens[k % 3])
			for side in [-1, 1]:
				for i in 6:
					var z := -2.2 + i * 0.95
					b.prim(ball(0.17, 5, 3), at(side * _half_w(z) * 0.95, _top(z) + 0.28, z), greens[i % 3])
			for i in 4:
				b.prim(ball(0.08, 5, 3), at(-0.4 + i * 0.27, deck_y(2.5) + 0.32, 2.5), Color8(0xe8, 0x6a, 0x8a) if i % 2 else Color8(0xf0, 0xd8, 0x5a))
		"magie":
			# a floating crystal over the mainmast, runes along the band
			var mz: float = zs[0 if zs.size() < 3 else 1]
			gl.prim(ball(0.3, 4, 2), at(0, 6.9, mz, Vector3.ZERO, Vector3(1, 1.8, 1)), L.glow)
			for side in [-1, 1]:
				for i in 9:
					var z := -2.4 + i * 0.62
					gl.prim(box(0.03, 0.08, 0.08), at(side * (_half_w(z) * 1.0 + 0.01), _top(z) - 0.26, z, Vector3(PI / 4, 0, 0)), L.emblem if i % 2 else L.glow)
			for i in 5:
				var a := i * TAU / 5
				gl.prim(box(0.06, 0.06, 0.06), at(cos(a) * 0.5, 6.4 + sin(a * 2) * 0.1, mz + sin(a) * 0.5, Vector3(0.5, a, 0.5)), L.emblem)
		"abysses":
			# coral and barnacles on the hull, weed hanging from the yards
			var corals := [Color8(0xe8, 0x7a, 0x6a), Color8(0xf0, 0xa0, 0x5a), Color8(0xd0, 0x5a, 0x8a)]
			for side in [-1, 1]:
				for i in 8:
					var z := -2.5 + i * 0.75 + Models.hash3(i, side, 7.0) * 0.3
					var y := 0.15 + Models.hash3(z, i, 9.0) * 0.5
					b.prim(cyl(0.0, 0.07, 0.24, 4), at(side * (_half_w(z) + 0.04), y, z, Vector3(0, 0, side * 1.2)), corals[i % 3])
					b.prim(ball(0.05, 4, 2), at(side * (_half_w(z) + 0.01), y + 0.2, z + 0.15), Color8(0xd8, 0xd4, 0xc4))
			for z in zs:
				for k in 4:
					var x := -1.0 + k * 0.66
					b.prim(box(0.06, 0.55 + Models.hash3(x, z, 3.0) * 0.4, 0.03), at(x, 3.5, z + 0.18), Color8(0x3e, 0x6e, 0x4a))


static func billow(g: Node3D, depth: float, t: float) -> void:
	for m in g.get_meta("sails"):
		m.set_shader_parameter("depth", depth)
		m.set_shader_parameter("t", t)
	for m in g.get_meta("flags", []):
		m.set_shader_parameter("t", t)


## A flat patch of foam (the wake).
static func foam_mesh() -> ArrayMesh:
	var b := Builder.new()
	var n := 6
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		b.tri(Vector3.ZERO, Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Color.WHITE)
	return b.commit()


## A gull: body and head in one mesh, two wings that flap (pivots "L" and "R").
static func gull() -> Node3D:
	var g := Node3D.new()
	var b := Builder.new()
	b.prim(cyl(0.12, 0.2, 0.9, 5), at(0, 0, 0, Vector3(PI / 2, 0, 0)), Color8(0xf4, 0xf4, 0xf0))
	b.prim(ball(0.14, 5, 3), at(0, 0.08, 0.5), Color8(0xf4, 0xf4, 0xf0))
	b.prim(cyl(0.0, 0.05, 0.2, 4), at(0, 0.06, 0.7, Vector3(PI / 2, 0, 0)), Color8(0xe8, 0xb0, 0x3a))
	b.prim(box(0.3, 0.04, 0.3), at(0, 0, -0.5), Color8(0xd8, 0xd8, 0xd4))
	g.add_child(instance(b.commit(), null, false))
	for sd in [-1, 1]:
		var w := Builder.new()
		w.tri(Vector3.ZERO, Vector3(sd * 0.75, 0, 0.12), Vector3(sd * 0.75, 0, -0.25), Color8(0xf0, 0xf0, 0xec))
		w.tri(Vector3(sd * 0.75, 0, 0.12), Vector3(sd * 1.35, 0, -0.18), Vector3(sd * 0.75, 0, -0.25), Color8(0x3a, 0x3c, 0x40))
		w.tri(Vector3.ZERO, Vector3(sd * 0.75, 0, -0.25), Vector3(0, 0, -0.3), Color8(0xe0, 0xe0, 0xdc))
		var piv := Node3D.new()
		piv.name = "L" if sd < 0 else "R"
		piv.position = Vector3(sd * 0.12, 0.05, 0.05)
		piv.add_child(instance(w.commit(), mat(true), false))
		g.add_child(piv)
	g.scale = Vector3.ONE * 0.75
	return g


## Firing arcs drawn on the water during a fight, one fan per battery.
static func arcs(st: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.position.y = 0.55
	g.visible = false
	for bt in Rules.batteries(st):
		var b := Builder.new()
		var segs := 18
		for i in segs:
			# local heading convention: bearing c faces (sin c, cos c)
			var a0: float = bt.c - bt.half + bt.half * 2 * i / segs
			var a1: float = bt.c - bt.half + bt.half * 2 * (i + 1) / segs
			b.tri(Vector3.ZERO, Vector3(sin(a1), 0, cos(a1)) * st.range, Vector3(sin(a0), 0, cos(a0)) * st.range, Color.WHITE)
		var mi := instance(b.commit(), null, false)
		mi.set_meta("k", bt.k)
		g.add_child(mi)
	return g


static func set_arcs(g: Node3D, active: Array, col: Color) -> void:
	for mi in g.get_children():
		mi.material_override = flat_mat(col, 0.17 if active.has(mi.get_meta("k")) else 0.05)


## The treasure's X, and a beam of light to find it.
static func treasure() -> Node3D:
	var g := Node3D.new()
	var b := Builder.new()
	b.prim(box(2.6, 0.3, 0.5), at(0, 0.7, 0, Vector3(0, PI / 4, 0)), RUST)
	b.prim(box(2.6, 0.3, 0.5), at(0, 0.7, 0, Vector3(0, -PI / 4, 0)), RUST)
	g.add_child(instance(b.commit()))
	var beam := cyl(0.6, 0.6, 30, 6)
	beam.cap_top = false
	beam.cap_bottom = false
	var bm := instance(beam, flat_mat(Color8(0xe0, 0xb4, 0x5a), 0.22), false)
	bm.position.y = 15
	g.add_child(bm)
	return g
