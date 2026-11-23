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
## touched within RAM_R of their radius. Ground targets, scenery and the fortress (flown over, clear
## of the ship) can't be rammed; the Bastion's hull is a wall (Game.boss_rammed).
const RAMMABLE := ["dart", "swing", "heavy", "drone", "gull", "rotor", "scarab", "seeker", "gunship", "lancer", "prism",
	"ember", "wyrm"]
const RAM_KILLS := ["dart", "swing", "drone", "gull", "rotor", "scarab", "seeker", "lancer", "wyrm"]
const RAM_DMG := 12.0
const RAM_R := 0.7
const KNOCK := 9.0
const KNOCK_EASE := 30.0
const PICK_R := 1.0

# ---------------------------------------------------------------- the fortress (POV episode)
## The final boss (Guillaume, 2026-11-23: "a huge fortress class ship, you clear it section by
## section as you advance along the ship"): a capital ship far wider than the screen and some
## 200 m long. The chase comes in behind its stern and flies forward over its deck; each section
## is a stretch of hull with its own guns, and once they're down the ship glides on to the next
## (`ADVANCE` s), from the engines at the stern to the bridge and its reactor at the bow. There is
## no tunnel: everything is out in the open sky.
##
## Model frame: the stern at z = 0, the bow at z = -`fortress_len`, the deck at y = 0 (the hull
## below it, `HULL_DEPTH` deep), x across. In the chase the deck flies `CHASE_DECK` above the ground,
## at scale 1; seen from above before the swoop it is `TOP_SCALE` of that, its deck `TOP_DECK`.
const CHASE_DECK := 27.0
const HULL_DEPTH := 14.0
const TOP_SCALE := 0.3
const TOP_DECK := 7.5
## Its deck's half width (the hull flares a little past it below), much wider than the chase's
## reach: its edges run off the screen, and every gun stands within |x| <= `GUN_X` (tested).
const FORTRESS_HW := 21.0
const GUN_X := 10.0
## Past the last section, the bow's taper.
const BOW_LEN := 34.0
## Where the ship sits at each section: the guns start `LEAD` ahead of the ship (`at` of the
## section, from the stern), and the ship flies `fly` above the deck (the engines' nozzles are on
## the stern's face, so that section is flown lower, behind the stern).
const LEAD := 12.0
const FLY := 7.5
const ADVANCE := 2.6
## The guns a ship can carry (each its own look in `Models.ship_gun` and its pattern in
## `Game.think_gun`): `nozzle` (an engine's exhaust, on the stern's face, rings of fire), `twin`
## (a twin-barrel turret, aimed bursts), `quad` (flak, wide fans), `pod` (a missile box: rockets
## that home in and can be shot), `mast` (a lance mast: quick streams), `dish` (a radar dish: a
## turning spiral), `pylon` (a shield pylon: the rest of its section is shielded until it falls)
## and `hatch` (a hangar hatch that launches drones).
const SHIP_GUNS := ["nozzle", "twin", "quad", "pod", "mast", "dish", "pylon", "hatch"]
## Each gun's centre above the deck (its hit point), for guns standing on the deck.
const GUN_H := {"twin": 1.7, "quad": 1.6, "pod": 2.0, "mast": 6.5, "dish": 3.0, "pylon": 3.4, "hatch": 0.7, "nozzle": 0.0}
## The ships. Each section: `name`, `kind` (its look: engines, hangar, guns, missiles, lances,
## bridge; the last is the reactor, `core`), `len` (m of hull) and its `guns`: [kind, x, dz] on the
## deck `dz` ahead of the section's start, or [kind, x, y, dz] where the gun sits higher (a nozzle
## low on the stern, a gun up the bridge). Clearing a section breaks off its `piece` of
## superstructure (`Models.ship_piece`). Each ship also has its hull's look (`hull`: slab, wedge,
## round), paint, accent and drone rate (s). Each level has its own (`Campaign.fortress_of`).
const FORTRESSES := {
	"goliath": {"name": "Goliath", "title": "Goliath-class dreadnought", "hull": "slab",
		"paint": "steel", "accent": Color8(0xff, 0xa8, 0x2e), "drones": 7.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "len": 44.0, "guns": [["nozzle", -7.5, -6.5, 0.0], ["nozzle", -2.5, -6.5, 0.0],
			["nozzle", 2.5, -6.5, 0.0], ["nozzle", 7.5, -6.5, 0.0], ["twin", -6.0, 8.0], ["twin", 6.0, 8.0]]},
		{"name": "HANGAR DECK", "kind": "hangar", "len": 46.0, "guns": [["hatch", -4.5, 10.0], ["hatch", 4.5, 10.0],
			["twin", -8.0, 22.0], ["twin", 8.0, 22.0], ["quad", 0.0, 26.0]]},
		{"name": "GUN DECK", "kind": "guns", "len": 44.0, "guns": [["pylon", 0.0, 22.0], ["twin", -7.0, 10.0],
			["twin", 7.0, 10.0], ["quad", -4.0, 24.0], ["quad", 4.0, 24.0], ["twin", 0.0, 8.0]]},
		{"name": "BRIDGE", "kind": "bridge", "len": 46.0, "guns": [["dish", 0.0, 11.0, 23.0], ["mast", -6.5, 10.5, 13.0],
			["mast", 6.5, 10.5, 13.0], ["twin", -3.0, 5.7, 11.0], ["twin", 3.0, 5.7, 11.0]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a sky carrier: a round-bellied hull, two hangar decks and drones in swarms
	"zephyr": {"name": "Zephyr", "title": "Zephyr sky carrier", "hull": "round",
		"paint": "ivory", "accent": Color8(0x4c, 0xe0, 0xa8), "drones": 5.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "len": 40.0, "guns": [["nozzle", -6.0, -6.0, 0.0], ["nozzle", 0.0, -6.0, 0.0],
			["nozzle", 6.0, -6.0, 0.0], ["quad", -7.0, 9.0], ["quad", 7.0, 9.0]]},
		{"name": "FLIGHT DECK", "kind": "hangar", "len": 44.0, "guns": [["hatch", -5.0, 8.0], ["hatch", 5.0, 8.0],
			["hatch", 0.0, 20.0], ["twin", -8.0, 24.0], ["twin", 8.0, 24.0]]},
		{"name": "AFT HANGARS", "kind": "hangar", "len": 44.0, "guns": [["pylon", 0.0, 22.0], ["hatch", -5.0, 8.0],
			["hatch", 5.0, 8.0], ["quad", -8.0, 20.0], ["quad", 8.0, 20.0]]},
		{"name": "BRIDGE", "kind": "bridge", "len": 44.0, "guns": [["dish", 0.0, 11.0, 23.0], ["twin", -6.5, 5.7, 12.0],
			["twin", 6.5, 5.7, 12.0], ["quad", 0.0, 5.6, 10.0]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a missile cruiser: a sharp wedge of a hull, missile banks and a lance array
	"talon": {"name": "Talon", "title": "Talon missile cruiser", "hull": "wedge",
		"paint": "iron", "accent": Color8(0xff, 0x58, 0x40), "drones": 7.5, "sections": [
		{"name": "ENGINES", "kind": "engines", "len": 38.0, "guns": [["nozzle", -5.0, -6.0, 0.0], ["nozzle", 5.0, -6.0, 0.0],
			["pod", -6.5, 9.0], ["pod", 6.5, 9.0]]},
		{"name": "MISSILE BANKS", "kind": "missiles", "len": 46.0, "guns": [["pylon", 0.0, 24.0], ["pod", -7.0, 8.0],
			["pod", 7.0, 8.0], ["pod", -4.0, 20.0], ["pod", 4.0, 20.0]]},
		{"name": "LANCE ARRAY", "kind": "lances", "len": 42.0, "guns": [["mast", -6.0, 12.0], ["mast", 0.0, 16.0],
			["mast", 6.0, 12.0], ["twin", -3.5, 6.0], ["twin", 3.5, 6.0]]},
		{"name": "BRIDGE", "kind": "bridge", "len": 44.0, "guns": [["dish", 0.0, 11.0, 23.0], ["pod", -6.0, 6.0, 12.0],
			["pod", 6.0, 6.0, 12.0], ["mast", 0.0, 10.5, 10.0]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# the biggest: six engines, a hangar, a gun deck, missile banks and the bridge
	"leviathan": {"name": "Leviathan", "title": "Leviathan super-dreadnought", "hull": "slab",
		"paint": "olive", "accent": Color8(0xff, 0xd8, 0x40), "drones": 6.5, "sections": [
		{"name": "ENGINES", "kind": "engines", "len": 44.0, "guns": [["nozzle", -8.0, -5.0, 0.0], ["nozzle", -4.0, -8.0, 0.0],
			["nozzle", 0.0, -5.0, 0.0], ["nozzle", 4.0, -8.0, 0.0], ["nozzle", 8.0, -5.0, 0.0], ["twin", 0.0, 9.0]]},
		{"name": "HANGAR DECK", "kind": "hangar", "len": 44.0, "guns": [["hatch", -5.0, 10.0], ["hatch", 5.0, 10.0],
			["quad", -8.0, 22.0], ["quad", 8.0, 22.0]]},
		{"name": "GUN DECK", "kind": "guns", "len": 44.0, "guns": [["twin", -7.0, 8.0], ["twin", 7.0, 8.0],
			["twin", 0.0, 14.0], ["quad", -5.0, 24.0], ["quad", 5.0, 24.0]]},
		{"name": "MISSILE BANKS", "kind": "missiles", "len": 42.0, "guns": [["pylon", 0.0, 22.0], ["pod", -7.0, 8.0],
			["pod", 7.0, 8.0], ["mast", -4.0, 18.0], ["mast", 4.0, 18.0]]},
		{"name": "BRIDGE", "kind": "bridge", "len": 46.0, "guns": [["dish", 0.0, 11.0, 23.0], ["mast", -6.5, 10.5, 13.0],
			["mast", 6.5, 10.5, 13.0], ["twin", -3.0, 5.7, 11.0], ["twin", 3.0, 5.7, 11.0]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a fast raider: a wedge hull, flak and lances, three engines
	"wyvern": {"name": "Wyvern", "title": "Wyvern battle raider", "hull": "wedge",
		"paint": "cobalt", "accent": Color8(0xb4, 0x80, 0xff), "drones": 6.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "len": 38.0, "guns": [["nozzle", -6.0, -5.5, 0.0], ["nozzle", 0.0, -7.5, 0.0],
			["nozzle", 6.0, -5.5, 0.0], ["mast", -6.0, 10.0], ["mast", 6.0, 10.0]]},
		{"name": "FLAK DECK", "kind": "guns", "len": 44.0, "guns": [["quad", -6.0, 8.0], ["quad", 6.0, 8.0],
			["quad", 0.0, 16.0], ["twin", -7.5, 22.0], ["twin", 7.5, 22.0]]},
		{"name": "LANCE ARRAY", "kind": "lances", "len": 42.0, "guns": [["pylon", 0.0, 22.0], ["mast", -6.0, 10.0],
			["mast", 0.0, 12.0], ["mast", 6.0, 10.0]]},
		{"name": "BRIDGE", "kind": "bridge", "len": 44.0, "guns": [["dish", -3.5, 11.0, 23.0], ["dish", 3.5, 11.0, 23.0],
			["twin", -6.0, 5.7, 12.0], ["twin", 6.0, 5.7, 12.0]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
}
## The hand-made sector's fortress (kept for the tests and tools that look at it).
const FORTRESS_SECTIONS: Array = FORTRESSES.goliath.sections


static func fortress_parts(id := "goliath") -> int:
	var n := 0
	for sec: Dictionary in FORTRESSES[id].sections:
		n += 5 if sec.kind == "core" else sec.guns.size()
	return n


## Where each section starts, from the stern (m), and the ship's whole length.
static func section_at(id: String, i: int) -> float:
	var z := 0.0
	var secs: Array = FORTRESSES[id].sections
	for k in mini(i, secs.size()):
		z += float(secs[k].len)
	return z


static func fortress_len(id: String) -> float:
	return section_at(id, 99) + BOW_LEN


## A gun's place on the ship's model: x, height and z (the stern at 0, the bow towards -z).
static func gun_at(id: String, i: int, g: Array) -> Vector3:
	var at := section_at(id, i)
	if g.size() >= 4:
		return Vector3(float(g[1]), float(g[2]), -(at + float(g[3])))
	return Vector3(float(g[1]), float(GUN_H[g[0]]), -(at + float(g[2])))


## Where the ship flies while fighting section i: [distance ahead of the stern (negative: behind
## it), height above the deck]. The engines are fought from behind the stern, level with them.
static func station(id: String, i: int) -> Vector2:
	var secs: Array = FORTRESSES[id].sections
	i = mini(i, secs.size() - 1)
	if secs[i].kind == "core":
		i -= 1
	var fly := FLY
	if secs[i].kind == "engines":
		fly = -0.5
	return Vector2(section_at(id, i) - LEAD - (10.0 if secs[i].kind == "engines" else 0.0), fly)


## The chase (third person, outside): how far the ship may move from its line (x either side, y up;
## `POV_DOWN` down), the on-rails speed, the swoop's length, where the guns converge (a little
## below straight ahead, `AIM_DIP`, since most guns stand on the deck below) and how far the aim
## assist reaches.
const POV_REACH := Vector2(11.0, 13.0)
const POV_DOWN := 3.5
## The share of the screen's width (and height) one swipe needs to cross the whole reach.
const POV_SWIPE := 0.7
const RAIL := 18.0
## Lifting the finger slows time to a stop over `SLOW_STOP` s (a pause; Guillaume wanted it gradual, so
## about 2 s with an ease); touching again brings it back up to full speed over `SLOW_RESUME` s.
const SLOW_STOP := 2.0
const SLOW_RESUME := 0.25
const APPROACH := 2.8
const AIM_AHEAD := 32.0
const AIM_DIP := 0.12
const AIM_ASSIST := 3.4
## The ship's end (Guillaume, 2026-11-23: "die in the air and drift out of screen, not into the
## ground"): the reactor blows, a chain of blasts runs aft along the spine, and the hull breaks
## apart at its section seams, bow first. The pieces burn, spread apart, turn a little and sink a
## few metres while the wreck loses way and drifts back under and behind the ship, off the screen.
## Nothing reaches the ground. `BREAKUP_TIME` s in all.
const BREAKUP_TIME := 6.5
## Each seam parts `SEAM_GAP` s after the one ahead of it.
const SEAM_GAP := 0.4
## The wreck's slowing (m/s per s per s: it drifts back by DRIFT * t^3 / 3) and its pieces' sink.
const DRIFT := 2.2
const SINK := 1.1
## Meanwhile the ship climbs away from the blast, so the pieces pass beneath it.
const CLIMB := 16.0

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
	# more gun towers (`Towers`), dressed for each world
	"rocket": {"hp": 11.0, "r": 1.0, "score": 250, "scrap": 15},
	"howitzer": {"hp": 16.0, "r": 1.1, "score": 350, "scrap": 20},
	"pulse": {"hp": 12.0, "r": 1.0, "score": 300, "scrap": 18},
	"heavy": {"hp": 45.0, "r": 1.6, "score": 800, "scrap": 60},
	# the campaign's own foes, one new kind a level (`Foes.INTRO`)
	"gull": {"hp": 3.0, "r": 0.95, "score": 120, "scrap": 6},
	"rotor": {"hp": 7.0, "r": 1.0, "score": 220, "scrap": 10},
	"pillbox": {"hp": 14.0, "r": 1.15, "score": 300, "scrap": 15},
	"scarab": {"hp": 7.0, "r": 1.0, "score": 250, "scrap": 12},
	"tank": {"hp": 18.0, "r": 1.3, "score": 400, "scrap": 20},
	"borer": {"hp": 16.0, "r": 1.1, "score": 450, "scrap": 20},
	"seeker": {"hp": 2.0, "r": 0.75, "score": 80, "scrap": 4},
	"aa": {"hp": 15.0, "r": 1.15, "score": 350, "scrap": 15},
	"gunship": {"hp": 30.0, "r": 1.6, "score": 900, "scrap": 45},
	"lancer": {"hp": 6.0, "r": 0.95, "score": 250, "scrap": 12},
	"hover": {"hp": 14.0, "r": 1.3, "score": 350, "scrap": 18},
	"prism": {"hp": 16.0, "r": 1.15, "score": 500, "scrap": 22},
	"ember": {"hp": 8.0, "r": 1.0, "score": 250, "scrap": 12},
	"mortar": {"hp": 18.0, "r": 1.3, "score": 450, "scrap": 20},
	"wyrm": {"hp": 4.0, "r": 0.8, "score": 120, "scrap": 6},
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
	"nozzle": {"hp": 34.0, "r": 2.4, "score": 500, "scrap": 25},
	"twin": {"hp": 26.0, "r": 1.8, "score": 400, "scrap": 20},
	"quad": {"hp": 28.0, "r": 1.8, "score": 400, "scrap": 20},
	"pod": {"hp": 26.0, "r": 1.8, "score": 450, "scrap": 20},
	"mast": {"hp": 22.0, "r": 1.7, "score": 450, "scrap": 20},
	"dish": {"hp": 34.0, "r": 2.2, "score": 600, "scrap": 30},
	"pylon": {"hp": 20.0, "r": 1.7, "score": 500, "scrap": 25},
	"hatch": {"hp": 30.0, "r": 2.3, "score": 450, "scrap": 20},
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
	# the level's new foe (`Foes.INTRO`): beach pillboxes
	{"t": 5.5, "kind": "pillbox", "n": 2, "x": 2.0, "gap": 0.0},
	{"t": 7.0, "kind": "swing", "n": 6, "x": -1.0, "gap": 0.4},
	{"t": 9.0, "kind": "turret", "n": 2, "x": -3.5, "gap": 0.0},
	{"t": 10.0, "kind": "rocket", "n": 1, "x": 3.8, "gap": 0.0},
	{"t": 12.5, "kind": "dart", "n": 6, "x": -5.5, "gap": 0.3, "from": "back"},
	{"t": 15.0, "kind": "heavy", "n": 1, "x": 0.0, "gap": 0.0},
	# mid-boss: the clock waits until it's down
	{"t": 19.0, "kind": "boss", "n": 1, "x": 0.0, "gap": 0.0},
	{"t": 21.5, "kind": "swing", "n": 6, "x": 2.0, "gap": 0.35},
	{"t": 23.0, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 24.0, "kind": "pillbox", "n": 1, "x": -3.5, "gap": 0.0},
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
