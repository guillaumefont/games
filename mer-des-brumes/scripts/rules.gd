class_name Rules
extends RefCounted
## The game's rules and numbers, ported from the web prototype (web/index.html). Pure: no nodes,
## so tests can check them directly. Angles: heading h = 0 faces +z, the forward vector is
## (sin h, cos h), and a mesh shows heading h with rotation.y = h.

const SAVE_PATH := "user://save.json"
const WORLD_R := 250.0
const BASE_R := 15.0
const BASE_ZONE := 36.0
const DOCK := Vector3(0, 0, 27)
const ISLAND_SEED := 20261117
const BALL_COST := 60      # 20 cannonballs
const BALL_PACK := 20

const CREW := [
	{"k": "sabre", "name": "Hommes au sabre", "desc": "Corps à corps à l'abordage", "cost": 40, "power": 1.0, "color": Color8(0xc9, 0xb5, 0x9a)},
	{"k": "pistolet", "name": "Hommes au pistolet", "desc": "Tir à courte portée", "cost": 90, "power": 1.9, "color": Color8(0x8a, 0x6a, 0x52)},
	{"k": "fusil", "name": "Hommes au fusil", "desc": "Tir plus précis, plus fort", "cost": 160, "power": 2.8, "color": Color8(0x56, 0x63, 0x6f)},
	{"k": "grenade", "name": "Grenadiers", "desc": "Gros dégâts sur le pont ennemi", "cost": 300, "power": 4.5, "color": Color8(0x6e, 0x46, 0x46)},
]

## Each hull has its own upgrade limits (caps): past them you buy a new hull.
const HULL_ORDER := ["chaloupe", "sloop", "fregate", "galion"]
const HULLS := {
	"chaloupe": {"name": "Chaloupe", "desc": "Le bateau de départ : petit, à rames, un canon de chaque côté.", "price": 0, "hp": 100, "speed": 6.0, "turn": 1.9, "side": 1, "bow": 0, "stern": 0, "crew": 6, "scale": Vector3(1, 1, 1), "masts": 1,
		"caps": {"rameurs": 3, "voiles": 1, "canons": 1, "coque": 2, "capitaine": 1, "grappin": 0}},
	"sloop": {"name": "Sloop", "desc": "Fin et rapide, il tourne vite. Peu de canons sur les côtés, mais un canon à l'avant.", "price": 3500, "hp": 150, "speed": 10.0, "turn": 2.4, "side": 2, "bow": 1, "stern": 0, "crew": 8, "scale": Vector3(0.82, 1, 1.25), "masts": 1,
		"caps": {"rameurs": 2, "voiles": 3, "canons": 1, "coque": 2, "capitaine": 2, "grappin": 1}},
	"fregate": {"name": "Frégate", "desc": "Plus lente et lourde à tourner, mais bien armée, avec un canon avant et un canon arrière.", "price": 5000, "hp": 240, "speed": 7.5, "turn": 1.3, "side": 3, "bow": 1, "stern": 1, "crew": 12, "scale": Vector3(1.25, 1.15, 1.35), "masts": 2,
		"caps": {"rameurs": 2, "voiles": 2, "canons": 3, "coque": 4, "capitaine": 3, "grappin": 2}},
	"galion": {"name": "Galion", "desc": "Une forteresse flottante : très lent, très armé, canons avant et arrière.", "price": 14000, "hp": 380, "speed": 6.5, "turn": 0.95, "side": 5, "bow": 2, "stern": 2, "crew": 18, "scale": Vector3(1.5, 1.3, 1.6), "masts": 3,
		"caps": {"rameurs": 0, "voiles": 3, "canons": 3, "coque": 5, "capitaine": 4, "grappin": 3}},
}

const UPS := [
	{"k": "rameurs", "name": "Rameurs", "desc": "+0,8 nœud", "base": 150, "step": 200},
	{"k": "voiles", "name": "Voiles", "desc": "+1,6 nœud", "base": 500, "step": 450, "req": "Il faut d'abord tous les rameurs"},
	{"k": "canons", "name": "Canons", "desc": "Un canon de plus de chaque côté", "base": 300, "step": 300},
	{"k": "coque", "name": "Coque renforcée", "desc": "+40 points de coque", "base": 200, "step": 250},
	{"k": "capitaine", "name": "Meilleur capitaine", "desc": "+3 places d'équipage, +10 % de dégâts, tourne plus vite", "base": 600, "step": 600},
	{"k": "grappin", "name": "Grappins", "desc": "Le grappin va 4 m plus loin", "base": 800, "step": 700},
]

