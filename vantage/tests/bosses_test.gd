extends SceneTree
## The final bosses (Guillaume, 2026-11-24: "I want a different boss per level. You can advance over
## it, on the sides...", then "Bosses are too easy"): one ship for each level, fought from lanes
## over it, along its flanks, beneath it and between its hulls, glides between lanes that keep clear
## of the hull, guns standing on the hull where the lane meets it, fire that can't be shot down, and
## a whole fight from beneath to the break-up.
##   godot --headless --path . --script tests/bosses_test.gd

const SAVE := "user://test_bosses.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func roster() -> void:
	print("one boss a level")
	var ids := {}
	for lv in Campaign.count():
		ids[Campaign.fortress_of(lv)] = true
	check(ids.size() == Campaign.count() and Rules.FORTRESSES.size() == Campaign.count(),
		"%d levels, %d different final bosses" % [Campaign.count(), ids.size()])
	var shapes := {}
	var routes := {}
	for id: String in Rules.FORTRESSES:
		var f: Dictionary = Rules.FORTRESSES[id]
		var here := {}
		for i in f.sections.size() - 1:
			var r := Capital.route_of(id, i)
			# a lane is its route and where across it runs (over one wing, then the other)
			here["%s@%.0f" % [r, float(Capital.lane(id, i).x)]] = true
			routes[r] = true
		var shape := ""
		if Capital.lofted(id):
			for bd: Dictionary in Capital.bodies(id):
				shape += "%s%.0f/%.0f " % [bd.get("role", "hull"), bd.get("x", 0.0), bd.w]
		else:
			shape = "%s/%s/%s" % [f.hull, f.paint, f.get("extras", [])]
		shapes[shape] = true
		# Goliath, the hand-made sector's, is the straight run over the top; every other has a way round
		var varied := here.size() >= 3 or (id == "goliath" and here.size() >= 2)
		check(varied and f.sections[-1].kind == "core" and f.sections[-2].kind in Capital.HEARTS,
			"%s: %s, then its reactor" % [f.title, " > ".join(here.keys())])
	check(shapes.size() == Rules.FORTRESSES.size(), "no two hulls alike (%d shapes)" % shapes.size())
	for r: String in ["stern", "top", "left", "right", "under", "gap"]:
		check(routes.has(r), "somewhere the ship flies the %s lane" % r)


