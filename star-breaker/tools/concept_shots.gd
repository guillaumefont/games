extends SceneTree
## Concept stills for a new world 1 look (Guillaume, 2026-11-22: "forget everything about the
## current and suggest something new"). Each concept is a small standalone scene seen through the
## game's own top-down camera (CAM_D, the 126-unit stage width, floor 68 under the play plane),
## with Lance on the play plane for scale. Nothing here touches the game.
## xvfb-run -a -s "-screen 0 1100x2400x24" godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/concept_shots.gd -- OUT_DIR [names]

const CAM_D := 215.0
const FLOOR := -68.0
var out := "user://concepts"
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	Models.init()
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var only: Array = Array(args[1].split(",", false)) if args.size() > 1 else []
	DirAccess.make_dir_recursive_absolute(out)
	for n in ["canopy", "islands", "glass", "toon"]:
		if only.is_empty() or n in only:
			await shot(n)
	quit()


func shot(name: String) -> void:
	rng.seed = 7
	var w := Node3D.new()
	root.add_child(w)
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = rad_to_deg(2.0 * atan(63.0 / CAM_D))
	cam.far = 2000.0
	w.add_child(cam)
	cam.position = Vector3(0, 0, CAM_D)
	cam.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, 1.0 if i in [2, 3, 4] else 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = CAM_D + 300.0
	sun.shadow_bias = 0.05
	sun.shadow_opacity = 0.85
	w.add_child(sun)
	sun.look_at_from_position(Vector3(-70, 85, 150), Vector3.ZERO)
	call("_" + name, w, env, sun)
	# Lance on the play plane, firing
	var ship := VShips.upright(VShips.model("lance"))
	ship.add_child(Models.glow("ff9a40", 8))
	w.add_child(ship)
	ship.position = Vector3(0, -62, 0)
	for k in 4:
		for s in [-1.0, 1.0]:
			var b := MeshInstance3D.new()
			var q := CapsuleMesh.new()
			q.radius = 0.7
			q.height = 5.0
			b.mesh = q
			b.material_override = Models.glow_mat("6ff3e6")
			w.add_child(b)
			b.position = Vector3(s * 2.2, -50 + k * 16, 0)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)
	w.queue_free()
	await process_frame


# ---------- helpers ----------

func mat(src: String, params := {}) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = src
	var m := ShaderMaterial.new()
	m.shader = sh
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


func std(c: Color, rough := 0.8, metal := 0.0, e := Color.BLACK, ei := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if ei > 0.0:
		m.emission_enabled = true
		m.emission = e
		m.emission_energy_multiplier = ei
	return m


## A node whose local y is the world's z (up out of the ground), so Godot's y-up primitives stand up.
func up(w: Node3D, mesh: Mesh, m: Material, p: Vector3, s: Vector3, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	w.add_child(mi)
	mi.position = p
	mi.basis = Basis(Vector3.BACK, yaw) * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(s)
	return mi


func sphere(seg := 48) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = seg
	s.rings = seg / 2
	return s


func plane(w: Node3D, m: Material, z: float, size := Vector2(420, 700), sub := 1) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = size
	p.subdivide_width = sub
	p.subdivide_depth = sub
	return up(w, p, m, Vector3(0, 60, z), Vector3.ONE)


## A smooth rock lump: a sphere pushed out by noise, flattened on top and drawn to a point below
## (`kind` "island"), or squashed into a rounded mesa ("mesa").
func lump(r: float, kind: String, seed_: int) -> ArrayMesh:
	var nz := FastNoiseLite.new()
	nz.seed = seed_
	nz.frequency = 0.9
	nz.fractal_octaves = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 40
	var segs := 64
	var pts := []
	for i in rings + 1:
		var v := float(i) / rings
		var phi := v * PI
		var row := []
		for j in segs + 1:
			var th := float(j) / segs * TAU
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var rr := 1.0 + nz.get_noise_3dv(d * 1.3) * 0.28
			var p := d * rr
			if kind == "island":
				if p.y > 0.25:
					p.y = 0.25 + (p.y - 0.25) * 0.12
				else:
					var k := clampf(-p.y, 0.0, 1.0)
					p.x *= 1.0 - k * 0.75
					p.z *= 1.0 - k * 0.75
					p.y = 0.25 + (p.y - 0.25) * 1.7
			elif kind == "mesa":
				p.y = clampf(p.y * 1.6, -1.0, 0.55 + nz.get_noise_2d(p.x * 2.0, p.z * 2.0) * 0.08)
			row.append(p * r)
		pts.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j + 1]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][j + 1]
			st.add_vertex(a)
			st.add_vertex(d)
			st.add_vertex(b)
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(d)
	st.index()
	st.generate_normals()
	return st.commit()


