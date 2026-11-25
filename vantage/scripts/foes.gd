class_name Foes
extends RefCounted
## The campaign's own foes, on top of the first ones (darts, swings, turrets, heavies), which
## every world keeps. Guillaume (2026-11-23): "I feel like I've encountered the same enemies" and
## "staggered types": each level brings in one new kind (`INTRO`, in level order, so a world's
## three levels debut that world's three), announced the first time it shows. Later levels keep
## the kinds already met (`Campaign.mix_of`): the world's own the most, earlier worlds' the least.
##
## Each kind has its model (built here, low poly in the game's style, nose to +z, the player's
## way), its way in, its movement and its attack (`think`). Air foes fly on the flight plane with
## the scroll (`rel`); ground foes stay on the land, and some drive. Parts that move on their own
## (rotors, a tank's turret, fans) are child meshes tagged `part`: they flash with the hit and cast
## their own shadow.

## The kind each level debuts, by level (1-1 first).
const INTRO := ["gull", "rotor", "pillbox", "scarab", "tank", "borer", "seeker", "aa", "gunship",
	"lancer", "hover", "prism", "ember", "mortar", "wyrm"]
## Names on the "NEW" banner.
const NAMES := {
	"gull": "Gull seaplane", "rotor": "Whirl gyrocopter", "pillbox": "Beach pillbox",
	"scarab": "Scarab skimmer", "tank": "Dune tank", "borer": "Sand borer",
	"seeker": "Seeker quadcopters", "aa": "Flak gun", "gunship": "Hornet gunship",
	"lancer": "Lancer interceptor", "hover": "Floe hovercraft", "prism": "Rime crystal",
	"ember": "Magma drone", "mortar": "Cinder walker", "wyrm": "Ash wyrm",
}
## Collateral targets, not threats (Guillaume, 2026-11-24: "Hydro planes should be a collateral
## damage, not an enemy. It should stroll by (alone) waiting to be shot"): they never fire and the
## ship flies through them unharmed (not in `Rules.RAMMABLE`).
const HARMLESS := ["gull"]
## How fast a seaplane strolls across the screen (m/s).
const GULL_SPEED := 2.4
## Hacked civilians (Guillaume, 2026-11-24: "civil characters can be enemies if they are clearly
## hacked: a lighthouse that opens to show a turret, a hydro plane that unveils a minigun"). The
## chance a seaplane is hacked, after the level's opening (its first seaplane is always real), and
## how long a hacked one gives itself away (blinking, sparks) before its gun comes out.
const HACK_P := 0.35
const HACK_AFTER := 12.0
const HACK_TELL := 0.9
## How long the gun takes to come out once the tell is over.
const HACK_UNVEIL := 0.35

## On the ground (ramming passes under them; they stay with the land).
const GROUND := ["pillbox", "tank", "borer", "aa", "hover", "mortar"]
## Those that stand on dry land (the hovercraft rides the water too; the tank drives on).
const DRY := ["pillbox", "borer", "aa", "mortar"]

const CONCRETE := Color8(0xc2, 0xbc, 0xae)
const CAMO := Color8(0xc0, 0x8e, 0x52)
const CAMO_D := Color8(0x7a, 0x5a, 0x34)
const TRACK := Color8(0x34, 0x30, 0x2c)
const BEETLE := Color8(0x1c, 0x7c, 0x6c)
const BEETLE_D := Color8(0x10, 0x48, 0x40)
const DRAB := Color8(0x5c, 0x64, 0x3c)
const DRAB_D := Color8(0x3a, 0x40, 0x28)
const SANDBAG := Color8(0xa8, 0x98, 0x70)
const CRYSTAL := Color8(0x9a, 0x6c, 0xff)
const CRYSTAL_L := Color8(0xd4, 0xc4, 0xff)
const BASALT := Color8(0x3c, 0x32, 0x30)
const BASALT_L := Color8(0x5a, 0x4c, 0x46)
const MAGMA := Color8(0xff, 0x7a, 0x1e)


static func is_ground(kind: String) -> bool:
	return kind in GROUND or Towers.is_tower(kind)


# ---------------------------------------------------------------- models

static func mesh(kind: String, idx := 0) -> Mesh:
	if Towers.is_tower(kind):
		return Towers.base(Models.theme)
	match kind:
		"gull": return gull()
		"rotor": return rotor()
		"pillbox": return pillbox()
		"scarab": return scarab()
		"tank": return tank()
		"borer": return borer()
		"seeker": return seeker()
		"aa": return aa()
		"gunship": return gunship()
		"lancer": return lancer()
		"hover": return hover()
		"prism": return crystal()
		"ember": return ember()
		"mortar": return mortar()
		"wyrm": return wyrm_head() if idx == 0 else wyrm_body()
	return null


## A part of a foe that moves on its own (`Game.Obj.node`'s children tagged `part`).
static func part_mesh(name: String) -> Mesh:
	match name:
		"blades": return blades(1.35, 2, 0.16)
		"rotor": return blades(2.3, 4, 0.2)
		"quad": return quad_blades()
		"turret": return tank_turret()
		"gun": return aa_guns()
		"fan": return fan()
		"core": return magma_core()
		"minigun": return minigun()
		"hacked turret": return Models.turret()
	return null


static func side(sx: float, a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p: Vector2 in a:
		o.append(Vector2(p.x * sx, p.y))
	if sx < 0:
		o.reverse()
	return o


## Coast: a seaplane with a high wing, two floats and a nose propeller.
static func gull() -> Mesh:
	return Models.cached("f_gull", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 1.3), Vector2(0.26, 0.9), Vector2(0.3, -0.7),
			Vector2(0.12, -1.5), Vector2(-0.12, -1.5), Vector2(-0.3, -0.7), Vector2(-0.26, 0.9)]),
			-0.2, 0.2, Models.FOE, Vector2(0.75, 0.9))
		b.prism(Vector3(0, 0, 0.45), Models.ngon(0.2, 6, PI / 2), 0.2, 0.36, Models.GLASS, Vector2(0.6, 0.6))
		# the high wing, red tips
		b.box(Vector3(0, 0.46, 0.2), Vector3(3.2, 0.08, 0.62), Models.IVORY)
		for sx in [1.0, -1.0]:
			b.box(Vector3(1.45 * sx, 0.52, 0.2), Vector3(0.32, 0.06, 0.64), Models.FOE)
			# struts and floats
			b.box(Vector3(0.24 * sx, 0.3, 0.2), Vector3(0.06, 0.3, 0.06), Models.IVORY_D)
			b.box(Vector3(0.6 * sx, -0.32, 0.3), Vector3(0.06, 0.5, 0.06), Models.IVORY_D)
			b.prism(Vector3(0.6 * sx, 0, 0.2), Models.pts([Vector2(0, 1.0), Vector2(0.13, 0.7), Vector2(0.13, -0.8),
				Vector2(-0.13, -0.8), Vector2(-0.13, 0.7)]), -0.66, -0.5, Models.IVORY, Vector2(0.8, 0.9))
		# tail
		b.box(Vector3(0, 0.12, -1.35), Vector3(1.2, 0.05, 0.32), Models.IVORY)
		b.prism(Vector3(0, 0, -1.25), Models.pts([Vector2(-0.04, -0.25), Vector2(0.04, -0.25), Vector2(0.04, 0.25),
			Vector2(-0.04, 0.25)]), 0.15, 0.7, Models.FOE_D, Vector2(1, 0.5), Vector2(0, -0.2))
		b.prism(Vector3(0, 0, 1.38), Models.ngon(0.1, 6), -0.1, 0.1, Models.AMBER)
		return b.commit())


