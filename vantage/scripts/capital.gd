class_name Capital
extends RefCounted
## The final bosses' meshes: capital ships far bigger than the screen (`Rules.FORTRESSES`), built
## in their model frame: the stern at z = 0, the bow at z = -`Rules.fortress_len`, the deck at
## y = 0 and the hull below it. Flat-shaded and chunky like the rest of the game.
##
## The hull is cut into one segment a section (`segment`), so it can break apart at its seams when
## the ship dies. Each segment carries its deck's fittings by kind (engines, hangar, guns,
## missiles, lances, bridge), and its `piece`: the superstructure that breaks off when the
## section's guns are down. The guns themselves are foes, each its own mesh (`gun`), facing +z
## (aft, towards the chase) round its hit point.

const B := Models.Builder
## The bridge's tiers (the last section before the reactor): [dz from, dz to, half width, top].
const TIERS := [[8.0, 40.0, 9.0, 4.0], [20.0, 38.0, 6.0, 8.0], [25.0, 35.0, 4.5, 11.0]]
## The reactor, in front of the bridge's second tier: dz into the bridge section, height.
const CORE_DZ := 16.5
const CORE_Y := 6.4
const LIGHT := Color8(0xd8, 0xf6, 0xff)
const HAZARD := Color8(0x1e, 0x20, 0x24)


static func fort(id: String) -> Dictionary:
	return Rules.FORTRESSES[id]


static func paint(id: String) -> Array:
	return Models.PAINTS[fort(id).paint]


## The deck's half width at d metres from the stern.
static func hw(id: String, d: float) -> float:
	var f := fort(id)
	var L := Rules.fortress_len(id)
	var W := Rules.FORTRESS_HW
	var w := W
	match f.hull:
		"wedge":
			# widest just ahead of the stern, narrowing all the way to a sharp bow
			w = W * (0.9 + 0.1 * clampf(d / 12.0, 0.0, 1.0)) * (1.0 - 0.36 * clampf((d - 40.0) / (L - 80.0), 0.0, 1.0))
		"round":
			w = W * (0.82 + 0.18 * sin(clampf(d / 26.0, 0.0, 1.0) * PI * 0.5))
		_:
			w = W * (0.9 + 0.1 * clampf(d / 14.0, 0.0, 1.0))
	var bow := clampf((d - (L - Rules.BOW_LEN - 10.0)) / (Rules.BOW_LEN + 10.0), 0.0, 1.0)
	return maxf(0.6, w * (1.0 - pow(bow, 1.7) * 0.96))


## The hull's side below the deck edge, from the edge down to the keel (right half), at deck half
## width w: a flared armour belt, the flank, the belly.
static func side(kind: String, w: float, depth: float) -> PackedVector2Array:
	match kind:
		"wedge":
			return PackedVector2Array([Vector2(w, 0), Vector2(w + 0.7, -1.4), Vector2(w * 0.72, -depth * 0.6),
				Vector2(w * 0.18, -depth)])
		"round":
			return PackedVector2Array([Vector2(w, 0), Vector2(w + 1.4, -2.4), Vector2(w + 1.1, -depth * 0.45),
				Vector2(w * 0.72, -depth * 0.8), Vector2(w * 0.28, -depth)])
	return PackedVector2Array([Vector2(w, 0), Vector2(w + 1.2, -1.2), Vector2(w + 1.2, -4.2),
		Vector2(w * 0.86, -depth * 0.72), Vector2(w * 0.42, -depth)])


## The rings the hull is lofted through, by distance from the stern.
static func stations(id: String) -> PackedFloat32Array:
	var L := Rules.fortress_len(id)
	var out := PackedFloat32Array()
	var d := 0.0
	while d < L - 0.01:
		out.append(d)
		d += 4.0 if d < L - Rules.BOW_LEN - 10.0 else 3.0
	out.append(L)
	return out


## The segment of hull for section i: from its start to the next one's (the last runs to the bow).
static func seg_range(id: String, i: int) -> Vector2:
	var secs: Array = fort(id).sections
	var a := Rules.section_at(id, i)
	var b := Rules.section_at(id, i + 1)
	if i >= real_sections(id) - 1:
		b = Rules.fortress_len(id)
	return Vector2(a, b)


## Sections with a stretch of hull (the reactor is fought on the bridge's).
static func real_sections(id: String) -> int:
	var n := 0
	for sec: Dictionary in fort(id).sections:
		if sec.kind != "core":
			n += 1
	return n


