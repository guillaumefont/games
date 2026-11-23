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


## The terrain material: matte, no rim, so the ground stays calm under the action.
static func ground_mat() -> StandardMaterial3D:
	if not _cache.has("ground"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		m.metallic_specular = 0.2
		_cache["ground"] = m
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


static func hash2(x: float, y: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return s - floor(s)


## Collects coloured triangles from many parts into one flat-shaded mesh.
class Builder:
	var st := SurfaceTool.new()
	var n := 0
	## Where parts go: everything added is moved by this (scenery is built round its own origin,
	## then turned and placed).
	var xf := Transform3D.IDENTITY
	## False for things that sit on the ground: their bottom faces are never seen.
	var bottoms := true

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)

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
		if top.x > 0.5 and top.y > 0.5 and y1 - y0 > 0.12 and minr > 0.12:
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
			st.add_vertex(xf * (at * v[idx[i]]))
		n += idx.size()

	func commit() -> ArrayMesh:
		st.generate_normals()
		return st.commit()


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
		_cache[key] = f.call()
	return _cache[key]


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
static func boss_hull() -> Mesh:
	return cached("boss_hull", func() -> Mesh:
		var b := Builder.new()
		b.prism(Vector3.ZERO, pts([Vector2(0, 5.0), Vector2(2.6, 3.5), Vector2(3.6, -2.0), Vector2(3.2, -10.5),
			Vector2(1.6, -12.0), Vector2(-1.6, -12.0), Vector2(-3.2, -10.5), Vector2(-3.6, -2.0), Vector2(-2.6, 3.5)]),
			-0.9, 0.7, FOE_D, Vector2(0.9, 0.95))
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
		b.prism(Vector3(0, 0, 0), pts([Vector2(0, 9.6), Vector2(2.2, 7.0), Vector2(3.4, 2.0), Vector2(-3.4, 2.0),
			Vector2(-2.2, 7.0)]), -0.6, 1.0, FOE, Vector2(0.85, 0.9))
		b.box(Vector3(0, 1.05, 5.0), Vector3(1.0, 0.1, 5.0), AMBER, Vector2(0.4, 0.9))
		for sx in [1.0, -1.0]:
			b.prism(Vector3(sx * 1.6, 1.0, 6.5), ngon(1.0, 8, PI / 8), 0.0, 0.2, HULL_D)
			b.prism(Vector3(sx * 3.0, 0.7, 3.0), ngon(0.9, 8, PI / 8), 0.0, 0.2, HULL_D)
		return b.commit())


static func boss_wings() -> Mesh:
	return cached("boss_wings", func() -> Mesh:
		var b := Builder.new()
		for sx in [1.0, -1.0]:
			var w := [Vector2(3.4, 2.4), Vector2(12.5, -2.2), Vector2(12.5, -4.0), Vector2(3.4, -6.5)]
			var o := PackedVector2Array()
			for p: Vector2 in w:
				o.append(Vector2(p.x * sx, p.y))
			if sx < 0:
				o.reverse()
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


# ---------------------------------------------------------------- foes inside the carrier
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


# ---------------------------------------------------------------- the carrier
## The carrier, stern at z = 0, bow at z = -CARRIER_LEN: tall and narrow, a hull with an open
## hangar at the stern (where the reactor shows in the chase) and a stepped tower above it.
## From the vertical stage you see its long deck; in the chase, its tall stern.
static func carrier() -> Mesh:
	return cached("carrier", func() -> Mesh:
		var b := Builder.new()
		var L := Rules.CARRIER_LEN
		var y := Rules.PY
		var W := Rules.CARRIER_HW
		var top := Rules.CARRIER_TOP
		var hw := Rules.HANGAR_HW
		var hh := Rules.HANGAR_HH
		var bot := 0.8
		var deep := 7.0
		var zc := -L * 0.5
		var inner := Color8(0x2c, 0x31, 0x39)
		# hull behind the hangar, then the stern section round the hangar mouth
		b.box(Vector3(0, (bot + top) * 0.5, -deep - (L - deep) * 0.5), Vector3(W * 2, top - bot, L - deep), HULL, Vector2(0.94, 0.995))
		b.box(Vector3(0, (bot + y - hh) * 0.5, -deep * 0.5), Vector3(W * 2, y - hh - bot, deep), HULL_D)
		b.box(Vector3(0, (y + hh + top) * 0.5, -deep * 0.5), Vector3(W * 2, top - y - hh, deep), HULL, Vector2(0.94, 1.0))
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * (hw + (W - hw) * 0.5), y, -deep * 0.5), Vector3(W - hw, hh * 2, deep), HULL)
		b.box(Vector3(0, y, -deep + 0.1), Vector3(hw * 2, hh * 2, 0.2), inner)
		b.box(Vector3(0, y - hh + 0.05, -deep * 0.5), Vector3(hw * 2, 0.1, deep), inner.lightened(0.1))
		# keel and armour belts along the sides
		b.box(Vector3(0, bot - 0.5, zc), Vector3(W * 1.2, 1.0, L * 0.92), HULL_D, Vector2(1.4, 1.0))
		for sx in [1.0, -1.0]:
			for k in 6:
				b.box(Vector3(sx * (W + 0.4), 7.5, -12.0 - k * 30.0), Vector3(0.8, 6.0, 14.0), HULL_D, Vector2(0.6, 0.95))
		# deck: runway stripes and amber edges
		for k in 16:
			b.box(Vector3(0, top + 0.01, -46.0 - k * 8.5), Vector3(0.5, 0.04, 3.5), Color8(0xe8, 0xe0, 0xc8))
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * (W - 0.5), top + 0.01, zc), Vector3(0.22, 0.04, L - 6), AMBER)
		# amber frame round the hangar mouth
		b.box(Vector3(0, y + hh + 0.25, 0.2), Vector3(hw * 2 + 1.0, 0.5, 0.4), AMBER)
		b.box(Vector3(0, y - hh - 0.25, 0.2), Vector3(hw * 2 + 1.0, 0.5, 0.4), AMBER)
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * (hw + 0.25), y, 0.2), Vector3(0.5, hh * 2, 0.4), AMBER)
			# stern engines low on the hull
			b.prism(Vector3(sx * 3.4, 0, 0.5), ngon(1.1, 8, PI / 8), 1.0, 2.4, NAVY, Vector2(0.85, 0.85))
		return b.commit())