## A seaplane pilot under a parachute (`Blasts.chute`): a round canopy of red and white panels
## over the pilot (the origin), seen from above, with its rigging lines.
static func chute() -> Mesh:
	return Models.cached("f_chute", func() -> Mesh:
		var b := Models.Builder.new()
		var n := 10
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var col := Models.FOE if k % 2 == 0 else Models.IVORY
			# a panel: from the crown out to the rim, which hangs a little lower
			b.prism(Vector3(0, 1.55, 0), Models.pts([Vector2.ZERO, Vector2(cos(a1), sin(a1)) * 0.95,
				Vector2(cos(a0), sin(a0)) * 0.95]), 0.0, 0.14, col)
			b.prism(Vector3(0, 1.35, 0), Models.pts([Vector2(cos(a0), sin(a0)) * 0.7, Vector2(cos(a1), sin(a1)) * 0.7,
				Vector2(cos(a1), sin(a1)) * 1.12, Vector2(cos(a0), sin(a0)) * 1.12]), 0.0, 0.12, col.darkened(0.08))
		for k in 4:
			var a := TAU * k / 4 + PI / 4
			b.box(Vector3(cos(a) * 0.45, 0.75, sin(a) * 0.45), Vector3(0.03, 1.2, 0.03), Models.IVORY_D)
		b.box(Vector3(0, 0, 0), Vector3(0.26, 0.36, 0.2), Models.NAVY)
		b.octa(Vector3(0, 0.3, 0), 0.13, Color8(0xf0, 0xc8, 0x9a))
		return b.commit())


## A hacked seaplane's minigun, popped up on a mount over its wing (seen from above): six
## barrels round a dark drum, pointing +z.
static func minigun() -> Mesh:
	return Models.cached("f_minigun", func() -> Mesh:
		var b := Models.Builder.new()
		b.box(Vector3(0, -0.2, -0.05), Vector3(0.14, 0.3, 0.14), Models.HULL_D)
		b.box(Vector3(0, 0, -0.1), Vector3(0.5, 0.36, 0.7), Models.HULL_D)
		b.box(Vector3(0, 0.19, -0.1), Vector3(0.3, 0.04, 0.5), Color8(0xff, 0x30, 0x40))
		for k in 6:
			var a := TAU * k / 6.0
			b.box(Vector3(cos(a) * 0.13, sin(a) * 0.13, 0.6), Vector3(0.07, 0.07, 1.0), Models.STEEL_D)
		b.prism(Vector3(0, 0, 1.12), Models.ngon(0.2, 6), -0.05, 0.05, Models.AMBER)
		return b.commit())


## Rotor blades round y: `n` blades of radius r.
static func blades(r: float, n: int, w: float) -> Mesh:
	return Models.cached("f_blades%s_%d" % [r, n], func() -> Mesh:
		var b := Models.Builder.new()
		for k in n:
			var a := PI * k / n
			var d := Vector2(cos(a), sin(a))
			var p := Vector2(-d.y, d.x) * w * 0.5
			var o := Models.pts([d * r + p, d * r - p, -d * r - p, -d * r + p])
			if (o[1] - o[0]).cross(o[2] - o[1]) > 0:
				o.reverse()
			b.prism(Vector3.ZERO, o, -0.025, 0.025, Models.HULL_D)
		b.prism(Vector3.ZERO, Models.ngon(0.14, 6), -0.06, 0.08, Models.AMBER)
		return b.commit())


## Coast: a gyrocopter, a round cabin under a spinning rotor (`blades` child).
static func rotor() -> Mesh:
	return Models.cached("f_rotor", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3(0, -0.3, 0.1), Models.ngon(0.55, 8, PI / 8), 0.0, 0.5, Models.FOE, Vector2(0.75, 0.75))
		b.prism(Vector3(0, -0.3, 0.1), Models.ngon(0.5, 8, PI / 8), -0.18, 0.0, Models.FOE_D)
		b.prism(Vector3(0, 0, 0.45), Models.ngon(0.26, 6), 0.0, 0.22, Models.GLASS, Vector2(0.6, 0.6))
		b.box(Vector3(0, 0.0, -0.9), Vector3(0.14, 0.14, 1.2), Models.FOE_D)
		b.prism(Vector3(0, 0, -1.4), Models.pts([Vector2(-0.04, -0.2), Vector2(0.04, -0.2), Vector2(0.04, 0.2),
			Vector2(-0.04, 0.2)]), -0.1, 0.55, Models.IVORY, Vector2(1, 0.6), Vector2(0, -0.15))
		b.box(Vector3(0, -0.02, -1.4), Vector3(0.8, 0.05, 0.22), Models.IVORY)
		b.box(Vector3(0, 0.3, 0.05), Vector3(0.1, 0.45, 0.1), Models.HULL_D)
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.42 * sx, -0.62, 0.1), Vector3(0.07, 0.07, 1.2), Models.HULL_D)
		b.octa(Vector3(0, -0.05, 0.62), 0.12, Models.AMBER)
		return b.commit())


## Coast: a hexagonal concrete pillbox with a gun slit and a ring of sandbags.
static func pillbox() -> Mesh:
	return Models.cached("f_pillbox", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		for k in 10:
			var a := TAU * k / 10.0
			b.box(Vector3(sin(a) * 1.45, 0.14, cos(a) * 1.45), Vector3(0.55, 0.28, 0.36), Models.SAND.darkened(0.08), Vector2(0.85, 0.7))
		# a stepped foundation (a sea fort's footing when it stands in the shallows)
		b.prism(Vector3.ZERO, Models.ngon(1.85, 6, PI / 6), -0.7, 0.0, CONCRETE.darkened(0.2), Vector2(0.95, 0.95))
		b.prism(Vector3.ZERO, Models.ngon(1.1, 6, PI / 6), 0.0, 0.6, CONCRETE, Vector2(0.9, 0.9))
		b.box(Vector3(0, 0.42, 0.96), Vector3(0.9, 0.14, 0.12), Models.NAVY)
		b.prism(Vector3(0, 0.6, 0), Models.ngon(1.15, 6, PI / 6), 0.0, 0.16, CONCRETE.darkened(0.12), Vector2(0.85, 0.85))
		b.prism(Vector3(0, 0.76, 0), Models.ngon(0.45, 6, PI / 6), 0.0, 0.1, Models.FOE)
		b.box(Vector3(0, 0.42, 1.25), Vector3(0.14, 0.14, 0.7), Models.HULL_D)
		return b.commit())


## Dunes: a beetle-shaped skimmer, two wing cases over amber jets.
static func scarab() -> Mesh:
	return Models.cached("f_scarab", func() -> Mesh:
		var b := Models.Builder.new()
		for sx in [1.0, -1.0]:
			b.prism(Vector3.ZERO, side(sx, [Vector2(0.06, 0.7), Vector2(0.55, 0.55), Vector2(0.85, 0.0),
				Vector2(0.75, -0.75), Vector2(0.35, -1.05), Vector2(0.06, -1.0)]), -0.15, 0.4, BEETLE, Vector2(0.75, 0.85))
			b.box(Vector3(0.5 * sx, 0.36, -0.15), Vector3(0.12, 0.08, 0.9), Models.FOE)
			for k in 3:
				b.box(Vector3(0.95 * sx, -0.18, 0.45 - k * 0.5), Vector3(0.36, 0.08, 0.1), BEETLE_D)
		b.prism(Vector3(0, 0, 0.9), Models.ngon(0.35, 6, PI / 2), -0.12, 0.25, BEETLE_D, Vector2(0.7, 0.7))
		for sx in [1.0, -1.0]:
			b.octa(Vector3(0.16 * sx, 0.12, 1.15), 0.1, Models.AMBER)
			b.box(Vector3(0.22 * sx, 0.05, 1.45), Vector3(0.06, 0.06, 0.4), BEETLE_D)
		b.prism(Vector3(0, -0.15, -0.2), Models.ngon(0.4, 8), -0.18, 0.0, Models.AMBER)
		return b.commit())