## Where a segment turns about when the ship breaks up: its middle, half way down the hull.
static func pivot(id: String, i: int) -> Vector3:
	var r := seg_range(id, i)
	return Vector3(0, -Rules.HULL_DEPTH * 0.45, -(r.x + r.y) * 0.5)


static func core_at(id: String) -> Vector3:
	var n := real_sections(id) - 1
	return Vector3(0, CORE_Y, -(Rules.section_at(id, n) + CORE_DZ))


## A quad from points given as (x, y, -d): its colour, facing `out`.
static func q(b: B, a: Vector3, c: Vector3, d: Vector3, e: Vector3, col: Color, out: Vector3) -> void:
	b.quad(a, c, d, e, col, out)


## Section i's segment of hull with its deck's fittings, in the model frame.
static func segment(id: String, i: int) -> Mesh:
	return Models.cached("cap_seg_%s_%d" % [id, i], func() -> Mesh:
		var b := B.new()
		var f := fort(id)
		var pt: Array = paint(id)
		var deck: Color = pt[0]
		var flank: Color = pt[1]
		var trim: Color = pt[2]
		var accent: Color = f.accent
		var r := seg_range(id, i)
		var depth := Rules.HULL_DEPTH
		var ds: Array[float] = [r.x]
		for d in stations(id):
			if d > r.x + 0.5 and d < r.y - 0.5:
				ds.append(d)
		ds.append(r.y)
		for k in ds.size() - 1:
			var d0: float = ds[k]
			var d1: float = ds[k + 1]
			var w0 := hw(id, d0)
			var w1 := hw(id, d1)
			var s0 := side(f.hull, w0, depth * (0.3 + 0.7 * w0 / Rules.FORTRESS_HW))
			var s1 := side(f.hull, w1, depth * (0.3 + 0.7 * w1 / Rules.FORTRESS_HW))
			var plate := int(d0 / 4.0) % 2 == 0
			# the deck: two walkways along the edges, plating in between, a dashed centre line
			var dk: Color = deck if plate else deck.darkened(0.06)
			var walk: Color = deck.lerp(trim, 0.45)
			var e0 := w0 - 1.6
			var e1 := w1 - 1.6
			# the plating in lanes, every other plate a shade darker
			var lanes := 6
			for l in lanes:
				var u0 := -1.0 + 2.0 * l / lanes
				var u1 := -1.0 + 2.0 * (l + 1) / lanes
				var lc: Color = dk if (l + int(d0 / 4.0)) % 2 == 0 else dk.darkened(0.05)
				if l == 0 or l == lanes - 1:
					lc = lc.lerp(trim, 0.12)
				q(b, Vector3(u0 * e0, 0, -d0), Vector3(u1 * e0, 0, -d0), Vector3(u1 * e1, 0, -d1), Vector3(u0 * e1, 0, -d1), lc, Vector3.UP)
			for sx: float in [1.0, -1.0]:
				q(b, Vector3(sx * e0, 0, -d0), Vector3(sx * w0, 0, -d0), Vector3(sx * w1, 0, -d1), Vector3(sx * e1, 0, -d1), walk, Vector3.UP)
				# a low parapet along the deck edge
				var a0 := Vector3(sx * w0, 0, -d0)
				var a1 := Vector3(sx * w1, 0, -d1)
				q(b, a0 + Vector3(-sx * 0.35, 0, 0), a1 + Vector3(-sx * 0.35, 0, 0), a1 + Vector3(-sx * 0.35, 0.7, 0), a0 + Vector3(-sx * 0.35, 0.7, 0), trim, Vector3(-sx, 0, 0))
				q(b, a0 + Vector3(-sx * 0.35, 0.7, 0), a1 + Vector3(-sx * 0.35, 0.7, 0), a1 + Vector3(0, 0.7, 0), a0 + Vector3(0, 0.7, 0), flank.lightened(0.1), Vector3.UP)
				q(b, a0 + Vector3(0, 0.7, 0), a1 + Vector3(0, 0.7, 0), a1, a0, flank, Vector3(sx, 0.3, 0))
				# the hull's side, edge to keel: armour belt, flank, belly
				for j in s0.size() - 1:
					var p0 := Vector3(sx * s0[j].x, s0[j].y, -d0)
					var p1 := Vector3(sx * s0[j + 1].x, s0[j + 1].y, -d0)
					var p2 := Vector3(sx * s1[j + 1].x, s1[j + 1].y, -d1)
					var p3 := Vector3(sx * s1[j].x, s1[j].y, -d1)
					var col: Color = flank if j < s0.size() - 2 else trim
					if j == 0:
						col = flank.lightened(0.08)
					if j == 1 and plate:
						col = col.darkened(0.05)
					var n := Vector3(sx * ((s0[j].x + s0[j + 1].x) * 0.5), (s0[j].y + s0[j + 1].y) * 0.5 + depth * 0.5, 0)
					q(b, p0, p1, p2, p3, col, n)
				# a stripe of the accent colour along the belt
				var y0 := -1.0
				var mid0 := Vector3(sx * (w0 + 0.62), y0, -d0)
				var mid1 := Vector3(sx * (w1 + 0.62), y0, -d1)
				if f.hull != "wedge":
					q(b, mid0, mid1, mid1 + Vector3(0, -0.45, 0), mid0 + Vector3(0, -0.45, 0), accent.darkened(0.1), Vector3(sx, 0, 0))
			var kl0 := Vector3(s0[s0.size() - 1].x, s0[s0.size() - 1].y, -d0)
			var kl1 := Vector3(s1[s1.size() - 1].x, s1[s1.size() - 1].y, -d1)
			q(b, kl0 * Vector3(-1, 1, 1), kl0, kl1, kl1 * Vector3(-1, 1, 1), trim.darkened(0.2), Vector3.DOWN)
			if d1 < Rules.fortress_len(id) - Rules.BOW_LEN:
				# a seam between deck plates, a dashed centre line, vents and bollards by the edges
				b.box(Vector3(0, 0.02, -d0), Vector3(e0 * 2.0, 0.04, 0.16), deck.darkened(0.22))
				if plate:
					b.box(Vector3(0, 0.03, -(d0 + 1.0)), Vector3(0.6, 0.06, 2.0), accent.lerp(deck, 0.3))
				var hh := Models.hash2(d0 * 0.37 + i, 3.1)
				for sx in [1.0, -1.0]:
					if hh > 0.55:
						b.box(Vector3(sx * (e0 - 1.6), 0.25, -(d0 + 2.0)), Vector3(1.4, 0.5, 2.2), trim.lerp(deck, 0.3))
						b.box(Vector3(sx * (e0 - 1.6), 0.52, -(d0 + 2.0)), Vector3(1.0, 0.06, 1.8), trim)
					elif hh > 0.3:
						b.prism(Vector3(sx * (e0 - 0.9), 0, -(d0 + 2.0)), Models.ngon(0.3, 6), 0.0, 0.55, trim)
		# the stern's face
		if i == 0:
			var w := hw(id, 0.0)
			var s := side(f.hull, w, depth * (0.3 + 0.7 * w / Rules.FORTRESS_HW))
			var ring := PackedVector2Array()
			for j in s.size():
				ring.append(s[j])
			for j in range(s.size() - 1, -1, -1):
				ring.append(Vector2(-s[j].x, s[j].y))
			var c := Vector3(0, -depth * 0.4, 0)
			for j in ring.size():
				var a := ring[j]
				var e := ring[(j + 1) % ring.size()]
				b.tri(c, Vector3(a.x, a.y, 0), Vector3(e.x, e.y, 0), trim.lerp(flank, 0.3), Vector3.BACK)
		# the bow's prow: a sharp keel-cutter under the last metres
		if i == real_sections(id) - 1:
			var L := Rules.fortress_len(id)
			b.prism(Vector3(0, 0, -L + 4.0), PackedVector2Array([Vector2(0, -4.0), Vector2(0.6, 2.0), Vector2(0, 10.0), Vector2(-0.6, 2.0)]),
				-1.0, 1.2, accent.darkened(0.2))
		fittings(b, id, i)
		return b.commit())


