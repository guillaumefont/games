class_name Sim
extends RefCounted
## The whole battle simulation, ported from the web version (world pixels, 32 per tile).
## Rendering, UI and audio are reached through `host`.

const T := 32
const MW := 64
const MH := 64
const TAU := PI * 2.0
const HN := MW * 2 + 1

var host  # main.gd
var time := 0.0
var ents: Array = []
var nid := 1
var terr := PackedByteArray()
var ore := PackedInt32Array()
var bmap := PackedInt32Array()
var vis := PackedByteArray()
var H := PackedFloat32Array()  # height grid, 2 samples per tile
var proj: Array = []
var parts: Array = []
var wrecks: Array = []  # Pact salvage: {id, type, team, x, y, ang, intact} left by destroyed vehicles
var wid := 1
var sel: Array = []
var over := false
var vis_t := 0.0
var ai_t := 2.0
var last_alert := -99.0
var ping = null  # {x,y,t}
var seed := 0
var stats := {"built": 0, "lost": 0, "killed": 0, "mined": 0}
var radio_done := {}   # radio cues already said this mission (radio_cue)
var mission = null
var strikes: Array = []
var fields: Array = []        # crystal shard fields on the ground: {x, y, r, life, max, team, dps, tick, seed}
var aura_tick := 0.0
var combat := 0.0
var teams: Array = []
var diff := "normal"
var delayed: Array = []
var astar := AStarGrid2D.new()
var hums: Array = [[], []]    # what sends each team's Hum (Gardens, a Carillon)
var risers: Array = []        # the Hollowing: [time, x, y, team] of the dead about to rise as Wretches
var domes: Array = [[], []]   # live Shield Domes of each team
var ai_aim := {}   # Vanguard AI: the ore tile its next Signal Mast walks toward
var ai_dry := {}   # AI teams that found no berth for a shipyard
var astar_w := AStarGrid2D.new()  # boats: open water only
var astar_h := AStarGrid2D.new()  # hovercraft and jump troops: land or water
var by_id := {}
# mission state
var p0 := Vector2i(9, 53)     # player start (tile)
var e0 = null                 # enemy base (Vector2i) or null
var theme := "temperate"
var dusk := false
var gi := 0                   # current goal
var g_t0 := 0.0               # when the current goal started
var gst := {}                 # current goal's progress (held seconds, trucks through, aurite at start)
var wst := {}                 # wave state of the current wave plan
var ev_done := {}
var m_t := 1.0
var end_why := ""
var lvl := "normal"            # campaign difficulty (D.LEVELS)
var cine := false              # a cutscene runs on this sim: no AI, no goals or win checks, the whole map in view
## Tutorial hooks (scripts/tutorial.gd): tut_cb(kind, a, b) hears kills, heals, units trained, upgrades and launches.
var tut_cb := Callable()
var last_hurt := -99.0         # when one of the player's things last took damage (tutorial cards wait for calm)
var raids: Array = []          # ids of the enemy units each scripted event sent, one array per event
var vit := PackedByteArray()      # living fields: vitality of each tile's ore, 0..100 (D.FIELD)
var ore0 := PackedInt32Array()    # ore each tile started with (what it can regrow to)
var touch_t := PackedFloat32Array()  # when ore was last taken from each tile
var field_t := 0.0

func _tut(kind: String, a = null, b = null) -> void:
	if tut_cb.is_valid(): tut_cb.call(kind, a, b)

# ---------------- util ----------------
static func _u32(v: int) -> int:
	return v & 0xFFFFFFFF

static func _imul(a: int, b: int) -> int:
	a = a & 0xFFFFFFFF
	b = b & 0xFFFFFFFF
	var lo := (a & 0xFFFF) * b
	var hi := (((a >> 16) * b) & 0xFFFF) << 16
	return (lo + hi) & 0xFFFFFFFF

static func hash2(x: int, y: int, s: int) -> float:
	var h := _u32(_imul(x, 374761393) + _imul(y, 668265263) + _imul(s, 1442695041))
	h = _imul(h ^ (h >> 13), 1274126177)
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0

static func vnoise(x: float, y: float, s: int) -> float:
	var xi := int(floor(x)); var yi := int(floor(y))
	var xf := x - xi; var yf := y - yi
	var u := xf * xf * (3 - 2 * xf); var v := yf * yf * (3 - 2 * yf)
	var a := hash2(xi, yi, s); var b := hash2(xi + 1, yi, s); var c := hash2(xi, yi + 1, s); var d := hash2(xi + 1, yi + 1, s)
	return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

static func fbm(x: float, y: float, s: int) -> float:
	return vnoise(x, y, s) * 0.6 + vnoise(x * 2, y * 2, s + 7) * 0.28 + vnoise(x * 4, y * 4, s + 13) * 0.12

static func turn_to(a: float, b: float, m: float) -> float:
	var d := fposmod(b - a + PI, TAU) - PI
	if abs(d) <= m: return b
	return a + sign(d) * m

static func ang_diff(a: float, b: float) -> float:
	return abs(fposmod(b - a + PI, TAU) - PI)

static func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < MW and y < MH

