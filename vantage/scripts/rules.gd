class_name Rules
extends RefCounted
## Every number and rule of Vantage, as pure functions on the save dictionary, so the tests
## can check them without the scene.

const SAVE_PATH := "user://save.json"

# ---------------------------------------------------------------- the play field
## Flight altitude of the vertical stage (the ground is y = 0).
const PY := 6.0
## Half width of the play field and its top/bottom edges, relative to the scroll frame.
const HALF_W := 7.5
const Z_TOP := -16.0
const Z_BOT := 12.0
## Scroll speed of the vertical stage (world units a second).
const SCROLL := 8.0
## Player hit radius (small, as the genre wants) and pickup radius.
const PLAYER_R := 0.42
## Ramming (Game.ram): flying into a foe costs a hit of hull and throws the ship back at KNOCK
## units/s (easing off at KNOCK_EASE/s). Small foes break up; others take RAM_DMG. Foes are
## touched within RAM_R of their radius. Ground targets, scenery and the fortress (always ahead
## of the ship) can't be rammed; the Bastion's hull is a wall (Game.boss_rammed).
const RAMMABLE := ["dart", "swing", "heavy", "drone"]
const RAM_KILLS := ["dart", "swing", "drone"]
const RAM_DMG := 12.0
const RAM_R := 0.7
const KNOCK := 9.0
const KNOCK_EASE := 30.0
const PICK_R := 1.0