## The carrier's stern armour plating with the gun platforms of its first section (breaks off).
static func carrier_plating() -> Mesh:
	return cached("carrier_plating", func() -> Mesh:
		var b := Builder.new()
		var W := Rules.CARRIER_HW
		var top := Rules.CARRIER_TOP
		var y := Rules.PY
		var hh := Rules.HANGAR_HH
		b.box(Vector3(0, (y + hh + 0.6 + top) * 0.5, 0.25), Vector3(W * 2 - 0.6, top - y - hh - 0.6, 0.5), FOE_D, Vector2(0.97, 1.0))
		for k in 3:
			b.box(Vector3(0, top - 1.0 - k * 1.3, 0.52), Vector3(W * 2 - 1.4, 0.12, 0.06), AMBER)
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * 4.0, (1.2 + y + hh) * 0.5, 0.3), Vector3(1.6, y + hh - 1.2, 0.6), FOE_D)
		for m: Vector2 in Rules.CARRIER_SECTIONS[0].mounts:
			b.box(Vector3(m.x, m.y - 0.8, 0.8), Vector3(1.6, 0.25, 1.2), HULL)
		return b.commit())


## The carrier's stepped tower with the gun platforms of its second section (breaks off).
static func carrier_tower() -> Mesh:
	return cached("carrier_tower", func() -> Mesh:
		var b := Builder.new()
		var W := Rules.CARRIER_HW
		var top := Rules.CARRIER_TOP
		b.box(Vector3(0, (top + 17.0) * 0.5, -21.0), Vector3(W * 1.6, 17.0 - top, 40.0), HULL, Vector2(0.92, 0.97))
		b.box(Vector3(0, (17.0 + Rules.TOWER_TOP) * 0.5, -14.0), Vector3(W * 1.1, Rules.TOWER_TOP - 17.0, 22.0), HULL_D, Vector2(0.85, 0.95))
		b.box(Vector3(0, Rules.TOWER_TOP + 0.6, -16.0), Vector3(1.0, 1.2, 1.0), HULL_D)
		b.box(Vector3(0, Rules.TOWER_TOP + 2.2, -16.0), Vector3(0.25, 2.2, 0.25), STEEL_D)
		for k in 4:
			b.box(Vector3((k - 1.5) * 1.6, 18.2, -2.95), Vector3(1.0, 0.5, 0.1), CYAN)
		for m: Vector2 in Rules.CARRIER_SECTIONS[1].mounts:
			var fz := -0.4 if m.y < 17.0 else -2.4
			b.box(Vector3(m.x, m.y - 0.8, fz - 0.1), Vector3(1.4, 0.25, 1.2), HULL_D)
		return b.commit())


