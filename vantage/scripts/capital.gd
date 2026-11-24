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
	if lofted(id):
		var c := body_at(id, bodies(id)[0], clampf(d, body_span(id, bodies(id)[0]).x, body_span(id, bodies(id)[0]).y))
		return maxf(0.6, float(c[2]) * 0.6)
	var L := Rules.fortress_len(id)
	var W := Rules.FORTRESS_HW
	var w := W
	match f.hull:
		"wedge":
			# widest just ahead of the stern, narrowing all the way to a sharp bow
			w = W * (0.9 + 0.1 * clampf(d / 12.0, 0.0, 1.0)) * (1.0 - 0.36 * clampf((d - 40.0) / (L - 80.0), 0.0, 1.0))
		"round":
			w = W * (0.82 + 0.18 * sin(clampf(d / 26.0, 0.0, 1.0) * PI * 0.5))
		"keel":
			# a galleon's: a little narrower aft, drawing in early towards a long bow
			w = W * (0.86 + 0.14 * clampf(d / 16.0, 0.0, 1.0)) * (1.0 - 0.18 * clampf((d - 70.0) / (L - 110.0), 0.0, 1.0))
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
		"keel":
			return PackedVector2Array([Vector2(w, 0), Vector2(w + 0.6, -1.8), Vector2(w * 0.88, -depth * 0.45),
				Vector2(w * 0.48, -depth * 0.88), Vector2(w * 0.08, -depth * 1.18)])
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
	var m := (r.x + r.y) * 0.5
	if lofted(id):
		return Vector3(track_x(id, i, m), float(bodies(id)[0].y), -m)
	return Vector3(0, -Rules.HULL_DEPTH * 0.45, -m)


## The reactor: in front of the bridge's second tier, or slung under the hull below a gondola.
static func core_at(id: String) -> Vector3:
	var n := real_sections(id) - 1
	var d := Rules.section_at(id, n) + CORE_DZ
	var x := track_x(id, n, d)
	if fort(id).sections[n].kind == "gondola":
		return Vector3(x, bottom_y(id, d, x) - 3.8, -d)
	return Vector3(x, CORE_Y, -d)


## A quad from points given as (x, y, -d): its colour, facing `out`.
static func q(b: B, a: Vector3, c: Vector3, d: Vector3, e: Vector3, col: Color, out: Vector3) -> void:
	b.quad(a, c, d, e, col, out)