const BASE_UPS := [
	{"k": "defense", "name": "Tours de défense", "desc": "Des canons qui tirent sur les ennemis près du port", "max": 3, "base": 600, "step": 700},
	{"k": "coffre", "name": "Coffre plus grand", "desc": "+3 000 pièces de place", "max": 6, "base": 400, "step": 500},
]

const NAMES := ["La Mouette Noire", "Le Requin Gris", "La Veuve Salée", "Le Corbeau", "La Brume Rouge", "L'Écume",
	"Le Vieux Loup", "La Dent de Fer", "Le Goéland", "La Sirène Grise"]


static func fresh() -> Dictionary:
	return {
		"coins": 2000, "vault": 0, "maps": 10, "balls": 40, "ship": "chaloupe",
		"up": {"rameurs": 0, "voiles": 0, "canons": 0, "coque": 0, "capitaine": 0, "grappin": 0},
		"crew": {"sabre": 4, "pistolet": 0, "fusil": 0, "grenade": 0},
		"base": {"defense": 0, "coffre": 1},
	}


## A saved game (any older shape) made safe: missing fields filled, unknown hull reset,
## upgrades clamped to the hull's caps, and the dropped diamonds paid back as coins.
static func migrate(raw) -> Dictionary:
	var s := fresh()
	if not (raw is Dictionary):
		return s
	for k in ["coins", "vault", "maps", "balls"]:
		if raw.has(k):
			s[k] = maxi(0, int(raw[k]))
	if raw.has("ship") and HULLS.has(str(raw.ship)):
		s.ship = str(raw.ship)
	for group in ["up", "crew", "base"]:
		if raw.get(group) is Dictionary:
			for k in s[group]:
				if raw[group].has(k):
					s[group][k] = maxi(0, int(raw[group][k]))
	var caps: Dictionary = HULLS[s.ship].caps
	for k in s.up:
		s.up[k] = mini(s.up[k], caps.get(k, 0))
	for u in BASE_UPS:
		s.base[u.k] = clampi(s.base[u.k], 0 if u.k == "defense" else 1, u.max)
	if raw.has("diamonds"):
		s.vault += int(raw.diamonds) * 100
	return s


static func load_game(path := SAVE_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fresh()
	return migrate(JSON.parse_string(FileAccess.get_file_as_string(path)))


static func save_game(s: Dictionary, path := SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))


static func up_cost(k: String, level: int) -> int:
	for u in UPS:
		if u.k == k:
			return u.base + u.step * level
	for u in BASE_UPS:
		if u.k == k:
			return u.base + u.step * level
	return 0


static func crew_count(s: Dictionary) -> int:
	var n := 0
	for c in CREW:
		n += int(s.crew[c.k])
	return n


static func crew_power(s: Dictionary) -> float:
	var p := 0.0
	for c in CREW:
		p += int(s.crew[c.k]) * float(c.power)
	return p


static func vault_cap(s: Dictionary) -> int:
	return int(s.base.coffre) * 3000


static func ship_stats(hk: String, up: Dictionary, crew_pow: float) -> Dictionary:
	var H: Dictionary = HULLS[hk]
	var capt := 1.0 + 0.1 * int(up.get("capitaine", 0))
	return {
		"hull": hk,
		"speed": float(H.speed) + int(up.get("rameurs", 0)) * 0.8 + int(up.get("voiles", 0)) * 1.6,
		"turn": float(H.turn) * (1.0 + 0.06 * int(up.get("capitaine", 0))),
		"max_hp": int(H.hp) + int(up.get("coque", 0)) * 40,
		"side": int(H.side) + int(up.get("canons", 0)), "bow": int(H.bow), "stern": int(H.stern),
		"dmg": 7.0 * capt, "range": 24.0, "reload": 3.0,
		"crew_cap": int(H.crew) + int(up.get("capitaine", 0)) * 3,
		"board": 6.0 + int(up.get("grappin", 0)) * 3.0,
		"grapple": 10.0 + int(up.get("grappin", 0)) * 4.0,
		"crew_dps": crew_pow * 0.55 * capt,
	}


## The player's guns reach further than the AI's (aimed shots, any bearing).
const PLAYER_RANGE := 50.0

static func player_stats(s: Dictionary) -> Dictionary:
	var st := ship_stats(s.ship, s.up, crew_power(s))
	st.range = PLAYER_RANGE
	return st


## Broadsides to port (bab) and starboard (tri), plus bow (av) and stern (ar) chasers.
## c is the battery's bearing from the bow, half its half-angle.
static func batteries(st: Dictionary) -> Array:
	var b := [{"k": "bab", "c": PI / 2, "half": 0.75, "n": st.side}, {"k": "tri", "c": -PI / 2, "half": 0.75, "n": st.side}]
	if st.bow > 0:
		b.append({"k": "av", "c": 0.0, "half": 0.35, "n": st.bow})
	if st.stern > 0:
		b.append({"k": "ar", "c": PI, "half": 0.35, "n": st.stern})
	return b


