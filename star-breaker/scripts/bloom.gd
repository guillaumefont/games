class_name Bloom
## World 1's decor (Guillaume, 2026-11-22: "Let's keep bloom for the first world ... One decor per
## world"): the spore Bloom eating the moon, seen from above as a fungal canopy. Giant smooth caps
## at many heights with glowing gills, a dark floor threaded with glowing mycelium in the
## clearings, glowing pods, and spores drifting up. Canyon walls and islands are walls of the
## tallest caps, topped by the usual glowing lip on the exact collision edge.
##
## A chunk is the same strip of world as `Terrain`'s (x across the stage, y along it, z up, the
## floor at z = 0), built a little per frame by `Bloom.Builder` (same `step()` / `node` contract).
## Everything is MultiMesh: one draw for the caps, one for stems, one for pods, one for spores.

## Grid the caps are scattered on (one cap per cell, placed by the cell's own hash, so chunks agree).
const CELL := 17.0
## How far either side of the stage's middle the canopy reaches (wide screens see past the stage).
const REACH := 150.0
## Canopy tops above the floor: open ground, and the canyon walls' caps just under the play plane.
const TOP_LO := 14.0
const TOP_HI := 42.0

static var _cap: ArrayMesh
static var _stem: ArrayMesh
static var _pod: ArrayMesh
static var _mats := {}


static func h(x: float, y: float) -> float:
	return fposmod(sin(x * 127.1 + y * 311.7) * 43758.5453, 1.0)


## How open the canopy is at (x, wy): over 0.62 is a clearing where the floor shows.
static func openness(x: float, wy: float) -> float:
	return 0.5 + 0.28 * sin(x / 37.0 + sin(wy / 53.0) * 1.7) * sin(wy / 61.0 + x / 90.0) + 0.22 * sin(wy / 23.0 - x / 31.0) * 0.6


# ---------- meshes ----------

## A cap of radius 1 and height 1, z up: a smooth dome over a rounded rim, then the gills
## underneath curving in towards the stem. Smooth normals: no facet shows.
static func cap_mesh() -> ArrayMesh:
	if _cap:
		return _cap
	var prof := [[0.0, 1.0], [0.6, 0.94], [0.9, 0.76], [1.0, 0.46], [0.94, 0.26], [0.55, 0.24], [0.15, 0.3]]
	_cap = _lathe(prof, 14)
	return _cap


static func stem_mesh() -> ArrayMesh:
	if _stem:
		return _stem
	_stem = _lathe([[0.0, 1.0], [0.8, 1.0], [0.85, 0.5], [1.0, 0.0]], 7)
	return _stem


static func pod_mesh() -> ArrayMesh:
	if _pod:
		return _pod
	_pod = _lathe([[0.0, 1.0], [0.6, 0.85], [1.0, 0.5], [0.6, 0.15], [0.0, 0.0]], 8)
	return _pod


