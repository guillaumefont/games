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
varying float hgt;
float wave(float x, float z) {
	return sin(x * 0.13 + t * 0.9) * 0.3 + cos(z * 0.11 + t * 0.7) * 0.3 + sin((x + z) * 0.07 + t * 1.3) * 0.16;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = wave(w.x, w.z);
	hgt = VERTEX.y;
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) n = -n;
	NORMAL = n;
	ALBEDO = mix(deep, crest, clamp((hgt + 0.2) * 0.9, 0.0, 1.0) * 0.55);
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
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
	b.prim(cyl(0.0, 0.9 * s, 2.3 * s, 6), at(x, y + 1.9 * s, z, Vector3(0, rng.randf() * 3, 0)), greens[rng.randi() % 3])


## An island at (x, z) of radius r, with its seed: sand, grass, maybe a hill, trees and rocks.
static func island(x: float, z: float, r: float, port := false) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x) * 131 + absf(z) * 17 + r * 7)
	var b := Builder.new()
	var segs := 7 + rng.randi() % 3
	b.prim(cyl(r * 0.92, r * 1.06, 2.8, segs), at(0, 0.1, 0), Color8(0xd5, 0xc7, 0xa2), 0.9, x, z)
	b.prim(cyl(r * 0.6, r * 0.8, 1.6, segs), at(0, 1.9, 0), Color8(0x7c, 0x96, 0x68), 0.8, x + 3, z)
	if r > 9 and not port:
		b.prim(cyl(0.0, r * 0.42, r * 0.45, segs), at(0, 2.7 + r * 0.22, 0), Color8(0x8a, 0x9a, 0x86), 0.6, x, z + 5)
	var nt := int(r * 0.45) - (3 if port else 0)
	for i in nt:
		var a := rng.randf() * TAU
		var d := r * (0.2 + rng.randf() * 0.4)
		_tree(b, cos(a) * d, sin(a) * d, 2.6, 0.8 + rng.randf() * 0.5, rng)
	for i in 3:
		var a := rng.randf() * TAU
		var rr := 0.5 + rng.randf() * 0.9
		b.prim(ball(rr, 5, 2), at(cos(a) * r * 1.02, 0.4, sin(a) * r * 1.02, Vector3(rng.randf() * 3, rng.randf() * 3, 0)), Color8(0x8b, 0x8f, 0x8c))
	if port:
		_port(b)
	var g := Node3D.new()
	g.position = Vector3(x, 0, z)
	g.add_child(instance(b.commit()))
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
	return g


## The player's port: a hut, a jetty, a flag.
static func _port(b: Builder) -> void:
	var r := Rules.BASE_R
	b.prim(box(4.4, 2.6, 3.4), at(-2, 4, 2), Color8(0xb5, 0x9b, 0x78))
	b.prim(cyl(0.0, 3.6, 2.2, 4), at(-2, 6.4, 2, Vector3(0, PI / 4, 0)), Color8(0x7a, 0x45, 0x36))
	for i in 6:
		b.prim(box(3, 0.25, 1.5), at(0, 1.1, r - 1 + i * 1.6), PLANK)
	for pk in [[-1.4, 0], [1.4, 0], [-1.4, 1], [1.4, 1]]:
		b.prim(cyl(0.18, 0.18, 2.6, 5), at(pk[0], 0.2, r + 2 + pk[1] * 5), WOOD)
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

## The hull: U-shaped frames along the boat, a pointed stem, a transom and sheer.
static func hull_into(b: Builder, color: Color) -> void:
	var ZS := [-2.9, -2.5, -1.8, -0.9, 0.0, 0.9, 1.7, 2.4, 2.95, 3.35]
	var PROF := [[0.0, 0.0], [0.5, 0.1], [0.84, 0.36], [1.0, 0.66], [0.95, 1.0]]
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
	var c_bottom := Color8(0x4a, 0x2e, 0x22)
	var c_wale := Color8(0x3a, 0x2a, 0x20)
	var c_deck := Color8(0xa0, 0x7a, 0x52)
	for i in sections.size() - 1:
		var A: Array = sections[i]
		var B: Array = sections[i + 1]
		for j in A.size() - 1:
			var cy: float = (A[j].y + A[j + 1].y + B[j].y + B[j + 1].y) / 4.0
			var cz: float = (A[j].z + B[j].z) / 2.0
			var cc := c_bottom if cy < 0.02 else (c_wale if cy > _top(cz) - 0.18 else color)
			b.tri(A[j], B[j], B[j + 1], cc)
			b.tri(A[j], B[j + 1], A[j + 1], cc)
		# the deck, a little below the gunwale
		var n := A.size() - 1
		var k := 0.9
		var dy := -0.12
		var al := Vector3(A[0].x * k, A[0].y + dy, A[0].z)
		var ar := Vector3(A[n].x * k, A[n].y + dy, A[n].z)
		var bl := Vector3(B[0].x * k, B[0].y + dy, B[0].z)
		var br := Vector3(B[n].x * k, B[n].y + dy, B[n].z)
		b.tri(al, bl, br, c_deck)
		b.tri(al, br, ar, c_deck)
	# transom
	var S0: Array = sections[0]
	var top0 := _top(ZS[0])
	var cen := Vector3(0, (_bottom(ZS[0]) + top0) / 2.0, ZS[0])
	for j in S0.size() - 1:
		var y: float = (S0[j].y + S0[j + 1].y) / 2.0
		b.tri(cen, S0[j + 1], S0[j], c_bottom if y < 0.02 else (c_wale if y > top0 - 0.18 else color))
	b.tri(S0[0], S0[S0.size() - 1], cen, c_wale)


