class_name Towns
extends RefCounted
## Composed towns, one a world (Guillaume, 2026-11-24: "the landscape is too sparse, elements
## scattered without real character... a pyramid in a city like structure with small houses around
## it"). A `town` stretch of the course (`Relief`) levels a platform and lays a town on it round a
## centrepiece: a paved square, an avenue running down towards the player as they fly in, blocks of
## houses on a grid facing the square, a wall or hedges round it and its world's furniture.
## - dunes: a temple city: the stepped pyramid on its square, flat-roofed mud-brick houses, palms
##   down the avenue, obelisks, market stalls, a sandstone wall with towers.
## - coast: a market town: a church with a spire on a cobbled square, cottages and tall houses, a
##   fountain, trees down the avenue, hedged gardens.
## - ice: a polar village: the giant snowman on a skating rink, igloos and snow-roofed huts, lamp
##   posts, a radio mast, pines down the avenue.
## - volcano: a basalt temple: a stepped altar with a fire on top, stone heads down the avenue, dark
##   huts glowing inside, a basalt wall and a moat of lava (Relief) bridged at the gate.
## Everything is placed in world metres; each chunk builds the pieces whose spot it holds.

## The levelled platform: flat within FLAT m of the centre, back to the land by EDGE.
const FLAT := 19.0
const EDGE := 28.0
const GROUND_Y := 0.35
## The paved square's half size, the avenue's half width and how far down it runs.
const SQUARE := 6.5
const AVENUE := 2.0
const AVENUE_TO := 24.0
## Lots: houses on a grid of LOT m out to the wall at WALL m.
const LOT := 4.2
const WALL := 17.5

const PAVING := {"dunes": Color8(0xe6, 0xcc, 0x98), "coast": Color8(0xb8, 0xb2, 0xa6), "ice": Color8(0xc8, 0xe4, 0xf2),
	"volcano": Color8(0x4a, 0x42, 0x44)}
## The noise value the platform is coloured as (sand, grass, snow, ash).
const GROUND_H := {"dunes": 0.2, "coast": 0.2, "ice": 0.16, "volcano": 0.42}

static var _cache := {}