# ---------------------------------------------------------------- the fortress (POV episode)
## The fortress: `FORTRESS_LEN` long, its bay (the opening in its tail where the reactor
## shows) centred on the flight altitude.
const FORTRESS_LEN := 120.0
## The fortress is tall and narrow (it fits a portrait screen in the chase): half width, the
## height of its hull and of its tower, and its hangar (half width, half height).
const FORTRESS_HW := 5.0
const FORTRESS_TOP := 13.0
const TOWER_TOP := 21.0
const BAY_HW := 3.0
const BAY_HH := 2.3
## The final bosses, flying fortresses taken apart in sections like the mid-bosses: each section's
## gun mounts are (x, y) on the fortress's stern (z from `Models.mount_z`), all within the ship's
## reach in the chase (|x| <= 4.6, y <= 19.6, tested), on a `piece` that breaks off when the
## section falls: `collar` (gun pods either side of the bay), `plating` (armour on the stern),
## `tower` (a casemate on the spine) or `fin` (a tall dorsal fin). The last section is the
## reactor in the bay behind its shield panels. Each fortress has its own hull section (`hull`:
## box, round or hex), wings (`Models.WINGS`: propellers, short stubs, jets), tail (`fins`), paint,
## accent colour and drone rate. Each level has its own (`Campaign.fortress_of`).
const FORTRESSES := {
	"goliath": {"name": "Goliath", "title": "Goliath-class flying fortress", "hull": "box", "wings": "props", "fins": "twin",
		"paint": "steel", "accent": Color8(0xff, 0xa8, 0x2e), "drones": 6.5, "sections": [
		{"name": "TAIL GUNS", "piece": "plating", "mounts": [Vector2(-4.0, 3.2), Vector2(4.0, 3.2), Vector2(-4.0, 9.0),
			Vector2(4.0, 9.0), Vector2(-2.0, 10.8), Vector2(2.0, 10.8)]},
		{"name": "GUN TOWER", "piece": "tower", "mounts": [Vector2(-3.0, 14.5), Vector2(3.0, 14.5), Vector2(0.0, 16.0),
			Vector2(-1.8, 19.5), Vector2(1.8, 19.5)]},
		{"name": "REACTOR", "piece": "", "mounts": []},
	]},
	# an armoured airship: a round envelope, short engine stubs, a cross of tail fins
	"zephyr": {"name": "Zephyr", "title": "Zephyr war airship", "hull": "round", "wings": "stubs", "fins": "cross",
		"paint": "ivory", "accent": Color8(0x4c, 0xe0, 0xa8), "drones": 7.0, "sections": [
		{"name": "GONDOLA GUNS", "piece": "collar", "mounts": [Vector2(-4.0, 3.4), Vector2(4.0, 3.4), Vector2(-4.0, 8.6),
			Vector2(4.0, 8.6)]},
		{"name": "ENVELOPE GUNS", "piece": "plating", "mounts": [Vector2(-3.4, 10.6), Vector2(3.4, 10.6), Vector2(0.0, 12.0)]},
		{"name": "TOP TURRETS", "piece": "tower", "mounts": [Vector2(-2.4, 15.0), Vector2(2.4, 15.0), Vector2(0.0, 18.0)]},
		{"name": "REACTOR", "piece": "", "mounts": []},
	]},
	# a jet bomber: a peaked hull, swept wings with jet engines, one tall gun fin
	"talon": {"name": "Talon", "title": "Talon jet fortress", "hull": "hex", "wings": "jets", "fins": "none",
		"paint": "iron", "accent": Color8(0xff, 0x58, 0x40), "drones": 5.5, "sections": [
		{"name": "TAIL GUNS", "piece": "plating", "mounts": [Vector2(-4.0, 3.4), Vector2(4.0, 3.4), Vector2(-3.6, 10.2),
			Vector2(3.6, 10.2)]},
		{"name": "GUN FIN", "piece": "fin", "mounts": [Vector2(-1.4, 15.0), Vector2(1.4, 15.0), Vector2(-1.4, 18.6),
			Vector2(1.4, 18.6)]},
		{"name": "REACTOR", "piece": "", "mounts": []},
	]},
	# the biggest: four engines a wing, guns round its bay, on its stern and up its tower
	"leviathan": {"name": "Leviathan", "title": "Leviathan super-fortress", "hull": "box", "wings": "props4", "fins": "twin",
		"paint": "olive", "accent": Color8(0xff, 0xd8, 0x40), "drones": 6.0, "sections": [
		{"name": "BAY GUNS", "piece": "collar", "mounts": [Vector2(-4.2, 3.4), Vector2(4.2, 3.4), Vector2(-4.2, 6.0),
			Vector2(4.2, 6.0), Vector2(-4.2, 8.6), Vector2(4.2, 8.6)]},
		{"name": "TAIL GUNS", "piece": "plating", "mounts": [Vector2(-3.0, 10.6), Vector2(3.0, 10.6), Vector2(0.0, 11.8)]},
		{"name": "GUN TOWER", "piece": "tower", "mounts": [Vector2(-3.0, 14.5), Vector2(3.0, 14.5), Vector2(0.0, 16.0),
			Vector2(-1.8, 19.5), Vector2(1.8, 19.5)]},
		{"name": "REACTOR", "piece": "", "mounts": []},
	]},
	# a three-jet raider with a peaked hull and a crown of guns on its tower
	"wyvern": {"name": "Wyvern", "title": "Wyvern heavy raider", "hull": "hex", "wings": "jets3", "fins": "twin",
		"paint": "cobalt", "accent": Color8(0xb4, 0x80, 0xff), "drones": 5.0, "sections": [
		{"name": "TAIL GUNS", "piece": "plating", "mounts": [Vector2(-4.0, 4.4), Vector2(4.0, 4.4), Vector2(-2.6, 10.6),
			Vector2(2.6, 10.6), Vector2(0.0, 11.8)]},
		{"name": "CROWN", "piece": "tower", "mounts": [Vector2(-3.4, 14.6), Vector2(3.4, 14.6), Vector2(-1.2, 17.4),
			Vector2(1.2, 17.4), Vector2(0.0, 19.6)]},
		{"name": "REACTOR", "piece": "", "mounts": []},
	]},
}
## The hand-made sector's fortress (kept for the tests and tools that look at it).
const FORTRESS_SECTIONS: Array = FORTRESSES.goliath.sections


static func fortress_parts(id := "goliath") -> int:
	var n := 0
	for sec: Dictionary in FORTRESSES[id].sections:
		n += 5 if sec.mounts.is_empty() else sec.mounts.size()
	return n


