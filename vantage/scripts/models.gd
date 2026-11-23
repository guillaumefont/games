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
const SEA := Color8(0x2b, 0x7a, 0xa3)
const SEA_D := Color8(0x1f, 0x5c, 0x86)
const SAND := Color8(0xe3, 0xcf, 0x98)
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
		_mat.roughness = 0.85
	return _mat


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

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0xFFFFFFFF)

	## One triangle; `out` is roughly the direction its front faces.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		if (b - a).cross(c - a).dot(out) < 0.0:
			var t := b
			b = c
			c = t
		st.set_color(col)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
		n += 3

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out)
		tri(a, c, d, col, out)

	## A convex outline (x, z) extruded from y0 to y1 around `c`; the top outline is scaled by
	## `top` (tapers) and shifted by `shift` (x, z). Side colour `side` defaults to `col`
	## darkened.
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
		for p in outline:
			bot.append(c + Vector3(p.x, y0, p.y))
			var q := mid + (p - mid) * top + shift
			tp.append(c + Vector3(q.x, y1, q.y))
		var cb := c + Vector3(mid.x, y0, mid.y)
		var ct := c + Vector3(mid.x + shift.x, y1, mid.y + shift.y)
		for i in nb:
			var j := (i + 1) % nb
			tri(ct, tp[i], tp[j], col, Vector3.UP)
			tri(cb, bot[i], bot[j], sc.darkened(0.2), Vector3.DOWN)
			var o := ((bot[i] + bot[j]) * 0.5 - cb)
			o.y = 0.0
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
	func prim(p: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := p.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		st.set_color(col)
		for i in idx.size():
			st.add_vertex(xf * v[idx[i]])
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
		# the stepped tower over the stern
		b.box(Vector3(0, (top + 17.0) * 0.5, -21.0), Vector3(W * 1.6, 17.0 - top, 40.0), HULL, Vector2(0.92, 0.97))
		b.box(Vector3(0, (17.0 + Rules.TOWER_TOP) * 0.5, -14.0), Vector3(W * 1.1, Rules.TOWER_TOP - 17.0, 22.0), HULL_D, Vector2(0.85, 0.95))
		b.box(Vector3(0, Rules.TOWER_TOP + 0.6, -16.0), Vector3(1.0, 1.2, 1.0), HULL_D)
		b.box(Vector3(0, Rules.TOWER_TOP + 2.2, -16.0), Vector3(0.25, 2.2, 0.25), STEEL_D)
		# amber frame round the hangar mouth
		b.box(Vector3(0, y + hh + 0.25, 0.2), Vector3(hw * 2 + 1.0, 0.5, 0.4), AMBER)
		b.box(Vector3(0, y - hh - 0.25, 0.2), Vector3(hw * 2 + 1.0, 0.5, 0.4), AMBER)
		for sx in [1.0, -1.0]:
			b.box(Vector3(sx * (hw + 0.25), y, 0.2), Vector3(0.5, hh * 2, 0.4), AMBER)
			# stern engines low on the hull
			b.prism(Vector3(sx * 3.4, 0, 0.5), ngon(1.1, 8, PI / 8), 1.0, 2.4, NAVY, Vector2(0.85, 0.85))
		# stern face panelling above the hangar and up the tower
		for k in 3:
			b.box(Vector3(0, top - 1.2 - k * 1.4, 0.05), Vector3(W * 2 - 1.0, 0.12, 0.1), HULL_D)
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
		for k in 4:
			b.box(Vector3((k - 1.5) * 1.6, 18.8, -2.95), Vector3(1.0, 0.5, 0.1), Color.WHITE)
		return b.commit())


# ---------------------------------------------------------------- terrain
## One chunk of ground, `size.y` long from z0 towards -z, `size.x` wide: a low poly coast of
## sea, sand, grass and woods from a seeded noise, so chunks join seamlessly.
static func ground_chunk(noise: FastNoiseLite, z0: float, size: Vector2, cell: float) -> Mesh:
	var b := Builder.new()
	var nx := int(size.x / cell)
	var nz := int(size.y / cell)
	var x0 := -size.x * 0.5
	var hgt := func(x: float, z: float) -> float:
		var n := noise.get_noise_2d(x, z) + 0.35 * sin(x * 0.05 + z * 0.01)
		return n
	var height := func(h: float) -> float:
		return -0.4 if h < 0.0 else minf(h, 0.8) * 1.6
	for i in nx:
		for j in nz:
			var xa := x0 + i * cell
			var za := z0 - j * cell
			var c := [Vector2(xa, za), Vector2(xa + cell, za), Vector2(xa + cell, za - cell), Vector2(xa, za - cell)]
			var hs := []
			var avg := 0.0
			for p: Vector2 in c:
				var h: float = hgt.call(p.x, p.y)
				hs.append(h)
				avg += h
			avg /= 4.0
			var col: Color
			if avg < 0.0:
				col = SEA if avg > -0.25 else SEA_D
			elif avg < 0.08:
				col = SAND
			elif avg < 0.32:
				col = GRASS
			elif avg < 0.5:
				col = FOREST
			else:
				col = ROCK
			col = col.lightened((hash2(xa, za) - 0.5) * (0.035 if avg < 0.0 else 0.08))
			var v := []
			for k in 4:
				v.append(Vector3(c[k].x, height.call(hs[k]), c[k].y))
			b.quad(v[0], v[1], v[2], v[3], col, Vector3.UP)
			# a few trees on the woods, houses on the grass
			var r := hash2(xa * 1.7, za * 0.3)
			var cx := xa + cell * 0.5
			var cz := za - cell * 0.5
			var cy: float = height.call(avg)
			if avg >= 0.32 and avg < 0.5 and r < 0.55:
				b.prism(Vector3(cx + (r - 0.3) * 2, cy, cz), ngon(0.7, 5, r * 6), 0, 1.6, FOREST.darkened(0.15), Vector2(0.05, 0.05))
			elif avg >= 0.1 and avg < 0.3 and r < 0.06:
				b.box(Vector3(cx, cy + 0.35, cz), Vector3(1.1, 0.7, 0.8), Color8(0xee, 0xe6, 0xd8))
				b.prism(Vector3(cx, cy + 0.7, cz), pts([Vector2(-0.62, -0.48), Vector2(0.62, -0.48), Vector2(0.62, 0.48),
					Vector2(-0.62, 0.48)]), 0, 0.45, Color8(0xc0, 0x5a, 0x3e), Vector2(0.05, 1.0))
	return b.commit()


static func shot_mesh(r: float, stretch := 1.0) -> Mesh:
	return cached("shot%s_%s" % [r, stretch], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2 * stretch
		s.radial_segments = 6
		s.rings = 3
		return s)
