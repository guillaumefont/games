class_name Dwellings
extends RefCounted
## Cliff dwellings in Ember Dunes (Guillaume, 2026-11-27: "in the sandy desert I want more houses hidden
## around in the mountain flanks"). Down the flanks of the desert's set pieces (the wadi canyon's
## terraced walls, the feet of the mesas' buttes, the meteor crater's steps), little mud-brick houses
## stand in small hamlets on the ledges, their backs set into the rock, a brow of rock jutting over
## most of them: half hidden, so they are found rather than shown. Sandstone-coloured to keep the
## backdrop calm. Each chunk builds the dwellings whose grid spot it holds (`build`).

## Spots on a STEP m grid out to REACH m each side; hamlets live in some HAMLET m cells only.
const STEP := 3.0
const REACH := 27.0
const HAMLET := 16.0
const HOSTS := ["canyon", "mesas", "crater"]
## How far below the plain a ledge must lie, how much rock must rise behind it.
const DEPTH := 1.4
const WALL := 1.3
## The houses' scale: smaller than the comic props of the plain, so they fit on the ledges.
const W := 1.9
const V := 1.5
const WALLS := [Color8(0xd2, 0x9a, 0x68), Color8(0xc8, 0x8c, 0x5c), Color8(0xdc, 0xa8, 0x76), Color8(0xbe, 0x80, 0x56)]


## The dwellings whose spots lie in z_near >= z > z_far (one chunk), built into `b`.
static func build(b: Models.Builder, noise: FastNoiseLite, z_near: float, z_far: float) -> void:
	if Models.theme != "dunes":
		return
	for k in range(ceili(-z_near / STEP - 1e-4), ceili(-z_far / STEP - 1e-4)):
		var gz := -k * STEP
		if gz > z_near or gz <= z_far:
			continue
		for i in range(-roundi(REACH / STEP), roundi(REACH / STEP) + 1):
			var s := spot(noise, i * STEP, gz)
			if not s.is_empty():
				dwelling(b, s.p, s.a, s.r, s.cap)


## The dwelling on the grid spot (gx, gz), if one stands there: {p (its base), a (angle), r}.
static func spot(noise: FastNoiseLite, gx: float, gz: float) -> Dictionary:
	if Models.theme != "dunes":
		return {}
	var r := Models.hash2(gx * 1.31 + 0.7, gz * 0.77 - 0.3)
	var x := gx + (Models.hash2(gz * 1.9, gx * 0.6) - 0.5) * 1.2
	var z := gz + (Models.hash2(gx * 2.3, gz * 1.4) - 0.5) * 1.2
	if not Relief.kind_of(Relief.stretch_of(z)) in HOSTS or Relief.in_town(x, z):
		return {}
	var hamlet := Models.hash2(floorf(x / HAMLET) * 1.7 + 0.3, floorf(z / HAMLET) * 2.9 + 0.1)
	if hamlet > 0.6 or r > 0.8:
		return {}
	var h := Relief.raw(noise, x, z)
	var y := Relief.at(x, z, h).x
	if Relief.base_y(h) - y < DEPTH:
		return {}
	var yh := func(px: float, pz: float) -> float:
		return Relief.y_at(noise, px, pz)
	# the rock behind: the way the land climbs most within a few metres
	var best := Vector2.ZERO
	var rise := 0.0
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		var up: float = yh.call(x + d.x * 2.4, z + d.y * 2.4) - y
		if up > rise:
			rise = up
			best = d
	if rise < WALL:
		return {}
	# a ledge along the rock, level to either side, and no sheer drop right in front
	var side := Vector2(-best.y, best.x) * 0.8
	for d: Vector2 in [side, -side]:
		if absf(float(yh.call(x + d.x, z + d.y)) - y) > 0.5:
			return {}
	if float(yh.call(x - best.x * 0.7, z - best.y * 0.7)) < y - 1.1:
		return {}
	# how far the ledge runs back to the foot of the rock
	var back := 0.0
	while back < 2.4 and float(yh.call(x + best.x * (back + 0.2), z + best.y * (back + 0.2))) - y < 0.4:
		back += 0.2
	# the house's back is set well into the rock, its door looking out over the drop
	var c := Vector2(x, z) + best * (back + 0.5 - 0.45 * W)
	if Relief.in_town(c.x, c.y):
		return {}
	return {"p": Vector3(c.x, y, c.y), "a": atan2(-best.x, -best.y), "r": r, "cap": minf(rise, Relief.base_y(h) - y)}