# ---------- 1. Bloom canopy ----------

const CAP := """
shader_type spatial;
uniform vec3 top : source_color;
uniform vec3 edge : source_color;
uniform vec3 spot : source_color;
uniform float glow = 2.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void fragment() {
	float u = clamp(lp.y, -1.0, 1.0);
	vec3 c = mix(edge * 0.6, top, smoothstep(0.0, 0.6, u));
	// pale spots on the cap, crisp-edged
	vec3 g = lp * 3.5;
	vec3 cell = floor(g);
	vec3 f = fract(g) - 0.5;
	float r = 0.18 + 0.14 * h(cell);
	float s = (h(cell + 3.1) > 0.55 && u > 0.2) ? 1.0 - smoothstep(r - fwidth(length(f)), r + fwidth(length(f)), length(f)) : 0.0;
	ALBEDO = mix(c, spot, s * 0.85);
	ROUGHNESS = 0.45;
	SPECULAR = 0.6;
	// the gills glow under the rim
	float rim = 1.0 - smoothstep(0.0, 0.18, u);
	EMISSION = edge * rim * glow + spot * s * 0.35;
}
"""

const MYCEL := """
shader_type spatial;
uniform vec3 base : source_color;
uniform vec3 vein : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
vec2 h2(vec2 p) { p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
float edge(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x); vec2 mr; float md = 8.0; vec2 mg;
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
	float e = edge(wp.xy / 18.0) * 18.0;
	float w = fwidth(e);
	float l = 1.0 - smoothstep(0.12 - w, 0.12 + w, e);
	float l2 = edge(wp.xy / 3.0 + 7.0) * 3.0;
	float w2 = fwidth(l2);
	float fine = 1.0 - smoothstep(0.05 - w2, 0.05 + w2, l2);
	ALBEDO = base;
	ROUGHNESS = 0.9;
	EMISSION = vein * (l * 1.2 + fine * 0.15);
}
"""


func _canopy(w: Node3D, env: Environment, sun: DirectionalLight3D) -> void:
	env.background_color = Color("06030f")
	env.ambient_light_color = Color("3a2a8a")
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("0a0620")
	env.fog_density = 0.0
	env.fog_depth_curve = 1.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = CAM_D + 20.0
	env.fog_depth_end = CAM_D + 120.0
	sun.light_color = Color("ffc8b0")
	sun.light_energy = 1.1
	plane(w, mat(MYCEL, {base = Color("0c0820"), vein = Color("3ff0e0")}), FLOOR, Vector2(420, 700), 0)
	var caps := [
		[Color("5a2a78"), Color("ff4fa3"), Color("ffb0e0")],
		[Color("3a2a7a"), Color("8f6bff"), Color("c8b8ff")],
		[Color("4a2060"), Color("ff7ac0"), Color("ffd0ee")],
		[Color("1e3a6a"), Color("3ff0e0"), Color("b0fff4")],
	]
	var sm := sphere(64)
	var mats := []
	for c in caps:
		mats.append(mat(CAP, {top = c[0], edge = c[1], spot = c[2], glow = 1.6}))
	var stem := std(Color("2a1a40"), 0.9)
	var placed := []
	for n in 2500:
		var x := rng.randf_range(-110, 110)
		var y := rng.randf_range(-170, 300)
		# the canyon: a winding clearing down the middle of the screen
		var cx := sin(y / 70.0) * 22.0
		var half := 26.0 + sin(y / 45.0) * 6.0
		var inside := absf(x - cx) < half
		var r := rng.randf_range(6.0, 16.0) if not inside else rng.randf_range(2.5, 5.0)
		if inside and rng.randf() > 0.12:
			continue
		var ok := true
		for q in placed:
			if Vector2(x, y).distance_to(q[0]) < (r + q[1]) * 0.72:
				ok = false
				break
		if not ok:
			continue
		placed.append([Vector2(x, y), r])
		var z := FLOOR + (rng.randf_range(16, 40) if not inside else rng.randf_range(3, 10)) + r * 0.3
		var m: Material = mats[rng.randi() % mats.size()]
		up(w, sm, m, Vector3(x, y, z), Vector3(r, r * rng.randf_range(0.22, 0.32), r), rng.randf() * TAU)
		var cy := CylinderMesh.new()
		cy.top_radius = 0.18
		cy.bottom_radius = 0.28
		cy.height = 2.0
		up(w, cy, stem, Vector3(x, y, (z + FLOOR) / 2.0), Vector3(r, (z - FLOOR) / 2.0, r))
	# spores drifting up through the clearing
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sp := SphereMesh.new()
	sp.radius = 0.35
	sp.height = 0.7
	sp.radial_segments = 8
	sp.rings = 4
	mm.mesh = sp
	mm.instance_count = 260
	for i in mm.instance_count:
		var s := rng.randf_range(0.5, 1.6)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), Vector3(rng.randf_range(-90, 90), rng.randf_range(-150, 280), rng.randf_range(FLOOR + 5, -6))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Models.glow_mat("ffe0a0")
	w.add_child(mmi)