## Section i's segment of hull with its deck's fittings, in the model frame.
static func segment(id: String, i: int) -> Mesh:
	return Models.cached("cap_seg_%s_%d" % [id, i], func() -> Mesh:
		var b := B.new()
		if lofted(id):
			body_segment(b, id, i)
			fittings(b, id, i)
			extras(b, id, i)
			return b.commit()
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
		extras(b, id, i)
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
	# a ring of armour under each deck gun, a sponson under each gun on a flank, a hanger over
	# each slung under the hull
	for g: Array in sec.guns:
		mount_fitting(b, id, i, g)
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
		"bays":
			bay_doors(b, id, i)
		"gondola":
			gondola(b, id, i)


## The bridge: three stepped tiers, glazed at the top, a mast and antennas over it.
static func bridge(b: B, id: String, i: int) -> void:
	var f := fort(id)
	var pt: Array = paint(id)
	var a := Rules.section_at(id, i)
	var accent: Color = f.accent
	var y0 := 0.0
	var k := 0
	if lofted(id):
		# a skirt down into the curved top under the bottom tier
		var t0: Array = TIERS[0]
		b.prism(Vector3(0, 0, -(a + (t0[0] + t0[1]) * 0.5)), poly([[-t0[2], -(t0[1] - t0[0]) * 0.5], [t0[2], -(t0[1] - t0[0]) * 0.5],
			[t0[2], (t0[1] - t0[0]) * 0.5], [-t0[2], (t0[1] - t0[0]) * 0.5]]), -5.0, 0.05, (pt[1] as Color).darkened(0.1))
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
					var x := sx * maxf(hw(id, 12.0) - 4.2, 3.4) + track_x(id, i, a + 12.0)
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
			"battery", "bays":
				galleries(b, id, i, armour, trim, accent)
			"spires":
				crystals(b, id, i, accent, 1.0)
			"gondola":
				# the reactor's armoured shell, slung under the hull
				var c := core_at(id) + Vector3(0, 0.4, 0)
				var rings: Array = []
				for k in 6:
					var ang := PI * 0.5 * k / 5.0
					rings.append(Models.oval(c - Vector3(0, sin(ang) * 3.6, 0), Vector3(cos(ang) * 3.4 + 0.02, 0, 0), Vector3(0, 0, cos(ang) * 3.2 + 0.02), 2.0, 12))
				b.loft(rings, func(p: Vector3) -> Color: return accent if absf(p.y - c.y + 1.6) < 0.25 else armour, false, true, true)
				b.prism(c + Vector3(0, 0, 0), Models.ngon(4.2, 12), 0.0, 1.6, trim)
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
		if lofted(id):
			# along the main body's back, and round the pods and nacelles
			for bd: Dictionary in bodies(id):
				var sp := body_span(id, bd)
				d = sp.x + 3.0
				while d < sp.y - 3.0:
					var c := body_at(id, bd, d)
					if bd.get("role", "hull") == "wing":
						b.box(Vector3(c[0] + signf(c[0]) * (c[2] - 0.6), c[1], -d), Vector3(0.5, 0.25, 0.8), LIGHT)
					else:
						for sx: float in [-1.0, 1.0]:
							var x: float = c[0] + sx * c[2] * 0.62
							b.box(Vector3(x, top_y(id, d, x) + 0.05, -d), Vector3(0.35, 0.12, 0.7), LIGHT)
					d += 7.0
			return b.commit()
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


# ---------------------------------------------------------------- lofted bodies
## Ships built from smooth `bodies` (`Rules.FORTRESSES`) instead of a plated deck over a hull side:
## each body is a squircle (`n`: 2 round, higher squarer) `w` wide either side, `t` above and `b`
## below its centre (`x`, `y`), from `from` to `to` m from the stern (negative: from the bow),
## rounding off over `tail` m at the stern end and `nose` m at the bow end to `tip`/`nose_tip` of
## its size (`nose_p` < 2 sharpens the nose). A wing body sweeps in by `sweep` m a metre, a serpent's
## winds by `wave` [amplitude, period, phase]. Its `role` (hull, keel, pod, wing) picks its colours.
const RING_N := 24
## How far a flank gun's centre stands out from the hull, on its sponson.
const SPONSON := 2.4
## The last section before the reactor.
const HEARTS := ["bridge", "gondola"]
## How far a lane is from the flank it runs along, and the nearest the ship gets to it.
const FLANK := 10.5
const FLANK_IN := 3.5
## How far below the hull the ship flies under it, and the nearest it gets.
const UNDER := 12.0
const UNDER_IN := 6.5
## The clearance a glide keeps from the hull (`glide`).
const GLIDE_M := 4.0
## A glide's speed across (m/s): a long way round takes longer than `Rules.ADVANCE`.
const GLIDE_V := 44.0

static var _loops := {}
static var _lanes := {}
static var _mounts := {}


static func lofted(id: String) -> bool:
	return fort(id).has("bodies")


static func bodies(id: String) -> Array:
	return fort(id).get("bodies", [])


## How the ship passes section i: stern, top, left, right, under or gap.
static func route_of(id: String, i: int) -> String:
	var sec: Dictionary = fort(id).sections[i]
	return sec.get("route", "stern" if sec.kind == "engines" else "top")


## Where a body starts and ends (m from the stern).
static func body_span(id: String, bd: Dictionary) -> Vector2:
	var L := Rules.fortress_len(id)
	var a: float = bd.get("from", 0.0)
	var e: float = bd.get("to", L)
	if a < 0.0:
		a += L
	if e <= 0.0:
		e += L
	return Vector2(a, e)


## A serpent's sideways wind at d.
static func wave(bd: Dictionary, d: float) -> float:
	var wv: Array = bd.get("wave", [])
	if wv.is_empty():
		return 0.0
	return float(wv[0]) * sin(TAU * d / float(wv[1]) + float(wv[2]))


## A body's cross-section at d: [centre x, centre y, half width, top, bottom], or [] past its ends.
static func body_at(id: String, bd: Dictionary, d: float) -> Array:
	var sp := body_span(id, bd)
	if d < sp.x - 0.001 or d > sp.y + 0.001:
		return []
	var s := 1.0
	var tl: float = bd.get("tail", 0.0)
	if tl > 0.0:
		var u := clampf((d - sp.x) / tl, 0.0, 1.0)
		var tip: float = bd.get("tip", 0.3)
		s = minf(s, tip + (1.0 - tip) * sqrt(1.0 - (1.0 - u) * (1.0 - u)))
	var nl: float = bd.get("nose", 0.0)
	if nl > 0.0:
		var u := clampf((sp.y - d) / nl, 0.0, 1.0)
		var tip: float = bd.get("nose_tip", 0.3)
		var p: float = bd.get("nose_p", 2.0)
		s = minf(s, tip + (1.0 - tip) * pow(1.0 - pow(1.0 - u, p), 1.0 / p))
	var cx := float(bd.get("x", 0.0))
	var sw: float = bd.get("sweep", 0.0)
	if sw != 0.0:
		cx -= signf(cx) * sw * (d - sp.x)
	cx += wave(bd, d)
	return [cx, float(bd.y), float(bd.w) * s, float(bd.t) * s, float(bd.b) * s]


## A body's outline at d (x, y), or empty.
static func body_loop(id: String, bd: Dictionary, d: float) -> PackedVector2Array:
	var c := body_at(id, bd, d)
	var out := PackedVector2Array()
	if c.is_empty():
		return out
	var n: float = bd.get("n", 2.4)
	for k in RING_N:
		var q := Models.squircle(TAU * k / RING_N, n)
		out.append(Vector2(c[0] + c[2] * q.x, c[1] + (c[3] if q.y > 0.0 else c[4]) * q.y))
	return out


## The hull's outlines across the ship d m from the stern (one a body; a plated hull's runs from
## the deck's edge down its side to the keel and back up).
static func loops(id: String, d: float) -> Array:
	var key := "%s/%d" % [id, roundi(d * 2.0)]
	if _loops.has(key):
		return _loops[key]
	d = roundf(d * 2.0) * 0.5
	var out: Array = []
	if lofted(id):
		for bd: Dictionary in bodies(id):
			var r := body_loop(id, bd, d)
			if r.size() > 0:
				out.append(r)
	elif d >= 0.0 and d <= Rules.fortress_len(id):
		var w := hw(id, d)
		var s := side(fort(id).hull, w, Rules.HULL_DEPTH * (0.3 + 0.7 * w / Rules.FORTRESS_HW))
		var loop := PackedVector2Array()
		for p in s:
			loop.append(p)
		for j in range(s.size() - 1, -1, -1):
			loop.append(Vector2(-s[j].x, s[j].y))
		out.append(loop)
	_loops[key] = out
	return out


## How far a ray from o along dir goes before it meets the hull at d (INF: it doesn't).
static func ray(id: String, d: float, o: Vector2, dir: Vector2) -> float:
	var best := INF
	var far := o + dir * 1000.0
	for loop: PackedVector2Array in loops(id, d):
		var n := loop.size()
		for k in n:
			var hit: Variant = Geometry2D.segment_intersects_segment(o, far, loop[k], loop[(k + 1) % n])
			if hit != null:
				best = minf(best, ((hit as Vector2) - o).length())
	return best


## The hull's top at (d, x), or -INF where there's none.
static func top_y(id: String, d: float, x: float) -> float:
	var t := ray(id, d, Vector2(x, 200.0), Vector2(0, -1))
	return 200.0 - t if t < INF else -INF


## The hull's underside at (d, x), or INF where there's none.
static func bottom_y(id: String, d: float, x: float) -> float:
	var t := ray(id, d, Vector2(x, -300.0), Vector2(0, 1))
	return -300.0 + t if t < INF else INF


## Whether p (x, y) is in the hull at d, or within `margin` of it.
static func inside(id: String, d: float, p: Vector2, margin: float) -> bool:
	for loop: PackedVector2Array in loops(id, d):
		if Geometry2D.is_point_in_polygon(p, loop):
			return true
		var n := loop.size()
		for k in n:
			if Geometry2D.get_closest_point_to_segment(p, loop[k], loop[(k + 1) % n]).distance_squared_to(p) < margin * margin:
				return true
	return false


## How far out the hull reaches either side at d (m from the centre line).
static func extent(id: String, d: float) -> float:
	var e := 0.0
	for loop: PackedVector2Array in loops(id, d):
		for p in loop:
			e = maxf(e, absf(p.x))
	return e


## The x a section's guns and lanes are placed from: its `x`, and a serpent's wind at d.
static func track_x(id: String, i: int, d: float) -> float:
	var sec: Dictionary = fort(id).sections[mini(i, fort(id).sections.size() - 1)]
	var x: float = sec.get("x", 0.0)
	if lofted(id) and not sec.has("x"):
		x += wave(bodies(id)[0], d)
	return x


## Where a gun stands (`at`, its hit point) and how: `deck` (on the top, an armour ring round it),
## `fixed` (placed by hand: up the bridge, on the stern's face), `side` (on a sponson standing `out`
## from the face at x = `face`) or `hang` (slung under the hull, whose underside is at y = `face`).
static func mount(id: String, i: int, g: Array) -> Dictionary:
	var key := "%s/%d/%s" % [id, i, str(g)]
	if _mounts.has(key):
		return _mounts[key]
	var route := route_of(id, i)
	var at := Rules.section_at(id, i)
	var h: float = Rules.GUN_H[g[0]]
	var m := {"how": "deck", "face": 0.0, "out": 0.0, "at": Vector3.ZERO}
	match route:
		"left", "right":
			var s := -1.0 if route == "left" else 1.0
			var d := at + float(g[2])
			var l := lane(id, i)
			var y := float(g[1])
			var t := ray(id, d, Vector2(l.x, y - h), Vector2(-s, 0))
			var face: float = l.x - s * t if t < INF else s * 3.0
			# every gun of a flank stands in one line, out from its widest
			m = {"how": "side", "face": face, "out": s, "at": Vector3(s * (float(l.ext) + SPONSON), y, -d)}
		"gap":
			var side := float(g[1])
			var y := float(g[2])
			var d := at + float(g[3])
			var l := lane(id, i)
			var t := ray(id, d, Vector2(l.x, y - h), Vector2(side, 0))
			var face: float = l.x + side * t if t < INF else l.x + side * 12.0
			var line: float = l.left + SPONSON if side < 0.0 else l.right - SPONSON
			m = {"how": "side", "face": face, "out": -side, "at": Vector3(line, y, -d)}
		"under":
			var d := at + float(g[2])
			var x := track_x(id, i, d) + float(g[1])
			var yb := bottom_y(id, d, x)
			if yb == INF:
				yb = -Rules.HULL_DEPTH
			m = {"how": "hang", "face": yb, "out": 0.0, "at": Vector3(x, yb - h, -d)}
		_:
			if g.size() >= 4:
				var d := at + float(g[3])
				m = {"how": "fixed", "face": 0.0, "out": 0.0, "at": Vector3(float(g[1]) + track_x(id, i, d), float(g[2]), -d)}
			else:
				var d := at + float(g[2])
				var x := track_x(id, i, d) + float(g[1])
				var y := top_y(id, d, x)
				if y == -INF:
					y = 0.0
				m = {"how": "deck", "face": y, "out": 0.0, "at": Vector3(x, y + h, -d)}
	_mounts[key] = m
	return m


## Where the ship flies while fighting section i (the reactor: from the section before it): `x`
## across, `y` above the deck line, `along` m ahead of the stern; how far the drag may take it
## from there (`reach`: x min, x max, y min, y max), its guns' dip (`dip`, negative: up) and the
## camera's offsets (`cam`: height above the ship, the look's height, sideways, the look sideways).
## Over the top it flies `Rules.FLY` above the hull; along a flank `FLANK` out from its widest
## (no nearer than `FLANK_IN`); beneath, `UNDER` below its lowest (no nearer than `UNDER_IN`);
## between two hulls, down the middle, kept clear of both faces and the wing below.
static func lane(id: String, i: int) -> Dictionary:
	var secs: Array = fort(id).sections
	i = clampi(i, 0, secs.size() - 1)
	if secs[i].kind == "core":
		i -= 1
	var key := "%s/%d" % [id, i]
	if _lanes.has(key):
		return _lanes[key]
	var sec: Dictionary = secs[i]
	var route := route_of(id, i)
	var at := Rules.section_at(id, i)
	var hi := at + float(sec.len)
	var along := at - Rules.LEAD - (10.0 if route == "stern" else 0.0)
	var lo := maxf(0.0, along - 4.0)
	var x := track_x(id, i, (at + hi) * 0.5)
	var y := 0.0
	var reach := Vector4(-Rules.POV_REACH.x, Rules.POV_REACH.x, -Rules.POV_DOWN, Rules.POV_REACH.y)
	var dip := Rules.AIM_DIP
	var cam := Vector4(4.2, -0.5, 0.0, 0.0)
	var extra := {}
	match route:
		"stern":
			x = sec.get("x", 0.0)
			y = sec.get("y", -0.5)
		"top":
			var top := -INF
			var d := lo
			while d <= hi:
				for dx: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
					top = maxf(top, top_y(id, d, x + dx))
				d += 2.0
			y = (top if top > -INF else 0.0) + Rules.FLY
		"left", "right":
			# out from the flank's widest, where the ship flies and where its guns stand
			var s := -1.0 if route == "left" else 1.0
			y = sec.get("y", -4.0)
			var ext := 0.0
			var d := lo
			while d <= hi:
				if d <= along + 4.0 or d >= at:
					var yy := y - 6.0
					while yy <= y + 10.0:
						var t := ray(id, d, Vector2(s * 400.0, yy), Vector2(-s, 0))
						if t < INF:
							ext = maxf(ext, 400.0 - t)
						yy += 1.5
				d += 2.0
			x = s * (ext + FLANK)
			extra = {"ext": ext}
			if s < 0.0:
				reach.y = minf(reach.y, FLANK - FLANK_IN)
			else:
				reach.x = maxf(reach.x, FLANK_IN - FLANK)
			dip = 0.03
			cam = Vector4(3.0, 0.3, s * 3.0, -s * 5.0)
		"under":
			x = sec.get("x", x)
			var low := INF
			var d := lo
			while d <= hi:
				var dx := -12.0
				while dx <= 12.0:
					low = minf(low, bottom_y(id, d, x + dx))
					dx += 2.0
				d += 2.0
			if low == INF:
				low = -Rules.HULL_DEPTH
			y = low - UNDER
			reach.w = UNDER - UNDER_IN
			dip = -0.22
			cam = Vector4(-2.0, 3.5, 0.0, 0.0)
		"gap":
			x = sec.get("x", 0.0)
			y = sec.get("y", -4.0)
			var left := -INF
			var right := INF
			var fl := -INF
			var d := lo
			while d <= hi:
				var yy := y - 4.0
				while yy <= y + 7.0:
					var tl := ray(id, d, Vector2(x, yy), Vector2(-1, 0))
					var tr := ray(id, d, Vector2(x, yy), Vector2(1, 0))
					if tl < INF:
						left = maxf(left, x - tl)
					if tr < INF:
						right = minf(right, x + tr)
					yy += 1.5
				for dx: float in [-3.0, 0.0, 3.0]:
					var t := ray(id, d, Vector2(x + dx, y), Vector2(0, -1))
					if t < INF:
						fl = maxf(fl, y - t)
				d += 2.0
			reach.x = maxf(reach.x, left + FLANK_IN - x)
			reach.y = minf(reach.y, right - FLANK_IN - x)
			extra = {"left": left, "right": right}
			if fl > -INF:
				reach.z = maxf(reach.z, fl + 3.0 - y)
			dip = 0.06
			cam = Vector4(3.8, -0.5, 0.0, 0.0)
	var l := {"x": x, "y": y, "along": along, "reach": reach, "dip": dip, "cam": cam, "route": route}
	l.merge(extra)
	_lanes[key] = l
	return l


## The way from one lane to the next ([x, y, along] to [x, y, along]), as points across (x, y):
## straight there, across first, up or down first, over the top, or round either flank,
## whichever is shortest and keeps `GLIDE_M` clear of the hull all the way (the ship goes along
## at the same pace as across).
static func glide(id: String, a: Vector3, b: Vector3) -> PackedVector2Array:
	var A := Vector2(a.x, a.y)
	var Bp := Vector2(b.x, b.y)
	var high := maxf(A.y, Bp.y)
	var ext := 0.0
	var d := minf(a.z, b.z)
	while d <= maxf(a.z, b.z):
		ext = maxf(ext, extent(id, d))
		var xx := -80.0
		while xx <= 80.0:
			high = maxf(high, top_y(id, d, xx) + GLIDE_M + 4.0)
			xx += 4.0
		d += 4.0
	var cands: Array = [
		PackedVector2Array([A, Bp]),
		PackedVector2Array([A, Vector2(Bp.x, A.y), Bp]),
		PackedVector2Array([A, Vector2(A.x, Bp.y), Bp]),
		PackedVector2Array([A, Vector2(A.x, high), Vector2(Bp.x, high), Bp]),
	]
	for s: float in [-1.0, 1.0]:
		var sx := s * (ext + GLIDE_M + 8.0)
		cands.append(PackedVector2Array([A, Vector2(sx, A.y), Vector2(sx, Bp.y), Bp]))
		cands.append(PackedVector2Array([A, Vector2(A.x, high), Vector2(sx, high), Vector2(sx, Bp.y), Bp]))
		cands.append(PackedVector2Array([A, Vector2(sx, A.y), Vector2(sx, high), Vector2(Bp.x, high), Bp]))
	var best := PackedVector2Array()
	var best_len := INF
	var least := 1 << 30
	for c: PackedVector2Array in cands:
		var hits := glide_hits(id, c, a.z, b.z)
		var len := path_len(c)
		if hits < least or (hits == least and len < best_len):
			least = hits
			best_len = len
			best = c
	return best


## How many points along a glide come within `GLIDE_M` of the hull.
static func glide_hits(id: String, pts: PackedVector2Array, z0: float, z1: float) -> int:
	var n := 0
	for k in range(3, 58):
		var e := k / 60.0
		if inside(id, lerpf(z0, z1, e), path_at(pts, e), GLIDE_M):
			n += 1
	return n


static func path_len(pts: PackedVector2Array) -> float:
	var len := 0.0
	for k in pts.size() - 1:
		len += pts[k].distance_to(pts[k + 1])
	return len


## The point a share e of the way along a path.
static func path_at(pts: PackedVector2Array, e: float) -> Vector2:
	var total := path_len(pts)
	if total < 0.001:
		return pts[pts.size() - 1]
	var want := clampf(e, 0.0, 1.0) * total
	for k in pts.size() - 1:
		var seg := pts[k].distance_to(pts[k + 1])
		if want <= seg or k == pts.size() - 2:
			return pts[k].lerp(pts[k + 1], clampf(want / maxf(seg, 0.001), 0.0, 1.0))
		want -= seg
	return pts[pts.size() - 1]


## How long a glide takes: `Rules.ADVANCE`, or longer on a long way round.
static func glide_time(pts: PackedVector2Array) -> float:
	return maxf(Rules.ADVANCE, path_len(pts) / GLIDE_V)


## A point on the hull's top in segment i (u, v from 0 to 1 across and along), for fires.
static func deck_point(id: String, i: int, u: float, v: float) -> Vector3:
	var r := seg_range(id, i)
	var d := lerpf(r.x + 2.0, r.y - 2.0, v)
	if not lofted(id):
		return Vector3((u * 2.0 - 1.0) * 0.7 * hw(id, d), 0.4, -d)
	var best: Array = []
	for bd: Dictionary in bodies(id):
		var c := body_at(id, bd, d)
		if not c.is_empty() and (best.is_empty() or c[2] > best[2]):
			best = c
	if best.is_empty():
		return Vector3(0, 0, -d)
	var x: float = best[0] + (u * 2.0 - 1.0) * best[2] * 0.6
	return Vector3(x, top_y(id, d, x) + 0.4, -d)


## A body's colour at a point on it: its top, its flanks (an accent line along the widest), its belly.
static func body_col(id: String, bd: Dictionary, p: Vector3) -> Color:
	var c := body_at(id, bd, clampf(-p.z, body_span(id, bd).x, body_span(id, bd).y))
	var pt: Array = paint(id)
	var accent: Color = fort(id).accent
	var rel := 0.0
	if not c.is_empty():
		rel = (p.y - c[1]) / maxf(0.01, c[3] if p.y > c[1] else c[4])
	var top: Color = pt[0]
	var flank: Color = pt[1]
	var belly: Color = (pt[2] as Color).lerp(pt[1], 0.4)
	match bd.get("role", "hull"):
		"keel":
			top = pt[1]
			flank = (pt[1] as Color).lerp(pt[2], 0.4)
			belly = pt[2]
		"pod":
			top = (pt[0] as Color).lerp(accent, 0.1)
		"wing":
			top = (pt[0] as Color).darkened(0.05)
			flank = (pt[1] as Color).darkened(0.05)
	if rel > 0.72:
		return top
	if absf(rel) < 0.04 and bd.get("role", "hull") != "wing":
		return accent.darkened(0.12)
	if rel > -0.5:
		return flank.lerp(top, clampf(rel, 0.0, 0.72) * 0.25)
	return belly


## Section i's stretch of each body: smooth lofted skins, closed at both ends.
static func body_segment(b: B, id: String, i: int) -> void:
	var r := seg_range(id, i)
	for bd: Dictionary in bodies(id):
		var sp := body_span(id, bd)
		var a := maxf(r.x, sp.x)
		var e := minf(r.y, sp.y)
		if e - a < 0.2:
			continue
		var ds: Array[float] = [a]
		var d := ceilf(a / 3.0) * 3.0
		while d < e - 0.6:
			if d > a + 0.6:
				ds.append(d)
			d += 3.0
		ds.append(e)
		var rings: Array = []
		for dd in ds:
			var lp := body_loop(id, bd, dd)
			var ring := PackedVector3Array()
			for q in lp:
				ring.append(Vector3(q.x, q.y, -dd))
			rings.append(ring)
		b.loft(rings, func(p: Vector3) -> Color: return body_col(id, bd, p), false, true, true)
	# a dashed line down the main body's back
	var pt: Array = paint(id)
	var accent: Color = fort(id).accent
	var bd0: Dictionary = bodies(id)[0]
	var dd := ceilf(r.x / 8.0) * 8.0 + 2.0
	while dd < r.y - 2.0:
		var c := body_at(id, bd0, dd)
		if not c.is_empty() and c[2] > 6.0:
			var y := top_y(id, dd, c[0])
			b.box(Vector3(c[0], y + 0.03, -dd), Vector3(0.6, 0.08, 2.6), accent.lerp(pt[0], 0.35))
		dd += 8.0


## The armour under a gun: a ring on the deck, a sponson out from a flank, a hanger under the hull.
static func mount_fitting(b: B, id: String, i: int, g: Array) -> void:
	var m := mount(id, i, g)
	var pt: Array = paint(id)
	var trim: Color = pt[2]
	var armour: Color = (pt[1] as Color).lerp(trim, 0.3)
	var accent: Color = fort(id).accent
	var at: Vector3 = m.at
	var h: float = Rules.GUN_H[g[0]]
	match m.how:
		"deck":
			if g[0] in ["twin", "quad", "pod", "dish", "mast", "pylon"]:
				b.prism(Vector3(at.x, 0, at.z), Models.ngon(2.1, 10), at.y - h - 0.6, at.y - h + 0.35, trim.lerp(accent, 0.15))
		"side":
			# a rounded platform from the face out under the gun, braced underneath
			var s: float = m.out
			var base := at.y - h
			var o := PackedVector2Array()
			for k in 9:
				var ang := -PI * 0.5 + PI * k / 8.0
				o.append(Vector2(at.x + s * cos(ang) * 2.2, sin(ang) * 2.2))
			o.append(Vector2(float(m.face) - s * 1.6, 2.2))
			o.append(Vector2(float(m.face) - s * 1.6, -2.2))
			if s < 0.0:
				o.reverse()
			b.prism(Vector3(0, 0, at.z), o, base - 0.55, base, armour)
			b.prism(Vector3(0, 0, at.z), poly([[float(m.face) - s * 1.4, -1.0], [at.x - s * 0.2, -0.7], [at.x - s * 0.2, 0.7], [float(m.face) - s * 1.4, 1.0]]) if s > 0.0
				else poly([[at.x - s * 0.2, -0.7], [float(m.face) - s * 1.4, -1.0], [float(m.face) - s * 1.4, 1.0], [at.x - s * 0.2, 0.7]]),
				base - 3.2, base - 0.55, trim, Vector2(1.0, 1.0))
			b.box(Vector3(at.x + s * 2.15, base - 0.28, at.z), Vector3(0.12, 0.3, 2.4), accent)
		"hang":
			var top: float = m.face
			b.prism(Vector3(at.x, 0, at.z), Models.ngon(1.9, 10), top - 0.35, top + 1.2, armour)
			b.prism(Vector3(at.x, 0, at.z), Models.ngon(2.2, 10), top - 0.5, top - 0.35, accent.darkened(0.2))


## Bay doors along the belly, between the guns slung under it.
static func bay_doors(b: B, id: String, i: int) -> void:
	var r := seg_range(id, i)
	var accent: Color = fort(id).accent
	var d := r.x + 6.0
	while d < r.y - 6.0:
		var x := track_x(id, i, d)
		var y := bottom_y(id, d, x)
		if y < INF:
			b.box(Vector3(x, y - 0.12, -d), Vector3(3.6, 0.24, 5.0), HAZARD)
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(x + sx * 1.95, y - 0.15, -d), Vector3(0.3, 0.3, 5.2), accent.darkened(0.15))
		d += 9.0