## A section's deck fittings that stay put (the piece that breaks off is separate).
static func fittings(b: B, id: String, i: int) -> void:
	var f := fort(id)
	var sec: Dictionary = f.sections[i]
	var pt: Array = paint(id)
	var trim: Color = pt[2]
	var accent: Color = f.accent
	var r := seg_range(id, i)
	var a := r.x
	var len := r.y - r.x
	# a ring of armour under each deck gun
	for g: Array in sec.guns:
		var at := Rules.gun_at(id, i, g)
		if g[0] in ["twin", "quad", "pod", "dish", "mast", "pylon"] and g.size() < 4:
			b.prism(Vector3(at.x, 0, at.z), Models.ngon(2.1, 10), 0.0, 0.35, trim.lerp(accent, 0.15))
	match sec.kind:
		"engines":
			# heat-sink grilles and warning chevrons aft of the engine housings
			for k in 6:
				b.box(Vector3(0, 0.05, -(a + 30.0 + k * 1.6)), Vector3(8.0, 0.1, 0.7), trim)
			for sx: float in [-1.0, 1.0]:
				for k in 4:
					b.prism(Vector3(sx * 3.0, 0.02, -(a + 1.5 + k * 2.2)), poly([[-1.2, 0.4], [0, -0.6], [1.2, 0.4], [0, -0.1]]), 0.0, 0.06, accent)
			# the cowls round the nozzles on the stern's face
			for g: Array in sec.guns:
				if g[0] == "nozzle":
					var at := Rules.gun_at(id, i, g)
					b.loft([Models.oval(Vector3(at.x, at.y, 0.05), Vector3(3.1, 0, 0), Vector3(0, 3.1, 0), 2.0, 14),
						Models.oval(Vector3(at.x, at.y, 1.4), Vector3(2.9, 0, 0), Vector3(0, 2.9, 0), 2.0, 14),
						Models.oval(Vector3(at.x, at.y, 1.5), Vector3(2.5, 0, 0), Vector3(0, 2.5, 0), 2.0, 14)], trim.lerp(Models.STEEL_D, 0.3))
		"hangar":
			# a landing strip: edge lines, dashes, a lift outlined in the accent colour
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(sx * 9.6, 0.04, -(a + len * 0.5)), Vector3(0.35, 0.08, len - 4.0), Color8(0xe8, 0xe8, 0xe0))
			for k in int(len / 6.0):
				b.box(Vector3(0, 0.04, -(a + 3.0 + k * 6.0)), Vector3(0.4, 0.08, 2.6), Color8(0xe8, 0xe8, 0xe0))
			var lz := a + len - 9.0
			for e in [[0.0, 3.4, 7.0, 0.3], [0.0, -3.4, 7.0, 0.3], [3.4, 0.0, 0.3, 7.0], [-3.4, 0.0, 0.3, 7.0]]:
				b.box(Vector3(e[0], 0.05, -(lz + e[1])), Vector3(e[2], 0.1, e[3]), accent)
			b.box(Vector3(0, 0.02, -lz), Vector3(6.6, 0.04, 6.6), trim.lerp(pt[0], 0.4))
		"guns":
			# an armoured spine along the gun deck
			b.prism(Vector3(0, 0, -(a + len * 0.5)), poly([[-0.9, -len * 0.42], [0.9, -len * 0.42], [0.9, len * 0.42], [-0.9, len * 0.42]]), 0.0, 0.4, trim)
		"missiles":
			# the vertical launch grid: rows of cell lids
			for row in 5:
				for col in 6:
					var x := (col - 2.5) * 1.6
					if absf(x) < 1.0:
						continue
					b.box(Vector3(x, 0.08, -(a + 10.0 + row * 1.6)), Vector3(1.3, 0.16, 1.3), trim if (row + col) % 3 else accent.darkened(0.3))
		"lances":
			# conduits feeding the masts
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(sx * 2.2, 0.15, -(a + len * 0.5)), Vector3(0.5, 0.3, len - 6.0), trim)
				b.box(Vector3(sx * 2.2, 0.32, -(a + len * 0.5)), Vector3(0.18, 0.06, len - 6.0), accent)
		"bridge":
			bridge(b, id, i)


