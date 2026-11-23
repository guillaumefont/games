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
## The final boss in sections, like the mid-boss: turrets on the stern round the hangar (on
## armour plating that breaks off), then turrets up the tower (which breaks off), then the
## reactor in the hangar behind its four shield panels. Mounts are (x, y) on the carrier's
## model, all within the ship's reach in the chase.
const CARRIER_SECTIONS := [
	{"name": "STERN GUNS", "mounts": [Vector2(-4.0, 3.2), Vector2(4.0, 3.2), Vector2(-4.0, 9.0),
		Vector2(4.0, 9.0), Vector2(-2.0, 10.8), Vector2(2.0, 10.8)]},
	{"name": "TOWER", "mounts": [Vector2(-3.0, 14.5), Vector2(3.0, 14.5), Vector2(0.0, 16.0),
		Vector2(-1.8, 19.5), Vector2(1.8, 19.5)]},
	{"name": "REACTOR", "mounts": []},
]
## Seconds between drone launches from the hangar during the chase.
const DRONE_EVERY := 6.5
## The chase (third person, outside): how far the ship may move from the centre line
## (x either side, wide enough to fly past the carrier's flanks at its chase scale; y up; `POV_DOWN` down; the carrier is tall, so the ship climbs high), metres per pixel of drag, the on-rails speed, the distance
## to the carrier's stern while chasing and while fighting its reactor, the swoop's length,
## where the guns converge and how far the aim assist reaches.
const POV_REACH := Vector2(11.0, 36.0)
const POV_DOWN := 2.5
## The share of the screen's width (and height) one swipe needs to cross the whole reach.
const POV_SWIPE := 0.7
const RAIL := 18.0
## Lifting the finger slows time to a stop over `SLOW_STOP` s (a pause); touching again brings
## it back up to full speed over `SLOW_RESUME` s.
const SLOW_STOP := 0.7
const SLOW_RESUME := 0.25
const GAP_FAR := 10.0
const GAP_NEAR := 9.0
## In the chase the carrier grows (during the swoop) to `CARRIER_SCALE` times its size, its
## hangar `CARRIER_LIFT` above the flight altitude, so up close it overflows the screen.
const CARRIER_SCALE := 2.2
const CARRIER_LIFT := 6.0
const APPROACH := 2.6
const AIM_AHEAD := 32.0
## The carrier going down after its reactor: how long, and how fast it falls (m/s per second).
const CRASH_TIME := 5.0
const CRASH_FALL := 1.6
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
	"drone": {"hp": 4.0, "r": 0.9, "score": 150, "scrap": 10},
	"sentry": {"hp": 16.0, "r": 1.4, "score": 400, "scrap": 25},
	"orb": {"hp": 1.0, "r": 0.35, "score": 10, "scrap": 0},
	"panel": {"hp": 14.0, "r": 1.5, "score": 300, "scrap": 20},
	"core": {"hp": 45.0, "r": 2.3, "score": 3000, "scrap": 200},
}

## The vertical stage, Sector 1 (Glass Coast): waves by stage time (seconds of vertical play).
## The mid-boss (the Bastion, top-down) holds the clock until it's down; the final boss is the
## carrier, chased in third person, and ends the sector. `x` is where the wave enters, `n` how many
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
	# final boss: the carrier chase ends the sector
	{"t": 40.0, "kind": "carrier", "n": 1, "x": 0.0, "gap": 0.0},
]



## The mid-boss, a battleship bigger than the screen, taken apart section by section:
## each section's parts (kind, position on the ship: x, y, z towards its bow) must all go down
## before the next section opens. The bridge is shielded until the last section. Nose to +z.
const BOSS_SECTIONS := [
	{"name": "BOW GUNS", "parts": [
		{"kind": "cannon", "at": Vector3(-1.6, 1.4, 6.5)}, {"kind": "cannon", "at": Vector3(1.6, 1.4, 6.5)},
		{"kind": "flak", "at": Vector3(-3.0, 1.0, 3.0)}, {"kind": "flak", "at": Vector3(3.0, 1.0, 3.0)}]},
	{"name": "WING BATTERIES", "parts": [
		{"kind": "battery", "at": Vector3(-5.4, 0.8, 0.2)}, {"kind": "battery", "at": Vector3(5.4, 0.8, 0.2)},
		{"kind": "battery", "at": Vector3(-7.0, 0.8, -1.8)}, {"kind": "battery", "at": Vector3(7.0, 0.8, -1.8)}]},
	{"name": "BRIDGE", "parts": [{"kind": "bridge", "at": Vector3(0.0, 1.8, -3.6)}]},
]
## How far down the screen (relative z of the boss's centre) the boss sits, and how much
## closer it pushes after each section is destroyed.
const BOSS_Z := Z_TOP + 8.0
const BOSS_PUSH := 2.2


static func boss_parts() -> int:
	var n := 0
	for sec: Dictionary in BOSS_SECTIONS:
		n += sec.parts.size()
	return n


## Count of foes in the stage that can be shot down (for the results' kill rate).
static func stage_foes() -> int:
	var n := 0
	for w: Dictionary in STAGE:
		if w.kind == "boss":
			n += boss_parts()
		elif w.kind != "carrier":
			n += int(w.n)
	for sec: Dictionary in CARRIER_SECTIONS:
		n += 5 if sec.mounts.is_empty() else sec.mounts.size()
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
