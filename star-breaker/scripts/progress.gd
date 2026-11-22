class_name Progress
extends RefCounted
## Replay progress of the portrait game: each stage is played on three tiers (Normal, Nova,
## Supernova). On each tier the stages open one by one (clear a stage to open the next one on
## that tier), and a tier above Normal also needs the stage cleared on the tier below. Each tier
## of each stage holds four medals. Medals add up on a track of rewards (ship colour schemes for now).
## Saved in the game's save file, keyed by a stage's `id` ("w1s1"), so adding or reordering
## stages never mixes up progress.

## What each tier changes: enemy bullet speed, how often enemies fire, enemy hit points,
## ships per run and the score multiplier.
const TIERS := [
	{name = "Normal", bullet = 1.0, fire = 1.0, hp = 1.0, ships = 3, score = 1.0, color = "3ff0e0"},
	{name = "Nova", bullet = 1.2, fire = 1.3, hp = 1.5, ships = 3, score = 1.5, color = "ffb547"},
	{name = "Supernova", bullet = 1.4, fire = 1.6, hp = 2.0, ships = 2, score = 2.0, color = "ff4fa3"},
]

## The four medals of a tier, in the order of their bits. Each needs the stage cleared.
const MEDALS := ["sweep", "untouched", "breaker", "swift"]
const MEDAL_INFO := {
	sweep = {name = "Sweep", how = "Destroy 90% of enemies", color = "3ff0e0"},
	untouched = {name = "Untouched", how = "Take no hull damage", color = "f4f2ff"},
	breaker = {name = "Breaker", how = "Destroy every generator and wall", color = "ffb547"},
	swift = {name = "Swift", how = "Beat the boss under par time", color = "ff4fa3"},
}
const SWEEP_SHARE := 0.9
## Par time in seconds for each kind of stage end on Normal in world 1 (the part of the stage's
## `end` before ":"), about twice what a perfect bot takes (2026-11-18 measurement); scaled with
## the boss's hit points (world and tier). A stage end that isn't listed uses DEFAULT_PAR.
## A named world boss (an end with no ":", such as "prism") that isn't listed gets BOSS_PAR.
const PAR := {big = 12.0, twins = 15.0, giant = 24.0, bloom = 36.0,
	prism = 36.0, queen = 36.0, titan = 36.0, bastion = 36.0, heart = 36.0}
const BOSS_PAR := 36.0
const DEFAULT_PAR := 30.0

## Ship colour schemes: hull, dark trim, glow (canopy and lance) and engine flame. The first
## of each ship is its stock look.
const SCHEMES := {
	lance = [
		{id = "stock", name = "Stock", hull = "dfe8f2", dark = "56607a", glow = "4fe3d6", flame = ""},
		{id = "ember", name = "Ember", hull = "f2d6c4", dark = "7a3a2e", glow = "ff8a3d", flame = "ff6a2a"},
		{id = "violet", name = "Violet", hull = "d9d0ff", dark = "4a3a8a", glow = "b38cff", flame = "a070ff"},
		{id = "obsidian", name = "Obsidian", hull = "3a3648", dark = "1c1a26", glow = "ff4fa3", flame = "ff4fa3"},
		{id = "prism", name = "Prism", hull = "f4f2ff", dark = "8c7bff", glow = "3ff0e0", flame = "3ff0e0"},
	],
	warden = [
		{id = "stock", name = "Stock", hull = "dfe8f2", dark = "56607a", glow = "4fe3d6", flame = ""},
		{id = "moss", name = "Moss", hull = "d2e6c8", dark = "3e5a3a", glow = "a6ff5a", flame = "c8ff6a"},
		{id = "gold", name = "Gold", hull = "f6e2a8", dark = "6a5220", glow = "ffd24a", flame = "ffb547"},
		{id = "coral", name = "Coral", hull = "ffd6d0", dark = "8a3a4a", glow = "ff6f7f", flame = "ff4fa3"},
		{id = "prism", name = "Prism", hull = "f4f2ff", dark = "8c7bff", glow = "3ff0e0", flame = "3ff0e0"},
	],
}