## The carrier's lights (engines, hangar strips, tower windows), a separate mesh with a glow
## material.
static func carrier_lights() -> Mesh:
	return cached("carrier_lights", func() -> Mesh:
		var b := Builder.new()
		var y := Rules.PY
		var hw := Rules.HANGAR_HW
		var hh := Rules.HANGAR_HH
		for k in 3:
			b.box(Vector3(0, y + hh - 0.3, -1.5 - k * 2.0), Vector3(hw * 1.4, 0.05, 0.25), Color.WHITE)
		for sx in [1.0, -1.0]:
			b.prism(Vector3(sx * 3.4, 0, 0.62), ngon(0.75, 8, PI / 8), 1.2, 2.2, Color.WHITE)
		return b.commit())


# ---------------------------------------------------------------- terrain
## One chunk of ground, `size.y` long from z0 towards -z, `size.x` wide: a low poly coast of
## sea, sand, grass and woods from a seeded noise, so chunks join seamlessly.
## The colour of the ground at noise height h, blended across bands so coasts and tree lines
## grade softly instead of stepping cell by cell.
## The terrain theme of the current world (`Campaign.WORLDS`): "coast", "dunes", "city", "ice"
## or "volcano". `ground_chunk` colours the land and picks its props by it.
static var theme := "coast"

## Each theme's sky (top, middle, horizon, below), fog, ambient light and sun.
const THEMES := {
	"coast": {"sky": [Color(0.24, 0.50, 0.80), Color(0.48, 0.74, 0.92), Color(0.86, 0.92, 0.94), Color(0.62, 0.78, 0.88)],
		"fog": Color8(0xc4, 0xde, 0xee), "ambient": Color8(0xb4, 0xcc, 0xe8), "sun": Color8(0xff, 0xef, 0xd6)},
	"dunes": {"sky": [Color(0.36, 0.56, 0.80), Color(0.66, 0.78, 0.88), Color(0.96, 0.88, 0.74), Color(0.86, 0.74, 0.58)],
		"fog": Color8(0xf0, 0xdc, 0xbc), "ambient": Color8(0xe0, 0xcc, 0xb0), "sun": Color8(0xff, 0xe6, 0xc0), "lift": 0.45},
	"city": {"sky": [Color(0.30, 0.42, 0.62), Color(0.56, 0.64, 0.76), Color(0.84, 0.80, 0.78), Color(0.58, 0.60, 0.66)],
		"fog": Color8(0xc8, 0xc8, 0xd0), "ambient": Color8(0xb8, 0xc0, 0xd4), "sun": Color8(0xff, 0xe2, 0xc8), "lift": 0.35},
	"ice": {"sky": [Color(0.40, 0.58, 0.82), Color(0.66, 0.80, 0.92), Color(0.92, 0.95, 0.98), Color(0.74, 0.84, 0.92)],
		"fog": Color8(0xe2, 0xee, 0xf6), "ambient": Color8(0xc4, 0xd8, 0xf0), "sun": Color8(0xf4, 0xf6, 0xff), "lift": 0.3},
	"volcano": {"sky": [Color(0.22, 0.18, 0.26), Color(0.50, 0.32, 0.30), Color(0.86, 0.52, 0.34), Color(0.40, 0.24, 0.20)],
		"fog": Color8(0x8c, 0x5c, 0x4c), "ambient": Color8(0xc8, 0x9c, 0x88), "sun": Color8(0xff, 0xc8, 0x90), "lift": 0.45},
}


## How far the theme raises the land out of the water (the coast keeps its sea; the dunes are
## nearly all land, with the odd dry wash).
static func lift() -> float:
	return float(THEMES[theme].get("lift", 0.0))