## The pieces of stretch n's town, in world space: {k (kind), p (on the platform), a (angle), r}.
static func layout(n: int) -> Array:
	var key := "%s%d_%d" % [Models.theme, Relief.lv_of(n), n]
	if _cache.has(key):
		return _cache[key]
	var c := Relief.town_c(n)
	var turn := (Relief.h1(n, 21.0) - 0.5) * 0.35
	var th := Models.theme
	var out := []
	var put := func(k: String, lx: float, lz: float, a: float, r: float) -> void:
		var o := Vector2(lx, lz).rotated(-turn)
		out.append({"k": k, "p": Vector3(c.x + o.x, GROUND_Y, c.y + o.y), "a": a + turn, "r": r})
	# the square, the avenue and the centrepiece
	put.call("square", 0.0, 0.0, 0.0, 0.0)
	put.call("avenue", 0.0, (SQUARE + AVENUE_TO) * 0.5, 0.0, 0.0)
	put.call({"dunes": "pyramid", "coast": "church", "ice": "snowman", "volcano": "altar"}[th], 0.0, -0.5, 0.0, Relief.h1(n, 22.0))
	# the avenue's furniture, in pairs down both sides
	var lining: String = {"dunes": "palm", "coast": "tree", "ice": "pine", "volcano": "stone head"}[th]
	var step := 6.5 if th != "volcano" else 7.0
	var z := SQUARE + 2.5
	var i := 0
	while z < AVENUE_TO - 1.0:
		for sx in [-1.0, 1.0]:
			put.call(lining, sx * (AVENUE + 1.6), z, PI * 0.5 * sx if th == "volcano" else 0.0, Relief.h1(n, 30.0 + i))
			i += 1
		z += step
	# the square's corners and edges
	var corner: String = {"dunes": "obelisk", "coast": "fountain", "ice": "lamp", "volcano": "brazier"}[th]
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var cr := Vector2(cos(a), sin(a)) * (SQUARE - 1.0) * 1.41
		if th == "coast" and k > 0:
			put.call("lamp", cr.x, cr.y, 0.0, 0.0)
		elif th == "coast":
			put.call("fountain", cr.x * 0.55, cr.y * 0.55 + 1.0, 0.0, 0.0)
		else:
			put.call(corner, cr.x, cr.y, 0.0, 0.0)
	if th == "dunes":
		for k in 3:
			put.call("stall", -SQUARE + 1.4, -3.0 + k * 3.0, PI * 0.5, Relief.h1(n, 40.0 + k))
			put.call("stall", SQUARE - 1.4, -3.0 + k * 3.0, -PI * 0.5, Relief.h1(n, 50.0 + k))
	# the blocks: a grid of lots round the square, each house facing it
	var reach := WALL - 1.6
	var gx := -reach
	while gx <= reach + 0.01:
		var gz := -reach
		while gz <= reach + 0.01:
			var lx := gx
			var lz := gz
			var skip := (absf(lx) < SQUARE + 1.6 and absf(lz) < SQUARE + 1.6) or (absf(lx) < AVENUE + 2.6 and lz > 0.0)
			if not skip:
				var r := Models.hash2(lx * 1.3 + n * 7.1, lz * 0.7 + Relief.lv_of(n))
				# face the square: turn towards the nearer axis
				var face := atan2(-lx, -lz) if absf(lx) < 1.0 else 0.0
				if absf(lx) > absf(lz):
					face = -PI * 0.5 if lx > 0.0 else PI * 0.5
				else:
					face = PI if lz > 0.0 else 0.0
				var house: String = {"dunes": "adobe", "coast": "cottage", "ice": "igloo", "volcano": "hut"}[th]
				if th == "coast" and r < 0.22:
					house = "house"   # a tall one, a landmark
				elif th == "ice" and r < 0.4:
					house = "cabin"
				if r < 0.86:
					put.call(house, lx + (r - 0.5) * 0.6, lz + (Models.hash2(r, lx) - 0.5) * 0.6, face, r)
				else:
					put.call({"dunes": "palm", "coast": "tree", "ice": "pine", "volcano": "brazier"}[th], lx, lz, 0.0, r)
			gz += LOT
		gx += LOT
	# round it: a wall with towers and a gate (hedges on the coast, a ring of lamps on the ice)
	var edge: String = {"dunes": "wall", "coast": "hedge", "ice": "fence", "volcano": "wall"}[th]
	var seg := 3.5
	for side in 4:
		var a := side * PI * 0.5
		var t := -WALL
		while t < WALL - 0.01:
			var m := t + seg * 0.5
			var p := Vector2(m, WALL).rotated(a)
			# the gate, where the avenue leaves
			if not (side == 0 and absf(m) < AVENUE + 1.0):
				put.call(edge, p.x, p.y, -a, 0.0)
			t += seg
		if th == "dunes" or th == "volcano":
			var tc := Vector2(WALL, WALL).rotated(a)
			put.call("tower", tc.x, tc.y, 0.0, 0.0)
	if th == "dunes" or th == "volcano":
		for sx in [-1.0, 1.0]:
			put.call("tower", sx * (AVENUE + 1.2), WALL, 0.0, 0.0)
	if th == "ice":
		put.call("mast", -WALL + 3.0, -WALL + 3.0, 0.0, 0.0)
	_cache[key] = out
	return out


## Lays the pieces whose spot lies in [z_far, z_near) into the chunk (landmarks go to Models.marks).
static func build(b: Models.Builder, z_near: float, z_far: float) -> void:
	var n0 := Relief.stretch_of(z_near)
	var n1 := Relief.stretch_of(z_far - 0.01)
	for n in range(maxi(n0, 0), n1 + 1):
		if Relief.kind_of(n) != "town":
			continue
		for e: Dictionary in layout(n):
			var p: Vector3 = e.p
			if p.z <= z_near and p.z > z_far:
				piece(b, e)
	b.xf = Transform3D.IDENTITY