func walk(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < MW and y < MH and terr[y * MW + x] < D.ROCK and bmap[y * MW + x] == 0

## Movement classes (UN "mob"): 0 land, 1 water (boats), 2 land or water (hovercraft).
func passable(m: int, x: int, y: int) -> bool:
	if m == 0: return walk(x, y)
	if x < 0 or y < 0 or x >= MW or y >= MH or bmap[y * MW + x] != 0: return false
	var t: int = terr[y * MW + x]
	if m == 1: return t == D.WATER
	return t == D.WATER or t < D.ROCK

func mob(u: Ent) -> int:
	return 0 if u.d.air else int(u.d.get("mob", 0))

func grid(m: int) -> AStarGrid2D:
	return astar if m == 0 else (astar_w if m == 1 else astar_h)

## True when there is open water next to this footprint (a shipyard needs it).
func water_beside(tx: int, ty: int, w: int, h: int) -> bool:
	for y in range(ty - 1, ty + h + 1):
		for x in range(tx - 1, tx + w + 1):
			if inb(x, y) and terr[y * MW + x] == D.WATER: return true
	return false

func t_idx(e) -> int:
	return clampi(int(e.y / T), 0, MH - 1) * MW + clampi(int(e.x / T), 0, MW - 1)

func h_at(x: float, y: float) -> float:
	if H.is_empty(): return 0.0
	var gx: float = clamp(x / T * 2.0, 0.0, HN - 1.001)
	var gy: float = clamp(y / T * 2.0, 0.0, HN - 1.001)
	var i := int(gx); var j := int(gy)
	var fx := gx - i; var fy := gy - j
	return (H[j * HN + i] * (1 - fx) + H[j * HN + i + 1] * fx) * (1 - fy) + (H[(j + 1) * HN + i] * (1 - fx) + H[(j + 1) * HN + i + 1] * fx) * fy

func ud(e: Ent) -> Dictionary:
	return e.d

func is_air(e: Ent) -> bool:
	return e.kind == "u" and e.d.air

## A shared type name in this team's own army (the Pact's "barracks" is its Muster Hall), for factions whose rule "swap" is on.
func tr_t(team: int, t: String) -> String:
	if teams.size() <= team or not D.rule(teams[team].fac, "swap"): return t
	var s := D.sub(teams[team].fac, t)
	return s if s != "" else t

func avail(team: int, type: String) -> bool:
	var d: Dictionary = D.def_of(type)
	if d.get("retired", false): return false
	if d.fac != "" and teams.size() > team and d.fac != teams[team].fac: return false
	if teams.size() > team and d.no.has(teams[team].fac): return false
	if mission:
		var ts = mission.tech if team == 0 else mission.aiTech
		if ts != null and not (ts as Array).has(type) and not (ts as Array).any(func(o): return tr_t(team, o) == type): return false
	return true

func can_hit(sd: Dictionary, t: Ent) -> bool:
	var w: String = sd.weapon
	if w == "": return false
	if sd.get("bldOnly", false) and t.kind != "b": return false
	if w == "toll" and not (t.kind == "u" and t.d.armor == "inf" and not t.d.air): return false
	if t.kind == "u" and t.d.air: return D.AIRW.has(w)
	return not sd.antiAir

# ---------------- map ----------------
func gen_map(sd: int) -> void:
	var s := sd % 9973
	var off := func(v: float) -> float: return 3 * sin((v - 63) * 0.09) + 1.5 * sin((v - 63) * 0.23)
	for y in MH:
		for x in MW:
			if y < x: continue
			var n1 := fbm(x / 8.0, y / 8.0, s + 1); var n2 := fbm(x / 5.0, y / 5.0, s + 2)
			var t := D.GRASS
			if n2 > 0.6: t = D.DIRT
			if n1 > 0.68: t = D.ROCK
			var sv := x + y
			var dv: float = abs((y - x) - off.call(float(sv))) / sqrt(2.0)
			if dv < 1.6: t = D.WATER
			elif dv < 2.6 and t != D.ROCK: t = D.SAND
			for f in [31, 63, 95]:
				if abs(sv - f) <= 3 and (t == D.WATER or t == D.ROCK): t = D.SAND
			terr[y * MW + x] = t
	var clear := func(cx: int, cy: int, r: int) -> void:
		for y in range(cy - r, cy + r + 1):
			for x in range(cx - r, cx + r + 1):
				if not inb(x, y) or y < x: continue
				if Vector2(x - cx, y - cy).length() <= r:
					var i := y * MW + x
					if terr[i] >= D.ROCK: terr[i] = D.GRASS
	clear.call(D.P0.x, D.P0.y, 7)
	var fields := [[18, 52, 3.4], [9, 42, 3.0], [22, 38, 3.2], [8, 20, 3.6], [31, 57, 2.8]]
	for f in fields:
		var fx: int = f[0]; var fy: int = f[1]; var r: float = f[2]
		clear.call(fx, fy, int(ceil(r)))
		for y in range(fy - 4, fy + 5):
			for x in range(fx - 4, fx + 5):
				if not inb(x, y) or y < x: continue
				var dd := Vector2(x - fx, y - fy).length() + (hash2(x, y, s + 5) - 0.5) * 1.3
				var i := y * MW + x
				if dd < r and terr[i] < D.ROCK:
					ore[i] = int(round((160 + (1 - dd / r) * 340) / 20.0)) * 20
					terr[i] = D.DIRT
	for y in MH:
		for x in MW:
			if y < x:
				var i := y * MW + x; var j := (MH - 1 - y) * MW + (MW - 1 - x)
				terr[i] = terr[j]; ore[i] = ore[j]
	# connectivity check base to base
	var seen := PackedByteArray(); seen.resize(MW * MH)
	var q := [D.P0.y * MW + D.P0.x]; seen[q[0]] = 1
	while q.size() > 0:
		var c: int = q.pop_back()
		var cx := c % MW; var cy := c / MW
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dxy[0]; var ny: int = cy + dxy[1]
			if not inb(nx, ny): continue
			var n := ny * MW + nx
			if seen[n] or terr[n] >= D.ROCK: continue
			seen[n] = 1; q.append(n)
	if not seen[(MH - 1 - D.P0.y) * MW + (MW - 1 - D.P0.x)]:
		var ax := MW - 1 - D.P0.x; var ay := MH - 1 - D.P0.y
		for k in 201:
			var f := k / 200.0
			var x := int(round(D.P0.x + (ax - D.P0.x) * f)); var y := int(round(D.P0.y + (ay - D.P0.y) * f))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if not inb(x + dx, y + dy): continue
					var i := (y + dy) * MW + x + dx
					if terr[i] == D.ROCK: terr[i] = D.GRASS
					elif terr[i] == D.WATER: terr[i] = D.SAND

func gen_heights(sd: int) -> void:
	H = PackedFloat32Array(); H.resize(HN * HN)
	for j in HN:
		for i in HN:
			var xs := [(i - 1) / 2] if i % 2 else [i / 2 - 1, i / 2]
			var ys := [(j - 1) / 2] if j % 2 else [j / 2 - 1, j / 2]
			var all_r := true; var all_w := true; var any_r := false; var any_w := false
			for yy in ys:
				for xx in xs:
					var t: int = terr[clampi(yy, 0, MH - 1) * MW + clampi(xx, 0, MW - 1)]
					if t == D.ROCK: any_r = true
					else: all_r = false
					if t == D.WATER: any_w = true
					else: all_w = false
			var n := fbm(i / 7.0, j / 7.0, sd + 21)
			var h: float
			if all_r: h = 0.6 + n * 1.3 + (0.3 if (i % 2 and j % 2) else 0.0) + hash2(i, j, sd + 3) * 0.25
			elif all_w: h = -0.62 + hash2(i, j, sd + 4) * 0.1
			elif any_w: h = -0.1
			else: h = (n - 0.5) * 0.12 + (0.07 if any_r else 0.0)
			H[j * HN + i] = h

func init_astar() -> void:
	astar.region = Rect2i(0, 0, MW, MH)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for g in [astar_w, astar_h]:
		g.region = astar.region; g.cell_size = astar.cell_size; g.diagonal_mode = astar.diagonal_mode
		g.default_compute_heuristic = astar.default_compute_heuristic; g.default_estimate_heuristic = astar.default_estimate_heuristic
		g.update()
	for y in MH:
		for x in MW:
			var t: int = terr[y * MW + x]
			astar.set_point_solid(Vector2i(x, y), t >= D.ROCK)
			astar_w.set_point_solid(Vector2i(x, y), t != D.WATER)
			astar_h.set_point_solid(Vector2i(x, y), t == D.ROCK)
			if t == D.SAND: astar.set_point_weight_scale(Vector2i(x, y), 1.15)

func _sync_solid(tx: int, ty: int, w: int, h: int) -> void:
	for y in range(ty, ty + h):
		for x in range(tx, tx + w):
			if inb(x, y):
				astar.set_point_solid(Vector2i(x, y), not walk(x, y))
				astar_w.set_point_solid(Vector2i(x, y), not passable(1, x, y)); astar_h.set_point_solid(Vector2i(x, y), not passable(2, x, y))

# ---------------- setup ----------------
func new_game(d: String, opt: Dictionary) -> void:
	var M = opt.get("mission", null)
	mission = M
	cine = opt.get("cine", false)
	ai_dry = {}; ai_aim = {}; risers = []; hums = [[], []]
	lvl = opt.get("level", "normal") if M else "normal"
	diff = (D.DIFF_ORDER[clampi(D.DIFF_ORDER.find(M.diff) + D.LEVELS[lvl].shift, 0, D.DIFF_ORDER.size() - 1)]) if M else d
	seed = M.seed if M else opt.get("seed", int(Time.get_ticks_msec() % 100000) + randi() % 1000)
	var pf: String = M.fac if M else opt.get("fac", "vanguard")
	var ef: String = opt.get("enemy", "") if not M else M.efac   # a mission may name its enemy army (campaign III fights both)
	if ef == "random":
		var others: Array = D.FAC_ORDER.filter(func(f): return f != pf)
		ef = others[randi() % others.size()]
	if ef == "" or ef == pf or not D.FACS.has(ef): ef = "ashen" if pf == "vanguard" else "vanguard"
	time = 0.0; ents = []; nid = 1; proj = []; parts = []; wrecks = []; sel = []; over = false; vis_t = 0.0; ai_t = 2.0; fields = []; aura_tick = 0.0
	last_alert = -99.0; ping = null; stats = {"built": 0, "lost": 0, "killed": 0, "mined": 0}; radio_done = {}; strikes = []; combat = 0.0; delayed = []; by_id = {}
	last_hurt = -99.0; raids = []
	terr = PackedByteArray(); terr.resize(MW * MH)
	ore = PackedInt32Array(); ore.resize(MW * MH)
	bmap = PackedInt32Array(); bmap.resize(MW * MH)
	vis = PackedByteArray(); vis.resize(MW * MH)
	teams = []
	for id in [0, 1]:
		var prod := {}
		for c in D.CAT_ORDER: prod[c] = {"cur": "", "prog": 0.0, "paid": 0.0, "ready": false, "queue": [], "left": 0}
		teams.append({"id": id, "credits": float((M.credits[id] * (D.LEVELS[lvl].credits if id == 1 else 1.0)) if M else D.DIFF[diff].start), "ai": id == 1,
			"fac": pf if id == 0 else ef, "pmade": 0, "pused": 0, "rally": null,
			"wave": 5, "waveT": 0, "wn": 0, "prod": prod, "noFundsT": 0.0, "earned": 0.0})
	if D.set_team_colors(teams[0].fac, teams[1].fac): Models.cache.clear()
	gi = 0; g_t0 = 0.0; gst = {}; wst = {}; ev_done = {}; m_t = 1.0; end_why = ""
	var A := Vector2i(MW - 1 - D.P0.x, MH - 1 - D.P0.y)
	if M:
		p0 = Vector2i(M.map.p0[0], M.map.p0[1])
		e0 = Vector2i(M.map.e0[0], M.map.e0[1]) if M.map.get("e0", null) != null else null
		theme = M.map.get("theme", "temperate"); dusk = M.map.get("dusk", false)
		MapGen.generate(self, M.map, seed, mission_keys(M))
	else:
		p0 = D.P0; e0 = A; theme = "temperate"; dusk = false
		gen_map(seed)
	gen_heights(seed)
	init_fields()
	init_astar()
	if M and opt.get("bare", false): gi = 99   # a cutscene's own cast, no mission units or goal marks
	elif M: mission_setup(M)
	if M: light_up()
	else:
		for pair in [[0, D.P0], [1, A]]:
			var tm: int = pair[0]; var p: Vector2i = pair[1]
			add_building(tm, "hq", p.x - 1, p.y - 1)
			var dir := 1 if tm == 0 else -1
			for k in 3: spawn_unit(tm, D.sub(teams[tm].fac, "rifle"), (p.x + dir * (2 + k)) * T + 16, (p.y - dir * 3) * T + 16)
			spawn_unit(tm, D.FACS[teams[tm].fac].lv, (p.x + dir * 3) * T + 16, (p.y - dir * 2) * T + 16)
	var er: Vector2i = e0 if e0 != null else Vector2i(MW - 1 - p0.x, MH - 1 - p0.y)
	teams[1].rally = Vector2((er.x - 6) * T, (er.y + 6) * T)
	update_vision()
	for e in ents:
		if e.kind == "b" and e.team == 0: e.born = -9.0

## Tiles that must be open ground and reachable: objectives, posts, captives, spawn points.
func mission_keys(M: Dictionary) -> Array:
	var k: Array = []
	for g in M.goals:
		if g.at != null: k.append([g.at[0], g.at[1], g.r + 0.5])
		if g.zone != null: k.append([g.zone[0], g.zone[1], 2.5])
		for z in g.zones: k.append([z[0], z[1], g.r + 0.5])
		if g.waves != null:
			for f in g.waves.from: k.append([f[0], f[1], 2.0])
		if g.done != null:
			if g.done.has("base"): k.append([g.done.base[0], g.done.base[1], 5.0])
			for sp in g.done.get("spawn", []): k.append([sp.at[0], sp.at[1], 2.0])
	for p in M.posts: k.append([p.at[0], p.at[1], 3.5])
	for c in M.captives: k.append([c.at[0], c.at[1], 2.5])
	for ev in M.events:
		for sp in ev.get("spawn", []): k.append([sp.at[0], sp.at[1], 2.0])
	return k

func mission_setup(M: Dictionary) -> void:
	if M.phq:
		add_building(0, "hq", p0.x - 1, p0.y - 1)
		if M.pbase.size(): prebuild(0, M.pbase)
	var c := p0 + (Vector2i(3, -3) if M.phq else Vector2i.ZERO)
	for h in M.pheroes:
		for u in squad(0, [[h, 1]], c.x, c.y): u.tag = "hero"
	if M.punits.size(): squad(0, M.punits, c.x, c.y)
	for u in squad(0, M.pvip, c.x, c.y): u.tag = "vip"
	if e0 != null and M.ehq != "":
		add_building(1, M.ehq, e0.x - 1, e0.y - 1)
		if M.ebase.size(): prebuild(1, M.ebase)
	if e0 != null:
		var ec: Vector2i = e0 + Vector2i(-3, 3)
		for h in M.eheroes:
			for u in squad(1, [[h, 1]], ec.x, ec.y): u.tag = "hero"
		if M.eunits.size(): squad(1, M.eunits, ec.x, ec.y)
	for pst in M.posts:
		var tm: int = pst.get("team", 1)
		for t in pst.get("b", []):
			var b := place_near(tm, t, pst.at[0], pst.at[1])
			if b != null:
				b.tag = pst.get("tag", ""); b.born = -9.0
		for u in squad(tm, pst.get("u", []), pst.at[0], pst.at[1]):
			u.post = true
			u.guard = Vector2(u.x, u.y)
	for cp in M.captives:
		for u in squad(0, cp.u, cp.at[0], cp.at[1]):
			u.captive = true; u.tag = "captive"; u.ang = randf() * TAU
	if M.swCh > 0:
		for e in ents:
			if e.team == 1 and e.kind == "b" and e.d.sw: e.ch = M.swCh
	calc_power()

## Puts a building on free open ground as close as possible to a tile (enemy posts, mission bases).
func place_near(team: int, type: String, cx: int, cy: int) -> Ent:
	var d: Dictionary = D.BLD[type]; var best = null; var bs := 1e9
	for ty in range(cy - 7, cy + 8):
		for tx in range(cx - 7, cx + 8):
			var ok := true
			for y in range(ty - 1, ty + d.h + 1):
				for x in range(tx - 1, tx + d.w + 1):
					var inside: bool = x >= tx and x < tx + d.w and y >= ty and y < ty + d.h
					if not inb(x, y):
						if inside: ok = false
						continue
					var i := y * MW + x
					if bmap[i]: ok = false
					elif inside and (terr[i] >= D.ROCK or ore[i] > 0): ok = false
				if not ok: break
			if not ok: continue
			var sc := Vector2(tx + d.w / 2.0 - cx, ty + d.h / 2.0 - cy).length() + randf() * 0.5
			if sc < bs: bs = sc; best = Vector2i(tx, ty)
	if best == null: return null
	return add_building(team, type, best.x, best.y)

func find_hq(team: int) -> Ent:
	for e in ents:
		if e.alive and e.team == team and e.kind == "b" and e.type == "hq": return e
	for e in ents:
		if e.alive and e.team == team and e.kind == "b": return e
	return null

func prebuild(team: int, list: Array) -> void:
	var hq := find_hq(team)
	if not hq: return
	if team == 0: update_vision()
	var f := fac_of(team)
	for t in list:
		if D.rule(f, "swap") and D.FACS[f].get("sub", {}).has(t):
			var st := D.sub(f, t)
			if st == "" or (D.BLD.has(st) and D.BLD[st].grow and t != "refinery"): continue   # no such thing in this army
		var sp = ai_spot(team, t, hq)
		if sp == null and D.rule(fac_of(team), "place") == "signal":
			# a Vanguard outpost with no Signal for this prefab yet: Masts first (walking out to a field for a drill)
			for k in 4:
				var tt := tr_t(team, t)
				if D.BLD[tt].pump > 0 and in_signal(team, hq.x / T, hq.y / T):
					var aim = ai_ore(team, hq)
					if aim != null: ai_aim[team] = aim
				var ms = ai_spot(team, "sigmast", hq) if ai_aim.has(team) else null
				var m: Ent = add_building(team, "sigmast", ms.x, ms.y) if ms != null else place_near(team, "sigmast", hq.tx + hq.w / 2, hq.ty + hq.h + 1)
				ai_aim.erase(team)
				if m == null: break
				m.born = -9.0
				sp = ai_spot(team, t, hq)
				if sp != null: break
		if sp != null:
			var b := add_building(team, t, sp.x, sp.y)
			b.born = -9.0
		if team == 0: update_vision()

func squad(team: int, list: Array, cx: int, cy: int) -> Array:
	var out: Array = []
	for pair in list:
		for k in pair[1]:
			var sl := slots_around(cx, cy, 12 + k)
			var p: Vector2i = sl[randi() % sl.size()] if sl.size() else Vector2i(cx, cy)
			out.append(spawn_unit(team, pair[0], p.x * T + 16, p.y * T + 16))
	return out

# ---------------- entities ----------------
func add_building(team: int, type: String, tx: int, ty: int) -> Ent:
	type = tr_t(team, type)
	var d: Dictionary = D.BLD[type]
	var b := Ent.new()
	b.id = nid; nid += 1
	b.kind = "b"; b.type = type; b.d = d; b.team = team; b.tx = tx; b.ty = ty; b.w = d.w; b.h = d.h
	b.x = (tx + d.w / 2.0) * T; b.y = (ty + d.h / 2.0) * T; b.hp = d.hp; b.max_hp = d.hp
	b.tang = -PI / 4 if team == 0 else PI * 0.75
	b.seen = team == 0; b.r = max(d.w, d.h) * T / 2.0; b.born = time
	if d.grow: b.pods = 1
	b.sh_max = float(d.sh) + (500.0 if type == "hq" and fac_of(team) == "vanguard" else 0.0); b.sh = b.sh_max
	for y in range(ty, ty + d.h):
		for x in range(tx, tx + d.w): bmap[y * MW + x] = b.id
	_sync_solid(tx, ty, d.w, d.h)
	ents.append(b); by_id[b.id] = b
	for u in ents:
		if u.kind != "u" or not u.alive or u.d.air: continue
		var ux := int(u.x / T); var uy := int(u.y / T)
		if ux >= tx and ux < tx + d.w and uy >= ty and uy < ty + d.h:
			var n = nearest_walk(ux, uy, ux, uy + d.h)
			if n != null: u.x = n.x * T + 16; u.y = n.y * T + 16
			u.path = []
	if d.dock:
		var u := spawn_unit(team, "harv", (tx + d.w / 2) * T + 16, (ty + d.h) * T + 16)
		u.hs = "find"
	if d.sw:
		b.ch = 0.0
		if team == 1 and time > 1:
			host.toast("Warning: enemy " + d.name + " detected", "warn"); host.sfx("alert")
	calc_power()
	host.on_world_changed()
	return b

func spawn_unit(team: int, type: String, x: float, y: float) -> Ent:
	type = tr_t(team, type)
	var tx := int(x / T); var ty := int(y / T)
	var d: Dictionary = D.UN[type]
	if d.air:
		tx = clampi(tx, 0, MW - 1); ty = clampi(ty, 0, MH - 1)
	elif not passable(int(d.get("mob", 0)), tx, ty):
		var n = nearest_walk(tx, ty, tx, ty, int(d.get("mob", 0)))
		if n != null: tx = n.x; ty = n.y
	var u := Ent.new()
	u.id = nid; nid += 1
	u.kind = "u"; u.type = type; u.d = d; u.team = team; u.x = tx * T + 16; u.y = ty * T + 16
	u.hp = d.hp; u.max_hp = d.hp; u.ang = -PI / 2 if team == 0 else PI / 2; u.tang = u.ang
	u.scan = randf() * 0.4; u.hs = "find" if d.harv else ""; u.r = d.r
	u.sh_max = float(d.sh); u.sh = u.sh_max
	ents.append(u); by_id[u.id] = u
	return u

func calc_power() -> void:
	for t in teams: t.pmade = 0; t.pused = 0
	for b in ents:
		if b.kind != "b" or not b.alive or b.cold: continue
		var p: int = b.d.pwr
		if p > 0: teams[b.team].pmade += p
		else: teams[b.team].pused -= p
	calc_signal()

## Vanguard Signal: its buildings only work within reach of the Yard or a Signal Mast. Outside it they go dark.
func calc_signal() -> void:
	calc_hum()
	domes = [[], []]
	for b in ents:
		if b.kind != "b" or not b.alive: continue
		var was: bool = b.dark
		b.dark = D.rule(fac_of(b.team), "place") == "signal" and b.d.signal <= 0 and not in_signal(b.team, b.x / T, b.y / T)
		if b.dark != was and time > 0.5 and b.team == 0 and host: host.toast(b.d.name + (" lost Signal" if b.dark else " back in Signal"), "warn" if b.dark else "")
		if b.d.dome > 0 and b.team < 2: domes[b.team].append(b)

## Mission start: any Vanguard building the map put outside Signal gets a Mast beside it, so nothing starts dark.
func light_up() -> void:
	for pass_n in 6:
		var dark: Ent = null
		for b in ents:
			if b.alive and b.kind == "b" and b.dark and b.d.kit == 0: dark = b; break
		if dark == null: return
		var m := place_near(dark.team, "sigmast", dark.tx + dark.w / 2, dark.ty + dark.h / 2)
		if m == null: return
		m.born = -9.0

## The Hum: the Choir's ground, sung by its Gardens (wider as they age), its first Garden and a Carillon on the march.
func calc_hum() -> void:
	hums = [[], []]
	for e in ents:
		if e.alive and e.team < 2 and e.d.hum > 0 and D.rule(fac_of(e.team), "place") == "hum": hums[e.team].append(e)

## True when this point (pixels) is inside the team's Hum.
func in_hum(team: int, x: float, y: float) -> bool:
	for e in hums[team]:
		if e.alive and Vector2(e.x - x, e.y - y).length() <= e.d.hum * T: return true
	return false

## True when this tile-space point is inside the team's Signal.
func in_signal(team: int, cx: float, cy: float) -> bool:
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and b.d.signal > 0 and Vector2(b.x / T - cx, b.y / T - cy).length() <= b.d.signal: return true
	return false

## True when this army has nothing that stands in for the shared type (its sub is "").
func lacks(team: int, t: String) -> bool:
	var f := fac_of(team)
	return D.rule(f, "swap") and D.FACS[f].get("sub", {}).get(t, "x") == ""

func low_power(t: int) -> bool:
	return uses_power(t) and teams[t].pused > teams[t].pmade

# ---------------- faction rules (D.RULES) ----------------
func fac_of(team: int) -> String:
	return teams[team].fac if teams.size() > team else "vanguard"

func uses_power(team: int) -> bool:
	return D.rule(fac_of(team), "power")

## The building type that makes this team's units of a category.
func producer(team: int, cat: String) -> String:
	return D.producer(fac_of(team), cat)

## The building a unit comes out of: its own "from" (a Slipway for boats), else its category's producer.
func unit_from(team: int, type: String) -> String:
	var d: Dictionary = D.UN[type]
	return d.from if d.from != "" else producer(team, d.cat)

## Unit cap (only for factions with "cap"): 0 means no cap.
func cap_max(team: int) -> int:
	if not D.rule(fac_of(team), "cap"): return 0
	var n := 0
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and not b.dark: n += int(b.d.capAdd)
	return n

## Cap used by living units plus the ones being trained.
func cap_used(team: int) -> int:
	var n := 0
	for u in ents:
		if u.alive and u.kind == "u" and u.team == team:
			n += int(u.d.capCost)
			for c in u.cargo: n += int(D.UN[c].capCost) * int(D.UN[c].pack)   # still on the dropship
	for c in teams[team].prod:
		var q: Dictionary = teams[team].prod[c]
		if c != "bld" and q.cur != "": n += int(D.UN[q.cur].capCost) * int(D.UN[q.cur].pack)
	return n

## True when the team's cap has no room for one more of this unit (always false without a cap).
func cap_full(team: int, type: String, queued_in := false) -> bool:
	var mx := cap_max(team)
	if not D.rule(fac_of(team), "cap"): return false
	var c: int = int(D.UN[type].capCost) * int(D.UN[type].pack)
	var used := cap_used(team) - (c if queued_in else 0)
	return used + c > mx

# ---------------- living fields (D.FIELD) ----------------
func init_fields() -> void:
	vit = PackedByteArray(); vit.resize(MW * MH)
	ore0 = ore.duplicate()
	touch_t = PackedFloat32Array(); touch_t.resize(MW * MH)
	field_t = 0.0
	for i in MW * MH:
		if ore[i] > 0: vit[i] = 100

## A tile that held ore and has been killed: no ore, never regrows.
func field_dead(i: int) -> bool:
	return ore0[i] > 0 and vit[i] == 0

## Takes up to n ore from tile i for an earner with this drain and returns what it got.
func take_ore(i: int, n: int, drain: float) -> int:
	var take := mini(n, ore[i])
	if take <= 0: return 0
	ore[i] -= take; touch_t[i] = time
	if drain != 0.0 and ore0[i] > 0:
		vit[i] = clampi(int(round(vit[i] - drain * take / float(ore0[i]))), 0, 100)
		if vit[i] == 0: ore[i] = 0
	return take

func upd_field_life(dt: float) -> void:
	field_t -= dt
	if field_t > 0: return
	field_t = D.FIELD.tick
	var changed := false
	for i in MW * MH:
		if ore0[i] <= 0 or vit[i] == 0 or time - touch_t[i] < D.FIELD.rest: continue
		var cap := int(ore0[i] * vit[i] / 100.0)
		if ore[i] < cap:
			var was := ore[i]
			ore[i] = mini(cap, ore[i] + maxi(1, int(ore0[i] * D.FIELD.ore)))
			if was == 0: changed = true
		if vit[i] < 100 and randf() < D.FIELD.vit: vit[i] += 1
	if changed and host: host.on_world_changed()

func count(team: int, type: String) -> int:
	type = tr_t(team, type)
	var n := 0
	if type == "bloom" or type == "cathedral":
		# an aged Garden counts as these
		for e in ents:
			if e.alive and e.team == team and e.kind == "b" and e.d.grow and e.lv >= (2 if type == "bloom" else 3): n += 1
		return n
	for e in ents:
		if e.alive and e.team == team and e.type == type: n += 1
	return n

func has_req(team: int, req: Array) -> bool:
	for r in req_of(team, req):
		if count(team, r) == 0: return false
	return true

## Requirements in the team's own buildings (the Choir's garden stands in for a refinery).
func req_of(team: int, req: Array) -> Array:
	if teams.size() <= team: return req
	var f: String = teams[team].fac
	# a shared building the faction has no stand-in for ("comms" for the Pact) is simply not required
	return req.map(func(r): return D.sub(f, r) if D.sub(f, r) != "" else ("" if D.rule(f, "swap") and D.FACS[f].get("sub", {}).has(r) else r)).filter(func(r): return r != "")

## One-of-a-kind units (the Cantor): true when one is alive or already ordered.
func at_limit(team: int, type: String) -> bool:
	var d: Dictionary = D.def_of(type)
	if d.lim <= 0 or teams.size() <= team: return false
	var n := count(team, type)
	if d.has("cat") and teams[team].prod.has(d.cat):
		var q: Dictionary = teams[team].prod[d.cat]
		n += q.queue.count(type) + (1 if q.cur == type else 0)
	return n >= d.lim

func dist_to_ent(ax: float, ay: float, b) -> float:
	if b.kind == "b":
		var x0: float = b.tx * T; var y0: float = b.ty * T
		var cx: float = clamp(ax, x0, x0 + b.w * T); var cy: float = clamp(ay, y0, y0 + b.h * T)
		return Vector2(ax - cx, ay - cy).length()
	return max(0.0, Vector2(ax - b.x, ay - b.y).length() - b.r)

## Burrowed or cloaked, and nothing has sniffed it out: cannot be seen or picked as a target.
func hid(e: Ent) -> bool:
	return (e.under or e.cloak) and e.reveal_t < time

func visible_to_player(e: Ent) -> bool:
	if e.team == 0: return true
	if e.kind == "u" and hid(e): return false
	return vis[t_idx(e)] == 2 if e.kind == "u" else e.seen

# ---------------- terrain-aware fire ----------------
## Height of the muzzle above the ground, and of the point a shooter aims at.
func muzzle_h(s: Ent) -> float:
	if s.kind == "b": return D.BH[s.type] * 0.75
	return D.ALT if s.d.air else D.UH[s.type] * 0.6

func aim_h(t: Ent) -> float:
	if t.kind == "b": return D.BH[t.type] * 0.5
	return D.ALT + 0.05 if t.d.air else D.UH[t.type] * 0.5

## True when no hill sits between the shooter and the target.
func line_clear(ax: float, ay: float, ha: float, bx: float, by: float, hb: float) -> bool:
	var L := Vector2(bx - ax, by - ay).length() / T
	var n := int(L * 3) + 1
	for i in range(1, n):
		var f := float(i) / n
		var px := ax + (bx - ax) * f; var py := ay + (by - ay) * f
		if h_at(px, py) > ha + (hb - ha) * f + 0.03: return false
	return true

func fire_clear(s: Ent, t: Ent) -> bool:
	var w: String = s.d.weapon
	if D.INDIRECT.has(w): return true
	return line_clear(s.x, s.y, h_at(s.x, s.y) + muzzle_h(s), t.x, t.y, h_at(t.x, t.y) + aim_h(t))

## Cached version for units (re-checked a few times a second).
func has_shot(s: Ent, t: Ent, dt: float) -> bool:
	s.los_t -= dt
	if s.los_of != t or s.los_t <= 0:
		s.los_of = t; s.los_t = 0.25; s.los_ok = fire_clear(s, t)
	return s.los_ok

# ---------------- pathfinding ----------------
func nearest_walk(gx: int, gy: int, sx: int, sy: int, m := 0):
	for r in 14:
		var best = null; var bd := 1e9
		for y in range(gy - r, gy + r + 1):
			for x in range(gx - r, gx + r + 1):
				if max(abs(x - gx), abs(y - gy)) != r: continue
				if not passable(m, x, y): continue
				var dd := (x - sx) * (x - sx) + (y - sy) * (y - sy)
				if dd < bd: bd = dd; best = Vector2i(x, y)
		if best != null: return best
	return null

func find_path(sx: int, sy: int, gx: int, gy: int, m := 0) -> Array:
	sx = clampi(sx, 0, MW - 1); sy = clampi(sy, 0, MH - 1)
	var astar: AStarGrid2D = grid(m)
	if not passable(m, gx, gy):
		var n = nearest_walk(gx, gy, sx, sy, m)
		if n == null: return []
		gx = n.x; gy = n.y
	if sx == gx and sy == gy: return []
	var sp := Vector2i(sx, sy)
	var was_solid := astar.is_point_solid(sp)
	if was_solid: astar.set_point_solid(sp, false)
	var ids := astar.get_id_path(sp, Vector2i(gx, gy), true)
	if was_solid: astar.set_point_solid(sp, true)
	var out: Array = []
	for k in range(1, ids.size()): out.append(ids[k])
	return smooth(sx, sy, out, m)

func los(ax: int, ay: int, bx: int, by: int, m := 0) -> bool:
	var dx := bx - ax; var dy := by - ay
	var L := sqrt(dx * dx + dy * dy); var n := int(ceil(L * 3))
	if n == 0: return true
	var px := -dy / L * 0.38; var py := dx / L * 0.38
	for i in range(1, n + 1):
		var f := float(i) / n
		var x := ax + 0.5 + dx * f; var y := ay + 0.5 + dy * f
		if not passable(m, int(floor(x)), int(floor(y))) or not passable(m, int(floor(x + px)), int(floor(y + py))) or not passable(m, int(floor(x - px)), int(floor(y - py))): return false
	return true

func smooth(sx: int, sy: int, p: Array, m := 0) -> Array:
	if p.size() < 3: return p
	var out: Array = []; var cx := sx; var cy := sy; var i := 0
	while i < p.size():
		var j := mini(p.size() - 1, i + 14)
		while j > i and not los(cx, cy, p[j].x, p[j].y, m): j -= 1
		out.append(p[j]); cx = p[j].x; cy = p[j].y; i = j + 1
	return out

func route(u: Ent, tx: int, ty: int) -> Array:
	if u.d.air:
		tx = clampi(tx, 0, MW - 1); ty = clampi(ty, 0, MH - 1)
		return [] if (int(u.x / T) == tx and int(u.y / T) == ty) else [Vector2i(tx, ty)]
	return find_path(int(u.x / T), int(u.y / T), tx, ty, mob(u))

func set_path(u: Ent, tx: int, ty: int) -> void:
	u.path = route(u, tx, ty); u.dest = Vector2i(tx, ty); u.stuck = 0; u.fspd = 0.0

# ---------------- orders ----------------
func slots_around(tx: int, ty: int, n: int) -> Array:
	if not walk(tx, ty):
		var w = nearest_walk(tx, ty, tx, ty)
		if w == null: return []
		tx = w.x; ty = w.y
	var out: Array = []; var seen := {ty * MW + tx: true}; var q := [Vector2i(tx, ty)]; var qi := 0
	while qi < q.size() and out.size() < n:
		var c: Vector2i = q[qi]; qi += 1
		out.append(c)
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
			var nx: int = c.x + dxy[0]; var ny: int = c.y + dxy[1]; var k := ny * MW + nx
			if not seen.has(k) and walk(nx, ny):
				seen[k] = true; q.append(Vector2i(nx, ny))
	return out

## formation rank: 0 armor up front, 1 infantry, 2 support and artillery at the back, 3 air
func rank_of(u: Ent) -> int:
	var d := u.d
	if d.air: return 3
	if d.heal or d.eng or d.harv or d.minr > 0: return 2
	return 1 if d.armor == "inf" else 0

func free_tile(x: float, y: float, used: Dictionary, air: bool):
	var xi := int(round(x)); var yi := int(round(y))
	for r in 8:
		for yy in range(yi - r, yi + r + 1):
			for xx in range(xi - r, xi + r + 1):
				if max(abs(xx - xi), abs(yy - yi)) != r: continue
				if not inb(xx, yy): continue
				var k := yy * MW + xx
				if used.has(k): continue
				if not air and not walk(xx, yy): continue
				used[k] = true
				return Vector2i(xx, yy)
	return null

## Plan formation slots without issuing orders (used for the drag preview too).
## face: optional facing angle; width: optional front width in tiles.
func plan_formation(movers: Array, wx: float, wy: float, face = null, width := 0.0) -> Array:
	var tx := clampi(int(wx / T), 0, MW - 1); var ty := clampi(int(wy / T), 0, MH - 1)
	if movers.size() <= 1:
		return [[movers[0], Vector2i(tx, ty)]] if movers.size() else []
	var cx := 0.0; var cy := 0.0
	for u in movers: cx += u.x; cy += u.y
	cx /= movers.size(); cy /= movers.size()
	var dir: float
	if face != null: dir = face
	else:
		dir = atan2(wy - cy, wx - cx)
		if Vector2(wx - cx, wy - cy).length() < T * 1.5: dir = movers[0].ang
	var fx := cos(dir); var fy := sin(dir); var rx := -fy; var ry := fx
	var ranks := [[], [], [], []]
	for u in movers: ranks[rank_of(u)].append(u)
	var used := {}
	var wide := maxi(3, int(ceil(sqrt(movers.size()) * 1.4)))
	if width > 1.5: wide = clampi(int(round(width / 1.3)) + 1, 2, movers.size())
	var row := 0; var plan: Array = []
	for rk in [0, 1, 2, 3]:
		var list: Array = ranks[rk]
		if list.is_empty(): continue
		var sp := 1.5 if rk == 0 else (1.6 if rk == 3 else 1.1)
		list.sort_custom(func(a, b): return ((a.x - cx) * rx + (a.y - cy) * ry) < ((b.x - cx) * rx + (b.y - cy) * ry))
		var i := 0
		while i < list.size():
			var chunk := list.slice(i, i + wide); var n := chunk.size()
			for j in n:
				var lat := (j - (n - 1) / 2.0) * sp; var back := row * (1.5 if rk == 0 else 1.15)
				var px := wx / T - 0.5 + rx * lat - fx * back; var py := wy / T - 0.5 + ry * lat - fy * back
				var sl = free_tile(px, py, used, rk == 3)
				plan.append([chunk[j], sl if sl != null else Vector2i(tx, ty)])
			row += 1; i += wide
	return plan

const STRAGGLE := 8.0
var formation := true   # off: every unit heads straight for the nearest free tile, no ranks, own speed

func group_move(units: Array, wx: float, wy: float, order: String, face = null, width := 0.0) -> void:
	if units.is_empty(): return
	var fighters := units.filter(func(u): return u.d.dmg > 0 and not u.d.air)
	var escorts: Array = []
	if order == "amove" and fighters.size():
		escorts = units.filter(func(u): return u.d.heal > 0 or u.d.eng)
	var movers := units.filter(func(u): return not escorts.has(u))
	var plan: Array
	var form: bool = formation or units[0].team != 0   # the toggle is the player's; the AI always forms up
	if form: plan = plan_formation(movers, wx, wy, face, width)
	else:
		plan = []; var used := {}
		movers.sort_custom(func(a, b): return Vector2(a.x - wx, a.y - wy).length() < Vector2(b.x - wx, b.y - wy).length())
		for u in movers:
			var sl = free_tile(wx / T - 0.5, wy / T - 0.5, used, u.d.air)
			plan.append([u, sl if sl != null else Vector2i(clampi(int(wx / T), 0, MW - 1), clampi(int(wy / T), 0, MH - 1))])
	for p in plan:
		var u: Ent = p[0]; var sl: Vector2i = p[1]
		if u.intun > 0:
			u.tun.dest = sl; u.tun.order = order; u.face = face; continue
		u.order = order; u.target = null; u.auto = false; u.guard = null; u.face = face
		if u.d.harv: u.hs = "manual"
		set_path(u, sl.x, sl.y)
		plan_tunnel(u, sl)
	if plan.size() > 1 and form:
		# shared pace: the main body arrives together (aircraft fly ahead). Units far behind the main
		# body (STRAGGLE tiles more to travel than the median) don't hold it back: they go at full speed.
		var ground: Array = []
		for p in plan:
			if not p[0].d.air and p[0].path.size() and p[0].tun == null: ground.append(p[0])
		var lens: Array = []
		for u in ground:
			var L := 0.0; var x: float = u.x; var y: float = u.y
			for c in u.path:
				var px: float = c.x * T + 16; var py: float = c.y * T + 16
				L += Vector2(px - x, py - y).length(); x = px; y = py
			u.path_len = L; lens.append(L)
		lens.sort()
		var med: float = lens[lens.size() / 2] if lens.size() else 0.0
		var body := ground.filter(func(u): return u.path_len <= med + STRAGGLE * T)
		var eta := 0.0
		for u in body: eta = max(eta, u.path_len / (u.d.spd * T))
		if eta > 0 and body.size() > 1:
			for u in body: u.fspd = max(u.d.spd * 0.35, min(u.d.spd, u.path_len / eta / T))
	for u in escorts:
		u.order = "escort"; u.esc = fighters.duplicate(); u.ecx = wx; u.ecy = wy; u.target = null; u.path = []; u.rp = 0.0; u.fspd = 0.0

func follow_esc(u: Ent, dt: float) -> bool:
	var es := u.esc.filter(func(e): return e.alive)
	if es.is_empty():
		u.order = "none"; u.esc = []
		if u.ecx != null:
			set_path(u, int(u.ecx / T), int(u.ecy / T)); u.order = "move"
		return move_unit(u, dt)
	var best: Ent = null; var bd := 1e9
	for e in es:
		var dd: float = Vector2(e.x - u.x, e.y - u.y).length() * (1.0 if e.d.armor == "inf" else 1.6)
		if dd < bd: bd = dd; best = e
	var tx := best.x - cos(best.ang) * T * 1.1; var ty := best.y - sin(best.ang) * T * 1.1
	if Vector2(tx - u.x, ty - u.y).length() > T * 1.3:
		u.rp -= dt
		if u.rp <= 0 or u.path.is_empty():
			u.rp = 0.6; u.path = route(u, int(tx / T), int(ty / T))
		return move_unit(u, dt)
	u.path = []
	return false

func attack_order(units: Array, t: Ent) -> void:
	for u in units:
		if u.d.dmg == 0 or not can_hit(u.d, t) or u.intun > 0: continue
		u.order = "attack"; u.target = t; u.auto = false; u.path = []; u.rp = 0.0; u.face = null; u.tun = null

func eng_order(us: Array, b: Ent) -> void:
	for u in us:
		if u.intun > 0: continue
		u.tun = null
		u.order = "capture"; u.target = b; u.path = []; u.rp = 0.0

# ---------------- Hollow Choir tunnels ----------------
## Burrows and the Choir's Command Yard are linked underground: a unit walks into the one nearest to it
## and comes out of the one nearest its destination, when that is clearly shorter than walking.
func is_tun(b: Ent) -> bool:
	return b.alive and b.kind == "b" and (b.d.tun or (b.type == "hq" and teams[b.team].fac == "choir"))

func tun_exit(b: Ent) -> Vector2i:
	var gx: int = b.tx + (b.w >> 1); var gy: int = b.ty + b.h
	var n = nearest_walk(gx, gy, gx, gy + 1)
	return n if n != null else Vector2i(gx, gy)

func plan_tunnel(u: Ent, dest: Vector2i) -> void:
	u.tun = null
	if u.d.air or u.d.harv or teams[u.team].fac != "choir" or u.captive: return
	var A: Ent = null; var B: Ent = null; var da := 1e9; var db := 1e9
	var dx := dest.x * T + 16.0; var dy := dest.y * T + 16.0
	for b in ents:
		if b.team != u.team or not is_tun(b): continue
		var a := Vector2(b.x - u.x, b.y - u.y).length()
		if a < da: da = a; A = b
		var c := Vector2(b.x - dx, b.y - dy).length()
		if c < db: db = c; B = b
	if A == null or A == B: return
	var direct := Vector2(dx - u.x, dy - u.y).length()
	if da + db + T * 4 >= direct * 0.75: return
	u.tun = {"a": A, "b": B, "dest": dest, "order": u.order}
	var ex := tun_exit(A)
	u.path = route(u, ex.x, ex.y); u.stuck = 0; u.fspd = 0.0

## Runs the tunnel trip. True while the unit is underground (nothing else to update).
func tunnel_tick(u: Ent, dt: float) -> bool:
	var tn: Dictionary = u.tun
	var A: Ent = tn.a; var B: Ent = tn.b
	if u.intun > 0:
		u.intun -= dt
		if u.intun <= 0 or (not A.alive and not B.alive): _emerge(u)
		return true
	if not A.alive or not B.alive:
		u.tun = null
		if u.target == null: set_path(u, tn.dest.x, tn.dest.y)
		return false
	if u.target != null or not u.path.is_empty(): return false
	if dist_to_ent(u.x, u.y, A) < T * 2.5:
		u.intun = 0.8 + Vector2(B.x - A.x, B.y - A.y).length() / (T * 14.0)
		u.under = true; u.moving = false; u.sel = false; _drop_sel(u)
		_dig(u.x, u.y, 6); host.sfx("burrow", u.x, u.y)
		return true
	u.tun = null
	return false

func _emerge(u: Ent) -> void:
	var tn: Dictionary = u.tun
	var out: Ent = tn.b if tn.b.alive else (tn.a if tn.a.alive else null)
	if out != null:
		var ex := tun_exit(out)
		var sl := slots_around(ex.x, ex.y, 1 + randi() % 4)
		var p: Vector2i = sl[-1] if sl.size() else ex
		u.x = p.x * T + 16; u.y = p.y * T + 16
	u.intun = 0.0; u.under = false; u.tun = null; u.lx = u.x; u.ly = u.y
	u.order = tn.order if tn.order != "none" else "move"
	set_path(u, tn.dest.x, tn.dest.y)
	_dig(u.x, u.y, 6); host.sfx("burrow", u.x, u.y)

func _dig(x: float, y: float, n: int) -> void:
	for k in n:
		var a := randf() * TAU
		parts.append({"k": "smoke", "x": x + cos(a) * 6, "y": y + sin(a) * 6, "vx": cos(a) * 26, "vy": sin(a) * 26, "life": 0.6, "max": 0.6, "s": 3.0, "c": Color8(122, 104, 78)})

# ---------------- Hollow Choir shard fields ----------------
func add_field(x: float, y: float, r: float, life: float, team: int, dps: float) -> void:
	fields.append({"x": x, "y": y, "r": r, "life": life, "max": life, "team": team, "dps": dps, "tick": 0.0, "seed": randi() % 1000})

func upd_fields(dt: float) -> void:
	if fields.is_empty(): return
	for f in fields:
		f.life -= dt; f.tick -= dt
		if f.tick > 0: continue
		f.tick = 0.25
		for o in ents:
			if not o.alive or o.kind != "u" or o.team == f.team or o.d.air or o.under or o.captive: continue
			if Vector2(o.x - f.x, o.y - f.y).length() < f.r: damage(o, f.dps * 0.25, "shard", null)
	fields = fields.filter(func(f): return f.life > 0)

## Cantors lift every friendly unit around them; a faint ring shows the reach.
func upd_auras(dt: float) -> void:
	aura_tick -= dt
	if aura_tick > 0: return
	aura_tick = 0.5
	for c in ents:
		if not c.alive or c.kind != "u" or c.d.aura <= 0 or c.intun > 0 or c.captive: continue
		var R: float = c.d.aura * T
		for o in ents:
			if o.alive and o.kind == "u" and o.team == c.team and o != c and Vector2(o.x - c.x, o.y - c.y).length() < R: o.aura_t = 0.7
		if int(time * 2) % 3 == 0: parts.append({"k": "aura", "x": c.x, "y": c.y, "life": 1.3, "max": 1.3, "R": R})

## Garden: it sings to the field around it. Every 4 s it pays its age's rate (less on a thin field), mends the field's
## vitality, ripens Pods, and now and then pushes the crystal one tile further out inside its Hum.
func upd_garden(b: Ent, tm: Dictionary, dt: float) -> void:
	b.pod_t += dt
	if b.pods >= D.HUM.hold: b.pod_t = 0.0
	elif b.pod_t >= D.HUM.pod:
		b.pod_t -= D.HUM.pod; b.pods += 1
		if b.team == 0: host.on_sel_changed()
	b.spread_t += dt
	if b.spread_t >= D.HUM.spread:
		b.spread_t = 0.0; spread_crystal(b)
	b.gt += dt
	if b.gt < 4.0: return
	b.gt -= 4.0
	var cx: float = b.tx + b.w / 2.0; var cy: float = b.ty + b.h / 2.0; var R: float = b.d.hum
	var live := 0; var shown := 0
	for ty in range(int(cy - R), int(cy + R) + 1):
		for tx in range(int(cx - R), int(cx + R) + 1):
			if not inb(tx, ty): continue
			var i := ty * MW + tx
			if ore0[i] <= 0 or Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length() > R: continue
			# the song: a tired tile mends (never a dead one), and its ore creeps back
			if vit[i] > 0 and vit[i] < 100: vit[i] = mini(100, vit[i] + 1)
			if vit[i] > 0 and ore[i] < ore0[i]: ore[i] = mini(ore0[i], ore[i] + 10)
			live += ore[i]
			if ore[i] > 0 and shown < 3 and randf() < 0.15 and (b.team == 0 or visible_to_player(b)):
				shown += 1
				parts.append({"k": "gem", "x": tx * T + 16.0, "y": ty * T + 16.0, "bx": b.x, "by": b.y, "ah": h_at(tx * T + 16.0, ty * T + 16.0) + .05, "bh": h_at(b.x, b.y) + 1.0, "life": .9, "max": .9, "s": .07 + randf() * .04})
	var amt: float = b.d.rate * 4.0 * b.d.yield * clamp(live / 2500.0, 0.4, 1.0)
	tm.credits += amt * (D.DIFF[diff].inc if tm.ai else 1.0); tm.earned += amt
	b.unload_t = time
	if b.team == 0:
		stats.mined += int(amt)
		parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "+%d" % int(amt), "c": Color("f0b93f"), "life": 1.6, "max": 1.6, "h": 1.5})

