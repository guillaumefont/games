class_name Civilians
extends RefCounted
## Each world's own civilian (Guillaume, 2026-11-25: "There should be no seaplane in the desert. You
## should replace it in each world with something appropriate... in the desert, that could be a
## camel caravan"). The campaign's waves still say "gull" (the civilian stroll, `Foes.INTRO`'s
## first kind); `Foes.spawn` turns it into the world's own (`BY_THEME`):
## - Glass Coast: the seaplane (`Foes.gull`), whose pilot bails out under a parachute.
## - Ember Dunes: a camel caravan plodding across the sand; downed, the lead camel bolts off at a
##   gallop with its rider clinging on, kicking up dust.
## - Iron Sprawl: an advertising blimp; downed, it whizzes off like a let-go party balloon.
## - Frost Shelf: a dog sled crossing the ice; downed, the dogs bolt, towing the musher on their belly.
## - Cinder Reach: a hot-air balloon; downed, its crew float away under a bunch of party balloons.
## They all keep the seaplane's rules: one at a time, harmless (`Foes.HARMLESS`), nothing scored,
## and some are hacked and unveil a minigun (`Foes.HACK_P`, `MOUNT`). The escape is `Blasts.escape`.

const BY_THEME := {"coast": "gull", "dunes": "caravan", "city": "blimp", "ice": "sled", "volcano": "balloon"}
## Those that go on the ground: they walk across the land and up it a little (`WALK`, `UPHILL`).
const WALKERS := ["caravan", "sled"]
## How fast each strolls across the screen (m/s).
const SPEED := {"gull": 2.4, "blimp": 1.9, "balloon": 1.6, "caravan": 1.5, "sled": 2.6}
## Walkers are drawn bigger than life: from up at the flight plane a real camel or dog is a speck.
const BIG := 1.7
## How fast a walker goes up the land, against the scroll (m/s), so it stays a while in sight.
const UPHILL := 1.4
## Where a hacked one's minigun pops up (on the wing, the middle camel's hump, the sled's load,
## the blimp's back, the balloon's crown).
const MOUNT := {"gull": Vector3(0, 0.78, 0.1), "caravan": Vector3(0, 1.62, 0), "sled": Vector3(0, 0.78, -1.5),
	"blimp": Vector3(0, 0.9, 0.3), "balloon": Vector3(0, 1.3, 0)}

const CAMEL := Color8(0x8e, 0x5e, 0x34)
const CAMEL_D := Color8(0x5e, 0x3c, 0x22)
const INDIGO := Color8(0x2c, 0x3c, 0x8c)
const TEAL := Color8(0x2a, 0xa0, 0x9a)
const SAFFRON := Color8(0xe8, 0xb0, 0x30)
const DOG := Color8(0x4a, 0x4e, 0x56)
const DOG_R := Color8(0xa0, 0x62, 0x34)
const PARKA := Color8(0xe8, 0x6a, 0x2a)
const AD := Color8(0xf4, 0xd0, 0x40)
const SKY_BLUE := Color8(0x36, 0xb8, 0xe8)
const SKIN := Color8(0xf0, 0xc8, 0x9a)
const PARTY := [Color8(0xff, 0x40, 0x50), Color8(0xff, 0xd2, 0x2e), Color8(0x3d, 0xd6, 0xf5), Color8(0xff, 0x7a, 0xc8),
	Color8(0x6a, 0xd8, 0x4a), Color8(0xf4, 0xf4, 0xf0), Color8(0x9a, 0x6c, 0xff)]


## The civilian of the world being played.
static func of_world() -> String:
	return BY_THEME.get(Models.theme, "gull")


static func is_walker(kind: String) -> bool:
	return kind in WALKERS


static func mesh(kind: String) -> Mesh:
	match kind:
		"caravan": return caravan()
		"sled": return sled()
		"blimp": return blimp()
		"balloon": return balloon()
	return Foes.gull()


## What bails out of a downed one (`Blasts.escape`).
static func escape_mesh(kind: String) -> Mesh:
	match kind:
		"caravan": return camel_bolt()
		"sled": return dogs_bolt()
		"blimp": return blimp()
		"balloon": return party_balloons()
	return Foes.chute()


# ---------------------------------------------------------------- the stroll

