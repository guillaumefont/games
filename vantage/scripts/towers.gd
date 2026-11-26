class_name Towers
extends RefCounted
## Gun towers on the ground. Guillaume (2026-11-23): "add different types of towers" and "customize
## tower for each world, snowy, sandy, on a building". Four types, each its own gun and fire
## (`TYPES`): the flak turret (a spread of three), the rocket battery (a salvo of four), the howitzer
## (a big slow shell between two quick ones) and the pulse mast (a ring, its radar dish turning). Each
## stands on its world's footing (`base`): a concrete pad with sandbags on the coast, a stepped
## sandstone block half buried in a drift in the dunes, a whole building in the city (the gun on its
## roof), a snowed-over pad on the ice (snow on the gun too), a basalt crag split by magma in the
## cinders.
##
## A tower's node is its footing; the gun is a child (`top`, a `Foes` part: it turns to aim and
## flashes with the hit). The node sits at the gun's height (`height`) so the tower is hit where its
## gun shows from the tilted camera; the footing reaches down to the ground.
##
## Every gun stands on a pole (`POLE`): Guillaume (2026-11-24) couldn't tell a flak turret on its pad
## from a flying foe ("if it's a tower put it on a pole"). The pole and its long shadow tie the gun
## to the ground. A tower only stands where its whole footing is on firm, level ground
## (`Foes.dry_x` with `FOOT_R`), never hanging over a canyon rim, and the footing runs `SINK` m into
## the ground so a slope never shows air under it.

const TYPES := ["turret", "rocket", "howitzer", "pulse"]
## The types a world can field, by world: the coast starts with flak turrets and rocket
## batteries, the dunes bring howitzers, the city on pulse masts.
const BY_WORLD := [["turret", "rocket"], ["turret", "rocket", "howitzer"], ["turret", "rocket", "howitzer", "pulse"],
	["turret", "rocket", "howitzer", "pulse"], ["turret", "rocket", "howitzer", "pulse"]]

const SNOW := Color8(0xf2, 0xf6, 0xfa)
const SNOW_D := Color8(0xc8, 0xd6, 0xe6)
const ICE := Color8(0xa8, 0xd8, 0xf0)
const SANDSTONE := Color8(0xd4, 0xa8, 0x6a)
const SANDSTONE_D := Color8(0xa8, 0x7c, 0x48)
const DRIFT := Color8(0xe6, 0xcc, 0x92)
const WALL := Color8(0x6c, 0x6a, 0x66)
const WALL_D := Color8(0x4a, 0x48, 0x46)
const WINDOW := Color8(0x26, 0x2e, 0x38)
const LIT := Color8(0xff, 0xc8, 0x6a)
const SANDBAG := Color8(0xb0, 0xa0, 0x76)


## How tall the pole between the footing and the gun is, by theme (short on a city roof).
const POLE := {"coast": 1.6, "dunes": 1.3, "city": 0.9, "ice": 1.4, "volcano": 1.3}
## The footing's own height, by theme (the city's is the building).
## The city's building rises from its sunken streets (City.SINK) to stand among the towers.
const FOOT := {"coast": 0.5, "dunes": 0.9, "city": 2.6 + City.SINK, "ice": 0.6, "volcano": 1.0}
## How far out the footing reaches from the tower's centre (sandbags, drifts): all of it must stand
## on firm ground.
const FOOT_R := 1.8
## How far the footing runs on under the ground.
const SINK := 1.5


static func is_tower(kind: String) -> bool:
	return kind in TYPES


## How high the gun stands above the ground in a theme (the footing and the pole).
static func height(theme: String) -> float:
	return FOOT.get(theme, 0.5) + pole(theme)


static func pole(theme: String) -> float:
	return POLE.get(theme, 1.6)


# ---------------------------------------------------------------- models