static func ground_col(h: float) -> Color:
	match theme:
		"dunes":
			if h < 0.0:   # dry washes and salt pans
				return Color8(0xc4, 0xa2, 0x70).lerp(Color8(0xe6, 0xd6, 0xb4), smoothstep(-0.1, -0.4, h))
			var d := Color8(0xee, 0xd0, 0x92).lerp(Color8(0xe0, 0xa8, 0x66), smoothstep(0.3, 0.5, h))
			return d.lerp(Color8(0xb4, 0x62, 0x40), smoothstep(0.74, 0.8, h))
		"city":
			if h < 0.0:   # canals
				return Color8(0x2c, 0x52, 0x66).lerp(Color8(0x7a, 0x7e, 0x84), smoothstep(-0.06, 0.0, h))
			var c := Color8(0x86, 0x8a, 0x90).lerp(Color8(0x6a, 0x8e, 0x56), smoothstep(0.3, 0.33, h) * (1.0 - smoothstep(0.4, 0.43, h)))
			return c.lerp(Color8(0xa6, 0xa8, 0xac), smoothstep(0.7, 0.76, h))
		"ice":
			if h < 0.0:   # cold sea, pale where the shelf meets it
				return Color8(0x1c, 0x3e, 0x60).lerp(Color8(0x6e, 0xae, 0xcc), smoothstep(-0.12, 0.0, h) * 0.8)
			var c := Color8(0xd6, 0xea, 0xf4).lerp(Color8(0xf6, 0xfa, 0xfd), smoothstep(0.08, 0.14, h))
			return c.lerp(Color8(0x8e, 0x9a, 0xa8), smoothstep(0.7, 0.76, h))
		"volcano":
			if h < 0.0:   # lava, a dark crust at its edge
				return Color8(0xf0, 0x6a, 0x1e).lerp(Color8(0x50, 0x26, 0x1e), smoothstep(-0.1, 0.0, h))
			var c := Color8(0x4a, 0x42, 0x42).lerp(Color8(0x74, 0x6c, 0x68), smoothstep(0.35, 0.5, h))
			return c.lerp(Color8(0x8a, 0x44, 0x34), smoothstep(0.72, 0.78, h))
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
	# one vertex grid, jittered in world space so neighbouring chunks still meet
	var hs := []
	var vs := []
	var cs := []
	for i in nx + 1:
		var hr := []
		var vr := []
		for j in nz + 1:
			var wx := xs[i]
			var wz := z0 - j * cz_
			var jx := (hash2(wx, wz) - 0.5) * cell * 0.3
			var jz := (hash2(wz * 1.3, wx * 0.7) - 0.5) * cell * 0.3
			if i == 0 or i == nx:
				jx = 0.0
			var h: float = hgt.call(wx + jx, wz + jz)
			hr.append(h)
			vr.append(Vector3(wx + jx, height.call(h), wz + jz))
		hs.append(hr)
		vs.append(vr)
	# vertex colours, darkened in hollows (cheap baked occlusion)
	for i in nx + 1:
		var cr := []
		for j in nz + 1:
			var h: float = hs[i][j]
			var c := ground_col(h)
			if h >= 0.0:
				var around := 0.0
				var k := 0
				for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var a := i + d.x
					var e := j + d.y
					if a >= 0 and a <= nx and e >= 0 and e <= nz:
						around += vs[a][e].y
						k += 1
				var hollow: float = clampf((around / k - vs[i][j].y) * 0.8, 0.0, 0.25)
				c = c.darkened(hollow)
			cr.append(c)
		cs.append(cr)
	# soft normals: mostly the broad shape of the land (from the height field itself, so chunks
	# meet without a seam), a little of each facet, so it reads as low poly but polished
	var e := cell * 0.6
	var ground_h := func(x: float, z: float) -> float:
		return height.call(hgt.call(x, z))
	var ns := []
	for i in nx + 1:
		var nr := []
		for j in nz + 1:
			var v: Vector3 = vs[i][j]
			var dx: float = ground_h.call(v.x + e, v.z) - ground_h.call(v.x - e, v.z)
			var dz: float = ground_h.call(v.x, v.z + e) - ground_h.call(v.x, v.z - e)
			nr.append(Vector3(-dx / (2.0 * e), 1.0, -dz / (2.0 * e)).normalized())
		ns.append(nr)
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
			# scenery: woods, villages, beaches, rocks and boats
			var hs4: Array[float] = [hs[i][j], hs[i + 1][j], hs[i + 1][j + 1], hs[i][j + 1]]
			var cy: float = minf(minf(q[0].y, q[1].y), minf(q[2].y, q[3].y))
			# the wide cells out on the flanks are far off in the fog: bare ground is enough
			if xs[i + 1] - xs[i] > cell * 3.5:
				continue
			var cen: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
			if theme != "coast":
				# the other worlds' land (Glass Coast's scenery is scatter's)
				b.xf = Transform3D.IDENTITY
				theme_prop(b, (hs4[0] + hs4[1] + hs4[2] + hs4[3]) * 0.25, cen, cy, hash2(cen.x * 1.7, cen.z * 0.3))
				continue
			scatter(b, hs4, cen, cy)
	var mesh := b.commit() if b.n > 0 else ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = gv
	arr[Mesh.ARRAY_NORMAL] = gn
	arr[Mesh.ARRAY_COLOR] = gc
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


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