## Dunes: a desert tank's hull and tracks; its turret is a child (`turret`) that aims.
static func tank() -> Mesh:
	return Models.cached("f_tank", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		for sx in [1.0, -1.0]:
			b.prism(Vector3(0.78 * sx, 0, 0), Models.pts([Vector2(-0.24, -1.25), Vector2(0.24, -1.25), Vector2(0.24, 1.25),
				Vector2(-0.24, 1.25)]), 0.0, 0.42, TRACK, Vector2(1.0, 0.92))
			for k in 4:
				b.box(Vector3(0.78 * sx, 0.18, -0.9 + k * 0.6), Vector3(0.5, 0.26, 0.3), TRACK.lightened(0.1))
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 1.45), Vector2(0.62, 1.15), Vector2(0.62, -1.15), Vector2(-0.62, -1.15),
			Vector2(-0.62, 1.15)]), 0.22, 0.62, CAMO, Vector2(0.92, 0.95))
		b.box(Vector3(0, 0.66, -1.0), Vector3(1.0, 0.1, 0.3), CAMO_D)
		return b.commit())


static func tank_turret() -> Mesh:
	return Models.cached("f_tank_turret", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 0.75), Vector2(0.48, 0.45), Vector2(0.5, -0.5),
			Vector2(-0.5, -0.5), Vector2(-0.48, 0.45)]), 0.0, 0.38, CAMO_D, Vector2(0.85, 0.85))
		b.box(Vector3(0, 0.2, 1.3), Vector3(0.14, 0.14, 1.3), TRACK)
		b.box(Vector3(0, 0.2, 1.95), Vector3(0.22, 0.22, 0.18), TRACK)
		b.box(Vector3(0, 0.4, -0.05), Vector3(0.62, 0.05, 0.5), Models.FOE)
		b.prism(Vector3(0.22, 0.38, -0.15), Models.ngon(0.14, 6), 0.0, 0.12, Models.AMBER)
		return b.commit())


## Dunes: a drilling rig that burrows through the sand and surfaces to fire: a red drill on a
## column of plated rings (most of it stays under the sand).
static func borer() -> Mesh:
	return Models.cached("f_borer", func() -> Mesh:
		var b := Models.Builder.new()
		for k in 4:
			var y0 := -0.7 - k * 0.75
			b.prism(Vector3.ZERO, Models.ngon(0.95 - k * 0.04, 8, PI / 8), y0, y0 + 0.62, Models.RUST if k % 2 == 0 else CAMO_D, Vector2(0.92, 0.92))
		b.prism(Vector3.ZERO, Models.ngon(1.05, 8, PI / 8), -0.2, 0.0, Models.HULL_D)
		b.prism(Vector3.ZERO, Models.ngon(0.95, 8, PI / 8), 0.0, 1.5, Models.FOE, Vector2(0.12, 0.12))
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			b.prism(Vector3(sin(a) * 0.62, 0.0, cos(a) * 0.62), Models.ngon(0.16, 4, a), 0.1, 0.65, Models.AMBER, Vector2(0.2, 0.2), Vector2(-sin(a), -cos(a)) * 0.25)
		return b.commit())


## City: a small quadcopter that flies into the ship (its rotors a `quad` child).
static func seeker() -> Mesh:
	return Models.cached("f_seeker", func() -> Mesh:
		var b := Models.Builder.new()
		for a in [PI / 4, -PI / 4]:
			var d := Vector2(cos(a), sin(a)) * 0.62
			var p := Vector2(-d.y, d.x).normalized() * 0.07
			var o := Models.pts([d + p, d - p, -d - p, -d + p])
			if (o[1] - o[0]).cross(o[2] - o[1]) > 0:
				o.reverse()
			b.prism(Vector3.ZERO, o, -0.05, 0.05, DRAB_D)
		b.prism(Vector3.ZERO, Models.ngon(0.3, 6), -0.16, 0.16, DRAB, Vector2(0.75, 0.75))
		b.octa(Vector3(0, -0.2, 0.15), 0.16, Models.FOE)
		b.box(Vector3(0, -0.28, 0.35), Vector3(0.14, 0.12, 0.3), Models.AMBER)
		for k in 4:
			var a := PI / 4 + TAU * k / 4.0
			b.prism(Vector3(cos(a) * 0.62, 0, sin(a) * 0.62), Models.ngon(0.08, 6), -0.1, 0.12, DRAB_D)
		return b.commit())


static func quad_blades() -> Mesh:
	return Models.cached("f_quad", func() -> Mesh:
		var b := Models.Builder.new()
		for k in 4:
			var a := PI / 4 + TAU * k / 4.0
			var c := Vector3(cos(a) * 0.62, 0.13, sin(a) * 0.62)
			b.prism(c, Models.ngon(0.3, 8), 0.0, 0.03, Models.HULL_D.lightened(0.25))
		return b.commit())


## City: an anti-aircraft gun in a ring of sandbags; its twin barrels are a child (`gun`).
static func aa() -> Mesh:
	return Models.cached("f_aa", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		for k in 12:
			var a := TAU * k / 12.0
			b.box(Vector3(sin(a) * 1.3, 0.16, cos(a) * 1.3), Vector3(0.6, 0.32, 0.38), SANDBAG, Vector2(0.85, 0.7))
			if k % 2 == 0:
				b.box(Vector3(sin(a + 0.26) * 1.3, 0.42, cos(a + 0.26) * 1.3), Vector3(0.55, 0.22, 0.34), SANDBAG.darkened(0.06), Vector2(0.85, 0.7))
		b.prism(Vector3.ZERO, Models.ngon(0.9, 8, PI / 8), 0.0, 0.3, DRAB_D)
		return b.commit())


static func aa_guns() -> Mesh:
	return Models.cached("f_aa_guns", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.ngon(0.55, 6), 0.0, 0.45, DRAB, Vector2(0.85, 0.85))
		b.box(Vector3(0, 0.5, -0.1), Vector3(0.8, 0.12, 0.5), Models.FOE)
		for sx in [1.0, -1.0]:
			# barrels leaning forward and up
			b.prism(Vector3(0.2 * sx, 0, 0.1), Models.ngon(0.07, 6), 0.35, 1.3, Models.HULL_D, Vector2.ONE, Vector2(0, 1.2))
			b.prism(Vector3(0.2 * sx, 0, 1.3), Models.ngon(0.11, 6), 1.25, 1.38, Models.AMBER)
		return b.commit())


## City: an attack helicopter with stub wings and rocket pods; its rotor is a child (`rotor`).
static func gunship() -> Mesh:
	return Models.cached("f_gunship", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 1.9), Vector2(0.42, 1.3), Vector2(0.5, -0.6), Vector2(0.28, -1.2),
			Vector2(-0.28, -1.2), Vector2(-0.5, -0.6), Vector2(-0.42, 1.3)]), -0.4, 0.4, DRAB, Vector2(0.75, 0.88))
		b.prism(Vector3(0, 0, 1.0), Models.pts([Vector2(0, 0.75), Vector2(0.3, 0.3), Vector2(0.3, -0.5), Vector2(-0.3, -0.5),
			Vector2(-0.3, 0.3)]), 0.3, 0.6, Models.GLASS, Vector2(0.65, 0.75))
		b.box(Vector3(0, 0.05, -2.2), Vector3(0.22, 0.22, 2.2), DRAB_D, Vector2(0.8, 0.8))
		b.prism(Vector3(0, 0, -3.15), Models.pts([Vector2(-0.05, -0.3), Vector2(0.05, -0.3), Vector2(0.05, 0.3),
			Vector2(-0.05, 0.3)]), 0.0, 0.9, DRAB, Vector2(1, 0.5), Vector2(0, -0.2))
		b.box(Vector3(0.12, 0.45, -3.2), Vector3(0.05, 0.55, 0.55), Models.HULL_D)
		b.box(Vector3(0, 0.55, 0), Vector3(0.5, 0.3, 0.9), DRAB_D, Vector2(0.75, 0.8))
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.95 * sx, -0.05, 0.1), Vector3(1.0, 0.08, 0.5), DRAB_D)
			b.prism(Vector3(1.3 * sx, -0.22, 0.1), Models.ngon(0.18, 8, PI / 8), -0.18, 0.18, Models.FOE, Vector2.ONE)
			b.box(Vector3(1.3 * sx, -0.22, 0.2), Vector3(0.36, 0.36, 0.9), Models.FOE)
			b.box(Vector3(1.3 * sx, -0.22, 0.68), Vector3(0.26, 0.26, 0.06), Models.AMBER)
			b.box(Vector3(0.45 * sx, -0.62, 0.0), Vector3(0.07, 0.07, 1.8), Models.HULL_D)
		b.box(Vector3(0, -0.45, 1.6), Vector3(0.14, 0.14, 0.6), Models.HULL_D)
		return b.commit())