## The footing of a tower in a theme and its pole, the pole's top at y = 0 (the gun's mount), down
## to -height (the ground) and on under it.
static func base(theme: String) -> Mesh:
	return Models.cached("tower_base_" + theme, func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		var h: float = FOOT.get(theme, 0.5)
		var up := pole(theme)
		# the footing, its top at -up
		b.xf = Transform3D(Basis.IDENTITY, Vector3(0, -up, 0))
		match theme:
			"dunes":
				# a stepped sandstone block, half buried in a drift, with a red band
				b.prism(Vector3(0, -h, 0), Models.ngon(1.7, 4, PI / 4), -SINK, 0.45, SANDSTONE_D, Vector2(0.92, 0.92))
				b.prism(Vector3(0, -h + 0.45, 0), Models.ngon(1.35, 4, PI / 4), 0.0, 0.45, SANDSTONE, Vector2(0.9, 0.9))
				b.box(Vector3(0, -0.12, 0), Vector3(1.75, 0.1, 1.75), Models.FOE)
				b.prism(Vector3(0.6, -h, 0.9), Models.ngon(1.2, 7), 0.0, 0.5, DRIFT, Vector2(0.4, 0.4), Vector2(0.2, 0.3))
				b.prism(Vector3(-0.9, -h, -0.5), Models.ngon(0.9, 7), 0.0, 0.35, DRIFT, Vector2(0.4, 0.4))
			"city":
				# a battered block of flats with the gun on its roof
				var w := 1.6
				b.box(Vector3(0, -(h + SINK) * 0.5 - 0.1, 0), Vector3(w * 2.0, h + SINK - 0.2, w * 2.0), WALL)
				for side in 4:
					var a := TAU * side / 4.0
					var n := Vector3(sin(a), 0, cos(a))
					var u := Vector3(cos(a), 0, -sin(a))
					for row in int((h - 0.4) / 0.9):
						for col in 3:
							var c := n * (w + 0.02) + u * (col - 1) * 0.95 + Vector3(0, -h + 0.55 + row * 0.9, 0)
							var lit := (row * 3 + col + side) % 5 == 0
							b.box(c, Vector3(0.5 * absf(u.x) + 0.06, 0.45, 0.5 * absf(u.z) + 0.06), LIT if lit else WINDOW)
				# parapet and roof
				b.box(Vector3(0, -0.15, 0), Vector3(w * 2.1, 0.12, w * 2.1), WALL_D)
				for k in 4:
					var a := TAU * k / 4.0
					b.box(Vector3(sin(a) * w, 0.0, cos(a) * w), Vector3(0.14 + absf(cos(a)) * w * 2.0, 0.3, 0.14 + absf(sin(a)) * w * 2.0), WALL_D)
				b.box(Vector3(0, -0.08, 0), Vector3(1.6, 0.06, 1.6), Models.FOE)
				# a sandbag wall on the roof's corner
				for k in 3:
					b.box(Vector3(-1.05 + k * 0.45, 0.0, 1.15), Vector3(0.42, 0.22, 0.28), SANDBAG, Vector2(0.85, 0.7))
			"ice":
				# a concrete pad under a cap of snow, a drift round its foot, icicles
				b.prism(Vector3(0, -h, 0), Models.ngon(1.3, 8, PI / 8), -SINK, h - 0.1, Models.HULL, Vector2(0.92, 0.92))
				b.prism(Vector3(0, -0.12, 0), Models.ngon(1.32, 8, PI / 8), 0.0, 0.16, SNOW, Vector2(0.88, 0.88))
				b.prism(Vector3(0, -h, 0), Models.ngon(1.9, 9), 0.0, 0.28, SNOW_D, Vector2(0.55, 0.55))
				for k in 8:
					var a := TAU * (k + 0.5) / 8.0
					b.prism(Vector3(sin(a) * 1.18, -0.12, cos(a) * 1.18), Models.ngon(0.08, 4), 0.0, -0.32, ICE, Vector2(0.1, 0.1))
			"volcano":
				# a basalt crag, cracked with glowing magma
				b.prism(Vector3(0, -h, 0), Models.ngon(1.6, 6, 0.3), -SINK, h, Foes.BASALT, Vector2(0.72, 0.72))
				for k in 3:
					var a := TAU * k / 3.0 + 0.4
					b.box(Vector3(sin(a) * 1.18, -h * 0.5, cos(a) * 1.18), Vector3(0.12 + absf(cos(a)) * 0.5, h * 0.8, 0.12 + absf(sin(a)) * 0.5), Foes.MAGMA)
				b.prism(Vector3(0, -0.06, 0), Models.ngon(1.15, 6, 0.3), 0.0, 0.08, Models.FOE)
			_:
				# the coast: a concrete pad in a ring of sandbags
				for k in 10:
					var a := TAU * k / 10.0
					b.box(Vector3(sin(a) * 1.5, -h + 0.14, cos(a) * 1.5), Vector3(0.55, 0.28, 0.36), SANDBAG, Vector2(0.85, 0.7))
				b.prism(Vector3(0, -h, 0), Models.ngon(1.15, 8, PI / 8), -SINK, h, Foes.CONCRETE, Vector2(0.9, 0.9))
				b.prism(Vector3(0, -0.06, 0), Models.ngon(0.95, 8, PI / 8), 0.0, 0.08, Models.FOE)
		# the pole: a steel column on a flange, four fins at its foot, a red band, a collar under the gun
		b.xf = Transform3D.IDENTITY
		b.prism(Vector3(0, -up, 0), Models.ngon(0.6, 8, PI / 8), 0.0, 0.14, Models.HULL_D, Vector2(0.85, 0.85))
		b.prism(Vector3(0, -up, 0), Models.ngon(0.3, 8, PI / 8), 0.0, up, Models.HULL, Vector2.ONE)
		b.prism(Vector3(0, -up * 0.5, 0), Models.ngon(0.33, 8, PI / 8), -0.12, 0.12, Models.FOE, Vector2.ONE)
		for k in 4:
			var a := TAU * k / 4.0
			var n := Vector3(sin(a), 0, cos(a))
			b.box(n * 0.42 + Vector3(0, -up + up * 0.225 + 0.1, 0), Vector3(0.08 + absf(n.x) * 0.3, up * 0.45, 0.08 + absf(n.z) * 0.3), Models.HULL_D)
		b.prism(Vector3(0, -0.16, 0), Models.ngon(0.5, 8, PI / 8), 0.0, 0.16, Models.FOE_D, Vector2(0.85, 0.85))
		return b.commit())