## A cliff dwelling: one or two flat-roofed mud-brick storeys stepped back into the rock, dark
## T-shaped doorways and window slits, roof beams poking out, often a ladder, and over most a brow
## of the cliff's own rock that half hides it from above (never higher than `cap` m, the rock behind).
static func dwelling(b: Models.Builder, p: Vector3, a: float, r: float, cap := 9.0) -> void:
	Models.count("cliff dwelling")
	b.xf = Transform3D(Basis(Vector3.UP, a) * Basis.from_scale(Vector3(W, V, W)), p)
	b.occlude(Models.AO_H)
	var wall: Color = WALLS[int(r * 17.0) % WALLS.size()]
	var dark := Color8(0x3a, 0x24, 0x1c)
	var beam := Color8(0x6a, 0x4a, 0x32)
	var tall := 0.62 + 0.18 * float(int(r * 29.0) % 2)
	# the ground floor stands on a built-up footing down to the ledge, so a narrow or sloping
	# ledge never shows a gap under it
	b.box(Vector3(0, (tall - 0.9) * 0.5, 0), Vector3(1.0, tall + 0.9, 0.9), wall)
	b.box(Vector3(0, tall + 0.03, 0), Vector3(1.06, 0.07, 0.96), wall.lightened(0.06), Vector2(0.88, 0.86))
	# a T-shaped door and two slits
	b.box(Vector3(-0.18, 0.2, 0.455), Vector3(0.16, 0.4, 0.02), dark)
	b.box(Vector3(-0.18, 0.36, 0.455), Vector3(0.28, 0.1, 0.02), dark)
	b.box(Vector3(0.24, tall - 0.24, 0.455), Vector3(0.12, 0.1, 0.02), dark)
	# beam ends under the roof
	for k in 4:
		b.box(Vector3(-0.39 + k * 0.26, tall - 0.06, 0.48), Vector3(0.05, 0.05, 0.1), beam)
	var top := tall
	if int(r * 53.0) % 3 != 0:
		# a second storey stepped back against the rock
		var t2 := 0.5
		b.box(Vector3(0.12, tall + t2 * 0.5, -0.2), Vector3(0.66, t2, 0.5), wall.darkened(0.05))
		b.box(Vector3(0.12, tall + t2 + 0.03, -0.2), Vector3(0.7, 0.06, 0.54), wall.lightened(0.04), Vector2(0.86, 0.84))
		b.box(Vector3(0.24, tall + 0.2, 0.055), Vector3(0.14, 0.26, 0.02), dark)
		top = tall + t2
	if int(r * 71.0) % 2 == 0:
		# a ladder up to the roof
		for sx in [-0.42, -0.26]:
			b.box(Vector3(sx, tall * 0.5 + 0.08, 0.56), Vector3(0.03, tall + 0.3, 0.03), beam)
		for k in 3:
			b.box(Vector3(-0.34, 0.18 + k * tall * 0.3, 0.56), Vector3(0.18, 0.025, 0.025), beam)
	if int(r * 37.0) % 3 != 0 and cap / V > top + 0.35:
		# the brow: a thin, broad slab of the cliff's own rock, rooted deep in the face behind and
		# jutting out over the back of the roof, so from above the house half hides under it
		var rock := Models.rock_col(p.y)
		var lip := Models.blob(1.0, 14, r * 7.0)
		var pts := PackedVector2Array()
		for q in lip:
			pts.append(Vector2(q.x * 0.95, q.y * 0.55 - 0.75))
		var y0 := top + 0.12
		# it hangs in the air: its underside shows from the chase's low camera
		b.bottoms = true
		b.prism(Vector3.ZERO, pts, y0, minf(y0 + 0.24, cap / V), rock.darkened(0.08), Vector2(0.92, 0.9), Vector2.ZERO, rock.darkened(0.16))
		b.bottoms = false
	b.xf = Transform3D.IDENTITY
