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
const PICK_R := 1.0

# ---------------------------------------------------------------- the carrier (POV episode)
## The carrier: `CARRIER_LEN` long, its hangar (the opening at the stern where the reactor
## shows) centred on the flight altitude.
const CARRIER_LEN := 180.0
## The carrier is tall and narrow (it fits a portrait screen in the chase): half width, the
## height of its hull and of its tower, and its hangar (half width, half height).
const CARRIER_HW := 5.0
const CARRIER_TOP := 13.0
const TOWER_TOP := 21.0
const HANGAR_HW := 3.0
const HANGAR_HH := 2.3
## Turret mounts on the carrier's stern (x, y): either side of the hangar, on the hull above
## it and up the tower. All within the ship's reach in the chase.
const MOUNTS := [Vector2(-4.0, 3.2), Vector2(4.0, 3.2), Vector2(-4.0, 9.0), Vector2(4.0, 9.0),
	Vector2(-2.0, 10.5), Vector2(2.0, 10.5), Vector2(-3.0, 14.5), Vector2(3.0, 14.5),
	Vector2(0.0, 17.5), Vector2(-1.8, 19.5), Vector2(1.8, 19.5)]
## The chase (third person, outside): how far the ship may move from the centre line
## (x either side, y up; `POV_DOWN` down; the carrier is tall, so the ship climbs high), metres per pixel of drag, the on-rails speed, the distance
## to the carrier's stern while chasing and while fighting its reactor, the swoop's length,
## where the guns converge and how far the aim assist reaches.
const POV_REACH := Vector2(4.5, 13.0)
const POV_DOWN := 2.5
const POV_DRAG := 0.016
const RAIL := 18.0
const GAP_FAR := 30.0
const GAP_NEAR := 22.0
const APPROACH := 2.6
const AIM_AHEAD := 32.0
const AIM_ASSIST := 1.6
## Rail distance where the reactor fight starts.
const RAIL_STOP := 330.0

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
	return {"scrap": 0, "best": 0, "runs": 0, "clears": 0,
		"up": {"cannon": 0, "missile": 0, "hull": 0, "magnet": 0}}


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
	"boss": {"hp": 380.0, "r": 2.6, "score": 6000, "scrap": 300},
	"drone": {"hp": 4.0, "r": 0.9, "score": 150, "scrap": 10},
	"sentry": {"hp": 7.0, "r": 0.9, "score": 200, "scrap": 15},
	"orb": {"hp": 1.0, "r": 0.35, "score": 10, "scrap": 0},
	"panel": {"hp": 14.0, "r": 0.95, "score": 300, "scrap": 20},
	"core": {"hp": 45.0, "r": 1.5, "score": 3000, "scrap": 200},
}

## The vertical stage, Sector 1 (Glass Coast): waves by stage time (seconds of vertical play;
## the clock stops during the carrier episode). `x` is where the wave enters, `n` how many
## foes, `gap` the seconds between them.
const STAGE := [
	{"t": 1.5, "kind": "dart", "n": 5, "x": -3.0, "gap": 0.35},
	{"t": 4.0, "kind": "dart", "n": 5, "x": 3.0, "gap": 0.35},
	{"t": 7.0, "kind": "swing", "n": 6, "x": -1.0, "gap": 0.4},
	{"t": 9.0, "kind": "turret", "n": 2, "x": -3.5, "gap": 0.0},
	{"t": 10.0, "kind": "turret", "n": 1, "x": 3.8, "gap": 0.0},
	{"t": 12.5, "kind": "dart", "n": 6, "x": 0.0, "gap": 0.3},
	{"t": 15.0, "kind": "heavy", "n": 1, "x": 0.0, "gap": 0.0},
	{"t": 19.5, "kind": "swing", "n": 6, "x": 2.0, "gap": 0.35},
	{"t": 21.0, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 23.0, "kind": "dart", "n": 8, "x": -4.0, "gap": 0.25},
	{"t": 25.0, "kind": "dart", "n": 8, "x": 4.0, "gap": 0.25},
	{"t": 28.0, "kind": "carrier", "n": 1, "x": 0.0, "gap": 0.0},
	# after the carrier
	{"t": 31.5, "kind": "swing", "n": 6, "x": -2.0, "gap": 0.35},
	{"t": 33.0, "kind": "turret", "n": 3, "x": 0.0, "gap": 0.0},
	{"t": 35.0, "kind": "heavy", "n": 1, "x": -2.5, "gap": 0.0},
	{"t": 37.0, "kind": "dart", "n": 8, "x": 3.0, "gap": 0.25},
	{"t": 40.0, "kind": "dart", "n": 6, "x": -3.0, "gap": 0.3},
	{"t": 40.5, "kind": "swing", "n": 6, "x": 2.5, "gap": 0.35},
	{"t": 45.0, "kind": "boss", "n": 1, "x": 0.0, "gap": 0.0},
]

## The chase: foes by rail distance (metres flown behind the carrier).
const POV_WAVES := [
	{"s": 15.0, "kind": "drone", "n": 3},
	{"s": 40.0, "kind": "sentry", "n": 2},
	{"s": 70.0, "kind": "drone", "n": 4},
	{"s": 110.0, "kind": "sentry", "n": 3},
	{"s": 140.0, "kind": "drone", "n": 5},
	{"s": 190.0, "kind": "sentry", "n": 2},
	{"s": 210.0, "kind": "drone", "n": 3},
	{"s": 260.0, "kind": "drone", "n": 4},
	{"s": 300.0, "kind": "core", "n": 1},
]


## Count of foes in the stage that can be shot down (for the results' kill rate).
static func stage_foes() -> int:
	var n := 0
	for w: Dictionary in STAGE:
		if w.kind != "carrier":
			n += int(w.n)
	for w: Dictionary in POV_WAVES:
		n += 5 if w.kind == "core" else int(w.n)
	return n


## Grade of a run from kill rate and hits taken.
static func grade(kills: int, total: int, hits: int, cleared: bool) -> String:
	if not cleared:
		return "-"
	var rate := float(kills) / maxf(1.0, float(total))
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