## The gondola heart: a glazed band under the hull and the reactor's socket.
static func gondola(b: B, id: String, i: int) -> void:
	var r := seg_range(id, i)
	var accent: Color = fort(id).accent
	var c := core_at(id)
	b.prism(Vector3(c.x, 0, c.z), Models.ngon(3.0, 10), c.y + 3.0, c.y + 4.4, HAZARD)
	var d := r.x + 26.0
	while d < r.y - 2.0:
		var x := track_x(id, i, d)
		var y := bottom_y(id, d, x)
		if y < INF:
			for sx: float in [-1.0, 1.0]:
				b.box(Vector3(x + sx * 2.6, y - 0.1, -d), Vector3(1.6, 0.3, 2.2), Models.GLASS_D)
			b.box(Vector3(x, y - 0.12, -d), Vector3(0.5, 0.3, 2.6), accent)
		d += 3.5


## A section's armour that breaks off: a gallery along the sponsons of each flank, a blister under
## the guns slung beneath, a barbette round each gun on the top and a fire-control dome behind them.
static func galleries(b: B, id: String, i: int, armour: Color, trim: Color, accent: Color) -> void:
	var sec: Dictionary = fort(id).sections[i]
	var groups := {}
	for g: Array in sec.guns:
		var m := mount(id, i, g)
		var k := "%s/%d" % [m.how, int(m.out)]
		if not groups.has(k):
			groups[k] = []
		groups[k].append([m, g])
	for k: String in groups:
		var list: Array = groups[k]
		var m0: Dictionary = list[0][0]
		var z0 := INF
		var z1 := -INF
		var face := 0.0
		var base := 0.0
		for e: Array in list:
			var m: Dictionary = e[0]
			var at: Vector3 = m.at
			z0 = minf(z0, -at.z)
			z1 = maxf(z1, -at.z)
			face += float(m.face)
			base += at.y - float(Rules.GUN_H[e[1][0]])
		face /= list.size()
		base /= list.size()
		match m0.how:
			"side":
				# a long rounded casemate along the face under the sponsons
				var s: float = m0.out
				var rings: Array = []
				var n := 8
				for j in n + 1:
					var d := lerpf(z0 - 5.0, z1 + 5.0, float(j) / n)
					var sc := 0.45 if j == 0 or j == n else 1.0
					rings.append(Models.oval(Vector3(face + s * 0.3, base - 1.6, -d), Vector3(1.9 * sc, 0, 0), Vector3(0, 1.9 * sc, 0), 2.4, 12))
				b.loft(rings, func(p: Vector3) -> Color: return accent if absf(p.y - base + 0.7) < 0.3 else armour, false, true, true)
			"hang":
				var rings: Array = []
				var n := 8
				for j in n + 1:
					var d := lerpf(z0 - 6.0, z1 + 6.0, float(j) / n)
					var x := track_x(id, i, d)
					var y := bottom_y(id, d, x)
					if y == INF:
						y = face
					var sc := 0.4 if j == 0 or j == n else 1.0
					rings.append(Models.oval(Vector3(x, y + 0.6, -d), Vector3(3.4 * sc, 0, 0), Vector3(0, 2.6 * sc, 0), 2.2, 14))
				b.loft(rings, func(p: Vector3) -> Color: return accent if absf(p.x - track_x(id, i, -p.z)) < 0.5 else armour, false, true, true)
			_:
				for e: Array in list:
					var m: Dictionary = e[0]
					var at: Vector3 = m.at
					var y: float = at.y - float(Rules.GUN_H[e[1][0]])
					b.prism(Vector3(at.x, 0, at.z - 1.2), poly([[-2.6, -0.6], [-1.8, -1.6], [1.8, -1.6], [2.6, -0.6], [2.4, 0.4], [-2.4, 0.4]]), y - 0.5, y + 1.3, armour, Vector2(0.9, 0.9))
				var dz := Rules.section_at(id, i) + float(sec.len) - 5.0
				var x := track_x(id, i, dz)
				var top := top_y(id, dz, x)
				if top > -INF:
					var c := Vector3(x, top - 0.2, -dz)
					var rings: Array = []
					for j in 6:
						var ang := PI * 0.5 * j / 5.0
						rings.append(Models.oval(c + Vector3(0, sin(ang) * 3.2, 0), Vector3(cos(ang) * 3.6 + 0.02, 0, 0), Vector3(0, 0, cos(ang) * 3.0 + 0.02), 2.0, 12))
					b.loft(rings, func(p: Vector3) -> Color: return accent if absf(p.y - c.y - 1.4) < 0.22 else armour, false, true, true)
					b.box(c + Vector3(0, 2.3, 2.6), Vector3(3.2, 0.5, 0.2), Models.GLASS_D)