## Sets a new civilian off, from the side `s` (-1 left, 1 right), across the screen.
static func spawn(g: Game, f: Game.Obj, s: float) -> void:
	f.x0 = s
	var v: float = SPEED.get(f.kind, 2.0)
	if is_walker(f.kind):
		# plods in from the top of the land on one side and across to the other, up the land
		var gz := g.frame_z + minf(g.view_ground_top, minf(g.view_top, Rules.Z_TOP) - 5.5) - 2.0
		var at := Foes.dry_x(g, s * 3.0, gz, f)
		f.pos = Vector3(at.x, g.ground_y(at.x, at.y), at.y)
		# no dry ground on that side: it sets off from the other one
		if at.x * s < 0.0:
			s = -s
			f.x0 = s
		f.vel = Vector3(-s * v, 0, -UPHILL)
		f.node.scale = Vector3.ONE * BIG
		f.node.rotation.y = atan2(f.vel.x, f.vel.z)
	else:
		var z := g.hold_z(6.5)
		f.goal = Vector3(0, 0, z)
		f.pos = Vector3(s * (g.view_hw(z) + 2.5), Rules.PY, g.frame_z + z)
		f.vel = Vector3(-s * v, 0, 0)
	f.hacked = g.stage_t > Foes.HACK_AFTER and g.rng.randf() < Foes.HACK_P


static func think(g: Game, f: Game.Obj, dt: float) -> void:
	var out := f.hacked and f.hold >= 0.0 and f.t - f.hold >= Foes.HACK_TELL + Foes.HACK_UNVEIL
	if is_walker(f.kind):
		walk(g, f, dt, out)
	else:
		fly(g, f, dt)
	if not f.hacked:
		return
	var at := Foes.at_of(g, f) if f.ground else f.pos
	var z := at.z - g.frame_z
	if f.hold < 0.0 and Foes.in_play(g, f) and absf(at.x) < g.view_hw(z) - 2.5:
		f.hold = f.t
	if Foes.unveil(g, f, "minigun", MOUNT.get(f.kind, Vector3(0, 0.8, 0))):
		# slows to hose the ship with short bursts, the gun turned to face it
		f.vel.x = move_toward(f.vel.x, -f.x0 * SPEED.get(f.kind, 2.0) * (0.0 if f.ground else 0.45), dt * 2.0)
		var to := g.ppos - at
		var gun := f.node.get_node("minigun") as Node3D
		gun.rotation.y = wrapf(atan2(to.x, to.z) - f.node.rotation.y, -PI, PI)
		if f.t >= f.fire_t and Foes.in_play(g, f):
			g.aimed(at + Vector3(to.x, 0, to.z).normalized() * 0.9, 11.0)
			f.burst -= 1
			f.fire_t = f.t + (0.09 if f.burst > 0 else 1.5)
			if f.burst <= 0:
				f.burst = 6


## In the air: strolls across in a lazy wave, never fires (unless hacked).
static func fly(g: Game, f: Game.Obj, dt: float) -> void:
	f.pos.x += f.vel.x * dt
	var w := 0.8 if f.kind == "gull" else 0.55
	f.pos.z = g.frame_z + f.goal.z + sin(f.t * w) * 0.9
	var dz := cos(f.t * w) * 0.9 * w
	match f.kind:
		"balloon":
			# a balloon doesn't steer: it turns slowly and sways under its envelope
			f.node.rotation = Vector3(sin(f.t * 1.3) * 0.06, f.t * 0.25, sin(f.t * 1.1) * 0.07)
		"blimp":
			f.node.rotation = Vector3(sin(f.t * 0.9) * 0.04, atan2(f.vel.x, dz * 0.5), 0)
		_:
			f.node.rotation = Vector3(0, atan2(f.vel.x, dz), sin(f.t * w) * 0.18 * -f.x0)


## On the ground: across and up the land, sidestepping water and lava (waits on the bank).
static func walk(g: Game, f: Game.Obj, dt: float, stop: bool) -> void:
	var d := Vector3(0.0 if stop else f.vel.x, 0.0, f.vel.z)
	var ahead := f.pos + Vector3(signf(d.x) * 1.4, 0, 0)
	if d.x != 0.0 and not Foes.dry(g, ahead.x, ahead.z):
		d.x = 0.0
	f.pos += d * dt
	f.pos.y = g.ground_y(f.pos.x, f.pos.z)
	if absf(d.x) > 0.01:
		Foes.face(f, d, dt, 3.0)
	# a plodding gait (camels) or a scamper (dogs)
	var k := 5.0 if f.kind == "caravan" else 11.0
	f.node.rotation.x = sin(f.t * k) * 0.03
	f.node.rotation.z = sin(f.t * k * 0.5) * 0.035