## The bridge: three stepped tiers, glazed at the top, a mast and antennas over it.
static func bridge(b: B, id: String, i: int) -> void:
	var f := fort(id)
	var pt: Array = paint(id)
	var a := Rules.section_at(id, i)
	var accent: Color = f.accent
	var y0 := 0.0
	var k := 0
	for t: Array in TIERS:
		var z0: float = a + t[0]
		var z1: float = a + t[1]
		var w: float = t[2]
		var top: float = t[3]
		var o := poly([[-w, -(z1 - z0) * 0.5], [w, -(z1 - z0) * 0.5], [w, (z1 - z0) * 0.5 - 1.2], [w - 1.2, (z1 - z0) * 0.5],
			[-w + 1.2, (z1 - z0) * 0.5], [-w, (z1 - z0) * 0.5 - 1.2]])
		b.prism(Vector3(0, 0, -(z0 + z1) * 0.5), o, y0, top, (pt[1] as Color).lightened(0.05 * k), Vector2(0.97, 0.98))
		if k == 2:
			# the bridge's windows, all round
			b.box(Vector3(0, top - 1.3, -z0 + 0.02), Vector3(w * 2.0 - 1.6, 0.9, 0.1), Models.GLASS_D)
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(sx * (w - 0.02), top - 1.3, -(z0 + z1) * 0.5), Vector3(0.1, 0.9, z1 - z0 - 2.0), Models.GLASS_D)
		else:
			b.box(Vector3(0, top - 0.25, -z0 + 0.6), Vector3(w * 2.0 - 2.6, 0.18, 0.1), accent)
		y0 = top
		k += 1
	# the mast and its yards, the antennas
	var mz := a + 32.0
	b.prism(Vector3(0, 0, -mz), Models.ngon(0.6, 6), 11.0, 20.0, pt[2], Vector2(0.4, 0.4))
	for yy: float in [14.5, 17.5]:
		b.box(Vector3(0, yy, -mz), Vector3(6.0 - (yy - 14.0) * 0.8, 0.25, 0.4), pt[2])
	b.octa(Vector3(0, 20.4, -mz), 0.5, Color8(0xff, 0x40, 0x40))
	for sx: float in [-1.0, 1.0]:
		b.prism(Vector3(sx * 3.0, 0, -(a + 28.0)), Models.ngon(0.15, 4), 11.0, 15.5, pt[2])
	# the reactor's cradle, a dark socket in front of the second tier
	b.prism(Vector3(0, 0, -(a + CORE_DZ)), Models.ngon(3.0, 10), 4.0, 4.6, HAZARD)
	b.box(Vector3(0, 6.6, -(a + TIERS[1][0]) + 0.05), Vector3(6.0, 4.4, 0.1), HAZARD)


