extends RefCounted
## Premium ground (graphics levels above Classic, see gfx.gd): one smooth terrain mesh painted per pixel.
## Grass, soil, sand, rock and ore ground blend with soft, slightly wavy borders and a thin darker rim on the grass
## side; steep slopes turn to cliff; the ground darkens where it is wet and under the water; buildings leave a soft
## contact shadow. Preload it (no class_name, so the self-update pack can carry it).

const SPLAT_RES := 4     # splat and contact shadow pixels per tile
const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D splat : filter_linear, repeat_disable;     // R soil, G sand, B rock, A ore ground (map uv)
uniform sampler2D occ_tex : filter_linear, repeat_disable;   // contact shadow under buildings (map uv)
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec2 map_size = vec2(64.0, 64.0);
uniform vec3 c_grass : source_color;
uniform vec3 c_gvar;
uniform vec3 c_dirt : source_color;
uniform vec3 c_sand : source_color;
uniform vec3 c_rock : source_color;
uniform vec3 c_cliff : source_color;
uniform vec3 c_bed : source_color;
uniform vec3 c_ore : source_color;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float band(float x) { return smoothstep(0.30, 0.46, x) * (1.0 - smoothstep(0.47, 0.56, x)); }
void fragment() {
	vec2 uv = wp.xz / map_size;
	float f = texture(fog_tex, wp.xz / 64.0).r;
	float n1 = texture(noise, wp.xz * 0.031).r;
	float n2 = texture(noise, wp.xz * 0.19 + vec2(0.37, 0.11)).r;
	float n3 = texture(noise, wp.xz * 0.83 + vec2(0.7, 0.2)).r;
	vec4 sp = texture(splat, uv);
	float wob = (n2 - 0.5) * 0.42;
	// grass: big soft patches, a faint fine grain
	vec3 col = (c_grass + c_gvar * (n1 - 0.5) * 2.2) * (0.97 + 0.06 * n3);
	float rim = 0.0;
	float wd = smoothstep(0.46, 0.53, sp.r + wob); rim = max(rim, band(sp.r + wob));
	col = mix(col, c_dirt * (0.93 + 0.12 * n3), wd);
	float ws = smoothstep(0.46, 0.53, sp.g + wob); rim = max(rim, band(sp.g + wob) * 0.6);
	col = mix(col, c_sand * (0.95 + 0.08 * n3), ws);
	float wo = smoothstep(0.44, 0.54, sp.a + wob * 0.7);
	col = mix(col, c_ore * (0.92 + 0.14 * n3), wo);
	float wr = smoothstep(0.46, 0.53, sp.b + wob * 0.8); rim = max(rim, band(sp.b + wob * 0.8));
	col = mix(col, c_rock * (0.88 + 0.22 * n2) * (0.9 + 0.12 * clamp(wp.y, 0.0, 2.0)), wr);
	col *= 1.0 - 0.16 * rim * (1.0 - wr);
	// steep ground is cliff, with soft horizontal strata
	float cl = 1.0 - smoothstep(0.62, 0.8, wn.y);
	float strata = 0.88 + 0.12 * sin(wp.y * 9.0 + n2 * 3.0);
	col = mix(col, c_cliff * strata * (0.9 + 0.15 * n3), cl);
	// wet ground at the bank, then the river bed
	float wet = smoothstep(-0.03, -0.14, wp.y);
	col = mix(col, mix(col, c_sand * 0.9, 0.5) * 0.78, wet);
	col = mix(col, c_bed, smoothstep(-0.12, -0.6, wp.y));
	// contact shadow under and around buildings
	col *= 1.0 - 0.42 * texture(occ_tex, uv).r;
	// same hemisphere and drifting cloud shade as the models (Models.LOOK)
	float hemi = mix(0.8, 1.04, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
	vec2 q = wp.xz * 0.075 + vec2(TIME * 0.022, TIME * 0.013);
	float c = sin(q.x * 1.7 + sin(q.y * 1.3) * 1.6) * sin(q.y * 1.9 + sin(q.x * 0.8) * 1.4);
	float cloud = 1.0 - 0.12 * smoothstep(-0.1, 0.8, c);
	ALBEDO = col * 0.8 * f * hemi * cloud;
	ROUGHNESS = mix(0.95, 0.4, wet * (1.0 - smoothstep(-0.2, -0.3, wp.y)));
	SPECULAR = 0.12 + 0.25 * wet;
}
"""

static var _noise: ImageTexture

static func noise_tex() -> ImageTexture:
	if _noise == null:
		var fn := FastNoiseLite.new(); fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; fn.frequency = 0.02
		fn.fractal_octaves = 3; fn.seed = 7
		var img := fn.get_seamless_image(256, 256, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8); img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise

## Theme colours as the shader wants them (linear), calmed the same way the classic ground was (less saturated grass).
static func _c(a: Array, desat := 0.0) -> Color:
	var c := Color(a[0], a[1], a[2])
	if desat > 0.0:
		var l := c.r * .3 + c.g * .59 + c.b * .11
		c = c.lerp(Color(l, l, l), desat)
	return c

## Builds the terrain for the current map: a smooth mesh over the height grid and its material.
static func build(S, fog_tex: Texture2D, MW: int, MH: int, HN: int) -> MeshInstance3D:
	var TH: Dictionary = D.THEMES[S.theme]
	var H: PackedFloat32Array = S.H
	var verts := PackedVector3Array(); verts.resize(HN * HN)
	var norms := PackedVector3Array(); norms.resize(HN * HN)
	for j in HN:
		for i in HN:
			var k := j * HN + i
			verts[k] = Vector3(i / 2.0, H[k], j / 2.0)
			var hl: float = H[k - 1] if i > 0 else H[k]; var hr: float = H[k + 1] if i < HN - 1 else H[k]
			var hu: float = H[k - HN] if j > 0 else H[k]; var hd: float = H[k + HN] if j < HN - 1 else H[k]
			var dx := (2.0 if i > 0 and i < HN - 1 else 1.0) / 2.0; var dz := (2.0 if j > 0 and j < HN - 1 else 1.0) / 2.0
			norms[k] = Vector3((hl - hr) / dx, 1.0, (hu - hd) / dz).normalized()
	var idx := PackedInt32Array()
	for j in HN - 1:
		for i in HN - 1:
			var a := j * HN + i; var b := a + 1; var c := a + HN; var d := c + 1
			# split along the flatter diagonal so ridges and banks keep their shape (clockwise for Godot)
			if absf(H[a] - H[d]) < absf(H[b] - H[c]): idx.append_array([a, b, d, a, d, c])
			else: idx.append_array([a, b, c, b, d, c])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new(); sh.code = SHADER
	var m := ShaderMaterial.new(); m.shader = sh
	m.set_shader_parameter("fog_tex", fog_tex)
	m.set_shader_parameter("noise", noise_tex())
	m.set_shader_parameter("map_size", Vector2(MW, MH))
	m.set_shader_parameter("splat", ImageTexture.create_from_image(splat_image(S, MW, MH)))
	m.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ_image(S, MW, MH)))
	m.set_shader_parameter("c_grass", _c(TH.grass, 0.12))
	m.set_shader_parameter("c_gvar", Vector3(TH.gvar[0], TH.gvar[1], TH.gvar[2]) * 0.6)
	m.set_shader_parameter("c_dirt", _c(TH.dirt) * Color(0.86, 0.82, 0.8)); m.set_shader_parameter("c_sand", _c(TH.sand))
	m.set_shader_parameter("c_rock", _c(TH.rock)); m.set_shader_parameter("c_cliff", _c(TH.cliff))
	m.set_shader_parameter("c_bed", _c(TH.bed)); m.set_shader_parameter("c_ore", _c(TH.dirt).lerp(Color(0.5, 0.4, 0.24), 0.6))
	am.surface_set_material(0, m)
	var mi := MeshInstance3D.new(); mi.mesh = am; mi.name = "ground"
	return mi

## Terrain kinds as soft weights, SPLAT_RES pixels per tile: R soil, G sand (and shore), B rock, A ore ground.
static func splat_image(S, MW: int, MH: int) -> Image:
	var img := Image.create(MW, MH, false, Image.FORMAT_RGBA8)
	for ty in MH:
		for tx in MW:
			var i := ty * MW + tx; var t: int = S.terr[i]
			img.set_pixel(tx, ty, Color(1.0 if t == D.DIRT else 0.0, 1.0 if t == D.SAND or t == D.WATER else 0.0, 1.0 if t == D.ROCK else 0.0, 1.0 if S.ore[i] > 0 else 0.0))
	img.resize(MW * SPLAT_RES, MH * SPLAT_RES, Image.INTERPOLATE_CUBIC)
	return img

## Soft shadow around building footprints (S.bmap), SPLAT_RES pixels per tile.
static func occ_image(S, MW: int, MH: int) -> Image:
	var R := SPLAT_RES
	var W := MW * R; var Hh := MH * R
	var a := PackedFloat32Array(); a.resize(W * Hh)
	for ty in MH:
		for tx in MW:
			if S.bmap[ty * MW + tx] == 0: continue
			for y in R:
				for x in R: a[(ty * R + y) * W + tx * R + x] = 1.0
	# two box blurs, each 2 pixels wide (half a tile), so the shadow spreads a little past the footprint
	for pass_i in 2:
		var b := PackedFloat32Array(); b.resize(W * Hh)
		for y in Hh:
			var s := 0.0
			for x in range(-2, W + 2):
				if x + 2 < W: s += a[y * W + x + 2]
				if x - 3 >= 0: s -= a[y * W + x - 3]
				if x >= 0 and x < W: b[y * W + x] = s / 5.0
		for x in W:
			var s := 0.0
			for y in range(-2, Hh + 2):
				if y + 2 < Hh: s += b[(y + 2) * W + x]
				if y - 3 >= 0: s -= b[(y - 3) * W + x]
				if y >= 0 and y < Hh: a[y * W + x] = s / 5.0
	var img := Image.create(W, Hh, false, Image.FORMAT_L8)
	var bytes := PackedByteArray(); bytes.resize(W * Hh)
	for k in W * Hh: bytes[k] = int(clampf(a[k] * 1.3, 0.0, 1.0) * 255.0)
	img.set_data(W, Hh, false, Image.FORMAT_L8, bytes)
	return img

## Buildings changed: refresh the contact shadow.
static func update_occ(mi: MeshInstance3D, S, MW: int, MH: int) -> void:
	if mi == null: return
	var m: ShaderMaterial = mi.mesh.surface_get_material(0)
	m.set_shader_parameter("occ_tex", ImageTexture.create_from_image(occ_image(S, MW, MH)))
