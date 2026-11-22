extends RefCounted
## Premium nature meshes (graphics levels above Classic, see gfx.gd): tiered faceted firs, round faceted leaf crowns,
## chunky rocks and aurite crystal clusters, like the premium concept render. Each is one mesh drawn in a MultiMesh;
## vertex colours hold only light and shade (grey), the instance colour gives the hue, as with the classic decor.
## Preload it (no class_name, so the self-update pack can carry it).

const GFX := preload("res://scripts/gfx.gd")

static var _cache := {}

class Mb:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	## One flat-shaded triangle, wound clockwise for Godot whichever way it was given (faces point away from `inside`).
	func tri(a: Vector3, b: Vector3, cc: Vector3, inside: Vector3, shade: Array) -> void:
		var nn := (b - a).cross(cc - a)
		if nn.length_squared() < 1e-12: return
		nn = nn.normalized()
		if nn.dot((a + b + cc) / 3.0 - inside) < 0: nn = -nn; var t := b; b = cc; cc = t; var s = shade[1]; shade[1] = shade[2]; shade[2] = s
		v.append_array([a, cc, b]); n.append_array([nn, nn, nn])
		c.append(shade[0]); c.append(shade[2]); c.append(shade[1])
	func mesh() -> ArrayMesh:
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am

static func _grey(g: float, a := 1.0) -> Color:
	g = clampf(g, 0.0, 1.0)
	return Color(g, g, g, a)

static func _h(i: int, k: int) -> float:
	return Sim.hash2(i, k, 913)

## A fir in faceted tiers, y from 0.16 to 1, base radius about 0.36. Each tier is darker underneath and at its base.
static func fir() -> ArrayMesh:
	if _cache.has("fir"): return _cache.fir
	var B := Mb.new()
	var tiers := 4 if GFX.level >= GFX.MEDIUM else 3
	var seg := 8 if GFX.level >= GFX.MEDIUM else 6
	for t in tiers:
		var f := float(t) / tiers
		var y0 := 0.16 + 0.2 * t * 3.0 / tiers; var hh := 0.44 - 0.06 * t * 3.0 / tiers
		var r := 0.36 * (1.0 - 0.22 * t * 3.0 / tiers)
		var top := Vector3(0, minf(y0 + hh, 1.0), 0)
		var ring: Array = []
		for k in seg:
			var a := TAU * (k + _h(t, k) * 0.3 + t * 0.37) / seg
			var rr := r * (0.9 + 0.18 * _h(k, t + 7))
			ring.append(Vector3(cos(a) * rr, y0 - 0.03 * _h(k, t + 3), sin(a) * rr))
		var ctr := Vector3(0, y0 + hh * 0.3, 0)
		for k in seg:
			var p0: Vector3 = ring[k]; var p1: Vector3 = ring[(k + 1) % seg]
			var lo := 0.62 + 0.1 * f; var hi := 0.95 + 0.06 * f
			B.tri(p0, p1, top, ctr, [_grey(lo), _grey(lo), _grey(hi)])
			B.tri(p0, p1, Vector3(0, y0 + 0.02, 0), Vector3(0, y0 + 0.2, 0), [_grey(0.42), _grey(0.42), _grey(0.42)])
	_cache.fir = B.mesh()
	return _cache.fir

## A subdivided icosahedron (80 faces) of radius r around c, nudged by n0 so each crown and rock differs.
static func _ico80(c: Vector3, r: float, sc: Vector3, n0: int) -> Array:
	Models._ico()
	var tris: Array = []
	for f in Models._ico_f:
		var a: Vector3 = Models._ico_v[f[0]]; var b: Vector3 = Models._ico_v[f[1]]; var d: Vector3 = Models._ico_v[f[2]]
		var ab := (a + b).normalized(); var bd := (b + d).normalized(); var da := (d + a).normalized()
		tris.append_array([[a, ab, da], [ab, b, bd], [da, bd, d], [ab, bd, da]])
	var jit := func(p: Vector3) -> Vector3:
		var h := Sim.hash2(int(p.x * 97.0 + 300), int(p.y * 89.0 + p.z * 53.0 + 300), n0)
		return c + p * r * (0.9 + 0.18 * h) * sc
	return tris.map(func(t): return [jit.call(t[0]), jit.call(t[1]), jit.call(t[2])])

## Round faceted leaf crown (broad trees), y up to about 0.8, lighter on top.
static func crown() -> ArrayMesh:
	if _cache.has("crown"): return _cache.crown
	var B := Mb.new()
	for bl in [[Vector3(0, .5, 0), .27], [Vector3(.11, .63, -.07), .19], [Vector3(-.12, .58, .09), .18]]:
		var c: Vector3 = bl[0]
		for t in _ico80(c, bl[1], Vector3(1, .86, 1), int(c.x * 100) + 5):
			var sh: Array = t.map(func(p: Vector3): return _grey(clampf(0.6 + (p.y - 0.3) * 0.9, 0.55, 1.0)))
			B.tri(t[0], t[1], t[2], c, sh)
	_cache.crown = B.mesh()
	return _cache.crown