## Schemes of the ships without a list of their own, and the medals each one needs.
const COMMON := [
	{id = "stock", name = "Stock", hull = "dfe8f2", dark = "56607a", glow = "4fe3d6", flame = ""},
	{id = "ember", name = "Ember", hull = "f2d6c4", dark = "7a3a2e", glow = "ff8a3d", flame = "ff6a2a"},
	{id = "moss", name = "Moss", hull = "d2e6c8", dark = "3e5a3a", glow = "a6ff5a", flame = "c8ff6a"},
	{id = "obsidian", name = "Obsidian", hull = "3a3648", dark = "1c1a26", glow = "ff4fa3", flame = "ff4fa3"},
	{id = "prism", name = "Prism", hull = "f4f2ff", dark = "8c7bff", glow = "3ff0e0", flame = "3ff0e0"},
]
const COMMON_AT := {ember = 8, moss = 24, obsidian = 40, prism = 72}

## The medal track: a reward unlocks once you hold `at` medals in total.
const TRACK := [
	{at = 2, ship = "lance", scheme = "ember"},
	{at = 6, ship = "warden", scheme = "moss"},
	{at = 12, ship = "lance", scheme = "violet"},
	{at = 20, ship = "warden", scheme = "gold"},
	{at = 32, ship = "lance", scheme = "obsidian"},
	{at = 48, ship = "warden", scheme = "coral"},
	{at = 72, ship = "lance", scheme = "prism"},
	{at = 72, ship = "warden", scheme = "prism"},
]

## stage id -> {m = [medal bits per tier], c = cleared tiers as bits}
var stages: Dictionary = {}
## ship -> chosen scheme id
var paint: Dictionary = {}
## Flux (soft currency) in the bank, and each ship's level (1 to MAX_LEVEL).
var flux := 0
var levels: Dictionary = {}


func _init() -> void:
	for k in VShips.ORDER:
		paint[k] = "stock"
		levels[k] = 1

## Ship levels: each one adds the same share of damage, up to double at MAX_LEVEL, so a
## levelled ship clears faster but Supernova still needs skill.
const MAX_LEVEL := 50
## Flux per 100 points scored (score already carries the tier's multiplier) and per new medal on
## each tier. A Normal stage pays about 150 to 300 flux.
const FLUX_PER_SCORE := 0.01
const MEDAL_FLUX := [25, 40, 60]


## What going from level `lv` to `lv + 1` costs: about 5 Normal stages buys level 10, and
## level 50 takes more than clearing everything once (the long tail the plan asks for).
static func level_cost(lv: int) -> int:
	return int(round(12.0 * pow(float(lv), 1.6) / 5.0)) * 5


## Damage multiplier of a ship at level `lv`: 1.0 at level 1, 2.0 at MAX_LEVEL.
static func power(lv: int) -> float:
	return 1.0 + float(clampi(lv, 1, MAX_LEVEL) - 1) / float(MAX_LEVEL - 1)


func level(ship: String) -> int:
	return clampi(int(levels.get(ship, 1)), 1, MAX_LEVEL)


## Spends flux on the next level of `ship`; false when maxed or short of flux.
func buy_level(ship: String) -> bool:
	var lv := level(ship)
	if lv >= MAX_LEVEL or flux < level_cost(lv):
		return false
	flux -= level_cost(lv)
	levels[ship] = lv + 1
	return true


## Banks a run's flux: its score's share plus a bonus for each new medal. Returns the amount.
func bank_run(score: int, t: int, new_medals: int) -> int:
	var f := int(floor(score * FLUX_PER_SCORE)) + new_medals * int(MEDAL_FLUX[clampi(t, 0, 2)])
	flux += f
	return f


static func stage_id(i: int) -> String:
	var st: Dictionary = VStage.STAGES[i]
	return String(st.get("id", "w1s%d" % (i + 1)))


static func tier(t: int) -> Dictionary:
	return TIERS[clampi(t, 0, TIERS.size() - 1)]


func _entry(id: String) -> Dictionary:
	if not stages.has(id):
		stages[id] = {m = [0, 0, 0], c = 0}
	return stages[id]


## Medal bits of stage `id` on tier `t` (bit k = MEDALS[k]).
func medals(id: String, t: int) -> int:
	return int(stages[id].m[t]) if stages.has(id) else 0


func has_medal(id: String, t: int, medal: String) -> bool:
	return medals(id, t) & (1 << MEDALS.find(medal)) != 0


func cleared(id: String, t: int) -> bool:
	return stages.has(id) and int(stages[id].c) & (1 << t) != 0