# ---------- 2. Floating islands ----------

const CLOUDS := """
shader_type spatial;
render_mode unshaded;
uniform vec3 deep : source_color;
uniform vec3 mid : source_color;
uniform vec3 hi : source_color;
uniform float sc = 60.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hs(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hs(i), hs(i + vec2(1, 0)), f.x), mix(hs(i + vec2(0, 1)), hs(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 5; i++) { s += a * vn(p); p *= 2.03; a *= 0.5; } return s; }
void fragment() {
	float v = fbm(wp.xy / sc);
	// banded, crisp cloud tops: three tones with a hard edge, a lit rim on each step
	float w = fwidth(v) * 1.2;
	float b1 = smoothstep(0.47 - w, 0.47 + w, v);
	float b2 = smoothstep(0.58 - w, 0.58 + w, v);
	vec3 c = mix(deep, mid, b1);
	c = mix(c, hi, b2);
	ALBEDO = c;
}
"""


func _islands(w: Node3D, env: Environment, sun: DirectionalLight3D) -> void:
	env.background_color = Color("140c38")
	env.ambient_light_color = Color("5a4ab8")
	env.ambient_light_energy = 0.7
	sun.light_color = Color("ffd0a8")
	sun.light_energy = 1.4
	plane(w, mat(CLOUDS, {deep = Color("120c40"), mid = Color("1e1658"), hi = Color("2c2070"), sc = 90.0}), -260.0, Vector2(900, 1400))
	plane(w, mat(CLOUDS.replace("render_mode unshaded;", "render_mode unshaded, blend_mix;").replace("ALBEDO = c;", "ALBEDO = c; ALPHA = b1;"),
			{deep = Color("3a2c88"), mid = Color("5a48b0"), hi = Color("9a80e0"), sc = 70.0}), -140.0, Vector2(700, 1100))
	var top := Color("8a5cd0")
	var rock := std(Color("3a2a70"), 0.85)
	var grass := mat("""
shader_type spatial;
uniform vec3 top : source_color;
uniform vec3 side : source_color;
uniform vec3 lit : source_color;
varying vec3 ln;
void vertex() { ln = NORMAL; }
void fragment() {
	float u = ln.y;
	float w = fwidth(u);
	float t = smoothstep(0.55 - w, 0.55 + w, u);
	ALBEDO = mix(side, top, t);
	EMISSION = lit * t * 0.08;
	ROUGHNESS = 0.8;
}
""", {top = top, side = Color("2e2264"), lit = Color("ffb0e0")})
	var isles := [[-58, 150, -40, 22], [52, 95, -55, 26], [-48, 20, -48, 18], [60, -40, -35, 20], [-62, -110, -60, 24],
		[40, 230, -70, 16], [-10, 280, -95, 14], [10, 60, -120, 12], [-20, -40, -150, 16], [70, 330, -40, 20]]
	for i in isles.size():
		var d: Array = isles[i]
		var mi := up(w, lump(1.0, "island", 30 + i), grass, Vector3(d[0], d[1], d[2]), Vector3.ONE * float(d[3]), rng.randf() * TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# a few crystals and rocks on top
		for k in 3:
			var cr := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.top_radius = 0.0
			cy.bottom_radius = 1.0
			cy.height = 4.0
			cy.radial_segments = 6
			cr.mesh = cy
			cr.material_override = Models.glow_mat("ff7ac0") if k == 0 else std(Color("6ff3e6"), 0.3, 0.0, Color("2fd6c8"), 0.6)
			mi.add_child(cr)
			cr.position = Vector3(rng.randf_range(-0.5, 0.5), 0.35, rng.randf_range(-0.5, 0.5))
			cr.scale = Vector3.ONE * rng.randf_range(0.06, 0.11)
			cr.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
	var _r := rock


# ---------- 3. Black glass ----------

const GLASS := """
shader_type spatial;
uniform vec3 vein : source_color;
varying vec3 wp;
float hs(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hs(i), hs(i + vec2(1, 0)), f.x), mix(hs(i + vec2(0, 1)), hs(i + vec2(1, 1)), f.x), f.y); }
float fbm(vec2 p) { float a = 0.5; float s = 0.0; for (int i = 0; i < 4; i++) { s += a * vn(p); p *= 2.1; a *= 0.5; } return s; }
float hgt(vec2 p) { return (vn(p / 60.0) * 0.75 + vn(p / 23.0) * 0.25) * 26.0; }
void vertex() {
	vec3 w0 = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += hgt(w0.xy);
	float e = 0.5;
	float hx = hgt(w0.xy + vec2(e, 0.0)) - hgt(w0.xy - vec2(e, 0.0));
	float hy = hgt(w0.xy + vec2(0.0, e)) - hgt(w0.xy - vec2(0.0, e));
	// plane's local x = world x, local z = world -y (it is stood up by a quarter turn)
	NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, hy / (2.0 * e)));
	wp = w0;
}
void fragment() {
	ALBEDO = vec3(0.012, 0.01, 0.03);
	METALLIC = 0.0;
	ROUGHNESS = 0.18;
	SPECULAR = 1.0;
	// thin glowing veins along ridged noise lines
	float r = abs(vn(wp.xy / 55.0 + 5.0) * 0.8 + vn(wp.xy / 21.0) * 0.2 - 0.5);
	float w = fwidth(r);
	float l = 1.0 - smoothstep(0.008 - w, 0.008 + w, r);
	EMISSION = vein * l * 2.4;
}
"""


func _glass(w: Node3D, env: Environment, sun: DirectionalLight3D) -> void:
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("2a1060")
	sm.sky_horizon_color = Color("ff6ab0")
	sm.ground_bottom_color = Color("140830")
	sm.ground_horizon_color = Color("ff6ab0")
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_color = Color("2a1a5a")
	env.ambient_light_energy = 0.5
	sun.light_color = Color("ffb0d0")
	sun.light_energy = 1.6
	plane(w, mat(GLASS, {vein = Color("3ff0e0")}), FLOOR - 6.0, Vector2(420, 700), 220)
	var crys := [std(Color("ff5ab0"), 0.15, 0.2, Color("ff2f8f"), 0.9), std(Color("8f6bff"), 0.15, 0.2, Color("6a4aff"), 0.7),
		std(Color("101018"), 0.05, 0.6)]
	for n in 26:
		var x := rng.randf_range(-100, 100)
		var y := rng.randf_range(-160, 300)
		if absf(x - sin(y / 70.0) * 20.0) < 30.0:
			continue
		var base := Vector3(x, y, FLOOR + 2.0)
		for k in rng.randi_range(3, 7):
			var cy := CylinderMesh.new()
			cy.top_radius = 0.0
			cy.bottom_radius = 1.0
			cy.height = 2.0
			cy.radial_segments = 6
			cy.rings = 1
			var s := rng.randf_range(2.0, 6.0)
			var mi := up(w, cy, crys[rng.randi() % crys.size()], base + Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), s * 1.5),
					Vector3(s * 0.45, s * rng.randf_range(1.6, 3.2), s * 0.45), rng.randf() * TAU)
			mi.basis = Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0).normalized(), rng.randf_range(0.1, 0.5)) * mi.basis