static func piece(b: Models.Builder, e: Dictionary) -> void:
	var p: Vector3 = e.p
	var a: float = e.a
	var r: float = e.r
	var th := Models.theme
	var pave: Color = PAVING.get(th, Models.STONE)
	match e.k:
		"square":
			flat(b, p, a, Vector2(SQUARE, SQUARE), pave)
		"avenue":
			flat(b, p, a, Vector2(AVENUE, (AVENUE_TO - SQUARE) * 0.5), pave.darkened(0.06))
		"pyramid", "snowman", "house", "stone head":
			Models.mark(e.k, p, a + (PI if e.k == "stone head" and a < 0.0 else 0.0), r)
		"church":
			church(b, p, a)
		"altar":
			altar(b, p, a)
		"palm":
			Models.palm(b, p, r)
		"tree":
			Models.broadleaf(b, p, r)
		"pine":
			pine(b, p, r)
		"obelisk":
			Models.count("obelisk")
			Models.place(b, p, a)
			b.box(Vector3(0, 0.05, 0), Vector3(0.5, 0.12, 0.5), pave.darkened(0.1))
			b.prism(Vector3.ZERO, Models.ngon(0.16, 4, PI * 0.25), 0.1, 1.5, Color8(0xd8, 0xb8, 0x7c), Vector2(0.55, 0.55))
			b.prism(Vector3.ZERO, Models.ngon(0.09, 4, PI * 0.25), 1.5, 1.7, Color8(0xe8, 0xc0, 0x50), Vector2(0.05, 0.05))
		"stall":
			Models.count("stall")
			Models.place(b, p, a)
			var cl: Color = [Color8(0xc8, 0x3c, 0x34), Color8(0x2e, 0x7a, 0xb0), Color8(0xe0, 0xa8, 0x2e)][int(r * 7.0) % 3]
			for sx in [-0.3, 0.3]:
				for sz in [-0.22, 0.22]:
					b.box(Vector3(sx, 0.25, sz), Vector3(0.05, 0.5, 0.05), Models.WOOD)
			b.box(Vector3(0, 0.15, 0.05), Vector3(0.55, 0.28, 0.3), Models.WOOD.lightened(0.2))
			b.prism(Vector3.ZERO, Models.pts([Vector2(-0.38, -0.3), Vector2(0.38, -0.3), Vector2(0.38, 0.3), Vector2(-0.38, 0.3)]),
				0.5, 0.62, cl, Vector2(0.6, 0.2))
			for k in 4:
				b.box(Vector3(-0.15 + k * 0.1, 0.32, 0.05), Vector3(0.07, 0.07, 0.07), [Color8(0xf0, 0x8a, 0x2a), Color8(0x8c, 0xb4, 0x40), Color8(0xe8, 0xd0, 0x60)][k % 3])
		"fountain":
			Models.count("fountain")
			Models.place(b, p, 0.0)
			b.prism(Vector3.ZERO, Models.ngon(0.75, 10), 0.0, 0.18, Color8(0xd4, 0xce, 0xc2))
			b.prism(Vector3.ZERO, Models.ngon(0.62, 10), 0.12, 0.16, Color8(0x5c, 0xb0, 0xd0))
			b.prism(Vector3.ZERO, Models.ngon(0.12, 6), 0.0, 0.55, Color8(0xd4, 0xce, 0xc2))
			b.prism(Vector3.ZERO, Models.ngon(0.3, 8), 0.5, 0.58, Color8(0xd4, 0xce, 0xc2))
			b.prism(Vector3.ZERO, Models.ngon(0.1, 6), 0.58, 0.72, Color8(0xdc, 0xf2, 0xff), Vector2(0.3, 0.3))
		"lamp":
			Models.count("lamp")
			Models.place(b, p, 0.0)
			b.box(Vector3(0, 0.45, 0), Vector3(0.05, 0.9, 0.05), Color8(0x30, 0x34, 0x3a))
			b.octa(Vector3(0, 0.95, 0), 0.09, Color8(0xff, 0xe0, 0x8a))
		"brazier":
			Models.count("brazier")
			Models.place(b, p, 0.0)
			b.prism(Vector3.ZERO, Models.ngon(0.16, 6), 0.0, 0.5, Color8(0x2a, 0x24, 0x26), Vector2(0.7, 0.7))
			b.prism(Vector3.ZERO, Models.ngon(0.24, 6), 0.5, 0.62, Color8(0x3a, 0x30, 0x30), Vector2(1.2, 1.2))
			b.prism(Vector3.ZERO, Models.ngon(0.16, 5), 0.62, 0.95, Color8(0xff, 0x8a, 0x22), Vector2(0.1, 0.1))
			b.prism(Vector3.ZERO, Models.ngon(0.09, 5, 0.6), 0.62, 1.1, Color8(0xff, 0xe0, 0x60), Vector2(0.1, 0.1))
		"adobe":
			adobe(b, p, a, r)
		"cottage":
			Models.house(b, p, a + PI, 0.34 if int(r * 53.0) % 3 == 1 else r)
		"igloo":
			igloo(b, p, a, r)
		"cabin":
			cabin(b, p, a, r)
		"hut":
			hut(b, p, a, r)
		"wall":
			Models.count("town wall")
			Models.place(b, p, a)
			var wc := Color8(0xd2, 0xac, 0x74) if th == "dunes" else Color8(0x2e, 0x28, 0x2a)
			b.box(Vector3(0, 0.3, 0), Vector3(1.42, 0.6, 0.22), wc)
			for k in 3:
				b.box(Vector3(-0.5 + k * 0.5, 0.67, 0), Vector3(0.22, 0.14, 0.24), wc.lightened(0.05))
		"tower":
			Models.count("town tower")
			Models.place(b, p, a)
			var tc := Color8(0xd2, 0xac, 0x74) if th == "dunes" else Color8(0x2e, 0x28, 0x2a)
			b.box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), tc)
			b.box(Vector3(0, 1.06, 0), Vector3(0.7, 0.12, 0.7), tc.lightened(0.06))
			if th == "volcano":
				b.box(Vector3(0, 1.2, 0), Vector3(0.22, 0.22, 0.22), Color8(0xff, 0x8a, 0x22))
			else:
				b.box(Vector3(0, 0.75, 0.31), Vector3(0.12, 0.2, 0.02), Color8(0x3a, 0x2a, 0x22))
		"hedge":
			Models.count("hedge")
			Models.place(b, p, a)
			b.box(Vector3(0, 0.12, 0), Vector3(1.3, 0.24, 0.2), Models.LEAF.darkened(0.25))
		"fence":
			Models.count("fence")
			Models.place(b, p, a)
			for k in 3:
				b.box(Vector3(-0.5 + k * 0.5, 0.2, 0), Vector3(0.05, 0.4, 0.05), Models.WOOD)
			b.box(Vector3(0, 0.3, 0), Vector3(1.4, 0.04, 0.04), Models.WOOD)
			b.box(Vector3(0, 0.42, 0), Vector3(0.06, 0.05, 0.06), Color8(0xff, 0xd8, 0x8a))
		"mast":
			Models.count("mast")
			Models.place(b, p, 0.4)
			b.box(Vector3(0, 0.15, 0), Vector3(0.7, 0.3, 0.5), Color8(0xd0, 0x3a, 0x30))
			b.prism(Vector3(0, 0, 0), Models.ngon(0.12, 3), 0.3, 2.3, Color8(0xe8, 0xe8, 0xec), Vector2(0.2, 0.2))
			b.box(Vector3(0, 2.35, 0), Vector3(0.08, 0.08, 0.08), Color8(0xff, 0x40, 0x30))
	b.xf = Transform3D.IDENTITY