## A low bush, y 0 to about 0.8, radius about 0.6.
static func bush() -> ArrayMesh:
	if _cache.has("bush"): return _cache.bush
	var B := Mb.new()
	for bl in [[Vector3(0, .32, 0), .42], [Vector3(.3, .26, .14), .3], [Vector3(-.26, .22, -.16), .3]]:
		var c: Vector3 = bl[0]
		for t in _ico80(c, bl[1], Vector3(1, .8, 1), int(c.z * 100) + 11):
			var sh: Array = t.map(func(p: Vector3): return _grey(clampf(0.58 + p.y * 0.6, 0.5, 1.0)))
			B.tri(t[0], t[1], t[2], c, sh)
	_cache.bush = B.mesh()
	return _cache.bush

## A chunky faceted rock, radius about 1, flattened; tops lighter than the sides.
static func rock() -> ArrayMesh:
	if _cache.has("rock"): return _cache.rock
	var B := Mb.new()
	for t in _ico80(Vector3.ZERO, 1.0, Vector3(1, .72, 1), 21):
		var sh: Array = []
		for p in t: sh.append(_grey(clampf(0.7 + p.y * 0.35, 0.55, 1.0)))
		B.tri(t[0], t[1], t[2], Vector3.ZERO, sh)
	_cache.rock = B.mesh()
	return _cache.rock

## A cluster of five hexagonal aurite crystals, about 1 tall, the base at y = 0. Vertex alpha falls toward the tips
## so the tips glow brighter (alpha below 1 = glow in Models' shader).
static func crystals() -> ArrayMesh:
	if _cache.has("crystals"): return _cache.crystals
	var B := Mb.new()
	var spec := [[0.0, 0.0, 1.0, 0.0, 0.0], [0.16, 0.05, 0.62, 0.5, 0.0], [-0.12, 0.12, 0.55, -0.45, 0.35], [0.02, -0.17, 0.7, 0.1, -0.5], [-0.1, -0.06, 0.4, -0.3, -0.25]]
	for s in spec:
		var base := Vector3(s[0], -0.05, s[1]); var hh: float = s[2]; var r := 0.13 + 0.07 * hh
		var bs := Basis.from_euler(Vector3(s[4] * 0.6, s[0] * 9.0, -s[3] * 0.6))
		var ring0: Array = []; var ring1: Array = []
		for k in 6:
			var a := TAU * k / 6.0
			ring0.append(base + bs * Vector3(cos(a) * r, 0, sin(a) * r))
			ring1.append(base + bs * Vector3(cos(a) * r * 0.9, hh * 0.72, sin(a) * r * 0.9))
		var tip := base + bs * Vector3(r * 0.15, hh, 0)
		var mid := base + bs * Vector3(0, hh * 0.5, 0)
		for k in 6:
			var j := (k + 1) % 6
			var lk := 0.8 + 0.25 * float(k % 3) / 2.0
			B.tri(ring0[k], ring0[j], ring1[j], mid, [_grey(lk * 0.75, 1.0), _grey(lk * 0.75, 1.0), _grey(lk, 0.8)])
			B.tri(ring0[k], ring1[j], ring1[k], mid, [_grey(lk * 0.75, 1.0), _grey(lk, 0.8), _grey(lk, 0.8)])
			B.tri(ring1[k], ring1[j], tip, mid, [_grey(lk * 1.05, 0.8), _grey(lk * 1.05, 0.8), _grey(1.15, 0.55)])
	_cache.crystals = B.mesh()
	return _cache.crystals

## A soft round puff (smoke, flashes, flame) with smooth normals, so the effect shaders can fade its rim.
static func puff() -> ArrayMesh:
	if _cache.has("puff"): return _cache.puff
	var v := PackedVector3Array(); var n := PackedVector3Array(); var c := PackedColorArray()
	for t in _ico80(Vector3.ZERO, 1.0, Vector3.ONE, 31):
		var a: Vector3 = t[0]; var b: Vector3 = t[1]; var d: Vector3 = t[2]
		if (b - a).cross(d - a).dot(a + b + d) < 0: var tmp := b; b = d; d = tmp
		v.append_array([a, d, b]); n.append_array([a.normalized(), d.normalized(), b.normalized()])
		for k in 3: c.append(Color(1, 1, 1, 1))
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_NORMAL] = n; arr[Mesh.ARRAY_COLOR] = c
	var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_cache.puff = am
	return am

static func reset() -> void:
	_cache.clear()