## How many of each kind of scenery the chunks built so far hold (tests read it).
static var scenery := {}


static func count(kind: String) -> void:
	scenery[kind] = scenery.get(kind, 0) + 1


## Scenery is drawn this much larger than life so it reads on a phone screen (Guillaume found
## it too small at 1).
const PROP_SCALE := 1.5


## Landmarks: the prominent scenery the player can shoot down (lighthouses, boats, two-storey
## houses). `scatter` leaves them out of the chunk's mesh and lists them here instead; the game
## takes the list after each chunk (`Game.update_chunks`) and gives each its own node.
static var marks: Array = []
## Height of a landmark's centre above its base (the game hits it there, as it shows on screen).
const MARK_H := {"lighthouse": 1.7, "boat": 0.3, "house": 0.85}


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
		var at := Vector3(0, -MARK_H[kind], 0)
		match kind:
			"lighthouse":
				lighthouse(b, at, q * TAU)
			"boat":
				boat(b, at, 0.0)
			"house":
				house(b, at, 0.0, q)
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
			"boat":
				b.prism(Vector3.ZERO, ngon(0.8, 10), -0.03, 0.01, FOAM.darkened(0.15))
				for k in 4:
					var a := k * 1.6
					b.xf = Transform3D(Basis(Vector3.UP, a * 2.0).scaled(Vector3.ONE * PROP_SCALE), Vector3(cos(a) * 0.5, 0, sin(a) * 0.4) * PROP_SCALE)
					b.box(Vector3(0, 0.02, 0), Vector3(0.36, 0.06, 0.1), WOOD.darkened(0.2))
		b.xf = Transform3D.IDENTITY
		return b.commit())