## A flat paved slab, `half` m (x, z) in world metres, turned by a.
static func flat(b: Models.Builder, p: Vector3, a: float, half: Vector2, col: Color) -> void:
	Models.count("paving")
	b.xf = Transform3D(Basis(Vector3.UP, a), p)
	b.box(Vector3(0, 0.03, 0), Vector3(half.x * 2.0, 0.08, half.y * 2.0), col)
	# a border of darker kerb
	for s in [-1.0, 1.0]:
		b.box(Vector3(s * half.x, 0.06, 0), Vector3(0.3, 0.12, half.y * 2.0), col.darkened(0.18))
	b.xf = Transform3D.IDENTITY


## Mud-brick houses: one or two flat-roofed cubes, a parapet, a dark door, small windows, now and
## then a dome, an awning or a roof terrace with pots.
static func adobe(b: Models.Builder, p: Vector3, a: float, r: float) -> void:
	Models.count("adobe")
	Models.place(b, p, a)
	var wall: Color = [Color8(0xe8, 0xc4, 0x8e), Color8(0xde, 0xb4, 0x80), Color8(0xf0, 0xd6, 0xa8), Color8(0xd6, 0xa6, 0x72)][int(r * 13.0) % 4]
	var tall := 0.55 + 0.35 * float(int(r * 31.0) % 2)
	b.box(Vector3(0, tall * 0.5 - 0.05, 0), Vector3(1.1, tall + 0.1, 0.9), wall)
	b.box(Vector3(0, tall + 0.03, 0), Vector3(1.16, 0.08, 0.96), wall.lightened(0.08), Vector2(0.86, 0.84))
	b.box(Vector3(0, 0.18, 0.46), Vector3(0.24, 0.36, 0.03), Color8(0x4a, 0x30, 0x22))
	for sx in [-0.32, 0.32]:
		b.box(Vector3(sx, tall - 0.2, 0.46), Vector3(0.14, 0.12, 0.02), Color8(0x3a, 0x2a, 0x26))
	match int(r * 97.0) % 4:
		0:   # a dome
			b.prism(Vector3(0.15, 0, -0.1), Models.ngon(0.32, 10), tall, tall + 0.18, Color8(0xf4, 0xe6, 0xcc), Vector2(0.75, 0.75))
			b.prism(Vector3(0.15, 0, -0.1), Models.ngon(0.24, 10), tall + 0.18, tall + 0.32, Color8(0xf4, 0xe6, 0xcc), Vector2(0.3, 0.3))
		1:   # a striped awning over the door
			b.prism(Vector3(0, 0, 0.56), Models.pts([Vector2(-0.34, -0.1), Vector2(0.34, -0.1), Vector2(0.34, 0.12), Vector2(-0.34, 0.12)]),
				0.42, 0.48, [Color8(0xc8, 0x3c, 0x34), Color8(0x2e, 0x7a, 0xb0)][int(r * 7.0) % 2])
		2:   # a little upper storey at the back
			b.box(Vector3(-0.22, tall + 0.2, -0.18), Vector3(0.55, 0.4, 0.5), wall.darkened(0.05))
		3:   # pots and a palm-frond shade on the roof terrace
			for k in 3:
				b.prism(Vector3(-0.35 + k * 0.3, 0, 0.25), Models.ngon(0.07, 6), tall + 0.06, tall + 0.18, Color8(0xb0, 0x5a, 0x34))
			b.box(Vector3(0.2, tall + 0.32, -0.15), Vector3(0.5, 0.04, 0.4), Models.PALM.darkened(0.1))
	b.xf = Transform3D.IDENTITY