## Ice: a blade-like interceptor that charges up and fires a lance of shots.
static func lancer() -> Mesh:
	return Models.cached("f_lancer", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 2.0), Vector2(0.32, 0.3), Vector2(1.05, -0.95), Vector2(0.95, -1.15),
			Vector2(0.22, -0.75), Vector2(0, -1.1), Vector2(-0.22, -0.75), Vector2(-0.95, -1.15), Vector2(-1.05, -0.95),
			Vector2(-0.32, 0.3)]), -0.12, 0.12, Models.COBALT, Vector2(0.85, 0.9))
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 1.6), Vector2(0.16, 0.2), Vector2(0.1, -0.9), Vector2(-0.1, -0.9),
			Vector2(-0.16, 0.2)]), 0.12, 0.34, Models.FOE, Vector2(0.6, 0.8))
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.95 * sx, 0.14, -1.0), Vector3(0.12, 0.16, 0.4), Models.FOE)
		b.octa(Vector3(0, 0.05, 2.0), 0.18, Models.AMBER, Vector3(0.8, 0.8, 1.6))
		b.box(Vector3(0, 0.1, -1.05), Vector3(0.36, 0.2, 0.2), Models.AMBER)
		return b.commit())


## Ice: a hovercraft on a black skirt, red deck, cabin and two fans at its stern (`fan` children).
static func hover() -> Mesh:
	return Models.cached("f_hover", func() -> Mesh:
		var b := Models.Builder.new()
		var deck := Models.pts([Vector2(0, 1.6), Vector2(0.7, 1.35), Vector2(0.95, 0.6), Vector2(0.95, -1.2),
			Vector2(0.7, -1.45), Vector2(-0.7, -1.45), Vector2(-0.95, -1.2), Vector2(-0.95, 0.6), Vector2(-0.7, 1.35)])
		b.prism(Vector3.ZERO, deck, 0.05, 0.42, Models.HULL_D.darkened(0.3), Vector2(1.06, 1.04))
		b.prism(Vector3.ZERO, deck, 0.42, 0.62, Models.FOE, Vector2(0.94, 0.95))
		b.prism(Vector3(0, 0, 0.4), Models.pts([Vector2(0, 0.8), Vector2(0.5, 0.45), Vector2(0.5, -0.6), Vector2(-0.5, -0.6),
			Vector2(-0.5, 0.45)]), 0.62, 1.05, Models.IVORY, Vector2(0.8, 0.85))
		b.prism(Vector3(0, 0, 0.95), Models.pts([Vector2(0, 0.25), Vector2(0.42, 0.05), Vector2(0.42, -0.1), Vector2(-0.42, -0.1),
			Vector2(-0.42, 0.05)]), 0.8, 0.98, Models.GLASS)
		b.box(Vector3(0, 0.95, 1.55), Vector3(0.12, 0.12, 0.6), Models.HULL_D)
		for sx in [1.0, -1.0]:
			# fan ducts: a square ring standing up at the stern
			var c := Vector3(0.5 * sx, 1.05, -1.15)
			b.box(c + Vector3(0, 0.42, 0), Vector3(0.9, 0.1, 0.3), Models.IVORY_D)
			b.box(c + Vector3(0, -0.42, 0), Vector3(0.9, 0.1, 0.3), Models.IVORY_D)
			b.box(c + Vector3(0.42, 0, 0), Vector3(0.1, 0.84, 0.3), Models.IVORY_D)
			b.box(c + Vector3(-0.42, 0, 0), Vector3(0.1, 0.84, 0.3), Models.IVORY_D)
		return b.commit())


## A fan's blades turning round z (the hovercraft's, set upright at its stern).
static func fan() -> Mesh:
	return Models.cached("f_fan", func() -> Mesh:
		var b := Models.Builder.new()
		for k in 3:
			var a := TAU * k / 3.0
			var u := Vector3(cos(a), sin(a), 0)
			var v := Vector3(-sin(a), cos(a), 0)
			b.quad(u * 0.06 + v * 0.07, u * 0.36 + v * 0.1, u * 0.36 - v * 0.1, u * 0.06 - v * 0.07, Models.HULL_D, Vector3(0, 0, -1))
			b.quad(u * 0.06 + v * 0.07, u * 0.36 + v * 0.1, u * 0.36 - v * 0.1, u * 0.06 - v * 0.07, Models.HULL_D, Vector3(0, 0, 1))
		b.octa(Vector3.ZERO, 0.09, Models.AMBER)
		return b.commit())


## Ice: a violet crystal in an iron cage that spins and fires spirals.
static func crystal() -> Mesh:
	return Models.cached("f_crystal", func() -> Mesh:
		var b := Models.Builder.new()
		b.octa(Vector3.ZERO, 0.75, CRYSTAL, Vector3(1, 1.7, 1))
		for k in 4:
			var a := TAU * k / 4.0
			b.octa(Vector3(sin(a) * 0.75, -0.2, cos(a) * 0.75), 0.34, CRYSTAL_L, Vector3(0.7, 1.5, 0.7))
		b.prism(Vector3.ZERO, Models.ngon(1.25, 8, PI / 8), -0.12, 0.12, Models.NAVY)
		b.prism(Vector3.ZERO, Models.ngon(0.95, 8, PI / 8), 0.12, 0.16, Models.FOE)
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4
			b.box(Vector3(sin(a) * 1.25, 0, cos(a) * 1.25), Vector3(0.26, 0.4, 0.26), Models.AMBER)
		return b.commit())


## Volcano: a ball of basalt plates round a glowing magma core (`core` child, unshaded).
static func ember() -> Mesh:
	return Models.cached("f_ember", func() -> Mesh:
		var b := Models.Builder.new()
		var plates := [Vector3(1, 0.3, 0), Vector3(-1, 0.3, 0), Vector3(0, 0.3, 1), Vector3(0, 0.3, -1),
			Vector3(0.6, -0.6, 0.6), Vector3(-0.6, -0.6, -0.6), Vector3(0, 0.9, 0)]
		for k in plates.size():
			var d: Vector3 = (plates[k] as Vector3).normalized()
			b.octa(d * 0.78, 0.32, BASALT if k % 2 == 0 else BASALT_L, Vector3(1.1, 0.7, 1.1))
		# a red armoured collar round its waist, three horns
		b.prism(Vector3.ZERO, Models.ngon(0.95, 8, PI / 8), -0.1, 0.1, Models.FOE)
		for k in 3:
			var a := TAU * k / 3.0
			b.prism(Vector3(sin(a) * 0.95, 0, cos(a) * 0.95), Models.ngon(0.14, 4), -0.08, 0.08, BASALT, Vector2.ONE, Vector2(sin(a), cos(a)) * 0.4)
		return b.commit())


static func magma_core() -> Mesh:
	return Models.cached("f_magma", func() -> Mesh:
		var b := Models.Builder.new()
		b.octa(Vector3.ZERO, 0.8, MAGMA, Vector3(1, 1.0, 1))
		return b.commit())


