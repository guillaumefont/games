extends RefCounted
## Preload it (`const Squads := preload("res://scripts/squads.gd")`); no class_name, so the self-update pack can carry it.
## Squads: numbered groups of the player's units that form by themselves (Guillaume, 2026-11-27).
##
## Rules (see the squad strip proposal in the project files, aurite-overhaul/squads/):
## - A hand-made selection of two or more units that gets an order becomes a squad, with the lowest free number.
## - A unit is in one squad at most. Ordering part of a squad splits it off; ordering whole squads together merges them
##   into the lowest-numbered one. A squad left with fewer than two units by such a reshuffle breaks up.
## - Deaths only shrink a squad: a lone survivor keeps its number until it dies too.
## - Units in no squad (fresh from the base, or the starting army) are "new"; JOIN adds them to a squad.
## - Selecting through a chip never reshuffles anything on its own: main.gd skips `formed` for a selection made by ALL.

const MAX := 5

var list: Array = []   # [{n: int, ids: Array[int]}], sorted by n

func reset() -> void:
	list = []

## A unit that can be in a squad: the player's own, not a harvester, a dropship or a prisoner.
static func eligible(e) -> bool:
	return e.alive and e.kind == "u" and e.team == 0 and not e.captive and not e.d.harv and not e.d.get("ship", false)

func find(n: int):
	for q in list:
		if q.n == n: return q
	return null

func of(e) -> int:
	for q in list:
		if q.ids.has(e.id): return q.n
	return 0

## Living members of squad n (units in a tunnel included: they still belong to it).
func members(S, n: int) -> Array:
	var q = find(n)
	if q == null: return []
	return S.ents.filter(func(e): return e.alive and e.kind == "u" and q.ids.has(e.id))

## Drops dead units; a squad with nobody left goes away (the others keep their numbers).
func prune(S) -> void:
	var alive := {}
	for e in S.ents:
		if e.alive and e.kind == "u" and e.team == 0: alive[e.id] = true
	for q in list:
		q.ids = q.ids.filter(func(i): return alive.has(i))
	list = list.filter(func(q): return q.ids.size() > 0)

## Units in no squad: what the NEW chip selects. Engineers stay out, like they stayed out of ALL.
func fresh(S) -> Array:
	var inq := {}
	for q in list:
		for i in q.ids: inq[i] = true
	return S.ents.filter(func(e): return eligible(e) and not e.d.eng and not inq.has(e.id))

## The squad whose living members are exactly these units, or 0.
func matching(S, units: Array) -> int:
	var ids := units.filter(func(e): return eligible(e)).map(func(e): return e.id)
	if ids.is_empty(): return 0
	ids.sort()
	for q in list:
		var m: Array = members(S, q.n).map(func(e): return e.id)
		m.sort()
		if m == ids: return q.n
	return 0

func _free_n() -> int:
	for n in range(1, MAX + 1):
		if find(n) == null: return n
	return 0

func _sort() -> void:
	list.sort_custom(func(a, b): return a.n < b.n)

## A selection got an order. Returns the squad number it now is, 0 when it forms none (fewer than two units), or -1
## when all five numbers are taken (nothing changes then).
func formed(S, units: Array) -> int:
	prune(S)
	var us := units.filter(func(e): return eligible(e))
	if us.size() < 2: return 0
	var have := matching(S, us)
	if have: return have
	var ids := {}
	for e in us: ids[e.id] = true
	# whole squads inside the selection: the lowest number takes everyone
	var keep := 0
	for q in list:
		var m: Array = members(S, q.n)
		if m.size() and m.all(func(e): return ids.has(e.id)):
			keep = q.n; break
	if keep == 0:
		# a new number: first see which squads the move would leave too small, they free their number
		var after := list.filter(func(q):
			var left: Array = q.ids.filter(func(i): return not ids.has(i))
			return left.size() >= 2 or (left.size() == 1 and q.ids.size() == 1))
		if after.size() >= MAX: return -1
	var cut := {}
	for q in list:
		if q.n == keep: continue
		var left: Array = q.ids.filter(func(i): return not ids.has(i))
		if left.size() < q.ids.size(): cut[q.n] = true
		q.ids = left
	list = list.filter(func(q): return q.n == keep or q.ids.size() >= 2 or (q.ids.size() == 1 and not cut.has(q.n)))
	if keep == 0:
		keep = _free_n()
		list.append({"n": keep, "ids": []})
	find(keep).ids = ids.keys()
	_sort()
	return keep

## Adds units to squad n (taking them out of any other squad). Returns how many joined.
func join(S, n: int, units: Array) -> int:
	var q = find(n)
	if q == null: return 0
	var add := units.filter(func(e): return eligible(e) and not q.ids.has(e.id))
	if add.is_empty(): return 0
	var ids := {}
	for e in add: ids[e.id] = true
	for o in list:
		if o.n != n: o.ids = o.ids.filter(func(i): return not ids.has(i))
	q.ids.append_array(ids.keys())
	list = list.filter(func(o): return o.n == n or o.ids.size() > 0)
	return add.size()

## A fused unit (four Thralls into a Knot) takes the place of the units it came from.
func replace(old_ids: Array, e) -> void:
	for q in list:
		if old_ids.any(func(i): return q.ids.has(i)):
			q.ids = q.ids.filter(func(i): return not old_ids.has(i))
			q.ids.append(e.id)
			return

## Status for a chip: count, health 0..1, under fire, idle, and the name of its most common unit type.
func status(S, n: int) -> Dictionary:
	var m := members(S, n)
	var hp := 0.0; var mx := 0.0; var hit := false; var idle := true; var by := {}
	for e in m:
		hp += e.hp; mx += e.max_hp
		if e.hit_t > 0: hit = true
		if e.order != "none" or e.target != null or e.moving: idle = false
		by[e.type] = by.get(e.type, 0) + 1
	var top := ""; var best := 0
	for t in by:
		if by[t] > best: best = by[t]; top = t
	var name := ""
	if top != "":
		var full := String(m.filter(func(e): return e.type == top)[0].d.name)
		name = full.get_slice(" ", full.get_slice_count(" ") - 1)   # Rivet Brute: BRUTE, Kestrel Vey: VEY
		if by.size() > 1: name += " +"
	return {"n": m.size(), "hp": (hp / mx) if mx > 0 else 0.0, "hit": hit, "idle": idle and m.size() > 0, "name": name}