## Ice crystals: long faceted spikes leaning out (`scale` 1 for the big cluster that breaks off).
static func crystals(b: B, id: String, i: int, accent: Color, scale: float) -> void:
	var r := seg_range(id, i)
	var ice := Color8(0xd8, 0xf4, 0xff)
	var d := r.x + r.y
	var spots: Array = [[0.0, r.y - 8.0, 7.0], [-3.0, r.y - 10.0, 5.0], [3.0, r.y - 9.5, 5.5], [-9.0, r.x + 20.0, 4.5], [9.0, r.x + 16.0, 4.0],
		[-1.5, r.y - 5.0, 4.0], [1.8, r.y - 13.0, 3.6]]
	for k in spots.size():
		var sp: Array = spots[k]
		var x: float = sp[0]
		var z: float = sp[1]
		var hgt: float = float(sp[2]) * scale
		var top := maxf(0.0, top_y(id, z, x))
		var keep := b.xf
		b.xf = Transform3D(Basis(Vector3.BACK, -x * 0.03).rotated(Vector3.RIGHT, 0.1 * (k % 3 - 1)), Vector3(x, top, -z))
		b.octa(Vector3(0, hgt * 0.5, 0), 1.0, ice.lerp(accent, 0.25 * (k % 2)), Vector3(0.9, hgt * 0.5, 0.9))
		b.xf = keep
	d = d