## Turns profile [radius, height] points round the z axis with smooth normals.
static func _lathe(prof: Array, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in prof.size() - 1:
		for j in seg:
			var a0 := TAU * j / seg
			var a1 := TAU * (j + 1) / seg
			var p := [Vector3(cos(a0) * prof[k][0], sin(a0) * prof[k][0], prof[k][1]), Vector3(cos(a1) * prof[k][0], sin(a1) * prof[k][0], prof[k][1]),
				Vector3(cos(a0) * prof[k + 1][0], sin(a0) * prof[k + 1][0], prof[k + 1][1]), Vector3(cos(a1) * prof[k + 1][0], sin(a1) * prof[k + 1][0], prof[k + 1][1])]
			for t in [[0, 1, 2], [1, 3, 2]]:
				for i in t:
					st.add_vertex(p[i])
	st.index()
	st.generate_normals()
	return st.commit()


# ---------- materials ----------

const CAP_SHADER := """
shader_type spatial;
varying vec3 lp;
varying vec3 top;
varying vec3 edge;
varying float seed;
vec3 lin(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}
void vertex() {
	lp = VERTEX;
	top = COLOR.rgb;
	edge = INSTANCE_CUSTOM.rgb;
	seed = INSTANCE_CUSTOM.a;
	if (!OUTPUT_IS_SRGB) {
		top = lin(top);
		edge = lin(edge);
	}
}
float hs(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	float u = lp.z;
	float r = length(lp.xy);
	vec3 c = mix(edge * 0.45, top, smoothstep(0.2, 0.85, u));
	// the crown is a touch lighter
	c *= 1.0 + 0.18 * smoothstep(0.6, 1.0, u);
	// pale spots on the crown, crisp-edged
	vec2 g = lp.xy * 3.2 + seed * 17.0;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5 - (vec2(hs(cell), hs(cell + 7.1)) - 0.5) * 0.4;
	float sr = 0.12 + 0.12 * hs(cell + 3.3);
	float d = length(f);
	float w = fwidth(d);
	float sp = (hs(cell + 9.7) > 0.72 && u > 0.5) ? 1.0 - smoothstep(sr - w, sr + w, d) : 0.0;
	c = mix(c, mix(top, vec3(1.0), 0.35), sp * 0.7);
	// fine grooves fanning out from the crown, crisp, fading towards it
	float ang = atan(lp.y, lp.x) / 6.2831853 * 22.0 + seed * 5.0;
	float gd = abs(fract(ang) - 0.5);
	float gw = fwidth(ang);
	float gr = (1.0 - smoothstep(0.06 - gw, 0.06 + gw, gd)) * smoothstep(0.92, 0.6, u) * step(0.2, u);
	c *= 1.0 - gr * 0.22;
	ALBEDO = c;
	ROUGHNESS = 0.6;
	SPECULAR = 0.3;
	// the gills glow under the rim; a thin bright line rings the rim
	float gill = 1.0 - smoothstep(0.2, 0.32, u);
	// a crisp glowing line round the rim: from above every cap reads as a cap, not a ball
	float wr = fwidth(r);
	float ring = smoothstep(0.93 - wr * 1.5, 0.93 + wr * 0.5, r) * step(0.3, u);
	EMISSION = edge * (gill * 1.2 + ring * 1.1) + top * sp * 0.2;
}
"""

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 base : source_color;
uniform vec3 vein : source_color;
vec2 h2(vec2 p) { p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
float edge(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x); vec2 mr = vec2(0.0); vec2 mg = vec2(0.0); float md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = vec2(float(i), float(j)); vec2 r = g + h2(n + g) - f; float d = dot(r, r);
		if (d < md) { md = d; mr = r; mg = g; } }
	md = 8.0;
	for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
		vec2 g = mg + vec2(float(i), float(j)); vec2 r = g + h2(n + g) - f;
		if (dot(r - mr, r - mr) > 0.0001) md = min(md, dot(0.5 * (mr + r), normalize(r - mr))); }
	return md;
}
void fragment() {
	// UV is the world position, so the mycelium runs on across chunks
	vec2 p = UV;
	float e = edge(p / 22.0) * 22.0;
	float w = fwidth(e);
	float l = 1.0 - smoothstep(0.08 - w, 0.08 + w, e);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + p.x * 0.05 + p.y * 0.04);
	ALBEDO = base;
	ROUGHNESS = 0.95;
	EMISSION = vein * l * 0.8 * pulse;
}
"""

const SPORE_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec3 col : source_color;
uniform float rise = 34.0;
void vertex() {
	// each mote drifts up its own column and starts again at the floor
	float ph = INSTANCE_CUSTOM.r;
	float sp = INSTANCE_CUSTOM.g;
	float z = mod(TIME * sp + ph * rise, rise);
	VERTEX *= smoothstep(0.0, 4.0, z) * (1.0 - smoothstep(rise - 6.0, rise, z));
	VERTEX.z += z;
	VERTEX.x += sin(TIME * 0.7 + ph * 6.3) * 1.5;
}
void fragment() {
	ALBEDO = col;
	EMISSION = col * 2.0;
}
"""


static func mats(pal: Dictionary) -> Dictionary:
	var key: String = pal.get("bloom_key", "w1")
	if _mats.has(key):
		return _mats[key]
	var m := {}
	var cs := Shader.new()
	cs.code = CAP_SHADER
	m.cap = ShaderMaterial.new()
	m.cap.shader = cs
	var fs := Shader.new()
	fs.code = FLOOR_SHADER
	m.floor = ShaderMaterial.new()
	m.floor.shader = fs
	m.floor.set_shader_parameter("base", Color(pal.get("floor", "0c0820")))
	m.floor.set_shader_parameter("vein", Color(pal.get("vein", "3ff0e0")))
	m.stem = StandardMaterial3D.new()
	m.stem.albedo_color = Color(pal.get("stem", "2a1a40"))
	m.stem.roughness = 0.9
	m.pod = StandardMaterial3D.new()
	m.pod.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.pod.vertex_color_use_as_albedo = true
	m.pod.albedo_color = Color(1.6, 1.6, 1.6)
	var ss := Shader.new()
	ss.code = SPORE_SHADER
	m.spore = ShaderMaterial.new()
	m.spore.shader = ss
	m.spore.set_shader_parameter("col", Color(pal.get("spore", "ffe0a0")))
	_mats[key] = m
	return m


# ---------- placing caps ----------