static func wrap_a(a: float) -> float:
	return wrapf(a, -PI, PI)


static func in_arcs(bats: Array, rel: float) -> Array:
	var out := []
	for b in bats:
		if absf(wrap_a(rel - b.c)) <= b.half:
			out.append(b)
	return out


static func guns_in_arcs(bats: Array, rel: float) -> int:
	var n := 0
	for b in in_arcs(bats, rel):
		n += int(b.n)
	return n


## Bearing of (tx, tz) seen from (x, z) heading h, relative to the bow, in -PI..PI.
static func rel_bearing(x: float, z: float, h: float, tx: float, tz: float) -> float:
	return wrap_a(atan2(tx - x, tz - z) - h)


## Pays from the coins on board first, then the port's coffre.
static func spend(s: Dictionary, n: int) -> bool:
	if s.coins + s.vault < n:
		return false
	var a := mini(s.coins, n)
	s.coins -= a
	s.vault -= n - a
	return true


static func can_upgrade(s: Dictionary, k: String) -> bool:
	var caps: Dictionary = HULLS[s.ship].caps
	if s.up[k] >= caps.get(k, 0):
		return false
	if k == "voiles" and s.up.rameurs < caps.rameurs:
		return false
	return s.coins + s.vault >= up_cost(k, s.up[k])


static func buy_upgrade(s: Dictionary, k: String) -> bool:
	if not can_upgrade(s, k):
		return false
	spend(s, up_cost(k, s.up[k]))
	s.up[k] += 1
	return true


## A new hull starts with no upgrades; crew beyond its places is put ashore.
static func buy_hull(s: Dictionary, hk: String) -> bool:
	if hk == s.ship or not HULLS.has(hk) or not spend(s, HULLS[hk].price):
		return false
	s.ship = hk
	for k in s.up:
		s.up[k] = 0
	var over := crew_count(s) - int(player_stats(s).crew_cap)
	for c in CREW:
		var n := mini(over, int(s.crew[c.k]))
		if n > 0:
			s.crew[c.k] -= n
			over -= n
	return true


static func hire(s: Dictionary, k: String) -> bool:
	for c in CREW:
		if c.k == k and crew_count(s) < int(player_stats(s).crew_cap) and spend(s, c.cost):
			s.crew[k] += 1
			return true
	return false


static func buy_base(s: Dictionary, k: String) -> bool:
	for u in BASE_UPS:
		if u.k == k and s.base[k] < u.max and spend(s, up_cost(k, s.base[k])):
			s.base[k] += 1
			return true
	return false


static func deposit(s: Dictionary) -> int:
	var n := mini(s.coins, vault_cap(s) - int(s.vault))
	n = maxi(n, 0)
	s.coins -= n
	s.vault += n
	return n


static func withdraw(s: Dictionary, n := 500) -> int:
	n = mini(n, s.vault)
	s.vault -= n
	s.coins += n
	return n


## Hulls shown in the shipyard: the starting boat only while you still sail it.
static func yard_list(s: Dictionary) -> Array:
	var out := []
	for k in HULL_ORDER:
		if k != "chaloupe" or k == s.ship:
			out.append(k)
	return out


## Losing a fight costs half the coins on board; the coffre is safe.
static func defeat_loss(s: Dictionary) -> int:
	var lost := int(s.coins) / 2
	s.coins -= lost
	return lost


## An enemy of level 1..5: its hull and how far it is upgraded.
static func enemy_build(lvl: int) -> Dictionary:
	var hk: String = ["chaloupe", "chaloupe", "sloop", "fregate", "galion"][lvl - 1]
	var f: float = [0.0, 0.7, 0.4, 0.5, 0.3][lvl - 1]
	var up := {}
	var caps: Dictionary = HULLS[hk].caps
	for k in caps:
		up[k] = roundi(caps[k] * f)
	var st := ship_stats(hk, up, lvl * 2.2)
	st.dmg *= 0.85
	st.speed *= 0.92
	return {"hull": hk, "up": up, "st": st}


# ---------------------------------------------------------------- boarding

const CREW_HP := 10.0
const CAPT_HP := 24.0

## The men who fight at a boarding: the crew (counts by kind) then the captain, who falls last.
static func fighters(crew: Dictionary, capt: int) -> Array:
	var out := []
	for c in CREW:
		for i in int(crew.get(c.k, 0)):
			out.append({"k": c.k, "power": float(c.power), "hp": CREW_HP, "max": CREW_HP})
	var ch := CAPT_HP + capt * 6.0
	out.append({"k": "capitaine", "power": 2.0 + capt * 0.8, "hp": ch, "max": ch})
	return out