# ---------------------------------------------------------------- models (nose to +z)

## Dunes: one camel, its hooves at y 0. With `rider` a robed rider on the hump, else packs.
static func camel(b: Models.Builder, c: Vector3, rider: bool, pack := TEAL) -> void:
	b.box(c + Vector3(0, 0.95, 0), Vector3(0.48, 0.44, 1.1), CAMEL)
	b.octa(c + Vector3(0, 1.22, -0.05), 0.34, CAMEL, Vector3(0.85, 0.75, 1.15))
	b.prism(c + Vector3(0, 0, 0.5), Models.ngon(0.12, 4, PI / 4), 0.95, 1.42, CAMEL, Vector2.ONE, Vector2(0, 0.28))
	b.box(c + Vector3(0, 1.5, 0.9), Vector3(0.2, 0.2, 0.4), CAMEL)
	b.box(c + Vector3(0, 1.47, 1.1), Vector3(0.15, 0.13, 0.08), CAMEL_D)
	for sx in [1.0, -1.0]:
		for sz in [1.0, -1.0]:
			b.box(c + Vector3(0.15 * sx, 0.37, 0.38 * sz), Vector3(0.1, 0.74, 0.1), CAMEL_D)
		b.box(c + Vector3(0.07 * sx, 1.62, 0.78), Vector3(0.05, 0.1, 0.05), CAMEL_D)
	b.box(c + Vector3(0, 0.85, -0.6), Vector3(0.05, 0.36, 0.05), CAMEL_D)
	if rider:
		# a striped saddle blanket, the rider in an indigo robe and a white headscarf
		b.box(c + Vector3(0, 1.32, -0.05), Vector3(0.62, 0.08, 0.66), Models.FOE)
		b.box(c + Vector3(0, 1.33, -0.05), Vector3(0.64, 0.07, 0.16), SAFFRON)
		b.box(c + Vector3(0, 1.62, -0.05), Vector3(0.32, 0.42, 0.26), INDIGO)
		b.octa(c + Vector3(0, 1.95, -0.05), 0.16, Models.IVORY)
		b.box(c + Vector3(0, 1.62, 0.18), Vector3(0.36, 0.08, 0.14), INDIGO.darkened(0.2))
	else:
		# bundles slung on both flanks and a rolled rug across the hump
		for sx in [1.0, -1.0]:
			b.box(c + Vector3(0.33 * sx, 1.05, -0.05), Vector3(0.2, 0.34, 0.5), pack)
		b.box(c + Vector3(0, 1.44, -0.05), Vector3(0.78, 0.16, 0.2), SAFFRON)
		b.box(c + Vector3(0, 1.45, -0.05), Vector3(0.2, 0.17, 0.21), Models.FOE)


## Dunes: three camels nose to tail on a lead rope, the first one ridden.
static func caravan() -> Mesh:
	return Models.cached("c_caravan", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		camel(b, Vector3(0, 0, 1.55), true)
		camel(b, Vector3(0, 0, 0.0), false, TEAL)
		camel(b, Vector3(0, 0, -1.55), false, Models.FOE)
		for z in [0.95, -0.6]:
			b.box(Vector3(0, 1.2, z), Vector3(0.04, 0.04, 0.55), CAMEL_D)
		return b.commit())


## The lead camel bolting off with its rider (`Blasts.escape`).
static func camel_bolt() -> Mesh:
	return Models.cached("c_camel_bolt", func() -> Mesh:
		var b := Models.Builder.new()
		camel(b, Vector3.ZERO, true)
		return b.commit())


## Ice: one sled dog, standing at y 0.
static func dog(b: Models.Builder, c: Vector3, col: Color) -> void:
	b.box(c + Vector3(0, 0.42, 0), Vector3(0.24, 0.22, 0.6), col)
	b.box(c + Vector3(0, 0.54, 0.36), Vector3(0.2, 0.2, 0.22), col)
	b.box(c + Vector3(0, 0.5, 0.5), Vector3(0.1, 0.1, 0.1), col.darkened(0.3))
	for sx in [1.0, -1.0]:
		b.box(c + Vector3(0.07 * sx, 0.68, 0.32), Vector3(0.05, 0.1, 0.05), col.darkened(0.25))
		for sz in [1.0, -1.0]:
			b.box(c + Vector3(0.08 * sx, 0.16, 0.2 * sz), Vector3(0.07, 0.32, 0.07), col.darkened(0.2))
	b.box(c + Vector3(0, 0.6, -0.36), Vector3(0.07, 0.07, 0.24), col)
	b.box(c + Vector3(0, 0.54, 0.0), Vector3(0.26, 0.05, 0.1), Models.FOE)