## A tower's gun (turns to aim), its mount at y = 0 and its muzzle to +z; snowed on in the ice.
static func top(kind: String, snowy: bool) -> Mesh:
	return Models.cached("tower_top_%s_%s" % [kind, snowy], func() -> Mesh:
		var b := Models.Builder.new()
		var roof := 0.0
		match kind:
			"rocket":
				# a swivel and a box of four rocket tubes
				b.prism(Vector3.ZERO, Models.ngon(0.55, 8, PI / 8), 0.0, 0.3, Models.FOE_D)
				b.box(Vector3(0, 0.62, 0.05), Vector3(1.2, 0.62, 1.0), Models.FOE, Vector2(0.95, 0.95))
				for k in 4:
					var c := Vector3((k % 2 - 0.5) * 0.56, 0.48 + (k / 2) * 0.3, 0.58)
					b.prism(c, Models.ngon(0.12, 8), 0.0, 0.04, Models.HULL_D)
					b.octa(c + Vector3(0, 0.04, 0.0), 0.08, Models.AMBER)
				b.box(Vector3(0, 0.62, -0.55), Vector3(1.0, 0.4, 0.12), Models.FOE_D)
				roof = 0.93
			"howitzer":
				# an armoured casemate and one long barrel with a muzzle brake
				b.prism(Vector3.ZERO, Models.pts([Vector2(0, 0.95), Vector2(0.75, 0.55), Vector2(0.75, -0.7),
					Vector2(-0.75, -0.7), Vector2(-0.75, 0.55)]), 0.0, 0.7, Models.FOE_D, Vector2(0.82, 0.82))
				b.box(Vector3(0, 0.72, -0.1), Vector3(0.9, 0.08, 0.7), Models.FOE)
				b.box(Vector3(0, 0.38, 1.6), Vector3(0.22, 0.22, 1.7), Models.HULL_D)
				b.box(Vector3(0, 0.38, 2.45), Vector3(0.36, 0.3, 0.22), Models.HULL_D)
				b.box(Vector3(0, 0.38, 2.58), Vector3(0.18, 0.18, 0.05), Models.AMBER)
				roof = 0.7
			"pulse":
				# a mast with a glowing emitter ring; its dish is a child that turns
				b.prism(Vector3.ZERO, Models.ngon(0.6, 6), 0.0, 0.3, Models.FOE_D, Vector2(0.85, 0.85))
				b.prism(Vector3(0, 0.3, 0), Models.ngon(0.22, 6), 0.0, 1.1, Models.HULL_D, Vector2(0.7, 0.7))
				b.prism(Vector3(0, 0.6, 0), Models.ngon(0.62, 10), 0.0, 0.12, Models.AMBER)
				b.prism(Vector3(0, 0.72, 0), Models.ngon(0.48, 10), 0.0, 0.1, Models.FOE)
				roof = 0.3
			_:
				# the flak turret: a drum, a hex turret and a barrel
				b.prism(Vector3.ZERO, Models.ngon(0.85, 8, PI / 8), 0.0, 0.4, Models.FOE_D, Vector2(0.85, 0.85))
				b.prism(Vector3(0, 0.4, 0), Models.ngon(0.6, 6), 0.0, 0.42, Models.FOE, Vector2(0.75, 0.75))
				for sx in [-1.0, 1.0]:
					b.box(Vector3(0.16 * sx, 0.62, 0.7), Vector3(0.14, 0.14, 0.9), Models.HULL_D)
				roof = 0.82
		if snowy and roof > 0.0:
			var cap := 0.5 if kind != "rocket" else 0.6
			b.prism(Vector3(0, roof, -0.05), Models.ngon(cap, 7), 0.0, 0.1, SNOW, Vector2(0.75, 0.75))
		return b.commit())


