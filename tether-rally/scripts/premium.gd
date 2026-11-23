# "Premium low-poly" look (preview branch): the same simple shapes, made to feel crafted.
#   - a curated palette per world (soft whites, lavender shade, warm accents)
#   - faceted props with colour gradients instead of flat fills (pines, boulders)
#   - soft light: a lower, warmer sun, cool sky rim on every prop, glowing windows
#   - detail in motion: trees sway, snow sparkles, round drifting flakes, chimney smoke
# world_view.gd asks this file for the palette, the prop meshes and the prop material
# when WorldView.premium is on (the default on this branch; --look=classic turns it off).
extends RefCounted

const U := 0.01

# ---------------------------------------------------------------- palette
# Theme keys replaced per world. Only snow is tuned so far.
const PALETTE := {
	"snow": {
		"ground": Color("#eceff4"), "ground_dots": Color("#dde3ee"),
		"ambient": Color("#aab6dc"), "sun": Color("#fff0de"),
		"road": Color("#636c7f"), "patch": Color("#8896ab"), "patch_amt": 0.28, "patch_rough": 0.18,
		"streak": Color("#d6dbe0"), "edge": Color("#f3f4f6"), "road_rough": 0.75,
		"verge": Color("#cfd5e2"), "bank_face": Color("#d9deea"),
		"rail_top": Color("#f6f4f0"),
		"column": Color("#55607a"), "cap": Color("#f6f4f0"), "foot": Color("#f3f2f2"),
		"hub": Color("#f6f4f0"),
		"ramp_a": Color("#f6f4f0"), "ramp_b": Color("#d9664a"),
		"drift_a": Color("#fbfaf8"), "drift_b": Color("#b2b5c2"),
		"sky": Color("#8c9ce0"), "shade": Color("#3b3a7a"), "glint": Color("#fff2e2"),
		# premium-only keys
		"rim": Color("#b9c8ff"), "pine": [Color("#173f3d"), Color("#24594f"), Color("#3a7a62")],
		"snow_lo": Color("#d6def0"), "snow_hi": Color("#fffdf9"), "trunk": Color("#6b4a3a"),
		"stone": [Color("#5d6380"), Color("#8a8fa8")], "wood": Color("#8f5a3c"),
		"roof": Color("#fbf9f5"), "shingle": Color("#7a3f2e"), "gantry": Color("#3b3f52"),
		"bark": Color("#5e4436"), "log_top": Color("#fbfaf6"), "cut": Color("#d9b98a"),
	},
	"forest": {
		"ground": Color("#567c3b"), "ground_dots": Color("#6e8a40"),
		"ambient": Color("#c2d4c4"), "sun": Color("#ffe2b6"),
		"road": Color("#735a44"), "patch": Color("#654e3a"), "patch_amt": 0.25, "patch_rough": 0.6,
		"streak": Color("#86705a"), "edge": Color("#a48f64"), "road_rough": 0.95,
		"verge": Color("#62893f"), "bank_face": Color("#7e5f40"),
		"rail_top": Color("#5f8239"), "column": Color("#6e6a5a"), "cap": Color("#5f8239"),
		"foot": Color("#587f3a"), "hub": Color("#5f8239"),
		"drift_a": Color("#5a863a"), "drift_b": Color("#7e5f40"),
		"sky": Color("#8ec2e6"), "shade": Color("#22385a"), "glint": Color("#ffe6bc"),
		"rim": Color("#d8f0ff"), "leaf": Color("#3d7432"), "leaf_b": Color("#41793a"),
		"stone": [Color("#6a6e66"), Color("#9a9c8e")], "moss": Color("#6f9a44"),
		"wood": Color("#8a5d3e"), "roof": Color("#b05a3c"), "shingle": Color("#7a3a2a"), "gantry": Color("#4a3a2e"),
		"bark": Color("#6b4a34"), "log_top": Color("#5a843a"), "cut": Color("#d8b480"),
	},
	"sand": {
		"ground": Color("#e3b47c"), "ground_dots": Color("#d8a46c"),
		"ambient": Color("#f0cdb8"), "sun": Color("#ffe2b8"),
		"road": Color("#92684e"), "patch": Color("#7e5a42"), "patch_amt": 0.35, "patch_rough": 1.0,
		"streak": Color("#d4a674"), "edge": Color("#efcc98"), "road_rough": 0.95,
		"verge": Color("#d9a874"), "bank_face": Color("#cf9a66"),
		"sky": Color("#9ccbec"), "shade": Color("#6a3a62"), "glint": Color("#fff0d4"),
		"rim": Color("#ffe2cc"), "cactus": Color("#4f8f6a"), "palm": Color("#457f3e"),
		"stone": [Color("#b06e48"), Color("#dca476")], "wall": Color("#e2b585"), "hut_roof": Color("#c98c5a"),
		"gantry": Color("#5a3a2e"),
		"bark": Color("#b4a088"), "log_top": Color("#cdbca2"), "cut": Color("#e6d2b0"),
	},
	"rock": {
		"ground": Color("#767b6c"), "ground_dots": Color("#6a6f60"),
		"ambient": Color("#c3c8d6"), "sun": Color("#ffe6c8"),
		"road": Color("#5c5a58"), "patch": Color("#6c6864"), "patch_amt": 0.4, "patch_rough": 0.9,
		"streak": Color("#87837e"), "edge": Color("#aaaca2"), "road_rough": 0.9,
		"verge": Color("#7e8274"), "bank_face": Color("#787b70"),
		"sky": Color("#a6b8dc"), "shade": Color("#3a3458"), "glint": Color("#ffecd0"),
		"rim": Color("#dce4ff"), "spire": Color("#6a6c6c"), "heather": Color("#8a6a9a"),
		"stone": [Color("#5a5d5e"), Color("#8e908c")], "moss": Color("#7d9a50"),
		"wall": Color("#9a988e"), "hut_roof": Color("#5a5c66"), "gantry": Color("#3e3c40"),
		"bark": Color("#6e655c"), "log_top": Color("#6a8448"), "cut": Color("#cdb894"),
	},
}