## The caps of the open canopy whose cells fall in world rows [wy0, wy1): [x, wy, radius, top, palette, seed].
## `clear` holds [x, wy, radius] circles kept free (props and fortress walls stand there).
static func canopy(wy0: float, wy1: float, pal: Dictionary, clear: Array) -> Array:
	var out := []
	var j0 := floori(wy0 / CELL)
	var j1 := ceili(wy1 / CELL)
	var npal: int = (pal.get("caps", [["5a2a78", "ff4fa3"]]) as Array).size()
	for j in range(j0, j1):
		for i in range(-ceili(REACH / CELL), ceili(REACH / CELL)):
			var hx := h(i, j)
			var hy := h(i + 0.37, j + 0.71)
			var x := (i + 0.15 + hx * 0.7) * CELL
			var wy := (j + 0.15 + hy * 0.7) * CELL
			if wy < wy0 or wy >= wy1:
				continue
			var op := openness(x, wy)
			var r := lerpf(10.5, 4.5, clampf((op - 0.3) / 0.4, 0.0, 1.0)) * (0.75 + 0.5 * h(i + 3.1, j))
			if op > 0.6 and h(i + 5.3, j) > 0.2:
				continue  # a clearing: the floor shows
			var free := true
			for cl in clear:
				if Vector2(x, wy).distance_to(Vector2(cl[0], cl[1])) < float(cl[2]) + r:
					free = false
					break
			if not free:
				continue
			var top := lerpf(TOP_HI, TOP_LO, clampf(op, 0.0, 1.0)) + (h(i, j + 9.0) - 0.5) * 10.0
			out.append([x, wy, r, top, int(h(i + 1.9, j + 4.2) * npal) % npal, h(i, j + 2.0)])
			# a smaller cap tucked against it now and then
			if h(i + 7.7, j) > 0.6:
				var a := h(i, j + 5.5) * TAU
				var r2 := r * (0.4 + 0.2 * h(i + 2.2, j))
				var p2 := Vector2(x, wy) + Vector2(cos(a), sin(a)) * (r + r2 * 0.4)
				if p2.y >= wy0 and p2.y < wy1:
					out.append([p2.x, p2.y, r2, top - r * 0.5, int(h(i + 4.4, j) * npal) % npal, h(i + 1.0, j)])
	return out


## Fills `mm` (custom data on) with caps given as [x, y, radius, top, palette, seed] in node space.
static func fill_caps(caps: Array, pal: Dictionary, stems: Array, key := "caps") -> MultiMesh:
	var cols: Array = pal.get(key, pal.get("caps", [["5a2a78", "ff4fa3"]]))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = cap_mesh()
	mm.instance_count = caps.size()
	for k in caps.size():
		var c: Array = caps[k]
		var r: float = c[2]
		var hh := r * (0.22 + 0.06 * float(c[5]))
		var b := Basis(Vector3.BACK, float(c[5]) * TAU).scaled(Vector3(r, r, hh))
		mm.set_instance_transform(k, Transform3D(b, Vector3(c[0], c[1], float(c[3]) - hh)))
		var pc: Array = cols[c[4] % cols.size()]
		# the low canopy sinks into the dark; the tall caps (walls, islands) keep their colour
		var dk := clampf((TOP_HI + 4.0 - float(c[3])) / (TOP_HI - TOP_LO + 8.0), 0.0, 1.0) * 0.55 if float(c[3]) > 0.0 else 0.0
		mm.set_instance_color(k, Color(pc[0]).darkened(dk))
		var e := Color(pc[1]).darkened(dk * 0.7)
		e.a = c[5]
		mm.set_instance_custom_data(k, e)
		stems.append([c[0], c[1], r * 0.2, float(c[3]) - hh * 0.5])
	return mm


static func fill_stems(stems: Array, z0: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stem_mesh()
	mm.instance_count = stems.size()
	for k in stems.size():
		var s: Array = stems[k]
		var len_: float = float(s[3]) - z0
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s[2], s[2], maxf(len_, 0.1))), Vector3(s[0], s[1], z0)))
	return mm


static func mm_node(mm: MultiMesh, m: Material, shadows: bool) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A wall of the tallest caps on side `s` (-1: the rock lies towards -x) of `edge` points
## (node space, y rising, z = 0 at the cliff top), never past the edge: each disc stays on the
## rock side of every edge point it spans. Rows run back from the edge out to `depth`, each a
## little lower and wider than the last.
static func wall(edge: Array, s: float, wy0: float, pal: Dictionary, depth := 110.0) -> Array:
	var caps := []
	var npal: int = (pal.get("caps", [[]]) as Array).size()
	var y_lo: float = (edge[0] as Vector3).y
	var y_hi: float = (edge[edge.size() - 1] as Vector3).y
	var off := 0.0
	var row := 0
	while off < depth:
		var rr := (5.5 + row * 2.2)
		var y := y_lo + (h(wy0, row + s) - 0.5) * rr
		while y < y_hi:
			var r := rr * (0.85 + 0.3 * h(wy0 + y, row + s))
			# the edge's furthest reach into the canyon over the disc's span
			var ext := INF if s < 0.0 else -INF
			for e: Vector3 in edge:
				if absf(e.y - y) <= r:
					ext = minf(ext, e.x) if s < 0.0 else maxf(ext, e.x)
			if is_finite(ext):
				var x := ext + s * (off + r)
				var top := -row * 2.2 - h(wy0 + y, row * 3.0 - s) * 1.5
				caps.append([x, y, r, top, int(h(wy0 + y + 3.0, row + s * 5.0) * npal) % npal, h(wy0 + y, row * 7.0 + s)])
			y += r * 1.45
		off += rr * 1.3
		row += 1
	return caps