func lanes() -> void:
	print("lanes and glides")
	for id: String in Rules.FORTRESSES:
		var f: Dictionary = Rules.FORTRESSES[id]
		var clear := true
		var glides := true
		var mounted := true
		var prev := Vector3(0, -0.5, -40.0)
		for i in f.sections.size():
			var l := Capital.lane(id, i)
			var r: Vector4 = l.reach
			# anywhere the drag can take the ship, it stays clear of the hull beside it
			for cx: float in [r.x, 0.0, r.y]:
				for cy: float in [r.z, 0.0, r.w]:
					for dd: float in [-3.0, 0.0, 3.0]:
						if Capital.inside(id, float(l.along) + dd, Vector2(l.x + cx, l.y + cy), 1.2):
							clear = false
							print("    in the hull: ", id, " ", f.sections[i].name, " at ", Vector2(l.x + cx, l.y + cy))
			# and the way there keeps clear of it too
			var to := Vector3(l.x, l.y, l.along)
			var pts := Capital.glide(id, prev, to)
			if Capital.glide_hits(id, pts, prev.z, to.z) > 0:
				glides = false
				print("    glide through the hull: ", id, " to ", f.sections[i].name)
			prev = to
			# guns on the hull: standing on its top, out on a sponson, or slung beneath
			for g: Array in f.sections[i].guns:
				var m := Capital.mount(id, i, g)
				var at: Vector3 = m.at
				var h: float = Rules.GUN_H[g[0]]
				var ok := true
				match m.how:
					"deck":
						ok = absf(at.y - h - Capital.top_y(id, -at.z, at.x)) < 0.01
					"hang":
						ok = absf(at.y + h - Capital.bottom_y(id, -at.z, at.x)) < 0.01
					"side":
						ok = not Capital.inside(id, -at.z, Vector2(at.x, at.y), 0.5) and absf(at.x - float(m.face)) < 22.0
				if not ok:
					mounted = false
					print("    gun off the hull: ", id, " ", g, " ", m)
		check(clear and glides and mounted, "%s: every lane and glide clear of the hull, every gun on it" % f.name)
		# a shield pylon can always be shot: no gun in front of it hides it from the lane (the ship's
		# guns fire along the lane's dip, so seen along it)
		var open := true
		for i in f.sections.size():
			var l := Capital.lane(id, i)
			for gb: Array in f.sections[i].guns:
				if gb[0] != "pylon":
					continue
				var B := Rules.gun_at(id, i, gb)
				var db: float = -B.z - float(l.along)
				var pb := Vector2(B.x, B.y + db * float(l.dip))
				for ga: Array in f.sections[i].guns:
					var A := Rules.gun_at(id, i, ga)
					var da: float = -A.z - float(l.along)
					if ga != gb and da < db and Vector2(A.x, A.y + da * float(l.dip)).distance_to(pb) < float(Rules.FOES[ga[0]].r) + 1.2:
						open = false
						print("    pylon hidden: ", id, " ", f.sections[i].name, " by ", ga)
		check(open, "%s: its shield pylons can be shot" % f.name)
		# compact (Guillaume: "you already see the next section, receive its bullets"; then "do the
		# opposite approach: start by designing a fortress, then choose a path that would clear it by
		# sections"): from each section's lane the next section's guns are in range and in sight
		# round the hull (guns don't fire through it), and the sections overlap along the hull
		var near := true
		for i in f.sections.size() - 2:
			var l := Capital.lane(id, i)
			var seen := 0
			for g: Array in f.sections[i + 1].guns:
				var at := Rules.gun_at(id, i + 1, g)
				var dist: float = -at.z - float(l.along)
				if dist > 5.0 and dist <= 62.0 and in_sight(id, l, at):
					seen += 1
			if seen == 0:
				near = false
				print("    next section out of sight: ", id, " ", f.sections[i].name)
		check(near, "%s: the next section's guns already in range and in sight from each lane" % f.name)
		var own := true
		for i in f.sections.size() - 1:
			var l := Capital.lane(id, i)
			for g: Array in f.sections[i].guns:
				if not in_sight(id, l, Rules.gun_at(id, i, g)):
					own = false
					print("    gun out of sight of its lane: ", id, " ", f.sections[i].name, " ", g)
		check(own, "%s: every gun in sight of its section's lane" % f.name)
		var L := Rules.fortress_len(id)
		var span := 0.0
		for i in f.sections.size() - 1:
			span += float(f.sections[i].len)
		var steps := true
		for i in range(1, f.sections.size() - 1):
			steps = steps and Rules.section_at(id, i) - Rules.section_at(id, i - 1) <= 20.0
		check(L <= 125.0 and span > L and steps, "%s: %.0f m, its sections overlapping (%.0f m of sections), each starting within 20 m of the last" % [f.name, L, span])
		# no two guns in each other's way
		var apart := true
		var pos: Array[Vector3] = []
		for i in f.sections.size():
			for g: Array in f.sections[i].guns:
				var at := Rules.gun_at(id, i, g)
				for p in pos:
					if p.distance_to(at) < 3.0:
						apart = false
						print("    guns on top of each other: ", id, " ", f.sections[i].name, " ", g)
				pos.append(at)
		check(apart, "%s: no two guns on top of each other" % f.name)
		var low := 1e9
		for i in f.sections.size():
			var l := Capital.lane(id, i)
			low = minf(low, Rules.deck_of(id) + float(l.y) + (l.reach as Vector4).z)
		check(low >= Rules.LOW - 0.01, "%s: the ship never comes within %.0f m of the ground (%.1f)" % [f.name, Rules.LOW, low])


## Whether a point on the ship is in sight of the ship anywhere the drag takes it in a lane.
func in_sight(id: String, l: Dictionary, at: Vector3) -> bool:
	var r: Vector4 = l.reach
	for p: Vector2 in [Vector2.ZERO, Vector2(r.x, 0), Vector2(r.y, 0), Vector2(0, r.z), Vector2(0, r.w)]:
		if Capital.sees(id, at, Vector3(l.x + p.x, l.y + p.y, -float(l.along))):
			return true
	return false


func make_game() -> Game:
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	g.rng.seed = 11
	root.add_child(g)
	return g


## Flies to the fortress of level lv and into the chase.
func to_chase(g: Game, lv: int) -> void:
	g.launch(lv)
	g.boss_done = true
	for k in g.waves.size():
		if g.waves[k].kind == "fortress":
			g.wave_i = k
			g.stage_t = g.waves[k].t
	for i in int(40.0 / DT):
		g.hp = maxi(g.hp, 2)
		g.step(DT)
		if g.phase == "pov":
			break