## The superstructure that breaks off when section i's guns are down, or null.
static func piece(id: String, i: int) -> Mesh:
	var sec: Dictionary = fort(id).sections[i]
	if sec.kind == "core":
		return null
	return Models.cached("cap_piece_%s_%d" % [id, i], func() -> Mesh:
		var b := B.new()
		var f := fort(id)
		var pt: Array = paint(id)
		var trim: Color = pt[2]
		var armour: Color = (pt[1] as Color).lerp(trim, 0.35)
		var accent: Color = f.accent
		var r := seg_range(id, i)
		var a := r.x
		var len := r.y - r.x
		match sec.kind:
			"engines":
				# two long engine housings either side, vented, with exhaust stacks
				for sx: float in [-1.0, 1.0]:
					var x := sx * (hw(id, 12.0) - 4.2)
					b.prism(Vector3(x, 0, -(a + 14.0)), poly([[-2.8, -13.0], [2.8, -13.0], [2.8, 11.0], [1.6, 13.0], [-1.6, 13.0], [-2.8, 11.0]]), 0.0, 3.6, armour, Vector2(0.9, 0.96))
					for k in 5:
						b.box(Vector3(x, 3.65, -(a + 6.0 + k * 3.4)), Vector3(4.2, 0.12, 0.9), trim)
					for k in 2:
						b.prism(Vector3(x + (k - 0.5) * 2.2, 3.6, -(a + 22.0)), Models.ngon(0.8, 8), 0.0, 3.0, trim, Vector2(0.8, 0.8))
						b.prism(Vector3(x + (k - 0.5) * 2.2, 6.55, -(a + 22.0)), Models.ngon(0.55, 8), 0.0, 0.1, HAZARD)
					b.box(Vector3(x, 1.8, -(a + 1.05)), Vector3(4.6, 0.4, 0.1), accent)
			"hangar":
				# the island: a control tower on the starboard edge, with a mast and a radar
				var x := hw(id, a + 20.0) - 3.2
				b.prism(Vector3(x, 0, -(a + 22.0)), poly([[-2.2, -9.0], [2.2, -9.0], [2.2, 7.0], [0.6, 9.0], [-1.4, 9.0], [-2.2, 7.0]]), 0.0, 7.0, armour, Vector2(0.9, 0.92))
				b.prism(Vector3(x, 0, -(a + 20.0)), poly([[-1.8, -5.0], [1.8, -5.0], [1.8, 4.0], [-1.8, 4.0]]), 7.0, 10.0, (pt[1] as Color).lightened(0.08))
				b.box(Vector3(x, 9.0, -(a + 16.0) + 0.02), Vector3(3.2, 0.8, 0.1), Models.GLASS_D)
				b.prism(Vector3(x, 0, -(a + 21.0)), Models.ngon(0.3, 6), 10.0, 15.0, trim)
				b.box(Vector3(x, 13.5, -(a + 21.0)), Vector3(3.0, 0.2, 0.3), trim)
				b.box(Vector3(x, 15.3, -(a + 21.0)), Vector3(2.0, 0.6, 0.2), accent)
				# a deck crane on the port side
				var cx := -(hw(id, a + 30.0) - 2.5)
				b.prism(Vector3(cx, 0, -(a + 30.0)), Models.ngon(0.8, 8), 0.0, 5.0, trim)
				b.box(Vector3(cx + 2.4, 5.2, -(a + 30.0)), Vector3(6.0, 0.5, 0.6), accent.darkened(0.2))
			"guns":
				# the fire-control tower at the back of the gun deck, a rangefinder across its top
				var z := a + len - 7.0
				b.prism(Vector3(0, 0, -z), poly([[-3.4, -3.0], [3.4, -3.0], [3.4, 2.0], [2.2, 3.0], [-2.2, 3.0], [-3.4, 2.0]]), 0.0, 6.0, armour, Vector2(0.8, 0.85))
				b.prism(Vector3(0, 0, -z), Models.ngon(1.6, 8), 6.0, 9.0, trim)
				b.box(Vector3(0, 9.6, -z), Vector3(9.0, 0.9, 1.0), armour.lightened(0.08))
				for sx: float in [-1.0, 1.0]:
					b.prism(Vector3(sx * 4.5, 9.6, -z + 0.5), Models.ngon(0.55, 8), -0.45, 0.45, Models.GLASS_D)
				b.box(Vector3(0, 4.8, -z + 2.6), Vector3(5.0, 0.4, 0.1), accent)
			"missiles":
				# a magazine block across the back, its hatches and loading cranes
				var z := a + len - 8.0
				var w := minf(10.5, hw(id, z) - 2.5)
				b.prism(Vector3(0, 0, -z), poly([[-w, -3.5], [w, -3.5], [w, 3.0], [w - 1.5, 3.5], [-w + 1.5, 3.5], [-w, 3.0]]), 0.0, 4.2, armour, Vector2(0.95, 0.9))
				for k in 4:
					b.box(Vector3((k - 1.5) * w * 0.5, 4.25, -z), Vector3(w * 0.36, 0.14, 4.0), trim)
				b.box(Vector3(0, 2.6, -z + 3.52), Vector3(w * 1.8, 0.35, 0.1), accent)
				for sx: float in [-1.0, 1.0]:
					b.prism(Vector3(sx * (w - 1.0), 4.2, -z), Models.ngon(0.4, 6), 0.0, 3.0, trim)
					b.box(Vector3(sx * (w - 2.4), 7.3, -z), Vector3(3.2, 0.35, 0.35), accent.darkened(0.2))
			"lances":
				# a capacitor bank at the back: a row of tall glowing-capped drums
				var z := a + len - 7.0
				for k in 5:
					var x := (k - 2.0) * 3.2
					b.prism(Vector3(x, 0, -z), Models.ngon(1.2, 10), 0.0, 5.0 + (2 - absi(k - 2)) * 0.8, armour)
					b.prism(Vector3(x, 5.0 + (2 - absi(k - 2)) * 0.8, -z), Models.ngon(0.9, 10), 0.0, 0.3, accent)
				b.box(Vector3(0, 1.0, -z), Vector3(15.0, 2.0, 1.8), trim)
			"bridge":
				# the reactor's armoured shell, in front of the second tier
				var c := Vector3(0, 4.0, -(a + CORE_DZ))
				var rings: Array = []
				for k in 6:
					var ang := PI * 0.5 * k / 5.0
					rings.append(Models.oval(c + Vector3(0, sin(ang) * 3.6, 0), Vector3(cos(ang) * 3.4 + 0.02, 0, 0), Vector3(0, 0, cos(ang) * 3.2 + 0.02), 2.0, 12))
				b.loft(rings, func(p: Vector3) -> Color: return accent if absf(p.y - c.y - 1.6) < 0.25 else armour, false, true, true)
				for k in 3:
					var ang := (k - 1) * 0.7
					b.box(c + Vector3(sin(ang) * 3.0, 1.0, cos(ang) * 2.9), Vector3(1.0, 2.0, 0.4), trim)
		return b.commit())