## One more tile of living crystal: open ground inside the Garden's Hum that touches crystal already there.
func spread_crystal(b: Ent) -> void:
	var cx: float = b.tx + b.w / 2.0; var cy: float = b.ty + b.h / 2.0; var R: float = b.d.hum
	var cand: Array = []
	for ty in range(int(cy - R), int(cy + R) + 1):
		for tx in range(int(cx - R), int(cx + R) + 1):
			if not inb(tx, ty) or tx < 1 or ty < 1 or tx >= MW - 1 or ty >= MH - 1: continue
			var i := ty * MW + tx
			if ore0[i] > 0 or bmap[i] or terr[i] >= D.ROCK or Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length() > R: continue
			if ore[i - 1] > 0 or ore[i + 1] > 0 or ore[i - MW] > 0 or ore[i + MW] > 0: cand.append(i)
	if cand.is_empty(): return
	var c: int = cand[randi() % cand.size()]
	ore0[c] = 200; ore[c] = 200; vit[c] = 100; touch_t[c] = time
	if host: host.on_world_changed()

## The Hollowing: the dead rise.
func upd_risers() -> void:
	var keep: Array = []
	for r in risers:
		if r[0] > time: keep.append(r); continue
		var w := spawn_unit(r[3], "wretch", r[1], r[2])
		_dig(w.x, w.y, 5)
		if r[3] == 0 and host: host.sfx("burrow", w.x, w.y)
	risers = keep

## A Choir form that has killed enough mutates: its def becomes its own changed copy.
func mutate(u: Ent) -> void:
	var m: Dictionary = u.d.mut
	if u.mut or m.is_empty(): return
	var nd: Dictionary = u.d.duplicate()
	for k in m:
		match k:
			"hp":
				u.max_hp *= m.hp; u.hp *= m.hp
			"dmg": nd.dmg = nd.dmg * m.dmg
			"spd": nd.spd = nd.spd * m.spd
			_: nd[k] = m[k]
	nd.mut = {}
	u.d = nd; u.mut = true; u.lv = 2; calc_hum()
	for k in 8: parts.append({"k": "spark", "x": u.x, "y": u.y, "vx": (randf() - 0.5) * 80, "vy": (randf() - 0.5) * 80, "life": 0.5, "max": 0.5, "c": Color("#9dffb4"), "s": 2.4, "h0": h_at(u.x, u.y) + .4})
	if u.team == 0: host.toast(u.d.name + ": a mutation", "gold")

## Fusion: four Thralls standing together become one Knot. Returns it (null when there are not enough).
func fuse(team: int, us: Array) -> Ent:
	var th: Array = us.filter(func(u): return u.alive and u.kind == "u" and u.team == team and u.d.fuse != "" and not u.captive and u.intun <= 0)
	if th.size() < D.HUM.fuse: return null
	var c := Vector2.ZERO
	for u in th: c += Vector2(u.x, u.y)
	c /= th.size()
	th.sort_custom(func(a, b): return Vector2(a.x - c.x, a.y - c.y).length_squared() < Vector2(b.x - c.x, b.y - c.y).length_squared())
	th = th.slice(0, D.HUM.fuse)
	var into: String = th[0].d.fuse
	c = Vector2.ZERO
	for u in th: c += Vector2(u.x, u.y)
	c /= th.size()
	for u in th:
		u.alive = false; _drop_sel(u); _dig(u.x, u.y, 3)
	var k := spawn_unit(team, into, c.x, c.y)
	k.stun = 2.0; _dig(k.x, k.y, 8)
	if team == 0: host.toast("Four Thralls have fused into a " + k.d.name, "gold"); host.sfx("burrow", k.x, k.y)
	return k

## Keener: its cry jams every enemy machine and gun in reach and drops their shields.
func cry(u: Ent) -> bool:
	var R: float = u.d.cry * T; var hit := false
	for o in ents:
		if not o.alive or o.team == u.team or o.captive or dist_to_ent(u.x, u.y, o) > R: continue
		if o.kind == "u" and o.d.armor == "inf" and o.sh_max <= 0: continue
		if o.kind == "b" and o.d.weapon == "" and o.sh_max <= 0: continue
		o.jam_t = time + D.HUM.jam; o.sh = 0.0; o.sh_t = time + D.HUM.jam; hit = true
	if not hit: return false
	u.cry_t = D.HUM.cry
	parts.append({"k": "aura", "x": u.x, "y": u.y, "life": 0.8, "max": 0.8, "R": R})
	host.sfx("shard", u.x, u.y)
	return true

# ---------------- simulation ----------------
func find_target(src: Ent, rng: float) -> Ent:
	var best: Ent = null; var bs := 1e9
	var sd: Dictionary = src.d
	var bld_src := src.kind == "b"
	for o in ents:
		if not o.alive or o.team == src.team or o.captive or hid(o): continue
		if src.team == 0 and not visible_to_player(o): continue
		if not can_hit(sd, o): continue
		var dd := dist_to_ent(src.x, src.y, o)
		if dd > rng: continue
		var s := dd + ((T * 7 if o.d.kit > 0 else T * 3) if o.kind == "b" else 0) + (T if (o.kind == "u" and o.d.harv) else 0)
		if s >= bs: continue
		if not D.INDIRECT.has(sd.weapon):
			var clear := fire_clear(src, o)
			if bld_src and not clear: continue
			if not clear:
				s += T * 4
				if s >= bs: continue
		bs = s; best = o
	return best

func fire(s: Ent, t: Ent, d: Dictionary) -> void:
	s.fired_t = time
	var n: int = d.get("salvo", 1)
	for k in n: fire_one(s, t, d)
	if d.get("suicide", false):
		# a Burster is its own charge
		if d.get("shards", 0) > 0: add_field(t.x, t.y, T * 1.8, 8.0, s.team, 9.0)
		s.alive = false; _drop_sel(s); explode(s.x, s.y, 12); return
	# a Slag Boar's charge: the first gore after a rest hits three times as hard and knocks the target down
	if d.get("charge", 0.0) > 0.0 and s.it <= 0.0 and t.alive and t.kind == "u":
		damage(t, d.dmg * (d.charge - 1.0), d.weapon, s)
		if t.alive and not t.d.air and t.d.armor != "heavy": t.stun = 1.5
		s.it = 6.0