## Volcano: a four-legged walker carrying a mortar.
static func mortar() -> Mesh:
	return Models.cached("f_mortar", func() -> Mesh:
		var b := Models.Builder.new()
		b.bottoms = false
		for k in 4:
			var a := TAU * k / 4.0 + PI / 4
			var d := Vector2(sin(a), cos(a))
			# a leg from the body out and down to a foot
			b.prism(Vector3(d.x * 0.6, 0, d.y * 0.6), Models.ngon(0.12, 4, PI / 4), 0.7, 1.05, BASALT_L, Vector2.ONE, d * 0.5)
			b.prism(Vector3(d.x * 1.25, 0, d.y * 1.25), Models.ngon(0.1, 4, PI / 4), 0.0, 1.0, BASALT, Vector2.ONE, -d * 0.18)
			b.prism(Vector3(d.x * 1.25, 0, d.y * 1.25), Models.ngon(0.22, 6), 0.0, 0.1, BASALT)
		b.prism(Vector3(0, 0.75, 0), Models.ngon(0.85, 6, PI / 6), 0.0, 0.45, BASALT, Vector2(0.85, 0.85))
		b.prism(Vector3(0, 1.2, 0), Models.ngon(0.65, 6, PI / 6), 0.0, 0.12, Models.FOE)
		b.prism(Vector3(0, 1.3, 0.1), Models.ngon(0.28, 8), 0.0, 0.8, Models.HULL_D, Vector2(1.1, 1.1), Vector2(0, 0.25))
		b.prism(Vector3(0, 2.1, 0.35), Models.ngon(0.32, 8), 0.0, 0.08, MAGMA)
		for sx in [1.0, -1.0]:
			b.octa(Vector3(0.3 * sx, 1.0, 0.72), 0.1, MAGMA)
		return b.commit())


## Volcano: the ash wyrm's head (horned, glowing eyes) and its plated body segments.
static func wyrm_head() -> Mesh:
	return Models.cached("f_wyrm_head", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 1.2), Vector2(0.45, 0.8), Vector2(0.7, -0.1), Vector2(0.5, -0.6),
			Vector2(-0.5, -0.6), Vector2(-0.7, -0.1), Vector2(-0.45, 0.8)]), -0.25, 0.3, BASALT, Vector2(0.75, 0.85))
		b.prism(Vector3.ZERO, Models.pts([Vector2(0, 0.9), Vector2(0.2, 0.3), Vector2(0.2, -0.5), Vector2(-0.2, -0.5),
			Vector2(-0.2, 0.3)]), 0.3, 0.45, Models.FOE, Vector2(0.6, 0.8))
		for sx in [1.0, -1.0]:
			b.octa(Vector3(0.36 * sx, 0.28, 0.55), 0.12, MAGMA)
			b.prism(Vector3(0.45 * sx, 0, -0.35), Models.ngon(0.1, 4), 0.2, 0.9, BASALT_L, Vector2(0.2, 0.2), Vector2(0.25 * sx, -0.5))
		return b.commit())


static func wyrm_body() -> Mesh:
	return Models.cached("f_wyrm_body", func() -> Mesh:
		var b := Models.Builder.new()
		b.prism(Vector3.ZERO, Models.ngon(0.55, 8, PI / 8), -0.25, 0.25, BASALT, Vector2(0.8, 0.8))
		b.prism(Vector3.ZERO, Models.ngon(0.6, 8, PI / 8), -0.06, 0.06, MAGMA)
		b.prism(Vector3.ZERO, Models.ngon(0.18, 4), 0.25, 0.6, Models.FOE, Vector2(0.2, 0.2), Vector2(0, -0.2))
		for sx in [1.0, -1.0]:
			b.box(Vector3(0.62 * sx, 0, 0), Vector3(0.3, 0.08, 0.16), BASALT_L)
		return b.commit())


# ---------------------------------------------------------------- spawning

## A child part on a foe (tagged so it flashes with the hit, with its own shadow).
static func add_part(g: Game, f: Game.Obj, name: String, at: Vector3, material: Material = null) -> MeshInstance3D:
	var mi := Models.instance(part_mesh(name), material)
	mi.name = name
	mi.position = at
	mi.set_meta("part", true)
	f.node.add_child(mi)
	g.cast_shadow_of(mi)
	return mi


## The spot nearest (x, z), across the field and then further ahead, where the land is dry, or
## (x, z) if there is none (all sea).
## A tower (`foot` past 0.9) that finds no firm ground (a canyon runs the whole width) settles for
## any dry, level floor (down in the canyon beside its river), else for a level riverbed (it stands
## in the water like a pier); never over a rim.
static func dry_x(g: Game, x: float, z: float, me: Game.Obj, foot := 0.9) -> Vector2:
	var tower := foot > 0.9
	var dzs := [0.0, -4.0, -8.0, -12.0, -16.0, -20.0, -24.0] if tower else [0.0, -4.0, -8.0, -12.0]
	for pass_i in (3 if tower else 1):
		for dz in dzs:
			for k in 15:
				var d := float((k + 1) / 2) * (1.0 if k % 2 == 0 else -1.0)
				var tx := clampf(x + d, -6.5, 6.5)
				var tz: float = z + dz
				var ok := g.land(tx, tz) > 0.06 if pass_i == 0 else (dry(g, tx, tz) if pass_i == 1 else true)
				if ok and footed(g, tx, tz, foot, pass_i == 0, pass_i < 2) and clear(g, tx, tz, me):
					return Vector2(tx, tz)
	return Vector2(x, z)


## Whether everything within `foot` m of (x, z) is firm land (or, not `firm`, any dry ground), and
## for a tower about level with its centre: its footing never hangs over a rim or a bank.
static func footed(g: Game, x: float, z: float, foot: float, firm := true, dry_only := true) -> bool:
	var y := g.ground_y(x, z)
	var n := 4 if foot <= 0.9 else 8
	for k in n:
		var a := TAU * k / n
		var px := x + sin(a) * foot
		var pz := z + cos(a) * foot
		if dry_only and ((g.land(px, pz) <= 0.0) if firm else not dry(g, px, pz)):
			return false
		if foot > 0.9 and absf(g.ground_y(px, pz) - y) > 0.5:
			return false
	return true


## No water or lava at (x, z) (a canyon floor counts).
static func dry(g: Game, x: float, z: float) -> bool:
	if Models.theme == "city":
		return g.land(x, z) > 0.0
	var v := Relief.at(x, z, Relief.raw(g.noise, x, z))
	return v.z == 0.0 and v.y > 0.0


## No other ground foe (but `me`) stands within 3.5 m of (x, z).
static func clear(g: Game, x: float, z: float, me: Game.Obj) -> bool:
	for f in g.foes:
		if f != me and is_ground(f.kind) and not f.dead and Vector2(f.pos.x - x, f.pos.z - z).length() < 3.5:
			return false
	return true