static func alive_count(f: Array) -> int:
	var n := 0
	for m in f:
		if m.hp > 0:
			n += 1
	return n


static func fight_power(f: Array) -> float:
	var p := 0.0
	for m in f:
		if m.hp > 0:
			p += m.power
	return p


## One moment of the melee: each side strikes with all its living men at once; the blows
## fall on the other side's crew first and on its captain last.
static func melee(a: Array, b: Array, dt: float) -> void:
	var da := fight_power(a) * dt
	var db := fight_power(b) * dt
	_strike(b, da)
	_strike(a, db)


static func _strike(f: Array, dmg: float) -> void:
	for m in f:
		if dmg <= 0:
			return
		if m.hp <= 0:
			continue
		var d := minf(dmg, m.hp)
		m.hp -= d
		dmg -= d


## The crew left after a boarding (the dead are gone for good).
static func survivors(f: Array) -> Dictionary:
	var out := {}
	for c in CREW:
		out[c.k] = 0
	for m in f:
		if m.hp > 0 and out.has(m.k):
			out[m.k] += 1
	return out


## Taking a ship: you sail it with its upgrades; crew beyond its places is put ashore.
static func take_hull(s: Dictionary, hk: String, up: Dictionary) -> void:
	s.ship = hk
	for k in s.up:
		s.up[k] = mini(int(up.get(k, 0)), int(HULLS[hk].caps.get(k, 0)))
	var over := crew_count(s) - int(player_stats(s).crew_cap)
	for c in CREW:
		var n := mini(over, int(s.crew[c.k]))
		if n > 0:
			s.crew[c.k] -= n
			over -= n


## A sunk ship sometimes carries a treasure map, more often a big one.
static func map_chance(lvl: int) -> float:
	return 0.2 + 0.1 * lvl


## The archipelago, always the same: the port island at the centre and 18 more.
static func islands() -> Array:
	var sd := ISLAND_SEED
	var out := [{"x": 0.0, "z": 0.0, "r": BASE_R}]
	var tries := 0
	while out.size() < 19 and tries < 500:
		tries += 1
		sd = (sd * 16807) % 2147483647
		var a := (sd - 1) / 2147483646.0 * TAU
		sd = (sd * 16807) % 2147483647
		var d := 55.0 + (sd - 1) / 2147483646.0 * (WORLD_R - 70.0)
		sd = (sd * 16807) % 2147483647
		var r := 5.0 + (sd - 1) / 2147483646.0 * 9.0
		var x := cos(a) * d
		var z := sin(a) * d
		var ok := true
		for i in out:
			if Vector2(i.x - x, i.z - z).length() <= i.r + r + 26.0:
				ok = false
				break
		if ok:
			out.append({"x": x, "z": z, "r": r})
	return out


static func wave(x: float, z: float, t: float) -> float:
	return sin(x * 0.13 + t * 0.9) * 0.3 + cos(z * 0.11 + t * 0.7) * 0.3 + sin((x + z) * 0.07 + t * 1.3) * 0.16


## The pilot: looks 1.6 s ahead at headings around its own and speed choices, and picks the one
## that keeps its guns on the foe and itself out of the foe's arcs, away from islands.
## Returns [heading, speed].
static func ai_choose(me: Dictionary, st: Dictionary, foe: Dictionary, fst: Dictionary, agg: float, isles: Array) -> Array:
	var T := 1.6
	var fx: float = foe.x + sin(foe.h) * foe.v * T
	var fz: float = foe.z + cos(foe.h) * foe.v * T
	var my_b := batteries(st)
	var foe_b := batteries(fst)
	var best := -1e9
	var res := [me.h, 0.0]
	for spd in [0.5, 1.0]:
		for i in range(-4, 5):
			var h: float = me.h + i * 0.35
			var sp: float = st.speed * agg * spd
			var nx: float = me.x + sin(h) * sp * T
			var nz: float = me.z + cos(h) * sp * T
			var d := Vector2(fx - nx, fz - nz).length()
			var s := -absf(d - 13.0) * 0.25 - absi(i) * 0.05
			if d < st.range:
				s += guns_in_arcs(my_b, rel_bearing(nx, nz, h, fx, fz)) * 2.0
			if d < fst.range:
				s -= guns_in_arcs(foe_b, rel_bearing(fx, fz, foe.h, nx, nz)) * 2.2
			if d < 5.0:
				s -= 6.0
			for isl in isles:
				if Vector2(isl.x - nx, isl.z - nz).length() < isl.r + 4.0:
					s -= 20.0
			if s > best:
				best = s
				res = [h, sp]
	return res


static func fmt(n) -> String:
	var s := str(int(floor(n)))
	var neg := s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if neg else "") + s + out