func fire_one(s: Ent, t: Ent, d: Dictionary) -> void:
	var ang := atan2(t.y - s.y, t.x - s.x)
	var mr := (s.r if s.kind == "u" else 12.0) + 2
	var mx := s.x + cos(ang) * mr; var my := s.y + sin(ang) * mr
	var ox := 0.0; var oy := 0.0
	if t.kind == "b":
		ox = (randf() - 0.5) * t.w * T * 0.6; oy = (randf() - 0.5) * t.h * T * 0.6
	s.flash = 0.08
	var hs := muzzle_h(s); var htg := aim_h(t)
	if t.team == 0 or s.team == 0: combat = min(1.0, combat + 0.04)
	var w: String = d.weapon
	if w == "bullet" or w == "snipe" or w == "rail" or w == "shard" or w == "laser":
		var sn := w == "snipe" or w == "rail" or w == "laser"; var sh := w == "shard"
		var lf := 0.18 if sn else (0.1 if sh else 0.07)
		parts.append({"k": "tracer", "x": mx, "y": my, "x2": t.x + ox + (randf() - 0.5) * 6, "y2": t.y + oy + (randf() - 0.5) * 6, "life": lf, "max": lf, "ha": h_at(mx, my) + hs, "hb": h_at(t.x, t.y) + htg, "c": 2 if sh else (1 if sn else 0)})
		parts.append({"k": "spark", "x": t.x + ox, "y": t.y + oy, "vx": (randf() - 0.5) * 60, "vy": (randf() - 0.5) * 60, "life": 0.15, "max": 0.15, "c": Color("#9dffb4") if sh else Color("#ffe7a0"), "s": 1.5, "h0": h_at(t.x, t.y) + htg})
		host.sfx("shard" if sh else ("snipe" if sn else "gun"), s.x, s.y)
		damage(t, d.dmg, w, s)
		if d.get("pierce", false):
			# a rail slug goes on through everything in its line, out to the gun's full reach
			var ex: float = mx + cos(ang) * d.range * T; var ey: float = my + sin(ang) * d.range * T
			parts.append({"k": "tracer", "x": mx, "y": my, "x2": ex, "y2": ey, "life": 0.25, "max": 0.25, "ha": h_at(mx, my) + hs, "hb": h_at(ex, ey) + htg, "c": 1})
			var seg := Vector2(ex - mx, ey - my); var L2 := seg.length_squared()
			for o in ents:
				if not o.alive or o.team == s.team or o == t or o.captive or (o.kind == "u" and o.d.air != (t.kind == "u" and t.d.air)): continue
				var f: float = clamp(Vector2(o.x - mx, o.y - my).dot(seg) / L2, 0.0, 1.0)
				if Vector2(o.x - (mx + seg.x * f), o.y - (my + seg.y * f)).length() < (o.r if o.kind == "u" else o.r * 0.8) + 5: damage(o, d.dmg, w, s)
	elif w == "charge":
		# the sapper sets a crystal charge against the target and steps back
		explode(t.x + ox * 0.5, t.y + oy * 0.5, 14)
		for k in 6: parts.append({"k": "spark", "x": t.x, "y": t.y, "vx": (randf() - 0.5) * 90, "vy": (randf() - 0.5) * 90, "life": 0.4, "max": 0.4, "c": Color("#9dffb4"), "s": 2.2})
		host.sfx("boom", s.x, s.y)
		damage(t, d.dmg, w, s)
	elif w == "toll" or w == "crush":
		# a Carillon's toll flattens every soldier round the target; a Knot crushes whatever is beside what it hits
		parts.append({"k": "aura", "x": t.x, "y": t.y, "life": 0.5, "max": 0.5, "R": d.splash})
		host.sfx("heavy" if w == "crush" else "shard", s.x, s.y)
		for o in ents:
			if o.alive and o.team != s.team and not o.captive and (o == t or (o.kind == "u" and not o.d.air and Vector2(o.x - t.x, o.y - t.y).length() < d.splash)):
				damage(o, d.dmg * (1.0 if o == t else 0.6), w, s)
	elif w == "gore" or w == "ram" or w == "bite":
		for k in 5: parts.append({"k": "spark", "x": t.x + ox * 0.5, "y": t.y + oy * 0.5, "vx": (randf() - 0.5) * 70, "vy": (randf() - 0.5) * 70, "life": 0.3, "max": 0.3, "c": Color("#ffb36b"), "s": 2.0, "h0": h_at(t.x, t.y) + htg})
		if w == "ram": explode(t.x + ox * 0.5, t.y + oy * 0.5, 10)
		host.sfx("heavy" if w == "ram" else "gun", s.x, s.y)
		damage(t, d.dmg, w, s)
	elif w == "flame":
		for i in 5:
			var f := 0.3 + i * 0.17
			parts.append({"k": "flame", "x": mx + (t.x - mx) * f * 0.4, "y": my + (t.y - my) * f * 0.4, "vx": (t.x - mx) * 1.6 + (randf() - 0.5) * 30, "vy": (t.y - my) * 1.6 + (randf() - 0.5) * 30, "life": 0.35 + randf() * 0.15, "max": 0.5, "s": 3.0 + i})
		host.sfx("flame", s.x, s.y)
		damage(t, d.dmg, "flame", s)
	elif w == "arc":
		var hit: Array = [t]; var cur := t
		for j in 2:
			var nb: Ent = null; var bd := T * 2.6
			for o in ents:
				if not o.alive or o.team == s.team or hit.has(o) or o.kind != "u" or o.d.air: continue
				var dd := Vector2(o.x - cur.x, o.y - cur.y).length()
				if dd < bd: bd = dd; nb = o
			if nb == null: break
			hit.append(nb); cur = nb
		var px := mx; var py := my; var ph = h_at(mx, my) + hs
		for j in hit.size():
			var o: Ent = hit[j]
			parts.append({"k": "arc", "x": px, "y": py, "x2": o.x, "y2": o.y, "ha": ph, "life": 0.22, "max": 0.22, "seed": randf() * 99})
			px = o.x; py = o.y; ph = null
			damage(o, d.dmg * (0.6 if j else 1.0), "arc", s)
		host.sfx("arc", s.x, s.y)
	else:
		var arty := D.INDIRECT.has(w)   # lobbed: Howler mortar shells, Geode Lobber crystals
		if arty: ox += (randf() - 0.5) * 30; oy += (randf() - 0.5) * 30
		var p := {"x": mx, "y": my, "t": t, "ox": ox, "oy": oy, "tx": t.x + ox, "ty": t.y + oy, "w": w, "dmg": d.dmg, "src": s, "src_team": s.team,
			"spd": D.PSPD.get(w, 230.0 if arty else 290.0), "ang": ang, "fixed": arty, "lob": arty, "splash": d.splash,
			"y0": h_at(mx, my) + hs, "y1": h_at(t.x + ox, t.y + oy) + (0.05 if arty else htg), "aim": 0.05 if arty else htg, "dead": false}
		p.d0 = max(1.0, Vector2(p.tx - mx, p.ty - my).length())
		p.apex = ballistic_apex(p) if arty else 0.0
		p.h = p.y0
		proj.append(p)
		var snd: String = w
		if w == "arty" or w == "grenade": snd = "mortar"
		elif w == "rivet": snd = "gun"
		elif w == "bomb": snd = "mortar"
		elif w == "spine": snd = "shard"
		elif s.type == "bulwark" or s.type == "bastion" or s.type == "saint": snd = "heavy"
		host.sfx(snd, s.x, s.y)

## A real lob: the apex is high enough for the shell to clear every hill on the way.
func ballistic_apex(p: Dictionary) -> float:
	var base: float = min(3.5, p.d0 / T * 0.45)
	var apex := base
	var n := int(p.d0 / T * 3) + 2
	for i in range(1, n):
		var f := float(i) / n
		var gx: float = p.x + (p.tx - p.x) * f; var gy: float = p.y + (p.ty - p.y) * f
		var need: float = h_at(gx, gy) + 0.35 - lerp(float(p.y0), float(p.y1), f)
		var k := 4.0 * f * (1.0 - f)
		if k > 0.05: apex = max(apex, need / k)
	return apex

func damage(t: Ent, dmg: float, w: String, src) -> void:
	if not t.alive or t.captive or (t.under and t.reveal_t < time): return
	var arm: String = "bld" if t.kind == "b" else t.d.armor
	var m: float = D.MOD[w][arm]
	if w == "bullet" and t.kind == "u": m *= 1.0 - t.d.tough   # Rivet Brutes shrug off rifle fire
	var dealt: float = dmg * m * (D.AEGIS.mark if t.mark_t > time else 1.0)
	# Aegis: a Shield Dome over the target soaks the hit first, then the target's own shield, then its hull
	var drain: float = D.AEGIS.arc if w == "arc" else 1.0
	if t.team < 2 and w != "sw":
		for dm in domes[t.team]:
			if dealt <= 0: break
			if not dm.alive or dm.dark or dm.sh <= 0 or dm == t or dist_to_ent(dm.x, dm.y, t) > dm.d.dome * T: continue
			var a: float = min(dm.sh, dealt * drain); dm.sh -= a; dm.sh_t = time; dealt -= a / drain; dm.flash = 0.15
	if t.sh > 0 and dealt > 0:
		var a: float = min(t.sh, dealt * drain); t.sh -= a; dealt -= a / drain
	if t.sh_max > 0: t.sh_t = time
	t.hp -= dealt; t.hit_t = 3.0
	if t.team == 0: combat = min(1.0, combat + 0.05); last_hurt = time
	if src != null and src.alive and t.kind == "u" and t.target == null and t.order == "none" and t.d.dmg > 0 and can_hit(t.d, src):
		t.target = src; t.auto = true
		if t.guard == null: t.guard = Vector2(t.x, t.y)
	if t.team == 0 and time - last_alert > 20:
		last_alert = time; ping = {"x": t.x, "y": t.y, "t": time}
		host.toast("Base under attack" if t.kind == "b" else ("Harvester under attack" if t.d.harv else "Units under attack"), "warn"); host.sfx("alert")
	if t.team == 0 and t.kind == "u" and t.d.hero and t.hp > 0 and t.hp < t.max_hp * 0.35: radio_cue("hero_hurt")
	if t.hp <= 0:
		if t.team == 1: _tut("kill", t, src)
		if src != null and src.alive and src.kind == "u" and not src.d.mut.is_empty():
			src.kills += 1
			if src.kills >= D.HUM.mut: mutate(src)
		kill(t)

func kill(e: Ent) -> void:
	e.alive = false; e.sel = false
	if e.kind == "u" and not e.d.air and e.team < 2 and teams.size() == 2:
		var o: int = 1 - e.team
		if e.d.armor == "inf" and not e.d.hero and fac_of(e.team) != "choir" and fac_of(o) == "choir" and in_hum(o, e.x, e.y):
			risers.append([time + D.HUM.rise, e.x, e.y, o])   # the Hollowing: it will rise as a Wretch
		elif fac_of(e.team) == "choir" and ore0[t_idx(e)] > 0 and vit[t_idx(e)] > 0:
			vit[t_idx(e)] = mini(100, vit[t_idx(e)] + 5)       # a fallen form feeds the crystal it lies on
	if e.kind == "u" and e.d.ship and not e.leaving and e.cargo.size():
		var back := int(e.paid * D.AEGIS.lost)
		teams[e.team].credits += back
		if e.team == 0: host.toast("Dropship lost with its cargo: +%d back" % back, "warn")
	if e.kind == "u" and e.d.hero:
		host.toast(e.d.name + (" is down!" if e.team == 0 else " destroyed"), "warn" if e.team == 0 else "gold"); host.sfx("alert" if e.team == 0 else "ready")
	elif e.tag == "vip" and e.team == 0:
		host.toast(e.d.name + " lost", "warn")
	if e.team == 0: stats.lost += 1
	if e.team == 0 and e.kind == "b": radio_cue("bld_lost")
	else: stats.killed += 1
	if e.kind == "b":
		for y in range(e.ty, e.ty + e.h):
			for x in range(e.tx, e.tx + e.w):
				if bmap[y * MW + x] == e.id: bmap[y * MW + x] = 0
		_sync_solid(e.tx, e.ty, e.w, e.h)
		e.end_kind = "die"; e.end_t = time
		if e.d.kit > 0:
			explode(e.x, e.y, 10); calc_power(); _drop_sel(e); host.on_world_changed(); return
		for k in e.w * e.h:
			delayed.append([time + k * 0.09, e.tx * T + randf() * e.w * T, e.ty * T + randf() * e.h * T, 18 + randf() * 10])
		host.add_scorch(e.x, e.y, e.w * T * 0.6); calc_power(); host.sfx("boom", e.x, e.y); host.on_world_changed()
	else:
		if e.d.armor == "inf":
			for k in 6: parts.append({"k": "smoke", "x": e.x, "y": e.y, "vx": (randf() - 0.5) * 20, "vy": (randf() - 0.5) * 20, "life": 0.6, "max": 0.6, "s": 3.0, "c": Color8(120, 110, 100)})
			parts.append({"k": "body", "x": e.x, "y": e.y, "life": 6.0, "max": 6.0, "c": D.TEAMC[e.team].dk, "rot": randf() * TAU})
		else:
			explode(e.x, e.y, e.r * 1.6)
			if not e.d.air: host.add_scorch(e.x, e.y, e.r * 1.2)
			if not e.d.air and e.d.cat == "veh" and not e.d.hero and e.type != "kettle":
				wrecks.append({"id": wid, "type": e.type, "team": e.team, "x": e.x, "y": e.y, "ang": e.ang, "intact": D.WRECK.start, "cost": e.d.cost, "hold": 0.0,
					"beacon": D.AEGIS.beacon if fac_of(e.team) == "vanguard" else 0.0}); wid += 1
			else:
				for p in parts.slice(-8):
					if p.k == "debris": p.h = 1.5
			host.sfx("boom", e.x, e.y)
	_drop_sel(e)

func _drop_sel(e: Ent) -> void:
	if sel.has(e):
		sel.erase(e); host.on_sel_changed()

func explode(x: float, y: float, s: float) -> void:
	parts.append({"k": "flash", "x": x, "y": y, "life": 0.25, "max": 0.25, "s": s})
	for i in 10:
		var a := randf() * TAU; var v := 40 + randf() * 120
		parts.append({"k": "spark", "x": x, "y": y, "vx": cos(a) * v, "vy": sin(a) * v, "life": 0.3 + randf() * 0.3, "max": 0.6, "c": Color("#ffcf6a") if randf() < 0.5 else Color("#ff8a3a"), "s": 2.0})
	for i in 6:
		parts.append({"k": "smoke", "x": x + (randf() - 0.5) * s, "y": y + (randf() - 0.5) * s, "vx": (randf() - 0.5) * 20, "vy": -10 - randf() * 20, "life": 1 + randf(), "max": 2.0, "s": s * 0.4, "c": Color8(50, 46, 42)})
	var nd := mini(8, 2 + int(s / 6))
	for i in nd:
		var a := randf() * TAU; var v := 30 + randf() * 70
		parts.append({"k": "debris", "x": x, "y": y, "vx": cos(a) * v, "vy": sin(a) * v, "h": 0.3, "vh": 2 + randf() * 3, "life": 1.6 + randf(), "max": 2.6, "s": 0.05 + randf() * 0.07, "r0": randf() * 6})

func move_unit(u: Ent, dt: float) -> bool:
	if u.path.is_empty():
		u.fspd = 0.0; return false
	var d := u.d
	var c: Vector2i = u.path[0]
	var px := c.x * T + 16.0; var py := c.y * T + 16.0
	var dx := px - u.x; var dy := py - u.y; var dist := sqrt(dx * dx + dy * dy)
	var inf: bool = d.armor == "inf"; var want := atan2(dy, dx)
	var sp: float = (u.fspd if u.fspd > 0 else d.spd) * T * dt * (0.85 if (not d.air and terr[t_idx(u)] == D.SAND) else 1.0) * (D.HUM.haste if u.inhum else 1.0)
	if dist > 1:
		u.ang = turn_to(u.ang, want, (18.0 if inf else (7.0 if d.spd > 2 else 3.6)) * dt)
		if not inf and ang_diff(u.ang, want) > 0.7: sp *= 0.15
	if d.turret and u.target == null: u.tang = turn_to(u.tang, u.ang, 3 * dt)
	if dist <= sp:
		u.x = px; u.y = py; u.path.pop_front()
		if not d.air and u.path.size() and not passable(mob(u), u.path[0].x, u.path[0].y):
			var l: Vector2i = u.path[-1]; set_path(u, l.x, l.y)
	else:
		u.x += dx / dist * sp; u.y += dy / dist * sp
	u.stuck_t += dt
	if not d.air and u.stuck_t > 1:
		if Vector2(u.x - u.lx, u.y - u.ly).length() < 6 and u.path.size():
			u.stuck += 1
			if u.stuck >= 3: u.path = []; u.stuck = 0
			else:
				var l: Vector2i = u.path[-1]; u.path = route(u, l.x, l.y)
		else: u.stuck = 0
		u.lx = u.x; u.ly = u.y; u.stuck_t = 0.0
	return true