## The chase (third person, outside): how far the ship may move from the centre line
## (x either side, wide enough to fly past the fortress's flanks at its chase scale; y up; `POV_DOWN` down; the fortress is tall, so the ship climbs high), metres per pixel of drag, the on-rails speed, the distance
## to the fortress's stern while chasing and while fighting its reactor, the swoop's length,
## where the guns converge and how far the aim assist reaches.
const POV_REACH := Vector2(11.0, 36.0)
const POV_DOWN := 2.5
## The share of the screen's width (and height) one swipe needs to cross the whole reach.
const POV_SWIPE := 0.7
const RAIL := 18.0
## Lifting the finger slows time to a stop over `SLOW_STOP` s (a pause; Guillaume wanted it gradual, so
## about 2 s with an ease); touching again brings it back up to full speed over `SLOW_RESUME` s.
const SLOW_STOP := 2.0
const SLOW_RESUME := 0.25
const GAP_FAR := 24.0
const GAP_NEAR := 16.0
## In the chase the fortress grows (during the swoop) to `FORTRESS_SCALE` times its size, its
## hangar `FORTRESS_LIFT` above the flight altitude; `GAP_FAR` behind it the stern, inner wings and
## engines fill the view (Guillaume wanted to see more of the ship) and the wing tips run off it.
const FORTRESS_SCALE := 1.3
const FORTRESS_LIFT := 6.0
## Before the swoop, seen from above, it cruises this far above where it sits in the chase's
## frame, so it flies clear of the land (its bay above the flight altitude).
const FORTRESS_CRUISE := 3.0
## Its propellers' spin (radians a second).
const PROP_SPIN := 16.0
const APPROACH := 2.6
const AIM_AHEAD := 32.0
## The fortress going down after its reactor: how long, how fast it falls (m/s per second), and
## when its left wing snaps off.
const CRASH_TIME := 5.0
const CRASH_FALL := 2.2
const WING_SNAP := 1.2
const AIM_ASSIST := 3.0

# ---------------------------------------------------------------- upgrades
const ORDER := ["cannon", "missile", "hull", "magnet"]
const UPGRADES := {
	"cannon": {"name": "Cannon", "max": 5, "cost": [120, 320, 700, 1300, 2400],
		"desc": "More guns, wider spread, harder hits"},
	"missile": {"name": "Missiles", "max": 4, "cost": [250, 600, 1200, 2200],
		"desc": "Homing missiles, faster salvos"},
	"hull": {"name": "Hull", "max": 3, "cost": [200, 550, 1100],
		"desc": "One more hit before going down"},
	"magnet": {"name": "Magnet", "max": 3, "cost": [100, 280, 600],
		"desc": "Pulls scrap from further away"},
}


static func fresh() -> Dictionary:
	var s := {"scrap": 0, "best": 0, "runs": 0, "clears": 0,
		"up": {"cannon": 0, "missile": 0, "hull": 0, "magnet": 0}}
	Campaign.fresh_into(s)
	return s


## Any saved dictionary (or garbage) back to a valid save.
static func migrate(d: Variant) -> Dictionary:
	var s := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return s
	for k in ["scrap", "best", "runs", "clears"]:
		if d.has(k):
			s[k] = maxi(0, int(d[k]))
	if typeof(d.get("up")) == TYPE_DICTIONARY:
		for k: String in ORDER:
			s.up[k] = clampi(int(d.up.get(k, 0)), 0, UPGRADES[k].max)
	Campaign.migrate_into(s, d)
	return s


static func level(s: Dictionary, key: String) -> int:
	return int(s.up.get(key, 0))


## Price of the next level, or -1 once the upgrade is maxed.
static func cost(s: Dictionary, key: String) -> int:
	var lv := level(s, key)
	var u: Dictionary = UPGRADES[key]
	return -1 if lv >= u.max else int(u.cost[lv])


static func can_buy(s: Dictionary, key: String) -> bool:
	var c := cost(s, key)
	return c >= 0 and s.scrap >= c


static func buy(s: Dictionary, key: String) -> bool:
	if not can_buy(s, key):
		return false
	s.scrap -= cost(s, key)
	s.up[key] += 1
	return true


static func max_hp(s: Dictionary) -> int:
	return 3 + level(s, "hull")


static func magnet_radius(s: Dictionary) -> float:
	return 2.5 + 2.0 * level(s, "magnet")


## The main gun at a cannon level: shots as [x offset, angle in degrees], damage per shot and
## the time between volleys. Used by both the vertical stage and the chase.
static func cannon(lv: int) -> Dictionary:
	var shots: Array = [[-0.22, 0.0], [0.22, 0.0]]
	if lv >= 1:
		shots = [[-0.32, 0.0], [0.0, 0.0], [0.32, 0.0]]
	if lv >= 2:
		shots += [[-0.4, -7.0], [0.4, 7.0]]
	if lv >= 4:
		shots += [[-0.5, -15.0], [0.5, 15.0]]
	var dmg: float = [1.0, 1.0, 1.0, 1.35, 1.35, 1.7][clampi(lv, 0, 5)]
	return {"shots": shots, "dmg": dmg, "period": 0.09 if lv >= 5 else 0.11}