## Spawns foe i of n of a wave of `kind` entering at x (from `from`), past the screen's edge.
static func spawn(g: Game, kind: String, x: float, i: int, n: int, from := "top") -> void:
	var top := g.frame_z + minf(g.view_top, Rules.Z_TOP) - 2.5
	var gz := g.frame_z + minf(g.view_ground_top, top - g.frame_z - 3.0) - 2.0
	var spread := (i - (n - 1) * 0.5)
	var f := g.new_foe(kind, mesh(kind, i))
	f.idx = i
	if is_ground(kind):
		f.ground = true
		var sx := clampf(x * 1.25 + spread * 4.0, -6.5, 6.5)
		var at := dry_x(g, sx, gz, f, Towers.FOOT_R if Towers.is_tower(kind) else 0.9) if kind in DRY or Towers.is_tower(kind) else Vector2(sx, gz)
		f.pos = Vector3(at.x, g.ground_y(at.x, at.y), at.y)
		sx = at.x
		f.x0 = sx
	else:
		f.rel = true
		f.x0 = x * 1.25
		f.pos = Vector3(f.x0, Rules.PY, top)
	if Towers.is_tower(kind):
		f.fire_t = 1.5 + 0.4 * i
		Towers.build(g, f)
		return
	# the side a foe that holds comes in from when the top edge is too far (`Game.enter_toward`)
	var side := -1.0 if from == "left" else (1.0 if from == "right" else (-1.0 if (x < 0.0 or x == 0.0 and i % 2 == 0) else 1.0))
	match kind:
		"gull":
			# a lone seaplane out for a stroll: crosses the upper screen from one side to the other
			var s := -1.0 if from == "left" else (1.0 if from == "right" else (-1.0 if x < 0.0 else 1.0))
			var z := g.hold_z(6.5)
			f.x0 = s
			f.goal = Vector3(0, 0, z)
			f.pos = Vector3(s * (g.view_hw(z) + 2.5), Rules.PY, g.frame_z + z)
			f.vel = Vector3(-s * GULL_SPEED, 0, 0)
			f.hacked = g.stage_t > HACK_AFTER and g.rng.randf() < HACK_P
		"rotor":
			var gx := clampf(f.x0 + spread * 4.2, -6.0, 6.0)
			f.goal = Vector3(gx, 0, g.hold_z(7.5 - (i % 2) * 1.8))   # z: above the screen's centre
			g.enter_toward(f, gx, f.goal.z, signf(gx) if gx != 0.0 else side)
			f.fire_t = 2.0
			add_part(g, f, "blades", Vector3(0, 0.55, 0.05))
		"pillbox":
			f.fire_t = 1.2
			f.burst = 4
		"scarab":
			var gx := clampf(f.x0 + spread * 2.0, -6.0, 6.0)
			f.goal = Vector3(gx, 0, g.hold_z(7.0))
			g.enter_toward(f, gx, f.goal.z, side)
			f.fire_t = 0.0
		"tank":
			# drives in from one side, up the land, across the screen
			var s := -1.0 if from == "left" else (1.0 if from == "right" else (-1.0 if x < 0.0 else 1.0))
			f.x0 = s
			f.pos.x = s * (8.0 + i * 2.5)
			f.pos.z = gz - i * 2.0
			f.pos.y = g.ground_y(f.pos.x, f.pos.z)
			f.fire_t = 1.6 + 0.5 * i
			add_part(g, f, "turret", Vector3(0, 0.62, -0.1))
		"borer":
			f.under = true
			f.pos.y = g.ground_y(f.pos.x, f.pos.z) - 3.4
			f.burst = 2   # surfacings
		"seeker":
			f.pos.x = clampf(f.x0 + spread * 1.6, -6.5, 6.5)
			f.vel = Vector3(0, 0, 7.0)
			add_part(g, f, "quad", Vector3.ZERO)
		"aa":
			f.fire_t = 1.4 + 0.6 * i
			add_part(g, f, "gun", Vector3(0, 0.3, 0))
		"gunship":
			var s := -1.0 if from == "left" else (1.0 if from == "right" else (-1.0 if x < 0.0 else 1.0))
			var z := g.hold_z(8.0) + i * 3.0
			f.x0 = s
			f.pos = Vector3(s * (g.view_hw(z) + 4.0), Rules.PY, g.frame_z + z)
			f.goal = Vector3(s * 2.8, 0, z)
			f.fire_t = 2.0
			add_part(g, f, "rotor", Vector3(0, 0.78, 0))
		"lancer":
			var gx := clampf(f.x0 + spread * 3.0, -6.0, 6.0)
			f.goal = Vector3(gx, 0, g.hold_z(7.0 - (i % 2) * 1.6))
			g.enter_toward(f, gx, f.goal.z, signf(gx) if gx != 0.0 else side)
			f.burst = 3
		"hover":
			f.pos.z = gz - i * 3.0
			f.fire_t = 1.5 + 0.4 * i
			for sx in [1.0, -1.0]:
				var fan := add_part(g, f, "fan", Vector3(0.5 * sx, 1.05, -1.25))
				fan.name = "fan_l" if sx < 0.0 else "fan_r"
		"prism":
			var gx := clampf(f.x0 + spread * 5.0, -5.5, 5.5)
			f.goal = Vector3(gx, 0, g.hold_z(6.0 - (i % 2) * 2.0))
			g.enter_toward(f, gx, f.goal.z, signf(gx) if gx != 0.0 else side)
			f.fire_t = 2.0
		"ember":
			f.pos.x = clampf(f.x0 + spread * 2.4, -6.0, 6.0)
			f.x0 = f.pos.x
			f.fire_t = 1.4 + 0.3 * i
			add_part(g, f, "core", Vector3.ZERO, Models.glow(MAGMA))
		"mortar":
			f.fire_t = 1.6 + 0.8 * i
		"wyrm":
			f.fire_t = 2.0 + i * 0.45
			if i == n - 1 and i > 0:
				f.size = 0.75


# ---------------------------------------------------------------- behaviour

## Nudges a foe away from others of its kind closer than r on the flight plane, so a group keeps
## its spacing instead of stacking into one blob.
static func keep_apart(g: Game, f: Game.Obj, r: float, dt: float) -> void:
	for o: Game.Obj in g.foes:
		if o == f or o.kind != f.kind or o.dead:
			continue
		var away := Vector2(f.pos.x - o.pos.x, f.pos.z - o.pos.z)
		var d := away.length()
		if d < r:
			if d < 0.001:
				away = Vector2(1.0 if f.idx > o.idx else -1.0, 0.0)
				d = 1.0
			var push := away / d * (r - d) * minf(1.0, dt * 6.0)
			f.pos.x += push.x
			f.pos.z += push.y

## Where a foe shows on the flight plane (ground foes are seen at an angle).
static func at_of(g: Game, f: Game.Obj) -> Vector3:
	var at := g.seen(f.pos)
	return Vector3(at.x, Rules.PY, at.z)


## A hacked civilian giving itself away (from `hold`, set when it starts): it blinks and throws
## red sparks for HACK_TELL s, then its gun (part `name`, at `at`) unfolds out of it. Returns
## whether the gun is out and may fire.
static func unveil(g: Game, f: Game.Obj, name: String, at: Vector3) -> bool:
	if f.hold < 0.0:
		return false
	var k := f.t - f.hold
	if k < HACK_TELL:
		if fmod(k, 0.22) < 0.11:
			f.hit = maxf(f.hit, 0.05)
		if fmod(k, 0.3) < 0.02:
			g.pop(f.pos + Vector3(0, 0.6, 0), 0.5, Color8(0xff, 0x30, 0x40), f.ground)
		return false
	if not f.node.has_node(name):
		var mi := add_part(g, f, name, at)
		mi.scale = Vector3.ONE * 0.01
		g.pop(f.pos + at, 0.8, Color8(0xff, 0x30, 0x40), f.ground)
		g.sound.play("pop")
		f.fire_t = f.t + HACK_UNVEIL + 0.25
		f.burst = 6 if name == "minigun" else 3
	var gun := f.node.get_node(name) as Node3D
	gun.scale = Vector3.ONE * clampf((k - HACK_TELL) / HACK_UNVEIL, 0.01, 1.0)
	return k >= HACK_TELL + HACK_UNVEIL


## Whether a foe is far enough onto the screen to open fire.
static func in_play(g: Game, f: Game.Obj) -> bool:
	var at := g.seen(f.pos)
	var z := at.z - g.frame_z
	return z > g.view_top + 1.0 and z < g.view_bot - 4.0 and absf(at.x) < g.view_hw(z)


static func face(f: Game.Obj, d: Vector3, dt: float, k := 8.0) -> void:
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var want := atan2(d.x, d.z)
	f.node.rotation.y = lerp_angle(f.node.rotation.y, want, minf(1.0, dt * k))