static func church(b: Models.Builder, p: Vector3, a: float) -> void:
	Models.count("church")
	Models.place(b, p, a)
	var wall := Color8(0xee, 0xe8, 0xda)
	var roof := Color8(0x5a, 0x66, 0x7a)
	# the nave along z, its front to +z (down the avenue), and the transept across it
	b.box(Vector3(0, 0.35, -0.3), Vector3(1.3, 0.9, 2.2), wall)
	b.box(Vector3(0, 0.3, -0.7), Vector3(2.1, 0.8, 0.8), wall)
	Models.gable(b, Vector3(0, 0, -0.7), 2.1, 0.8, 0.7, 0.45, roof, wall)
	var base := b.xf
	b.xf = base * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	Models.gable(b, Vector3(0.3, 0, 0), 2.2, 1.3, 0.8, 0.55, roof, wall)
	b.xf = base
	# the bell tower over the door, and its spire
	b.box(Vector3(0, 0.75, 0.75), Vector3(0.7, 1.7, 0.7), wall.darkened(0.04))
	b.box(Vector3(0, 1.45, 1.105), Vector3(0.22, 0.26, 0.02), Color8(0x2a, 0x2a, 0x30))
	b.prism(Vector3(0, 0, 0.75), Models.ngon(0.52, 4, PI * 0.25), 1.6, 2.45, roof, Vector2(0.05, 0.05))
	b.box(Vector3(0, 0.25, 1.105), Vector3(0.3, 0.5, 0.02), Color8(0x6a, 0x3e, 0x2a))
	for sx in [-0.4, 0.4]:
		for k in 3:
			b.box(Vector3(sx * 1.63, 0.45, -0.9 + k * 0.6), Vector3(0.02, 0.3, 0.14), Color8(0x6a, 0x8a, 0xc0))
	b.xf = Transform3D.IDENTITY


static func altar(b: Models.Builder, p: Vector3, a: float) -> void:
	Models.count("altar")
	Models.place(b, p, a)
	var st := Color8(0x34, 0x2e, 0x30)
	var y := 0.0
	for k in 3:
		var w := 2.1 - k * 0.55
		b.box(Vector3(0, y + 0.15, 0), Vector3(w, 0.3, w), st.lightened(k * 0.05))
		y += 0.3
	for k in 5:
		b.box(Vector3(0, 0.05 + k * 0.17, 1.05 - k * 0.14), Vector3(0.5, 0.1, 0.16), st.lightened(0.1))
	# the fire on top, in a ring of glowing stones
	b.prism(Vector3.ZERO, Models.ngon(0.4, 8), y, y + 0.1, Color8(0xff, 0x6a, 0x1a))
	b.prism(Vector3.ZERO, Models.ngon(0.3, 6), y + 0.1, y + 0.7, Color8(0xff, 0x9a, 0x2a), Vector2(0.1, 0.1))
	b.prism(Vector3(0.1, 0, 0.05), Models.ngon(0.16, 5), y + 0.1, y + 0.95, Color8(0xff, 0xe0, 0x60), Vector2(0.1, 0.1))
	for k in 4:
		var c := Vector2(cos(k * PI * 0.5 + 0.78), sin(k * PI * 0.5 + 0.78)) * 0.85
		b.box(Vector3(c.x, y + 0.2, c.y), Vector3(0.14, 0.4, 0.14), st.lightened(0.15))
	b.xf = Transform3D.IDENTITY