## Seconds between missile salvos (0: no missiles) and missiles per salvo.
static func missile_period(lv: int) -> float:
	return [0.0, 1.5, 1.15, 0.9, 0.65][clampi(lv, 0, 4)]


static func missile_count(lv: int) -> int:
	return 2 if lv >= 3 else 1


const MISSILE_DMG := 4.0

# ---------------------------------------------------------------- foes
## hp, hit radius, score and scrap of each kind of foe.
const FOES := {
	"dart": {"hp": 3.0, "r": 0.8, "score": 100, "scrap": 5},
	"swing": {"hp": 4.0, "r": 0.85, "score": 120, "scrap": 5},
	"turret": {"hp": 9.0, "r": 0.9, "score": 200, "scrap": 15},
	"heavy": {"hp": 45.0, "r": 1.6, "score": 800, "scrap": 60},
	"boss": {"hp": 1.0, "r": 0.0, "score": 0, "scrap": 0},
	"cannon": {"hp": 70.0, "r": 1.7, "score": 800, "scrap": 30},
	"flak": {"hp": 45.0, "r": 1.45, "score": 500, "scrap": 20},
	"battery": {"hp": 55.0, "r": 1.55, "score": 600, "scrap": 25},
	"bridge": {"hp": 260.0, "r": 2.7, "score": 6000, "scrap": 300},
	"lance": {"hp": 50.0, "r": 1.5, "score": 600, "scrap": 25},
	"spiral": {"hp": 60.0, "r": 1.6, "score": 700, "scrap": 30},
	"dome": {"hp": 280.0, "r": 2.8, "score": 6000, "scrap": 300},
	"drone": {"hp": 4.0, "r": 0.9, "score": 150, "scrap": 10},
	"sentry": {"hp": 16.0, "r": 1.4, "score": 400, "scrap": 25},
	"orb": {"hp": 1.0, "r": 0.35, "score": 10, "scrap": 0},
	"panel": {"hp": 14.0, "r": 1.5, "score": 300, "scrap": 20},
	"core": {"hp": 45.0, "r": 2.3, "score": 3000, "scrap": 200},
	# landmarks on the coast (Models.marks): they don't fire, and don't count as kills
	"lighthouse": {"hp": 70.0, "r": 2.0, "score": 500, "scrap": 25},
	"house": {"hp": 30.0, "r": 2.2, "score": 150, "scrap": 10},
	"boat": {"hp": 18.0, "r": 1.9, "score": 100, "scrap": 5},
	"pyramid": {"hp": 120.0, "r": 3.0, "score": 1200, "scrap": 40},
	"duck": {"hp": 20.0, "r": 1.9, "score": 300, "scrap": 10},
	"water tower": {"hp": 45.0, "r": 1.8, "score": 400, "scrap": 15},
	"snowman": {"hp": 40.0, "r": 1.8, "score": 400, "scrap": 15},
	"stone head": {"hp": 80.0, "r": 1.9, "score": 700, "scrap": 25},
}
## Scenery that can be shot down (see FOES).
## How far inside the top of the screen a landmark must be before shots hurt it.
const LANDMARK_IN := 4.0
const LANDMARKS := ["lighthouse", "house", "boat", "pyramid", "duck", "water tower", "snowman", "stone head"]

## The vertical stage, Sector 1 (Glass Coast): waves by stage time (seconds of vertical play).
## The mid-boss (the Bastion, top-down) holds the clock until it's down; the final boss is the
## fortress, chased in third person, and ends the sector. `x` is where the wave enters, `n` how many
## foes, `gap` the seconds between them.
## Waves enter from off-screen: "from" is the edge (top by default; darts can also sweep in
## from the left or right, x then shifting their row, or overtake from the back up the lane x).
const STAGE := [
	{"t": 1.5, "kind": "dart", "n": 5, "x": -3.0, "gap": 0.35},
	{"t": 4.0, "kind": "dart", "n": 5, "x": 0.0, "gap": 0.35, "from": "right"},
	{"t": 7.0, "kind": "swing", "n": 6, "x": -1.0, "gap": 0.4},
	{"t": 9.0, "kind": "turret", "n": 2, "x": -3.5, "gap": 0.0},
	{"t": 10.0, "kind": "turret", "n": 1, "x": 3.8, "gap": 0.0},
	{"t": 12.5, "kind": "dart", "n": 6, "x": -5.5, "gap": 0.3, "from": "back"},
	{"t": 15.0, "kind": "heavy", "n": 1, "x": 0.0, "gap": 0.0},
	# mid-boss: the clock waits until it's down
	{"t": 19.0, "kind": "boss", "n": 1, "x": 0.0, "gap": 0.0},
	{"t": 21.5, "kind": "swing", "n": 6, "x": 2.0, "gap": 0.35},
	{"t": 23.0, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 25.0, "kind": "heavy", "n": 1, "x": -2.5, "gap": 0.0},
	{"t": 27.5, "kind": "dart", "n": 8, "x": 0.0, "gap": 0.25, "from": "left"},
	{"t": 29.5, "kind": "dart", "n": 8, "x": 2.0, "gap": 0.25, "from": "right"},
	{"t": 32.0, "kind": "swing", "n": 6, "x": -2.0, "gap": 0.35},
	{"t": 33.5, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 35.5, "kind": "dart", "n": 6, "x": 4.5, "gap": 0.3, "from": "back"},
	{"t": 36.0, "kind": "swing", "n": 6, "x": 2.5, "gap": 0.35},
	# final boss: the fortress chase ends the sector
	{"t": 40.0, "kind": "fortress", "n": 1, "x": 0.0, "gap": 0.0},
]