static func _half_w(z: float) -> float:
	if z < -0.4:
		return 1.2 * (0.7 + 0.3 * sin(minf(1.0, (z + 2.9) / 2.5) * PI / 2))
	return 1.2 * pow(maxf(0.0, cos((z + 0.4) / 3.75 * PI / 2)), 0.75)


static func _bottom(z: float) -> float:
	return -0.45 + 0.75 * pow(maxf(0.0, (z - 1.1) / 2.25), 2) + 0.3 * pow(maxf(0.0, (-1.6 - z) / 1.3), 2)


static func _top(z: float) -> float:
	return 0.95 + 0.4 * pow(maxf(0.0, (z - 1.4) / 1.95), 2) + 0.28 * pow(maxf(0.0, (-1.4 - z) / 1.5), 2)


static func sail_shader() -> Shader:
	if _sail_shader == null:
		_sail_shader = Shader.new()
		_sail_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform float depth = 0.35;
uniform float t = 0.0;
uniform vec2 size = vec2(2.4, 1.9);
void vertex() {
	float u = VERTEX.x / (size.x * 0.5);
	float v = (VERTEX.y + size.y * 0.5) / size.y;
	float belly = (1.0 - u * u) * (0.55 + 0.45 * sin(3.14159 * min(1.0, v * 1.15)));
	float flutter = sin(t * 7.0 + u * 3.0 + v * 2.0) * 0.03 * (1.0 - v);
	VERTEX.z += depth * belly + flutter;
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


## A sail: a 4 x 4 canvas that billows forward with the wind (in its shader).
static func sail_mesh(w: float, h: float, col: Color, trim: Color) -> ArrayMesh:
	var key := "sail%.2f%.2f%s%s" % [w, h, col.to_html(), trim.to_html()]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	for i in 4:
		for j in 4:
			var x0 := -w / 2 + w * i / 4.0
			var x1 := -w / 2 + w * (i + 1) / 4.0
			var y0 := -h / 2 + h * j / 4.0
			var y1 := -h / 2 + h * (j + 1) / 4.0
			var c := trim if (y0 + y1) / 2.0 < -h * 0.25 else col
			b.tri(Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), c)
			b.tri(Vector3(x0, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0), c)
	_cache[key] = b.commit()
	return _cache[key]


## The look of a ship from its hull and upgrades.
static func ship_cfg(hk: String, up: Dictionary, crew: Array, colors: Dictionary) -> Dictionary:
	var H: Dictionary = Rules.HULLS[hk]
	var st := Rules.ship_stats(hk, up, 0)
	var c := {"masts": H.masts, "sail_lv": int(up.get("voiles", 0)), "oars": 1 + int(up.get("rameurs", 0)) if H.caps.rameurs > 0 else 0,
		"side": st.side, "bow": st.bow, "stern": st.stern, "grappin": int(up.get("grappin", 0)) > 0, "crew": crew, "scale": H.scale,
		"hull": Color8(0x7a, 0x52, 0x34), "sail": SAIL, "trim": RUST, "flag": RUST}
	c.merge(colors, true)
	return c


static func player_cfg(s: Dictionary) -> Dictionary:
	var crew := []
	for c in Rules.CREW:
		for i in int(s.crew[c.k]):
			crew.append(c.color)
	return ship_cfg(s.ship, s.up, crew, {})