# ---------------------------------------------------------------- extras
## Each ship's own features, built into the segment they stand on.
static func extras(b: B, id: String, i: int) -> void:
	var f := fort(id)
	var pt: Array = paint(id)
	var accent: Color = f.accent
	var r := seg_range(id, i)
	var L := Rules.fortress_len(id)
	var last := i == real_sections(id) - 1
	for ex: String in f.get("extras", []):
		match ex:
			"fins":
				# an airship's tail: four swept fins in an X
				if i == 0:
					for k in 4:
						var ang := PI * 0.25 + PI * 0.5 * k
						var keep := b.xf
						b.xf = Transform3D(Basis(Vector3.BACK, ang), Vector3(0, float(bodies(id)[0].y), 0))
						b.prism(Vector3.ZERO, poly([[2.0, -2.0], [16.0, -1.0], [18.0, -9.0], [11.0, -34.0]]), -0.45, 0.45, pt[0] if k % 2 else (pt[1] as Color))
						b.prism(Vector3.ZERO, poly([[15.5, -1.2], [17.6, -1.0], [18.0, -9.0], [16.6, -9.6]]), -0.5, 0.5, accent)
						b.xf = keep
			"masts":
				# a galleon's masts, yards and fin sails, leaning out over the rails
				if not last:
					var z := (r.x + r.y) * 0.5 + 4.0
					for sx: float in [-1.0, 1.0]:
						var x := sx * 14.0
						b.prism(Vector3(x, 0, -z), Models.ngon(0.7, 8), 0.0, 30.0, (pt[2] as Color).lightened(0.1), Vector2(0.45, 0.45))
						b.prism(Vector3(x, 0, -z), Models.ngon(1.4, 8), 0.0, 1.0, pt[2])
						b.box(Vector3(x, 26.0, -z), Vector3(1.0, 0.4, 10.0), pt[2])
						b.octa(Vector3(x, 30.6, -z), 0.5, accent)
						sail(b, Vector3(x, 4.5, -z), Vector3(x, 28.0, -z + 0.5), Vector3(x + sx * 8.0, 7.0, -z + 9.0), sx, Color8(0xf0, 0xe2, 0xc4), accent)
			"tusk":
				# a narwhal's spiral tusk from the bow
				if last:
					var rings: Array = []
					for k in 16:
						var u := k / 15.0
						var rr := lerpf(2.6, 0.12, pow(u, 0.8))
						var ring := PackedVector3Array()
						for j in 10:
							var a := TAU * j / 10.0
							ring.append(Vector3(cos(a) * rr, -2.0 + sin(a) * rr + u * 1.5, -(L - 6.0 + u * 52.0)))
						rings.append(ring)
					b.loft(rings, func(p: Vector3) -> Color:
						var a := atan2(p.y + 2.0, p.x) + (-p.z) * 0.35
						return Color8(0xf2, 0xee, 0xe0) if sin(a * 2.0) > 0.0 else Color8(0xc8, 0xc2, 0xb0), false, true, false)
			"spires":
				# little crystal growths along the deck's edges
				var d := r.x + 6.0
				var k := 0
				while d < r.y - 6.0 and d < L - Rules.BOW_LEN:
					var sx := -1.0 if k % 2 == 0 else 1.0
					var x := sx * (hw(id, d) - 2.4)
					var keep := b.xf
					b.xf = Transform3D(Basis(Vector3.BACK, -sx * 0.3), Vector3(x, 0.2, -d))
					b.octa(Vector3(0, 1.6, 0), 0.6, Color8(0xd8, 0xf4, 0xff).lerp(accent, 0.2), Vector3(1, 2.8, 1))
					b.octa(Vector3(sx * 0.8, 1.0, 0.6), 0.45, Color8(0xe8, 0xfa, 0xff), Vector3(1, 2.2, 1))
					b.xf = keep
					d += 11.0
					k += 1
			"legs":
				# a beetle's legs, folded under the shell
				for k in 3:
					var d := 50.0 + k * 52.0
					if d < r.x or d >= r.y:
						continue
					for sx: float in [-1.0, 1.0]:
						var c := body_at(id, bodies(id)[0], d)
						var hip := Vector3(sx * c[2] * 0.62, float(c[1]) - float(c[4]) * 0.7, -d)
						var knee := Vector3(sx * (float(c[2]) + 2.5), float(c[1]) - 1.0, -d + 3.0)
						var foot := Vector3(sx * (float(c[2]) + 1.0), float(c[1]) - float(c[4]) - 6.0, -d - 5.0)
						limb(b, hip, knee, 1.3, pt[2])
						limb(b, knee, foot, 0.9, (pt[2] as Color).lightened(0.08))
						b.octa(foot, 0.9, accent.darkened(0.3))
			"horn":
				# a rhinoceros beetle's horn, sweeping up from the head
				if last:
					var hd: Dictionary = bodies(id)[1]
					var c := body_at(id, hd, L - 14.0)
					var rings: Array = []
					for k in 9:
						var u := k / 8.0
						var rr := lerpf(3.2, 0.25, u)
						var cc := Vector3(0, float(c[1]) + float(c[3]) * 0.5 + u * u * 16.0, -(L - 16.0 + u * 22.0))
						rings.append(Models.oval(cc, Vector3(rr, 0, 0), Vector3(0, rr * 0.7, rr * 0.7), 2.0, 10))
					b.loft(rings, (pt[2] as Color).lerp(accent, 0.25), false, false, true)
			"spines":
				# a serpent's dorsal spines, swept back
				var bd: Dictionary = bodies(id)[0]
				var d := r.x + 3.0
				while d < r.y - 2.0:
					var c := body_at(id, bd, d)
					if not c.is_empty() and c[3] > 3.0:
						var y := float(c[1]) + float(c[3])
						var hgt: float = float(c[3]) * 0.65
						b.prism(Vector3(c[0], 0, -d), poly([[-0.35, -1.8], [0.35, -1.8], [0.25, 2.2], [-0.25, 2.2]]), y - 0.8, y + hgt, accent.darkened(0.35), Vector2(0.4, 0.3), Vector2(0, 2.4))
					d += 7.0
			"horns":
				if last:
					var hd: Dictionary = bodies(id)[1]
					var dd := L - 18.0
					var c := body_at(id, hd, dd)
					for sx: float in [-1.0, 1.0]:
						var rings: Array = []
						for k in 8:
							var u := k / 7.0
							var rr := lerpf(1.8, 0.15, u)
							var cc := Vector3(float(c[0]) + sx * (float(c[2]) * 0.55 + u * 6.0), float(c[1]) + float(c[3]) * 0.6 + u * 4.0, -(dd - u * 16.0))
							rings.append(Models.oval(cc, Vector3(rr, 0, 0), Vector3(0, rr, 0), 2.0, 8))
						b.loft(rings, Color8(0x2a, 0x24, 0x22), false, false, true)
					# its eyes
					for sx: float in [-1.0, 1.0]:
						b.octa(Vector3(float(c[0]) + sx * float(c[2]) * 0.7, float(c[1]) + float(c[3]) * 0.3, -(dd + 6.0)), 0.9, accent, Vector3(1.2, 0.6, 1))
			"rings":
				# glowing collars round the spine between the pods
				for bd: Dictionary in bodies(id):
					if bd.get("role", "") != "pod":
						continue
					var dd := body_span(id, bd).x - 2.5
					if dd < r.x or dd >= r.y or dd < 3.0:
						continue
					var sp: Dictionary = bodies(id)[0]
					var rings: Array = []
					for k in 4:
						var rr := 3.6 + (0.6 if k in [1, 2] else 0.0)
						rings.append(Models.oval(Vector3(0, float(sp.y), -(dd - 1.0 + k * 0.66)), Vector3(rr, 0, 0), Vector3(0, rr, 0), 2.0, 14))
					b.loft(rings, accent, false, true, true)