## The mid-bosses, each bigger than the screen and taken apart section by section: each
## section's parts (kind, position on the hull: x, y, z towards its bow) must all go down before
## the next section opens, and its `piece` (a separate mesh, `Models.midboss_piece`) breaks off.
## The last section is the boss's heart (a `bridge` or a `dome`), shielded until then. Nose to +z.
## Every part stays within the play field's width (|x| <= 7) and z -5..8, so it is in reach and
## on screen. `move` is how the hull flies (`Game.think_boss`). Each level has its own
## (`Campaign.midboss_of`).
const MIDBOSSES := {
	"bastion": {"name": "Bastion", "title": "Bastion-class battleship", "move": "sway", "sections": [
		{"name": "BOW GUNS", "piece": "bow", "parts": [
			{"kind": "cannon", "at": Vector3(-1.6, 1.4, 6.5)}, {"kind": "cannon", "at": Vector3(1.6, 1.4, 6.5)},
			{"kind": "flak", "at": Vector3(-3.0, 1.0, 3.0)}, {"kind": "flak", "at": Vector3(3.0, 1.0, 3.0)}]},
		{"name": "WING BATTERIES", "piece": "wings", "parts": [
			{"kind": "battery", "at": Vector3(-5.4, 0.8, 0.2)}, {"kind": "battery", "at": Vector3(5.4, 0.8, 0.2)},
			{"kind": "battery", "at": Vector3(-7.0, 0.8, -1.8)}, {"kind": "battery", "at": Vector3(7.0, 0.8, -1.8)}]},
		{"name": "BRIDGE", "piece": "", "parts": [{"kind": "bridge", "at": Vector3(0.0, 1.8, -3.6)}]},
	]},
	# a long gunship reaching for the player with two armoured claws
	"mantis": {"name": "Mantis", "title": "Mantis-class gunship", "move": "strafe", "sections": [
		{"name": "CLAWS", "piece": "claws", "parts": [
			{"kind": "lance", "at": Vector3(-5.0, 1.1, 7.6)}, {"kind": "lance", "at": Vector3(5.0, 1.1, 7.6)},
			{"kind": "flak", "at": Vector3(-4.4, 1.0, 2.6)}, {"kind": "flak", "at": Vector3(4.4, 1.0, 2.6)}]},
		{"name": "ENGINE PODS", "piece": "pods", "parts": [
			{"kind": "spiral", "at": Vector3(-6.2, 1.0, -2.2)}, {"kind": "spiral", "at": Vector3(6.2, 1.0, -2.2)},
			{"kind": "cannon", "at": Vector3(0.0, 1.5, 4.6)}]},
		{"name": "EYE", "piece": "", "parts": [{"kind": "dome", "at": Vector3(0.0, 1.6, -1.2)}]},
	]},
	# a round platform that turns slowly, guns all round its rim
	"halo": {"name": "Halo", "title": "Halo-class sky platform", "move": "spin", "sections": [
		{"name": "RIM GUNS", "piece": "rim", "parts": [
			{"kind": "cannon", "at": Vector3(2.7, 1.2, 4.68)}, {"kind": "flak", "at": Vector3(5.4, 1.0, 0.0)},
			{"kind": "cannon", "at": Vector3(2.7, 1.2, -4.68)}, {"kind": "flak", "at": Vector3(-2.7, 1.0, -4.68)},
			{"kind": "cannon", "at": Vector3(-5.4, 1.2, 0.0)}, {"kind": "flak", "at": Vector3(-2.7, 1.0, 4.68)}]},
		{"name": "SPOKES", "piece": "spokes", "parts": [
			{"kind": "battery", "at": Vector3(0.0, 1.3, 3.2)}, {"kind": "battery", "at": Vector3(2.77, 1.3, -1.6)},
			{"kind": "battery", "at": Vector3(-2.77, 1.3, -1.6)}]},
		{"name": "CORE", "piece": "", "parts": [{"kind": "dome", "at": Vector3(0.0, 2.0, 0.0)}]},
	]},
	# two long hulls on a shared deck: each hull is a section
	"twin": {"name": "Corsair", "title": "Corsair twin-hull cruiser", "move": "weave", "sections": [
		{"name": "PORT HULL", "piece": "port", "parts": [
			{"kind": "cannon", "at": Vector3(-4.6, 1.4, 5.4)}, {"kind": "lance", "at": Vector3(-4.6, 1.2, 1.2)},
			{"kind": "flak", "at": Vector3(-4.6, 1.0, -2.8)}]},
		{"name": "STARBOARD HULL", "piece": "starboard", "parts": [
			{"kind": "cannon", "at": Vector3(4.6, 1.4, 5.4)}, {"kind": "lance", "at": Vector3(4.6, 1.2, 1.2)},
			{"kind": "flak", "at": Vector3(4.6, 1.0, -2.8)}]},
		{"name": "DECK", "piece": "deck", "parts": [
			{"kind": "spiral", "at": Vector3(0.0, 1.2, 3.0)}]},
		{"name": "BRIDGE", "piece": "", "parts": [{"kind": "bridge", "at": Vector3(0.0, 1.8, -2.4)}]},
	]},
	# a T-shaped dreadnought: a wide gun bar at its bow, and it lunges at the player
	"hammer": {"name": "Hammerhead", "title": "Hammerhead dreadnought", "move": "charge", "sections": [
		{"name": "HAMMER", "piece": "hammer", "parts": [
			{"kind": "cannon", "at": Vector3(-2.6, 1.4, 7.0)}, {"kind": "cannon", "at": Vector3(2.6, 1.4, 7.0)},
			{"kind": "battery", "at": Vector3(-6.2, 0.9, 6.2)}, {"kind": "battery", "at": Vector3(6.2, 0.9, 6.2)}]},
		{"name": "FINS", "piece": "fins", "parts": [
			{"kind": "lance", "at": Vector3(-4.8, 1.0, -0.6)}, {"kind": "lance", "at": Vector3(4.8, 1.0, -0.6)},
			{"kind": "spiral", "at": Vector3(0.0, 1.4, 2.2)}]},
		{"name": "HEART", "piece": "", "parts": [{"kind": "dome", "at": Vector3(0.0, 1.8, -3.0)}]},
	]},
}
## The parts that make up a mid-boss (Game.think_part fires their patterns), and its hearts.
const BOSS_PART_KINDS := ["cannon", "flak", "battery", "lance", "spiral", "bridge", "dome"]
const BOSS_HEARTS := ["bridge", "dome"]
## The hand-made sector's mid-boss (kept for the tests and tools that look at it).
const BOSS_SECTIONS: Array = MIDBOSSES.bastion.sections
## How far down the screen (relative z of the boss's centre) the boss sits, and how much
## closer it pushes after each section is destroyed.
const BOSS_Z := Z_TOP + 8.0
const BOSS_PUSH := 2.2


static func boss_parts(id := "bastion") -> int:
	var n := 0
	for sec: Dictionary in MIDBOSSES[id].sections:
		n += sec.parts.size()
	return n


## Grade of a run from kill rate and hits taken.
static func grade(kills: int, total: int, hits: int, cleared: bool) -> String:
	if not cleared:
		return "-"
	var rate := minf(1.0, float(kills) / maxf(1.0, float(total)))
	if rate >= 0.9 and hits == 0:
		return "S"
	if rate >= 0.75 and hits <= 1:
		return "A"
	if rate >= 0.5:
		return "B"
	return "C"


static func save_game(s: Dictionary, path := SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))


static func load_game(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fresh()
	var f := FileAccess.open(path, FileAccess.READ)
	return migrate(JSON.parse_string(f.get_as_text()) if f else null)


static func fmt(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out
