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
		"road": Color("#4d5d82"), "patch": Color("#7f9dc2"), "patch_amt": 0.28, "patch_rough": 0.18,
		"streak": Color("#cfe2f2"), "edge": Color("#f3f5f9"), "road_rough": 0.75,
		"verge": Color("#cdd5e6"), "bank_face": Color("#d9dfec"),
		"rail_top": Color("#f6f4f0"),
		"column": Color("#55607a"), "cap": Color("#f6f4f0"), "foot": Color("#f3f2f2"),
		"hub": Color("#f6f4f0"),
		"ramp_a": Color("#f6f4f0"), "ramp_b": Color("#d9664a"),
		"drift_a": Color("#fbfaf8"), "drift_b": Color("#a3acd0"),
		"sky": Color("#8c9ce0"), "shade": Color("#3b3a7a"), "glint": Color("#fff2e2"),
		# premium-only keys
		"rim": Color("#b9c8ff"), "pine": [Color("#173f3d"), Color("#24594f"), Color("#3a7a62")],
		"snow_lo": Color("#d6def0"), "snow_hi": Color("#fffdf9"), "trunk": Color("#6b4a3a"),
		"stone": [Color("#5d6380"), Color("#8a8fa8")], "wood": Color("#8f5a3c"),
		"roof": Color("#fbf9f5"), "shingle": Color("#7a3f2e"), "gantry": Color("#3b3f52"),
	},
	"forest": {
		"ground": Color("#5a8a3a"), "ground_dots": Color("#4f7d33"),
		"ambient": Color("#bcd3c0"), "sun": Color("#ffe4bc"),
		"road": Color("#6e5844"), "patch": Color("#5a4632"), "patch_amt": 0.4, "patch_rough": 0.5,
		"streak": Color("#86705a"), "edge": Color("#9c8a5e"), "road_rough": 0.95,
		"verge": Color("#6b9444"), "bank_face": Color("#86643f"),
		"rail_top": Color("#6fa048"), "column": Color("#6e6a5a"), "cap": Color("#6fa048"),
		"foot": Color("#5f8f3e"), "hub": Color("#6fa048"),
		"drift_a": Color("#5f913c"), "drift_b": Color("#8a6640"),
		"sky": Color("#8ec2e6"), "shade": Color("#263f5e"), "glint": Color("#ffe8c0"),
		"rim": Color("#d4f0ff"), "leaf": Color("#3a7030"), "leaf_b": Color("#3f7a3a"),
		"stone": [Color("#6a6e66"), Color("#9a9c8e")], "moss": Color("#79a848"),
		"wood": Color("#8f5f3e"), "roof": Color("#5e8f3a"), "shingle": Color("#5a3e2c"), "gantry": Color("#4a3a2e"),
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
	var sides := 9
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