static func dish() -> Mesh:
	return Models.cached("tower_dish", func() -> Mesh:
		var b := Models.Builder.new()
		b.box(Vector3(0, 0, 0), Vector3(0.12, 0.12, 0.3), Models.HULL_D)
		b.prism(Vector3(0, 0, 0.25), Models.pts([Vector2(-0.7, -0.05), Vector2(0.7, -0.05), Vector2(0.55, 0.12),
			Vector2(-0.55, 0.12)]), -0.35, 0.35, Foes.CONCRETE, Vector2.ONE)
		b.octa(Vector3(0, 0, 0.55), 0.1, Models.AMBER)
		return b.commit())


# ---------------------------------------------------------------- in play

## Makes a foe a tower of its type in the current world: its footing, its gun (and dish).
static func build(g: Game, f: Game.Obj) -> void:
	var theme := Models.theme
	var gun := Models.instance(top(f.kind, theme == "ice"))
	gun.name = "top"
	gun.set_meta("part", true)
	f.node.add_child(gun)
	g.cast_shadow_of(gun)
	if f.kind == "pulse":
		var d := Models.instance(dish())
		d.name = "dish"
		d.position = Vector3(0, 1.4, 0)
		d.set_meta("part", true)
		gun.add_child(d)
	f.pos.y += height(theme)
	f.burst = 4 if f.kind == "rocket" else 0


static func think(g: Game, f: Game.Obj, dt: float) -> void:
	var at := Foes.at_of(g, f)
	var to := g.ppos - at
	# a bare turret (the old one-piece model) turns whole
	var gun := f.node.get_node_or_null("top") as Node3D
	if gun == null:
		gun = f.node
	gun.rotation.y = lerp_angle(gun.rotation.y, atan2(to.x, to.z), minf(1.0, dt * (2.0 if f.kind == "howitzer" else 5.0)))
	if gun != f.node:
		gun.position = gun.position.lerp(Vector3.ZERO, minf(1.0, dt * 5.0))
	if gun.has_node("dish"):
		(gun.get_node("dish") as Node3D).rotation.y += dt * 3.0
	if f.t < f.fire_t or not Foes.in_play(g, f):
		return
	var dir := Vector3(to.x, 0, to.z).normalized()
	match f.kind:
		"rocket":
			# a salvo of four, a little apart
			g.bullet(at + dir * 0.6, dir.rotated(Vector3.UP, g.rng.randf_range(-0.12, 0.12)) * 9.0)
			f.burst -= 1
			if f.burst > 0:
				f.fire_t = f.t + 0.2
			else:
				f.burst = 4
				f.fire_t = f.t + 3.0
		"howitzer":
			var shell := g.bullet(at + dir * 1.2, dir * 6.5)
			shell.size = 1.7
			shell.r = 0.42
			for a in [-0.38, 0.38]:
				g.bullet(at + dir * 1.2, dir.rotated(Vector3.UP, a) * 9.0)
			if gun != f.node:
				gun.position = -Vector3(sin(gun.rotation.y), 0, cos(gun.rotation.y)) * 0.35   # recoil
			f.fire_t = f.t + 2.8
		"pulse":
			g.ring(at, 10, 5.5, f.t * 0.7)
			f.fire_t = f.t + 2.6
		_:
			for k in 3:
				g.bullet(at, dir.rotated(Vector3.UP, (k - 1) * 0.12) * 9.5)
			f.fire_t = f.t + 2.4
