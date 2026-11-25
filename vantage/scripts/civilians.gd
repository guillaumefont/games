class_name Civilians
extends RefCounted
## Each world's own civilian (Guillaume, 2026-11-25: "There should be no seaplane in the desert. You
## should replace it in each world with something appropriate... in the desert, that could be a
## camel caravan"). The campaign's waves still say "gull" (the civilian stroll, `Foes.INTRO`'s
## first kind); `Foes.spawn` turns it into the world's own (`BY_THEME`):
## - Glass Coast: the seaplane (`Foes.gull`), whose pilot bails out under a parachute.
## - Ember Dunes: a paramotor, a pilot with a fan cage on their back under a striped wing; downed, the
##   motor coughs and dies and the pilot spirals away under the wing.
## - Iron Sprawl: an advertising blimp; downed, it whizzes off like a let-go party balloon.
## - Frost Shelf: a polar research helicopter; downed, its rotor spins off like a sycamore seed with the
##   pilot hanging underneath.
## - Cinder Reach: a hot-air balloon; downed, its crew float away under a bunch of party balloons.
## Simple low poly craft, no animals (Guillaume, 2026-11-25: "Camel and reindeer are a bad idea... You need
## to have simple shapes to keep the realism plausible"). They all keep the seaplane's rules: one at a time, harmless (`Foes.HARMLESS`), nothing scored,
## and some are hacked and unveil a minigun (`Foes.HACK_P`, `MOUNT`). The escape is `Blasts.escape`.

const BY_THEME := {"coast": "gull", "dunes": "paramotor", "city": "blimp", "ice": "heli", "volcano": "balloon"}
## How fast each strolls across the screen (m/s).
const SPEED := {"gull": 2.4, "paramotor": 2.0, "blimp": 1.9, "heli": 2.3, "balloon": 1.6}
## Where a hacked one's minigun pops up (on the wing, the paraglider's wing, the helicopter's nose,
## the blimp's back, the balloon's crown).
const MOUNT := {"gull": Vector3(0, 0.78, 0.1), "paramotor": Vector3(0, 1.75, 0.05), "heli": Vector3(0, 0.2, 1.25),
	"blimp": Vector3(0, 0.9, 0.3), "balloon": Vector3(0, 1.3, 0)}

const ROPE := Color8(0x5e, 0x3c, 0x22)
const SAFFRON := Color8(0xe8, 0xb0, 0x30)
const PARKA := Color8(0xe8, 0x6a, 0x2a)
const AD := Color8(0xf4, 0xd0, 0x40)
const SKY_BLUE := Color8(0x36, 0xb8, 0xe8)
const SKIN := Color8(0xf0, 0xc8, 0x9a)
const PARTY := [Color8(0xff, 0x40, 0x50), Color8(0xff, 0xd2, 0x2e), Color8(0x3d, 0xd6, 0xf5), Color8(0xff, 0x7a, 0xc8),
	Color8(0x6a, 0xd8, 0x4a), Color8(0xf4, 0xf4, 0xf0), Color8(0x9a, 0x6c, 0xff)]


## The civilian of the world being played.
static func of_world() -> String:
	return BY_THEME.get(Models.theme, "gull")


static func mesh(kind: String) -> Mesh:
	match kind:
		"paramotor": return paramotor()
		"heli": return heli()
		"blimp": return blimp()
		"balloon": return balloon()
	return Foes.gull()


## What bails out of a downed one (`Blasts.escape`).
static func escape_mesh(kind: String) -> Mesh:
	match kind:
		"paramotor": return paraglider()
		"heli": return heli_seed()
		"blimp": return blimp()
		"balloon": return party_balloons()
	return Foes.chute()


# ---------------------------------------------------------------- the stroll