static func restyle(name: String, th: Dictionary) -> Dictionary:
	if not PALETTE.has(name):
		return th
	var out := th.duplicate()
	out.merge(PALETTE[name], true)
	return out

# ---------------------------------------------------------------- props
# A band of a cone with its own radius and colour per corner (flat facets, soft gradients).
# r0/r1: radius per side at the bottom/top ring; c0/c1: colour per side (or one colour).
static func _ring_band(st: SurfaceTool, y0: float, y1: float, r0: Array, r1: Array, c0, c1, rot := 0.0, droop := 0.0) -> void:
	var n := r0.size()
	for k in n:
		var a0 := rot + TAU * k / n
		var a1 := rot + TAU * (k + 1) / n
		var k1 := (k + 1) % n
		var p0 := Vector3(cos(a0) * r0[k], y0, sin(a0) * r0[k])
		var p1 := Vector3(cos(a1) * r0[k1], y0, sin(a1) * r0[k1])
		var p2 := Vector3(cos(a1) * r1[k1], y1, sin(a1) * r1[k1])
		var p3 := Vector3(cos(a0) * r1[k], y1, sin(a0) * r1[k])
		# lower corners droop between the ribs: a scalloped, hand-cut skirt
		var mid := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		var cc0: Color = c0[k] if c0 is Array else c0
		var cc0b: Color = c0[k1] if c0 is Array else c0
		var cc1: Color = c1[k] if c1 is Array else c1
		var cc1b: Color = c1[k1] if c1 is Array else c1
		var tri := func(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, ccc: Color) -> void:
			var nrm := (b - a).cross(c - a)
			if nrm.length_squared() < 1e-10:
				return
			nrm = nrm.normalized()
			if nrm.dot(mid) < 0.0:
				nrm = -nrm
			for v in [[a, ca], [b, cb], [c, ccc]]:
				st.set_normal(nrm)
				st.set_color(v[1])
				st.add_vertex(v[0] * U)
		if droop != 0.0:
			p0.y -= droop * float(k % 2)
			p1.y -= droop * float(k1 % 2)
		tri.call(p0, p1, p2, cc0, cc0b, cc1b)
		if (p3 - p2).length_squared() > 1e-8:
			tri.call(p0, p2, p3, cc0, cc1b, cc1)