## The ship's lights: deck-edge strips and the hangar's lift lights (a glow mesh).
static func lights(id: String) -> Mesh:
	return Models.cached("cap_lights_" + id, func() -> Mesh:
		var b := B.new()
		var L := Rules.fortress_len(id) - Rules.BOW_LEN
		var d := 2.0
		while d < L:
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(sx * (hw(id, d) - 0.9), 0.08, -d), Vector3(0.35, 0.08, 0.7), LIGHT)
			d += 6.0
		return b.commit())


# ---------------------------------------------------------------- guns
## A gun's mesh, facing +z (aft) round its hit point; its base sits `Rules.GUN_H` below.
static func gun(kind: String, id: String) -> Mesh:
	return Models.cached("cap_gun_%s_%s" % [kind, id], func() -> Mesh:
		var b := B.new()
		var pt: Array = paint(id)
		var body: Color = (pt[1] as Color).lerp(Models.FOE_D, 0.35)
		var dark: Color = pt[2]
		var accent: Color = fort(id).accent
		var red := Models.FOE
		var h: float = Rules.GUN_H[kind]
		match kind:
			"twin":
				b.prism(Vector3(0, 0, 0), Models.ngon(1.6, 10), -h, -h + 0.7, dark)
				b.prism(Vector3(0, 0, -0.2), poly([[-1.5, -1.7], [1.5, -1.7], [1.5, 0.9], [0.9, 1.7], [-0.9, 1.7], [-1.5, 0.9]]), -h + 0.7, 0.6, body, Vector2(0.85, 0.9))
				b.box(Vector3(0, 0.0, 1.45), Vector3(1.6, 0.6, 0.1), red)
				for sx: float in [-0.5, 0.5]:
					b.box(Vector3(sx, -0.1, 3.0), Vector3(0.32, 0.32, 3.0), dark)
					b.box(Vector3(sx, -0.1, 4.4), Vector3(0.42, 0.42, 0.35), accent)
			"quad":
				b.prism(Vector3.ZERO, Models.ngon(1.5, 8), -h, -0.1, body, Vector2(0.85, 0.85))
				b.prism(Vector3.ZERO, Models.ngon(1.0, 8), -0.1, 0.4, dark)
				var keep := b.xf
				b.xf = Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(0, 0.1, 0.4))
				for k in 4:
					var x := (k % 2 - 0.5) * 0.7
					var y := (k / 2) * 0.55 - 0.1
					b.box(Vector3(x, y, 1.3), Vector3(0.22, 0.22, 2.2), dark)
					b.box(Vector3(x, y, 2.45), Vector3(0.3, 0.3, 0.2), red)
				b.xf = keep
			"pod":
				b.prism(Vector3.ZERO, Models.ngon(0.7, 6), -h, -0.8, dark)
				var keep := b.xf
				b.xf = Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 0, 0))
				b.box(Vector3(0, 0, 0), Vector3(2.6, 1.8, 2.4), body)
				for k in 6:
					var x := (k % 3 - 1) * 0.78
					var y := (k / 3 - 0.5) * 0.78
					b.box(Vector3(x, y, 1.22), Vector3(0.6, 0.6, 0.06), Models.HULL_D.darkened(0.4))
					b.box(Vector3(x, y, 1.26), Vector3(0.3, 0.3, 0.06), red)
				b.box(Vector3(0, 0.95, 0), Vector3(2.7, 0.12, 2.5), accent)
				b.xf = keep
			"mast":
				# a tall tapered mast, collared, with the lance's emitter at its tip (glow, `gun_glow`)
				b.prism(Vector3.ZERO, Models.ngon(1.0, 6), -h, -h + 0.8, dark)
				b.prism(Vector3.ZERO, Models.ngon(0.7, 4, PI / 4), -h + 0.8, -0.6, body, Vector2(0.45, 0.45))
				for k in 3:
					b.prism(Vector3.ZERO, Models.ngon(0.75 - k * 0.12, 8), -h + 1.6 + k * 1.5, -h + 1.85 + k * 1.5, accent)
				b.octa(Vector3(0, -0.6, 0), 0.6, dark, Vector3(1, 0.6, 1))
			"dish":
				# a pedestal and a big radar dish on a yoke (the node spins it)
				b.prism(Vector3.ZERO, Models.ngon(0.6, 6), -h, -0.9, dark)
				b.box(Vector3(0, -0.7, 0), Vector3(2.4, 0.4, 0.6), body)
				var rings: Array = []
				for k in 4:
					var rr := 0.3 + k * 0.75
					rings.append(Models.oval(Vector3(0, 0.3, 0.9 - k * k * 0.12), Vector3(rr, 0, 0), Vector3(0, rr, 0), 2.0, 14))
				b.loft(rings, func(p: Vector3) -> Color: return accent if Vector2(p.x, p.y - 0.3).length() > 2.3 else Models.STEEL_D, false, true, false)
				b.box(Vector3(0, 0.3, 1.5), Vector3(0.15, 0.15, 1.6), dark)
				b.octa(Vector3(0, 0.3, 2.3), 0.3, red)
			"pylon":
				# an obelisk on a stepped plinth; its glowing ring is `gun_glow`
				b.prism(Vector3.ZERO, Models.ngon(1.3, 4, PI / 4), -h, -h + 0.6, dark)
				b.prism(Vector3.ZERO, Models.ngon(0.9, 4, PI / 4), -h + 0.6, 1.4, body, Vector2(0.35, 0.35))
				b.octa(Vector3(0, 1.7, 0), 0.4, Models.CYAN)
			"hatch":
				# an armoured hatch flush with the deck, hazard-striped, doors ajar
				for k in 8:
					var a := TAU * k / 8.0
					b.box(Vector3(cos(a) * 2.1, -h + 0.12, sin(a) * 2.1), Vector3(1.0, 0.24, 1.0), accent if k % 2 else HAZARD)
				b.prism(Vector3.ZERO, Models.ngon(1.9, 8), -h, -h + 0.05, Color8(0x10, 0x12, 0x16))
				for sx: float in [-1.0, 1.0]:
					var keep := b.xf
					b.xf = Transform3D(Basis(Vector3.BACK, sx * 0.5), Vector3(sx * 1.8, -h + 0.2, 0))
					b.box(Vector3(-sx * 0.9, 0.1, 0), Vector3(1.8, 0.22, 3.4), body)
					b.xf = keep
				b.prism(Vector3.ZERO, Models.ngon(0.6, 8), -h + 0.05, 0.0, red)
			"nozzle":
				# an engine bell on the stern's face, facing aft; its fire is `gun_glow`
				var rings: Array = []
				for k in 4:
					var rr := 2.3 + k * 0.18
					rings.append(Models.oval(Vector3(0, 0, -0.8 + k * 0.7), Vector3(rr, 0, 0), Vector3(0, rr, 0), 2.0, 16))
				b.loft(rings, Models.STEEL_D.darkened(0.25), true, false, false)
				b.loft(rings, dark, false, false, false)
				for k in 8:
					var a := TAU * k / 8.0
					b.box(Vector3(cos(a) * 2.75, sin(a) * 2.75, 1.25), Vector3(0.5, 0.5, 0.4), accent if k % 2 else dark)
		return b.commit())