## A ship: root (turned by heading) > body (scaled, rolls) > one mesh for the wood and guns,
## the sails (each with its billow material) and the oars (pivots that row).
static func ship(c: Dictionary) -> Node3D:
	var g := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	g.add_child(body)
	var b := Builder.new()
	hull_into(b, c.hull)
	b.prim(cyl(0.05, 0.08, 2, 5), at(0, 1.55, 3.6, Vector3(PI / 2 - 0.35, 0, 0)), WOOD)
	var n: int = clampi(c.masts, 1, 3)
	var sl: int = c.sail_lv
	var zs: Array = [0.2] if n == 1 else ([1.0, -0.9] if n == 2 else [1.5, 0.0, -1.5])
	var sails := []
	for i in zs.size():
		var z: float = zs[i]
		var h := 4.6 if i == 0 and n > 1 else 4.1
		b.prim(cyl(0.09, 0.13, h, 5), at(0, 1 + h / 2, z), WOOD)
		var w := (2.0 if n == 3 else 2.4) * (1 + 0.08 * sl)
		var sh := 1.9 * (1 + 0.1 * sl)
		var y := 1 + h * 0.6
		var sm := ShaderMaterial.new()
		sm.shader = sail_shader()
		sm.set_shader_parameter("size", Vector2(w, sh))
		var sail := instance(sail_mesh(w, sh, c.sail, c.trim), sm)
		sail.position = Vector3(0, y, z + 0.14)
		body.add_child(sail)
		sails.append(sm)
		b.prim(cyl(0.06, 0.06, w + 0.4, 5), at(0, y + sh / 2 + 0.02, z + 0.14, Vector3(0, 0, PI / 2)), WOOD)
		b.prim(cyl(0.06, 0.06, w + 0.4, 5), at(0, y - sh / 2 - 0.02, z + 0.14, Vector3(0, 0, PI / 2)), WOOD)
		if i == 0:
			b.prim(box(0.9, 0.5, 0.05), at(0.5, 1 + h + 0.1, z), c.flag)
	var ng: int = clampi(c.side, 1, 8)
	for side in [-1, 1]:
		for k in ng:
			b.prim(cyl(0.13, 0.15, 0.7, 6), at(side * 1.15, 1.05, 0.4 if ng == 1 else 1.6 - k * (3.0 / (ng - 1)), Vector3(0, 0, PI / 2)), IRON)
	for k in int(c.bow):
		b.prim(cyl(0.12, 0.14, 0.8, 6), at((k - (c.bow - 1) / 2.0) * 0.4, 1.3, 2.75, Vector3(PI / 2, 0, 0)), IRON)
	for k in int(c.stern):
		b.prim(cyl(0.12, 0.14, 0.8, 6), at((k - (c.stern - 1) / 2.0) * 0.4, 1.2, -2.9, Vector3(PI / 2, 0, 0)), IRON)
	if c.grappin:
		b.prim(cyl(0.05, 0.05, 1.2, 4), at(0, 1.3, 3.2, Vector3(PI / 2.6, 0, 0)), Color8(0x3b, 0x3f, 0x42))
		b.prim(box(0.5, 0.1, 0.1), at(0, 1.75, 3.65, Vector3(0.4, 0, 0)), Color8(0x3b, 0x3f, 0x42))
	var crew: Array = c.crew
	for i in mini(crew.size(), 10):
		var x := 0.45 if i % 2 else -0.45
		var z := 1.6 - floorf(i / 2.0) * 0.75
		b.prim(box(0.28, 0.5, 0.26), at(x, 1.28, z), crew[i])
		b.prim(box(0.22, 0.22, 0.22), at(x, 1.65, z), Color8(0xd9, 0xb9, 0x9a))
	var hull := instance(b.commit(), mat(true))
	hull.name = "Hull"
	body.add_child(hull)
	# oars: pivots on the gunwale, the blade dips during the stroke
	var oars := []
	var no: int = clampi(c.oars, 0, 5)
	if no > 0:
		for side in [-1, 1]:
			var ob := Builder.new()
			ob.prim(box(2.3, 0.07, 0.09), at(side * 1.15, 0, 0), PLANK)
			ob.prim(box(0.55, 0.04, 0.26), at(side * 2.15, 0, 0), PLANK)
			var oar_mesh := ob.commit()
			for k in no:
				var piv := Node3D.new()
				piv.position = Vector3(side * 1.0, 0.85, 0.0 if no == 1 else 1.7 - k * (3.4 / (no - 1)))
				piv.add_child(instance(oar_mesh, null, false))
				piv.set_meta("side", side)
				body.add_child(piv)
				oars.append(piv)
	body.scale = c.scale
	g.set_meta("body", body)
	g.set_meta("oars", oars)
	g.set_meta("sails", sails)
	return g


## Rowing: the blade dips while it sweeps aft and comes out to go back. `ph` is the stroke phase.
static func row(g: Node3D, ph: float, rowing: bool) -> void:
	for o in g.get_meta("oars"):
		var sd: int = o.get_meta("side")
		var sweep := -0.5 * cos(ph) if rowing else 0.0
		var dip := 0.14 + 0.42 * maxf(0.0, sin(ph)) if rowing else 0.12
		o.rotation = Vector3(0, sd * sweep, -sd * dip)


static func billow(g: Node3D, depth: float, t: float) -> void:
	for m in g.get_meta("sails"):
		m.set_shader_parameter("depth", depth)
		m.set_shader_parameter("t", t)


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