static func _fill(n: int, v) -> Array:
	var a := []
	a.resize(n)
	a.fill(v)
	return a

# A snowy pine: a tapering stack of scalloped tiers, each dark at its heart and lighter at
# the rim, with a ragged snow cap that drips down between the branches.
static func pine(tiers: int, h: float, r: float, pal: Dictionary, seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var trunk: Color = pal["trunk"]
	_ring_band(st, 0.0, h * 0.22, _fill(6, r * 0.15), _fill(6, r * 0.1), trunk.darkened(0.25), trunk)
	var greens: Array = pal["pine"]
	var snow_lo: Color = pal["snow_lo"]
	var snow_hi: Color = pal["snow_hi"]
	var sides := 7
	var y := h * 0.16
	var tier_h := (h - y) / tiers * 1.4
	for t in tiers:
		var f: float = float(t) / maxi(1, tiers - 1)
		var rr := r * (1.0 - 0.24 * t)
		var rot := 0.7 * t
		var y_top := y + tier_h
		# skirt underside (seen at the edges only): darkest green
		var r_out: Array = []
		var r_snow: Array = []
		var g_out: Array = []
		var g_in: Array = []
		var s_lo: Array = []
		for k in sides:
			var j := rng.randf()
			r_out.append(rr * (0.92 + 0.14 * j))
			# the snow reaches further down some branches than others
			r_snow.append(rr * (0.66 + 0.24 * rng.randf()))
			g_out.append((greens[2] as Color).lerp(greens[1], 0.3 + 0.5 * j).lightened(0.05 * f))
			g_in.append((greens[1] as Color).lerp(greens[0], 0.3))
			s_lo.append(snow_lo.lerp(snow_hi, 0.35 * rng.randf()))
		var droop := tier_h * 0.07
		# underside (seen at the edges only): darkest green
		_ring_band(st, y - tier_h * 0.08, y + tier_h * 0.02, _fill(sides, rr * 0.35), r_out, greens[0], g_out, rot, -droop)
		# a green fringe of branch tips, then snow settled on the top of the tier
		var snow_y := y + tier_h * 0.14
		_ring_band(st, y + tier_h * 0.02, snow_y, r_out, r_snow, g_out, g_in, rot, droop)
		_ring_band(st, snow_y - 0.5, y_top, r_snow, _fill(sides, 0.0), s_lo, snow_hi, rot)
		y += tier_h * 0.6
	return st.commit()

# A faceted boulder: a squashed, jittered dome with snow settled on its flatter faces.
static func boulder(pal: Dictionary, seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var stone: Array = pal["stone"]
	var sides := 7
	var rings := [[-4.0, 42.0], [12.0, 40.0], [24.0, 30.0], [33.0, 14.0], [36.0, 0.0]]
	var pts: Array = []
	for ri in rings.size():
		var row: Array = []
		for k in sides:
			var a := TAU * (k + 0.5 * ri) / sides
			var rr: float = rings[ri][1] * (0.82 + 0.3 * rng.randf())
			row.append(Vector3(cos(a) * rr, rings[ri][0] + rng.randf() * 4.0 - 2.0, sin(a) * rr))
		pts.append(row)
	for ri in rings.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			for tri in [[pts[ri][k], pts[ri][k1], pts[ri + 1][k1]], [pts[ri][k], pts[ri + 1][k1], pts[ri + 1][k]]]:
				var a: Vector3 = tri[0]; var b: Vector3 = tri[1]; var c: Vector3 = tri[2]
				var nrm := (b - a).cross(c - a)
				if nrm.length_squared() < 1e-6:
					continue
				nrm = nrm.normalized()
				var ctr := (a + b + c) / 3.0
				if nrm.dot(Vector3(ctr.x, 0.0, ctr.z)) < 0.0 and nrm.y < 0.0:
					nrm = -nrm
				var snowy := nrm.y > 0.62 and ctr.y > 14.0
				for v: Vector3 in [a, b, c]:
					var col: Color
					if snowy:
						col = (pal["snow_lo"] as Color).lerp(pal["snow_hi"], clampf(v.y / 36.0, 0.0, 1.0))
					else:
						col = (stone[0] as Color).lerp(stone[1], clampf((v.y + 4.0) / 40.0, 0.0, 1.0))
					st.set_normal(nrm)
					st.set_color(col)
					st.add_vertex(v * U)
	return st.commit()

# Any vertex-coloured prop shaded with a soft gradient: darker at its foot, lighter towards
# its top, and each facet a touch lighter or darker than its neighbour (hand-cut facets
# instead of one flat fill per part). Alpha is kept (glowing windows).
static func gradient(mesh: ArrayMesh, h: float, lo := 0.7, hi := 1.12, facet := 0.06) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		if cs.size() != vs.size():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			continue
		for k in vs.size():
			var f := lerpf(lo, hi, clampf(vs[k].y / (h * U), 0.0, 1.0))
			var tri := k / 3
			f *= 1.0 + facet * (fposmod(sin(tri * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0)
			var c := cs[k]
			cs[k] = Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0), c.a)
		arr[Mesh.ARRAY_COLOR] = cs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out

# A fallen tree: a tapering trunk lying on the ground, pale sawn faces at both ends and two
# snapped branch stubs. Its upper faces wear
# the world's cover (snow, moss, sand-bleach). Long axis along x, about 200 units long.
static func fallen_log(pal: Dictionary, seed_: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var bark: Color = pal["bark"]
	var top: Color = pal["log_top"]
	var cut: Color = pal["cut"]
	var tri := func(a: Vector3, b: Vector3, c: Vector3, centre: Vector3, col_fn: Callable) -> void:
		var nrm := (b - a).cross(c - a)
		if nrm.length_squared() < 1e-8:
			return
		nrm = nrm.normalized()
		if nrm.dot((a + b + c) / 3.0 - centre) < 0.0:
			nrm = -nrm
		for v: Vector3 in [a, b, c]:
			st.set_normal(nrm)
			st.set_color(col_fn.call(v, nrm))
			st.add_vertex(v * U)
	var shade := func(v: Vector3, n: Vector3) -> Color:
		if n.y > 0.82 and rng.randf() < 0.7:   # patchy cover on the upper faces
			return top.lerp(top.lightened(0.12), rng.randf())
		return bark.darkened(0.25).lerp(bark.lightened(0.08), clampf(v.y / 26.0, 0.0, 1.0))
	var sides := 7
	var x0 := -95.0; var x1 := 95.0
	var r0 := 18.0; var r1 := 13.0
	var segs := 3
	var ring := func(x: float, r: float, y: float) -> Array:
		var pts := []
		for k in sides:
			var a := TAU * k / sides + 0.3
			var j := 1.0 + (rng.randf() - 0.5) * 0.12
			pts.append(Vector3(x, y + sin(a) * r * j, cos(a) * r * j))
		return pts
	var rings := []
	for i in segs + 1:
		var t := float(i) / segs
		var r := lerpf(r0, r1, t)
		rings.append(ring.call(lerpf(x0, x1, t), r, r * 0.75 + sin(t * 2.4) * 2.0))
	for i in segs:
		var cx := lerpf(x0, x1, (i + 0.5) / segs)
		var c := Vector3(cx, lerpf(r0, r1, (i + 0.5) / segs) * 0.75, 0.0)
		for k in sides:
			var k1 := (k + 1) % sides
			tri.call(rings[i][k], rings[i][k1], rings[i + 1][k1], c, shade)
			tri.call(rings[i][k], rings[i + 1][k1], rings[i + 1][k], c, shade)
	# sawn / snapped thin end: pale rings of wood
	var tip_c := Vector3(x1 + 1.0, r1 * 0.75, 0.0)
	for k in sides:
		tri.call(rings[segs][k], rings[segs][(k + 1) % sides], tip_c, Vector3(x1 - 10.0, r1 * 0.75, 0.0),
			func(v: Vector3, n: Vector3) -> Color: return cut if v.distance_to(tip_c) < 3.0 else cut.darkened(0.12))
	# the thick end: a plain sawn face too (no root plate: simpler, and cheaper)
	var butt_c := Vector3(x0 - 1.0, r0 * 0.75, 0.0)
	for k in sides:
		tri.call(rings[0][(k + 1) % sides], rings[0][k], butt_c, Vector3(x0 + 10.0, r0 * 0.75, 0.0),
			func(v: Vector3, n: Vector3) -> Color: return cut if v.distance_to(butt_c) < 4.0 else cut.darkened(0.15))
	# two snapped branch stubs reaching up and out
	for b in 2:
		var bx := lerpf(x0, x1, 0.35 + 0.3 * b)
		var side := 1.0 if b == 0 else -1.0
		var base := Vector3(bx, r0 * 0.9, side * 4.0)
		var tip := base + Vector3(14.0, 24.0, side * 16.0)
		var br := 3.5
		var bpts := [base + Vector3(-br, 0, 0), base + Vector3(br, 0, -br * side), base + Vector3(0, 0, br * side)]
		for k in 3:
			tri.call(bpts[k], bpts[(k + 1) % 3], tip, base + Vector3(0, 10, 0), shade)
	return st.commit()

# ---------------------------------------------------------------- materials
static var _shader: Shader

# Vertex-coloured props: a cool sky rim on the silhouettes (soft fresnel, so the facets
# read as rounded and lit from all round), windows glow (vertex alpha < 1 = lit glass),
# and trees sway in the wind (sway = metres at the top, `sway_h` = height that sways fully).
static func prop_mat(rim: Color, sway := 0.0, sway_h := 2.0) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rim_col : source_color;
uniform float rim = 0.16;
uniform float sway = 0.0;
uniform float sway_h = 2.0;
uniform float gamma = 2.2;   // 1.0 on the browser's Compatibility renderer, which draws darker
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float k = clamp(VERTEX.y / sway_h, 0.0, 1.0);
	k *= k;
	float ph = TIME * 1.3 + o.x * 0.35 + o.z * 0.27;
	vec2 w = vec2(sin(ph) + 0.35 * sin(ph * 2.7 + 1.3), 0.5 * cos(ph * 0.9)) * sway * k;
	VERTEX.xz += w;
}
void fragment() {
	// the palette is written in sRGB: convert, so the colours land as picked
	vec3 c = pow(COLOR.rgb, vec3(gamma));
	ALBEDO = c;
	ROUGHNESS = 0.82;
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	EMISSION = rim_col * fr * rim + c * glow * 2.2;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("rim_col", rim)
	m.set_shader_parameter("sway", sway)
	m.set_shader_parameter("sway_h", sway_h)
	m.set_shader_parameter("gamma", gamma())
	return m

# how vertex colours are linearised: Mobile (phones) works in linear light; the browser's
# Compatibility renderer already draws darker, so it keeps them as they are
static func gamma() -> float:
	return 1.0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 2.2

# a soft round dot (falling flakes, smoke puffs)
static var _dot: GradientTexture2D
static func soft_dot() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.width = 32
		_dot.height = 32
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
		_dot.gradient = g
	return _dot

# a falling leaf: a pointed lens with a soft edge and a faint midrib (white, tinted by the
# particle colour), so the forest's leaves stop reading as square pixels
static var _leaf: ImageTexture
static func leaf_tex() -> ImageTexture:
	if _leaf == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0   # across the leaf
				var v := (y + 0.5) / n * 2.0 - 1.0   # along it
				# lens: inside two offset circles, tip to tip along v
				var r := 1.55
				var d := maxf(Vector2(u + 0.62 * r - 0.07, v).length(), Vector2(u - 0.62 * r + 0.07, v).length()) - r
				var a := clampf(-d * 9.0, 0.0, 1.0) * clampf((1.0 - absf(v)) * 6.0, 0.0, 1.0)
				var shade := 1.0 - 0.25 * clampf(1.0 - absf(u) * 14.0, 0.0, 1.0) - 0.12 * absf(u)
				img.set_pixel(x, y, Color(shade, shade, shade, a))
		_leaf = ImageTexture.create_from_image(img)
	return _leaf

# a lazy curl of smoke from a chimney, a dozen soft puffs
static func smoke(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 12
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.local_coords = false
	p.direction = Vector3(0.25, 1.0, 0.1)
	p.spread = 8.0
	p.initial_velocity_min = 0.35
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0.12, 0.02, 0.05)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.25))
	c.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = c
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(0.95, 0.95, 0.98, 0.0), Color(0.93, 0.93, 0.97, 0.35), Color(0.9, 0.92, 0.98, 0.0)])
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = pos
	return p
