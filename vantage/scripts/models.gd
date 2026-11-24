class_name Models
extends RefCounted
## Low poly models built in code: flat shaded, vertex coloured, one mesh per object. No
## imported art: everything here is original.

const STEEL := Color8(0xdc, 0xe3, 0xea)
const STEEL_D := Color8(0x7d, 0x8b, 0x99)
const CYAN := Color8(0x3d, 0xd6, 0xf5)
const NAVY := Color8(0x24, 0x34, 0x4a)
const FOE := Color8(0xc8, 0x3a, 0x3a)
const FOE_D := Color8(0x4a, 0x3c, 0x44)
const AMBER := Color8(0xff, 0xa8, 0x2e)
const HULL := Color8(0x5c, 0x63, 0x6e)
const HULL_D := Color8(0x3a, 0x3f, 0x48)
const DECK := Color8(0x76, 0x7d, 0x86)
const SEA := Color8(0x23, 0x6c, 0x98)
const SEA_D := Color8(0x17, 0x4b, 0x78)
const SAND := Color8(0xdc, 0xc3, 0x86)
const GRASS := Color8(0x74, 0xa8, 0x4e)
const FOREST := Color8(0x3f, 0x77, 0x44)
const ROCK := Color8(0x9a, 0x94, 0x88)
const SKY := Color8(0x9c, 0xd4, 0xee)

static var _mat: StandardMaterial3D
static var _cache := {}


## The shared vertex-coloured material.
static func mat() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.62
		_mat.metallic_specular = 0.55
		# a soft rim catches the silhouette against the ground
		_mat.rim_enabled = true
		_mat.rim = 0.35
		_mat.rim_tint = 0.6
	return _mat


## The terrain material: matte, no rim, so the ground stays calm under the action. Where a vertex
## is flagged as bare rock (alpha below 1: steep faces, see `ground_chunk`), it shows strata, bands
## that follow the height, so canyon walls and cliffs read as layered rock. Where the
## ground lies at the water line (`SEA_Y`, flat), it turns liquid by the theme (`LIQUIDS`): open water
## gets a glossy sun highlight and slow drifting glints, lava glows and churns.
const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float sea_y = -0.4;
uniform float water = 1.0;
uniform float lava = 0.0;
uniform vec3 glint : source_color = vec3(1.0, 0.97, 0.88);
varying vec3 wpos;
varying float flat_up;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flat_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
	// vertex colours are sRGB (as `vertex_color_is_srgb` does it)
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = to_linear(COLOR.rgb);
	}
}

void fragment() {
	vec3 col = COLOR.rgb;
	float rock = 1.0 - COLOR.a;
	if (rock > 0.01) {
		float y = wpos.y + 0.35 * sin(wpos.x * 0.23 + wpos.z * 0.17) + 0.15 * sin(wpos.z * 0.61);
		float band = fract(y * 0.62);
		float k = mix(0.78, 1.1, smoothstep(0.1, 0.2, band)) * mix(1.0, 0.86, smoothstep(0.62, 0.7, band) * (1.0 - smoothstep(0.82, 0.9, band)));
		// thicker beds of warmer and cooler rock
		float bed = smoothstep(0.4, 0.5, fract(y * 0.23 + 0.3)) * (1.0 - smoothstep(0.75, 0.85, fract(y * 0.23 + 0.3)));
		vec3 kc = vec3(k) * mix(vec3(1.0), vec3(1.07, 0.93, 0.82), bed);
		col *= mix(vec3(1.0), kc, rock);
	}
	float wet = (1.0 - smoothstep(sea_y + 0.01, sea_y + 0.12, wpos.y)) * smoothstep(0.92, 0.99, flat_up);
	float t = TIME;
	vec2 p = wpos.xz;
	// two slow swells crossing, and finer ripples on them
	float w1 = sin(p.x * 0.35 + p.y * 0.21 + t * 0.9) + sin(p.x * -0.18 + p.y * 0.42 - t * 0.7);
	float w2 = sin(p.x * 1.7 - p.y * 1.1 + t * 2.3) * sin(p.x * 0.9 + p.y * 1.9 - t * 1.9);
	vec3 n = normalize(vec3(cos(p.x * 0.35 + p.y * 0.21 + t * 0.9) * 0.06 + w2 * 0.05, 1.0,
		cos(p.x * -0.18 + p.y * 0.42 - t * 0.7) * 0.06 + w2 * 0.04));
	float aw = wet * water;
	// crest glints: short thin streaks along the swell, where the ripples peak on it
	float line = smoothstep(0.86, 1.0, sin(p.x * 0.31 + p.y * 0.62 + t * 0.8 + w2 * 0.6));
	float crest = line * smoothstep(0.2, 0.9, w2 * 0.5 + 0.5) * smoothstep(-0.5, 1.5, w1);
	col += glint * crest * 0.07 * aw;
	ALBEDO = col;
	NORMAL = mix(NORMAL, normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz), aw);
	ROUGHNESS = mix(0.95, 0.32, aw);
	SPECULAR = mix(0.2, 0.6, aw);
	// lava: a dark crust broken by hot veins that crawl and pulse, glowing in the dark
	float al = wet * lava;
	float vein = smoothstep(0.55, 0.95, abs(sin(p.x * 0.45 + w1 * 0.9 + t * 0.25) * sin(p.y * 0.38 - w2 * 0.7 - t * 0.2)));
	ALBEDO = mix(ALBEDO, col * mix(0.35, 1.1, vein), al);
	EMISSION = col * al * (0.25 + vein * (1.3 + 0.3 * sin(t * 2.0 + p.x * 0.3)));
}
"""
const SEA_Y := -0.4
## Each theme's liquid at the water line: water gloss and glints, or lava glow.
const LIQUIDS := {"coast": [1.0, 0.0], "dunes": [0.0, 0.0], "city": [0.55, 0.0], "ice": [0.9, 0.0], "volcano": [0.0, 1.0]}


static func ground_mat() -> ShaderMaterial:
	if not _cache.has("ground"):
		var sh := Shader.new()
		sh.code = GROUND_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("sea_y", SEA_Y)
		_cache["ground"] = m
	var lq: Array = LIQUIDS.get(theme, [0.0, 0.0])
	_cache["ground"].set_shader_parameter("water", lq[0])
	_cache["ground"].set_shader_parameter("lava", lq[1])
	return _cache["ground"]


## A glowing unshaded material (shots, lights, engines).
static func glow(c: Color, alpha := 1.0) -> StandardMaterial3D:
	var key := "g%s%s" % [c.to_html(), alpha]
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


## A soft halo round a shot: a camera-facing disc whose colour fades out from the centre. Mixed
## over the ground (not added), so it tints sand, snow or lava with the shot's colour instead of
## washing out; it reads from both cameras.
const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(0.0, 1.0, d);
	ALBEDO = col.rgb;
	ALPHA = col.a * a * (0.6 + 0.4 * a);
}
"""


static func halo_mat(c: Color) -> ShaderMaterial:
	var key := "halo%s" % c.to_html()
	if not _cache.has(key):
		var sh := Shader.new()
		sh.code = HALO_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("col", c)
		_cache[key] = m
	return _cache[key]


static func halo_mesh() -> Mesh:
	return cached("halo", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		return q)


## Enemy fire takes each world's `fire` colour (`THEMES`), picked to stand apart from its ground:
## a white-hot core, a saturated body and a soft halo of the same colour.
const BULLET_CORE := Color8(0xff, 0xfa, 0xe0)
## The ship's shots: cyan with a soft blue halo.
const SHOT_BODY := Color8(0x9c, 0xf6, 0xff)
const SHOT_HALO := Color8(0x2a, 0x6c, 0xff)


static func fire_col() -> Color:
	return THEMES[theme].get("fire", Color8(0xff, 0x24, 0x5e))


## A shot node: `body` mesh of radius `r`, a soft `halo` disc `glow_k` times its size and, if
## `core` > 0, a hot core.
static func shot_node(r: float, body: Color, halo: Color, core := 0.0, glow_k := 3.4, halo_a := 0.75) -> MeshInstance3D:
	var n := instance(shot_mesh(r), glow(body))
	if core > 0.0:
		var c := instance(shot_mesh(core), glow(BULLET_CORE))
		c.name = "core"
		n.add_child(c)
	var h := instance(halo_mesh(), halo_mat(Color(halo, halo_a)))
	h.scale = Vector3.ONE * r * glow_k
	h.name = "halo"
	n.add_child(h)
	return n