## A fin sail: a curved membrane from its luff on the mast (foot to head) out to its clew.
static func sail(b: B, foot: Vector3, head: Vector3, clew: Vector3, sx: float, col: Color, accent: Color) -> void:
	var n := 5
	for j in n:
		for k in n - j:
			var p := func(u: float, v: float) -> Vector3:
				var q: Vector3 = foot + (head - foot) * v + (clew - foot) * u
				var bel := sin(PI * clampf(u + v, 0.0, 1.0)) * 1.6 * (1.0 - absf(u - v))
				return q + Vector3(0, 0, -bel)
			var u0 := float(k) / n
			var v0 := float(j) / n
			var a: Vector3 = p.call(u0, v0)
			var c: Vector3 = p.call(u0 + 1.0 / n, v0)
			var e: Vector3 = p.call(u0, v0 + 1.0 / n)
			var cc: Color = col if (j + k) % 4 else col.lerp(accent, 0.35)
			b.tri(a, c, e, cc, Vector3(sx, 0, 1))
			b.tri(a, c, e, cc.darkened(0.12), Vector3(-sx, 0, -1))
			if k < n - j - 1:
				var f: Vector3 = p.call(u0 + 1.0 / n, v0 + 1.0 / n)
				b.tri(c, f, e, cc, Vector3(sx, 0, 1))
				b.tri(c, f, e, cc.darkened(0.12), Vector3(-sx, 0, -1))


## A tapered round limb from a to c.
static func limb(b: B, a: Vector3, c: Vector3, r: float, col: Color) -> void:
	var axis := (c - a).normalized()
	var u := axis.cross(Vector3.UP).normalized()
	if u.length() < 0.1:
		u = Vector3.RIGHT
	var v := u.cross(axis)
	var rings: Array = []
	for k in 3:
		var t := k / 2.0
		rings.append(Models.oval(a.lerp(c, t), u * r * (1.0 - t * 0.35), v * r * (1.0 - t * 0.35), 2.0, 8))
	b.loft(rings, col, false, true, true)