## Ice: five dogs in pairs on a gangline.
static func team(b: Models.Builder) -> void:
	b.box(Vector3(0, 0.38, 0.25), Vector3(0.03, 0.03, 2.8), CAMEL_D)
	var cols := [DOG, DOG_R, DOG_R, DOG]
	for i in 4:
		dog(b, Vector3((0.26 if i % 2 == 0 else -0.26), 0, -0.45 + (i / 2) * 0.9), cols[i])
	dog(b, Vector3(0, 0, 1.4), DOG)


## Ice: a dog sled, the team ahead, the loaded sled and its musher in an orange parka behind.
static func sled() -> Mesh:
	return Models.cached("c_sled", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		team(b)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.27 * sx, 0.05, -1.75), Vector3(0.05, 0.06, 1.4), Models.WOOD.darkened(0.3))
			b.box(Vector3(0.27 * sx, 0.6, -2.3), Vector3(0.05, 0.5, 0.05), Models.WOOD.darkened(0.3))
		b.box(Vector3(0, 0.2, -1.65), Vector3(0.6, 0.08, 1.0), Models.WOOD)
		b.box(Vector3(0, 0.42, -1.55), Vector3(0.48, 0.34, 0.7), Models.FOE)
		b.box(Vector3(0, 0.6, -1.55), Vector3(0.5, 0.04, 0.1), SAFFRON)
		b.box(Vector3(0, 0.82, -2.3), Vector3(0.6, 0.05, 0.05), Models.WOOD.darkened(0.3))
		b.box(Vector3(0, 0.62, -2.5), Vector3(0.32, 0.72, 0.26), PARKA)
		b.octa(Vector3(0, 1.1, -2.48), 0.17, Models.IVORY)
		b.octa(Vector3(0, 1.1, -2.42), 0.1, SKIN)
		return b.commit())


## The dogs bolting with the musher sliding behind on their belly, holding the line.
static func dogs_bolt() -> Mesh:
	return Models.cached("c_dogs_bolt", func() -> Mesh:
		var b := Models.Builder.new()
		team(b)
		b.box(Vector3(0, 0.1, -1.6), Vector3(0.4, 0.05, 0.9), Models.WOOD)
		b.box(Vector3(0, 0.25, -1.65), Vector3(0.32, 0.2, 0.75), PARKA)
		b.box(Vector3(0, 0.25, -1.1), Vector3(0.36, 0.08, 0.3), PARKA.darkened(0.15))
		b.octa(Vector3(0, 0.3, -1.12), 0.15, Models.IVORY)
		return b.commit())


## City: an advertising blimp, its envelope ringed by a red banner, fins at the tail, a gondola.
static func blimp() -> Mesh:
	return Models.cached("c_blimp", func() -> Mesh:
		var b := Models.Builder.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.78
		cap.height = 4.2
		cap.radial_segments = 14
		cap.rings = 4
		var along := Basis(Vector3.RIGHT, PI / 2)
		b.smooth(true)
		b.prim(cap, Transform3D(along, Vector3.ZERO), AD)
		var band := CylinderMesh.new()
		band.top_radius = 0.8
		band.bottom_radius = 0.8
		band.height = 1.3
		band.radial_segments = 14
		band.rings = 1
		b.prim(band, Transform3D(along, Vector3(0, 0, 0.1)), Models.FOE)
		var stripe := CylinderMesh.new()
		stripe.top_radius = 0.81
		stripe.bottom_radius = 0.81
		stripe.height = 0.22
		stripe.radial_segments = 14
		stripe.rings = 1
		b.prim(stripe, Transform3D(along, Vector3(0, 0, 0.1)), Models.IVORY)
		b.smooth(false)
		# tail fins in a cross, red tipped
		b.box(Vector3(0, 0.55, -1.65), Vector3(0.06, 0.7, 0.62), Models.IVORY)
		b.box(Vector3(0, 0, -1.65), Vector3(2.0, 0.06, 0.62), Models.IVORY)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.95 * sx, 0.01, -1.7), Vector3(0.2, 0.07, 0.5), Models.FOE)
		# the gondola, its windows and a little propeller each side
		b.box(Vector3(0, -0.86, 0.35), Vector3(0.36, 0.28, 0.95), Models.IVORY)
		b.box(Vector3(0, -0.84, 0.35), Vector3(0.38, 0.1, 0.8), Models.GLASS)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.36 * sx, -0.8, 0.0), Vector3(0.3, 0.05, 0.05), Models.IVORY_D)
			b.box(Vector3(0.52 * sx, -0.8, 0.05), Vector3(0.04, 0.34, 0.05), Models.HULL_D)
		return b.commit())