static func think(g: Game, f: Game.Obj, dt: float) -> void:
	if Towers.is_tower(f.kind):
		Towers.think(g, f, dt)
		return
	match f.kind:
		"gull":
			# strolls across in a lazy wave, never fires: it's only there to be shot down
			f.pos.x += f.vel.x * dt
			f.pos.z = g.frame_z + f.goal.z + sin(f.t * 0.8) * 0.9
			var dz := cos(f.t * 0.8) * 0.72
			f.node.rotation = Vector3(0, atan2(f.vel.x, dz), sin(f.t * 0.8) * 0.18 * -f.x0)
			if f.hacked:
				var z := f.pos.z - g.frame_z
				if f.hold < 0.0 and in_play(g, f) and absf(f.pos.x) < g.view_hw(z) - 2.5:
					f.hold = f.t
				if unveil(g, f, "minigun", Vector3(0, 0.78, 0.1)):
					# slows to hose the ship with short bursts, nose round to face it
					f.vel.x = move_toward(f.vel.x, -f.x0 * GULL_SPEED * 0.45, dt * 2.0)
					var to := g.ppos - f.pos
					var gun := f.node.get_node("minigun") as Node3D
					gun.rotation.y = wrapf(atan2(to.x, to.z) - f.node.rotation.y, -PI, PI)
					if f.t >= f.fire_t and in_play(g, f):
						g.aimed(f.pos + to.normalized() * 0.9, 11.0)
						f.burst -= 1
						f.fire_t = f.t + (0.09 if f.burst > 0 else 1.5)
						if f.burst <= 0:
							f.burst = 6
		"lighthouse":
			# a hacked lighthouse: once well in view, its lantern blinks and sparks, then a
			# turret rises out of the top and fires aimed bursts
			if not f.hacked:
				return
			if f.hold < 0.0 and g.well_in_view(f) and in_play(g, f):
				f.hold = f.t
			var top := ((f.node as MeshInstance3D).mesh.get_aabb().end.y + 0.1) if f.node is MeshInstance3D else 1.0
			if unveil(g, f, "hacked turret", Vector3(0, top, 0)):
				var at := at_of(g, f)
				var to := g.ppos - at
				var gun := f.node.get_node("hacked turret") as Node3D
				gun.rotation.y = wrapf(atan2(to.x, to.z) - f.node.rotation.y, -PI, PI)
				if f.t >= f.fire_t and in_play(g, f):
					g.aimed(at, 10.0)
					f.burst -= 1
					f.fire_t = f.t + (0.15 if f.burst > 0 else 1.9)
					if f.burst <= 0:
						f.burst = 3
		"rotor":
			# drops into the upper screen, hovers firing rings, then sinks away down the screen
			var bl := f.node.get_node("blades") as Node3D
			bl.rotation.y += dt * 22.0
			if f.t < 7.0:
				f.pos.z = lerpf(f.pos.z, g.frame_z + f.goal.z, minf(1.0, dt * 1.8))
				f.pos.x = lerpf(f.pos.x, f.goal.x + sin(f.t * 1.1 + f.idx) * 1.2, minf(1.0, dt * 2.0))
				if f.t >= f.fire_t and in_play(g, f):
					f.fire_t = f.t + 1.7
					g.ring(f.pos, 8, 6.0, f.t)
			else:
				f.pos.z += 7.0 * dt
			face(f, g.ppos - f.pos, dt, 3.0)
		"pillbox":
			var at := at_of(g, f)
			face(f, g.ppos - at, dt, 4.0)
			if f.t >= f.fire_t and in_play(g, f):
				# a burst of four aimed shots, then a pause
				g.aimed(at, 10.5)
				f.burst -= 1
				if f.burst > 0:
					f.fire_t = f.t + 0.13
				else:
					f.burst = 4
					f.fire_t = f.t + 2.4
		"scarab":
			# dashes from side to side down the screen, fires a spread after each dash
			if f.t >= f.fire_t:
				f.burst += 1
				f.hold = f.t
				f.size_y = 0.0   # not fired yet on this dash
				f.fire_t = f.t + 1.2
				if f.burst > 5:
					f.goal = Vector3(f.pos.x, 0, maxf(g.view_bot, Rules.Z_BOT) + 8.0)
				else:
					var s := -1.0 if (f.burst + f.idx) % 2 == 0 else 1.0
					f.goal = Vector3(s * g.rng.randf_range(1.5, 5.5), 0, g.hold_z(7.0) + f.burst * 2.2)
			var k := minf(1.0, dt * 5.0)
			var was := f.pos
			f.pos.x = lerpf(f.pos.x, f.goal.x, k)
			f.pos.z = lerpf(f.pos.z, g.frame_z + f.goal.z, k)
			f.node.rotation.z = clampf(-(f.pos.x - was.x) / maxf(dt, 1e-4) * 0.05, -0.5, 0.5)
			if f.burst <= 5 and f.size_y == 0.0 and f.t - f.hold > 0.5 and in_play(g, f):
				f.size_y = 1.0
				g.fan(f.pos + Vector3(0, 0, 1.0), 3, 0.5, 9.0)
		"tank":
			# drives up the land and across, its turret tracking the ship
			var d := Vector3(-f.x0 * 1.6, 0, -2.2)
			f.pos += d * dt
			f.pos.y = g.ground_y(f.pos.x, f.pos.z)
			face(f, d, dt)
			var at := at_of(g, f)
			var tur := f.node.get_node("turret") as Node3D
			var to := g.ppos - at
			tur.rotation.y = lerp_angle(tur.rotation.y, atan2(to.x, to.z) - f.node.rotation.y, minf(1.0, dt * 4.0))
			tur.position.z = lerpf(tur.position.z, -0.1, minf(1.0, dt * 6.0))
			if f.t >= f.fire_t and in_play(g, f):
				f.fire_t = f.t + 2.3
				g.aimed(at, 12.5)
				var dir := Vector3(to.x, 0, to.z).normalized()
				for a in [-0.28, 0.28]:
					g.bullet(at, dir.rotated(Vector3.UP, a) * 8.5)
				tur.position.z = -0.45   # recoil
		"borer":
			think_borer(g, f, dt)
		"seeker":
			# homes on the ship with a slow turn, then peels off
			if f.t < 5.0:
				var want := (g.ppos - f.pos)
				want.y = 0
				want = want.normalized() * 6.8
				f.vel = f.vel.lerp(want, minf(1.0, dt * 1.2))
			else:
				f.vel.x += (1.0 if f.pos.x > 0.0 else -1.0) * 14.0 * dt
			f.pos += f.vel * dt
			keep_apart(g, f, 2.0, dt)   # a swarm, not one blob
			f.node.rotation = Vector3(0, atan2(f.vel.x, f.vel.z), sin(f.t * 9.0) * 0.12)
			(f.node.get_node("quad") as Node3D).rotation.y += dt * 30.0
		"aa":
			var at := at_of(g, f)
			var gun := f.node.get_node("gun") as Node3D
			var to := g.ppos - at
			gun.rotation.y = lerp_angle(gun.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 3.0))
			if f.t >= f.fire_t and in_play(g, f):
				# a flak shell that bursts where the ship was
				f.fire_t = f.t + 2.5
				g.shell(at, g.ppos + Vector3(g.rng.randf_range(-1.0, 1.0), 0, g.rng.randf_range(-1.0, 0.5)), 8.0, 7)
		"gunship":
			(f.node.get_node("rotor") as Node3D).rotation.y += dt * 24.0
			var hover := f.t > 1.8 and f.t < 10.0
			if f.t < 10.0:
				f.pos.x = lerpf(f.pos.x, f.goal.x + sin(f.t * 0.8) * 0.8, minf(1.0, dt * 1.6))
				f.pos.z = lerpf(f.pos.z, g.frame_z + f.goal.z + sin(f.t * 0.6) * 0.6, minf(1.0, dt * 1.6))
			else:
				f.pos.x += f.x0 * 8.0 * dt
				f.pos.z -= 2.0 * dt
			var to := g.ppos - f.pos
			face(f, to if hover else Vector3(-f.x0, 0, 0.6), dt, 3.0)
			f.node.rotation.z = clampf((f.goal.x - f.pos.x) * -0.06, -0.3, 0.3)
			if hover and f.t >= f.fire_t and in_play(g, f):
				# sweeps a stream of shots across the ship, then pauses
				if f.burst <= 0:
					f.burst = 15
					f.size_y = -1.0 if f.size_y > 0.0 else 1.0   # sweep direction, alternating
				var k := 1.0 - f.burst / 15.0
				var a := lerpf(-0.75, 0.75, k) * f.size_y
				var dir := Vector3(to.x, 0, to.z).normalized().rotated(Vector3.UP, a)
				for sx in [-1.0, 1.0]:
					var side := Vector3(1.3 * sx, 0, 0).rotated(Vector3.UP, f.node.rotation.y)
					g.bullet(Vector3(f.pos.x + side.x, Rules.PY, f.pos.z + side.z), dir * 9.5)
				f.burst -= 1
				f.fire_t = f.t + (0.1 if f.burst > 0 else 1.5)
		"lancer":
			think_lancer(g, f, dt)
		"hover":
			# glides up the ice in an S, firing pairs
			var w := 0.9
			var nx := f.x0 + sin(f.t * w + f.idx * 1.3) * 4.5
			var d := Vector3((nx - f.pos.x) / maxf(dt, 1e-4), 0, -4.5)
			f.pos.x = clampf(nx, -7.0, 7.0)
			f.pos.z -= 4.5 * dt
			f.pos.y = g.ground_y(f.pos.x, f.pos.z) + 0.08 * sin(f.t * 5.0)
			face(f, d, dt, 6.0)
			for n in ["fan_l", "fan_r"]:
				(f.node.get_node(n) as Node3D).rotation.z += dt * 26.0
			if f.t >= f.fire_t and in_play(g, f):
				f.fire_t = f.t + 1.7
				var at := at_of(g, f)
				var to := g.ppos - at
				var dir := Vector3(to.x, 0, to.z).normalized()
				var across := Vector3(-dir.z, 0, dir.x) * 0.45
				g.bullet(at + across, dir * 10.0)
				g.bullet(at - across, dir * 10.0)
		"prism":
			# drifts in, spins out a two-armed spiral, then sinks away
			f.node.rotation.y += dt * (1.0 if f.t < 2.0 else 4.0)
			if f.t < 6.0:
				f.pos.z = lerpf(f.pos.z, g.frame_z + f.goal.z, minf(1.0, dt * 1.5))
				f.pos.x = lerpf(f.pos.x, f.goal.x, minf(1.0, dt * 1.5))
				if f.t >= f.fire_t and in_play(g, f):
					f.fire_t = f.t + 0.14
					var a := f.t * 2.4 + f.idx * 0.9
					for k in 2:
						var dir := Vector3(sin(a + PI * k), 0, cos(a + PI * k))
						g.bullet(f.pos + dir * 0.9, dir * 6.0)
			else:
				f.pos.z += 6.0 * dt
		"ember":
			# drifts down in a lazy weave, dropping fans of magma
			f.pos.z += 3.0 * dt
			f.pos.x = f.x0 + sin(f.t * 1.1 + f.idx) * 2.8
			f.node.rotation = Vector3(sin(f.t * 1.3) * 0.3, f.t * 0.8, 0)
			var c := f.node.get_node("core") as Node3D
			var p := 1.0 + 0.08 * sin(f.t * 9.0 + f.idx)
			c.scale = Vector3(p, p, p)
			if f.t >= f.fire_t and in_play(g, f):
				f.fire_t = f.t + 2.2
				for k in 5:
					var dir := Vector3(0, 0, 1).rotated(Vector3.UP, (k - 2) * 0.28)
					g.bullet(f.pos + dir * 0.8, dir * 7.0)
		"mortar":
			# stalks sideways, lobbing shells that burst round the ship
			var s := -1.0 if f.x0 > 0.0 else 1.0
			f.pos.x += s * 1.1 * dt
			f.pos.y = g.ground_y(f.pos.x, f.pos.z)
			face(f, g.ppos - at_of(g, f), dt, 3.0)
			if f.t >= f.fire_t and in_play(g, f):
				f.fire_t = f.t + 2.8
				g.shell(at_of(g, f), g.ppos, 7.0, 8)
		"wyrm":
			# weaves down the screen, each segment tracing the head's path a moment later
			var a := f.t * 1.3
			f.pos.x = f.x0 + sin(a) * 4.5
			f.pos.z += 5.0 * dt
			f.node.rotation.y = atan2(cos(a) * 4.5 * 1.3, 5.0)
			if f.t >= f.fire_t and in_play(g, f):
				f.fire_t = f.t + (1.6 if f.idx == 0 else 3.6)
				g.aimed(f.pos, 9.0)