static func igloo(b: Models.Builder, p: Vector3, a: float, r: float) -> void:
	Models.count("igloo")
	Models.place(b, p, a)
	var snow := Color8(0xf2, 0xf8, 0xfc)
	var rad := 0.5 + r * 0.15
	b.prism(Vector3.ZERO, Models.ngon(rad, 10), 0.0, rad * 0.45, snow, Vector2(0.8, 0.8))
	b.prism(Vector3.ZERO, Models.ngon(rad * 0.8, 10), rad * 0.45, rad * 0.75, snow.darkened(0.03), Vector2(0.55, 0.55))
	b.prism(Vector3.ZERO, Models.ngon(rad * 0.44, 10), rad * 0.75, rad * 0.9, snow.darkened(0.06), Vector2(0.3, 0.3))
	# the entrance tunnel, facing the square
	b.box(Vector3(0, 0.14, rad + 0.12), Vector3(0.3, 0.28, 0.36), snow.darkened(0.06))
	b.box(Vector3(0, 0.12, rad + 0.31), Vector3(0.16, 0.2, 0.02), Color8(0x3a, 0x5a, 0x7a))
	b.xf = Transform3D.IDENTITY


static func cabin(b: Models.Builder, p: Vector3, a: float, r: float) -> void:
	Models.count("cabin")
	Models.place(b, p, a)
	var wall: Color = [Color8(0x9a, 0x4a, 0x36), Color8(0x6a, 0x4e, 0x3a), Color8(0x3e, 0x5a, 0x7a)][int(r * 11.0) % 3]
	b.box(Vector3(0, 0.25, 0), Vector3(1.1, 0.6, 0.8), wall)
	Models.gable(b, Vector3.ZERO, 1.1, 0.8, 0.55, 0.38, Color8(0xf4, 0xf8, 0xfc), wall)
	b.box(Vector3(0, 0.22, 0.41), Vector3(0.2, 0.36, 0.02), Color8(0x3a, 0x2a, 0x22))
	for sx in [-0.32, 0.32]:
		b.box(Vector3(sx, 0.32, 0.41), Vector3(0.16, 0.14, 0.02), Color8(0xff, 0xd8, 0x8a))
	b.box(Vector3(0.3, 0.95, -0.15), Vector3(0.14, 0.3, 0.14), Color8(0x5a, 0x50, 0x4c))
	b.xf = Transform3D.IDENTITY


static func hut(b: Models.Builder, p: Vector3, a: float, r: float) -> void:
	Models.count("hut")
	Models.place(b, p, a)
	var st := Color8(0x3a, 0x34, 0x36).lightened(r * 0.12)
	b.prism(Vector3.ZERO, Models.ngon(0.55, 7), 0.0, 0.5, st, Vector2(0.92, 0.92))
	b.prism(Vector3.ZERO, Models.ngon(0.62, 7), 0.5, 0.95, Color8(0x5a, 0x40, 0x36), Vector2(0.1, 0.1))
	b.box(Vector3(0, 0.18, 0.5), Vector3(0.2, 0.34, 0.06), Color8(0xff, 0x7a, 0x22))
	b.box(Vector3(0.35, 0.32, 0.36), Vector3(0.1, 0.1, 0.04), Color8(0xff, 0xa0, 0x30))
	b.xf = Transform3D.IDENTITY


static func pine(b: Models.Builder, p: Vector3, r: float) -> void:
	Models.count("pine")
	Models.place(b, p, r * 6.0)
	var tall := 1.3 + r * 0.6
	b.prism(Vector3(0, -0.1, 0), Models.ngon(0.6, 6), 0, tall, Color8(0x2e, 0x50, 0x4c).darkened(r * 0.2), Vector2(0.05, 0.05))
	b.prism(Vector3(0, tall * 0.55, 0), Models.ngon(0.45, 6, 0.5), 0, tall * 0.55, Color8(0xe8, 0xf2, 0xf8), Vector2(0.05, 0.05))
	b.xf = Transform3D.IDENTITY