## Index of stage `id` in VStage.STAGES, or -1.
static func index_of(id: String) -> int:
	for i in VStage.STAGES.size():
		if stage_id(i) == id:
			return i
	return -1


## The furthest stage (index) cleared on tier `t`, or -1. Every stage up to the one after it is
## open on that tier: for a new save that is exactly "clear the previous stage", and a save from
## before the rule (stages could be played in any order) keeps every stage it has already reached.
func reach(t: int) -> int:
	for i in range(VStage.STAGES.size() - 1, -1, -1):
		if cleared(stage_id(i), t):
			return i
	return -1


## On Normal, stage `i` is open once the stage before it is cleared (stage 1 of world 1 is
## always open). Above Normal, a stage is open once it is cleared on the tier just below
## (Guillaume, 2026-11-21): Nova stage 5 needs Normal stage 5, not Nova stage 4. A stage already
## cleared on a tier stays open on it. Cleared means finished with ships left; medals don't matter.
func open(i: int, t: int) -> bool:
	t = clampi(t, 0, TIERS.size() - 1)
	if t <= 0:
		return i <= reach(0) + 1
	return cleared(stage_id(i), t) or cleared(stage_id(i), t - 1)


## How many stages are cleared on Normal.
func cleared_count() -> int:
	var n := 0
	for i in VStage.STAGES.size():
		if cleared(stage_id(i), 0):
			n += 1
	return n


## A ship opens once `VShips.KITS[ship].unlock` stages are cleared on Normal.
func ship_open(ship: String) -> bool:
	return cleared_count() >= int(VShips.KITS[ship].get("unlock", 0))


func unlocked(id: String, t: int) -> bool:
	var i := index_of(id)
	if i < 0:
		return t <= 0 or cleared(id, t) or cleared(id, t - 1)
	return open(i, t)


## The stage to play next on tier `t`: the first open stage not yet cleared there (the last
## stage once everything is cleared). -1 when nothing on that tier is open yet.
func next_stage(t: int) -> int:
	var first_open := -1
	for i in VStage.STAGES.size():
		if open(i, t):
			if not cleared(stage_id(i), t):
				return i
			first_open = i
	return first_open


## The highest tier of stage `id` that is open, at most `want`.
func best_open(id: String, want: int) -> int:
	var t := clampi(want, 0, TIERS.size() - 1)
	while t > 0 and not unlocked(id, t):
		t -= 1
	return t


static func bits(m: int) -> int:
	var n := 0
	for k in MEDALS.size():
		if m & (1 << k):
			n += 1
	return n


func total() -> int:
	var n := 0
	for id in stages:
		for m in stages[id].m:
			n += bits(int(m))
	return n


## How many medals there are to take across every stage and tier.
static func max_total() -> int:
	return VStage.STAGES.size() * TIERS.size() * MEDALS.size()


## The medals a run earned. `s` has: cleared, foes, foes_killed, breakables, broken, hits,
## boss_ticks (60 a second; -1 when the stage end never came), end (the stage end's kind), tier,
## and optionally boss_scale (how much tougher the world makes its bosses).
static func judge(s: Dictionary) -> Array:
	var got: Array = []
	if not s.cleared:
		return got
	if s.foes <= 0 or float(s.foes_killed) >= SWEEP_SHARE * float(s.foes) - 0.001:
		got.append("sweep")
	if s.hits == 0:
		got.append("untouched")
	if s.broken >= s.breakables:
		got.append("breaker")
	if s.boss_ticks >= 0 and s.boss_ticks <= par_ticks(String(s.end), int(s.tier), float(s.get("boss_scale", 1.0))):
		got.append("swift")
	return got


## Par time of a stage end on tier `t`, in ticks: tougher bosses get a bit more time.
static func par_ticks(end: String, t: int, boss_scale := 1.0) -> int:
	var sec: float = PAR.get(end.get_slice(":", 0), DEFAULT_PAR if end.contains(":") else BOSS_PAR)
	return int(sec * 60.0 * boss_scale * (1.0 + 0.8 * (float(tier(t).hp) - 1.0)))