# ---------- the chunk builder ----------

class Builder:
	var c: int
	var len: float
	var pal: Dictionary
	var clear: Array
	var node := Node3D.new()
	var y0: float
	var _t := 0
	var _caps := []

	func _init(c_: int, len_: float, pal_: Dictionary, clear_: Array) -> void:
		c = c_
		len = len_
		pal = pal_
		clear = clear_
		y0 = c * len
		node.name = "Bloom%d" % c

	## One piece per call: the floor, the caps' placing, then each MultiMesh.
	func step() -> bool:
		var m: Dictionary = Bloom.mats(pal)
		match _t:
			0:
				var q := PlaneMesh.new()
				q.size = Vector2(Bloom.REACH * 2.0 + 40.0, len)
				q.orientation = PlaneMesh.FACE_Z
				var arr := q.get_mesh_arrays()
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var uv := PackedVector2Array()
				for p in v:
					uv.append(Vector2(p.x, y0 + p.y + len / 2.0))
				arr[Mesh.ARRAY_TEX_UV] = uv
				var am := ArrayMesh.new()
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				var mi := MeshInstance3D.new()
				mi.mesh = am
				mi.material_override = m.floor
				mi.position.y = len / 2.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(mi)
			1:
				var local := []
				for cl in clear:
					local.append([cl[0], cl[1] - y0, cl[2]])
				for k in Bloom.canopy(y0, y0 + len, pal, clear):
					k[1] -= y0
					_caps.append(k)
			2:
				var stems := []
				# the low canopy casts no shadow (it halves its cost); the walls' caps do
				node.add_child(Bloom.mm_node(Bloom.fill_caps(_caps, pal, stems), m.cap, false))
				node.add_child(Bloom.mm_node(Bloom.fill_stems(stems, 0.0), m.stem, false))
			3:
				_pods(m)
			_:
				return true
		_t += 1
		return false

	## Glowing pods on the floor of the clearings, and spores rising out of them.
	func _pods(m: Dictionary) -> void:
		var pods := []
		var spores := []
		var cols: Array = pal.get("pods", ["3ff0e0", "ff7ac0"])
		var n := 0
		while n < 30:
			var x := (Bloom.h(c + n * 0.31, 1.0) - 0.5) * Bloom.REACH * 2.0
			var ly := Bloom.h(c + n * 0.53, 2.0) * len
			n += 1
			if Bloom.openness(x, y0 + ly) < 0.6:
				continue
			for k in 5:
				var a := Bloom.h(x + k, ly) * TAU
				var d := Bloom.h(ly + k, x) * 4.0
				pods.append([x + cos(a) * d, ly + sin(a) * d, 0.6 + Bloom.h(x, k + ly) * 1.1, cols[k % cols.size()]])
			for k in 3:
				spores.append([x + (Bloom.h(x, k) - 0.5) * 10.0, ly + (Bloom.h(ly, k) - 0.5) * 10.0, Bloom.h(x + k, ly + k), 2.0 + Bloom.h(k, x) * 3.0])
		if pods.size() > 0:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = Bloom.pod_mesh()
			mm.instance_count = pods.size()
			for k in pods.size():
				var p: Array = pods[k]
				var s: float = p[2]
				mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(s, s, s * 1.4)), Vector3(p[0], p[1], 0)))
				mm.set_instance_color(k, Color(p[3]))
			node.add_child(Bloom.mm_node(mm, m.pod, false))
		if spores.size() > 0:
			var sm := MultiMesh.new()
			sm.transform_format = MultiMesh.TRANSFORM_3D
			sm.use_custom_data = true
			sm.mesh = Bloom.pod_mesh()
			sm.instance_count = spores.size()
			for k in spores.size():
				var p: Array = spores[k]
				sm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * 0.35), Vector3(p[0], p[1], 0)))
				sm.set_instance_custom_data(k, Color(p[2], p[3], 0, 0))
			var si := Bloom.mm_node(sm, m.spore, false)
			si.custom_aabb = AABB(Vector3(-Bloom.REACH, -10, -5), Vector3(Bloom.REACH * 2.0, len + 20, 50))
			node.add_child(si)