func upd_unit(u: Ent, dt: float) -> void:
	var d := u.d
	u.cd -= dt
	if u.flash > 0: u.flash -= dt
	if u.hit_t > 0: u.hit_t -= dt
	if u.captive:
		u.moving = false; return
	if d.ship:
		upd_dropship(u, dt); return
	aegis(u, dt)
	if hum_tick(u, dt): return
	if d.cry > 0:
		u.cry_t -= dt
		if u.cry_t <= 0 and not cry(u): u.cry_t = 0.5
	if u.hop != null:
		# a Jump Trooper in the air: over cliffs, water and walls
		var hp: Dictionary = u.hop
		hp.t += dt
		var f: float = min(1.0, hp.t / hp.d)
		u.x = lerp(hp.x0, hp.x1, f); u.y = lerp(hp.y0, hp.y1, f); u.moving = true
		if f >= 1.0:
			u.hop = null; _dig(u.x, u.y, 3)
			if u.dest != null: set_path(u, u.dest.x, u.dest.y)
		return
	if d.cloak > 0:
		if u.moving or time - u.fired_t < d.cloak: u.still_t = 0.0
		else: u.still_t += dt
		u.cloak = u.still_t >= d.cloak
	if u.tun != null and tunnel_tick(u, dt): return
	if u.aura_t > 0:
		u.aura_t -= dt; u.cd -= dt * 0.3
		if u.hp < u.max_hp: u.hp = min(u.max_hp, u.hp + u.max_hp * 0.01 * dt)
	if d.hero and u.hp < u.max_hp and u.hit_t <= 0: u.hp = min(u.max_hp, u.hp + u.max_hp * 0.02 * dt)
	if u.stun > 0:
		u.stun -= dt; u.moving = false; return
	if d.charge > 0 and u.it > 0 and u.target == null: u.it -= dt   # a boar gets its wind back away from the fight
	if d.scrap and upd_scrap(u, dt): return
	if d.harv:
		upd_harv(u, dt); u.moving = move_unit(u, dt); return
	if d.heal: upd_medic(u, dt); return
	if d.eng: upd_eng(u, dt); return
	if u.target != null and (not u.target.alive or hid(u.target) or not can_hit(d, u.target) or (u.team == 0 and not visible_to_player(u.target) and u.order != "attack")):
		u.target = null
		if u.order == "attack": u.order = "none"; u.path = []
		if u.order == "amove" and u.dest != null: set_path(u, u.dest.x, u.dest.y)
	u.scan -= dt
	if u.target == null and (u.order == "none" or u.order == "amove") and u.scan <= 0 and not u.nofire:
		u.scan = 0.35 + randf() * 0.2
		var t := find_target(u, (d.range if u.hold else d.sight) * T)
		if t != null:
			u.target = t; u.auto = true; u.fspd = 0.0
			if u.order == "none" and u.guard == null: u.guard = Vector2(u.x, u.y)
	var moving := false
	if u.target != null:
		var t: Ent = u.target
		var dist := dist_to_ent(u.x, u.y, t)
		var in_range: bool = dist <= d.range * T and has_shot(u, t, dt)
		if in_range:
			u.path = []
			var want := atan2(t.y - u.y, t.x - u.x); var aimed: bool
			if d.turret:
				u.tang = turn_to(u.tang, want, 5 * dt); aimed = ang_diff(u.tang, want) < 0.12
			else:
				u.ang = turn_to(u.ang, want, (16.0 if d.armor == "inf" else 6.0) * dt); aimed = ang_diff(u.ang, want) < 0.15
			if u.cd <= 0 and aimed and time >= u.jam_t and not (d.minr > 0 and dist < d.minr * T):
				fire(u, t, d); u.cd = d.rof * (0.9 + randf() * 0.2)
		else:
			var leash: bool = u.order == "none" and u.auto and u.guard != null and (u.hold or Vector2(u.x - u.guard.x, u.y - u.guard.y).length() > 7 * T)
			var lost: bool = u.auto and dist > d.sight * T * 1.6
			if leash or lost:
				u.target = null; u.auto = false
				if u.order == "amove" and u.dest != null: set_path(u, u.dest.x, u.dest.y)
				elif u.guard != null:
					set_path(u, int(u.guard.x / T), int(u.guard.y / T)); u.order = "move"; u.guard = null
			else:
				u.rp -= dt
				if u.rp <= 0 or u.path.is_empty():
					u.rp = 0.9; u.path = route(u, int(t.x / T), int(t.y / T))
				moving = move_unit(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none":
			u.order = "none"; u.guard = Vector2(u.x, u.y)
		if not moving and u.face != null:
			u.ang = turn_to(u.ang, u.face, (18.0 if d.armor == "inf" else 3.0) * dt)
			if d.turret: u.tang = turn_to(u.tang, u.ang, 3 * dt)
			if ang_diff(u.ang, u.face) < 0.01: u.face = null
	u.moving = moving
	if d.jump > 0 and moving and time >= u.jump_t and u.path.size(): try_jump(u)
	if d.ram > 0 and moving and time >= u.ram_t: ram_check(u)
	if d.w2 != null:
		u.cd2 -= dt
		if u.cd2 <= 0: fire_w2(u)
	if d.burrow:
		# sappers dig through the ground while they move and surface to set their charges
		if moving != u.under:
			u.under = moving; _dig(u.x, u.y, 4)
		elif moving and randf() < dt * 6: _dig(u.x, u.y, 1)

## Life in and around the Hum. Choir forms in their own Hum heal and hurry, and a Wretch withers outside it; human infantry
## standing on living crystal inside an enemy Hum are cut. Returns true when the unit died of it.
func hum_tick(u: Ent, dt: float) -> bool:
	var f := fac_of(u.team)
	if f == "choir":
		u.inhum = in_hum(u.team, u.x, u.y)
		if u.inhum:
			if u.hp < u.max_hp: u.hp = min(u.max_hp, u.hp + u.max_hp * D.HUM.heal * dt)
		elif u.d.wither > 0:
			u.hp -= u.d.wither * dt
			if u.hp <= 0:
				u.alive = false; _drop_sel(u); return true
		return false
	if u.team > 1: return false
	var o: int = 1 - u.team
	if u.d.armor != "inf" or u.d.air or teams.size() <= o or fac_of(o) != "choir" or ore[t_idx(u)] <= 0 or not in_hum(o, u.x, u.y): return false
	u.hp -= D.HUM.cut * dt; u.hit_t = max(u.hit_t, 0.3)
	if randf() < dt * 3: parts.append({"k": "spark", "x": u.x, "y": u.y, "vx": (randf() - 0.5) * 30, "vy": (randf() - 0.5) * 30, "life": 0.3, "max": 0.3, "c": Color("#9dffb4"), "s": 1.6, "h0": h_at(u.x, u.y) + .2})
	if u.hp <= 0:
		kill(u); return true
	return false

## Jump Trooper: on a long move it jumps up to d.jump tiles toward where it is going, over anything in the way.
func try_jump(u: Ent) -> void:
	var l: Vector2i = u.path[-1]
	var goal := Vector2(l.x * T + 16.0, l.y * T + 16.0); var v := goal - Vector2(u.x, u.y)
	if v.length() < T * 4.5: return
	var p: Vector2 = Vector2(u.x, u.y) + v.normalized() * min(v.length(), float(u.d.jump) * T)
	var n = nearest_walk(int(p.x / T), int(p.y / T), int(p.x / T), int(p.y / T))
	if n == null: return
	var land := Vector2(n.x * T + 16.0, n.y * T + 16.0)
	if (land - Vector2(u.x, u.y)).length() < T * 3 or (goal - land).length() > v.length() - T * 2: return
	u.hop = {"x0": u.x, "y0": u.y, "x1": land.x, "y1": land.y, "t": 0.0, "d": 0.7}
	u.dest = l; u.path = []; u.jump_t = time + 12.0; u.ang = v.angle(); _dig(u.x, u.y, 3)
	host.sfx("flame", u.x, u.y)

## Jump Trooper ordered to jump (the JUMP button): leaps up to d.jump tiles toward (x, y) now, then walks on to it.
## Returns false while its jets cool down or when there is nowhere to land.
func jump_to(u: Ent, x: float, y: float) -> bool:
	if u.d.jump <= 0 or u.hop != null or time < u.jump_t or u.stun > 0: return false
	var v := Vector2(x - u.x, y - u.y)
	if v.length() < T: return false
	var p: Vector2 = Vector2(u.x, u.y) + v.normalized() * min(v.length(), float(u.d.jump) * T)
	var n = nearest_walk(int(p.x / T), int(p.y / T), int(p.x / T), int(p.y / T))
	if n == null: return false
	var land := Vector2(n.x * T + 16.0, n.y * T + 16.0)
	u.hop = {"x0": u.x, "y0": u.y, "x1": land.x, "y1": land.y, "t": 0.0, "d": 0.7}
	u.dest = Vector2i(clampi(int(x / T), 0, D.MW - 1), clampi(int(y / T), 0, D.MH - 1)) if v.length() > float(u.d.jump) * T else null
	u.path = []; u.order = "move"; u.target = null; u.auto = false; u.guard = null
	u.jump_t = time + 12.0; u.ang = v.angle(); _dig(u.x, u.y, 3)
	host.sfx("flame", u.x, u.y)
	return true

## Ram Bike: running at full speed into enemy infantry or a light vehicle hits it hard and knocks it down.
func ram_check(u: Ent) -> void:
	for o in ents:
		if not o.alive or o.team == u.team or o.kind != "u" or o.d.air or o.under or o.captive or o.d.armor == "heavy": continue
		if Vector2(o.x - u.x, o.y - u.y).length() < u.r + o.r + 4:
			damage(o, u.d.ram, "shell", u)
			if o.alive: o.stun = 1.0
			explode(o.x, o.y, 8); host.sfx("heavy", u.x, u.y)
			u.ram_t = time + 6.0
			return

## A second weapon that picks its own target (the Juggernaut's side flamers).
func fire_w2(u: Ent) -> void:
	var w: Dictionary = u.d.w2
	var best: Ent = null; var bd: float = w.range * T
	for o in ents:
		if not o.alive or o.team == u.team or o.under or o.captive or (o.kind == "u" and o.d.air): continue
		var dd := dist_to_ent(u.x, u.y, o)
		if dd < bd: bd = dd; best = o
	if best == null: return
	fire_one(u, best, {"weapon": w.weapon, "dmg": w.dmg, "splash": w.get("splash", 0.0)})
	u.cd2 = w.rof * (0.9 + randf() * 0.2)

## Scrapper: works a wreck it was sent to (revive it while it is still in one piece, else strip it for aurite),
## and patches up friendly vehicles near it when idle. Returns true when it handled the unit this frame.
func upd_scrap(u: Ent, dt: float) -> bool:
	if u.order == "capture" and u.target != null and u.target.team != u.team: return false
	if u.order == "capture" and u.target != null and u.target.team == u.team:
		# a friendly building: mend it in place instead of spending the Scrapper like an Engineer would
		var b: Ent = u.target
		if not b.alive or b.hp >= b.max_hp: u.target = null; u.order = "none"; return true
		if dist_to_ent(u.x, u.y, b) < T * 0.9:
			b.hp = min(b.max_hp, b.hp + D.WRECK.fix * dt); u.path = []; u.moving = false
			if randf() < dt * 8: parts.append({"k": "spark", "x": b.x + (randf() - 0.5) * 20, "y": b.y + (randf() - 0.5) * 20, "vx": (randf() - 0.5) * 50, "vy": (randf() - 0.5) * 50, "life": 0.3, "max": 0.3, "c": Color("#ffd27a"), "s": 1.6})
			return true
		return false
	if u.order == "scrap":
		var w = u.wk
		if w == null or not wrecks.has(w): u.order = "none"; u.wk = null; return true
		if Vector2(w.x - u.x, w.y - u.y).length() > T * 0.9:
			if u.path.is_empty():
				u.rp -= dt
				if u.rp <= 0:
					u.rp = 1.0; u.path = route(u, int(w.x / T), int(w.y / T))
					if u.path.is_empty(): u.order = "none"; u.wk = null; return true
			u.moving = move_unit(u, dt); return true
		u.path = []; u.moving = false; u.wk_t += dt
		if randf() < dt * 10: parts.append({"k": "spark", "x": w.x + (randf() - 0.5) * 16, "y": w.y + (randf() - 0.5) * 16, "vx": (randf() - 0.5) * 60, "vy": (randf() - 0.5) * 60, "life": 0.3, "max": 0.3, "c": Color("#ffd27a"), "s": 1.6})
		var revive: bool = w.intact >= D.WRECK.revive and not u.strip
		if u.wk_t >= (D.WRECK.revive_t if revive else D.WRECK.strip_t):
			wrecks.erase(w); u.order = "none"; u.wk = null; u.wk_t = 0.0
			if revive:
				var nu := spawn_unit(u.team, w.type, w.x, w.y)
				nu.type = w.type; nu.d = D.UN[w.type]; nu.max_hp = nu.d.hp; nu.r = nu.d.r
				nu.hp = nu.max_hp * w.intact; nu.ang = w.ang; nu.tang = w.ang
				if u.team == 0: host.toast(nu.d.name + " back on its tracks", "gold"); host.sfx("ready"); stats.built += 1; _tut("revive", nu)
			else:
				var gain: float = D.UN[w.type].cost * D.WRECK.strip
				teams[u.team].credits += gain
				if u.team == 0: host.toast("Stripped for %d aurite" % int(gain), "gold"); host.sfx("ready")
		return true
	if u.order == "none" and u.path.is_empty():
		# idle: weld the nearest damaged friendly vehicle within reach
		var best: Ent = null; var bd := T * 3.0
		for o in ents:
			if not o.alive or o.team != u.team or o.kind != "u" or o.d.armor == "inf" or o.d.air or o.hp >= o.max_hp: continue
			var dd := Vector2(o.x - u.x, o.y - u.y).length()
			if dd < bd: bd = dd; best = o
		if best != null:
			u.moving = false
			if bd > T * 1.3:
				u.moving = step_toward(u, best.x, best.y, dt)
			else:
				best.hp = min(best.max_hp, best.hp + D.WRECK.fix * dt)
				u.ang = atan2(best.y - u.y, best.x - u.x)
				if randf() < dt * 8: parts.append({"k": "spark", "x": best.x, "y": best.y, "vx": (randf() - 0.5) * 50, "vy": (randf() - 0.5) * 50, "life": 0.3, "max": 0.3, "c": Color("#ffd27a"), "s": 1.6})
			return true
	return false

## Moves a unit straight at a point (short hops, no path).
func step_toward(u: Ent, x: float, y: float, dt: float) -> bool:
	var v := Vector2(x - u.x, y - u.y)
	if v.length() < 2: return false
	var st: float = min(v.length(), u.d.spd * T * dt)
	var nx: float = u.x + v.normalized().x * st; var ny: float = u.y + v.normalized().y * st
	if not walk(int(nx / T), int(ny / T)): return false
	u.x = nx; u.y = ny; u.ang = v.angle()
	return true

func scrap_order(us: Array, w: Dictionary) -> void:
	for u in us:
		if not u.d.scrap: continue
		u.order = "scrap"; u.wk = w; u.wk_t = 0.0; u.target = null; u.rp = 0.0
		u.path = route(u, int(w.x / T), int(w.y / T))

func wreck_at(x: float, y: float):
	for w in wrecks:
		if Vector2(w.x - x, w.y - y).length() < T * 0.8: return w
	return null

## Aegis shields come back once they have been left alone for a while (never on a building that has gone dark).
func aegis(e: Ent, dt: float) -> void:
	if e.sh_max > 0 and e.sh < e.sh_max and not e.dark and time - e.sh_t > D.AEGIS.rest:
		e.sh = min(e.sh_max, e.sh + e.sh_max * D.AEGIS.regen * dt)

## A few times a second: K9s sniff out cloaked and burrowed units (anything standing right next to a cloaked one sees it too),
## and Spotter Drones mark what they can see.
func upd_sense() -> void:
	for o in ents:
		if not o.alive or o.kind != "u": continue
		if o.under or o.cloak:
			for e in ents:
				if not e.alive or e.team == o.team or e.captive: continue
				var r: float = max(float(e.d.get("detect", 0.0)), 1.5 if o.cloak else 0.0)
				if r > 0 and dist_to_ent(o.x, o.y, e) < r * T:
					o.reveal_t = time + 1.0; break
		if o.d.mark > 0:
			for e in ents:
				if e.alive and e.team != o.team and not hid(e) and dist_to_ent(o.x, o.y, e) < o.d.mark * T: e.mark_t = time + 1.0

## Live ore within r tiles of a point (in tiles).
func live_ore(cx: float, cy: float, r: float) -> int:
	var n := 0
	for ty in range(int(cy - r), int(cy + r) + 1):
		for tx in range(int(cx - r), int(cx + r) + 1):
			if inb(tx, ty) and ore[ty * MW + tx] > 0 and Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length() <= r: n += ore[ty * MW + tx]
	return n

## Deep Drill: pumps the field around it straight into the bank, and kills every tile it empties.
func upd_drill(b: Ent, tm: Dictionary, dt: float) -> void:
	b.pump_t += dt
	if b.pump_t < 2.0: return
	b.pump_t -= 2.0
	var want := int(b.d.pump * b.d.yield); var got := 0
	var cx: float = b.x / T; var cy: float = b.y / T; var R := 4.5
	var best := -1
	while got < want:
		best = -1; var bd := 1e9
		for ty in range(int(cy - R), int(cy + R) + 1):
			for tx in range(int(cx - R), int(cx + R) + 1):
				if not inb(tx, ty) or ore[ty * MW + tx] <= 0: continue
				var dd := Vector2(tx + 0.5 - cx, ty + 0.5 - cy).length()
				if dd <= R and dd < bd: bd = dd; best = ty * MW + tx
		if best < 0: break
		var was_live := vit[best] > 0
		got += take_ore(best, want - got, 100.0)
		if was_live and vit[best] == 0 and host: host.on_world_changed()
	b.dry = got == 0
	if got == 0: return
	tm.credits += got * (D.DIFF[diff].inc if tm.ai else 1.0); tm.earned += got
	b.unload_t = time
	if b.team == 0:
		stats.mined += got
		parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "+%d" % got, "c": Color("f0b93f"), "life": 1.6, "max": 1.6, "h": 1.5})

## Wrecks slowly burn out: past the revive line they can only be stripped, and at zero they are gone.
func upd_wrecks(dt: float) -> void:
	if wrecks.is_empty(): return
	var keep: Array = []
	for w in wrecks:
		w.intact -= D.WRECK.decay * dt
		if w.intact > 0: keep.append(w)
		# Vanguard recovery: hold the beacon with a ground unit for a few seconds and part of the cost comes back
		if w.beacon > 0:
			w.beacon -= dt
			var held := false
			for u in ents:
				if u.alive and u.kind == "u" and u.team == w.team and not u.d.air and Vector2(u.x - w.x, u.y - w.y).length() < T * 1.6: held = true; break
			w.hold = w.hold + dt if held else 0.0
			if randf() < dt * 2.5: parts.append({"k": "spark", "x": w.x, "y": w.y, "vx": 0.0, "vy": 0.0, "life": 0.5, "max": 0.5, "c": Color("#7fd8ff"), "s": 2.6 if held else 1.8, "h0": 0.9})
			if w.hold >= D.AEGIS.hold:
				var back := int(w.cost * D.AEGIS.back)
				teams[w.team].credits += back; w.beacon = 0.0
				if w.team == 0:
					parts.append({"k": "txt", "x": w.x, "y": w.y, "txt": "+%d" % back, "c": Color("7fd8ff"), "life": 1.8, "max": 1.8, "h": 1.0})
					host.toast("Recovered: +%d" % back, "gold"); host.sfx("ready")
	wrecks = keep

## Aurite the stokers keep aside for the Furnaces (D.FUEL_KEEP seconds of burn): training and building never dip into it.
func fuel_reserve(team: int) -> float:
	var r := 0.0
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and b.d.burn > 0: r += b.d.burn * D.FUEL_KEEP
	return r

## Furnaces burn aurite to make power; a cold one makes none.
func upd_furnaces(dt: float) -> void:
	var changed := false
	for b in ents:
		if not b.alive or b.kind != "b" or b.d.burn <= 0: continue
		var c: float = b.d.burn * dt
		var cold: bool = teams[b.team].credits < c
		if not cold: teams[b.team].credits -= c
		if cold != b.cold: b.cold = cold; changed = true
	if changed: calc_power()

## Hearths: once a match, every Hearth sends out free Militia (3 each).
func muster(team: int) -> int:
	var tm: Dictionary = teams[team]
	if tm.get("mustered", false): return 0
	var n := 0
	for b in ents.duplicate():
		if not b.alive or b.kind != "b" or b.team != team or b.d.muster <= 0: continue
		for k in int(b.d.muster):
			var u := spawn_unit(team, "militia", (b.tx + b.w / 2 + k - 1) * T + 16, (b.ty + b.h) * T + 16)
			u.order = "none"; n += 1
	if n > 0:
		tm.mustered = true
		if team == 0: host.toast("The Hearths answer: %d Militia" % n, "gold"); host.sfx("ready")
	return n