## Volcano: a hot-air balloon, an envelope of cyan, white and yellow gores over a wicker basket
## (the origin is the envelope's middle).
static func balloon() -> Mesh:
	return Models.cached("c_balloon", func() -> Mesh:
		var b := Models.Builder.new()
		b.smooth(true)
		# the envelope's profile, crown to mouth: (height, radius)
		var prof := [Vector2(1.2, 0.0), Vector2(1.08, 0.5), Vector2(0.82, 0.88), Vector2(0.42, 1.06), Vector2(0.0, 1.04),
			Vector2(-0.42, 0.88), Vector2(-0.8, 0.58), Vector2(-1.1, 0.3), Vector2(-1.22, 0.24)]
		var n := 12
		var cols := [SKY_BLUE, Models.IVORY, AD]
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var col: Color = cols[k % 3]
			for i in prof.size() - 1:
				var p: Vector2 = prof[i]
				var q: Vector2 = prof[i + 1]
				var p0 := Vector3(cos(a0) * p.y, p.x, sin(a0) * p.y)
				var p1 := Vector3(cos(a1) * p.y, p.x, sin(a1) * p.y)
				var q0 := Vector3(cos(a0) * q.y, q.x, sin(a0) * q.y)
				var q1 := Vector3(cos(a1) * q.y, q.x, sin(a1) * q.y)
				var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)) * (q.x - p.x) * -1.0 \
					+ Vector3(0, q.y - p.y, 0)
				if out.length_squared() < 0.0001:
					out = Vector3.UP
				if p.y > 0.001:
					b.tri(p0, p1, q1, col, out)
				b.tri(p0, q1, q0, col, out)
		b.smooth(false)
		# ropes down to the basket, the burner and two passengers waving
		for k in 4:
			var a := TAU * k / 4 + PI / 4
			b.box(Vector3(cos(a) * 0.2, -1.5, sin(a) * 0.2), Vector3(0.03, 0.5, 0.03), Models.WOOD.darkened(0.3))
		b.box(Vector3(0, -1.32, 0), Vector3(0.18, 0.12, 0.18), Models.HULL_D)
		b.box(Vector3(0, -1.95, 0), Vector3(0.56, 0.4, 0.56), Models.WOOD)
		b.box(Vector3(0, -1.75, 0), Vector3(0.6, 0.06, 0.6), Models.WOOD.darkened(0.2))
		for sx in [1.0, -1.0]:
			b.octa(Vector3(0.14 * sx, -1.62, 0.06 * sx), 0.11, SKIN)
			b.box(Vector3(0.14 * sx, -1.72, 0.06 * sx), Vector3(0.16, 0.08, 0.12), PARKA if sx > 0 else SKY_BLUE)
		return b.commit())


## The balloon's crew floating off under a bunch of party balloons (`Blasts.escape`).
static func party_balloons() -> Mesh:
	return Models.cached("c_party", func() -> Mesh:
		var b := Models.Builder.new()
		var spots := [Vector3(0, 1.85, 0), Vector3(0.36, 1.7, 0.1), Vector3(-0.34, 1.72, 0.14), Vector3(0.12, 1.66, -0.36),
			Vector3(-0.16, 1.64, 0.38), Vector3(0.3, 2.04, -0.16), Vector3(-0.26, 2.06, -0.14)]
		for i in spots.size():
			b.octa(spots[i], 0.24, PARTY[i % PARTY.size()], Vector3(1, 1.25, 1))
			var s: Vector3 = spots[i]
			b.box(Vector3(s.x * 0.5, 0.95 + (s.y - 1.7) * 0.5, s.z * 0.5), Vector3(0.02, 1.4, 0.02), Models.IVORY_D)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.13 * sx, 0.0, 0), Vector3(0.18, 0.34, 0.16), PARKA if sx > 0 else SKY_BLUE)
			b.octa(Vector3(0.13 * sx, 0.26, 0), 0.11, SKIN)
			b.box(Vector3(0.08 * sx, 0.32, 0), Vector3(0.05, 0.3, 0.05), PARKA if sx > 0 else SKY_BLUE)
		return b.commit())