static func place(b: Builder, pos: Vector3, ang: float) -> void:
	b.xf = Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * PROP_SCALE), pos)


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
			mark("lighthouse", Vector3(cen.x, -0.4, cen.z), ang, r2)
		elif r < 0.12:
			rocks(b, Vector3(cen.x + (r2 - 0.5) * 0.8, -0.4, cen.z), 0.32 + r * 2.5, r2, true)
	elif hi < 0.0:
		# at sea: stacks in the shallows, fishing boats further out
		if avg > -0.14 and r < 0.025:
			rocks(b, Vector3(cen.x, -0.4, cen.z), 0.4 + r * 16.0, r2, true)
		elif avg < -0.22 and r < 0.0035:
			mark("boat", Vector3(cen.x, -0.4, cen.z), ang, r2)
	elif avg < 0.08:
		# the beach: palms, sun-bleached driftwood, pebbles, the odd parasol, dune grass
		if r < 0.08:
			palm(b, at, r2)
			if r < 0.025:
				palm(b, at + Vector3(0.7, 0, 0.5).rotated(Vector3.UP, ang), r2 * 0.7 + 0.2)
		elif r < 0.1:
			count("driftwood")
			place(b, at, ang)
			b.box(Vector3(0, 0.04, 0), Vector3(1.1, 0.13, 0.13), DRIFT)
			b.box(Vector3(0.25, 0.05, 0.16), Vector3(0.4, 0.09, 0.09), DRIFT.darkened(0.1))
		elif r < 0.14:
			rocks(b, at, 0.25 + (r - 0.1) * 5.0, r2, false)
		elif r < 0.155:
			parasol(b, at, ang, r2)
		elif r < 0.3 and avg > 0.03:
			# dune grass where the sand rises
			place(b, at, ang)
			count("dune grass")
			for k in 3:
				var tp := Vector3((k - 1) * 0.5, -0.05, (k % 2) * 0.4)
				b.prism(tp, ngon(0.3 - k * 0.04, 5, k), 0, 0.3, Color8(0xa6, 0xb2, 0x62).darkened(k * 0.06), Vector2(0.3, 0.3))
	elif avg < 0.3:
		# the grass: villages here and there, a farm or a copse elsewhere
		var village := hash2(floor(cen.x / 14.0) * 3.1 + 0.5, floor(cen.z / 14.0) * 1.7 + 0.5) < 0.38
		# one house per 4 x 4 lot at most, so the scaled-up houses and gardens don't overlap
		var even := posmod(floori(cen.x * 0.5), 2) == 0 and posmod(floori(cen.z * 0.5), 2) == 0
		var lot := 0.6 if village else 0.06
		if avg >= 0.11 and r < lot and even:
			var turn := snappedf(ang, PI * 0.5) + (r2 - 0.5) * 0.3
			if house_kind(r2) == 1:
				mark("house", at, turn, r2)   # the tall ones can be shot down
			else:
				house(b, at, turn, r2)
		elif r2 < 0.1:
			broadleaf(b, at + Vector3((r - 0.5) * 0.8, 0, (r2 - 0.05) * 6.0), r)
		elif r2 < 0.16:
			bush(b, at + Vector3((r - 0.5), 0, 0), r)
		elif village and r2 < 0.19:
			count("hay")
			place(b, at, ang)
			for k in 2:
				b.prism(Vector3(k * 0.5 - 0.25, -0.1, 0), ngon(0.2, 7), 0, 0.36, Color8(0xe0, 0xbc, 0x60))
	elif avg < 0.52:
		# the woods, with a boulder among the pines
		if r < 0.8:
			for n in 2 if r < 0.4 else 1:
				conifer(b, at + Vector3((r - 0.4) * 2.2 + n * 1.1, 0, (n - 0.5) * 1.2), r)
		elif r < 0.86:
			rocks(b, at, 0.35, r2, false)
	elif r < 0.2:
		# bare rock on the heights
		rocks(b, at, 0.45 + r, r2, false)
	b.xf = Transform3D.IDENTITY