# ---------- 4. Toon diorama ----------

const TOON := """
shader_type spatial;
uniform vec3 col : source_color;
uniform vec3 shade : source_color;
void fragment() { ALBEDO = col; }
void light() {
	float l = dot(NORMAL, LIGHT) * ATTENUATION;
	float w = fwidth(l) + 0.001;
	float b = smoothstep(0.02 - w, 0.02 + w, l) * 0.55 + smoothstep(0.55 - w, 0.55 + w, l) * 0.45;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shade * 0.6, vec3(1.0), b) * b;
}
"""

const INK := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float t = 0.5;
void vertex() { VERTEX += NORMAL * t; }
void fragment() { ALBEDO = vec3(0.09, 0.05, 0.16); }
"""


func toon_mi(w: Node3D, mesh: Mesh, c: Color, p: Vector3, s: Vector3, yaw := 0.0, ink := 0.04) -> MeshInstance3D:
	var mi := up(w, mesh, mat(TOON, {col = c, shade = Color("8a6ad0")}), p, s, yaw)
	var o := MeshInstance3D.new()
	o.mesh = mesh
	o.material_override = mat(INK, {t = ink})
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(o)
	return mi


func _toon(w: Node3D, env: Environment, sun: DirectionalLight3D) -> void:
	env.background_color = Color("b8a8f0")
	env.ambient_light_color = Color("7a6ad8")
	env.ambient_light_energy = 0.45
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sun.light_color = Color("fff0e0")
	sun.light_energy = 0.9
	sun.shadow_opacity = 1.0
	var gp := PlaneMesh.new()
	gp.size = Vector2(420, 700)
	var g := up(w, gp, mat(TOON, {col = Color("b49ae8"), shade = Color("8a6ad0")}), Vector3(0, 60, FLOOR), Vector3.ONE)
	var _g := g
	var cols := [Color("ff9ab8"), Color("ffb8a0"), Color("f0a0e0"), Color("a0e8d8")]
	for n in 140:
		var x := rng.randf_range(-110, 110)
		var y := rng.randf_range(-170, 300)
		if absf(x - sin(y / 70.0) * 22.0) < 34.0 and rng.randf() > 0.15:
			continue
		var r := rng.randf_range(10, 24) if absf(x - sin(y / 70.0) * 22.0) > 40.0 else rng.randf_range(3, 7)
		var kind := "mesa" if r > 7.0 else "island"
		var m := lump(1.0, kind, n)
		var mi := toon_mi(w, m, cols[rng.randi() % cols.size()], Vector3(x, y, FLOOR + r * (0.5 if kind == "mesa" else 0.1)),
				Vector3(r, r * (0.9 if kind == "mesa" else 0.6), r), rng.randf() * TAU, 0.05)
		if kind == "island":
			mi.basis = mi.basis * Basis(Vector3.RIGHT, PI)
	# arches over the clearing
	for a in [[-12.0, 40.0], [18.0, 200.0]]:
		var t := TorusMesh.new()
		t.inner_radius = 0.72
		t.outer_radius = 1.0
		t.rings = 64
		t.ring_segments = 24
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = mat(TOON, {col = Color("ffb8a0"), shade = Color("8a6ad0")})
		var o := MeshInstance3D.new()
		o.mesh = t
		o.material_override = mat(INK, {t = 0.04})
		mi.add_child(o)
		w.add_child(mi)
		mi.position = Vector3(a[0], a[1], FLOOR)
		mi.basis = Basis(Vector3.BACK, 0.3) * Basis.from_scale(Vector3.ONE * 26.0)