## Records a run of stage `id` on tier `t`: `got` is the medal list from `judge`. Returns what
## changed: new medals, the tier it unlocked (-1 if none), the stage it opened on this tier
## (-1 if none) and the rewards it unlocked.
func record(id: String, t: int, is_cleared: bool, got: Array) -> Dictionary:
	var out := {new_medals = [], unlocked_tier = -1, unlocked_next = -1, rewards = []}
	if not is_cleared:
		return out
	var before := total()
	var i := index_of(id)
	var next_was_open := i < 0 or i + 1 >= VStage.STAGES.size() or open(i + 1, t)
	var e := _entry(id)
	var m := int(e.m[t])
	for g in got:
		var bit := 1 << MEDALS.find(g)
		if m & bit == 0:
			out.new_medals.append(g)
			m |= bit
	e.m[t] = m
	if int(e.c) & (1 << t) == 0:
		e.c = int(e.c) | (1 << t)
		if t + 1 < TIERS.size():
			out.unlocked_tier = t + 1
	if not next_was_open and open(i + 1, t):
		out.unlocked_next = i + 1
	var after := total()
	for r in TRACK:
		if before < int(r.at) and after >= int(r.at):
			out.rewards.append(r)
	return out


# ---------- the medal track and paint ----------

## A ship's colour schemes: its own list, or the shared one (`COMMON`) for the newer ships.
static func schemes(ship: String) -> Array:
	return SCHEMES.get(ship, COMMON)


static func scheme(ship: String, id: String) -> Dictionary:
	for s in schemes(ship):
		if s.id == id:
			return s
	return schemes(ship)[0]


static func reward_name(r: Dictionary) -> String:
	return "%s %s" % [scheme(r.ship, r.scheme).name, String(VShips.KITS[r.ship].name)]


## The medal count that unlocks a ship's scheme (0 for the stock look).
static func scheme_at(ship: String, id: String) -> int:
	for r in TRACK:
		if r.ship == ship and r.scheme == id:
			return int(r.at)
	if not SCHEMES.has(ship):
		return int(COMMON_AT.get(id, 0))
	return 0


func scheme_open(ship: String, id: String) -> bool:
	return total() >= scheme_at(ship, id)


func set_paint(ship: String, id: String) -> bool:
	if not scheme_open(ship, id):
		return false
	paint[ship] = id
	return true


func paint_of(ship: String) -> Dictionary:
	var id: String = paint.get(ship, "stock")
	if not scheme_open(ship, id):
		id = "stock"
	return scheme(ship, id)


## Recolours a ship model built by VShips (stock materials swapped for the scheme's).
static func apply_paint(model: Node, s: Dictionary) -> void:
	if s.is_empty() or s.id == "stock":
		return
	var M := Models.M
	var swap := {M.hull: Models.std(s.hull), M.hull_dark: Models.std(s.dark), M.lance: Models.std(s.glow, s.glow, 1.2)}
	if s.flame != "":
		var f: StandardMaterial3D = M.engine.duplicate()
		f.albedo_color = Color(Color(s.flame), M.engine.albedo_color.a)
		swap[M.engine] = f
	_swap(model, swap)


static func _swap(n: Node, swap: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var cur := mi.get_surface_override_material(0)
		if cur and swap.has(cur):
			mi.set_surface_override_material(0, swap[cur])
	for c in n.get_children():
		_swap(c, swap)


# ---------- save ----------

func load_from(cfg: ConfigFile) -> void:
	var s = cfg.get_value("progress", "stages", {})
	stages = {}
	if s is Dictionary:
		for id in s:
			var e = s[id]
			if e is Dictionary and e.get("m") is Array:
				var m: Array = [0, 0, 0]
				for t in mini(3, e.m.size()):
					m[t] = int(e.m[t])
				stages[String(id)] = {m = m, c = int(e.get("c", 0))}
	flux = maxi(0, int(cfg.get_value("progress", "flux", 0)))
	var lv = cfg.get_value("progress", "levels", {})
	if lv is Dictionary:
		for k in levels:
			if lv.has(k):
				levels[k] = clampi(int(lv[k]), 1, MAX_LEVEL)
	var p = cfg.get_value("progress", "paint", {})
	if p is Dictionary:
		for k in paint:
			if p.has(k):
				paint[k] = String(p[k])


func save_to(cfg: ConfigFile) -> void:
	cfg.set_value("progress", "stages", stages)
	cfg.set_value("progress", "paint", paint)
	cfg.set_value("progress", "flux", flux)
	cfg.set_value("progress", "levels", levels)