## Sets a new civilian off, from the side `s` (-1 left, 1 right), across the screen.
static func spawn(g: Game, f: Game.Obj, s: float) -> void:
	f.x0 = s
	var v: float = SPEED.get(f.kind, 2.0)
	var z := g.hold_z(6.5)
	f.goal = Vector3(0, 0, z)
	f.pos = Vector3(s * (g.view_hw(z) + 2.5), Rules.PY, g.frame_z + z)
	f.vel = Vector3(-s * v, 0, 0)
	if f.kind == "heli":
		Foes.add_part(g, f, "heli blades", Vector3(0, 0.66, 0.2))
	f.hacked = g.stage_t > Foes.HACK_AFTER and g.rng.randf() < Foes.HACK_P


static func think(g: Game, f: Game.Obj, dt: float) -> void:
	fly(g, f, dt)
	if not f.hacked:
		return
	var at := f.pos
	var z := at.z - g.frame_z
	if f.hold < 0.0 and Foes.in_play(g, f) and absf(at.x) < g.view_hw(z) - 2.5:
		f.hold = f.t
	if Foes.unveil(g, f, "minigun", MOUNT.get(f.kind, Vector3(0, 0.8, 0))):
		# slows to hose the ship with short bursts, the gun turned to face it
		f.vel.x = move_toward(f.vel.x, -f.x0 * SPEED.get(f.kind, 2.0) * 0.45, dt * 2.0)
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
		"heli":
			# nose down a little into its way, the rotor turning
			f.node.rotation = Vector3(0.12, atan2(f.vel.x, dz * 0.5), sin(f.t * 0.7) * 0.06)
			(f.node.get_node("heli blades") as Node3D).rotation.y += dt * 20.0
		"paramotor":
			# swings gently under its wing as it turns
			f.node.rotation = Vector3(sin(f.t * 1.4) * 0.05, atan2(f.vel.x, dz), sin(f.t * w) * 0.12 * -f.x0)
		_:
			f.node.rotation = Vector3(0, atan2(f.vel.x, dz), sin(f.t * w) * 0.18 * -f.x0)


# ---------------------------------------------------------------- models (nose to +z)

## A thin line from a to b (rigging, ropes).
static func line(b: Models.Builder, a: Vector3, to: Vector3, col: Color, w := 0.025) -> void:
	b.prism(Vector3(a.x, 0, a.z), Models.ngon(w, 4, PI / 4), a.y, to.y, col, Vector2.ONE, Vector2(to.x - a.x, to.z - a.z))


## Dunes: a paraglider's wing, an arc of orange and white cells over the pilot (the origin).
static func wing(b: Models.Builder) -> void:
	var n := 8
	var r := 2.1
	for i in n:
		var a0 := lerpf(-1.05, 1.05, float(i) / n)
		var a1 := lerpf(-1.05, 1.05, float(i + 1) / n)
		var p0 := Vector3(sin(a0) * r, 1.75 + (cos(a0) - 1.0) * r, 0)
		var p1 := Vector3(sin(a1) * r, 1.75 + (cos(a1) - 1.0) * r, 0)
		var col := PARKA if i % 2 == 0 else Models.IVORY
		var up := Vector3(-(sin(a0) + sin(a1)), cos(a0) + cos(a1), 0)
		for side: float in [1.0, -1.0]:
			var o := Vector3(0, 0.04 * side, 0)
			var f0 := p0 + o + Vector3(0, 0, 0.5)
			var f1 := p1 + o + Vector3(0, 0, 0.5)
			var b0 := p0 + o + Vector3(0, 0, -0.45)
			var b1 := p1 + o + Vector3(0, 0, -0.45)
			b.tri(f0, f1, b1, col if side > 0 else col.darkened(0.25), up * side)
			b.tri(f0, b1, b0, col if side > 0 else col.darkened(0.25), up * side)
	for x in [-1.6, -0.8, 0.8, 1.6]:
		var a := asin(x / r)
		line(b, Vector3(0.1 * signf(x), 0.25, 0), Vector3(x, 1.75 + (cos(a) - 1.0) * r, 0.1), Models.IVORY_D, 0.015)


