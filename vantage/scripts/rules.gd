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
const RAMMABLE := ["dart", "swing", "heavy", "drone", "rotor", "scarab", "seeker", "gunship", "lancer", "prism",
	"ember", "wyrm"]
const RAM_KILLS := ["dart", "swing", "drone", "rotor", "scarab", "seeker", "lancer", "wyrm"]
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
const BOW_LEN := 26.0
## Where the ship sits at each section: the guns start `LEAD` ahead of the ship (`at` of the
## section, from the stern), and the ship flies `fly` above the deck (the engines' nozzles are on
## the stern's face, so that section is flown lower, behind the stern).
const LEAD := 12.0
const FLY := 7.5
const ADVANCE := 1.8
## The next section's guns join in before their turn, firing this much slower (`Game.live_sec`).
const AHEAD_FIRE := 1.6
## The guns a ship can carry (each its own look in `Models.ship_gun` and its pattern in
## `Game.think_gun`): `nozzle` (an engine's exhaust, on the stern's face, rings of fire), `twin`
## (a twin-barrel turret, aimed bursts), `quad` (flak, wide fans), `pod` (a missile box: rockets
## that home in and can be shot), `mast` (a lance mast: quick streams), `dish` (a radar dish: a
## turning spiral), `pylon` (a shield pylon: the rest of its section is shielded until it falls)
## and `hatch` (a hangar hatch that launches drones).
const SHIP_GUNS := ["nozzle", "twin", "quad", "pod", "mast", "dish", "pylon", "hatch"]
## Each gun's centre above the deck (its hit point), for guns standing on the deck.
const GUN_H := {"twin": 1.7, "quad": 1.6, "pod": 2.0, "mast": 6.5, "dish": 3.0, "pylon": 3.4, "hatch": 0.7, "nozzle": 0.0}
## The ships, one for each level (`Campaign.FORTRESS_ORDER`; Guillaume, 2026-11-24: "I want a
## different boss per level. You can advance over it, on the sides..."). Each has its hull's look
## (`hull`: slab, wedge, round or keel, a plated deck over a hull side; or `bodies`, smooth lofted
## bodies: an airship's envelope and gondola, twin or triple hulls, a flying wing, a string of pods,
## a serpent; see `Capital.body_at`), paint, accent, drone rate (s), `extras` (fins, masts and sails,
## a tusk, crystal spires, legs and a horn, dorsal spines) and its sections from stern to bow.
##
## Each ship is designed first, as one dense object (Guillaume, 2026-11-24: "start by designing a
## fortress, then choose a path that would clear it by sections"), its `len` (m, stern to bow tip)
## about 100-125 m; then the order of its sections is the path that clears it, winding round the
## hull (behind the stern, under it, up a flank, over the top, down the other flank...) so the next
## section is always in sight and in range, never across the hull from the one being fought.
## Each section: `name`, `kind` (its look and the piece that breaks off: engines, hangar, guns,
## missiles, lances, battery, bays, then the heart, bridge or gondola; the last is the reactor,
## `core`), `at` (where its stretch starts, m from the stern: sections overlap, two flanks or a
## deck and a belly can share a stretch), `len` (m of hull), the `route` the ship takes past it (`Capital.lane`: `stern` behind
## it, `top` over it, `left`/`right` along a flank, `under` beneath it, `gap` between two hulls;
## `x`, `y` place the lane where it isn't worked out) and its `guns`, by route:
## - top, stern: [kind, x, dz] on the hull's top `dz` ahead of the section's start (x from the
##   section's track: its `x` and a serpent's wave), or [kind, x, y, dz] where it sits higher
##   (up the bridge) or on the stern's face (a nozzle);
## - left, right: [kind, y, dz] on a sponson on that flank, its hit point at height y;
## - under: [kind, x, dz] hung under the hull;
## - gap: [kind, side, y, dz] on a sponson on the face of the hull to that side (-1, 1) of the lane.
const FORTRESSES := {
	# Glass Coast
	# an airship carrier: a great envelope, a gondola slung under it, engine nacelles on outriggers
	"albatross": {"name": "Albatross", "title": "Albatross airship carrier", "len": 100.0, "paint": "pearl",
		"accent": Color8(0xff, 0x6a, 0x4a), "drones": 6.0, "extras": ["fins"], "bodies": [
		{"y": -13.0, "w": 15.0, "t": 13.0, "b": 13.0, "n": 3.0, "tail": 23.3, "tip": 0.1, "nose": 19.6, "nose_tip": 0.08},
		{"y": -29.5, "w": 6.0, "t": 5.0, "b": 4.5, "n": 2.6, "from": 28.0, "to": 78.5, "tail": 8.4, "tip": 0.25, "nose": 7.5, "nose_tip": 0.3, "role": "keel"},
		{"x": 21.0, "y": -14.0, "w": 3.2, "t": 3.2, "b": 3.2, "n": 2.0, "from": 5.6, "to": 22.4, "tail": 3.2, "tip": 0.4, "nose": 4.2, "nose_tip": 0.3, "role": "pod"},
		{"x": -21.0, "y": -14.0, "w": 3.2, "t": 3.2, "b": 3.2, "n": 2.0, "from": 5.6, "to": 22.4, "tail": 3.2, "tip": 0.4, "nose": 4.2, "nose_tip": 0.3, "role": "pod"},
		{"x": 14.0, "y": -14.0, "w": 8.0, "t": 0.7, "b": 0.7, "n": 2.0, "from": 9.3, "to": 18.7, "tail": 1.9, "tip": 0.5, "nose": 1.9, "nose_tip": 0.5, "role": "wing"},
		{"x": -14.0, "y": -14.0, "w": 8.0, "t": 0.7, "b": 0.7, "n": 2.0, "from": 9.3, "to": 18.7, "tail": 1.9, "tip": 0.5, "nose": 1.9, "nose_tip": 0.5, "role": "wing"},
	], "sections": [
		{"name": "STARBOARD ENGINES", "kind": "battery", "route": "right", "y": -14.0, "at": 0, "len": 31.7, "guns": [["twin", -11.0, 10.0], ["quad", -12.5, 14.5], ["pod", -12.5, 19.0], ["twin", -11.0, 23.5]]},
		{"name": "GONDOLA", "kind": "bays", "route": "under", "at": 16, "len": 31.7, "guns": [["hatch", -3.0, 15.8], ["twin", 3.0, 13.0],
			["twin", -3.0, 21.6], ["quad", 3.0, 20.2], ["twin", 0.0, 23.0]]},
		{"name": "PORT GUNS", "kind": "battery", "route": "left", "y": -13.0, "at": 20, "len": 31.7, "guns": [["twin", -10.0, 7.2],
			["twin", -16.0, 11.5], ["quad", -12.0, 15.8], ["twin", -9.0, 20.2], ["pod", -16.0, 23.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 36, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["quad", 0.0, 5.6, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a catamaran: two long hulls, a low wing between them aft, a bridge deck joining them forward
	"marlin": {"name": "Marlin", "title": "Marlin twin-hull cruiser", "len": 104.0, "paint": "teal",
		"accent": Color8(0xff, 0xd0, 0x4a), "drones": 6.5, "bodies": [
		{"x": -22.0, "y": -7.0, "w": 7.0, "t": 7.0, "b": 9.0, "n": 2.6, "tail": 3.9, "tip": 0.55, "nose": 23.3, "nose_tip": 0.04, "nose_p": 1.4},
		{"x": 22.0, "y": -7.0, "w": 7.0, "t": 7.0, "b": 9.0, "n": 2.6, "tail": 3.9, "tip": 0.55, "nose": 23.3, "nose_tip": 0.04, "nose_p": 1.4},
		{"y": -3.2, "w": 18.0, "t": 3.2, "b": 3.0, "n": 3.0, "from": 59.2, "to": -0.9, "tail": 6.8, "tip": 0.2, "nose": 21.4, "nose_tip": 0.06},
		{"y": -12.5, "w": 20.0, "t": 1.2, "b": 1.4, "n": 2.0, "from": 2.9, "to": 60.2, "tail": 2.9, "tip": 0.6, "nose": 4.9, "nose_tip": 0.4, "role": "wing"},
	], "sections": [
		{"name": "TWIN STERNS", "kind": "battery", "route": "gap", "y": -4.0, "at": 0, "len": 31.7, "guns": [["twin", -1, -3.0, 8.6],
			["twin", 1, -3.0, 8.6], ["quad", -1, -6.0, 15.8], ["quad", 1, -6.0, 15.8], ["pod", -1, -2.0, 23.0], ["pod", 1, -2.0, 23.0]]},
		{"name": "STARBOARD HULL", "kind": "battery", "route": "right", "y": -6.0, "at": 14, "len": 31.7, "guns": [["twin", -3.0, 7.2],
			["twin", -9.0, 11.5], ["quad", -4.0, 15.8], ["mast", 1.0, 20.2], ["twin", -10.0, 23.0]]},
		{"name": "PORT HULL", "kind": "battery", "route": "top", "y": -6.0, "at": 30, "x": -22.0, "len": 31.7, "guns": [["pylon", 0.0, 22.0], ["quad", -3.0, 7.2], ["twin", 3.0, 11.5], ["pod", -3.0, 17.3], ["twin", 3.0, 26.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 50, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", 0.0, 5.7, 7.9]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	"goliath": {"name": "Goliath", "title": "Goliath-class dreadnought", "len": 110.0, "hull": "slab",
		"paint": "steel", "accent": Color8(0xff, 0xa8, 0x2e), "drones": 7.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "len": 31.7, "guns": [["nozzle", -7.5, -6.5, 0.0], ["nozzle", -2.5, -6.5, 0.0],
			["nozzle", 2.5, -6.5, 0.0], ["nozzle", 7.5, -6.5, 0.0], ["twin", -6.0, 5.8], ["twin", 6.0, 5.8]]},
		{"name": "HANGAR DECK", "kind": "hangar", "at": 14, "len": 33.1, "guns": [["hatch", -4.5, 7.2], ["hatch", 4.5, 7.2],
			["twin", -8.0, 15.8], ["twin", 8.0, 15.8], ["quad", 0.0, 18.7]]},
		{"name": "GUN DECK", "kind": "guns", "at": 30, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["twin", -7.0, 7.2],
			["twin", 7.0, 7.2], ["quad", -4.0, 17.3], ["quad", 4.0, 17.3], ["twin", 0.0, 22.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 48, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", -3.0, 5.7, 7.9], ["twin", 3.0, 5.7, 7.9]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# Ember Dunes
	# a sky galleon: a deep keeled hull under masts and fin sails, broadsides down both flanks
	"sirocco": {"name": "Sirocco", "title": "Sirocco sky galleon", "len": 112.0, "hull": "keel", "paint": "bronze",
		"accent": Color8(0xff, 0xc2, 0x5a), "drones": 7.0, "extras": ["masts"], "sections": [
		{"name": "STERN CASTLE", "kind": "engines", "at": 0, "len": 28.8, "guns": [["nozzle", -6.0, -5.5, 0.0], ["nozzle", 6.0, -5.5, 0.0],
			["twin", -7.0, 6.5], ["twin", 7.0, 6.5]]},
		{"name": "PORT BROADSIDE", "kind": "battery", "route": "left", "y": -4.0, "at": 10, "len": 31.7, "guns": [["twin", -1.5, 5.8],
			["twin", -1.5, 10.1], ["quad", -4.5, 14.4], ["twin", -1.5, 18.7], ["twin", -1.5, 23.0]]},
		{"name": "MAIN DECK", "kind": "guns", "at": 22, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["twin", -7.0, 7.2],
			["twin", 7.0, 7.2], ["quad", -5.0, 18.7], ["quad", 5.0, 18.7]]},
		{"name": "STARBOARD BROADSIDE", "kind": "battery", "route": "right", "y": -4.0, "at": 34, "len": 31.7, "guns": [["twin", -1.5, 5.8],
			["twin", -1.5, 10.1], ["quad", -4.5, 14.4], ["twin", -1.5, 18.7], ["twin", -1.5, 23.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 52, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["mast", 0.0, 10.5, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a beetle: a broad domed shell, a horned head, legs folded under
	"scarab": {"name": "Scarab", "title": "Scarab dome carrier", "len": 112.0, "paint": "sand",
		"accent": Color8(0x3a, 0xd0, 0xb8), "drones": 6.5, "extras": ["legs", "horn"], "bodies": [
		{"y": -9.0, "w": 24.0, "t": 9.0, "b": 6.0, "n": 2.4, "tail": 14.8, "tip": 0.35, "nose": 26.9, "nose_tip": 0.3},
		{"from": -21.7, "y": -7.0, "w": 10.0, "t": 6.0, "b": 5.0, "n": 2.4, "tail": 4.3, "tip": 0.6, "nose": 6.9, "nose_tip": 0.3},
	], "sections": [
		{"name": "UNDERBELLY", "kind": "bays", "route": "under", "at": 0, "len": 31.7, "guns": [["twin", -6.0, 10.1], ["twin", 6.0, 10.1],
			["hatch", 0.0, 15.8], ["quad", -7.0, 23.0], ["quad", 7.0, 23.0]]},
		{"name": "PORT ELYTRON", "kind": "battery", "route": "left", "y": -9.0, "at": 10, "len": 31.7, "guns": [["twin", -7.0, 7.2],
			["quad", -10.0, 13.0], ["twin", -6.0, 18.0], ["pod", -9.0, 23.0]]},
		{"name": "THORAX", "kind": "battery", "at": 24, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["twin", -8.0, 7.2],
			["twin", 8.0, 7.2], ["dish", 0.0, 23.0]]},
		{"name": "STARBOARD ELYTRON", "kind": "battery", "route": "right", "y": -9.0, "at": 36, "len": 31.7, "guns": [["twin", -7.0, 7.2],
			["pod", -9.0, 13.0], ["twin", -6.0, 18.0], ["quad", -10.0, 23.0]]},
		{"name": "CROWN", "kind": "bridge", "at": 54, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["quad", 0.0, 5.6, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a missile cruiser: a sharp wedge of a hull, missile banks and a lance array down its flank
	"talon": {"name": "Talon", "title": "Talon missile cruiser", "len": 100.0, "hull": "wedge",
		"paint": "iron", "accent": Color8(0xff, 0x58, 0x40), "drones": 7.5, "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "len": 27.4, "guns": [["nozzle", -5.0, -6.0, 0.0], ["nozzle", 5.0, -6.0, 0.0],
			["pod", -6.5, 6.5], ["pod", 6.5, 6.5]]},
		{"name": "MISSILE BANKS", "kind": "missiles", "at": 8, "len": 33.1, "guns": [["pylon", 0.0, 17.3], ["pod", -7.0, 5.8],
			["pod", 7.0, 5.8], ["pod", -4.0, 14.4], ["pod", 4.0, 14.4]]},
		{"name": "STARBOARD LANCES", "kind": "battery", "route": "right", "y": -4.0, "at": 20, "len": 30.2, "guns": [["mast", 2.5, 7.2],
			["twin", -3.0, 11.5], ["mast", 2.5, 17.3], ["twin", -3.0, 21.6]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 40, "len": 31.7, "guns": [["dish", 0.0, 11.0, 16.6], ["pod", -6.0, 6.0, 8.6],
			["pod", 6.0, 6.0, 8.6], ["mast", 0.0, 10.5, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# Iron Sprawl
	# a flying wing: a body blended into two swept wings, fought under its belly, out past one wingtip, over the other wing
	"manta": {"name": "Manta", "title": "Manta flying wing", "len": 104.0, "paint": "graphite",
		"accent": Color8(0x5a, 0xe8, 0xff), "drones": 6.0, "bodies": [
		{"y": -6.0, "w": 11.0, "t": 6.0, "b": 6.0, "n": 2.4, "tail": 9.7, "tip": 0.5, "nose": 24.3, "nose_tip": 0.12},
		{"x": -30.0, "y": -4.5, "w": 20.0, "t": 1.6, "b": 2.0, "n": 2.0, "from": 2.0, "to": -19.4, "sweep": 0.133, "tail": 8.8, "tip": 0.3, "nose": 34.0, "nose_tip": 0.05, "role": "wing"},
		{"x": 30.0, "y": -4.5, "w": 20.0, "t": 1.6, "b": 2.0, "n": 2.0, "from": 2.0, "to": -19.4, "sweep": 0.133, "tail": 8.8, "tip": 0.3, "nose": 34.0, "nose_tip": 0.05, "role": "wing"},
	], "sections": [
		{"name": "BELLY", "kind": "bays", "route": "under", "at": 0, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["twin", -5.0, 7.2],
			["twin", 5.0, 7.2], ["quad", -6.0, 23.0], ["quad", 6.0, 23.0]]},
		{"name": "STARBOARD WING", "kind": "battery", "route": "right", "x": 25.0, "at": 12, "y": -4.5, "len": 31.7, "guns": [["twin", -2.8, 7.2], ["quad", -3.0, 12.0], ["twin", -2.8, 17.0], ["pod", -2.5, 22.0]]},
		{"name": "PORT WING", "kind": "battery", "route": "top", "x": -28.0, "at": 24, "len": 31.7, "guns": [["twin", -6.0, 10.1],
			["twin", 5.0, 10.1], ["quad", -1.0, 17.3], ["pod", -6.0, 23.0], ["pod", 5.0, 23.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 40, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["mast", 0.0, 10.5, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a sky carrier: a round-bellied hull, hangars opening under its belly, an island battery on its flank, a flight deck
	"zephyr": {"name": "Zephyr", "title": "Zephyr sky carrier", "len": 112.0, "hull": "round",
		"paint": "ivory", "accent": Color8(0x4c, 0xe0, 0xa8), "drones": 5.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "y": -6.0, "len": 28.8, "guns": [["nozzle", -6.0, -6.0, 0.0], ["nozzle", 0.0, -6.0, 0.0],
			["nozzle", 6.0, -6.0, 0.0], ["quad", -7.0, 6.5], ["quad", 7.0, 6.5]]},
		{"name": "BELLY HANGARS", "kind": "bays", "route": "under", "at": 6, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["hatch", -5.0, 5.8],
			["hatch", 5.0, 5.8], ["quad", -6.0, 23.0], ["quad", 6.0, 23.0]]},
		{"name": "ISLAND BATTERY", "kind": "battery", "route": "right", "y": -3.0, "at": 18, "len": 26.0, "guns": [["twin", -1.0, 7.2],
			["quad", -5.0, 12.0], ["twin", 1.5, 17.0], ["pod", -4.0, 22.0]]},
		{"name": "FLIGHT DECK", "kind": "hangar", "at": 30, "len": 31.7, "guns": [["hatch", -5.0, 5.8], ["hatch", 5.0, 5.8],
			["hatch", 0.0, 14.4], ["twin", -8.0, 17.3], ["twin", 8.0, 17.3]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 48, "len": 31.7, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["quad", 0.0, 5.6, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a trimaran: a centre hull and two outriggers on cross wings, fought down both channels
	"trident": {"name": "Trident", "title": "Trident trimaran battleship", "len": 112.0, "paint": "crimson",
		"accent": Color8(0xff, 0xe0, 0x6a), "drones": 6.5, "bodies": [
		{"y": -8.0, "w": 11.0, "t": 8.0, "b": 10.0, "n": 3.0, "tail": 3.6, "tip": 0.7, "nose": 24.9, "nose_tip": 0.04, "nose_p": 1.4},
		{"x": -37.0, "y": -6.0, "w": 5.5, "t": 5.0, "b": 6.0, "n": 2.5, "from": 13.3, "to": -19.6, "tail": 7.1, "tip": 0.25, "nose": 13.3, "nose_tip": 0.1, "role": "pod"},
		{"x": 37.0, "y": -6.0, "w": 5.5, "t": 5.0, "b": 6.0, "n": 2.5, "from": 13.3, "to": -19.6, "tail": 7.1, "tip": 0.25, "nose": 13.3, "nose_tip": 0.1, "role": "pod"},
		{"x": -22.0, "y": -10.5, "w": 15.0, "t": 1.0, "b": 1.2, "n": 2.0, "from": 25.8, "to": 44.4, "tail": 1.8, "tip": 0.6, "nose": 1.8, "nose_tip": 0.6, "role": "wing"},
		{"x": 22.0, "y": -10.5, "w": 15.0, "t": 1.0, "b": 1.2, "n": 2.0, "from": 25.8, "to": 44.4, "tail": 1.8, "tip": 0.6, "nose": 1.8, "nose_tip": 0.6, "role": "wing"},
		{"x": -22.0, "y": -10.5, "w": 15.0, "t": 1.0, "b": 1.2, "n": 2.0, "from": 66.6, "to": 80.8, "tail": 1.8, "tip": 0.6, "nose": 1.8, "nose_tip": 0.6, "role": "wing"},
		{"x": 22.0, "y": -10.5, "w": 15.0, "t": 1.0, "b": 1.2, "n": 2.0, "from": 66.6, "to": 80.8, "tail": 1.8, "tip": 0.6, "nose": 1.8, "nose_tip": 0.6, "role": "wing"},
	], "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "len": 28.8, "guns": [["nozzle", -4.5, -7.0, 0.0], ["nozzle", 4.5, -7.0, 0.0],
			["twin", -5.0, 7.2], ["twin", 5.0, 7.2]]},
		{"name": "PORT CHANNEL", "kind": "battery", "route": "gap", "x": -21.5, "y": -3.0, "at": 10, "len": 31.7, "guns": [["twin", 1, -3.0, 7.2],
			["twin", -1, -3.0, 10.1], ["quad", 1, -6.0, 15.8], ["pod", -1, -2.0, 18.7], ["twin", 1, -2.0, 22.3], ["twin", -1, -6.0, 23.0]]},
		{"name": "SPINE", "kind": "battery", "at": 24, "len": 30.2, "guns": [["mast", -4.0, 8.6], ["mast", 4.0, 8.6],
			["twin", -3.0, 15.8], ["twin", 3.0, 15.8], ["pylon", 0.0, 21.6]]},
		{"name": "STARBOARD CHANNEL", "kind": "battery", "route": "gap", "x": 21.5, "y": -3.0, "at": 36, "len": 31.7, "guns": [["twin", -1, -3.0, 7.2],
			["twin", 1, -3.0, 10.1], ["quad", -1, -6.0, 15.8], ["pod", 1, -2.0, 18.7], ["twin", -1, -2.0, 22.3], ["twin", 1, -6.0, 23.0]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 54, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", 0.0, 5.7, 7.9]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# Frost Shelf
	# an icebreaker: a wedge hull grown over with crystal, a spiral tusk at its bow
	"narwhal": {"name": "Narwhal", "title": "Narwhal icebreaker", "len": 112.0, "hull": "wedge", "paint": "frost",
		"accent": Color8(0x3a, 0xc8, 0xff), "drones": 6.5, "extras": ["tusk", "spires"], "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "y": -6.0, "len": 28.8, "guns": [["nozzle", -6.0, -6.0, 0.0], ["nozzle", 0.0, -7.5, 0.0],
			["nozzle", 6.0, -6.0, 0.0], ["twin", 0.0, 6.5]]},
		{"name": "KEEL GUNS", "kind": "bays", "route": "under", "at": 6, "len": 31.7, "guns": [["twin", -2.5, 7.2], ["twin", 2.5, 7.2],
			["quad", 0.0, 15.8], ["pod", -2.5, 23.0], ["pod", 2.5, 23.0]]},
		{"name": "PORT CASEMATES", "kind": "battery", "route": "left", "y": -4.0, "at": 18, "len": 31.7, "guns": [["quad", -1.0, 7.2],
			["twin", -2.5, 12.2], ["twin", -1.0, 17.3], ["pod", -2.0, 22.3]]},
		{"name": "CRYSTAL DECK", "kind": "spires", "at": 30, "len": 31.7, "guns": [["pylon", 0.0, 15.8], ["mast", -6.0, 8.6],
			["mast", 6.0, 8.6], ["twin", -4.0, 21.6], ["twin", 4.0, 21.6]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 50, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["twin", -6.5, 5.7, 8.6],
			["twin", 6.5, 5.7, 8.6], ["quad", 0.0, 5.6, 7.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a fast raider: a wedge hull, flak and lances down its flank, three engines
	"wyvern": {"name": "Wyvern", "title": "Wyvern battle raider", "len": 100.0, "hull": "wedge",
		"paint": "cobalt", "accent": Color8(0xb4, 0x80, 0xff), "drones": 6.0, "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "len": 27.4, "guns": [["nozzle", -6.0, -5.5, 0.0], ["nozzle", 0.0, -7.5, 0.0],
			["nozzle", 6.0, -5.5, 0.0], ["mast", -6.0, 7.2], ["mast", 6.0, 7.2]]},
		{"name": "FLAK DECK", "kind": "guns", "at": 8, "len": 31.7, "guns": [["quad", -6.0, 5.8], ["quad", 6.0, 5.8],
			["quad", 0.0, 11.5], ["twin", -7.5, 15.8], ["twin", 7.5, 15.8]]},
		{"name": "PORT LANCES", "kind": "battery", "route": "left", "y": -4.0, "at": 22, "len": 30.2, "guns": [["pylon", -7.0, 22.3],
			["mast", 2.5, 7.2], ["twin", -3.0, 11.5], ["mast", 2.5, 17.3]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 40, "len": 31.7, "guns": [["dish", -3.5, 11.0, 16.6], ["dish", 3.5, 11.0, 16.6],
			["twin", -6.0, 5.7, 8.6], ["twin", 6.0, 5.7, 8.6]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# a string of pods on a slender spine, flown round: over, to port, under, to starboard, over
	"aurora": {"name": "Aurora", "title": "Aurora pod chain", "len": 104.0, "paint": "violet",
		"accent": Color8(0x6a, 0xff, 0xc8), "drones": 6.0, "extras": ["rings"], "bodies": [
		{"y": -4.0, "w": 2.4, "t": 2.4, "b": 2.4, "n": 2.0, "tail": 0.8, "tip": 0.6, "nose": 2.4, "nose_tip": 0.4, "role": "keel"},
		{"from": 0.8, "to": 16.9, "y": -10.0, "w": 12.0, "t": 10.0, "b": 10.0, "n": 2.3, "tail": 5.7, "tip": 0.3, "nose": 5.7, "nose_tip": 0.3, "role": "pod"},
		{"from": 18.9, "to": 34.2, "y": -10.0, "w": 12.0, "t": 10.0, "b": 10.0, "n": 2.3, "tail": 5.7, "tip": 0.3, "nose": 5.7, "nose_tip": 0.3, "role": "pod"},
		{"from": 36.6, "to": 52.0, "y": -10.0, "w": 12.0, "t": 10.0, "b": 10.0, "n": 2.3, "tail": 5.7, "tip": 0.3, "nose": 5.7, "nose_tip": 0.3, "role": "pod"},
		{"from": 54.4, "to": 69.7, "y": -10.0, "w": 12.0, "t": 10.0, "b": 10.0, "n": 2.3, "tail": 5.7, "tip": 0.3, "nose": 5.7, "nose_tip": 0.3, "role": "pod"},
		{"from": 72.1, "to": -0.4, "y": -10.0, "w": 16.0, "t": 10.0, "b": 10.0, "n": 2.8, "tail": 4.8, "tip": 0.3, "nose": 14.5, "nose_tip": 0.05},
	], "sections": [
		{"name": "FIRST POD", "kind": "battery", "at": 0, "len": 31.7, "guns": [["twin", -5.0, 5.0], ["twin", 5.0, 5.0], ["dish", 0.0, 9.0], ["quad", -5.0, 13.0], ["quad", 5.0, 13.0]]},
		{"name": "PORT POD", "kind": "battery", "route": "left", "y": -10.0, "at": 14, "len": 31.7, "guns": [["twin", -7.0, 8.0], ["quad", -12.0, 12.0], ["twin", -7.0, 16.0], ["pod", -12.5, 19.0]]},
		{"name": "KEEL POD", "kind": "bays", "route": "under", "at": 30, "len": 31.7, "guns": [["twin", -5.0, 9.0], ["twin", 5.0, 9.0], ["hatch", 0.0, 13.0], ["quad", -5.0, 17.0], ["quad", 5.0, 17.0]]},
		{"name": "STARBOARD POD", "kind": "battery", "route": "right", "y": -10.0, "at": 46, "len": 31.7, "guns": [["twin", -7.0, 12.0], ["pod", -12.5, 15.0], ["twin", -7.0, 19.0], ["quad", -12.0, 22.0]]},
		{"name": "CROWN POD", "kind": "bridge", "at": 62, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", 0.0, 5.7, 7.9]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# Cinder Reach
	# a serpent: a long body winding through the sky, spined, its reactor in its throat
	"basilisk": {"name": "Basilisk", "title": "Basilisk serpent ship", "len": 116.0, "paint": "basalt",
		"accent": Color8(0xff, 0x7a, 0x2a), "drones": 6.0, "extras": ["spines", "horns"], "bodies": [
		{"y": -8.0, "w": 10.0, "t": 8.0, "b": 8.0, "n": 2.3, "wave": [11.0, 79.1, -0.785], "tail": 25.1, "tip": 0.12, "nose": 6.3, "nose_tip": 0.7},
		{"from": -21.6, "y": -7.5, "w": 13.0, "t": 7.5, "b": 7.5, "n": 2.4, "wave": [11.0, 79.1, -0.785], "tail": 5.4, "tip": 0.75, "nose": 9.0, "nose_tip": 0.25},
	], "sections": [
		{"name": "TAIL", "kind": "battery", "at": 0, "len": 31.7, "guns": [["twin", -3.5, 11.5], ["twin", 3.5, 11.5],
			["quad", 0.0, 17.3], ["twin", -4.0, 23.0], ["twin", 4.0, 23.0]]},
		{"name": "COILS", "kind": "battery", "route": "right", "y": -8.0, "at": 12, "len": 31.7, "guns": [["twin", -5.0, 8.6],
			["quad", -9.0, 13.0], ["twin", -6.0, 18.0], ["pod", -10.0, 23.0]]},
		{"name": "BELLY SCALES", "kind": "bays", "route": "under", "at": 26, "len": 31.7, "guns": [["twin", -4.0, 8.6], ["twin", 4.0, 8.6],
			["pylon", 0.0, 15.8], ["quad", -4.0, 23.0], ["quad", 4.0, 23.0]]},
		{"name": "DORSAL SPINES", "kind": "battery", "route": "left", "y": -8.0, "at": 40, "len": 31.7, "guns": [["mast", -1.0, 8.6],
			["twin", -8.0, 13.7], ["mast", -1.0, 18.7], ["quad", -10.0, 23.0]]},
		{"name": "THROAT", "kind": "gondola", "route": "under", "at": 58, "len": 33.1, "guns": [["twin", -5.0, 5.8], ["twin", 5.0, 5.8],
			["quad", -6.0, 20.2], ["quad", 6.0, 20.2]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# the biggest: six engines, a hangar, a ventral battery, missile banks down its flank, the bridge
	"leviathan": {"name": "Leviathan", "title": "Leviathan super-dreadnought", "len": 116.0, "hull": "slab",
		"paint": "olive", "accent": Color8(0xff, 0xd8, 0x40), "drones": 6.5, "sections": [
		{"name": "ENGINES", "kind": "engines", "at": 0, "y": -6.0, "len": 31.7, "guns": [["nozzle", -8.0, -5.0, 0.0], ["nozzle", -4.0, -8.0, 0.0],
			["nozzle", 0.0, -5.0, 0.0], ["nozzle", 4.0, -8.0, 0.0], ["nozzle", 8.0, -5.0, 0.0], ["twin", 0.0, 6.5]]},
		{"name": "VENTRAL GUNS", "kind": "bays", "route": "under", "at": 6, "len": 31.7, "guns": [["twin", -5.0, 7.2], ["twin", 5.0, 7.2],
			["twin", 0.0, 13.0], ["quad", -5.0, 20.2], ["quad", 5.0, 20.2]]},
		{"name": "PORT MISSILES", "kind": "battery", "route": "left", "y": -4.0, "at": 18, "len": 30.2, "guns": [["pylon", -10.0, 21.6],
			["pod", -2.0, 7.2], ["pod", -6.0, 14.4], ["mast", 2.5, 10.1], ["pod", -2.0, 23.0]]},
		{"name": "HANGAR DECK", "kind": "hangar", "at": 30, "len": 31.7, "guns": [["hatch", -5.0, 7.2], ["hatch", 5.0, 7.2],
			["quad", -8.0, 15.8], ["quad", 8.0, 15.8]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 50, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", -3.0, 5.7, 7.9], ["twin", 3.0, 5.7, 7.9]]},
		{"name": "REACTOR", "kind": "core", "len": 0.0, "guns": []},
	]},
	# the last: a vast hull between two engine nacelles on pylon wings, fought all the way round
	"behemoth": {"name": "Behemoth", "title": "Behemoth sky citadel", "len": 124.0, "paint": "graphite",
		"accent": Color8(0xff, 0x4a, 0x3a), "drones": 5.5, "bodies": [
		{"y": -11.0, "w": 17.0, "t": 11.0, "b": 13.0, "n": 2.9, "tail": 4.3, "tip": 0.7, "nose": 21.4, "nose_tip": 0.08, "nose_p": 1.5},
		{"x": -45.0, "y": -12.0, "w": 6.5, "t": 6.5, "b": 6.5, "n": 2.1, "from": 10.3, "to": -29.9, "tail": 4.3, "tip": 0.55, "nose": 9.4, "nose_tip": 0.2, "role": "pod"},
		{"x": 45.0, "y": -12.0, "w": 6.5, "t": 6.5, "b": 6.5, "n": 2.1, "from": 10.3, "to": -29.9, "tail": 4.3, "tip": 0.55, "nose": 9.4, "nose_tip": 0.2, "role": "pod"},
		{"x": -31.0, "y": -13.0, "w": 15.0, "t": 1.3, "b": 1.6, "n": 2.0, "from": 17.1, "to": -38.5, "tail": 2.6, "tip": 0.5, "nose": 2.6, "nose_tip": 0.5, "role": "wing"},
		{"x": 31.0, "y": -13.0, "w": 15.0, "t": 1.3, "b": 1.6, "n": 2.0, "from": 17.1, "to": -38.5, "tail": 2.6, "tip": 0.5, "nose": 2.6, "nose_tip": 0.5, "role": "wing"},
	], "sections": [
		{"name": "ENGINES", "kind": "engines", "route": "stern", "y": -16.0, "at": 0, "len": 28.8, "guns": [["nozzle", -7.0, -9.0, 0.0], ["nozzle", 0.0, -12.0, 0.0], ["nozzle", 7.0, -9.0, 0.0], ["twin", -10.0, -4.0, 1.0], ["twin", 10.0, -4.0, 1.0]]},
		{"name": "VENTRAL BATTERY", "kind": "bays", "route": "under", "at": 6, "len": 30.2, "guns": [["pylon", 0.0, 14.4], ["twin", -6.0, 7.2],
			["twin", 6.0, 7.2], ["quad", -6.0, 21.6], ["quad", 6.0, 21.6], ["hatch", 0.0, 23.0]]},
		{"name": "PORT NACELLE", "kind": "battery", "route": "gap", "x": -28.0, "y": -4.0, "at": 18, "len": 30.2, "guns": [["twin", 1, -4.0, 7.2],
			["twin", -1, -4.0, 8.6], ["quad", 1, -8.0, 14.4], ["pod", -1, -6.0, 15.8], ["twin", 1, -2.0, 23.0], ["mast", -1, -6.0, 22.3]]},
		{"name": "DORSAL BATTERIES", "kind": "guns", "at": 32, "len": 30.2, "guns": [["pylon", 0.0, 15.8], ["twin", -7.0, 7.2],
			["twin", 7.0, 7.2], ["quad", -5.0, 18.7], ["quad", 5.0, 18.7], ["dish", 0.0, 23.0]]},
		{"name": "STARBOARD NACELLE", "kind": "battery", "route": "gap", "x": 28.0, "y": -4.0, "at": 44, "len": 30.2, "guns": [["twin", -1, -4.0, 7.2],
			["twin", 1, -4.0, 8.6], ["quad", -1, -8.0, 14.4], ["pod", 1, -6.0, 15.8], ["twin", -1, -2.0, 23.0], ["mast", 1, -6.0, 22.3]]},
		{"name": "BRIDGE", "kind": "bridge", "at": 64, "len": 33.1, "guns": [["dish", 0.0, 11.0, 16.6], ["mast", -6.5, 10.5, 9.4],
			["mast", 6.5, 10.5, 9.4], ["twin", -3.0, 5.7, 7.9], ["twin", 3.0, 5.7, 7.9]]},
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
## A section placed on the hull by its `at` (the ship is designed first, its sections overlapping:
## flanks side by side, a belly under a deck); without one, end to end after the one before. The
## reactor sits on the heart's stretch.
static func section_at(id: String, i: int) -> float:
	var secs: Array = FORTRESSES[id].sections
	if i < secs.size():
		if secs[i].kind == "core" and i > 0:
			return section_at(id, i - 1)
		if secs[i].has("at"):
			return float(secs[i].at)
	var z := 0.0
	for k in mini(i, secs.size()):
		z += float(secs[k].len)
	return z


## The hull's length, stern to bow tip: its `len`, or its sections end to end and the bow.
static func fortress_len(id: String) -> float:
	var f: Dictionary = FORTRESSES[id]
	if f.has("len"):
		return float(f.len)
	var z := 0.0
	for sec: Dictionary in f.sections:
		z += float(sec.len)
	return z + BOW_LEN


## A gun's place on the ship's model: x, height and z (the stern at 0, the bow towards -z). Guns
## sit on the hull's surface where their section's route meets it (`Capital.mount`).
static func gun_at(id: String, i: int, g: Array) -> Vector3:
	return Capital.mount(id, i, g).at


## Where the ship flies while fighting section i: [distance ahead of the stern (negative: behind
## it), height above the deck]; across, `Capital.lane(id, i).x`. The engines are fought from
## behind the stern, level with them; a flank from beside it, the belly from beneath.
static func station(id: String, i: int) -> Vector2:
	var l := Capital.lane(id, i)
	return Vector2(l.along, l.y)


## How high the deck flies in the chase: `CHASE_DECK`, or higher for a ship fought from beneath,
## so the ship never comes within `LOW` m of the ground.
const LOW := 12.0
static func deck_of(id: String) -> float:
	var low := 0.0
	for i in FORTRESSES[id].sections.size():
		var l := Capital.lane(id, i)
		low = minf(low, l.y + l.reach.z)
	return maxf(CHASE_DECK, LOW - low)


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
## about 2 s; a big drop at once, then a gentle tail, see `Game.time_speed`); touching again brings it back up to full speed over `SLOW_RESUME` s.
const SLOW_STOP := 2.0
const SLOW_RESUME := 0.25
const APPROACH := 2.8
const AIM_AHEAD := 32.0
const AIM_DIP := 0.12
## The aim assist only nudges the guns onto a target almost lined up (Guillaume, 2026-11-24: the
## bosses were too easy, "there is some form of auto aim"): you have to fly onto your target.
const AIM_ASSIST := 1.0
## The fortress's fire is quicker than the stage's (Guillaume wanted a real challenge).
const BOSS_FIRE := 1.15
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
## Meanwhile the ship climbs a little away from the blast, but no higher than `CRUISE_Y` above
## the ground: from higher up the camera would see the edges of the land.
const CLIMB := 5.0
## The mid-boss's husk: how fast it loses way against the scroll (m/s per s) and sinks (m/s).
const HUSK_DRAG := 1.6
const HUSK_SINK := 0.35
const CRUISE_Y := 32.0

# ---------------------------------------------------------------- upgrades
const ORDER := ["cannon", "missile", "hull", "magnet"]
const UPGRADES := {
	"cannon": {"name": "Cannon", "max": 5, "cost": [120, 320, 700, 1300, 2400],
		"desc": "Harder hits (power cores widen the spread)"},
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


## In-level power (Guillaume, 2026-11-24: with every upgrade bought the game was too easy; "how
## about keeping an in level progress"). Every level starts on the bare twin gun. Foes of the
## vertical stage drop power cores, each a step wider spread, up to `POWER_MAX`. A hit costs a power
## step and the kills towards the next core. The hangar's Cannon upgrade no longer buys the spread:
## it makes every shot hit harder (`CANNON_DMG` a level), so the ship keeps improving but every run
## builds up from weak.
## Each step takes more kills than the last (`POWER_KILLS`; Guillaume, 2026-11-24: "you go too
## quickly from 0 to the max, and then you're OP and you cannot lose"), and the mid-boss gives one
## core when it goes down: full power comes late in a long level, if ever, and is easily lost.
const POWER_MAX := 4
const POWER_KILLS := [12, 22, 34, 48]


## Kills of the vertical stage it takes for the core of the next step from a power.
static func kills_for(power: int) -> int:
	return int(POWER_KILLS[clampi(power, 0, POWER_KILLS.size() - 1)])


const CANNON_DMG := 0.15


## Damage of each cannon shot at a Cannon upgrade level.
static func cannon_dmg(lv: int) -> float:
	return 1.0 + CANNON_DMG * clampi(lv, 0, UPGRADES.cannon.max)


## The main gun at an in-level power (0..POWER_MAX) and a Cannon upgrade level: shots as
## [x offset, angle in degrees], damage per shot and the time between volleys. Used by both the
## vertical stage and the chase.
static func cannon(power: int, lv := 0) -> Dictionary:
	var shots: Array = [[-0.22, 0.0], [0.22, 0.0]]
	if power >= 1:
		shots = [[-0.32, 0.0], [0.0, 0.0], [0.32, 0.0]]
	if power >= 2:
		shots += [[-0.4, -7.0], [0.4, 7.0]]
	if power >= 3:
		shots += [[-0.5, -15.0], [0.5, 15.0]]
	return {"shots": shots, "dmg": cannon_dmg(lv), "period": 0.09 if power >= POWER_MAX else 0.11}


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
	# each world's own civilian in place of the seaplane (`Civilians`)
	"paramotor": {"hp": 3.0, "r": 1.5, "score": 120, "scrap": 6},
	"heli": {"hp": 4.0, "r": 1.4, "score": 120, "scrap": 6},
	"blimp": {"hp": 4.0, "r": 1.5, "score": 120, "scrap": 6},
	"balloon": {"hp": 3.0, "r": 1.2, "score": 120, "scrap": 6},
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
	"panel": {"hp": 22.0, "r": 1.5, "score": 300, "scrap": 20},
	"core": {"hp": 70.0, "r": 2.3, "score": 3000, "scrap": 200},
	"nozzle": {"hp": 48.0, "r": 2.4, "score": 500, "scrap": 25},
	"twin": {"hp": 38.0, "r": 1.8, "score": 400, "scrap": 20},
	"quad": {"hp": 40.0, "r": 1.8, "score": 400, "scrap": 20},
	"pod": {"hp": 38.0, "r": 1.8, "score": 450, "scrap": 20},
	"mast": {"hp": 32.0, "r": 1.7, "score": 450, "scrap": 20},
	"dish": {"hp": 48.0, "r": 2.2, "score": 600, "scrap": 30},
	"pylon": {"hp": 30.0, "r": 1.7, "score": 500, "scrap": 25},
	"hatch": {"hp": 42.0, "r": 2.3, "score": 450, "scrap": 20},
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
## Civilians (Guillaume, 2026-11-24): shooting a real one down scores nothing and drops no scrap,
## and it doesn't count towards the kill rate. No penalty and no notice (Guillaume, 2026-11-25: "The
## game is too dense to be able to avoid killing them"). A hacked one (`Game.Obj.hacked`) unveils a gun:
## a seaplane a minigun, a lighthouse a turret. It's a foe then, and pays HACK_PAY times its due.
const CIVILIANS := ["gull", "paramotor", "heli", "blimp", "balloon", "boat", "house", "lighthouse"]
const HACK_PAY := 2.0
## Chance a lighthouse is hacked (a seaplane's: `Foes.HACK_P`).
const HACK_LIGHTHOUSE := 0.4

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
	# a longer run to the mid-boss (Guillaume, 2026-11-24: "the journey between two bosses
	# should be longer")
	{"t": 18.5, "kind": "dart", "n": 6, "x": 1.5, "gap": 0.3, "from": "left"},
	{"t": 20.0, "kind": "pillbox", "n": 2, "x": -2.5, "gap": 0.0},
	{"t": 21.5, "kind": "swing", "n": 6, "x": 1.5, "gap": 0.37},
	{"t": 23.5, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 25.0, "kind": "rocket", "n": 1, "x": -3.8, "gap": 0.0},
	{"t": 26.5, "kind": "dart", "n": 7, "x": 3.0, "gap": 0.28, "from": "right"},
	{"t": 28.5, "kind": "dart", "n": 6, "x": 5.0, "gap": 0.3, "from": "back"},
	{"t": 30.5, "kind": "swing", "n": 6, "x": -2.0, "gap": 0.37},
	# mid-boss: the clock waits until it's down
	{"t": 34.5, "kind": "boss", "n": 1, "x": 0.0, "gap": 0.0},
	{"t": 37.0, "kind": "swing", "n": 6, "x": 2.0, "gap": 0.35},
	{"t": 38.5, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 39.5, "kind": "pillbox", "n": 1, "x": -3.5, "gap": 0.0},
	{"t": 40.5, "kind": "heavy", "n": 1, "x": -2.5, "gap": 0.0},
	{"t": 43.0, "kind": "dart", "n": 8, "x": 0.0, "gap": 0.25, "from": "left"},
	{"t": 45.0, "kind": "dart", "n": 8, "x": 2.0, "gap": 0.25, "from": "right"},
	{"t": 47.5, "kind": "swing", "n": 6, "x": -2.0, "gap": 0.35},
	{"t": 49.0, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 51.0, "kind": "dart", "n": 6, "x": 4.5, "gap": 0.3, "from": "back"},
	{"t": 51.5, "kind": "swing", "n": 6, "x": 2.5, "gap": 0.35},
	{"t": 54.0, "kind": "rocket", "n": 1, "x": 3.5, "gap": 0.0},
	{"t": 55.0, "kind": "pillbox", "n": 2, "x": 2.5, "gap": 0.0},
	{"t": 56.5, "kind": "dart", "n": 6, "x": -3.0, "gap": 0.3},
	{"t": 58.5, "kind": "heavy", "n": 1, "x": 2.0, "gap": 0.0},
	{"t": 61.5, "kind": "swing", "n": 6, "x": -1.5, "gap": 0.35},
	{"t": 63.0, "kind": "turret", "n": 2, "x": 3.5, "gap": 0.0},
	{"t": 64.5, "kind": "dart", "n": 8, "x": -1.0, "gap": 0.25, "from": "left"},
	{"t": 66.5, "kind": "dart", "n": 6, "x": -5.0, "gap": 0.3, "from": "back"},
	{"t": 68.0, "kind": "swing", "n": 6, "x": 1.0, "gap": 0.35},
	# final boss: the fortress chase ends the sector
	{"t": 72.0, "kind": "fortress", "n": 1, "x": 0.0, "gap": 0.0},
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