static func conifer(b: Builder, p: Vector3, r: float) -> void:
	count("conifer")
	b.xf = Transform3D.IDENTITY
	var tall := 1.4 + hash2(p.x, p.z) * 0.9
	var tc := FOREST.darkened(0.05 + r * 0.15)
	b.prism(Vector3(p.x, p.y - 0.1, p.z), ngon(0.8, 7, r * 6), 0, tall * 0.6, tc, Vector2(0.45, 0.45))
	b.prism(Vector3(p.x, p.y - 0.1 + tall * 0.45, p.z), ngon(0.6, 7, r * 6 + 0.4), 0, tall * 0.6, tc.lightened(0.06), Vector2(0.05, 0.05))


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
static func rocks(b: Builder, p: Vector3, s: float, r: float, wet: bool) -> void:
	count("sea rocks" if wet else "rocks")
	place(b, p, r * TAU)
	var n := 1 + int(r * 3.0)
	for k in n:
		var sz := s * (1.0 - k * 0.3)
		var off := Vector3(k * s * 0.85, 0, (k % 2) * s * 0.6 - s * 0.3)
		var out := PackedVector2Array()
		for a in 6:
			var rr := sz * (0.75 + hash2(r * 31.0 + a, k * 7.0 + a * 3.0) * 0.5)
			var an := TAU * a / 6.0 + r * 2.0
			out.append(Vector2(cos(an), sin(an)) * rr)
		var c := (STONE_WET if wet else STONE).darkened(hash2(r + k, s) * 0.15)
		var tall := sz * (0.6 + hash2(k, r * 9.0) * 0.5) + (0.25 if wet else 0.0)
		b.prism(off, out, -0.3, tall, c, Vector2(0.6, 0.56), Vector2(sz * 0.12, -sz * 0.08))
		if wet:
			b.prism(off, ngon(sz * 1.75, 8, r), -0.43, -0.37, FOAM)


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
	var r2 := hash2(cen.z * 0.9, cen.x * 2.1)
	match theme:
		"dunes":
			if avg >= 0.8 and r < 0.3:
				var tall := 0.9 + r2 * 1.6
				b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.9 + r * 0.8, 6, r2 * 6), 0, tall, Color8(0xb8, 0x66, 0x42), Vector2(0.75, 0.75))
			elif avg >= 0.05 and avg < 0.6 and r < 0.04:
				b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.16, 6), 0, 1.3, Color8(0x5c, 0x8a, 0x4a), Vector2(0.8, 0.8))
				b.prism(Vector3(cen.x + 0.28, cy + 0.5, cen.z), ngon(0.11, 6), 0, 0.5, Color8(0x5c, 0x8a, 0x4a), Vector2(0.8, 0.8))
			elif avg >= 0.1 and avg < 0.5 and r >= 0.04 and r < 0.07:
				b.box(Vector3(cen.x, cy + 0.3, cen.z), Vector3(1.2, 0.6, 1.0), Color8(0xe0, 0xb8, 0x88))
				b.box(Vector3(cen.x - 0.2, cy + 0.75, cen.z + 0.1), Vector3(0.6, 0.3, 0.6), Color8(0xd6, 0xac, 0x7c))
		"city":
			# streets every few metres, a park where the land is green
			var gx := posmod(int(floor(cen.x / 2.0)), 4)
			var gz := posmod(int(floor(cen.z / 2.0)), 5)
			if avg < 0.02 or gx == 0 or gz == 0 or (avg >= 0.3 and avg < 0.43):
				if avg >= 0.3 and avg < 0.43 and r < 0.35:
					b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.6, 7, r * 6), 0, 0.9, Color8(0x4a, 0x7a, 0x44), Vector2(0.3, 0.3))
				return
			var tall := 0.6 + r2 * r2 * 3.0
			var cols := [Color8(0xd8, 0xd4, 0xcc), Color8(0x9e, 0xae, 0xc0), Color8(0xc4, 0x9a, 0x84), Color8(0x7e, 0x88, 0x96)]
			var col: Color = cols[int(r * 40.0) % cols.size()]
			b.box(Vector3(cen.x, cy + tall * 0.5 - 0.1, cen.z), Vector3(1.7, tall, 1.7), col)
			b.box(Vector3(cen.x, cy + tall - 0.05, cen.z), Vector3(1.4, 0.12, 1.4), col.darkened(0.25))
			if tall > 2.2:
				b.box(Vector3(cen.x + 0.3, cy + tall + 0.15, cen.z - 0.2), Vector3(0.4, 0.3, 0.4), Color8(0x5a, 0x60, 0x6a))
		"ice":
			if avg >= 0.28 and avg < 0.5 and r < 0.7:
				var tall := 1.3 + r2 * 0.9
				var tc := Color8(0x2e, 0x50, 0x4c).darkened(r * 0.2)
				b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.6, 6, r * 6), 0, tall, tc, Vector2(0.05, 0.05))
				b.prism(Vector3(cen.x, cy + tall * 0.55, cen.z), ngon(0.45, 6, r * 6 + 0.5), 0, tall * 0.55, Color8(0xe8, 0xf2, 0xf8), Vector2(0.05, 0.05))
			elif avg >= 0.72 and r < 0.2:
				b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.5, 4, r2 * 6), 0, 1.0 + r2 * 1.4, Color8(0xa6, 0xd6, 0xec), Vector2(0.1, 0.1), Vector2(0.2, 0.0))
			elif avg < -0.05 and r < 0.06:
				b.prism(Vector3(cen.x, -0.42, cen.z), ngon(0.7 + r2 * 0.8, 7, r * 6), 0, 0.14, Color8(0xee, 0xf6, 0xfa), Vector2(0.9, 0.9))
		"volcano":
			if avg >= 0.62 and r < 0.28:
				var tall := 1.0 + r2 * 1.8
				b.prism(Vector3(cen.x, cy - 0.1, cen.z), ngon(0.55, 5, r2 * 6), 0, tall, Color8(0x26, 0x22, 0x2a), Vector2(0.15, 0.15), Vector2(0.15, -0.1))
			elif avg < -0.05 and r < 0.05:
				b.prism(Vector3(cen.x, -0.45, cen.z), ngon(0.5 + r2 * 0.4, 6, r * 6), 0, 0.3, Color8(0x3a, 0x2c, 0x2a), Vector2(0.7, 0.7))


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