## Dunes: the pilot in a harness seat, helmeted (the origin).
static func pilot(b: Models.Builder) -> void:
	b.box(Vector3(0, -0.05, 0), Vector3(0.36, 0.16, 0.42), Models.HULL_D)
	b.box(Vector3(0, 0.15, -0.05), Vector3(0.32, 0.36, 0.24), Models.NAVY)
	b.octa(Vector3(0, 0.42, -0.02), 0.13, SAFFRON)
	b.box(Vector3(0, -0.02, 0.32), Vector3(0.24, 0.1, 0.3), Models.NAVY)


## Dunes: a paramotor, the pilot with a caged fan on their back under the wing.
static func paramotor() -> Mesh:
	return Models.cached("c_paramotor", func() -> Mesh:
		var b := Models.Builder.new()
		wing(b)
		pilot(b)
		var cage := CylinderMesh.new()
		cage.top_radius = 0.5
		cage.bottom_radius = 0.5
		cage.height = 0.06
		cage.radial_segments = 12
		cage.rings = 1
		b.prim(cage, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.2, -0.38)), Models.IVORY_D)
		b.box(Vector3(0, 0.2, -0.3), Vector3(0.22, 0.22, 0.16), Models.HULL)
		b.box(Vector3(0, 0.2, -0.42), Vector3(0.9, 0.06, 0.04), Models.WOOD)
		return b.commit())


## The paramotor's pilot spiralling away under the wing once the motor has died (`Blasts.escape`).
static func paraglider() -> Mesh:
	return Models.cached("c_paraglider", func() -> Mesh:
		var b := Models.Builder.new()
		wing(b)
		pilot(b)
		return b.commit())


## Ice: a polar research helicopter, an orange and white cabin with a tail boom and skids (the
## two-blade rotor is a part, `Foes.part_mesh` "heli blades").
static func heli() -> Mesh:
	return Models.cached("c_heli", func() -> Mesh:
		var b := Models.Builder.new()
		b.box(Vector3(0, 0, 0.25), Vector3(0.9, 0.8, 1.4), PARKA)
		b.box(Vector3(0, -0.12, 0.25), Vector3(0.92, 0.16, 1.42), Models.IVORY)
		b.box(Vector3(0, 0.08, 1.02), Vector3(0.78, 0.5, 0.2), Models.GLASS)
		b.box(Vector3(0, 0.46, 0.2), Vector3(0.5, 0.14, 0.7), Models.IVORY)
		b.box(Vector3(0, 0.56, 0.2), Vector3(0.12, 0.12, 0.12), Models.HULL_D)
		b.box(Vector3(0, 0.15, -1.25), Vector3(0.18, 0.18, 1.7), PARKA)
		b.box(Vector3(0, 0.45, -2.0), Vector3(0.06, 0.55, 0.35), Models.IVORY)
		b.box(Vector3(0.08, 0.45, -2.05), Vector3(0.04, 0.55, 0.08), Models.HULL_D)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.45 * sx, -0.58, 0.25), Vector3(0.06, 0.06, 1.6), Models.HULL_D)
			for z in [-0.2, 0.7]:
				b.box(Vector3(0.4 * sx, -0.48, z), Vector3(0.05, 0.2, 0.05), Models.HULL_D)
		return b.commit())


## The helicopter's rotor spinning off like a sycamore seed, the pilot hanging underneath (`Blasts.escape`).
static func heli_seed() -> Mesh:
	return Models.cached("c_heli_seed", func() -> Mesh:
		var b := Models.Builder.new()
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.9 * sx, 0.6, 0), Vector3(1.8, 0.06, 0.3), Models.IVORY)
			b.box(Vector3(1.9 * sx, 0.61, 0), Vector3(0.3, 0.06, 0.3), PARKA)
		b.box(Vector3(0, 0.6, 0), Vector3(0.2, 0.14, 0.2), Models.IVORY)
		line(b, Vector3(0, -0.2, 0), Vector3(0, 0.55, 0), Models.IVORY_D)
		b.box(Vector3(0, -0.4, 0), Vector3(0.4, 0.45, 0.3), PARKA)
		b.octa(Vector3(0, -0.12, 0), 0.13, Models.IVORY)
		b.box(Vector3(0, -0.05, 0), Vector3(0.36, 0.05, 0.05), PARKA)
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