## A gun's glowing part (its own glow material), or null: the nozzle's fire, the lance's emitter,
## the pylon's ring.
static func gun_glow(kind: String) -> Mesh:
	match kind:
		"nozzle":
			return Models.cached("cap_glow_nozzle", func() -> Mesh:
				var b := B.new()
				b.prism(Vector3(0, 0, -0.4), Models.ngon(2.2, 16), -0.05, 0.05, Color.WHITE)
				return b.commit())
		"mast":
			return Models.cached("cap_glow_mast", func() -> Mesh:
				var b := B.new()
				b.octa(Vector3(0, 0.4, 0), 0.55, Color.WHITE, Vector3(1, 1.5, 1))
				return b.commit())
		"pylon":
			return Models.cached("cap_glow_pylon", func() -> Mesh:
				var b := B.new()
				for k in 12:
					var a := TAU * k / 12.0
					b.box(Vector3(cos(a) * 1.6, 0.6, sin(a) * 1.6), Vector3(0.55, 0.18, 0.55), Color.WHITE)
				return b.commit())
	return null


## The bubble over a gun shielded by its section's pylon.
static func bubble() -> Mesh:
	return Models.cached("cap_bubble", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 2.4
		s.height = 4.0
		s.radial_segments = 12
		s.rings = 6
		return s)


## An outline from [x, z] pairs.
static func poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out