## The borer: waits under the sand until well on screen, rises (a puff of sand), turns firing two
## rings, sinks again, and comes up once more further up the screen.
static func think_borer(g: Game, f: Game.Obj, dt: float) -> void:
	var gy := g.ground_y(f.pos.x, f.pos.z)
	var depth := 3.4
	f.node.rotation.y += dt * (6.0 if not f.under else 2.0)
	match f.idx:
		0:   # waiting under the sand
			f.pos.y = gy - depth
			var z := g.seen(Vector3(f.pos.x, gy, f.pos.z)).z - g.frame_z
			if z > g.view_top + 4.0 and f.t > 0.4 and z < g.view_bot - 6.0:
				f.idx = 1
				f.hold = f.t
				f.fire_t = f.t + 1.0
				g.pop(Vector3(f.pos.x, gy + 0.3, f.pos.z), 1.4, Models.SAND, true)
		1:   # up, firing
			var k := clampf((f.t - f.hold) / 0.7, 0.0, 1.0)
			f.pos.y = gy - depth * (1.0 - k * k * (3.0 - 2.0 * k)) * 1.0
			f.under = f.pos.y < gy - 1.2
			if f.t >= f.fire_t and not f.under:
				g.ring(at_of(g, f), 12, 6.5, f.t)
				f.fire_t = f.t + 1.0
				f.size_y += 1.0
			if f.size_y >= 2.0:
				f.idx = 2
				f.hold = f.t
		2:   # sinking
			var k := clampf((f.t - f.hold) / 0.6, 0.0, 1.0)
			f.pos.y = gy - depth * k
			f.under = f.pos.y < gy - 1.2
			if k >= 1.0:
				f.burst -= 1
				if f.burst > 0:
					# burrows up the screen, towards the ship's side
					f.pos.z -= 9.0
					f.pos.x = clampf(lerpf(f.pos.x, g.ppos.x, 0.6), -6.0, 6.0)
					f.size_y = 0.0
					f.idx = 0
				else:
					f.idx = 3
		3:
			f.pos.y = gy - depth


## The lancer: darts to a spot, glows as it charges, fires a lance of shots at the ship, darts
## across to another spot, three times, then climbs away.
static func think_lancer(g: Game, f: Game.Obj, dt: float) -> void:
	var k := minf(1.0, dt * 4.5)
	f.pos.x = lerpf(f.pos.x, f.goal.x, k)
	f.pos.z = lerpf(f.pos.z, g.frame_z + f.goal.z, k)
	f.node.rotation.z = clampf((f.goal.x - f.pos.x) * -0.25, -0.7, 0.7)
	f.size = 1.0
	if f.burst <= 0:
		f.goal.z -= 16.0 * dt
		return
	var since := f.t - f.hold if f.hold >= 0.0 else f.t
	if f.hold < 0.0 and f.t > 1.0:
		f.hold = f.t
	elif f.hold >= 0.0:
		if since < 0.6:
			f.size = 1.0 + 0.12 * sin(since * 40.0)   # charging
		elif f.fire_t >= 0.0 and in_play(g, f):
			var to := g.ppos - f.pos
			var dir := Vector3(to.x, 0, to.z).normalized()
			for n in 5:
				g.bullet(f.pos + dir * 1.8, dir * (14.0 - n * 1.2))
			f.fire_t = -1.0
			f.burst -= 1
			var s := -1.0 if f.pos.x > 0.0 else 1.0
			f.goal = Vector3(s * g.rng.randf_range(2.0, 5.5), 0, f.goal.z + 1.5)
		elif f.fire_t < 0.0 and since > 1.5:
			f.fire_t = 0.0
			f.hold = f.t