func fight() -> void:
	print("fire and aim")
	var g := make_game()
	await process_frame
	var lv := Campaign.FORTRESS_ORDER.find("basilisk")
	to_chase(g, lv)
	check(g.phase == "pov" and g.fort_id == "basilisk", "the Basilisk's chase begins")
	# Guillaume: "I can shoot down their bullets, there is some form of auto aim"
	var o := g.shoot(g.ppos + Vector3(0, 0, -12), Vector3(0, 0, 1), 8.0)
	var shot := g.new_shot(o.pos + Vector3(0, 0, 0.1), Vector3(0, 0, -80.0), 5.0)
	g.collide(DT)
	check(not o.dead and not shot.dead, "a boss's shot can't be shot down")
	shot.dead = true
	var rk := g.shoot(g.ppos + Vector3(0, 0, -12), Vector3(0, 0, 1), 8.0)
	rk.homing = 2.0
	rk.hp = 3.0
	var shot2 := g.new_shot(rk.pos + Vector3(0, 0, 0.1), Vector3(0, 0, -80.0), 1.0)
	g.collide(DT)
	check(shot2.dead and not rk.dead, "a rocket can, but takes a few hits")
	check(Rules.AIM_ASSIST <= 1.5, "the aim assist only nudges (%.1f m)" % Rules.AIM_ASSIST)
	o.dead = true
	rk.dead = true
	# a gun slung under the hull hangs upside down; the lane beneath it aims up
	var hung := 0
	for f in g.fort_guns:
		if Capital.route_of(g.fort_id, f.sec) == "under" and absf(f.node.rotation.z - PI) < 0.01:
			hung += 1
	check(hung > 0, "guns slung under the hull hang upside down (%d)" % hung)
	var ahead := 0
	for f in g.fort_guns:
		if f.sec == g.fort_sec + 1 and g.lockable(f):
			ahead += 1
	check(ahead > 0, "the next section's guns are already in the fight (%d)" % ahead)
	# the whole fight, the ship lined up with each gun in turn
	var routes := {}
	var lowest := 1e9
	var max_dip := 0.0
	var held_up := true
	var cruise := 0.0
	var min_dip := 1.0
	for i in int(400.0 / DT):
		g.hp = maxi(g.hp, 2)
		var best: Game.Obj = null
		for f in g.foes:
			if f.kind not in ["orb", "boss"] and g.lockable(f) and f.pos.z < g.ppos.z - 4.0:
				if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
					best = f
		if best:
			g.off = g.line_up(best)
		g.step(DT)
		if g.phase in ["pov", "core"] and not g.lane.is_empty():
			routes[g.lane.route] = true
			max_dip = maxf(max_dip, g.aim_dip)
			min_dip = minf(min_dip, g.aim_dip)
		if g.phase == "escape" and g.fortress != null:
			for seg in g.segs:
				lowest = minf(lowest, seg.global_position.y - 14.0)
			g.touching = false
			g.slow_down(0.5)
			held_up = held_up and not g.paused() and g.time_speed() > 0.99
			cruise = g.chase_y
		if g.phase == "results" or g.phase == "clear":
			break
	check(g.phase in ["clear", "results"], "the Basilisk taken apart, its reactor down from beneath its throat")
	check(routes.has("top") and routes.has("left") and routes.has("right") and routes.has("under"),
		"over it, along both flanks and beneath it (%s)" % [routes.keys()])
	check(min_dip < 0.0 and max_dip > 0.0, "the guns aim up from beneath, down from above")
	check(held_up, "lifting the finger doesn't pause the break-up")
	# Guillaume: high up after the kill "you can see the limited decor"
	check(cruise > 0.0 and cruise <= Rules.CRUISE_Y + 0.01, "the ship flies on low after the kill (%.1f m)" % cruise)
	check(lowest > 4.0, "it breaks up in the air (lowest piece %.1f m up)" % lowest)
	g.queue_free()
	await process_frame


## Guillaume: "I don't want the ship to be hit during fortress transitions".
func transits() -> void:
	print("no hits between sections")
	var g := make_game()
	await process_frame
	to_chase(g, Campaign.FORTRESS_ORDER.find("albatross"))
	check(not g.transit(), "at its first section, the ship can be hit")
	g.inv = 0.0
	var hp0: int = g.hp
	for p in g.fort_parts.duplicate():
		g.damage(p, 99999.0)
	g.step(DT)
	var gliding: bool = g.transit()
	var shot3 := g.shoot(g.ppos, Vector3(0, 0, 1), 0.0)
	g.collide(DT)
	g.hurt()
	check(gliding and g.hp == hp0 and not shot3.dead, "gliding on to the next section, shots pass through the ship")
	shot3.dead = true
	while g.transit():
		g.step(DT)
	var shot4 := g.shoot(g.ppos, Vector3(0, 0, 1), 0.0)
	g.collide(DT)
	check(g.hp == hp0 - 1 and shot4.dead, "once there, they hit again")
	g.hp = hp0
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage bosses test")
	roster()
	lanes()
	await fight()
	await transits()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