static func hash2(x: float, y: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return s - floor(s)


## An irregular outline: n points round a circle of radius r, each pushed in or out.
static func blob(r: float, n: int, seed: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n + seed
		out.append(Vector2(cos(a), sin(a)) * r * (0.72 + 0.5 * hash2(seed * 9.1 + i, i * 1.3)))
	return out

## Baked occlusion (`Builder.ao`): how dark a placed prop gets at its very base, how high (m) the
## darkening reaches, and how tall a part must stand to shade the ground round it.
const AO_BASE := 0.5
const AO_H := 1.4
const AO_TALL := 0.75
const AO_FLAT := 0.15

## Collects coloured triangles from many parts into one flat-shaded mesh.
class Builder:
	var st := SurfaceTool.new()
	var n := 0
	## Where parts go: everything added is moved by this (scenery is built round its own origin,
	## then turned and placed).
	var xf := Transform3D.IDENTITY:
		set(v):
			if ao > 0.0:
				close_spot()
			xf = v
			ao = 0.0
	## Baked ambient occlusion for things standing on the ground (`Models.place` turns it on):
	## vertices darken towards the placement's base over `ao` metres, so walls, trunks and rocks
	## sit in the ground instead of floating on it. Any new `xf` turns it off.
	var ao := 0.0
	## The footprint of each placement with `ao` on, seen from above, where it stands taller than
	## `AO_TALL`: [origin at its base, height, (x, z) min, (x, z) max]. `Models.ao_blobs` turns them
	## into soft dark patches on the ground (`take_spots`).
	var spots: Array = []
	# the open placement's footprint, kept in plain floats (this runs for every vertex)
	var _oy := 0.0
	var _top := 0.0
	var _lx := INF
	var _lz := INF
	var _hx := -INF
	var _hz := -INF
	## False for things that sit on the ground: their bottom faces are never seen.
	var bottoms := true
	## False skips prism's bevelled top edge (small parts, built by the thousand, don't need it).
	var bevels := true

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)

	## Smooth shading for what follows (curved hulls, wings, nacelles), or back to flat facets.
	func smooth(on: bool) -> void:
		st.set_smooth_group(1 if on else 0xFFFFFFFF)

	## Joins rings of points (each the same count, going round the same way) into a smooth skin;
	## `col` gives the colour at a point (a Callable taking the point) or is a Color. `inward`
	## faces it inside (a tunnel). Caps close the first and last rings with flat fans.
	func loft(rings: Array, col: Variant, inward := false, cap0 := false, cap1 := false) -> void:
		var mids: Array[Vector3] = []
		for r: PackedVector3Array in rings:
			var m := Vector3.ZERO
			for q in r:
				m += q
			mids.append(m / maxf(1.0, r.size()))
		var colf: Callable = col if col is Callable else func(_q: Vector3) -> Color: return col
		smooth(true)
		for i in rings.size() - 1:
			var r0: PackedVector3Array = rings[i]
			var r1: PackedVector3Array = rings[i + 1]
			var n := r0.size()
			for k in n:
				var a := r0[k]
				var b := r0[(k + 1) % n]
				var c := r1[(k + 1) % n]
				var d := r1[k]
				var axis := (mids[i + 1] - mids[i]).normalized()
				var o := (a + b + c + d) * 0.25 - (mids[i] + mids[i + 1]) * 0.5
				o -= axis * o.dot(axis)
				if inward:
					o = -o
				tri_cols(a, b, c, colf.call(a), colf.call(b), colf.call(c), o)
				tri_cols(a, c, d, colf.call(a), colf.call(c), colf.call(d), o)
		smooth(false)
		for e in [[cap0, 0, 1], [cap1, rings.size() - 1, rings.size() - 2]]:
			if not e[0]:
				continue
			var r: PackedVector3Array = rings[e[1]]
			var o2: Vector3 = mids[e[1]] - mids[e[2]]
			for k in r.size():
				tri(mids[e[1]], r[k], r[(k + 1) % r.size()], colf.call(r[k]), o2)

	## Starts occlusion for a placement at `xf` (`h`: how high the darkening reaches, metres).
	func occlude(h: float) -> void:
		ao = h
		_oy = xf.origin.y
		_top = 0.0
		_lx = INF
		_lz = INF
		_hx = -INF
		_hz = -INF

	func close_spot() -> void:
		if _lx <= _hx:
			spots.append([Vector3(xf.origin.x, _oy, xf.origin.z), _top, Vector2(_lx, _lz), Vector2(_hx, _hz)])
		_lx = INF
		_hx = -INF

	## The footprints so far (closing the open one).
	func take_spots() -> Array:
		if ao > 0.0:
			close_spot()
			ao = 0.0
		return spots

	func grow(p: Vector3) -> void:
		var up := p.y - _oy
		if up > AO_TALL:
			_lx = minf(_lx, p.x)
			_lz = minf(_lz, p.z)
			_hx = maxf(_hx, p.x)
			_hz = maxf(_hz, p.z)
			_top = maxf(_top, up)

	## Whether a triangle needs darkening: not if it lies flat on the ground (foam rings, paths,
	## garden beds) or stands clear above `ao`. It also grows the footprint.
	func occluded(a: Vector3, b: Vector3, c: Vector3) -> bool:
		grow(a)
		grow(b)
		grow(c)
		var lo := minf(a.y, minf(b.y, c.y)) - _oy
		var hi := maxf(a.y, maxf(b.y, c.y)) - _oy
		return lo < ao and hi > AO_FLAT

	## A vertex colour darkened by how close the (world) point is to its placement's base, less so
	## on faces open to the sky (`open`).
	func shade(p: Vector3, col: Color, open := 0.0) -> Color:
		var k := lerpf(AO_BASE, 1.0, maxf(smoothstep(-0.1, ao, p.y - _oy), open))
		return Color(col.r * k, col.g * k, col.b * k, col.a)

	## How open to the sky a face is (tops of rocks and roofs stay lit; walls darken at the base).
	func sky(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> float:
		var fn := (b - a).cross(c - a)
		if fn.dot(out) < 0.0:
			fn = -fn
		return smoothstep(0.5, 0.95, fn.y / maxf(fn.length(), 1e-9))

	## One triangle; `out` is roughly the direction its front faces.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		a = xf * a
		b = xf * b
		c = xf * c
		out = xf.basis * out
		if (b - a).cross(c - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
		if ao > 0.0 and occluded(a, b, c):
			var o := sky(a, b, c, out)
			st.set_color(shade(a, col, o))
			st.add_vertex(a)
			st.set_color(shade(c, col, o))
			st.add_vertex(c)
			st.set_color(shade(b, col, o))
			st.add_vertex(b)
		else:
			st.set_color(col)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
		n += 3

	## A triangle with a colour per corner.
	func tri_cols(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color, out: Vector3) -> void:
		a = xf * a
		b = xf * b
		c = xf * c
		out = xf.basis * out
		if (b - a).cross(c - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
			var u := cb
			cb = cc
			cc = u
		if ao > 0.0 and occluded(a, b, c):
			var o := sky(a, b, c, out)
			ca = shade(a, ca, o)
			cb = shade(b, cb, o)
			cc = shade(c, cc, o)
		st.set_color(ca)
		st.add_vertex(a)
		st.set_color(cc)
		st.add_vertex(c)
		st.set_color(cb)
		st.add_vertex(b)
		n += 3

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out)
		tri(a, c, d, col, out)

	## A convex outline (x, z) extruded from y0 to y1 around `c`; the top outline is scaled by
	## `top` (tapers) and shifted by `shift` (x, z). Side colour `side` defaults to `col`
	## darkened.
	## Straight extrusions get a small chamfer round the top edge, a lighter band that catches
	## the sun the way machined plating does.
	func prism(c: Vector3, outline: PackedVector2Array, y0: float, y1: float, col: Color,
			top := Vector2.ONE, shift := Vector2.ZERO, side := Color(0, 0, 0, 0)) -> void:
		var sc := col.darkened(0.18) if side.a == 0.0 else side
		var nb := outline.size()
		var bot: Array[Vector3] = []
		var tp: Array[Vector3] = []
		var mid := Vector2.ZERO
		for p in outline:
			mid += p
		mid /= nb
		var minr := INF
		for p in outline:
			minr = minf(minr, (p - mid).length())
		var bev := 0.0
		if bevels and top.x > 0.5 and top.y > 0.5 and y1 - y0 > 0.12 and minr > 0.12:
			bev = minf(minf(0.16, (y1 - y0) * 0.3), minr * 0.22)
		var yb := y1 - bev
		var inset := 1.0 - bev / maxf(minr, 0.001) * 0.9
		var ring: Array[Vector3] = []
		for p in outline:
			bot.append(c + Vector3(p.x, y0, p.y))
			var f := (yb - y0) / (y1 - y0)
			var q := mid + (p - mid) * Vector2.ONE.lerp(top, f) + shift * f
			ring.append(c + Vector3(q.x, yb, q.y))
			var t := mid + (p - mid) * top * (inset if bev > 0.0 else 1.0) + shift
			tp.append(c + Vector3(t.x, y1, t.y))
		var cb := c + Vector3(mid.x, y0, mid.y)
		var ct := c + Vector3(mid.x + shift.x, y1, mid.y + shift.y)
		var edge := col.lightened(0.16)
		for i in nb:
			var j := (i + 1) % nb
			tri(ct, tp[i], tp[j], col, Vector3.UP)
			if bottoms:
				tri(cb, bot[i], bot[j], sc.darkened(0.2), Vector3.DOWN)
			var o := ((bot[i] + bot[j]) * 0.5 - cb)
			o.y = 0.0
			if bev > 0.0:
				quad(bot[i], bot[j], ring[j], ring[i], sc, o)
				quad(ring[i], ring[j], tp[j], tp[i], edge, o + Vector3.UP * o.length())
			else:
				quad(bot[i], bot[j], tp[j], tp[i], sc, o)

	## An axis-aligned box.
	func box(c: Vector3, s: Vector3, col: Color, top := Vector2.ONE) -> void:
		var h := s * 0.5
		prism(Vector3(c.x, 0, c.z), PackedVector2Array([Vector2(-h.x, -h.z), Vector2(h.x, -h.z),
			Vector2(h.x, h.z), Vector2(-h.x, h.z)]), c.y - h.y, c.y + h.y, col, top)

	## A diamond (octahedron) of radius r, squashed by `sc`.
	func octa(c: Vector3, r: float, col: Color, sc := Vector3.ONE) -> void:
		var px := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
		for i in 4:
			var a: Vector3 = c + px[i] * r * sc
			var b: Vector3 = c + px[(i + 1) % 4] * r * sc
			var top := c + Vector3(0, r * sc.y, 0)
			var bot := c - Vector3(0, r * sc.y, 0)
			var o: Vector3 = (px[i] + px[(i + 1) % 4])
			tri(a, b, top, col, o + Vector3.UP)
			tri(a, b, bot, col.darkened(0.25), o + Vector3.DOWN)

	## A Godot primitive placed by `xf`.
	func prim(p: PrimitiveMesh, at: Transform3D, col: Color) -> void:
		var arr := p.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		st.set_color(col)
		for i in idx.size():
			var q := xf * (at * v[idx[i]])
			if ao > 0.0:
				grow(q)
				st.set_color(shade(q, col))
			st.add_vertex(q)
		n += idx.size()

	## When set (`Callable` Color -> Color), every colour goes through it at commit: the city's
	## calming (`City.calm`).
	var tone := Callable()

	func commit() -> ArrayMesh:
		st.generate_normals()
		if not tone.is_valid():
			return st.commit()
		var arr := st.commit_to_arrays()
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		for i in cols.size():
			cols[i] = tone.call(cols[i])
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


## Baked ambient occlusion for a model (ships, foes, bosses, landmarks): the mesh is dropped into
## a coarse grid of cells (`AO_CELLS` along its longest side), then from each vertex a few rays go
## out over its hemisphere; the sooner they hit the model itself, the darker the vertex, down to
## `1 - AO_STRENGTH`. Creases, the feet of turrets and bridges, gun wells and the gaps between
## parts darken; open plating stays as it was. Runs once per cached mesh (`cached`).
const AO_CELLS := 44.0
const AO_STRENGTH := 0.6
const AO_STEPS := [0.8, 1.8, 3.2, 5.5]
## The ray directions round +y (a hemisphere, slightly favouring the normal).
const AO_DIRS := [Vector3(0, 1, 0), Vector3(0.7, 0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0, 0.7, 0.7),
	Vector3(0, 0.7, -0.7), Vector3(0.9, 0.3, 0.3), Vector3(-0.9, 0.3, -0.3), Vector3(0.3, 0.3, -0.9),
	Vector3(-0.3, 0.3, 0.9)]


static func bake_ao(m: Mesh) -> Mesh:
	if not (m is ArrayMesh) or m.get_surface_count() == 0:
		return m
	var aabb := m.get_aabb()
	var cell := maxf(aabb.get_longest_axis_size() / AO_CELLS, 0.02)
	var org := aabb.position - Vector3.ONE * cell * 2.0
	var dim := Vector3i((aabb.size / cell).ceil()) + Vector3i(5, 5, 5)
	var grid := PackedByteArray()
	grid.resize(dim.x * dim.y * dim.z)
	var surfs := []
	for si in m.get_surface_count():
		surfs.append(m.surface_get_arrays(si))
	# the surface, rasterised by sampling each triangle finer than a cell
	for arr: Array in surfs:
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var nt := idx.size() / 3 if idx.size() > 0 else vs.size() / 3
		for t in nt:
			var a := vs[idx[t * 3] if idx.size() > 0 else t * 3]
			var b := vs[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1]
			var c := vs[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2]
			var steps := ceili(maxf((b - a).length(), (c - a).length()) / (cell * 0.7)) + 1
			for i in steps + 1:
				for j in steps + 1 - i:
					var q := a + (b - a) * (float(i) / steps) + (c - a) * (float(j) / steps)
					var g := Vector3i(((q - org) / cell).floor())
					grid[(g.z * dim.y + g.y) * dim.x + g.x] = 1
	var out := ArrayMesh.new()
	for si in surfs.size():
		var arr: Array = surfs[si]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if arr[Mesh.ARRAY_COLOR] == null or ns.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			continue
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var seen := {}
		for v in vs.size():
			var key := Vector3i(((vs[v] - org) / (cell * 0.25)).round()) * 8 + Vector3i((ns[v] * 3.0).round())
			var k: float = seen.get(key, -1.0)
			if k < 0.0:
				k = 1.0 - AO_STRENGTH * occlusion(grid, dim, org, cell, vs[v], ns[v])
				seen[key] = k
			cs[v] = Color(cs[v].r * k, cs[v].g * k, cs[v].b * k, cs[v].a)
		arr[Mesh.ARRAY_COLOR] = cs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mt := m.surface_get_material(si)
		if mt:
			out.surface_set_material(si, mt)
	return out


## How shut in a point is (0 open, 1 buried): the share of rays from it that hit the grid, nearer
## hits counting more.
static func occlusion(grid: PackedByteArray, dim: Vector3i, org: Vector3, cell: float, p: Vector3, n: Vector3) -> float:
	var basis := Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT)
	# looking_at points -z along n: map the table's +y onto n
	var occ := 0.0
	for d: Vector3 in AO_DIRS:
		var dir := (basis * Vector3(d.x, d.z, -d.y)).normalized()
		var w := 1.0
		for st: float in AO_STEPS:
			var g := Vector3i(((p + n * cell * 1.01 + dir * st * cell - org) / cell).floor())
			if g.x < 0 or g.y < 0 or g.z < 0 or g.x >= dim.x or g.y >= dim.y or g.z >= dim.z:
				break
			if grid[(g.z * dim.y + g.y) * dim.x + g.x] == 1:
				occ += w
				break
			w *= 0.75
	return occ / AO_DIRS.size()


static func ngon(r: float, n: int, rot := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := rot + TAU * i / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in a:
		out.append(p)
	return out


static func mirror(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in a:
		out.append(Vector2(-p.x, p.y))
	out.reverse()
	return out


static func instance(m: Mesh, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material if material else mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The hit flash: drawn over a foe for a moment when a shot lands.
static func hit_mat() -> StandardMaterial3D:
	if not _cache.has("hit"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.9, 0.75, 0.32)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_cache["hit"] = m
	return _cache["hit"]


## Shadow casters: plain white, drawn only into the game's shadow mask (see Game.make_shadow_view).
static func shadow_mat() -> StandardMaterial3D:
	if not _cache.has("shadow"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.WHITE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["shadow"] = m
	return _cache["shadow"]


const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 tint : source_color;
uniform float soft = 1.0;

void fragment() {
	// a 13-tap blur of the mask, only to smooth the stair-steps off the edge
	vec2 px = soft / vec2(textureSize(mask, 0));
	float m = texture(mask, SCREEN_UV).r * 0.2;
	m += (texture(mask, SCREEN_UV + vec2(px.x, 0.0)).r + texture(mask, SCREEN_UV - vec2(px.x, 0.0)).r
		+ texture(mask, SCREEN_UV + vec2(0.0, px.y)).r + texture(mask, SCREEN_UV - vec2(0.0, px.y)).r) * 0.1;
	m += (texture(mask, SCREEN_UV + px).r + texture(mask, SCREEN_UV - px).r
		+ texture(mask, SCREEN_UV + vec2(px.x, -px.y)).r + texture(mask, SCREEN_UV + vec2(-px.x, px.y)).r) * 0.06;
	m += (texture(mask, SCREEN_UV + vec2(2.0 * px.x, 0.0)).r + texture(mask, SCREEN_UV - vec2(2.0 * px.x, 0.0)).r
		+ texture(mask, SCREEN_UV + vec2(0.0, 2.0 * px.y)).r + texture(mask, SCREEN_UV - vec2(0.0, 2.0 * px.y)).r) * 0.04;
	if (m < 0.002) {
		discard;
	}
	ALBEDO = tint.rgb;
	// one flat tone inside, only a thin anti-aliased rim: thin wings stay as dark as the body
	ALPHA = tint.a * smoothstep(0.12, 0.5, m);
}
"""


## The ground's shadow plane: a see-through blue-black wherever the blurred mask is set.
static func shadow_plane_mat(mask: Texture2D) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SHADOW_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("mask", mask)
	m.set_shader_parameter("tint", Color(0.02, 0.07, 0.18, 0.34))
	m.render_priority = -1
	return m


static func cached(key: String, f: Callable) -> Mesh:
	if not _cache.has(key):
		var m: Mesh = f.call()
		# every solid model gets its occlusion baked in; glowing things (shots, lights) don't need it
		if not NO_AO.any(func(p: String) -> bool: return key.begins_with(p)):
			m = bake_ao(m)
		_cache[key] = m
	return _cache[key]


## Cached meshes left without baked occlusion: unshaded glows and effects.
const NO_AO := ["halo", "shot", "ring", "scrap", "cap_glow", "cap_lights", "cap_bubble", "contact"]


# ---------------------------------------------------------------- the player's ship
## The Vantage fighter, nose to -z: a slim fuselage, forward-swept canards and swept main
## wings, twin tail fins, a cyan canopy.
static func player() -> Mesh:
	return cached("player", func() -> Mesh:
		var b := Builder.new()
		# fuselage
		b.prism(Vector3.ZERO, pts([Vector2(0, -1.5), Vector2(0.28, -0.7), Vector2(0.34, 0.9),
			Vector2(0.22, 1.25), Vector2(-0.22, 1.25), Vector2(-0.34, 0.9), Vector2(-0.28, -0.7)]),
			-0.18, 0.18, STEEL, Vector2(0.7, 0.92))
		# canopy
		b.prism(Vector3(0, 0.0, -0.35), pts([Vector2(0, -0.55), Vector2(0.17, -0.1), Vector2(0.15, 0.35),
			Vector2(-0.15, 0.35), Vector2(-0.17, -0.1)]), 0.18, 0.36, CYAN, Vector2(0.45, 0.6))
		# main wings (right then left)
		for sx in [1.0, -1.0]:
			var w := [Vector2(0.3, 0.0), Vector2(1.55, 0.75), Vector2(1.55, 1.0), Vector2(0.3, 1.05)]
			var o := PackedVector2Array()
			for p: Vector2 in w:
				o.append(Vector2(p.x * sx, p.y))
			if sx < 0:
				o.reverse()
			b.prism(Vector3.ZERO, o, -0.06, 0.04, STEEL)
			# wing tip stripe
			b.box(Vector3(1.45 * sx, 0.06, 0.88), Vector3(0.2, 0.05, 0.28), CYAN)
			# canard
			var cn := [Vector2(0.25, -0.75), Vector2(0.75, -0.55), Vector2(0.75, -0.42), Vector2(0.25, -0.4)]
			var oc := PackedVector2Array()
			for p: Vector2 in cn:
				oc.append(Vector2(p.x * sx, p.y))
			if sx < 0:
				oc.reverse()
			b.prism(Vector3.ZERO, oc, -0.03, 0.03, STEEL_D)
			# tail fin
			b.prism(Vector3(0.24 * sx, 0, 0), pts([Vector2(-0.03, 0.55), Vector2(0.03, 0.55),
				Vector2(0.03, 1.2), Vector2(-0.03, 1.2)]), 0.1, 0.6, NAVY, Vector2(1, 0.45), Vector2(0, 0.25))
			# engine
			b.box(Vector3(0.16 * sx, -0.05, 1.22), Vector3(0.2, 0.22, 0.18), NAVY)
		return b.commit())


# ---------------------------------------------------------------- foes of the vertical stage
## Small crimson interceptor (nose to +z: towards the player).
static func dart() -> Mesh:
	return cached("dart", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, pts([Vector2(0, 1.0), Vector2(0.9, -0.6), Vector2(0.3, -0.35),
			Vector2(0, -0.7), Vector2(-0.3, -0.35), Vector2(-0.9, -0.6)]), -0.12, 0.12, FOE, Vector2(0.8, 0.8))
		b.prism(Vector3(0, 0, -0.05), ngon(0.22, 5, -PI / 2), 0.12, 0.3, AMBER, Vector2(0.5, 0.5))
		return b.commit())


## Twin-boom weaver.
static func swing() -> Mesh:
	return cached("swing", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, ngon(0.45, 6, PI / 6), -0.2, 0.2, FOE_D, Vector2(0.7, 0.7))
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.65 * sx, 0, 0.1), Vector3(0.22, 0.22, 1.5), FOE, Vector2(0.7, 0.8))
			b.box(Vector3(0.65 * sx, 0, 0.9), Vector3(0.14, 0.14, 0.2), AMBER)
		b.box(Vector3(0, 0, 0), Vector3(1.3, 0.08, 0.35), FOE_D)
		return b.commit())


## Ground flak turret (sits on the ground, y = 0).
static func turret() -> Mesh:
	return cached("turret", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, ngon(1.0, 8, PI / 8), 0.0, 0.45, FOE_D, Vector2(0.85, 0.85))
		b.prism(Vector3.ZERO, ngon(0.6, 6), 0.45, 0.9, FOE, Vector2(0.75, 0.75))
		b.box(Vector3(0, 0.75, 0.65), Vector3(0.18, 0.18, 0.9), HULL_D)
		return b.commit())


## Gunship: a wide armoured hull with four engine pods.
static func heavy() -> Mesh:
	return cached("heavy", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, pts([Vector2(0, 1.7), Vector2(1.1, 1.0), Vector2(2.0, -0.4), Vector2(1.6, -1.2),
			Vector2(-1.6, -1.2), Vector2(-2.0, -0.4), Vector2(-1.1, 1.0)]), -0.3, 0.3, FOE_D, Vector2(0.85, 0.85))
		b.prism(Vector3(0, 0, 0.1), ngon(0.7, 6), 0.3, 0.65, FOE, Vector2(0.6, 0.6))
		for sx in [1.0, -1.0]:
			b.box(Vector3(1.4 * sx, 0, -1.25), Vector3(0.45, 0.4, 0.5), HULL_D)
			b.box(Vector3(0.6 * sx, 0, -1.25), Vector3(0.45, 0.4, 0.5), HULL_D)
			b.box(Vector3(1.0 * sx, 0.32, 0.7), Vector3(0.18, 0.18, 0.8), AMBER)
		return b.commit())


## The sector's guardian, the Bastion: a battleship wider than the screen, nose to +z. The hull
## stays; the bow plating and the wings are separate meshes that break off when their section
## is destroyed. Its guns are separate parts (boss_cannon, boss_battery, boss_bridge, turret).
## The Bastion's outlines seen from above (x, z from the hull's centre, bow towards +z): its
## meshes are built from them and ramming tests the ship against them (Game.boss_rammed).
const BOSS_HULL := [Vector2(0, 5.0), Vector2(2.6, 3.5), Vector2(3.6, -2.0), Vector2(3.2, -10.5),
	Vector2(1.6, -12.0), Vector2(-1.6, -12.0), Vector2(-3.2, -10.5), Vector2(-3.6, -2.0), Vector2(-2.6, 3.5)]
const BOSS_BOW := [Vector2(0, 9.6), Vector2(2.2, 7.0), Vector2(3.4, 2.0), Vector2(-3.4, 2.0), Vector2(-2.2, 7.0)]
const BOSS_WING := [Vector2(3.4, 2.4), Vector2(12.5, -2.2), Vector2(12.5, -4.0), Vector2(3.4, -6.5)]


## One of the Bastion's wings (sx = 1 right, -1 left), wound the same way as the others.
static func boss_wing(sx: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p: Vector2 in BOSS_WING:
		o.append(Vector2(p.x * sx, p.y))
	if sx < 0:
		o.reverse()
	return o


static func boss_hull() -> Mesh:
	return cached("boss_hull", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, pts(BOSS_HULL), -0.9, 0.7, FOE_D, Vector2(0.9, 0.95))
		# raised spine, deck stripes, stern engines
		b.box(Vector3(0, 0.9, -5.5), Vector3(2.4, 0.5, 9.0), HULL_D, Vector2(0.8, 0.95))
		for k in 4:
			b.box(Vector3(0, 0.72, 2.6 - k * 1.6), Vector3(3.6 - k * 0.2, 0.04, 0.3), AMBER)
		for sx in [1.0, -1.0]:
			b.prism(Vector3(sx * 2.0, 0, -12.2), ngon(0.9, 8, PI / 8), -0.6, 0.6, HULL, Vector2(0.85, 0.85))
			b.box(Vector3(sx * 3.3, 0.2, -6.0), Vector3(0.6, 0.9, 6.0), FOE, Vector2(0.7, 0.95))
		return b.commit())


static func boss_bow() -> Mesh:
	return cached("boss_bow", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3(0, 0, 0), pts(BOSS_BOW), -0.6, 1.0, FOE, Vector2(0.85, 0.9))
		b.box(Vector3(0, 1.05, 5.0), Vector3(1.0, 0.1, 5.0), AMBER, Vector2(0.4, 0.9))
		for sx in [1.0, -1.0]:
			b.prism(Vector3(sx * 1.6, 1.0, 6.5), ngon(1.0, 8, PI / 8), 0.0, 0.2, HULL_D)
			b.prism(Vector3(sx * 3.0, 0.7, 3.0), ngon(0.9, 8, PI / 8), 0.0, 0.2, HULL_D)
		return b.commit())


static func boss_wings() -> Mesh:
	return cached("boss_wings", func() -> Mesh:
		var b := Builder.new()
		for sx in [1.0, -1.0]:
			var o := boss_wing(sx)
			b.prism(Vector3.ZERO, o, -0.35, 0.35, FOE, Vector2(0.97, 0.97))
			b.box(Vector3(sx * 12.2, 0.0, -3.1), Vector3(0.7, 1.0, 2.6), HULL_D)
			b.box(Vector3(sx * 9.5, 0.37, -2.0), Vector3(3.5, 0.05, 0.3), AMBER)
			for at in [Vector2(5.4, 0.2), Vector2(7.0, -1.8)]:
				b.prism(Vector3(sx * at.x, 0.35, at.y), ngon(0.9, 8, PI / 8), 0.0, 0.25, HULL_D)
		return b.commit())


## Heavy twin cannon (barrels along +z).
static func boss_cannon() -> Mesh:
	return cached("boss_cannon", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, ngon(0.85, 8, PI / 8), 0.0, 0.6, HULL, Vector2(0.8, 0.8))
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * 0.3, 0.4, 1.0), Vector3(0.22, 0.22, 1.6), HULL_D)
			b.box(Vector3(sx * 0.3, 0.4, 1.85), Vector3(0.28, 0.28, 0.15), AMBER)
		return b.commit())


## Wing battery: a low box with three short barrels.
static func boss_battery() -> Mesh:
	return cached("boss_battery", func() -> Mesh:
		var b := Builder.new()
		b.box(Vector3(0, 0.3, 0), Vector3(1.5, 0.6, 1.3), FOE_D, Vector2(0.8, 0.8))
		for k in 3:
			b.box(Vector3((k - 1) * 0.42, 0.35, 0.95), Vector3(0.16, 0.16, 0.8), HULL)
		b.box(Vector3(0, 0.62, -0.2), Vector3(0.9, 0.05, 0.4), AMBER)
		return b.commit())


## The bridge tower, the boss's heart.
static func boss_bridge() -> Mesh:
	return cached("boss_bridge", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, pts([Vector2(-1.4, -1.6), Vector2(1.4, -1.6), Vector2(1.1, 1.4), Vector2(-1.1, 1.4)]),
			-0.8, 1.2, HULL, Vector2(0.75, 0.8))
		b.box(Vector3(0, 1.0, 1.0), Vector3(1.6, 0.25, 0.1), AMBER)
		b.prism(Vector3(0, 1.2, -0.2), ngon(0.6, 6), 0.0, 0.8, FOE, Vector2(0.6, 0.6))
		b.box(Vector3(0, 2.2, -0.3), Vector3(0.12, 1.2, 0.12), STEEL_D)
		return b.commit())


# ---------------------------------------------------------------- the other mid-bosses
## Every mid-boss (`Rules.MIDBOSSES`) is a hull that stays and a piece per section that breaks
## off; its guns are separate parts (`boss_part`). Nose to +z, decks round y = 0.7..1.2 so the
## parts' mounts sit on them.
const OLIVE := Color8(0x7a, 0x84, 0x4c)
const OLIVE_D := Color8(0x4c, 0x55, 0x34)
const IVORY := Color8(0xd6, 0xd8, 0xd2)
const IVORY_D := Color8(0x8e, 0x96, 0x9a)
const COBALT := Color8(0x2c, 0x4a, 0x7c)
const COBALT_D := Color8(0x1e, 0x2c, 0x48)
const IRON := Color8(0x4a, 0x46, 0x44)
const IRON_D := Color8(0x2e, 0x2a, 0x2a)
const RUST := Color8(0xd0, 0x5c, 0x2a)


static func midboss_hull(id: String) -> Mesh:
	if id == "bastion":
		return boss_hull()
	return cached("mid_%s" % id, func() -> Mesh:
		var b := Builder.new()
		match id:
			"mantis":
				# a long segmented body, a raised carapace, the eye's socket near its tail
				b.prism(Vector3.ZERO, pts([Vector2(0, 6.2), Vector2(1.8, 4.2), Vector2(2.6, -0.8), Vector2(2.2, -5.4),
					Vector2(1.0, -7.2), Vector2(-1.0, -7.2), Vector2(-2.2, -5.4), Vector2(-2.6, -0.8), Vector2(-1.8, 4.2)]),
					-0.8, 0.8, OLIVE_D, Vector2(0.9, 0.95))
				for k in 4:
					b.prism(Vector3(0, 0, 3.0 - k * 2.4), ngon(1.7 - k * 0.12, 6, PI / 6), 0.8, 1.2, OLIVE, Vector2(0.7, 0.7))
				b.prism(Vector3(0, 0, -1.2), ngon(2.0, 10), 0.8, 1.0, HULL_D)
				b.prism(Vector3(0, 0, 4.6), ngon(1.0, 8, PI / 8), 0.8, 1.3, HULL_D)
				for sx in [1.0, -1.0]:
					b.box(Vector3(sx * 2.3, 0.3, -2.0), Vector3(0.4, 0.8, 5.0), AMBER, Vector2(0.6, 0.95))
					b.prism(Vector3(sx * 1.0, 0, -7.0), ngon(0.7, 8, PI / 8), -0.5, 0.5, HULL)
			"halo":
				# a hub with an inner ring round it
				b.prism(Vector3.ZERO, ngon(2.4, 12), -0.9, 1.2, IVORY_D, Vector2(0.85, 0.85))
				b.prism(Vector3.ZERO, ngon(1.7, 12), 1.2, 1.5, IVORY)
				ring(b, 3.8, 4.6, 16, -0.5, 0.8, IVORY)
				for k in 16:
					var a := TAU * (k + 0.5) / 16.0
					b.box(Vector3(sin(a) * 4.2, 0.82, cos(a) * 4.2), Vector3(0.2, 0.06, 0.2), CYAN)
			"twin":
				# the keel between the hulls, the bridge's base at its stern
				b.prism(Vector3.ZERO, pts([Vector2(0, 2.8), Vector2(1.6, 1.4), Vector2(1.6, -5.6), Vector2(0.8, -6.6),
					Vector2(-0.8, -6.6), Vector2(-1.6, -5.6), Vector2(-1.6, 1.4)]), -0.7, 0.8, COBALT_D, Vector2(0.9, 0.95))
				b.box(Vector3(0, 0.9, -2.4), Vector3(2.6, 0.3, 3.4), HULL_D)
				for k in 3:
					b.box(Vector3(0, 0.82, 1.4 - k * 2.6), Vector3(2.4, 0.04, 0.24), AMBER)
			"hammer":
				# a thick body, the heart's armoured cradle near its stern
				b.prism(Vector3.ZERO, pts(HAMMER_BODY), -0.9, 0.9, IRON, Vector2(0.9, 0.95))
				b.prism(Vector3(0, 0, -3.0), ngon(2.0, 8, PI / 8), 0.9, 1.2, IRON_D)
				for sx in [1.0, -1.0]:
					b.prism(Vector3(sx * 1.2, 0, -6.6), ngon(0.8, 8, PI / 8), -0.6, 0.6, HULL)
					b.box(Vector3(sx * 2.5, 0.4, 0.0), Vector3(0.3, 0.6, 8.0), RUST, Vector2(0.6, 0.95))
		return b.commit())


static func midboss_piece(id: String, piece: String) -> Mesh:
	if id == "bastion":
		return boss_bow() if piece == "bow" else boss_wings()
	return cached("mid_%s_%s" % [id, piece], func() -> Mesh:
		var b := Builder.new()
		var parts: Array = []
		for sec: Dictionary in Rules.MIDBOSSES[id].sections:
			if sec.piece == piece:
				parts = sec.parts
		match [id, piece]:
			["mantis", "claws"]:
				for sx in [1.0, -1.0]:
					slab(b, Vector2(sx * 2.2, 1.2), Vector2(sx * 4.4, 2.6), 1.4, -0.4, 0.7, OLIVE)
					slab(b, Vector2(sx * 4.4, 2.6), Vector2(sx * 5.0, 7.6), 1.6, -0.4, 0.8, OLIVE)
					slab(b, Vector2(sx * 5.2, 7.4), Vector2(sx * 3.0, 9.6), 1.0, -0.3, 0.6, AMBER)
					b.prism(Vector3(sx * 4.4, 0, 2.6), ngon(1.0, 8, PI / 8), -0.5, 0.75, OLIVE_D)
			["mantis", "pods"]:
				for sx in [1.0, -1.0]:
					slab(b, Vector2(sx * 2.3, -2.0), Vector2(sx * 5.6, -2.2), 1.0, -0.2, 0.5, OLIVE_D)
					slab(b, Vector2(sx * 6.2, 0.6), Vector2(sx * 6.2, -5.6), 1.9, -0.6, 0.8, OLIVE)
					b.box(Vector3(sx * 6.2, 0.1, -5.7), Vector3(1.2, 0.8, 0.3), AMBER)
			["halo", "rim"]:
				ring(b, 4.6, 6.2, 24, -0.4, 0.6, IVORY_D)
				for k in 24:
					if k % 2 == 0:
						var a := TAU * k / 24.0
						b.box(Vector3(sin(a) * 6.1, 0.3, cos(a) * 6.1), Vector3(0.3, 0.5, 0.3), CYAN)
			["halo", "spokes"]:
				for p: Dictionary in parts:
					var at := Vector2(p.at.x, p.at.z)
					slab(b, at.normalized() * 2.2, at.normalized() * 4.0, 1.2, 0.0, 1.0, IVORY)
			["twin", "port"], ["twin", "starboard"]:
				var sx := -1.0 if piece == "port" else 1.0
				var c := Vector3(sx * 4.6, 0, 0)
				b.prism(c, pts(TWIN_HULL), -0.9, 0.8, COBALT, Vector2(0.88, 0.95))
				b.box(c + Vector3(0, 0.82, 1.0), Vector3(0.4, 0.06, 9.0), FOE)
				# the beams joining it to the keel
				for z in [3.4, -3.8]:
					b.box(Vector3(sx * 2.4, 0.3, z), Vector3(2.4, 0.6, 1.0), COBALT_D)
			["twin", "deck"]:
				b.prism(Vector3(0, 0, 2.2), pts(TWIN_DECK), 0.0, 1.0, COBALT, Vector2(0.9, 0.9))
				b.box(Vector3(0, 1.02, 4.0), Vector3(2.0, 0.05, 0.24), AMBER)
			["hammer", "hammer"]:
				b.prism(Vector3(0, 0, 6.6), pts(HAMMER_BAR), -0.7, 0.8, IRON, Vector2(0.97, 0.9))
				b.box(Vector3(0, 0.82, 7.9), Vector3(12.0, 0.06, 0.3), RUST)
				for sx in [1.0, -1.0]:
					b.box(Vector3(sx * 7.4, 0.0, 6.4), Vector3(0.5, 1.2, 2.6), HULL_D)
			["hammer", "fins"]:
				for sx in [1.0, -1.0]:
					b.prism(Vector3.ZERO, pts([Vector2(sx * 2.2, 2.4), Vector2(sx * 5.8, -1.6), Vector2(sx * 5.4, -3.0),
						Vector2(sx * 2.2, -1.2)]) if sx < 0 else pts([Vector2(sx * 2.2, -1.2), Vector2(sx * 5.4, -3.0),
						Vector2(sx * 5.8, -1.6), Vector2(sx * 2.2, 2.4)]), -0.3, 0.6, IRON_D, Vector2(0.97, 0.97))
					b.box(Vector3(sx * 4.0, 0.62, -1.0), Vector3(2.2, 0.05, 0.22), RUST)
				b.prism(Vector3(0, 0, 2.2), ngon(1.3, 8, PI / 8), 0.9, 1.3, IRON_D)
		# a platform under each of the section's guns
		for p: Dictionary in parts:
			b.prism(Vector3(p.at.x, 0, p.at.z), ngon(0.95, 8, PI / 8), p.at.y - 0.4, p.at.y - 0.15, HULL_D)
		return b.commit())


## A mid-boss's outlines seen from above (x, z from the hull's centre, bow towards +z), by the
## piece they belong to ("" for the hull, which stays): ramming tests the ship against the hull
## and the pieces still on (`Game.boss_rammed`).
static var _shapes := {}


static func midboss_shapes(id: String) -> Dictionary:
	if _shapes.has(id):
		return _shapes[id]
	var out := {}
	match id:
		"bastion":
			out = {"": [pts(BOSS_HULL)], "bow": [pts(BOSS_BOW)], "wings": [boss_wing(1.0), boss_wing(-1.0)]}
		"mantis":
			out = {"": [pts([Vector2(0, 6.2), Vector2(1.8, 4.2), Vector2(2.6, -0.8), Vector2(2.2, -5.4), Vector2(1.0, -7.2),
				Vector2(-1.0, -7.2), Vector2(-2.2, -5.4), Vector2(-2.6, -0.8), Vector2(-1.8, 4.2)])], "claws": [], "pods": []}
			for sx in [1.0, -1.0]:
				out.claws.append(slab_poly(Vector2(sx * 2.2, 1.2), Vector2(sx * 4.4, 2.6), 1.4))
				out.claws.append(slab_poly(Vector2(sx * 4.4, 2.6), Vector2(sx * 5.0, 7.6), 1.6))
				out.claws.append(slab_poly(Vector2(sx * 5.2, 7.4), Vector2(sx * 3.0, 9.6), 1.0))
				out.pods.append(slab_poly(Vector2(sx * 2.3, -2.0), Vector2(sx * 5.6, -2.2), 1.0))
				out.pods.append(slab_poly(Vector2(sx * 6.2, 0.6), Vector2(sx * 6.2, -5.6), 1.9))
		"halo":
			out = {"": [ngon(4.6, 16)], "rim": [ngon(6.2, 24)]}
		"twin":
			out = {"": [pts([Vector2(0, 2.8), Vector2(1.6, 1.4), Vector2(1.6, -5.6), Vector2(0.8, -6.6), Vector2(-0.8, -6.6),
				Vector2(-1.6, -5.6), Vector2(-1.6, 1.4)])], "deck": [shifted(TWIN_DECK, Vector2(0, 2.2))]}
			for side in ["port", "starboard"]:
				var sx := -1.0 if side == "port" else 1.0
				out[side] = [shifted(TWIN_HULL, Vector2(sx * 4.6, 0))]
				for z in [3.4, -3.8]:
					out[side].append(slab_poly(Vector2(sx * 1.2, z), Vector2(sx * 3.6, z), 1.0))
		"hammer":
			out = {"": [pts(HAMMER_BODY)], "hammer": [shifted(HAMMER_BAR, Vector2(0, 6.6))], "fins": []}
			for sx in [1.0, -1.0]:
				out.fins.append(pts([Vector2(sx * 2.2, 2.4), Vector2(sx * 5.8, -1.6), Vector2(sx * 5.4, -3.0), Vector2(sx * 2.2, -1.2)]))
	_shapes[id] = out
	return out


const TWIN_HULL := [Vector2(0, 8.4), Vector2(1.6, 5.6), Vector2(1.7, -5.0), Vector2(1.0, -6.6),
	Vector2(-1.0, -6.6), Vector2(-1.7, -5.0), Vector2(-1.6, 5.6)]
const TWIN_DECK := [Vector2(0, 2.8), Vector2(2.8, 1.2), Vector2(2.8, -1.4), Vector2(-2.8, -1.4), Vector2(-2.8, 1.2)]
const HAMMER_BODY := [Vector2(2.2, 5.4), Vector2(2.6, 1.0), Vector2(2.4, -5.0), Vector2(1.4, -6.6),
	Vector2(-1.4, -6.6), Vector2(-2.4, -5.0), Vector2(-2.6, 1.0), Vector2(-2.2, 5.4)]
const HAMMER_BAR := [Vector2(-7.4, -1.2), Vector2(7.4, -1.2), Vector2(7.6, 0.6), Vector2(6.8, 1.6),
	Vector2(-6.8, 1.6), Vector2(-7.6, 0.6)]


static func shifted(a: Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in a:
		out.append(p + by)
	return out


## The outline of a slab from a to b `w` wide (x, z).
static func slab_poly(from: Vector2, to: Vector2, w: float) -> PackedVector2Array:
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x) * w * 0.5
	return pts([from + n, to + n, to - n, from - n])


## A convex slab from a to b (x, z) `w` wide, from y0 to y1: arms, beams, struts.
static func slab(b: Builder, from: Vector2, to: Vector2, w: float, y0: float, y1: float, col: Color) -> void:
	var o := slab_poly(from, to, w)
	# the outline must wind the same way as every other prism's (anticlockwise seen from above)
	if (o[1] - o[0]).cross(o[2] - o[1]) < 0.0:
		o.reverse()
	b.prism(Vector3.ZERO, o, y0, y1, col)


## A flat ring from radius r0 to r1 in n segments.
static func ring(b: Builder, r0: float, r1: float, n: int, y0: float, y1: float, col: Color) -> void:
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var o := pts([Vector2(sin(a0), cos(a0)) * r0, Vector2(sin(a0), cos(a0)) * r1,
			Vector2(sin(a1), cos(a1)) * r1, Vector2(sin(a1), cos(a1)) * r0])
		if (o[1] - o[0]).cross(o[2] - o[1]) < 0.0:
			o.reverse()
		b.prism(Vector3.ZERO, o, y0, y1, col)


## A mid-boss's gun, by kind (barrels along +z, turned to the player).
static func boss_part(kind: String) -> Mesh:
	match kind:
		"cannon":
			return boss_cannon()
		"flak":
			return turret()
		"battery":
			return boss_battery()
		"bridge":
			return boss_bridge()
	return cached("part_" + kind, func() -> Mesh:
		var b := Builder.new()
		match kind:
			"lance":
				# one long barrel on a sloped mantlet
				b.prism(Vector3.ZERO, ngon(0.8, 8, PI / 8), 0.0, 0.5, HULL, Vector2(0.75, 0.75))
				b.box(Vector3(0, 0.6, -0.1), Vector3(0.9, 0.4, 1.0), FOE_D, Vector2(0.7, 0.8))
				b.box(Vector3(0, 0.6, 1.3), Vector3(0.26, 0.26, 2.2), HULL_D)
				b.box(Vector3(0, 0.6, 2.45), Vector3(0.34, 0.34, 0.16), AMBER)
			"spiral":
				# a squat drum with four short barrels round it
				b.prism(Vector3.ZERO, ngon(0.95, 8, PI / 8), 0.0, 0.7, HULL_D, Vector2(0.85, 0.85))
				for k in 4:
					var a := TAU * k / 4.0
					b.box(Vector3(sin(a) * 0.95, 0.4, cos(a) * 0.95), Vector3(0.3 + absf(cos(a)) * 0.0, 0.24, 0.3) + Vector3(absf(sin(a)), 0, absf(cos(a))) * 0.6, HULL)
				b.prism(Vector3(0, 0.7, 0), ngon(0.45, 8), 0.0, 0.2, AMBER)
			"dome":
				# the heart: a stepped armoured dome with a glowing eye band
				b.prism(Vector3.ZERO, ngon(2.0, 10), -0.4, 0.4, HULL_D, Vector2(0.9, 0.9))
				b.prism(Vector3(0, 0.4, 0), ngon(1.75, 10), 0.0, 0.35, FOE)
				b.prism(Vector3(0, 0.75, 0), ngon(1.6, 10), 0.0, 0.5, FOE_D, Vector2(0.75, 0.75))
				b.prism(Vector3(0, 1.25, 0), ngon(1.15, 10), 0.0, 0.4, FOE, Vector2(0.5, 0.5))
				for k in 10:
					var a := TAU * (k + 0.5) / 10.0
					b.box(Vector3(sin(a) * 1.74, 0.58, cos(a) * 1.74), Vector3(0.36, 0.14, 0.36), AMBER)
		return b.commit())


# ---------------------------------------------------------------- foes inside the fortress
## Security drone: a diamond with four fins and an amber eye facing the player (+z).
static func drone() -> Mesh:
	return cached("drone", func() -> Mesh:
		var b := Builder.new()
		b.octa(Vector3.ZERO, 0.7, FOE_D, Vector3(1, 0.8, 1))
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4
			var d := Vector3(cos(a), sin(a), 0)
			b.box(d * 0.75, Vector3(0.12 + abs(d.x) * 0.4, 0.12 + abs(d.y) * 0.4, 0.5), FOE)
		b.prism(Vector3(0, 0, 0.5), ngon(0.22, 6), -0.22, 0.22, AMBER)
		return b.commit())


## Wall sentry gun (barrel along +z, the base against a wall along -x).
static func sentry() -> Mesh:
	return cached("sentry", func() -> Mesh:
		var b := Builder.new()
		b.box(Vector3(-0.3, 0, 0), Vector3(0.6, 1.4, 1.4), HULL_D)
		b.octa(Vector3(0.15, 0, 0), 0.55, FOE)
		b.box(Vector3(0.3, 0, 0.6), Vector3(0.2, 0.2, 1.1), FOE_D)
		b.box(Vector3(0.3, 0, 1.15), Vector3(0.24, 0.24, 0.1), AMBER)
		return b.commit())


## A shield panel of the reactor.
static func panel() -> Mesh:
	return cached("panel", func() -> Mesh:
		var b := Builder.new()
		b.box(Vector3.ZERO, Vector3(1.5, 0.3, 1.5), FOE_D)
		b.box(Vector3(0, 0.17, 0), Vector3(1.0, 0.06, 1.0), FOE)
		return b.commit())


# ---------------------------------------------------------------- the fortress
## The capital ships (`Rules.FORTRESSES`) are built in `Capital` (capital.gd); these are their
## paints and the lofting helpers they share.
const ARMOUR := Color8(0x4e, 0x56, 0x62)
const GLASS_D := Color8(0x1c, 0x2a, 0x3c)
## Each paint: deck and upper hull, the flanks and belly, and the darker trim.
const PAINTS := {
	"steel": [Color8(0x7a, 0x82, 0x8e), Color8(0x55, 0x5d, 0x69), Color8(0x33, 0x38, 0x41)],
	"ivory": [Color8(0xe2, 0xe0, 0xd6), Color8(0x9e, 0xa4, 0xa6), Color8(0x4a, 0x50, 0x56)],
	"iron": [Color8(0x4c, 0x4a, 0x4c), Color8(0x34, 0x32, 0x34), Color8(0x1e, 0x1c, 0x1e)],
	"olive": [Color8(0x86, 0x8e, 0x58), Color8(0x5a, 0x62, 0x3c), Color8(0x36, 0x3a, 0x26)],
	"cobalt": [Color8(0x3a, 0x5a, 0x8e), Color8(0x26, 0x38, 0x5c), Color8(0x16, 0x20, 0x34)],
	"pearl": [Color8(0xd8, 0xe2, 0xea), Color8(0xa8, 0xb8, 0xc6), Color8(0x4c, 0x5a, 0x68)],
	"teal": [Color8(0x4e, 0x8c, 0x90), Color8(0x2e, 0x5e, 0x66), Color8(0x1a, 0x34, 0x3a)],
	"sand": [Color8(0xc8, 0xa8, 0x78), Color8(0x8e, 0x6c, 0x48), Color8(0x4a, 0x36, 0x26)],
	"bronze": [Color8(0x9a, 0x7a, 0x4a), Color8(0x5e, 0x4c, 0x36), Color8(0x2e, 0x26, 0x1e)],
	"graphite": [Color8(0x5e, 0x62, 0x6a), Color8(0x3c, 0x40, 0x48), Color8(0x22, 0x24, 0x2a)],
	"crimson": [Color8(0x9a, 0x3c, 0x3a), Color8(0x62, 0x26, 0x28), Color8(0x2e, 0x16, 0x18)],
	"frost": [Color8(0xe6, 0xf0, 0xf6), Color8(0x9c, 0xb6, 0xcc), Color8(0x4a, 0x5e, 0x74)],
	"violet": [Color8(0x6a, 0x5a, 0x9a), Color8(0x44, 0x3a, 0x6a), Color8(0x24, 0x1e, 0x3a)],
	"basalt": [Color8(0x48, 0x42, 0x40), Color8(0x30, 0x2a, 0x2a), Color8(0x18, 0x14, 0x14)],
}
const HULL_N := 32
const WING_N := 14


static func fort(id: String) -> Dictionary:
	return Rules.FORTRESSES[id]


static func paint(id: String) -> Array:
	return PAINTS[fort(id).paint]


## Extrudes the outline (x, y) along -z, from z = -z0 to z = -z1 round `c`, the far end scaled
## by `top` and shifted (x, y) by `shift`.
static func along_z(b: Builder, c: Vector3, outline: PackedVector2Array, z0: float, z1: float, col: Color,
		top := Vector2.ONE, shift := Vector2.ZERO) -> void:
	if z1 < z0 and top == Vector2.ONE and shift == Vector2.ZERO:
		var t := z0
		z0 = z1
		z1 = t
	var keep := b.xf
	b.xf = keep * Transform3D(Basis(Vector3.RIGHT, -PI / 2), c)
	b.prism(Vector3.ZERO, outline, z0, z1, col, top, shift)
	b.xf = keep


## A superellipse's point at angle a (unit size): exponent p, 2 an ellipse, higher squarer.
static func squircle(a: float, p: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	return Vector2(signf(c) * pow(absf(c), 2.0 / p), signf(s) * pow(absf(s), 2.0 / p))


## A ring of n points round c in the plane of u and v (their lengths are the radii).
static func oval(c: Vector3, u: Vector3, v: Vector3, p: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in n:
		var q := squircle(TAU * k / n, p)
		out.append(c + u * q.x + v * q.y)
	return out


## The part of a convex outline where p . n >= d (Sutherland-Hodgman against one line).
static func clip(o: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in o.size():
		var a := o[i]
		var c := o[(i + 1) % o.size()]
		var ia := a.dot(n) >= d
		var ic := c.dot(n) >= d
		if ia:
			out.append(a)
		if ia != ic:
			var t := (d - a.dot(n)) / (c - a).dot(n)
			out.append(a + (c - a) * t)
	return out


static func inset(o: PackedVector2Array, k: float) -> PackedVector2Array:
	var mid := Vector2.ZERO
	for p in o:
		mid += p
	mid /= maxf(1.0, o.size())
	var out := PackedVector2Array()
	for p in o:
		out.append(mid + (p - mid) * k)
	return out


## A smooth gun dome with `n` barrels pointing along `dir` (+z aft, the way the chase sees them).
static func gun_dome(b: Builder, at: Vector3, r: float, n: int, dir := 1.0, col := HULL_D) -> void:
	var rings: Array = []
	for k in 5:
		var a := PI * 0.5 * k / 4.0
		rings.append(oval(at + Vector3(0, sin(a) * r * 0.75, 0), Vector3(cos(a) * r + 0.01, 0, 0), Vector3(0, 0, cos(a) * r * 1.1 + 0.01), 2.0, 12))
	b.loft(rings, col, false, true, true)
	for k in n:
		var x := (k - (n - 1) * 0.5) * r * 0.5
		var c := at + Vector3(x, r * 0.4, 0)
		b.loft([oval(c, Vector3(r * 0.12, 0, 0), Vector3(0, r * 0.12, 0), 2.0, 8),
			oval(c + Vector3(0, 0, r * 2.4 * dir), Vector3(r * 0.1, 0, 0), Vector3(0, r * 0.1, 0), 2.0, 8)], STEEL_D, false, false, true)


## A capsule standing up from y0 to y1 at (x, z): gun pods on the stern.
static func capsule_y(b: Builder, x: float, z: float, y0: float, y1: float, rx: float, rz: float, col: Variant) -> void:
	var rings: Array = []
	for k in 4:
		var a := PI * 0.5 * (3 - k) / 3.0
		rings.append(oval(Vector3(x, y0 + rx * (1.0 - cos(a)) - rx + rx, z), Vector3(sin(a) * rx + 0.01, 0, 0), Vector3(0, 0, sin(a) * rz + 0.01), 2.0, 12))
	rings[0] = oval(Vector3(x, y0, z), Vector3(0.02, 0, 0), Vector3(0, 0, 0.02), 2.0, 12)
	for k in 4:
		var a := PI * 0.5 * k / 3.0
		rings.append(oval(Vector3(x, y1 - rx + sin(a) * rx, z), Vector3(cos(a) * rx + 0.01, 0, 0), Vector3(0, 0, cos(a) * rz + 0.01), 2.0, 12))
	b.loft(rings, col)


## A tapered airfoil from `root` along `span` (a vector: its length and direction, sweep and rise
## included), chord c0 at the root to c1 at a rounded tip; `thick` scales its thickness and `up`
## is the side its thickness grows towards. Wings, tailplanes and fins.
static func airfoil(b: Builder, root: Vector3, span: Vector3, c0: float, c1: float, thick: float, up: Vector3,
		col: Color, tip_col := Color(0, 0, 0, 0)) -> void:
	var rings: Array = []
	var ts := [0.0, 0.25, 0.5, 0.75, 0.92, 1.0]
	var dir := Vector3(span.x, span.y, 0).normalized() if absf(span.x) + absf(span.y) > 0.01 else Vector3.RIGHT
	for t: float in ts:
		var ch := lerpf(c0, c1, t) * (0.55 if t == 1.0 else 1.0)
		var th := ch * 0.12 * thick * (0.5 if t == 1.0 else 1.0)
		var c := root + span * t - dir * (0.0 if t < 1.0 else 0.0)
		var pts3 := PackedVector3Array()
		for k in WING_N:
			var a := TAU * k / WING_N
			var z := -cos(a) * ch * 0.5
			var yy := sin(a) * th * 0.5 * (0.7 + 0.3 * cos(a))
			pts3.append(c + Vector3(0, 0, z) + up * yy)
		rings.append(pts3)
	var tipc := tip_col if tip_col.a > 0.0 else col
	b.loft(rings, func(q: Vector3) -> Color: return tipc if (q - root).dot(dir) > span.length() * 0.9 else col, false, true, true)


# ---------------------------------------------------------------- terrain
## One chunk of ground, `size.y` long from z0 towards -z, `size.x` wide: a low poly coast of
## sea, sand, grass and woods from a seeded noise, so chunks join seamlessly.
## The colour of the ground at noise height h, blended across bands so coasts and tree lines
## grade softly instead of stepping cell by cell.
## The terrain theme of the current world (`Campaign.WORLDS`): "coast", "dunes", "city", "ice"
## or "volcano". `ground_chunk` colours the land and picks its props by it.
static var theme := "coast"
## Where the sun throws a shadow: a point h above the ground shades the ground h * sun_slide
## away (x, z). Game sets it from its sun; this is the same sun's.
static var sun_slide := Vector2(0.4016, -0.5736)

## Each theme's sky (top, middle, horizon, below), fog, ambient light and sun.
const THEMES := {
	"coast": {"sky": [Color(0.24, 0.50, 0.80), Color(0.48, 0.74, 0.92), Color(0.86, 0.92, 0.94), Color(0.62, 0.78, 0.88)],
		"fog": Color8(0xc4, 0xde, 0xee), "ambient": Color8(0xb4, 0xcc, 0xe8), "fire": Color8(0xff, 0x24, 0x5e), "sun": Color8(0xff, 0xef, 0xd6)},
	"dunes": {"sky": [Color(0.36, 0.56, 0.80), Color(0.66, 0.78, 0.88), Color(0.96, 0.88, 0.74), Color(0.86, 0.74, 0.58)],
		"fog": Color8(0xf0, 0xdc, 0xbc), "ambient": Color8(0xe0, 0xcc, 0xb0), "fire": Color8(0x8a, 0x2c, 0xff), "sun": Color8(0xff, 0xe6, 0xc0), "lift": 0.45},
	# a city at war: a sky of smoke, lit orange low down by the fires; magenta shots stand out from the flames
	"city": {"sky": [Color(0.12, 0.12, 0.13), Color(0.24, 0.23, 0.23), Color(0.46, 0.32, 0.24), Color(0.20, 0.19, 0.19)],
		"fog": Color8(0x48, 0x46, 0x46), "ambient": Color8(0x94, 0x94, 0x98), "fire": Color8(0xff, 0x2c, 0xe0), "sun": Color8(0xd0, 0xc0, 0xb4), "lift": 0.35},
	"ice": {"sky": [Color(0.40, 0.58, 0.82), Color(0.66, 0.80, 0.92), Color(0.92, 0.95, 0.98), Color(0.74, 0.84, 0.92)],
		"fog": Color8(0xe2, 0xee, 0xf6), "ambient": Color8(0xc4, 0xd8, 0xf0), "fire": Color8(0xff, 0x3a, 0x1a), "sun": Color8(0xf4, 0xf6, 0xff), "lift": 0.3},
	"volcano": {"sky": [Color(0.22, 0.18, 0.26), Color(0.50, 0.32, 0.30), Color(0.86, 0.52, 0.34), Color(0.40, 0.24, 0.20)],
		"fog": Color8(0x8c, 0x5c, 0x4c), "ambient": Color8(0xc8, 0x9c, 0x88), "fire": Color8(0xd8, 0x3c, 0xff), "sun": Color8(0xff, 0xc8, 0x90), "lift": 0.45},
}


## How far the theme raises the land out of the water (the coast keeps its sea; the dunes are
## nearly all land, with the odd dry wash).
static func lift() -> float:
	return float(THEMES[theme].get("lift", 0.0))


## The water's height under the terrain cell being dressed (a lowered sea sits far below -0.4).
static var sea_y := -0.4


## Bare rock on steep faces, by world, a little darker deeper down (the ground shader adds strata).
static func rock_col(y: float) -> Color:
	var c: Color = {"coast": Color8(0xd8, 0xcc, 0xb0), "dunes": Color8(0xc4, 0x66, 0x3e), "ice": Color8(0xa4, 0xd2, 0xea),
		"volcano": Color8(0x3e, 0x34, 0x36), "city": Color8(0x6a, 0x66, 0x62)}.get(theme, ROCK)
	return c.darkened(clampf(-y * 0.025, 0.0, 0.25))


static func ground_col(h: float) -> Color:
	match theme:
		"dunes":
			if h < 0.0:   # dry washes and salt pans
				return Color8(0xc4, 0xa2, 0x70).lerp(Color8(0xe6, 0xd6, 0xb4), smoothstep(-0.1, -0.4, h))
			var d := Color8(0xee, 0xd0, 0x92).lerp(Color8(0xe0, 0xa8, 0x66), smoothstep(0.3, 0.5, h))
			return d.lerp(Color8(0xb4, 0x62, 0x40), smoothstep(0.74, 0.8, h))
		"city":
			if h < 0.0:   # canals
				return Color8(0x3a, 0x48, 0x4c).lerp(Color8(0x4e, 0x4e, 0x4e), smoothstep(-0.06, 0.0, h))
			# scorched banks along the canals, ash-grey concrete under the blocks (City paves the rest)
			return Color8(0x44, 0x40, 0x36).lerp(Color8(0x56, 0x56, 0x58), smoothstep(0.1, 0.16, h))
		"ice":
			if h < 0.0:   # cold sea, pale where the shelf meets it
				return Color8(0x1c, 0x3e, 0x60).lerp(Color8(0x6e, 0xae, 0xcc), smoothstep(-0.12, 0.0, h) * 0.8)
			var c := Color8(0xd6, 0xea, 0xf4).lerp(Color8(0xf6, 0xfa, 0xfd), smoothstep(0.08, 0.14, h))
			return c.lerp(Color8(0xb4, 0xce, 0xe2), smoothstep(0.7, 0.76, h))   # glacier ice on the heights
		"volcano":
			if h < 0.0:   # lava, a dark crust at its edge
				return Color8(0xf0, 0x6a, 0x1e).lerp(Color8(0x50, 0x26, 0x1e), smoothstep(-0.1, 0.0, h))
			# basalt, ash, then dark rusty rock on the heights (never as bright as the lava)
			var c := Color8(0x4a, 0x42, 0x42).lerp(Color8(0x74, 0x6c, 0x68), smoothstep(0.35, 0.5, h))
			return c.lerp(Color8(0x5e, 0x44, 0x3e), smoothstep(0.72, 0.78, h))
	if h < 0.0:
		# deep blue out at sea, turquoise shallows along the coast
		return SEA.lerp(SEA_D, smoothstep(-0.08, -0.5, h)).lerp(Color8(0x3f, 0xa6, 0xb4), smoothstep(-0.1, 0.0, h) * 0.75)
	var c := SAND.lerp(GRASS, smoothstep(0.05, 0.09, h))
	c = c.lerp(FOREST, smoothstep(0.3, 0.34, h))
	return c.lerp(ROCK, smoothstep(0.5, 0.56, h))


## The x of each column of ground vertices: `core` wide at `cell` spacing around the centre line,
## then `flank` more on each side in ever wider cells, so the land runs out past the fog (the chase
## camera looks far across it) for few extra triangles. Every chunk uses the same columns.
static func ground_cols(core: float, cell: float, flank: float) -> PackedFloat32Array:
	var n := roundi(core / cell)
	var right := PackedFloat32Array()
	for i in n / 2 + 1:
		right.append(i * core / n)
	var x := core * 0.5
	var step := cell * 1.5
	while x < core * 0.5 + flank - 0.01:
		x = minf(x + step, core * 0.5 + flank)
		right.append(x)
		step *= 1.22
	var cols := PackedFloat32Array()
	for i in range(right.size() - 1, 0, -1):
		cols.append(-right[i])
	cols.append_array(right)
	return cols


## How deep in the land's own shadow the ground at p lies, 0 (in the sun) to 1: the ground
## between p and the sun stands above the sun's ray through p. Soft at the shadow's edge.
const SUN_STEPS := [1.0, 2.2, 3.6, 5.2, 7.2]
const SHADE := 0.55
## The highest the land rises (the plain's top, `Relief.base_y`).
const LAND_TOP := 1.3


static func sun_shade(ground_h: Callable, p: Vector3) -> float:
	var l := sun_slide.length()
	if l < 0.01:
		return 0.0
	var to_sun := -sun_slide / l
	var worst := 0.0
	for s: float in SUN_STEPS:
		# the land never rises past LAND_TOP, so past where the ray clears it nothing can shade p
		# (and most of the land, near the plain, is never tested at all)
		if p.y + s / l > LAND_TOP + 0.7:
			break
		var q := Vector2(p.x, p.z) + to_sun * s
		var above: float = float(ground_h.call(q.x, q.y)) - (p.y + s / l)
		worst = maxf(worst, above)
	return smoothstep(0.0, 0.45, worst)


## A colour in the land's shadow: darker and a little cooler (lit by the sky, not the sun).
static func shade_col(c: Color) -> Color:
	return Color(c.r * (1.0 - SHADE) * 0.94, c.g * (1.0 - SHADE) * 0.97, c.b * (1.0 - SHADE * 0.75), c.a)


## How much wider than the core strip the city is built (half on each side).
const CITY_MORE := 24.0


static func ground_chunk(noise: FastNoiseLite, z0: float, size: Vector2, cell: float, flank := 0.0) -> Mesh:
	var b := Builder.new()
	b.bottoms = false
	var xs := ground_cols(size.x, cell, flank)
	var nx := xs.size() - 1
	var nz := roundi(size.y / cell)
	var cz_ := size.y / nz
	var hgt := func(x: float, z: float) -> float:
		return noise.get_noise_2d(x, z) + 0.35 * sin(x * 0.05 + z * 0.01) + lift()
	var height := func(h: float) -> float:
		return -0.4 if h < 0.0 else minf(h, 0.8) * 1.6
	# the city keeps its flat ground (its roads are laid on it); elsewhere the land has its set
	# pieces (Relief): canyons, cliffs, craters...
	var shaped := theme != "city"
	Relief.fx.clear()
	Relief.liquid = PackedVector3Array()
	Relief.liquid_flow = PackedVector2Array()
	# one vertex grid, jittered in world space so neighbouring chunks still meet
	var hs := []
	var vs := []
	var wet := []
	for i in nx + 1:
		var hr := []
		var vr := []
		var wr := []
		for j in nz + 1:
			var wx := xs[i]
			var wz := z0 - j * cz_
			var jx := (hash2(wx, wz) - 0.5) * cell * 0.3
			var jz := (hash2(wz * 1.3, wx * 0.7) - 0.5) * cell * 0.3
			if i == 0 or i == nx:
				jx = 0.0
			var h: float = hgt.call(wx + jx, wz + jz)
			if shaped:
				var r := Relief.at(wx + jx, wz + jz, h)
				hr.append(r.y)
				vr.append(Vector3(wx + jx, r.x, wz + jz))
				wr.append(Vector2(r.z, r.w))
			else:
				hr.append(h)
				vr.append(Vector3(wx + jx, height.call(h), wz + jz))
				wr.append(Vector2.ZERO)
		hs.append(hr)
		vs.append(vr)
		wet.append(wr)
	# soft normals: mostly the broad shape of the land (from the height field itself, so chunks
	# meet without a seam), a little of each facet, so it reads as low poly but polished
	var e := cell * 0.6
	var ground_h := func(x: float, z: float) -> float:
		if shaped:
			return Relief.at(x, z, hgt.call(x, z)).x
		return height.call(hgt.call(x, z))
	var ns := []
	for i in nx + 1:
		var nr := []
		for j in nz + 1:
			var v: Vector3 = vs[i][j]
			if (wet[i][j] as Vector2).x > 0.0 or (v.y <= -0.4 and hs[i][j] < 0.0):
				nr.append(Vector3.UP)   # water lies flat, even where a lowered sea slopes away
				continue
			var dx: float = ground_h.call(v.x + e, v.z) - ground_h.call(v.x - e, v.z)
			var dz: float = ground_h.call(v.x, v.z + e) - ground_h.call(v.x, v.z - e)
			nr.append(Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized())
		ns.append(nr)
	# vertex colours, darkened in hollows (cheap baked occlusion) and in the depths; steep faces
	# are bare rock, flagged in alpha for the ground shader's strata
	var cs := []
	for i in nx + 1:
		var cr := []
		for j in nz + 1:
			var h: float = hs[i][j]
			var c := ground_col(h)
			var y: float = vs[i][j].y
			if h >= 0.0:
				var around := 0.0
				var k := 0
				for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var a := i + d.x
					var ee := j + d.y
					if a >= 0 and a <= nx and ee >= 0 and ee <= nz:
						around += vs[a][ee].y
						k += 1
				var hollow: float = clampf((around / k - y) * 0.8, 0.0, 0.25)
				c = c.darkened(hollow)
				var steep := smoothstep(0.16, 0.42, 1.0 - (ns[i][j] as Vector3).y)
				if steep > 0.0:
					c = c.lerp(rock_col(y), steep)
					c.a = 1.0 - steep
				if y < -0.6:
					c = Color(c.darkened(clampf(-y * 0.03, 0.0, 0.3)), c.a)
				# baked sun shadows: cliffs, canyon walls, crater rims and mesas shade the land beside
				# them (Guillaume, 2026-11-24: "bake shadows" on the landscape)
				if shaped:
					var sh := sun_shade(ground_h, vs[i][j])
					if sh > 0.0:
						c = Color(c.lerp(shade_col(c), sh), c.a)
			cr.append(c)
		cs.append(cr)
	var gv := PackedVector3Array()
	var gn := PackedVector3Array()
	var gc := PackedColorArray()
	for i in nx:
		for j in nz:
			var q := [vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]]
			var qn := [ns[i][j], ns[i + 1][j], ns[i + 1][j + 1], ns[i][j + 1]]
			var qc := [cs[i][j], cs[i + 1][j], cs[i + 1][j + 1], cs[i][j + 1]]
			# split along the shorter diagonal of heights so ridges read as ridges
			var flip: bool = absf(q[0].y - q[2].y) > absf(q[1].y - q[3].y)
			var order := [[0, 1, 3], [1, 2, 3]] if flip else [[0, 1, 2], [0, 2, 3]]
			# colours blend smoothly corner to corner; normals are 80% land, 20% facet
			for t: Array in order:
				var a: Vector3 = q[t[0]]
				var bb: Vector3 = q[t[1]]
				var c: Vector3 = q[t[2]]
				var fn := (bb - a).cross(c - a).normalized()
				if fn.y < 0.0:
					fn = -fn
					var tmp: int = t[1]
					t = [t[0], t[2], tmp]
				for k: int in [t[0], t[2], t[1]]:
					gv.append(q[k])
					gn.append(((qn[k] as Vector3) * 0.8 + fn * 0.2).normalized())
					gc.append(qc[k])
			# rivers, lakes and lava: a moving surface over the ground (Relief.fx_mesh)
			var wq := [wet[i][j], wet[i + 1][j], wet[i + 1][j + 1], wet[i][j + 1]]
			var nwet := 0
			for w: Vector2 in wq:
				if w.x > 0.0:
					nwet += 1
			if nwet > 0:
				for t: Array in order:
					if (wq[t[0]] as Vector2).x > 0.0 and (wq[t[1]] as Vector2).x > 0.0 and (wq[t[2]] as Vector2).x > 0.0:
						for k: int in [t[0], t[2], t[1]]:
							Relief.liquid.append(q[k] + Vector3(0, 0.04, 0))
							var fl: float = (wq[k] as Vector2).y
							Relief.liquid_flow.append(Vector2(0, 1) if fl == 1.0 else (Vector2(1, 0) if fl == 2.0 else Vector2.ZERO))
			# scenery: woods, villages, beaches, rocks and boats
			var hs4: Array[float] = [hs[i][j], hs[i + 1][j], hs[i + 1][j + 1], hs[i][j + 1]]
			var cy: float = minf(minf(q[0].y, q[1].y), minf(q[2].y, q[3].y))
			var top: float = maxf(maxf(q[0].y, q[1].y), maxf(q[2].y, q[3].y))
			# the wide cells out on the flanks are far off in the fog: bare ground is enough
			if xs[i + 1] - xs[i] > cell * 3.5:
				continue
			# nothing stands on a cliff, in a river or on a lowered shore (only the sea's own props)
			if top - cy > 0.9 or (nwet > 0 and nwet < 4) or (nwet == 4 and theme != "volcano"):
				continue
			sea_y = cy
			var cen: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
			if shaped and (Relief.in_town(cen.x, cen.z) or Relief.near_fall(cen.x, cen.z)):
				continue
			if theme != "coast":
				# the other worlds' land (Glass Coast's scenery is scatter's)
				b.xf = Transform3D.IDENTITY
				theme_prop(b, (hs4[0] + hs4[1] + hs4[2] + hs4[3]) * 0.25, cen, cy, hash2(cen.x * 1.7, cen.z * 0.3))
				continue
			scatter(b, hs4, cen, cy)
	if shaped:
		Towns.build(b, z0, z0 - size.y)
		Relief.fx = Relief.events(z0, z0 - size.y, noise)
		for ev: Dictionary in Relief.fx:
			if ev.t == "rock":
				meteorite(b, ev.at)
	if theme == "city":
		# the city runs on past the core strip, so from the chase its blocks don't stop short
		var roads := City.build(b, z0, Vector2(size.x + CITY_MORE, size.y), hgt, height)
		gv.append_array(PackedVector3Array(roads[0]))
		gn.append_array(PackedVector3Array(roads[1]))
		gc.append_array(PackedColorArray(roads[2]))
		# a calm, low-contrast backdrop, so foes and bullets stand out (Guillaume, 2026-11-24: "the
		# city landscape is too messy... not very easy to see the enemies")
		b.tone = City.calm
		for i in gc.size():
			gc[i] = City.calm(gc[i])
	var mesh := b.commit() if b.n > 0 else ArrayMesh.new()
	ao_mesh = ao_blobs(b.take_spots(), ground_h)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = gv
	arr[Mesh.ARRAY_NORMAL] = gn
	arr[Mesh.ARRAY_COLOR] = gc
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## The last `ground_chunk`'s contact shadows (`ao_blobs`), for `Game.update_chunks` to hang under it.
static var ao_mesh: Mesh


## Baked contact occlusion: a soft dark disc on the ground under each placed prop, as wide as
## what stands on it and darker the taller it is, following the ground's height (`ground_h`).
## One see-through mesh a chunk, drawn with `ao_mat`.
static func ao_blobs(spots: Array, ground_h: Callable, cast := true) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for sp: Array in spots:
		var lo: Vector2 = sp[2]
		var hi: Vector2 = sp[3]
		var base: Vector3 = sp[0]
		var c := (lo + hi) * 0.5
		var r := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 * AO_SPREAD + 0.3
		var a := clampf(0.3 + float(sp[1]) * 0.06, 0.0, AO_DARK)
		# baked cast shadow: the disc stretches away from the sun as far as the prop is tall
		var lean: Vector2 = sun_slide * float(sp[1]) * CAST if cast else Vector2.ZERO
		var u := lean.normalized() if lean.length() > 0.01 else Vector2(1, 0)
		var w := Vector2(-u.y, u.x)
		var ru := r + lean.length() * 0.5
		c += lean * 0.5
		var on_ground := func(x: float, z: float) -> Vector3:
			return Vector3(x, maxf(float(ground_h.call(x, z)), base.y) + AO_LIFT, z)
		# a soft falloff: an inner ring at 55% of the radius still holds 60% of the shade
		var mid: Vector3 = on_ground.call(c.x, c.y)
		var inner := []
		var ring := []
		for k in AO_SEG:
			var ang := TAU * k / AO_SEG
			var o := u * cos(ang) * ru + w * sin(ang) * r
			inner.append(on_ground.call(c.x + o.x * 0.55, c.y + o.y * 0.55))
			ring.append(on_ground.call(c.x + o.x, c.y + o.y))
		var dark := Color(0, 0, 0, a)
		var half := Color(0, 0, 0, a * 0.6)
		var clear := Color(0, 0, 0, 0)
		for k in AO_SEG:
			var k1 := (k + 1) % AO_SEG
			for t: Array in [[mid, dark, inner[k], half, inner[k1], half],
					[inner[k], half, ring[k], clear, ring[k1], clear],
					[inner[k], half, ring[k1], clear, inner[k1], half]]:
				for v in 3:
					st.set_color(t[v * 2 + 1])
					st.add_vertex(t[v * 2])
			n += 9
	if n == 0:
		return null
	return st.commit()


## A contact shadow for a model standing on something else (a gun on a fortress's deck): a soft disc
## on y = 0 as wide as the model seen from above, cached by `key`.
static func contact(key: String, m: Mesh) -> Mesh:
	return cached("contact_" + key, func() -> Mesh:
		var bx := m.get_aabb()
		var lo := Vector2(bx.position.x, bx.position.z)
		var hi := lo + Vector2(bx.size.x, bx.size.z)
		return ao_blobs([[Vector3.ZERO, bx.size.y, lo * 0.8, hi * 0.8]], func(_x: float, _z: float) -> float: return 0.0, false))


const AO_SEG := 10
## Contact shadows: how far past the prop's own footprint they spread, their darkest, their lift
## off the ground (above the low poly ground's facets).
const AO_SPREAD := 1.35
const AO_DARK := 0.42
const AO_LIFT := 0.1
## How far a prop's baked shadow reaches along the sun, as a share of its full sun shadow.
const CAST := 1.6


## The contact shadows' material: black, see-through by vertex alpha, fogged like the ground.
static func ao_mat() -> StandardMaterial3D:
	if not _cache.has("ao"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color.WHITE
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.render_priority = -10
		_cache["ao"] = m
	return _cache["ao"]


# ---------------------------------------------------------------- scenery
## Small things on the land and sea, built into each terrain chunk (one mesh, no extra draw
## calls). Each is built round its own origin, then turned and placed with `Builder.xf`.
const WALLS := [Color8(0xf4, 0xee, 0xe2), Color8(0xec, 0xdc, 0xbe), Color8(0xd8, 0xe6, 0xee), Color8(0xf2, 0xd6, 0xc2)]
const ROOFS := [Color8(0xc0, 0x5a, 0x3e), Color8(0xa2, 0x46, 0x36), Color8(0x56, 0x68, 0x7e), Color8(0xd4, 0x7c, 0x4a)]
const WOOD := Color8(0x8a, 0x62, 0x40)
const DRIFT := Color8(0xc8, 0xb4, 0x96)
const GLASS := Color8(0x35, 0x4e, 0x68)
const BRICK := Color8(0x9a, 0x5a, 0x48)
const LEAF := Color8(0x5a, 0x94, 0x44)
const PALM := Color8(0x66, 0xa4, 0x40)
const FOAM := Color8(0xdc, 0xf2, 0xf2)
const STONE := Color8(0xc4, 0xba, 0xa6)
const STONE_WET := Color8(0x96, 0x90, 0x86)
const PYRAMID := Color8(0xc9, 0xa8, 0x6c)
const DUCK := Color8(0xff, 0xd2, 0x2e)


## How many of each kind of scenery the chunks built so far hold (tests read it).
static var scenery := {}


static func count(kind: String) -> void:
	scenery[kind] = scenery.get(kind, 0) + 1


## Scenery is drawn comically larger than life so it reads on a phone screen (Guillaume found
## it too small at 1, then asked for it "comically big"): this wide, and PROP_V as tall, which
## keeps the tallest props (lighthouses, towers, pines) under the flight altitude.
const PROP_SCALE := 2.5
const PROP_V := 1.8


## Landmarks: the prominent scenery the player can shoot down (lighthouses, boats, two-storey
## houses). `scatter` leaves them out of the chunk's mesh and lists them here instead; the game
## takes the list after each chunk (`Game.update_chunks`) and gives each its own node.
static var marks: Array = []
## Height of a landmark's centre above its base before PROP_V (see mark_h).
const MARK_H := {"lighthouse": 1.15, "boat": 0.2, "house": 0.57, "pyramid": 0.7, "duck": 0.4,
	"water tower": 1.1, "snowman": 1.0, "stone head": 0.85}


## Height of a landmark's centre above its base (the game hits it there, as it shows on screen).
static func mark_h(kind: String) -> float:
	return MARK_H[kind] * PROP_V


static func mark(kind: String, pos: Vector3, ang: float, r: float) -> void:
	count(kind)
	marks.append({"kind": kind, "pos": pos, "ang": ang, "r": r})


static func house_kind(r: float) -> int:
	return int(r * 53.0) % 3


## A landmark's own mesh, centred on its hit point (MARK_H above its base), facing +z.
static func landmark(kind: String, r: float) -> Mesh:
	var q := snappedf(r, 1.0 / 32.0)
	return cached("mark_%s_%s" % [kind, q], func() -> Mesh:
		var b := Builder.new()
		b.bottoms = false
		var at := Vector3(0, -mark_h(kind), 0)
		match kind:
			"lighthouse":
				lighthouse(b, at, q * TAU)
			"boat":
				boat(b, at, 0.0)
			"house":
				house(b, at, 0.0, q)
			"pyramid":
				pyramid(b, at)
			"duck":
				duck(b, at)
			"water tower":
				water_tower(b, at)
			"snowman":
				snowman(b, at, q)
			"stone head":
				stone_head(b, at)
		b.xf = Transform3D.IDENTITY
		return b.commit())


## What is left of a landmark once it's shot down, from its base: a scorched stump and rubble.
static func ruin(kind: String) -> Mesh:
	return cached("ruin_" + kind, func() -> Mesh:
		var b := Builder.new()
		b.bottoms = false
		place(b, Vector3.ZERO, 0.0)
		var soot := Color8(0x3a, 0x34, 0x30)
		match kind:
			"lighthouse":
				b.prism(Vector3.ZERO, ngon(0.75, 8), -0.4, 0.42, STONE_WET.darkened(0.2), Vector2(0.8, 0.8))
				b.prism(Vector3.ZERO, ngon(0.36, 8), 0.1, 0.55, Color8(0xd8, 0xd2, 0xc8).darkened(0.3), Vector2(0.9, 0.9))
				b.prism(Vector3.ZERO, ngon(0.24, 8), 0.5, 0.58, soot)
				for k in 4:
					b.octa(Vector3(cos(k * 1.7) * 0.7, 0.35, sin(k * 1.7) * 0.7), 0.16, Color8(0xc8, 0x3c, 0x34).darkened(0.35))
			"house":
				b.prism(Vector3.ZERO, ngon(0.95, 8), -0.3, 0.05, soot, Vector2(0.95, 0.95))
				b.box(Vector3(-0.3, 0.2, 0.42), Vector3(0.7, 0.36, 0.08), WALLS[0].darkened(0.45))
				b.box(Vector3(0.5, 0.15, -0.1), Vector3(0.08, 0.3, 0.7), WALLS[0].darkened(0.5))
				b.box(Vector3(-0.3, 0.35, 0.1), Vector3(0.16, 0.7, 0.16), BRICK.darkened(0.25))
				for k in 5:
					b.octa(Vector3(cos(k * 2.3) * 0.5, 0.08, sin(k * 2.3) * 0.4), 0.13, ROOFS[k % 4].darkened(0.4))
			"pyramid", "water tower", "snowman", "stone head":
				# a scorched heap in the landmark's own colours
				var c: Color = {"pyramid": PYRAMID, "water tower": Color8(0xc8, 0x3c, 0x34), "snowman": Color8(0xf2, 0xf6, 0xfa),
					"stone head": Color8(0x5a, 0x56, 0x58)}[kind]
				var w := 1.1 if kind == "pyramid" else 0.6
				b.prism(Vector3.ZERO, ngon(w * 1.1, 8), -0.3, 0.05, soot, Vector2(0.95, 0.95))
				b.prism(Vector3.ZERO, ngon(w * 0.8, 7), -0.2, 0.3 if kind == "pyramid" else 0.2, c.darkened(0.3), Vector2(0.6, 0.6))
				for k in 6:
					b.octa(Vector3(cos(k * 2.1) * w * 0.9, 0.08, sin(k * 2.1) * w * 0.8), 0.14, c.darkened(0.2 + (k % 2) * 0.2))
			"duck":
				b.prism(Vector3.ZERO, ngon(0.7, 10), -0.03, 0.01, FOAM.darkened(0.15))
				for k in 3:
					b.octa(Vector3(cos(k * 2.0) * 0.4, 0.03, sin(k * 2.0) * 0.35), 0.14, DUCK.darkened(0.2))
			"boat":
				b.prism(Vector3.ZERO, ngon(0.8, 10), -0.03, 0.01, FOAM.darkened(0.15))
				for k in 4:
					var a := k * 1.6
					place(b, Vector3(cos(a) * 0.5, 0, sin(a) * 0.4) * PROP_SCALE, a * 2.0)
					b.box(Vector3(0, 0.02, 0), Vector3(0.36, 0.06, 0.1), WOOD.darkened(0.2))
		b.xf = Transform3D.IDENTITY
		return b.commit())


static func place(b: Builder, pos: Vector3, ang: float) -> void:
	b.xf = Transform3D(Basis(Vector3.UP, ang) * Basis.from_scale(Vector3(PROP_SCALE, PROP_V, PROP_SCALE)), pos)
	b.occlude(AO_H)


## What grows or stands on one terrain cell, from the noise heights at its corners `h`;
## `cen` is its centre and `cy` its lowest corner.
static func scatter(b: Builder, h: Array[float], cen: Vector3, cy: float) -> void:
	var avg := (h[0] + h[1] + h[2] + h[3]) * 0.25
	var lo := minf(minf(h[0], h[1]), minf(h[2], h[3]))
	var hi := maxf(maxf(h[0], h[1]), maxf(h[2], h[3]))
	var r := hash2(cen.x * 1.7, cen.z * 0.3)
	var r2 := hash2(cen.z * 0.9 + 3.1, cen.x * 1.3)
	var ang := r2 * TAU
	var at := Vector3(cen.x, cy, cen.z)
	if lo < 0.0 and hi >= 0.0:
		# the shoreline: rocks in the surf, now and then a lighthouse on a point
		if r < 0.0045 and avg > -0.15:
			mark("lighthouse", Vector3(cen.x, sea_y, cen.z), ang, r2)
		elif r < 0.016:
			rocks(b, Vector3(cen.x + (r2 - 0.5) * 0.8, sea_y, cen.z), 0.8 + r * 30.0, r2, true)
	elif hi < 0.0:
		# at sea: stacks in the shallows, fishing boats further out
		if avg > -0.14 and r < 0.008:
			rocks(b, Vector3(cen.x, sea_y, cen.z), 0.9 + r * 50.0, r2, true)
		elif avg < -0.22 and r < 0.0035:
			mark("boat", Vector3(cen.x, sea_y, cen.z), ang, r2)
		elif avg < -0.22 and r < 0.0045:
			mark("duck", Vector3(cen.x, sea_y, cen.z), ang, r2)
	elif avg < 0.08:
		# the beach: palms, sun-bleached driftwood, pebbles, the odd parasol, dune grass
		if r < 0.035:
			palm(b, at, r2)
			if r < 0.012:
				palm(b, at + Vector3(1.8, 0, 1.2).rotated(Vector3.UP, ang), r2 * 0.7 + 0.2)
		elif r < 0.045:
			count("driftwood")
			place(b, at, ang)
			b.box(Vector3(0, 0.04, 0), Vector3(1.1, 0.13, 0.13), DRIFT)
			b.box(Vector3(0.25, 0.05, 0.16), Vector3(0.4, 0.09, 0.09), DRIFT.darkened(0.1))
		elif r < 0.05:
			rocks(b, at, 0.7 + (r - 0.045) * 60.0, r2, false)
		elif r < 0.067:
			parasol(b, at, ang, r2)
		elif r < 0.12 and avg > 0.03:
			# dune grass where the sand rises
			place(b, at, ang)
			count("dune grass")
			for k in 3:
				var tp := Vector3((k - 1) * 0.5, -0.05, (k % 2) * 0.4)
				b.prism(tp, ngon(0.3 - k * 0.04, 5, k), 0, 0.3, Color8(0xa6, 0xb2, 0x62).darkened(k * 0.06), Vector2(0.3, 0.3))
	elif avg < 0.3:
		# the grass: villages here and there, a farm or a copse elsewhere
		var village := hash2(floor(cen.x / 14.0) * 3.1 + 0.5, floor(cen.z / 14.0) * 1.7 + 0.5) < 0.38
		# one house per 8 x 8 lot at most, so the scaled-up houses and gardens don't overlap
		var even := posmod(floori(cen.x * 0.5), 4) == 0 and posmod(floori(cen.z * 0.5), 4) == 0
		var lot := 0.7 if village else 0.03
		if avg >= 0.11 and r < lot and even:
			var turn := snappedf(ang, PI * 0.5) + (r2 - 0.5) * 0.3
			if house_kind(r2) == 1:
				mark("house", at, turn, r2)   # the tall ones can be shot down
			else:
				house(b, at, turn, r2)
		elif r2 < 0.035:
			broadleaf(b, at + Vector3((r - 0.5) * 0.8, 0, (r2 - 0.02) * 20.0), r)
		elif r2 < 0.06:
			bush(b, at + Vector3((r - 0.5), 0, 0), r)
		elif village and r2 < 0.075:
			count("hay")
			place(b, at, ang)
			for k in 2:
				b.prism(Vector3(k * 0.5 - 0.25, -0.1, 0), ngon(0.2, 7), 0, 0.36, Color8(0xe0, 0xbc, 0x60))
	elif avg < 0.52:
		# the woods, with a boulder among the pines
		if r < 0.3:
			conifer(b, at + Vector3((r2 - 0.5) * 1.2, 0, 0), r)
		elif r < 0.306:
			rocks(b, at, 0.8 + r2 * 0.4, r2, false)
	elif r < 0.025:
		# outcrops of bare rock on the heights
		rocks(b, at, 1.0 + r * 16.0, r2, false)
	b.xf = Transform3D.IDENTITY


static func conifer(b: Builder, p: Vector3, r: float) -> void:
	count("conifer")
	place(b, p, r * 6.0)
	var tall := 1.4 + hash2(p.x, p.z) * 0.9
	var tc := FOREST.darkened(0.05 + r * 0.15)
	b.prism(Vector3(0, -0.1, 0), ngon(0.8, 7), 0, tall * 0.6, tc, Vector2(0.45, 0.45))
	b.prism(Vector3(0, -0.1 + tall * 0.45, 0), ngon(0.6, 7, 0.4), 0, tall * 0.6, tc.lightened(0.06), Vector2(0.05, 0.05))


## A round-crowned tree: a stubby trunk and two tiers of foliage.
static func broadleaf(b: Builder, p: Vector3, r: float) -> void:
	place(b, p, r * TAU)
	count("broadleaf")
	var c := LEAF.darkened(r * 0.2).lerp(Color8(0x8c, 0xb4, 0x4a), maxf(0.0, r - 0.7) * 2.0)
	var big := 0.85 + r * 0.35
	b.prism(Vector3.ZERO, ngon(0.09, 5), -0.1, 0.55 * big, WOOD)
	b.prism(Vector3(0, 0.45 * big, 0), ngon(0.6 * big, 7), 0, 0.42 * big, c, Vector2(1.08, 1.08))
	b.prism(Vector3(0, 0.87 * big, 0), ngon(0.65 * big, 7, 0.2), 0, 0.42 * big, c.lightened(0.07), Vector2(0.35, 0.35))


static func bush(b: Builder, p: Vector3, r: float) -> void:
	count("bush")
	place(b, p, r * TAU)
	b.prism(Vector3.ZERO, ngon(0.34, 6), -0.1, 0.32, LEAF.darkened(0.15 + r * 0.1), Vector2(0.55, 0.55))
	b.prism(Vector3(0.3, 0, 0.1), ngon(0.22, 6), -0.1, 0.22, LEAF.darkened(0.08), Vector2(0.5, 0.5))


## One to three boulders round `p`, sized about `s`; `wet` ones are darker and ringed with surf.
static func rocks(b: Builder, p: Vector3, s: float, r: float, wet: bool, tint := Color(0, 0, 0, 0)) -> void:
	# a natural outcrop (Guillaume, 2026-11-24: "big rocks, as big as the ship, with small ones on
	# the sides"): one big faceted rock, a few smaller ones leaning on its sides, pebbles at its foot
	count("sea rocks" if wet else "rocks")
	place(b, p, r * TAU)
	var col := (STONE_WET if wet else STONE) if tint.a == 0.0 else tint
	boulder(b, Vector3.ZERO, s, r, col)
	var n := 3 + int(r * 4.0)
	var reach := s
	for k in n:
		var hk := hash2(r * 17.0 + k, k * 3.3)
		var a := TAU * k / n + r * 5.0 + hk * 0.9
		var sz := s * (0.22 + 0.3 * hash2(k * 1.7, r * 11.0))
		var d := s * (0.78 + 0.3 * hk) + sz * 0.5
		reach = maxf(reach, d + sz)
		boulder(b, Vector3(cos(a), 0, sin(a)) * d, sz, r + k * 0.37, col.darkened(0.04 + hk * 0.1))
	for k in 5:
		var a := r * 9.0 + k * 1.3
		var d := s * (1.25 + 0.4 * hash2(k, r))
		b.octa(Vector3(cos(a) * d, -0.02, sin(a) * d), s * 0.07 + 0.03, col.darkened(0.12), Vector3(1.0, 0.6, 1.0))
	if wet:
		b.prism(Vector3.ZERO, ngon(reach * 1.15, 10, r), -0.43, -0.37, FOAM)


## One rock: an irregular faceted body, a narrower cap catching the light, leaning a little.
static func boulder(b: Builder, c: Vector3, s: float, seed: float, col: Color) -> void:
	var out := PackedVector2Array()
	for a in 7:
		var rr := s * (0.7 + hash2(seed * 31.0 + a, a * 3.0 + seed) * 0.45)
		var an := TAU * a / 7.0 + seed * 2.0
		out.append(Vector2(cos(an), sin(an)) * rr)
	var mid := s * (0.42 + 0.15 * hash2(seed, 5.0))
	var lean := Vector2(hash2(seed, 7.0) - 0.5, hash2(seed, 9.0) - 0.5) * s * 0.25
	b.prism(c, out, -0.3, mid, col.darkened(0.05), Vector2(0.9, 0.88), lean * 0.4)
	b.prism(c + Vector3(lean.x * 0.4, 0, lean.y * 0.4), out, mid, mid + s * (0.32 + 0.2 * hash2(seed, 13.0)), col.lightened(0.06),
		Vector2(0.45, 0.4), lean, col.darkened(0.12))


## A palm: a slender trunk that leans and curves, a crown of drooping fronds.
static func palm(b: Builder, p: Vector3, r: float) -> void:
	count("palm")
	place(b, p, r * TAU)
	var tall := 1.3 + r * 0.6
	var seg := tall / 4.0
	var base := Vector3(0, -0.1, 0)
	for k in 4:
		var lean := Vector2(0.05 + k * 0.05, 0.0)
		b.prism(base, ngon(0.11 - k * 0.012, 5), 0, seg + 0.04, WOOD.lightened(0.15 + (k % 2) * 0.08), Vector2(0.85, 0.85), lean)
		base += Vector3(lean.x, seg, lean.y)
	var top := base + Vector3(0, 0.05, 0)
	b.octa(top + Vector3(0.05, -0.1, 0), 0.1, Color8(0x6a, 0x4a, 0x2c))
	for k in 7:
		var an := TAU * k / 7.0 + r
		var d := Vector3(cos(an), 0, sin(an))
		var side := Vector3(-d.z, 0, d.x)
		var ln := 0.85 + hash2(r * 5.0, k) * 0.3
		var mid := top + d * ln * 0.5 + Vector3(0, 0.08, 0)
		var tip := top + d * ln + Vector3(0, -0.45, 0)
		var c := PALM.darkened(0.12 * (k % 2))
		b.tri(top, mid + side * 0.2, tip, c, Vector3.UP)
		b.tri(top, tip, mid - side * 0.2, c.darkened(0.08), Vector3.UP)


## A beach parasol in red and white, with a towel laid out beside it.
static func parasol(b: Builder, p: Vector3, ang: float, r: float) -> void:
	count("parasol")
	place(b, p, ang)
	b.prism(Vector3.ZERO, ngon(0.03, 4), -0.1, 0.8, WOOD.lightened(0.3))
	var apex := Vector3(0, 0.9, 0)
	var c: Color = ROOFS[int(r * 40.0) % 4].lightened(0.1)
	for k in 8:
		var a := Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * 0.55 + Vector3(0, 0.68, 0)
		var e := Vector3(cos(TAU * (k + 1) / 8.0), 0, sin(TAU * (k + 1) / 8.0)) * 0.55 + Vector3(0, 0.68, 0)
		b.tri(apex, a, e, c if k % 2 == 0 else Color8(0xf6, 0xf2, 0xea), Vector3.UP)
	b.box(Vector3(0.55, 0.01, 0.1), Vector3(0.32, 0.04, 0.6), Color8(0x4c, 0xb8, 0xd8) if r < 0.5 else Color8(0xf2, 0xc6, 0x3a))


## A small fishing boat riding at sea level (y = -0.4): white hull, wooden deck, a wheelhouse.
static func boat(b: Builder, p: Vector3, ang: float) -> void:
	count("boat")
	place(b, p, ang)
	var hull := pts([Vector2(-0.26, 0.55), Vector2(0.26, 0.55), Vector2(0.32, -0.1), Vector2(0, -0.8), Vector2(-0.32, -0.1)])
	b.prism(Vector3.ZERO, ngon(0.75, 10), -0.03, 0.02, FOAM, Vector2(1, 1))
	b.prism(Vector3.ZERO, hull, -0.1, 0.18, Color8(0xf4, 0xf4, 0xf0), Vector2(1.05, 1.05), Vector2.ZERO, Color8(0x2e, 0x5a, 0x8a))
	b.prism(Vector3(0, 0, 0.04), hull, 0.18, 0.2, WOOD.lightened(0.2), Vector2(0.82, 0.82))
	b.box(Vector3(0, 0.34, 0.2), Vector3(0.32, 0.3, 0.28), Color8(0xf4, 0xf4, 0xf0))
	b.box(Vector3(0, 0.52, 0.2), Vector3(0.38, 0.06, 0.34), Color8(0xc0, 0x5a, 0x3e))
	b.box(Vector3(0, 0.36, 0.05), Vector3(0.26, 0.1, 0.03), GLASS)


## A gabled roof over a w x d box whose walls end at y, ridge along x; gable ends in `wall`.
static func gable(b: Builder, c: Vector3, w: float, d: float, y: float, rise: float, col: Color, wall: Color) -> void:
	var o := 0.1
	var x0 := c.x - w * 0.5
	var x1 := c.x + w * 0.5
	var fz := c.z + d * 0.5 + o
	var bz := c.z - d * 0.5 - o
	var ry := y + rise
	b.quad(Vector3(x0 - o, y - 0.04, fz), Vector3(x1 + o, y - 0.04, fz), Vector3(x1 + o, ry, c.z), Vector3(x0 - o, ry, c.z), col, Vector3(0, 1, 1))
	b.quad(Vector3(x0 - o, y - 0.04, bz), Vector3(x1 + o, y - 0.04, bz), Vector3(x1 + o, ry, c.z), Vector3(x0 - o, ry, c.z), col, Vector3(0, 1, -1))
	# the eaves' thickness, a darker line that crisps the roof against the walls
	b.quad(Vector3(x0 - o, y - 0.04, fz), Vector3(x1 + o, y - 0.04, fz), Vector3(x1 + o, y - 0.1, fz), Vector3(x0 - o, y - 0.1, fz), col.darkened(0.35), Vector3(0, 0, 1))
	for x in [x0, x1]:
		b.tri(Vector3(x, y, c.z - d * 0.5), Vector3(x, y, c.z + d * 0.5), Vector3(x, ry, c.z), wall.darkened(0.05), Vector3(signf(x - c.x), 0, 0))


## Windows (and a door) on a wall facing +z at z, centred on x.
static func facade(b: Builder, x: float, z: float, w: float, floors: int, door: bool) -> void:
	for f in floors:
		var y := 0.36 + f * 0.42
		for k in 2:
			var wx := x + (k - 0.5) * w * 0.5
			if door and f == 0 and k == 0:
				b.box(Vector3(wx, 0.17, z + 0.02), Vector3(0.2, 0.38, 0.05), WOOD)
			else:
				b.box(Vector3(wx, y, z + 0.02), Vector3(0.2, 0.17, 0.04), GLASS)


## A house, one of three: a cottage, a two-storey house with a hipped roof, or an L-shaped
## farmhouse; walls and roofs vary, gardens get a fence or a hedge.
static func house(b: Builder, p: Vector3, ang: float, r: float) -> void:
	count("house")
	place(b, p, ang)
	var base := b.xf
	var wall: Color = WALLS[int(r * 17.0) % 4]
	var roof: Color = ROOFS[int(r * 29.0) % 4]
	var kind := house_kind(r)
	if kind == 0:
		var w := 1.25
		var d := 0.85
		var y := 0.62
		b.box(Vector3(0, (y - 0.4) * 0.5, 0), Vector3(w, y + 0.4, d), wall)
		gable(b, Vector3.ZERO, w, d, y, 0.42, roof, wall)
		b.box(Vector3(w * 0.28, y + 0.38, -d * 0.18), Vector3(0.16, 0.46, 0.16), BRICK)
		facade(b, 0, d * 0.5, w, 1, true)
		facade(b, 0, -d * 0.5 - 0.04, w, 1, false)
	elif kind == 1:
		var w := 1.05
		var d := 0.95
		var y := 1.02
		b.box(Vector3(0, (y - 0.4) * 0.5, 0), Vector3(w, y + 0.4, d), wall)
		b.prism(Vector3.ZERO, pts([Vector2(-w * 0.5 - 0.1, -d * 0.5 - 0.1), Vector2(w * 0.5 + 0.1, -d * 0.5 - 0.1),
			Vector2(w * 0.5 + 0.1, d * 0.5 + 0.1), Vector2(-w * 0.5 - 0.1, d * 0.5 + 0.1)]), y - 0.04, y + 0.42, roof, Vector2(0.4, 0.04))
		b.box(Vector3(-w * 0.3, y + 0.35, 0.1), Vector3(0.15, 0.42, 0.15), BRICK)
		facade(b, 0, d * 0.5, w, 2, true)
		b.xf = base * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		facade(b, 0, w * 0.5, d, 2, false)
		b.xf = base
	else:
		var w := 1.5
		var d := 0.72
		var y := 0.56
		b.box(Vector3(0, (y - 0.4) * 0.5, -0.15), Vector3(w, y + 0.4, d), wall)
		gable(b, Vector3(0, 0, -0.15), w, d, y, 0.36, roof, wall)
		facade(b, -0.2, d * 0.5 - 0.15, w * 0.7, 1, true)
		# the wing, its ridge across the main one
		b.xf = base * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.45, 0, 0.35))
		b.box(Vector3(0, (y - 0.4) * 0.5, 0), Vector3(0.75, y + 0.4, 0.6), wall)
		gable(b, Vector3.ZERO, 0.75, 0.6, y, 0.32, roof, wall)
		b.xf = base
		b.box(Vector3(0.45, 0.3, 0.66), Vector3(0.18, 0.15, 0.04), GLASS)
	# the garden in front: a white picket fence or a hedge
	var g := 0.62
	var hedge := r > 0.6
	var fc := LEAF.darkened(0.2) if hedge else Color8(0xf4, 0xf0, 0xe6)
	var th := 0.12 if hedge else 0.05
	var fh := 0.18 if hedge else 0.14
	if r < 0.85:
		var front := 0.95 if kind != 2 else 1.05
		b.box(Vector3(0, fh * 0.5 - 0.1, front), Vector3(1.5, fh + 0.2, th), fc)
		for sx in [-0.75, 0.75]:
			b.box(Vector3(sx, fh * 0.5 - 0.1, front - g * 0.5 + 0.1), Vector3(th, fh + 0.2, g - 0.2), fc)
	b.xf = Transform3D.IDENTITY


## A lighthouse on a rocky foot: red and white bands, a gallery, a lit lantern, a red cap.
static func lighthouse(b: Builder, p: Vector3, ang: float) -> void:
	count("lighthouse")
	rocks(b, p, 0.6, ang / TAU, true)
	place(b, p, ang)
	var y := 0.1
	var rad := 0.36
	for k in 4:
		var c := Color8(0xf6, 0xf4, 0xee) if k % 2 == 0 else Color8(0xc8, 0x3c, 0x34)
		b.prism(Vector3.ZERO, ngon(rad, 8), y, y + 0.5, c, Vector2(0.9, 0.9))
		y += 0.5
		rad *= 0.9
	b.prism(Vector3.ZERO, ngon(rad + 0.12, 8), y, y + 0.06, Color8(0x3a, 0x3f, 0x48))
	b.prism(Vector3.ZERO, ngon(rad * 0.8, 8), y + 0.06, y + 0.34, Color8(0xff, 0xe2, 0x8a))
	b.prism(Vector3.ZERO, ngon(rad, 8), y + 0.34, y + 0.62, Color8(0xc8, 0x3c, 0x34), Vector2(0.08, 0.08))
	b.xf = Transform3D.IDENTITY


## The props of the other worlds' land (Glass Coast's trees and houses are in ground_chunk):
## cacti, mesas and adobe in the dunes; blocks of buildings on a street grid in the city; pines,
## ice shards and floes on the shelf; obsidian spires and lava rocks in the cinder fields.
static func theme_prop(b: Builder, avg: float, cen: Vector3, cy: float, r: float) -> void:
	# things come in groups, not one by one (Guillaume, 2026-11-24: "elements scattered without
	# real character"): groves, fields and outcrops live in some 12 m cells and not others; the
	# landmarks and houses stand in the towns (Towns)
	var r2 := hash2(cen.z * 0.9, cen.x * 2.1)
	var at := Vector3(cen.x, cy, cen.z)
	var grove := hash2(floorf(cen.x / 12.0) * 2.3 + 0.7, floorf(cen.z / 12.0) * 1.9 + 0.3)
	match theme:
		"dunes":
			if avg >= 0.72 and r < 0.02:
				# outcrops of red rock on the heights
				count("boulder")
				rocks(b, at, 0.9 + r * 25.0, r2, false, Color8(0xb8, 0x62, 0x40))
			elif avg >= 0.05 and avg < 0.6 and grove < 0.22 and r < 0.2:
				count("cactus")
				place(b, at + Vector3((r2 - 0.5) * 1.2, 0, 0), r2 * TAU)
				var cg := Color8(0x5c, 0x8a, 0x4a).darkened(r2 * 0.12)
				var ht := 1.0 + r2 * 0.6
				b.prism(Vector3(0, -0.1, 0), ngon(0.26, 7), 0, ht, cg, Vector2(0.85, 0.85))
				b.prism(Vector3(0.36, 0.45, 0), ngon(0.15, 6), 0, 0.55, cg.darkened(0.06), Vector2(0.8, 0.8))
				b.prism(Vector3(-0.32, 0.7, 0), ngon(0.13, 6), 0, 0.4, cg.darkened(0.06), Vector2(0.8, 0.8))
			elif avg >= 0.05 and avg < 0.6 and grove > 0.93 and r < 0.06:
				rocks(b, at, 0.7 + r * 8.0, r2, false, Color8(0xd0, 0x9a, 0x62))
		"city":
			# the city itself is City.build's; the canals get the odd giant rubber duck
			if avg < -0.05 and r < 0.012 and not City.on_road(cen.x, cen.z, 1.5):
				mark("duck", Vector3(cen.x, sea_y, cen.z), r2 * TAU, r2)
		"ice":
			if avg >= 0.28 and avg < 0.5 and r < 0.25:
				count("pine")
				place(b, at, r * 6.0)
				var tall := 1.3 + r2 * 0.6
				var tc := Color8(0x2e, 0x50, 0x4c).darkened(r * 0.2)
				b.prism(Vector3(0, -0.1, 0), ngon(0.6, 6), 0, tall, tc, Vector2(0.05, 0.05))
				b.prism(Vector3(0, tall * 0.55, 0), ngon(0.45, 6, 0.5), 0, tall * 0.55, Color8(0xe8, 0xf2, 0xf8), Vector2(0.05, 0.05))
			elif avg >= 0.6 and grove < 0.35 and r < 0.18:
				# fields of ice shards, leaning together
				count("ice shard")
				place(b, at + Vector3((r2 - 0.5) * 1.2, 0, 0), 0.4 + r2 * 0.5)
				b.prism(Vector3(0, -0.1, 0), ngon(0.5, 4), 0, 1.0 + r2 * 0.8, Color8(0xa6, 0xd6, 0xec), Vector2(0.1, 0.1), Vector2(0.25, 0.05))
				b.prism(Vector3(0.45, -0.1, 0.3), ngon(0.28, 4, 0.4), 0, 0.6 + r * 2.0, Color8(0xc4, 0xe6, 0xf4), Vector2(0.1, 0.1), Vector2(0.15, 0.05))
			elif avg < -0.05 and r < 0.025:
				count("floe")
				place(b, Vector3(cen.x, sea_y - 0.02, cen.z), r * 6.0)
				b.prism(Vector3.ZERO, ngon(0.7 + r2 * 0.8, 7), 0, 0.12, Color8(0xee, 0xf6, 0xfa), Vector2(0.9, 0.9))
		"volcano":
			if avg >= 0.55 and grove < 0.4 and r < 0.22:
				# stands of basalt spires, a big one with smaller round it
				count("spire")
				place(b, at + Vector3((r2 - 0.5), 0, 0), r2 * 6.0)
				b.prism(Vector3(0, -0.1, 0), ngon(0.55, 5), 0, 1.2 + r2 * 1.0, Color8(0x26, 0x22, 0x2a), Vector2(0.15, 0.15), Vector2(0.15, -0.1))
				b.prism(Vector3(0.6, -0.1, 0.25), ngon(0.3, 5, 0.5), 0, 0.5 + r * 3.0, Color8(0x30, 0x2a, 0x30), Vector2(0.2, 0.2))
			elif avg >= 0.15 and avg < 0.55 and r < 0.012:
				rocks(b, at, 0.9 + r * 30.0, r2, false, Color8(0x4a, 0x40, 0x42))
			elif avg < -0.05 and r < 0.02:
				# a raft of cooled crust drifting on the lava
				count("lava rock")
				place(b, Vector3(cen.x, sea_y - 0.05, cen.z), r * 6.0)
				var raft := blob(0.5 + r2 * 0.5, 9, r2)
				b.prism(Vector3.ZERO, raft, 0, 0.16, Color8(0x2a, 0x20, 0x20), Vector2(0.8, 0.8))
				b.prism(Vector3(0.08, 0, -0.05), blob(0.22 + r2 * 0.2, 6, r), 0.1, 0.3, Color8(0x3a, 0x2c, 0x2a), Vector2(0.6, 0.6))
	b.xf = Transform3D.IDENTITY


## The meteorite at the bottom of a desert crater: a dark faceted lump, glowing cracks, debris.
static func meteorite(b: Builder, p: Vector3) -> void:
	count("meteorite")
	place(b, p, 0.4)
	b.octa(Vector3(0, 0.55, 0), 0.9, Color8(0x3a, 0x30, 0x2e), Vector3(1.0, 0.75, 0.85))
	b.octa(Vector3(0.5, 0.35, 0.3), 0.55, Color8(0x2e, 0x26, 0x26), Vector3(1.0, 0.8, 1.0))
	b.box(Vector3(0, 0.6, 0.62), Vector3(0.7, 0.06, 0.06), Color8(0xff, 0x7a, 0x22))
	b.box(Vector3(0.62, 0.5, 0.0), Vector3(0.06, 0.06, 0.6), Color8(0xff, 0x9a, 0x30))
	for k in 6:
		var a := k * 1.1
		b.octa(Vector3(cos(a), 0, sin(a)) * (1.3 + 0.2 * (k % 3)), 0.18 + 0.04 * k, Color8(0x4a, 0x3a, 0x34))
	b.xf = Transform3D.IDENTITY


## A stepped temple pyramid: four tiers, a stair up the front, a small shrine on top.
static func pyramid(b: Builder, p: Vector3) -> void:
	place(b, p, 0.0)
	var y := -0.3
	for k in 4:
		var w := 2.3 - k * 0.48
		var h := 0.34 if k > 0 else 0.6
		b.box(Vector3(0, y + h * 0.5, 0), Vector3(w, h, w), PYRAMID.darkened(k * 0.04))
		b.box(Vector3(0, y + h - 0.02, 0), Vector3(w + 0.06, 0.05, w + 0.06), PYRAMID.lightened(0.12))
		y += h
	# the stair: a ramp of steps up the +z face
	for k in 8:
		var sy := 0.0 + k * 0.155
		var sz := 1.15 - k * 0.115
		b.box(Vector3(0, sy + 0.04, sz), Vector3(0.42, 0.1, 0.13), PYRAMID.lightened(0.06))
	# the shrine
	b.box(Vector3(0, y + 0.2, 0), Vector3(0.62, 0.4, 0.55), Color8(0xe4, 0xd2, 0xa8))
	b.box(Vector3(0, y + 0.45, 0), Vector3(0.72, 0.1, 0.65), Color8(0xa8, 0x4a, 0x36))
	b.box(Vector3(0, y + 0.13, 0.28), Vector3(0.2, 0.26, 0.03), Color8(0x3a, 0x2a, 0x22))
	b.box(Vector3(0, y + 0.55, 0), Vector3(0.4, 0.12, 0.35), Color8(0x3c, 0x8a, 0x7a))


## A giant rubber duck, bobbing at the water line.
static func duck(b: Builder, p: Vector3) -> void:
	place(b, p, PI)   # built beak to -z; turned to face the camera
	b.prism(Vector3.ZERO, ngon(0.85, 12), -0.03, 0.02, FOAM)
	b.prism(Vector3(0, 0, 0.1), ngon(0.6, 9), -0.1, 0.42, DUCK, Vector2(0.85, 0.85))
	b.prism(Vector3(0, 0.3, 0.15), ngon(0.62, 9), 0, 0.2, DUCK.lightened(0.05), Vector2(0.75, 0.75))
	b.prism(Vector3(0, 0.0, 0.62), ngon(0.18, 6), 0.32, 0.55, DUCK, Vector2(0.5, 0.5), Vector2(0, 0.15))
	b.prism(Vector3(0, 0, -0.32), ngon(0.32, 8), 0.45, 0.9, DUCK, Vector2(1.05, 1.05))
	b.prism(Vector3(0, 0, -0.32), ngon(0.34, 8, 0.2), 0.9, 1.08, DUCK.lightened(0.06), Vector2(0.5, 0.5))
	b.prism(Vector3(0, 0, -0.68), pts([Vector2(-0.14, 0.12), Vector2(0.14, 0.12), Vector2(0.0, -0.18)]), 0.62, 0.72, Color8(0xff, 0x7a, 0x1e))
	for sx in [-0.17, 0.17]:
		b.box(Vector3(sx, 0.86, -0.6), Vector3(0.08, 0.1, 0.06), Color8(0x22, 0x22, 0x28))


## A city water tower: four legs, a red tank with a cone roof.
static func water_tower(b: Builder, p: Vector3) -> void:
	place(b, p, 0.0)
	for k in 4:
		var a := Vector3(cos(k * PI * 0.5 + PI * 0.25), 0, sin(k * PI * 0.5 + PI * 0.25)) * 0.42
		b.box(a + Vector3(0, 0.55, 0), Vector3(0.08, 1.3, 0.08), Color8(0x5a, 0x60, 0x6a))
	b.box(Vector3(0, 0.6, 0), Vector3(0.75, 0.05, 0.05), Color8(0x5a, 0x60, 0x6a))
	b.prism(Vector3.ZERO, ngon(0.6, 12), 1.15, 1.7, Color8(0xc8, 0x3c, 0x34))
	b.prism(Vector3.ZERO, ngon(0.62, 12), 1.38, 1.46, Color8(0xf4, 0xf0, 0xe6))
	b.prism(Vector3.ZERO, ngon(0.64, 12), 1.7, 1.98, Color8(0x8a, 0x2c, 0x28), Vector2(0.08, 0.08))


## A giant snowman: three snowballs, coal eyes, a carrot nose, a red scarf and a top hat.
static func snowman(b: Builder, p: Vector3, r: float) -> void:
	place(b, p, 0.0)
	var snow := Color8(0xf6, 0xfa, 0xfd)
	for ball in [[0.0, 0.62, 0.5], [0.62, 0.5, 0.42], [1.08, 0.38, 0.36]]:
		var y: float = ball[0]
		var rr: float = ball[1]
		b.prism(Vector3.ZERO, ngon(rr, 10), y, y + ball[2], snow, Vector2(0.62, 0.62))
		b.prism(Vector3.ZERO, ngon(rr * 0.62, 10, 0.3), y - 0.02, y + 0.05, snow.darkened(0.04))
	b.prism(Vector3(0, 0, 0), ngon(0.37, 10), 1.02, 1.14, Color8(0xd8, 0x34, 0x3a) if r < 0.5 else Color8(0x2e, 0x7a, 0xd0))
	b.box(Vector3(0.2, 0.98, 0.25), Vector3(0.1, 0.28, 0.06), Color8(0xd8, 0x34, 0x3a) if r < 0.5 else Color8(0x2e, 0x7a, 0xd0))
	b.octa(Vector3(0, 1.28, 0.36), 0.08, Color8(0xff, 0x8a, 0x22), Vector3(1, 1, 3.0))
	for sx in [-0.11, 0.11]:
		b.octa(Vector3(sx, 1.36, 0.3), 0.045, Color8(0x22, 0x22, 0x28))
	for k in 3:
		b.octa(Vector3(0, 0.75 + k * 0.14, 0.45 - k * 0.02), 0.04, Color8(0x22, 0x22, 0x28))
	b.prism(Vector3.ZERO, ngon(0.34, 10), 1.42, 1.46, Color8(0x22, 0x22, 0x28))
	b.prism(Vector3.ZERO, ngon(0.22, 10), 1.46, 1.8, Color8(0x22, 0x22, 0x28))
	b.prism(Vector3.ZERO, ngon(0.225, 10), 1.5, 1.56, Color8(0xd8, 0x34, 0x3a))


## A huge carved stone head, half sunk in the cinders, staring down the valley.
static func stone_head(b: Builder, p: Vector3) -> void:
	place(b, p, 0.0)
	var st := Color8(0x5a, 0x56, 0x58)
	b.box(Vector3(0, 0.55, 0), Vector3(0.8, 1.3, 0.7), st)
	b.box(Vector3(0, 1.26, -0.03), Vector3(0.84, 0.14, 0.74), st.darkened(0.15))   # brow of the cap
	b.box(Vector3(0, 0.98, 0.37), Vector3(0.7, 0.1, 0.08), st.darkened(0.2))        # heavy brow
	for sx in [-0.18, 0.18]:
		b.box(Vector3(sx, 0.86, 0.36), Vector3(0.16, 0.1, 0.03), Color8(0xff, 0x7a, 0x2a))   # glowing eyes
	b.prism(Vector3(0, 0, 0.4), pts([Vector2(-0.1, -0.05), Vector2(0.1, -0.05), Vector2(0.13, 0.12), Vector2(-0.13, 0.12)]), 0.5, 0.92, st.lightened(0.06), Vector2(0.6, 0.6))
	b.box(Vector3(0, 0.36, 0.37), Vector3(0.44, 0.08, 0.06), st.darkened(0.35))      # mouth
	for sx in [-0.43, 0.43]:
		b.box(Vector3(sx, 0.75, 0), Vector3(0.08, 0.5, 0.2), st.darkened(0.08))     # ears


## The city's colours (City builds the city) and its comically big cars.
const ASPHALT := Color8(0x34, 0x34, 0x38)
const KERB := Color8(0x74, 0x74, 0x76)
const PAINT := Color8(0xa8, 0xa4, 0x96)
const CARS := [Color8(0x7a, 0x3a, 0x34), Color8(0x8a, 0x7a, 0x44), Color8(0x3e, 0x52, 0x6a), Color8(0x8c, 0x8a, 0x86), Color8(0x4a, 0x5e, 0x46)]


## A little car, comically big like the rest: a coloured body, a glass cabin, dark wheels.
static func car(b: Builder, p: Vector3, ang: float, r: float, col := Color(0, 0, 0, 0)) -> void:
	count("car")
	place(b, p, ang)
	var c: Color = CARS[int(r * 997.0) % CARS.size()] if col.a == 0.0 else col
	b.box(Vector3(0, 0.1, 0), Vector3(0.42, 0.16, 0.82), c)
	b.box(Vector3(0, 0.25, 0.04), Vector3(0.36, 0.14, 0.42), c.lightened(0.08))
	for e in [[-0.181, -1.0], [0.261, 1.0]]:   # windscreen and rear window
		var z: float = e[0]
		b.quad(Vector3(-0.17, 0.2, z), Vector3(0.17, 0.2, z), Vector3(0.17, 0.3, z), Vector3(-0.17, 0.3, z), GLASS, Vector3(0, 0, e[1]))
	for sx in [-0.22, 0.22]:
		b.box(Vector3(sx, 0.05, 0), Vector3(0.05, 0.1, 0.66), Color8(0x24, 0x24, 0x2a))   # the wheels, one dark band a side


## The vertex-coloured material tinted (a world's colours on its bosses).
static func tinted(c: Color) -> Material:
	if c == Color(1, 1, 1):
		return mat()
	var key := "tint%s" % c.to_html()
	if not _cache.has(key):
		var m: StandardMaterial3D = mat().duplicate()
		m.albedo_color = c
		_cache[key] = m
	return _cache[key]


static func shot_mesh(r: float, stretch := 1.0) -> Mesh:
	return cached("shot%s_%s" % [r, stretch], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2 * stretch
		s.radial_segments = 6
		s.rings = 3
		return s)