func upd_medic(u: Ent, dt: float) -> void:
	var d := u.d
	u.scan -= dt
	if u.scan <= 0:
		u.scan = 0.4
		if u.ht == null or not u.ht.alive or u.ht.hp >= u.ht.max_hp:
			u.ht = null
			var bd: float = (d.sight if u.order == "none" else (4.0 if u.order == "escort" else 2.5)) * T
			for o in ents:
				if not o.alive or o == u or o.kind != "u" or o.team != u.team or o.d.armor != "inf" or o.hp >= o.max_hp: continue
				var dd := Vector2(o.x - u.x, o.y - u.y).length()
				if dd < bd: bd = dd; u.ht = o
	var moving := false
	if u.ht != null and u.order != "move":
		var t: Ent = u.ht; var dist := Vector2(t.x - u.x, t.y - u.y).length()
		if dist <= d.range * T:
			u.ang = turn_to(u.ang, atan2(t.y - u.y, t.x - u.x), 16 * dt)
			if u.cd <= 0:
				t.hp = min(t.max_hp, t.hp + d.heal); u.cd = d.rof; u.flash = 0.25
				if u.team == 0: _tut("heal", t, u)
				parts.append({"k": "heal", "x": t.x, "y": t.y, "life": 0.8, "max": 0.8})
		else:
			u.rp -= dt
			if u.rp <= 0 or u.path.is_empty():
				u.rp = 0.8; u.path = route(u, int(t.x / T), int(t.y / T))
			moving = move_unit(u, dt)
	elif u.order == "escort": moving = follow_esc(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none": u.order = "none"
	u.moving = moving

func upd_eng(u: Ent, dt: float) -> void:
	var moving := false; var t: Ent = u.target
	if u.order == "capture" and t != null:
		if not t.alive or (t.team == u.team and t.hp >= t.max_hp):
			u.target = null; u.order = "none"; u.path = []
		elif dist_to_ent(u.x, u.y, t) < T * 0.85:
			if t.team != u.team:
				var was := t.team
				cancel_upgrade(t)
				t.team = u.team; t.seen = true; t.target = null; t.rally = null; t.hp = max(t.hp, t.max_hp * 0.5); calc_power()
				if u.team == 0:
					host.toast(t.d.name + " captured", "gold"); host.sfx("ready"); stats.killed += 1
				elif was == 0:
					host.toast(t.d.name + " lost to engineers", "warn"); host.sfx("alert")
				if sel.has(t): set_sel(sel.filter(func(x): return x != t))
				host.on_world_changed()
			else:
				t.hp = t.max_hp
				if u.team == 0: host.toast(t.d.name + " repaired", "gold"); host.sfx("ready"); _tut("eng_fix", t)
			for k in 6: parts.append({"k": "spark", "x": t.x + (randf() - 0.5) * 20, "y": t.y + (randf() - 0.5) * 20, "vx": (randf() - 0.5) * 50, "vy": (randf() - 0.5) * 50, "life": 0.4, "max": 0.4, "c": Color("#9df5b0"), "s": 2.0})
			u.alive = false; u.sel = false; _drop_sel(u)
			return
		else:
			u.rp -= dt
			if u.rp <= 0 or u.path.is_empty():
				u.rp = 0.9
				var n = nearest_walk(t.tx + (t.w >> 1), t.ty + t.h, int(u.x / T), int(u.y / T))
				if n == null: n = Vector2i(t.tx, t.ty)
				u.path = route(u, n.x, n.y)
			moving = move_unit(u, dt)
	elif u.order == "escort": moving = follow_esc(u, dt)
	else:
		moving = move_unit(u, dt)
		if u.path.is_empty() and u.order != "none": u.order = "none"
	u.moving = moving

func find_ore(u: Ent) -> int:
	var start := u.pref if (u.pref >= 0 and ore[u.pref] > 0) else t_idx(u)
	var taken := {}
	for o in ents:
		if o != u and o.alive and o.kind == "u" and (o.hs == "go" or o.hs == "mine"): taken[o.ot] = true
	var seen := PackedByteArray(); seen.resize(MW * MH)
	var q := [start]; seen[start] = 1; var qi := 0; var fallback := -1
	while qi < q.size() and qi < 2600:
		var c: int = q[qi]; qi += 1
		if ore[c] > 0:
			if not taken.has(c): return c
			if fallback < 0: fallback = c
		var cx := c % MW; var cy := c / MW
		for dxy in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + dxy[0]; var ny: int = cy + dxy[1]
			if not inb(nx, ny): continue
			var n := ny * MW + nx
			if seen[n]: continue
			seen[n] = 1
			if terr[n] < D.ROCK and bmap[n] == 0: q.append(n)
	return fallback

func upd_harv(u: Ent, dt: float) -> void:
	u.cd -= dt
	match u.hs:
		"manual":
			if u.path.is_empty(): u.hs = "idle"
		"idle":
			if u.team != 0:
				u.it -= dt
				if u.it <= 0: u.it = 3.0; u.hs = "find"
		"find":
			if u.load >= D.HARV_CAP: u.hs = "ret"; return
			var t := find_ore(u)
			if t < 0:
				u.hs = "ret" if u.load > 0 else "idle"; u.it = 4.0; return
			u.ot = t; set_path(u, t % MW, t / MW); u.hs = "go"
		"go":
			if ore[u.ot] == 0: u.hs = "find"; return
			if u.path.is_empty():
				var i := t_idx(u)
				if ore[i] > 0: u.hs = "mine"; u.mt = 0.3; u.ot = i
				elif Vector2(u.x - (u.ot % MW * T + 16), u.y - ((u.ot / MW) * T + 16)).length() < T * 1.2: u.hs = "mine"; u.mt = 0.3
				else: u.hs = "find"
		"mine":
			u.mt -= dt; u.ang += sin(time * 3) * dt * 0.3
			if u.mt <= 0:
				u.mt = 0.3
				var i := t_idx(u)
				if ore[i] == 0: i = u.ot
				if ore[i] == 0: u.hs = "find"; return
				u.load += take_ore(i, 20, u.d.drain)
				if randf() < 0.5: parts.append({"k": "smoke", "x": u.x + cos(u.ang) * 14, "y": u.y + sin(u.ang) * 14, "vx": (randf() - 0.5) * 14, "vy": -8.0, "life": 0.7, "max": 0.7, "s": 4.0, "c": Color8(170, 140, 70)})
				if u.load >= D.HARV_CAP: u.hs = "ret"
				elif ore[i] == 0: u.hs = "find"
		"ret":
			var best: Ent = null; var bd := 1e9
			for b in ents:
				if b.alive and b.kind == "b" and b.team == u.team and b.d.dock:
					var dd := Vector2(b.x - u.x, b.y - u.y).length()
					if dd < bd: bd = dd; best = b
			if best == null: u.hs = "idle"; u.it = 4.0; return
			u.ref = best; set_path(u, best.tx + best.w / 2, best.ty + best.h); u.hs = "toref"
		"toref":
			if u.ref == null or not u.ref.alive: u.hs = "ret"; return
			if u.path.is_empty():
				if dist_to_ent(u.x, u.y, u.ref) < T * 1.1: u.hs = "unload"; u.mt = 0.4; u.retry = 0
				else:
					u.retry += 1
					if u.retry > 3: u.hs = "idle"; u.it = 3.0; u.retry = 0
					else: u.hs = "ret"
		"unload":
			u.ang = turn_to(u.ang, -PI / 2, 3 * dt)
			if not u.ref.alive: u.hs = "ret"; return
			u.mt -= dt; u.ref.unload_t = time
			if u.mt <= 0:
				u.mt = 0.1
				var a: float = min(50.0, u.load); u.load -= a
				a *= float(u.ref.d.yield); u.dump += a
				var tm: Dictionary = teams[u.team]
				tm.credits += a * (D.DIFF[diff].inc if tm.ai else 1.0); tm.earned += a
				if u.team == 0: stats.mined += int(a)
				if u.load <= 0:
					u.load = 0.0; u.hs = "find"
					if u.team == 0: parts.append({"k": "txt", "x": u.ref.x, "y": u.ref.y, "txt": "+%d" % int(u.dump), "c": Color("f0b93f"), "life": 1.6, "max": 1.6, "h": 1.2})
					u.dump = 0.0

func upd_bld(b: Ent, dt: float) -> void:
	if b.hit_t > 0: b.hit_t -= dt
	if b.flash > 0: b.flash -= dt
	var d := b.d
	var tm: Dictionary = teams[b.team]
	if tm.ai and not b.repairing and b.hp < b.max_hp * 0.7 and tm.credits > 700 and b.d.kit == 0: b.repairing = true
	if b.repairing:
		if b.hp >= b.max_hp: b.repairing = false
		else:
			var add: float = min(b.max_hp * 0.07 * dt, b.max_hp - b.hp)
			var cost: float = d.cost * 0.5 * add / b.max_hp if d.cost else add * 0.3
			if tm.credits >= cost:
				tm.credits -= cost; b.hp += add; b.rp_t -= dt
				if b.rp_t <= 0:
					b.rp_t = 0.3
					parts.append({"k": "spark", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": 0.0, "vy": 0.0, "life": 0.35, "max": 0.35, "c": Color("#9df5b0"), "s": 2.5, "h0": 0.9})
			else:
				b.repairing = false
				if b.team == 0: host.toast("Insufficient aurite", "warn")
	if b.type == "repair":
		b.cd -= dt
		if b.cd <= 0:
			b.cd = 0.25; b.busy = false
			for u in ents:
				if not u.alive or u.kind != "u" or u.team != b.team or u.d.armor == "inf" or u.hp >= u.max_hp: continue
				if dist_to_ent(u.x, u.y, b) > T * 1.3: continue
				var add: float = min(14.0, u.max_hp - u.hp); var cost := add * 0.5
				if tm.credits < cost: continue
				tm.credits -= cost; u.hp += add; b.busy = true
				parts.append({"k": "spark", "x": u.x + (randf() - 0.5) * 12, "y": u.y + (randf() - 0.5) * 12, "vx": (randf() - 0.5) * 40, "vy": (randf() - 0.5) * 40, "life": 0.3, "max": 0.3, "c": Color("#9df5b0"), "s": 2.0})
	if b.hp < b.max_hp * 0.5:
		b.smoke_t -= dt
		if b.smoke_t <= 0:
			b.smoke_t = 0.22
			parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": (randf() - 0.5) * 8, "vy": -14.0, "life": 1.5, "max": 1.5, "s": 5.0, "c": Color8(40, 36, 32) if b.hp < b.max_hp * 0.25 else Color8(90, 86, 80)})
	aegis(b, dt)
	if b.dark:
		b.target = null; return
	if b.upg >= 0: upd_upgrade(b, tm, dt)
	if d.grow: upd_garden(b, tm, dt)
	if d.pump > 0: upd_drill(b, tm, dt)
	if d.thorn > 0:
		# Thornglass cuts enemy infantry that press against it
		b.gt += dt
		if b.gt >= 0.5:
			b.gt = 0.0
			for u in ents:
				if u.alive and u.kind == "u" and u.team != b.team and u.d.armor == "inf" and not u.d.air and not u.captive and dist_to_ent(u.x, u.y, b) < T * 0.7: damage(u, d.thorn * 0.5, "shard", null)
	if d.sw:
		b.ch = min(d.charge, b.ch + dt * (0.4 if low_power(b.team) else 1.0))
		if b.ch >= d.charge and not b.rdy:
			b.rdy = true
			if b.team == 0:
				host.toast(d.name + " ready", "gold"); host.sfx("ready"); host.on_sel_changed()
			else:
				host.toast("Enemy " + d.name + " is armed", "warn"); host.sfx("alert")
	if d.weapon == "": return
	if d.needPower and low_power(b.team):
		b.target = null; return
	b.cd -= dt * (0.4 if low_power(b.team) else 1.0)
	if b.target != null and (not b.target.alive or hid(b.target) or dist_to_ent(b.x, b.y, b.target) > d.range * T or (b.team == 0 and not visible_to_player(b.target)) or not has_shot(b, b.target, dt)):
		b.target = null
	b.scan -= dt
	if b.target == null and b.scan <= 0:
		b.scan = 0.4; b.target = find_target(b, d.range * T)
	if b.target != null:
		var want := atan2(b.target.y - b.y, b.target.x - b.x)
		b.tang = turn_to(b.tang, want, 4 * dt)
		if b.cd <= 0 and time >= b.jam_t and ang_diff(b.tang, want) < 0.12:
			fire(b, b.target, d); b.cd = d.rof

func launch_sw(b: Ent, x: float, y: float) -> void:
	var d := b.d
	b.ch = 0.0; b.rdy = false
	strikes.append({"x": x, "y": y, "t": 0.0, "kind": b.type, "team": b.team, "hit": 0, "done": false})
	if b.team == 1:
		host.toast("Enemy " + d.name + " launched!", "warn"); ping = {"x": x, "y": y, "t": time}
	else: host.toast(d.name + " launched", "gold"); _tut("launch", b.type)
	host.sfx("siren"); host.on_sel_changed()

func upd_strikes(dt: float) -> void:
	for s in strikes:
		s.t += dt
		if s.kind == "skyfall":
			if s.t > 2.2 and s.hit < 7 and s.t > 2.2 + s.hit * 0.16:
				var a := randf() * TAU; var r := randf() * T * 2.2
				var x: float = s.x + cos(a) * r; var y: float = s.y + sin(a) * r
				s.hit += 1; explode(x, y, 26); host.add_scorch(x, y, T * 1.2); sw_damage(x, y, T * 1.8, 260); host.sfx("bigboom", x, y)
			if s.t < 2.4 and randf() < 0.5:
				parts.append({"k": "missile", "x": s.x + (randf() - 0.5) * T * 4, "y": s.y + (randf() - 0.5) * T * 4, "h": 14.0, "vh": -6.0, "vx": 0.0, "vy": 0.0, "life": 2.2 - s.t, "max": 2.2})
		elif s.kind == "chorus":
			# the ground hums, then crystals burst up and stay as a field of shards
			if s.t < 2.6:
				parts.append({"k": "rift", "x": s.x, "y": s.y, "life": 0.4, "max": 0.4, "f": s.t / 2.6, "g": true})
				if randf() < 0.5: _dig(s.x + (randf() - 0.5) * T * 5, s.y + (randf() - 0.5) * T * 5, 1)
			if s.t >= 2.6 and not s.hit:
				s.hit = 1
				for k in 10:
					var a := k / 10.0 * TAU + randf() * 0.3; var r := T * (1.0 + randf() * 2.0)
					explode(s.x + cos(a) * r, s.y + sin(a) * r, 18)
				explode(s.x, s.y, 34); host.add_scorch(s.x, s.y, T * 2.6); sw_damage(s.x, s.y, T * 3.2, 750)
				add_field(s.x, s.y, T * 3.2, 18.0, s.team, 30.0); host.sfx("bigboom", s.x, s.y)
		else:
			if s.t < 3: parts.append({"k": "rift", "x": s.x, "y": s.y, "life": 0.4, "max": 0.4, "f": s.t / 3.0})
			if s.t >= 3 and not s.hit:
				s.hit = 1
				for k in 9:
					var a := k / 9.0 * TAU
					explode(s.x + cos(a) * T * 1.6, s.y + sin(a) * T * 1.6, 22)
				explode(s.x, s.y, 40); host.add_scorch(s.x, s.y, T * 3); sw_damage(s.x, s.y, T * 3.4, 900); host.sfx("bigboom", s.x, s.y)
		if s.t > 4: s.done = true
	strikes = strikes.filter(func(s): return not s.done)

func sw_damage(x: float, y: float, R: float, dmg: float) -> void:
	for o in ents:
		if not o.alive: continue
		var dd := dist_to_ent(x, y, o) if o.kind == "b" else Vector2(o.x - x, o.y - y).length()
		if dd < R: damage(o, dmg * (1 - dd / R * 0.6), "sw", null)

func separate() -> void:
	# bucket units by tile so we only compare neighbours
	var grid := {}
	var us: Array = []
	for e in ents:
		if e.kind == "u" and e.alive:
			us.append(e)
			var k := int(e.y / T) * MW + int(e.x / T)
			if grid.has(k): grid[k].append(e)
			else: grid[k] = [e]
	for a in us:
		if a.intun > 0: continue
		var ax := int(a.x / T); var ay := int(a.y / T)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var k := (ay + oy) * MW + ax + ox
				if not grid.has(k): continue
				for b in grid[k]:
					if b.id <= a.id or b.intun > 0: continue
					if a.d.air != b.d.air: continue
					var dx: float = b.x - a.x; var dy: float = b.y - a.y; var mn: float = (a.r + b.r) * 0.8
					if abs(dx) > mn or abs(dy) > mn: continue
					var d2 := dx * dx + dy * dy
					if d2 >= mn * mn: continue
					var nx: float; var ny: float; var dd: float
					if d2 < 0.01:
						var an := randf() * TAU; nx = cos(an); ny = sin(an); dd = 0.0
					else:
						dd = sqrt(d2); nx = dx / dd; ny = dy / dd
					var push := (mn - dd) * 0.5
					var wa := (0.3 if a.moving else 1.0) * (0.1 if (a.hs == "mine" or a.hs == "unload") else 1.0)
					var wb := (0.3 if b.moving else 1.0) * (0.1 if (b.hs == "mine" or b.hs == "unload") else 1.0)
					nudge(a, -nx * push * wa, -ny * push * wa); nudge(b, nx * push * wb, ny * push * wb)

func nudge(u: Ent, dx: float, dy: float) -> void:
	var nx := u.x + dx; var ny := u.y + dy
	var ok: bool = (nx > 4 and ny > 4 and nx < D.WW - 4 and ny < D.WH - 4) if u.d.air else passable(mob(u), int(nx / T), int(ny / T))
	if ok: u.x = nx; u.y = ny

func upd_proj(dt: float) -> void:
	for p in proj:
		var tg: Ent = p.t
		if tg.alive and not p.fixed:
			p.tx = tg.x + p.ox; p.ty = tg.y + p.oy; p.y1 = h_at(tg.x, tg.y) + p.aim
		var dx: float = p.tx - p.x; var dy: float = p.ty - p.y; var dd := sqrt(dx * dx + dy * dy); var st: float = p.spd * dt
		p.ang = atan2(dy, dx)
		if p.w == "rocket" and randf() < 0.8: parts.append({"k": "smoke", "x": p.x, "y": p.y, "vx": 0.0, "vy": 0.0, "life": 0.45, "max": 0.45, "s": 2.5, "c": Color8(200, 200, 200), "h0": p.h})
		var impact := dd <= st
		if not impact:
			p.x += dx / dd * st; p.y += dy / dd * st
			var prog: float = clamp(1.0 - Vector2(p.tx - p.x, p.ty - p.y).length() / p.d0, 0.0, 1.0)
			var arc: float = p.apex * 4.0 * prog * (1.0 - prog) if p.lob else sin(prog * PI) * 0.12
			p.h = lerp(float(p.y0), float(p.y1), prog) + arc
			# shells that meet a hill burst on it
			if p.h < h_at(p.x, p.y):
				p.h = h_at(p.x, p.y); p.tx = p.x; p.ty = p.y; p.ground = true; impact = true
		else:
			p.h = p.y1
		if impact:
			p.dead = true
			if p.splash > 0:
				for o in ents:
					if not o.alive or o.team == p.src_team: continue
					var od := dist_to_ent(p.tx, p.ty, o) if o.kind == "b" else Vector2(o.x - p.tx, o.y - p.ty).length()
					if od < p.splash: damage(o, p.dmg * (1 - od / p.splash * 0.6), p.w, p.src)
				explode(p.tx, p.ty, 10)
				if p.w == "geode": add_field(p.tx, p.ty, T * 1.3, 7.0, p.src_team, 12.0)
			elif tg.alive and not p.get("ground", false): damage(tg, p.dmg, p.w, p.src)
			var hh: float = p.h
			parts.append({"k": "flash", "x": p.tx, "y": p.ty, "life": 0.15, "max": 0.15, "s": 12.0 if p.w == "shell" else (10.0 if p.w == "flak" else 9.0), "h0": hh})
			for i in 4:
				var a := randf() * TAU
				parts.append({"k": "spark", "x": p.tx, "y": p.ty, "vx": cos(a) * 80, "vy": sin(a) * 80, "life": 0.2, "max": 0.2, "c": Color("#ffcf6a"), "s": 1.5, "h0": hh})
			parts.append({"k": "smoke", "x": p.tx, "y": p.ty, "vx": 0.0, "vy": -10.0, "life": 0.6, "max": 0.6, "s": 5.0, "c": Color8(40, 38, 36) if p.w == "flak" else Color8(70, 64, 58), "h0": hh})
			host.sfx("small", p.tx, p.ty)
	proj = proj.filter(func(p): return not p.dead)

func upd_parts(dt: float) -> void:
	for p in parts:
		p.life -= dt
		if p.has("vx"): p.x += p.vx * dt; p.y += p.vy * dt
		if p.has("vh"):
			p.h += p.vh * dt; p.vh -= 9 * dt
			if p.h < 0.03:
				p.h = 0.03; p.vh = -p.vh * 0.3 if abs(p.vh) > 0.8 else 0.0; p.vx *= 0.5; p.vy *= 0.5
	parts = parts.filter(func(p): return p.life > 0)
	if parts.size() > 900: parts = parts.slice(parts.size() - 900)

func update_vision() -> void:
	if cine:
		vis.fill(2)
		for b in ents: b.seen = true
		host.on_vision(); return
	for i in vis.size():
		if vis[i] == 2: vis[i] = 1
	for e in ents:
		if not e.alive or e.team != 0: continue
		var r: float = e.d.sight if e.kind == "u" else e.d.sight + e.w / 2.0
		var cx: float = e.x / T; var cy: float = e.y / T; var r2 := r * r
		for y in range(maxi(0, int(floor(cy - r))), mini(MH - 1, int(ceil(cy + r))) + 1):
			for x in range(maxi(0, int(floor(cx - r))), mini(MW - 1, int(ceil(cx + r))) + 1):
				var dx := x + 0.5 - cx; var dy := y + 0.5 - cy
				if dx * dx + dy * dy <= r2: vis[y * MW + x] = 2
	for b in ents:
		if b.kind != "b" or b.team == 0 or b.seen or not b.alive: continue
		for y in range(b.ty, b.ty + b.h):
			for x in range(b.tx, b.tx + b.w):
				if vis[y * MW + x] == 2: b.seen = true
	host.on_vision()

# ---------------- production ----------------
func upd_prod(tm: Dictionary, dt: float) -> void:
	var mult: float = (0.5 if low_power(tm.id) else 1.0) * (D.DIFF[diff].prod if tm.ai else 1.0)
	for cat in D.CAT_ORDER:
		var q: Dictionary = tm.prod[cat]
		if q.cur == "" and q.queue.size():
			if cat != "bld" and cap_full(tm.id, q.queue[0]):
				if tm.id == 0:
					tm.noFundsT -= dt
					if tm.noFundsT <= 0: tm.noFundsT = 8.0; host.toast("Unit cap reached", "warn")
				continue
			if cat != "bld" and D.rule(tm.fac, "pods") and not take_pod(tm.id):
				if tm.id == 0:
					tm.noFundsT -= dt
					if tm.noFundsT <= 0: tm.noFundsT = 8.0; host.toast("No ripe Pod: Gardens ripen one every %d s" % int(D.HUM.pod), "warn")
				continue
			q.cur = q.queue.pop_front(); q.prog = 0.0; q.paid = 0.0
		if q.cur == "" or q.ready: continue
		var d: Dictionary = D.def_of(q.cur)
		if cat != "bld" and not has_live(tm.id, unit_from(tm.id, q.cur)): continue
		if cat == "bld" and not has_req(tm.id, d.req):
			tm.credits += q.paid; q.cur = ""; continue
		var tt: float = D.AEGIS.prefab if (cat == "bld" and D.rule(tm.fac, "place") == "signal") else d.time   # every Vanguard prefab arrives in the same few seconds
		var rate: float = min(dt * mult * (prod_speed(tm.id, cat) if cat != "bld" else 1.0) / tt, 1.0 - q.prog); var cost: float = d.cost * rate
		if tm.credits - fuel_reserve(tm.id) >= cost:
			tm.credits -= cost; q.paid += cost; q.prog += rate
			if q.prog >= 1 - 1e-6:
				if cat == "bld":
					q.ready = true
					if tm.id == 0: host.toast("Construction complete", "gold"); host.sfx("ready")
				else:
					# LOOP on its producer: what just finished goes back to the end of the line (not one-of-a-kind units)
					if tm.get("loop", {}).get(unit_from(tm.id, q.cur), false) and D.def_of(q.cur).lim <= 0: q.queue.append(q.cur)
					produce_done(tm, q.cur); q.cur = ""
		elif tm.id == 0:
			tm.noFundsT -= dt
			if tm.noFundsT <= 0: tm.noFundsT = 8.0; host.toast("Insufficient aurite", "warn")

## Ripe Pods in all the team's Gardens.
func pods(team: int) -> int:
	var n := 0
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and b.d.grow: n += b.pods
	return n

## Takes one ripe Pod from the Garden that has the most. False when none is ripe.
func take_pod(team: int) -> bool:
	var best: Ent = null
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and b.d.grow and b.pods > 0 and (best == null or b.pods > best.pods): best = b
	if best == null: return false
	best.pods -= 1; best.out_t = time
	return true

## True when the team has a working (not dark) building of this type.
func has_live(team: int, type: String) -> bool:
	for e in ents:
		if e.alive and e.kind == "b" and e.team == team and e.type == type and not e.dark: return true
	return false

## The point on the map edge nearest to (x, y), in pixels.
func edge_near(x: float, y: float) -> Vector2:
	var W: float = MW * T; var H: float = MH * T
	var c := [[x, Vector2(8, y)], [W - x, Vector2(W - 8, y)], [y, Vector2(x, 8)], [H - y, Vector2(x, H - 8)]]
	c.sort_custom(func(a, b): return a[0] < b[0])
	return c[0][1]

## Vanguard delivery: a dropship leaves the map edge with the order on board and sets it down at the Landing Zone.
func send_dropship(tm: Dictionary, type: String, b: Ent) -> Ent:
	var d: Dictionary = D.UN[type]
	var e := edge_near(b.x, b.y)
	var u := spawn_unit(tm.id, "dropship", e.x, e.y)
	u.x = e.x; u.y = e.y
	u.cargo = d.cargo.duplicate() if d.cargo.size() else [type]
	u.paid = d.cost; u.lz = b; u.guard = e; u.post = true; u.ang = atan2(b.y - e.y, b.x - e.x)
	if tm.id == 0: host.toast(d.name + " inbound"); host.sfx("ready")
	return u

func upd_dropship(u: Ent, dt: float) -> void:
	aegis(u, dt)
	var goal: Vector2
	if u.leaving: goal = u.guard
	else:
		if u.lz == null or not u.lz.alive:
			# its pad is gone: any other pad, else the Yard, else wherever it is
			u.lz = null
			for b in ents:
				if b.alive and b.kind == "b" and b.team == u.team and (b.d.pad or (u.lz == null and b.type == "hq")): u.lz = b
		goal = Vector2(u.lz.x, u.lz.y) if u.lz != null else Vector2(u.x, u.y)
	var v := goal - Vector2(u.x, u.y); var dist := v.length()
	var st: float = u.d.spd * T * dt * (1.0 if u.leaving or dist > T * 3 else 0.45)
	u.moving = true
	if dist > st:
		u.x += v.x / dist * st; u.y += v.y / dist * st; u.ang = turn_to(u.ang, v.angle(), 5 * dt)
		return
	if u.leaving:
		u.alive = false; _drop_sel(u); return   # off the map, no wreck
	var tm: Dictionary = teams[u.team]
	for c in u.cargo: roll_out(tm, c, u.lz, u.x, u.y)
	if tm.id == 0: host.toast("Delivery landed", "gold"); host.sfx("ready"); _tut("made", u.cargo[0])
	u.cargo = []; u.leaving = true
	if u.lz != null: u.lz.out_t = time

## Puts a finished order on the ground by its building (or where the dropship set it down) and sends it to the rally point.
func roll_out(tm: Dictionary, type: String, b: Ent, px := -1.0, py := -1.0) -> void:
	var d: Dictionary = D.UN[type]
	var ex := int(px / T) if (b == null or px >= 0) else b.tx + b.w / 2
	var ey := int(py / T) if (b == null or px >= 0) else b.ty + b.h
	if b != null and b.d.pad:
		ex = b.tx + b.w / 2; ey = b.ty + b.h / 2
	if d.mob == 1 and not d.air:
		# a boat is set down on the nearest open water, however far that is
		var bd := 1e9; var w = null
		for i in MW * MH:
			if passable(1, i % MW, i / MW):
				var dd := Vector2(i % MW - ex, i / MW - ey).length_squared()
				if dd < bd: bd = dd; w = Vector2i(i % MW, i / MW)
		if w == null:
			tm.credits += d.cost
			if tm.id == 0: host.toast("No water to set the " + d.name + " down on: refunded", "warn")
			return
		ex = w.x; ey = w.y
	# a pack (Slag Boars, Hornet Drones) comes out as several
	for k in int(d.pack):
		var u := spawn_unit(tm.id, type, ex * T + 16 + k * 10, ey * T + 16)
		if d.harv: u.hs = "find"
		else:
			var rp = (b.rally if b != null and b.rally != null else tm.rally)
			if d.mob == 1: rp = null   # a boat stays where the water is
			u.order = "move"
			if rp != null:
				var s := slots_around(int(rp.x / T), int(rp.y / T), 1 + randi() % 6)
				var t: Vector2i = s[-1] if s.size() else Vector2i(int(rp.x / T), int(rp.y / T))
				set_path(u, t.x, t.y)
			else:
				var s := slots_around(ex, ey + (3 if b != null and b.d.pad else 1), 1 + randi() % 5)
				var t: Vector2i = s[-1] if s.size() else Vector2i(ex, ey + 1)
				if d.mob != 1: set_path(u, t.x, t.y)

func produce_done(tm: Dictionary, type: String) -> void:
	var d: Dictionary = D.UN[type]
	var bs: Array = ents.filter(func(e): return e.alive and e.kind == "b" and e.team == tm.id and e.type == unit_from(tm.id, type) and not e.dark)
	if bs.is_empty(): return
	var b: Ent = bs[-1]
	for x in bs:
		if x.sel: b = x; break
	if tm.id == 0: stats.built += 1
	if b.d.pad:
		send_dropship(tm, type, b); return
	var ex := b.tx + b.w / 2; var ey := b.ty + b.h
	b.out_t = time
	# a pack (Slag Boars) comes out as several animals
	for k in int(d.pack):
		var u := spawn_unit(tm.id, type, ex * T + 16 + k * 10, ey * T + 16)
		if d.harv: u.hs = "find"
		else:
			var rp = b.rally if b.rally != null else tm.rally
			u.order = "move"
			if rp != null:
				var s := slots_around(int(rp.x / T), int(rp.y / T), 1 + randi() % 6)
				var t: Vector2i = s[-1] if s.size() else Vector2i(int(rp.x / T), int(rp.y / T))
				set_path(u, t.x, t.y)
			else:
				var s := slots_around(ex, ey + 1, 1 + randi() % 5)
				var t: Vector2i = s[-1] if s.size() else Vector2i(ex, ey + 1)
				set_path(u, t.x, t.y)
	if tm.id == 0: host.toast(d.name + " ready"); host.sfx("ready"); _tut("made", type)

## A building just went down on top of some of the team's own ground units: each walks straight out to the nearest
## free tile beside the footprint (Guillaume 2026-11-28: "allow building on a unit, it will move automatically").
func clear_footprint(b: Ent) -> void:
	for u in ents:
		if u.kind != "u" or not u.alive or u.team != b.team or u.d.air or u.intun > 0: continue
		var ux := int(u.x / T); var uy := int(u.y / T)
		if ux < b.tx or ux >= b.tx + b.w or uy < b.ty or uy >= b.ty + b.h: continue
		var best = null; var bd := 1e9
		for y in range(b.ty - 1, b.ty + b.h + 1):
			for x in range(b.tx - 1, b.tx + b.w + 1):
				if not walk(x, y): continue
				var dd := Vector2(x * T + 16.0 - u.x, y * T + 16.0 - u.y).length()
				if dd < bd: bd = dd; best = Vector2i(x, y)
		if best == null: best = nearest_walk(ux, uy, ux, uy)
		if best == null: continue
		u.path = [best]; u.dest = best; u.order = "move"; u.target = null; u.auto = false; u.guard = null; u.stuck = 0
		if u.d.harv: u.hs = "idle"
		u.wk = null

func can_place(team: int, type: String, tx: int, ty: int, gap: bool) -> bool:
	var d: Dictionary = D.BLD[type]
	for y in range(ty, ty + d.h):
		for x in range(tx, tx + d.w):
			if not inb(x, y): return false
			var i := y * MW + x
			if terr[i] >= D.ROCK or (ore[i] > 0 and not d.onore) or bmap[i]: return false
			if team == 0 and vis[i] == 0: return false
	if d.shore and not water_beside(tx, ty, d.w, d.h): return false
	if d.onore and live_ore(tx + d.w / 2.0, ty + d.h / 2.0, 2.5) == 0: return false
	if gap:
		for y in range(ty - 1, ty + d.h + 1):
			for x in range(tx - 1, tx + d.w + 1):
				if inb(x, y) and bmap[y * MW + x]: return false
		if d.dock or d.door or d.tun:
			var ex: int = tx + d.w / 2; var ey: int = ty + d.h
			if not walk(ex, ey) or not walk(ex, ey + 1): return false
	if team == 0:
		for u in ents:
			# the player's own units step aside (clear_footprint); anyone else's in the way still blocks
			if u.kind != "u" or not u.alive or u.d.air or u.team == team: continue
			var ux := int(u.x / T); var uy := int(u.y / T)
			if ux >= tx and ux < tx + d.w and uy >= ty and uy < ty + d.h: return false
	if d.field and live_ore(tx + d.w / 2.0, ty + d.h / 2.0, 3.5) == 0: return false
	if d.tun or d.shore or d.field:
		# a burrow, a shipyard or a Garden can go anywhere the team has seen, but not right under an enemy base
		for b in ents:
			if b.kind == "b" and b.alive and b.team != team and Vector2(b.x - (tx + d.w / 2.0) * T, b.y - (ty + d.h / 2.0) * T).length() < T * 7: return false
		return true
	if D.rule(fac_of(team), "place") == "signal": return in_signal(team, tx + d.w / 2.0, ty + d.h / 2.0)
	if D.rule(fac_of(team), "place") == "hum": return in_hum(team, (tx + d.w / 2.0) * T, (ty + d.h / 2.0) * T)
	for b in ents:
		if b.kind != "b" or not b.alive or b.team != team: continue
		var gx := maxi(maxi(b.tx - (tx + d.w), tx - (b.tx + b.w)), 0); var gy := maxi(maxi(b.ty - (ty + d.h), ty - (b.ty + b.h)), 0)
		if maxi(gx, gy) <= 2: return true
	return false

func tile_ok(tx: int, ty: int) -> bool:
	if not inb(tx, ty): return false
	var i := ty * MW + tx
	return terr[i] < D.ROCK and ore[i] == 0 and bmap[i] == 0 and vis[i] != 0

func sell(b: Ent) -> int:
	var ref := int(floor(b.d.cost * 0.5 * b.hp / b.max_hp + max(b.upaid, 0.0)))
	b.upg = -1.0; b.upaid = 0.0
	teams[b.team].credits += ref
	b.alive = false; b.sel = false; b.end_kind = "sell"; b.end_t = time
	if ref > 0: parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "+%d" % ref, "c": Color("f0b93f"), "life": 1.8, "max": 1.8, "h": D.BH[b.type] + .3})
	for y in range(b.ty, b.ty + b.h):
		for x in range(b.tx, b.tx + b.w):
			if bmap[y * MW + x] == b.id: bmap[y * MW + x] = 0
	_sync_solid(b.tx, b.ty, b.w, b.h)
	for k in 8: parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": b.ty * T + randf() * b.h * T, "vx": (randf() - 0.5) * 30, "vy": -randf() * 10, "life": 0.7, "max": 0.7, "s": 3.5, "c": Color8(196, 184, 156)})
	calc_power(); host.on_world_changed()
	return ref

# ---------------- upgrades ----------------
## The upgrade a building can take, or {} (none, already upgraded, or not this faction's).
func upg_def(b: Ent) -> Dictionary:
	if b == null or b.kind != "b" or not D.UPG.has(b.type): return {}
	if b.lv == 2: return D.UPG3.get(b.type, {})
	return D.UPG[b.type] if b.lv == 1 else {}

## Why the building cannot start its upgrade now ("" when it can).
func upg_block(b: Ent) -> String:
	var u := upg_def(b)
	if u.is_empty(): return "No upgrade"
	if b.upg >= 0: return "Upgrading"
	if not has_req(b.team, u.req): return "Requires " + " + ".join(req_of(b.team, u.req).map(func(r): return D.BLD[r].name))
	return ""

func start_upgrade(b: Ent) -> bool:
	if upg_block(b) != "": return false
	b.upg = 0.0; b.upaid = 0.0
	if b.team == 1 and visible_to_player(b): host.toast("Enemy " + b.d.name + " is upgrading", "warn")
	return true

func cancel_upgrade(b: Ent) -> void:
	if b.upg < 0: return
	teams[b.team].credits += b.upaid
	b.upg = -1.0; b.upaid = 0.0

## Pays and builds a running upgrade like a production queue: slower on low power, stalls without aurite.
func upd_upgrade(b: Ent, tm: Dictionary, dt: float) -> void:
	var u: Dictionary = upg_def(b)
	var mult: float = (0.5 if low_power(b.team) else 1.0) * (D.DIFF[diff].prod if tm.ai else 1.0)
	var rate: float = min(dt * mult / u.time, 1.0 - b.upg); var cost: float = u.cost * rate
	if tm.credits < cost:
		if b.team == 0:
			tm.noFundsT -= dt
			if tm.noFundsT <= 0: tm.noFundsT = 8.0; host.toast("Insufficient aurite", "warn")
		return
	tm.credits -= cost; b.upaid += cost; b.upg += rate
	if b.upg >= 1 - 1e-6: finish_upgrade(b)

func finish_upgrade(b: Ent) -> void:
	var nd: Dictionary = D.BLD2[b.type] if b.lv == 1 else D.BLD3[b.type]
	var fr: float = b.hp / b.max_hp; var old_hp: float = b.d.hp
	b.d = nd; b.lv += 1; b.upg = -1.0; b.upaid = 0.0; b.up_t = time
	b.max_hp = nd.hp; b.hp = min(nd.hp, max(fr, 0.0) * nd.hp + (nd.hp - old_hp))
	calc_power()
	if b.team == 0:
		host.toast(nd.name + " online", "gold"); host.sfx("ready"); _tut("upgrade", b.type)
		parts.append({"k": "txt", "x": b.x, "y": b.y, "txt": "UPGRADED", "c": Color("f0b93f"), "life": 2.0, "max": 2.0, "h": D.BH[b.type] + .4})
	elif visible_to_player(b): host.toast("Enemy " + nd.name + " online", "warn")
	host.on_world_changed(); host.on_sel_changed()

## Training speed of a category: an upgraded producer (Drill Hall, Heavy Works) speeds up its whole queue.
func prod_speed(team: int, cat: String) -> float:
	var p := producer(team, cat)
	var best := 1.0
	for b in ents:
		if b.alive and b.kind == "b" and b.team == team and b.type == p: best = max(best, float(b.d.speed))
	return best

func set_sel(list: Array) -> void:
	for e in sel: e.sel = false
	list = list.filter(func(e): return not (e.kind == "u" and e.d.ship))   # delivery dropships fly themselves
	sel = list
	for e in list: e.sel = true
	host.on_sel_changed()

# ---------------- AI ----------------
func ai_think(tm: Dictionary) -> void:
	var id: int = tm.id; var q: Dictionary = tm.prod.bld; var F: Dictionary = D.FACS[tm.fac]; var M = mission
	var hq := find_hq(id)
	if hq == null: return
	var ok := func(t: String) -> bool: return t != "" and avail(id, t) and has_req(id, D.def_of(t).req) and not at_limit(id, t)
	# upgrades: always in skirmish, only on Hard in the campaigns (Normal stays as beatable as before)
	var ai_ups: bool = (not M) or (M.aiBuild and lvl == "hard")
	if tm.fac == "choir" and (not M or M.aiBuild):
		# the Choir's whole tech is the age of its Gardens: it always lets one age
		# (an age is paid for as it grows, so it can start on a thin purse)
		if not _ai_upgrading(id, "garden") and count(id, "garden") >= 2:
			for b in ents:
				if b.alive and b.team == id and b.kind == "b" and b.d.grow and not upg_def(b).is_empty() and upg_block(b) == "" and tm.credits >= 300:
					start_upgrade(b); break
		# Gardens are its only income, so it keeps planting while there is living aurite to plant beside
		tm.plant = q.cur == "" and not q.ready and count(id, "garden") < mini(7, 2 + int(time / 110.0)) and ok.call("garden") and ai_spot(id, "garden", hq) != null
		if tm.plant and tm.credits >= 500:
			q.cur = "garden"; tm.plant = false
		# and four idle Thralls out of every six fuse into a Knot
		var th := ents.filter(func(e): return e.alive and e.team == id and e.kind == "u" and e.d.fuse != "" and e.order == "none" and e.target == null)
		if th.size() >= D.HUM.fuse + 2: fuse(id, th)
	elif ai_ups and not _ai_upgrading(id, ""):
		for t in D.AI_UPG:
			if t == "power" and tm.pused + 60 <= tm.pmade: continue
			if _ai_upgrade(tm, t, 800): break
	if not M or M.aiBuild:
		# Vanguard: a Deep Drill that has pumped its field dry is sold, and the next one goes to a live field
		var dr := tr_t(id, "refinery")
		var pumps: bool = D.BLD.has(dr) and D.BLD[dr].pump > 0
		if pumps:
			for b in ents:
				if b.alive and b.kind == "b" and b.team == id and b.dry and b.d.pump > 0: sell(b); break
		if q.ready:
			var spot = ai_spot(id, q.cur, hq)
			tm.stall = 0 if spot != null else tm.get("stall", 0) + 1
			if spot != null:
				add_building(id, q.cur, spot.x, spot.y); q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0
				if D.BLD[tr_t(id, "power")].signal > 0: ai_aim.erase(id)
			elif tm.stall > 12:
				# nowhere to put it: take the money back and think again
				tm.credits += q.paid; tm.stall = 0; q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0
			elif D.BLD[q.cur].shore:
				# water in sight but no berth to build on: take the money back and stop asking
				tm.credits += q.paid; ai_dry[id] = true; q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0
		elif q.cur == "":
			var nxt := ""
			var pw := tr_t(id, "power")
			var cm := cap_max(id)
			# a cold Furnace still counts: building more of them would only burn aurite faster
			var pm: int = tm.pmade
			for b in ents:
				if b.alive and b.kind == "b" and b.team == id and b.cold: pm += int(b.d.pwr)
			var capb: String = F.get("cap_bld", "")
			var drills := 0
			for b in ents:
				if b.alive and b.kind == "b" and b.team == id and b.d.pump > 0 and not b.dry: drills += 1
			if pumps and drills < (2 if time < 240 else 3) + (1 if diff == "hard" else 0) and ok.call(dr) and (drills == 0 or tm.credits > 1200):
				if ai_spot(id, dr, hq) != null: nxt = dr
				else:
					# no live field inside Signal: walk a Mast out toward the nearest one
					var aim = ai_ore(id, hq)
					if aim != null and ok.call(tr_t(id, "power")): ai_aim[id] = aim; nxt = tr_t(id, "power")
			elif cm > 0 and cap_used(id) + 6 > cm and cm < 200 and ok.call(capb): nxt = capb
			elif uses_power(id) and tm.pused + 20 > pm and count(id, pw) < 10 and avail(id, pw):
				# an upgrade running on a reactor (or one it can start now) beats a new reactor
				if not (ai_ups and (_ai_upgrading(id, pw) or _ai_upgrade(tm, pw, 200))): nxt = pw
			else:
				var need := {}
				for t0 in F.get("ai_order", D.AI_ORDER):
					var t: String = t0
					if t == "DEF": t = F.def
					if t == "SW": t = F.sw
					if t == "TUN": t = F.get("tun", "")
					if t == "NAVAL": t = F.get("naval", "")
					# a shipyard only where the base has a shore in reach
					if t != "" and D.BLD.has(t) and D.BLD[t].shore and (count(id, t) > 0 or ai_dry.has(id) or shore_near(hq) == null): continue
					t = D.sub(tm.fac, t)
					if t == "" or not avail(id, t) or (t == "power" and not uses_power(id)): continue
					if D.BLD[t].pump > 0: continue   # drills are handled above
					need[t] = need.get(t, 0) + 1
					if count(id, t) < need[t]: nxt = t; break
			if nxt != "" and ok.call(nxt): q.cur = nxt
	if not M or M.aiProd:
		var harvs := count(id, "harv"); var refs := count(id, "refinery")
		var hv := tr_t(id, "harv")
		var vq: Dictionary = tm.prod.veh; var iq: Dictionary = tm.prod.inf; var aq: Dictionary = tm.prod.air
		var pick := func(l: Array) -> String:
			var f := l.filter(func(t): return ok.call(t))
			return f[randi() % f.size()] if f.size() else ""
		if count(id, "factory") and vq.cur == "" and vq.queue.is_empty():
			if refs and harvs < mini(refs * 2, 3) and ok.call(hv): vq.queue.append(hv)
			elif tm.credits > 500 or q.cur == "":
				var sea: Array = F.get("ai_sea", [])
				var nv: String = F.get("naval", "")
				var u: String = pick.call(sea) if (sea.size() and ((count(id, nv) > 0 and randf() < 0.3) if nv != "" else (randf() < 0.1 and shore_near(hq) != null))) else ""
				if u == "": u = pick.call(F.get("ai_veh", [F.lv, F.mt, F.mt, F.mt, D.sub(tm.fac, "arty"), F.ht, F.ht]))
				if u != "": vq.queue.append(u)
		if count(id, "barracks") and iq.cur == "" and iq.queue.is_empty() and (tm.credits > 300 or q.cur == ""):
			var rf := D.sub(tm.fac, "rifle")
			var u: String = pick.call(F.get("ai_inf", [rf, rf, "lancer", "lancer", "medic", F.inf, F.inf]))
			if F.get("hero", "") != "" and tm.credits > 2200 and ok.call(F.hero): u = F.hero
			if u != "":
				iq.queue.append(u)
		var airs: Array = F.get("ai_air", [F.air])
		if count(id, "helipad") and aq.cur == "" and aq.queue.is_empty() and tm.credits > 900 and airs.reduce(func(n, t): return n + count(id, t), 0) < 4 + (2 if diff == "hard" else 0):
			var a: String = pick.call(airs)
			if a != "": aq.queue.append(a)
	# superweapon
	for b in ents:
		if b.alive and b.team == id and b.kind == "b" and b.rdy:
			var best: Ent = null; var bs := -1
			for o in ents:
				if not o.alive or o.team == id or o.kind != "b" or o.d.kit > 0: continue
				var sc := 0
				for p in ents:
					if p.alive and p.team != id and Vector2(p.x - o.x, p.y - o.y).length() < T * 3: sc += 3 if p.kind == "b" else 1
				if sc > bs: bs = sc; best = o
			if best != null: launch_sw(b, best.x, best.y)
	var army := ents.filter(func(e): return e.alive and e.team == id and e.kind == "u" and not e.d.harv and not e.d.eng and not e.d.ship and not e.post and not (M and e.d.hero))
	var idle := army.filter(func(u): return u.order == "none" and u.target == null)
	var intr: Ent = null
	for e in ents:
		if not e.alive or e.team == id or e.kind != "u" or e.captive: continue
		if Vector2(e.x - hq.x, e.y - hq.y).length() < 13 * T: intr = e; break
	if intr != null:
		for b in ents:
			if b.alive and b.team == id and b.kind == "b" and b.d.muster > 0 and not tm.get("mustered", false): muster(id)
		for u in idle:
			if (Vector2(u.x - intr.x, u.y - intr.y).length() < 20 * T and can_hit(u.d, intr)) or u.d.heal:
				u.order = "amove"; set_path(u, int(intr.x / T), int(intr.y / T))
		return
	var first: float = ((M.aiFirst if M.aiFirst >= 0 else D.DIFF[diff].first) + D.LEVELS[lvl].first) if M else D.DIFF[diff].first
	if time > first and idle.size() >= tm.wave:
		var tgt: Ent = null; var bd := 1e9
		for e in ents:
			if not e.alive or e.team == id or e.captive: continue
			var dd := Vector2(e.x - hq.x, e.y - hq.y).length() + (T * 8 if e.kind == "u" else 0)
			if dd < bd: bd = dd; tgt = e
		if tgt != null:
			group_move(idle, tgt.x, tgt.y, "amove"); tm.wave = mini(tm.wave + 2, 16)

func _ai_upgrading(id: int, type: String) -> bool:
	for b in ents:
		if b.alive and b.team == id and b.kind == "b" and b.upg >= 0 and (type == "" or b.type == type): return true
	return false

## Starts the upgrade of one of the team's buildings of this type when it keeps `spare` aurite in hand.
func _ai_upgrade(tm: Dictionary, type: String, spare: float) -> bool:
	for b in ents:
		if b.alive and b.team == tm.id and b.kind == "b" and b.type == type and upg_block(b) == "" and tm.credits >= upg_def(b).cost + spare:
			return start_upgrade(b)
	return false

## The water tile nearest the AI's HQ, or null on a dry map (no dice, so it doesn't shift the game's random rolls).
func shore_near(hq: Ent):
	var best = null; var bd := 1e9
	for i in MW * MH:
		if terr[i] != D.WATER: continue
		var dd := Vector2(i % MW - hq.tx, i / MW - hq.ty).length_squared()
		if dd < bd: bd = dd; best = Vector2i(i % MW, i / MW)
	return best

## The live ore tile nearest the HQ that none of the team's drills reaches yet (null when the map has none left).
func ai_ore(id: int, hq: Ent):
	var best = null; var bd := 1e9
	for i in MW * MH:
		if ore[i] <= 0: continue
		var x := i % MW; var y := i / MW
		var dd := Vector2(x - hq.tx, y - hq.ty).length()
		if dd >= bd: continue
		var taken := false
		for b in ents:
			if b.alive and b.kind == "b" and b.team == id and b.d.pump > 0 and Vector2(b.x / T - x, b.y / T - y).length() < 5.5: taken = true; break
		if not taken: bd = dd; best = Vector2i(x, y)
	return best

func ai_spot(id: int, type: String, hq: Ent, home := false):
	var d: Dictionary = D.BLD[type]; var best = null; var bs := 1e9
	if d.signal > 0 and ai_aim.has(id):
		# a Mast walking toward a field: the free tile inside Signal that is nearest to it
		var aim: Vector2i = ai_aim[id]
		for b in ents:
			if not (b.alive and b.kind == "b" and b.team == id and b.d.signal > 0): continue
			var R := int(b.d.signal)
			for ty in range(int(b.y / T) - R, int(b.y / T) + R + 1):
				for tx in range(int(b.x / T) - R, int(b.x / T) + R + 1):
					var s: float = Vector2(tx - aim.x, ty - aim.y).length()
					if s < bs and s > 2.5 and can_place(id, type, tx, ty, true): bs = s; best = Vector2i(tx, ty)
		if best != null: return best
	if d.pump > 0:
		# a drill: the placeable spot with the most live ore in reach, anywhere inside Signal
		for ty in range(2, MH - 3):
			for tx in range(2, MW - 3):
				if ore[ty * MW + tx] <= 0 and ore[ty * MW + tx + 1] <= 0 and ore[(ty + 1) * MW + tx] <= 0: continue
				if not can_place(id, type, tx, ty, false): continue
				var near := false
				for b in ents:
					if b.alive and b.kind == "b" and b.team == id and b.d.pump > 0 and Vector2(b.x / T - tx - 1, b.y / T - ty - 1).length() < 5.0: near = true; break
				if near: continue
				var s: float = -live_ore(tx + 1.0, ty + 1.0, 4.5) / 400.0 + Vector2(tx - hq.tx, ty - hq.ty).length() * 0.5
				if s < bs: bs = s; best = Vector2i(tx, ty)
		return best
	var ores: Array = []
	var eco: bool = d.dock or d.grow
	if eco:
		for i in MW * MH:
			if ore[i]: ores.append(i)
	var cx := hq.tx + 1; var cy := hq.ty + 1
	var fwd = null
	if d.tun and not home:
		# burrows go forward, part way to the nearest enemy building, a little further for each one dug
		var en: Ent = null; var ed := 1e9
		for e in ents:
			if e.alive and e.kind == "b" and e.team != id:
				var dd := Vector2(e.x - hq.x, e.y - hq.y).length()
				if dd < ed: ed = dd; en = e
		if en == null: return null
		var f: float = clamp(0.3 + 0.12 * count(id, type), 0.3, 0.6)
		fwd = Vector2(lerp(hq.x, en.x, f) / T, lerp(hq.y, en.y, f) / T)
		cx = int(fwd.x); cy = int(fwd.y)
	if d.shore:
		# a shipyard goes out to the nearest bank, however far from the base that is
		var w = shore_near(hq)
		if w == null: return null
		cx = w.x; cy = w.y
	for ty in range(cy - 12, cy + 13):
		for tx in range(cx - 12, cx + 13):
			if not can_place(id, type, tx, ty, true): continue
			var mx: float = tx + d.w / 2.0; var my: float = ty + d.h / 2.0; var s: float
			if fwd != null: s = Vector2(mx - fwd.x, my - fwd.y).length() + randf() * 3
			elif eco:
				s = 1e9
				for o in ores:
					var dd := Vector2(o % MW - mx, o / MW - my).length()
					if dd < s: s = dd
				s += randf() * 2
			elif d.weapon != "": s = Vector2(mx - MW / 2.0, my - MH / 2.0).length() + randf() * 4
			elif d.shore: s = Vector2(mx - hq.tx, my - hq.ty).length() + randf() * 2
			else: s = Vector2(mx - cx, my - cy).length() + randf() * 3
			if s < bs: bs = s; best = Vector2i(tx, ty)
	if best == null and fwd != null: return ai_spot(id, type, hq, true)
	return best

# ---------------- campaign goals, events, waves ----------------
func goal():
	return mission.goals[gi] if mission and gi < mission.goals.size() else null

func _hero_alive(team: int) -> Ent:
	for e in ents:
		if e.alive and e.team == team and e.kind == "u" and e.d.hero and not e.captive: return e
	return null

## Where enemy reinforcements head when nothing else is named: the Command Yard, else a hero, else any unit.
func _player_focus(from: Vector2) -> Vector2:
	var hq := find_hq(0)
	if hq != null and hq.kind == "b": return Vector2(hq.x, hq.y)
	var h := _hero_alive(0)
	if h != null: return Vector2(h.x, h.y)
	var best = null; var bd := 1e9
	for e in ents:
		if e.alive and e.team == 0 and not e.captive:
			var dd := Vector2(e.x, e.y).distance_to(from)
			if dd < bd: bd = dd; best = Vector2(e.x, e.y)
	return best if best != null else Vector2(p0.x * T, p0.y * T)

func _nearest(team: int, from: Vector2, f: Callable) -> Ent:
	var best: Ent = null; var bd := 1e9
	for e in ents:
		if e.alive and e.team == team and not e.captive and f.call(e):
			var dd := Vector2(e.x, e.y).distance_to(from)
			if dd < bd: bd = dd; best = e
	return best

## Sends a fresh group somewhere: a unit to hunt ("harv", "vip", "hero", "comms"), a tile, or the player's base.
func send_group(us: Array, go) -> void:
	if us.is_empty(): return
	var from := Vector2(us[0].x, us[0].y)
	var tgt: Ent = null
	if go is String:
		match go:
			"harv": tgt = _nearest(0, from, func(e): return (e.kind == "u" and e.d.harv) or e.type == "garden")   # the Choir mines with gardens
			"vip": tgt = _nearest(0, from, func(e): return e.tag == "vip")
			"hero": tgt = _nearest(0, from, func(e): return e.kind == "u" and e.d.hero)
			"comms": tgt = _nearest(0, from, func(e): return e.type == "comms")
			"none": return
	var dest: Vector2
	if go is Array: dest = Vector2(go[0] * T + 16, go[1] * T + 16)
	elif tgt != null: dest = Vector2(tgt.x, tgt.y)
	else: dest = _player_focus(from)
	group_move(us, dest.x, dest.y, "amove")
	if tgt != null and tgt.kind == "u":
		attack_order(us.filter(func(u): return u.d.dmg > 0 and can_hit(u.d, tgt)), tgt)

## Enemy group size at the chosen campaign difficulty (never drops a group to nothing).
func scaled(n: int) -> int:
	if n <= 0: return 0
	return maxi(1, int(round(n * D.LEVELS[lvl].waves)))

func spawn_group(sp: Dictionary) -> Array:
	var tm: int = sp.get("team", 1)
	var list: Array = sp.u if tm == 0 else sp.u.map(func(p): return [p[0], scaled(p[1])])
	var us := squad(tm, list, sp.at[0], sp.at[1])
	if tm == 1: send_group(us, sp.get("go", "base"))
	return us

## A line of mission talk: on the radio panel with the speaker's portrait when it names one ("who", see
## Data.SPEAKERS), else as a toast like before.
func say(line: Dictionary, warn: bool) -> void:
	if line.get("who", "") != "": host.radio(line.who, line.say, warn)
	else: host.toast(line.say, "warn" if warn else "gold")
	host.sfx("alert" if warn else "ready")

## Radio lines a mission ties to moments rather than times: mission.radio = [{"on", "who", "say"}], each said once.
## on: start · hero_hurt (own hero under 35% health) · bld_lost (first own building lost) · ehero_seen (enemy hero in sight)
func radio_cue(on: String) -> void:
	if mission == null or cine or radio_done.has(on): return
	radio_done[on] = true
	for r in mission.get("radio", []):
		if r.on == on: say(r, on == "hero_hurt" or on == "bld_lost")

func run_event(ev: Dictionary, warn := true) -> void:
	if ev.has("say"): say(ev, warn)
	var sent: Array = []
	for sp in ev.get("spawn", []):
		for u in spawn_group(sp):
			if u.team == 1: sent.append(u.id)
	if sent.size(): raids.append(sent)
	if ev.get("attack", "") == "hero":
		var hs := ents.filter(func(e): return e.alive and e.team == 1 and e.kind == "u" and e.d.hero)
		if hs.size():
			var c := Vector2(hs[0].x, hs[0].y)
			var esc := ents.filter(func(e): return e.alive and e.team == 1 and e.kind == "u" and not e.d.harv and not e.d.eng and not e.post and not e.d.hero and Vector2(e.x, e.y).distance_to(c) < 10 * T)
			send_group(hs + esc.slice(0, 8), "base")
	if ev.has("credits") and ev.get("team", 0) == 0: teams[0].credits += ev.credits

func goal_done(g: Dictionary) -> void:
	var dn = g.done
	if dn != null:
		if dn.has("base"):
			var bp: Vector2i = Vector2i(dn.base[0], dn.base[1])
			var hq := place_near(0, "hq", bp.x - 1, bp.y - 1)
			if hq != null:
				update_vision()
				prebuild(0, dn.get("pbase", []))
		if dn.has("credits"): teams[0].credits += dn.credits
		if dn.has("tech") and mission.tech != null:
			for t in dn.tech:
				if not mission.tech.has(t): mission.tech.append(t)
		for sp in dn.get("spawn", []): spawn_group(sp)
		if dn.has("say"): say(dn, false)
	gi += 1; g_t0 = time; gst = {}; wst = {}
	var nx = goal()
	if nx == null:
		over = true; host.end_game(true)
	elif dn == null or not dn.has("say"):
		host.toast("Objective complete. Next: " + _goal_name(nx), "gold"); host.sfx("ready")

func lose(why: String) -> void:
	if over: return
	end_why = why; over = true
	host.toast(why, "warn"); host.end_game(false)

func _goal_name(g: Dictionary) -> String:
	match g.k:
		"reach": return "reach the " + g.label
		"survive": return g.label
		"hold": return "hold the " + g.label
		"escort": return "get them to the " + g.label
		"rescue": return "free the " + g.label
		"capture": return "capture the " + g.label
		"mine": return "deliver aurite"
	return g.get("verb", "Destroy the").to_lower() + " " + g.label

## The goal's targets: entities with its tag (if any) and of its types (buildings when it names none). team -1: any side.
func goal_targets(g: Dictionary, team := 1) -> Array:
	return ents.filter(func(e): return e.alive and (team < 0 or e.team == team) and not e.captive and (g.tag == "" or e.tag == g.tag) and (g.types.has(e.type) if g.types.size() else e.kind == "b"))

## Who stands in a zone: 0 the player, 1 the enemy, -1 nobody, 2 contested.
func zone_owner(z: Array, r: float) -> int:
	var p := false; var en := false
	var c := Vector2(z[0] * T + 16, z[1] * T + 16)
	for e in ents:
		if not e.alive or e.kind != "u" or e.captive or e.d.harv: continue
		if Vector2(e.x, e.y).distance_to(c) <= r * T:
			if e.team == 0: p = true
			else: en = true
	if p and en: return 2
	return 0 if p else (1 if en else -1)

func _in_zone(e: Ent, at: Array, r: float) -> bool:
	return Vector2(e.x, e.y).distance_to(Vector2(at[0] * T + 16, at[1] * T + 16)) <= r * T

func mission_tick() -> void:
	var M = mission
	if not M or over: return
	radio_cue("start")
	if not radio_done.has("ehero_seen"):
		for e in ents:
			if e.alive and e.team == 1 and e.kind == "u" and e.d.hero and visible_to_player(e): radio_cue("ehero_seen"); break
	for i in M.events.size():
		var ev: Dictionary = M.events[i]
		if not ev_done.has(i) and time >= ev.t:
			ev_done[i] = true; run_event(ev)
	var g = goal()
	if g == null: return
	if g.waves != null: do_waves(g.waves, time - g_t0)
	elif M.waves != null: do_waves(M.waves, time)
	# prisoners walk free when a friendly unit reaches them
	for c in ents:
		if not c.alive or not c.captive: continue
		for e in ents:
			if e.alive and e.team == 0 and e.kind == "u" and not e.captive and Vector2(e.x - c.x, e.y - c.y).length() < T * 2.6:
				c.captive = false; c.tag = "vip"; c.guard = null
				if not gst.get("freed_msg", false):
					gst.freed_msg = true; host.toast("Prisoners freed", "gold"); host.sfx("ready")
				break
	for t in M.keep:
		if count(0, t) == 0:
			lose(("%s has fallen" % D.def_of(t).name) if D.UN.has(t) else ("Your %s was destroyed" % D.def_of(t).name)); return
	for t in g.protect:
		if count(0, t) == 0:
			lose("Your %s was lost" % D.def_of(t).name); return
	match g.k:
		"destroy_all":
			if ents.filter(func(e): return e.alive and e.team == 1 and (e.d.kit == 0 if e.kind == "b" else not (e.d.harv or e.d.free))).is_empty(): goal_done(g)
		"kill":
			if goal_targets(g).is_empty(): goal_done(g)
		"mine":
			if not gst.has("m0"): gst.m0 = stats.mined
			if stats.mined - gst.m0 >= g.n: goal_done(g)
			elif g.t > 0 and time - g_t0 > g.t: lose("Time is up")
		"survive":
			if time - g_t0 >= g.t: goal_done(g)
		"reach":
			for e in ents:
				if e.alive and e.team == 0 and e.kind == "u" and not e.captive and (g.who != "hero" or e.d.hero) and _in_zone(e, g.at, g.r):
					goal_done(g); return
		"hold":
			var all_ok := true
			for z in g.zones:
				if zone_owner(z, g.r) != 0: all_ok = false
			if all_ok: gst.held = gst.get("held", 0.0) + 1.0
			if gst.get("held", 0.0) >= g.t: goal_done(g)
		"escort":
			for e in ents:
				if e.alive and e.team == 0 and e.tag == "vip" and not e.captive and _in_zone(e, g.at, g.r):
					e.alive = false; e.sel = false; _drop_sel(e)
					gst.arrived = gst.get("arrived", 0) + 1
					host.toast("%s is through (%d of %d)" % [e.d.name, gst.arrived, g.need], "gold"); host.sfx("ready")
			var left := ents.filter(func(e): return e.alive and e.team == 0 and e.tag == "vip").size()
			if gst.get("arrived", 0) >= g.need: goal_done(g)
			elif gst.get("arrived", 0) + left < g.need: lose("Too many of them were lost")
		"rescue":
			if ents.filter(func(e): return e.alive and e.captive).is_empty(): goal_done(g)
		"capture":
			var tg := goal_targets(g, -1)
			if tg.any(func(e): return e.team == 0): goal_done(g)
			elif tg.is_empty(): lose("The %s was destroyed" % g.label)

## Wave plan {first, every, n, from, to, list: [[type, base, per wave, from wave]]}; t is seconds since the plan started.
func do_waves(W: Dictionary, t: float) -> void:
	var wn: int = wst.get("wn", 0)
	if wn >= W.get("n", 99) or t < W.first + wn * W.every: return
	wn += 1; wst.wn = wn
	var fr: Array = W.from[randi() % W.from.size()]
	var list: Array = []
	for row in W.list:
		if wn < row[3]: continue
		var n := scaled(int(row[1] + row[2] * (wn - row[3])))
		# wave plans name their units outright: only the faction matters, not the AI's build list (often empty)
		var wf: String = D.def_of(row[0]).fac
		if n > 0 and (wf == "" or wf == teams[1].fac): list.append([row[0], n])
	if list.is_empty(): return
	var us := squad(1, list, fr[0], fr[1])
	send_group(us, W.get("to", "base"))
	host.toast("Enemy wave %d of %d incoming" % [wn, W.get("n", 99)] if W.has("n") else "Enemy wave %d incoming" % wn, "warn"); host.sfx("alert")

func check_end() -> void:
	if over: return
	var alive := [0, 0]
	for e in ents:
		if e.alive and not e.captive and (e.d.kit == 0 if e.kind == "b" else not (e.d.harv or e.d.free)): alive[e.team] += 1
	if mission:
		if alive[0] == 0: lose("All your forces are gone")
		return
	if alive[0] == 0 or alive[1] == 0:
		over = true; host.end_game(alive[0] > 0)

func _sw_line() -> String:
	for e in ents:
		if e.alive and e.team == 1 and e.kind == "b" and e.d.sw:
			return "\n%s: %s" % [e.d.name, "ARMED" if e.rdy else D.fmt(e.d.charge - e.ch)]
	return ""

## Mission HUD text: the current goal with its progress, plus what must not be lost.
func obj_text() -> String:
	var M = mission
	if not M: return ""
	var g = goal()
	if g == null: return "Mission complete"
	var s := ""
	var step := "" if M.goals.size() < 2 else "(%d/%d) " % [gi + 1, M.goals.size()]
	match g.k:
		"destroy_all":
			var n := ents.filter(func(e): return e.alive and e.team == 1 and (e.d.kit == 0 if e.kind == "b" else not (e.d.harv or e.d.free))).size()
			s = "Destroy the %s. Enemy forces left: %d" % [g.label if g.label != "" else "enemy", n]
		"kill": s = "%s %s · %d left" % [g.get("verb", "Destroy the"), g.label, goal_targets(g).size()]
		"mine":
			var m: int = stats.mined - int(gst.get("m0", stats.mined))
			s = "Aurite delivered: %s / %s" % [_thousands(m), _thousands(g.n)] + (" · %s left" % D.fmt(g.t - (time - g_t0)) if g.t > 0 else "")
		"survive": s = "%s: %s to go" % [g.label, D.fmt(g.t - (time - g_t0))]
		"reach": s = "Bring %s to the %s (gold marker)" % ["your hero" if g.who == "hero" else "a unit", g.label]
		"hold":
			var own := 0
			for z in g.zones:
				if zone_owner(z, g.r) == 0: own += 1
			s = "Hold all %d %s at once: %d held · %s to go" % [g.zones.size(), g.label, own, D.fmt(g.t - gst.get("held", 0.0))]
		"escort":
			var left := ents.filter(func(e): return e.alive and e.team == 0 and e.tag == "vip").size()
			s = "Get %d to the %s (gold marker): %d through, %d on the way" % [g.need, g.label, gst.get("arrived", 0), left]
		"rescue":
			s = "Free the %s: %d still held (marked on the map)" % [g.label, ents.filter(func(e): return e.alive and e.captive).size()]
		"capture": s = "Capture the %s with %s. Do not destroy it" % [g.label, "a Scrapper" if fac_of(0) == "ashen" else "an Engineer"]
	s = step + s + _sw_line()
	var keep: Array = []
	for t in M.keep:
		if D.UN.has(t): keep.append(D.UN[t].name)
	if keep.size(): s += "\nKeep alive: " + ", ".join(keep)
	return s

## Gold rings the 3D view and the minimap draw: [x, y, radius (tiles), owner (-1 none, 0 you, 1 enemy, 2 contested)].
func marks() -> Array:
	var g = goal()
	if g == null or over: return []
	var out: Array = []
	match g.k:
		"reach", "escort": out.append([g.at[0], g.at[1], g.r, -1])
		"hold":
			for z in g.zones: out.append([z[0], z[1], g.r, zone_owner(z, g.r)])
		"survive":
			if g.zone != null: out.append([g.zone[0], g.zone[1], 3.0, -1])
	return out

static func _thousands(n: int) -> String:
	var s := str(n); var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out; s = s.substr(0, s.length() - 3)
	return s + out

# ---------------- loop ----------------
func step(dt: float) -> void:
	time += dt
	upd_furnaces(dt)   # Furnaces take their fuel before anything else is paid for
	for tm in teams: upd_prod(tm, dt)
	for e in ents:
		if not e.alive: continue
		if e.kind == "u": upd_unit(e, dt)
		else: upd_bld(e, dt)
	separate(); upd_proj(dt); upd_parts(dt); upd_fields(dt); upd_auras(dt); upd_field_life(dt); upd_wrecks(dt)
	if delayed.size():
		var keep: Array = []
		for dl in delayed:
			if dl[0] <= time: explode(dl[1], dl[2], dl[3])
			else: keep.append(dl)
		delayed = keep
	vis_t -= dt
	if vis_t <= 0: vis_t = 0.2; update_vision(); upd_sense(); calc_hum()
	if risers.size(): upd_risers()
	ai_t -= dt
	if ai_t <= 0 and not cine:
		ai_t = 1.0; ai_think(teams[1]); mission_tick(); check_end()
	upd_strikes(dt); combat = max(0.0, combat - dt * 0.05)
	var any_dead := false
	for e in ents:
		if not e.alive: any_dead = true; break
	if any_dead:
		for e in ents:
			if not e.alive: by_id.erase(e.id)
		ents = ents.filter(func(e): return e.alive)

## True once every unit of one scripted enemy event is dead (a raid wiped out).
func raid_wiped() -> bool:
	for ids in raids:
		if ids.all(func(i): return not by_id.has(i) or not by_id[i].alive): return true
	return false
