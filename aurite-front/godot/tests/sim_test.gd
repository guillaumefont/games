extends Node
const Cutscenes := preload("res://scripts/cutscenes.gd")
const Squads := preload("res://scripts/squads.gd")
const TD := preload("res://scripts/tutorial_data.gd")  # no class_name: an installed shell would not know a new global class
class Host:
	var log := []
	func toast(m, k = ""): log.append(m)
	func radio(who, m, warn = false): log.append(who + ": " + m)
	func sfx(n, x = null, y = null): pass
	func say(k, x = null, y = null): log.append("SAY " + k)
	func on_world_changed(): pass
	func on_sel_changed(): pass
	func on_vision(): pass
	func add_scorch(x, y, r): pass
	func end_game(w): log.append("END " + str(w))
## Meets each goal of the running mission by hand (teleports, kills, timers) and checks the mission is won.
func solve(s, h) -> bool:
	h.log.clear()
	for guard in 12:
		if s.over: break
		var g = s.goal()
		if g == null: break
		var g0: int = s.gi
		for e in s.ents:
			if e.team == 0 and e.kind == "u": e.hp = e.max_hp   # keep heroes alive while we cheat
		# a goal with a wave plan really sends enemies (no cheating): jump to the next wave and let it land
		if g.waves != null:
			var before: int = s.nid
			s.g_t0 = s.time - g.waves.first - s.wst.get("wn", 0) * g.waves.every - 0.5
			for i in 40: s.step(0.05)
			var spawned: Array = s.ents.filter(func(e): return e.id >= before and e.team == 1 and e.kind == "u")
			print("   ", g.k, " wave ", s.wst.get("wn", 0), ": ", spawned.size(), " enemy units")
			if spawned.size() < 2:
				print("  no wave arrived"); return false
		match g.k:
			"destroy_all":
				for e in s.ents.duplicate():
					if e.alive and e.team == 1: s.kill(e)
			"kill":
				for e in s.goal_targets(g): s.kill(e)
			"mine": s.stats.mined += g.n
			"survive": s.g_t0 -= g.t
			"reach":
				var u = s._hero_alive(0) if g.who == "hero" else s.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.captive)[0]
				u.x = g.at[0] * D.T + 16; u.y = g.at[1] * D.T + 16; u.path = []
			"hold":
				for e in s.ents.duplicate():
					if e.alive and e.team == 1 and e.kind == "u": s.kill(e)
				var us = s.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.d.air and not e.d.harv)
				for i in g.zones.size():
					us[i].x = g.zones[i][0] * D.T + 16; us[i].y = g.zones[i][1] * D.T + 16; us[i].path = []; us[i].order = "none"
				s.gst.held = g.t - 1
			"escort":
				for e in s.ents:
					if e.alive and e.tag == "vip" and not e.captive: e.x = g.at[0] * D.T + 16; e.y = g.at[1] * D.T + 16; e.path = []
			"rescue":
				var u = s._hero_alive(0)
				if u == null: u = s.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u")[0]
				for c in s.ents.filter(func(e): return e.alive and e.captive):
					u.x = c.x + 20; u.y = c.y; u.path = []
					s.mission_tick()
			"capture":
				for e in s.goal_targets(g, -1): e.team = 0
		for i in 30:
			s.step(0.05)
			if s.over or s.gi != g0: break
		if not s.over and s.gi == g0: s.mission_tick()
		if s.gi == g0 and not s.over:
			print("  goal ", g.k, " did not complete"); return false
	return h.log.has("END true")

func _ready():
	var t0 = Time.get_ticks_msec()
	var s = Sim.new(); var h = Host.new(); s.host = h
	if OS.get_environment("AF_ONLY") == "missions":
		for C in D.CAMPAIGNS:
			for m in C.missions:
				s.new_game("normal", {"mission": m})
				var dk: Array = s.ents.filter(func(e): return e.alive and e.kind == "b" and e.dark and e.type != "wall").map(func(e): return str(e.team) + e.type)
				var miss: Array = (m.pbase as Array).filter(func(t): return s.count(0, t) == 0)
				var emiss: Array = (m.ebase as Array).filter(func(t): return s.count(1, t) == 0)
				print(C.num, ".", m.idx + 1, " dark ", dk, " missing ", miss, " enemy missing ", emiss, " masts ", s.count(0, "sigmast"), "/", s.count(1, "sigmast"))
		get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "cards":
		# what each mission gives the player (owned from the start in capitals) and whether it has a tutorial card
		for C in D.CAMPAIGNS:
			var known := {}
			for i in C.missions.size():
				s.new_game("normal", {"mission": C.missions[i]})
				var types := {}
				for t in D.UN.keys() + D.BLD.keys():
					if s.avail(0, t) and s.mission.tech != null: types[t] = false
				for e in s.ents:
					if e.team == 0: types[e.type] = true
				var fresh: Array = []
				for t in types:
					if known.has(t): continue
					known[t] = true
					fresh.append((t.to_upper() if types[t] else t) + ("" if TD.CARDS.has(t) else "?"))
				var foes := {}
				for e in s.ents:
					if e.team == 1: foes[e.type] = true
				print(C.id, " ", i + 1, " ", C.missions[i].title, ": ", fresh, " | enemy ", foes.keys())
		get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "duel":
		# AI against AI, for balance: AF_A and AF_B are the factions, AF_N the number of games, AF_MIN the length, AF_LOG=1 a line a minute
		var fa := OS.get_environment("AF_A"); var fb := OS.get_environment("AF_B")
		var wins := [0, 0, 0]; var n: int = maxi(1, int(OS.get_environment("AF_N")))
		var mins: int = int(OS.get_environment("AF_MIN")) if OS.get_environment("AF_MIN") != "" else 20
		for g in n:
			s.new_game("normal", {"fac": fa, "enemy": fb, "seed": 1000 + g * 77})
			for i in 20 * 60 * mins:
				s.step(0.05)
				if i % 20 == 0: s.ai_think(s.teams[0])
				if OS.get_environment("AF_LOG") != "" and i % 1200 == 0:
					var c := [{}, {}]
					for e in s.ents:
						if e.alive and e.team < 2: c[e.team][e.type] = c[e.team].get(e.type, 0) + 1
					print(int(s.time), " A ", int(s.teams[0].credits), " earned ", int(s.teams[0].earned), " ", c[0], "\n    B ", int(s.teams[1].credits), " earned ", int(s.teams[1].earned), " ", c[1])
				if s.over: break
			var w := 2
			if s.over: w = 0 if s.find_hq(0) != null else 1
			else:
				# no knock-out: whoever has the stronger army and defences, by cost
				var v := [0.0, 0.0]
				for e in s.ents:
					# fighting strength only: a rich economy that has not won yet is not a win
					if e.alive and e.team < 2 and (e.kind == "u" and not e.d.harv or e.d.weapon != ""): v[e.team] += e.d.cost * e.hp / e.max_hp
				w = 0 if v[0] > v[1] * 1.25 else (1 if v[1] > v[0] * 1.25 else 2)
			wins[w] += 1
			print("game ", g, ": ", [fa, fb, "draw"][w], " t=", int(s.time), " over=", s.over)
		print("DUEL ", fa, " ", wins[0], " : ", wins[1], " ", fb, " (draws ", wins[2], ")")
		get_tree().quit(0); return
	if OS.get_environment("AF_ONLY").begins_with("choir"):
		print("ONLY ", choir_tests(s, h, OS.get_environment("AF_ONLY") == "choirsoak")); get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "vanguard":
		print("ONLY ", vanguard_tests(s, h)); get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "orders":
		print("ONLY ", order_tests(s, h)); get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "gfx":
		print("ONLY ", gfx_tests()); get_tree().quit(0); return
	if OS.get_environment("AF_ONLY") == "voice":
		print("ONLY ", voice_tests(s, h)); get_tree().quit(0); return
	s.new_game("hard", {"fac": "ashen"})
	print("setup ms ", Time.get_ticks_msec() - t0, " ents ", s.ents.size())
	t0 = Time.get_ticks_msec()
	var mx := 0
	var ups := {}   # upgrades either AI made: "team type" -> true
	for i in 20 * 60 * 15:
		var a = Time.get_ticks_usec()
		s.step(0.05)
		if i % 20 == 0:
			s.ai_think(s.teams[0])
			for e in s.ents:
				if e.alive and e.kind == "b" and e.lv > 1: ups["%d %s" % [e.team, e.type]] = true
		mx = max(mx, Time.get_ticks_usec() - a)
		if i % 2400 == 0: print("t=", int(s.time), " ents=", s.ents.size(), " proj=", s.proj.size(), " parts=", s.parts.size(), " worst step us=", mx)
		if s.over: break
	print("8 min sim ms ", Time.get_ticks_msec() - t0, " t=", s.time, " ents ", s.ents.size(), " credits ", int(s.teams[0].credits), "/", int(s.teams[1].credits))
	var c = {}
	for e in s.ents: c[str(e.team)+e.type] = c.get(str(e.team)+e.type, 0) + 1
	print(c)
	print(h.log.slice(-10))
	print("AI upgrades in the soak: ", ups.keys())
	if ups.is_empty():
		print("UPGRADE TEST FAILED: neither skirmish AI upgraded anything"); get_tree().quit(1); return
	# every mission sets up, runs a minute, and can be won by meeting its goals in order
	for C in D.CAMPAIGNS:
		for m in C.missions:
			s.new_game("normal", {"mission": m})
			if s.teams[0].fac != C.fac or D.TEAMC[0] != D.FCOL[C.fac]:
				print("MISSION TEST FAILED: wrong faction or colour in ", m.title); get_tree().quit(1); return
			var dk: Array = s.ents.filter(func(e): return e.alive and e.kind == "b" and e.dark and e.type != "wall").map(func(e): return str(e.team) + e.type)
			var miss: Array = (m.pbase as Array).filter(func(t): return s.count(0, t) == 0 and t != "burrow" and not s.lacks(0, t)) + (m.ebase as Array).filter(func(t): return s.count(1, t) == 0 and t != "burrow" and not s.lacks(1, t))
			if dk.size() or miss.size():
				print("MISSION TEST FAILED: ", m.title, " starts with dark buildings ", dk, " or missing ", miss); get_tree().quit(1); return
			for i in 1200: s.step(0.05)
			var txt: String = s.obj_text()
			print(C.num, ".", m.idx + 1, " ", m.title, " ents=", s.ents.size(), " over=", s.over, " | ", txt.replace("\n", " | "))
			if s.over or txt == "":
				print("MISSION TEST FAILED: ", m.title, " ended or has no objective after a minute: ", h.log.slice(-3)); get_tree().quit(1); return
			var won := solve(s, h)
			if not won:
				print("MISSION TEST FAILED: could not win ", m.title, " goal ", s.gi, " ", h.log.slice(-4)); get_tree().quit(1); return
	# formation move: a unit far behind must not slow the main body down
	# fixed map: on some random maps the near units' paths differ enough to trip the pace check
	s.new_game("normal", {"fac": "vanguard", "seed": 4242})
	var bx: float = (D.P0.x + 4) * D.T; var by: float = (D.P0.y - 4) * D.T
	var near := []
	for i in 3: near.append(s.spawn_unit(0, "rifle", bx + i * D.T, by))
	var far = s.spawn_unit(0, "rifle", bx + 30 * D.T, by - 25 * D.T)
	s.group_move(near + [far], bx + 2 * D.T, by - 6 * D.T, "move")
	var slow := near.filter(func(u): return u.fspd > 0 and u.fspd < u.d.spd * 0.6)
	print("formation near fspd=", near.map(func(u): return snappedf(u.fspd, 0.01)), " far fspd=", far.fspd, " spd=", far.d.spd)
	if slow.size() or far.path.is_empty():
		print("FORMATION TEST FAILED"); get_tree().quit(1); return
	# formation off: player units go straight to the spot at their own speed, no ranks
	s.formation = false
	s.group_move(near, bx + 2 * D.T, by - 6 * D.T, "move")
	var paced := near.filter(func(u): return u.fspd > 0 or u.path.is_empty())
	print("formation off fspd=", near.map(func(u): return u.fspd))
	s.formation = true
	if paced.size():
		print("FORMATION OFF TEST FAILED"); get_tree().quit(1); return
	if not groundwork_tests(s, h): get_tree().quit(1); return
	if not pact_tests(s, h): get_tree().quit(1); return
	if not vanguard_tests(s, h): get_tree().quit(1); return
	if not choir_tests(s, h): get_tree().quit(1); return
	if not upgrade_tests(s, h): get_tree().quit(1); return
	if not cutscene_tests(s, h): get_tree().quit(1); return
	if not tutorial_tests(s, h): get_tree().quit(1); return
	if not squad_tests(s, h): get_tree().quit(1); return
	if not order_tests(s, h): get_tree().quit(1); return
	if not gfx_tests(): get_tree().quit(1); return
	if not voice_tests(s, h): get_tree().quit(1); return
	print("SIM TEST DONE")
	get_tree().quit()

## Every cutscene: its map and cast set up, its timeline runs on the sim (no AI, no goals), its cast
## stays on the map, nobody dies by accident, and the mission it belongs to still plays normally afterwards.
func cutscene_tests(s, h) -> bool:
	for id in Cutscenes.all():
		var sc: Dictionary = Cutscenes.scene(id)
		var M: Dictionary = D.camp(sc.camp).missions[sc.map]
		s.new_game("normal", {"mission": M, "cine": true, "bare": sc.get("bare", false)})
		var cast: Dictionary = Cutscenes.setup(s, sc)
		for c in sc.get("cast", []):
			var want: int = c.get("b", []).size()
			for p in c.get("u", []): want += p[1]
			if cast[c.id].size() != want:
				print("CUTSCENE TEST FAILED: ", id, " cast ", c.id, " has ", cast[c.id].size(), " of ", want); return false
		var n0: int = s.ents.filter(func(e): return e.kind == "u").size()
		var total := 0.0
		for sh in sc.shots:
			if sh.has("follow") and not cast.has(sh.follow):
				print("CUTSCENE TEST FAILED: ", id, " follows unknown ", sh.follow); return false
			if sh.has("say") and sh.say[1].length() > 64:
				print("CUTSCENE TEST FAILED: ", id, " line too long for a phone: ", sh.say[1]); return false
			var fired := {}
			var t := 0.0
			while t < sh.d:
				for i in sh.get("do", []).size():
					if not fired.has(i) and t >= sh.do[i].get("t", 0.0):
						fired[i] = true; Cutscenes.act(s, cast, sh.do[i])
				s.step(0.05); t += 0.05
			total += sh.d
		var n1: int = s.ents.filter(func(e): return e.kind == "u" and e.alive).size()
		print("cutscene ", id, " ", snappedf(total, 0.1), "s units ", n0, " -> ", n1, " over=", s.over, " gi=", s.gi)
		if s.over or n1 < n0 - 1 or total > 50.0:
			print("CUTSCENE TEST FAILED: ", id, " ended the game, lost units or runs too long"); return false
		if s.cine == false or s.vis.count(2) != s.vis.size():
			print("CUTSCENE TEST FAILED: ", id, " not in cutscene mode"); return false
	# the mission after an intro is an ordinary game again
	s.new_game("normal", {"mission": D.camp("ashen").missions[0]})
	if s.cine or s.gi != 0:
		print("CUTSCENE TEST FAILED: mission after a cutscene is still in cutscene mode"); return false
	return true

func _fail(msg: String) -> bool:
	print("CHOIR TEST FAILED: ", msg); return false

## The Hollow Choir: AI soaks on both sides, then each of its systems on its own.
func choir_tests(s, h, soak := true) -> bool:
	for pair in ([["choir", "vanguard"], ["ashen", "choir"]] if soak else []):
		var t0 = Time.get_ticks_msec()
		s.new_game("normal", {"fac": pair[0], "enemy": pair[1]})
		if s.teams[0].fac != pair[0] or s.teams[1].fac != pair[1] or D.TEAMC[0] != D.FCOL[pair[0]]: return _fail("factions or colours not set")
		var ci: int = 0 if pair[0] == "choir" else 1
		var seen := {}   # every type the Choir side had at some point
		for i in 20 * 60 * 9:
			s.step(0.05)
			if i % 20 == 0:
				s.ai_think(s.teams[0])
				for e in s.ents:
					if e.team == ci: seen[e.type] = true
			if s.over: break
		var c = {}
		for e in s.ents: c[str(e.team) + e.type] = c.get(str(e.team) + e.type, 0) + 1
		print("choir soak ", pair, " ms ", Time.get_ticks_msec() - t0, " t=", int(s.time), " over=", s.over, " credits ", int(s.teams[0].credits), "/", int(s.teams[1].credits), " ", c)
		print("  the Choir had: ", seen.keys())
		if seen.has("refinery") or seen.has("harv") or seen.has("rifle"): return _fail("the Choir got a refinery, harvester or riflemen")
		if not seen.has("garden") or not seen.has("burrow"): return _fail("the Choir AI built no garden or no burrow")
		if not (seen.has("thrall") or seen.has("skitter") or seen.has("mantis")): return _fail("the Choir AI trained no army")
	# a fixed map for the unit tests
	s.new_game("normal", {"fac": "choir", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	for i in D.MW * D.MH: s.vis[i] = 2
	var hq = s.find_hq(0)
	var T: float = D.T
	if not s.avail(0, "thrall") or s.avail(0, "rifle") or s.avail(0, "refinery") or s.avail(0, "power") or not s.avail(0, "garden"): return _fail("availability")
	if s.avail(0, "wretch") or s.avail(0, "knot") or s.avail(0, "bloom"): return _fail("a Wretch, a Knot or an age can be ordered")
	if not s.lacks(0, "power") or s.lacks(0, "refinery") or s.uses_power(0): return _fail("the Choir should have no power and no reactor")
	if s.has_req(0, ["refinery"]): return _fail("refinery requirement met without a garden")
	# the Hum: growths only inside it; a Garden goes wherever there is living aurite
	if not s.can_place(0, "spire", hq.tx + 4, hq.ty, false): return _fail("a Spire inside the Yard's Hum was refused")
	if s.can_place(0, "spire", hq.tx + 12, hq.ty, false) or s.can_place(0, "spire", hq.tx + 3, hq.ty - 12, false): return _fail("a Spire outside the Hum was allowed")
	if s.can_place(0, "garden", hq.tx + 4, hq.ty, false) and s.live_ore(hq.tx + 5.0, hq.ty + 1.0, 3.5) == 0: return _fail("a Garden away from aurite was allowed")
	var oi := -1
	for i in D.MW * D.MH:
		if s.ore[i] > 0 and Vector2(i % D.MW - hq.tx, i / D.MW - hq.ty).length() < 16 and Vector2(i % D.MW - hq.tx, i / D.MW - hq.ty).length() > 8: oi = i; break
	if oi < 0: return _fail("no ore near the base on the test map")
	var gp = null
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if gp == null and s.can_place(0, "garden", oi % D.MW + dx, oi / D.MW + dy, false): gp = Vector2i(oi % D.MW + dx, oi / D.MW + dy)
	if gp == null: return _fail("no room for a Garden beside the field, outside the Hum")
	var g = s.add_building(0, "garden", gp.x, gp.y)
	if not s.has_req(0, ["refinery"]) or not s.has_req(0, ["barracks"]) or not s.has_req(0, ["factory"]): return _fail("a Garden does not stand in for the refinery, barracks and factory")
	if not s.in_hum(0, g.x + 4 * T, g.y) or s.in_hum(0, g.x + 6 * T, g.y + 6 * T): return _fail("the Garden's Hum")
	# it earns on its own, with no harvester
	var cr0: float = s.teams[0].credits
	for i in 20 * 9: s.step(0.05)
	print("garden: +", int(s.teams[0].credits - cr0), " aurite in 9 s, ", g.pods, " Pod")
	if s.teams[0].credits - cr0 < 30: return _fail("garden gave nothing")
	if s.ents.any(func(e): return e.alive and e.team == 0 and e.kind == "u" and e.d.harv): return _fail("the Choir has a harvester")
	# Pods: one to start with, one more every 15 s, three at most; a unit needs one to start
	if g.pods != 1: return _fail("a new Garden should hold one Pod, has %d" % g.pods)
	for i in 20 * 8: s.step(0.05)
	if g.pods != 2: return _fail("no second Pod after 15 s")
	for i in 20 * 40: s.step(0.05)
	if g.pods != D.HUM.hold or s.pods(0) != D.HUM.hold: return _fail("Pods did not stop at %d" % D.HUM.hold)
	s.teams[0].credits = 5000.0
	var th0: int = s.count(0, "thrall")
	for i in 5: s.teams[0].prod.inf.queue.append("thrall")
	for i in 20 * 14: s.step(0.05)
	var hatched: int = s.count(0, "thrall") - th0
	print("pods: ", hatched, " Thralls hatched from 3 Pods in 14 s, ", s.teams[0].prod.inf.queue.size(), " broods still waiting")
	if hatched != 9 or s.pods(0) != 0: return _fail("3 Pods should hatch exactly 3 broods of 3 before the next one ripens")
	s.teams[0].prod.inf.queue.clear(); s.teams[0].prod.inf.cur = ""
	for e in s.ents:
		if e.kind == "u" and e.team == 0: e.alive = false
	# aging: Sprout, Bloom, Cathedral; each age unlocks forms and widens the Hum
	if s.has_req(0, D.UN.mantis.req) or s.has_req(0, D.UN.carillon.req): return _fail("a Sprout unlocks later forms")
	if s.upg_def(g).is_empty() or s.upg_def(g).name != "Bloom Garden": return _fail("a Sprout has no Bloom to grow into")
	s.teams[0].credits = 5000.0
	if not s.start_upgrade(g): return _fail("aging did not start: " + s.upg_block(g))
	for i in 20 * 62: s.step(0.05)
	if g.lv != 2 or g.d.name != "Bloom Garden" or g.d.hum != 7.0 or s.count(0, "bloom") != 1: return _fail("Bloom")
	if not s.has_req(0, D.UN.mantis.req) or s.has_req(0, D.UN.carillon.req): return _fail("what a Bloom unlocks")
	var rate2: float = g.d.rate
	if s.upg_def(g).is_empty() or s.upg_def(g).name != "Cathedral Garden": return _fail("a Bloom has no Cathedral to grow into")
	s.finish_upgrade(g)
	if g.lv != 3 or g.d.hum != 9.0 or g.d.rate <= rate2 or s.count(0, "cathedral") != 1 or s.count(0, "bloom") != 1: return _fail("Cathedral")
	if not s.has_req(0, D.UN.carillon.req) or not s.has_req(0, D.BLD.chorus.req) or not s.upg_def(g).is_empty(): return _fail("what a Cathedral unlocks")
	# the crystal spreads one tile at a time inside the Hum
	var n0 := 0
	for i in D.MW * D.MH:
		if s.ore0[i] > 0: n0 += 1
	g.spread_t = D.HUM.spread
	s.step(0.05)
	var n1 := 0
	for i in D.MW * D.MH:
		if s.ore0[i] > 0: n1 += 1
	if n1 != n0 + 1: return _fail("the crystal did not spread (%d -> %d tiles)" % [n0, n1])
	# in the Hum the Choir heals and hurries; a Wretch withers outside it
	var ht = s.spawn_unit(0, "thrall", g.x + 3 * T, g.y); ht.hp = 10.0
	var wo = s.spawn_unit(0, "wretch", hq.x + 14 * T, hq.y - 14 * T)
	var wi = s.spawn_unit(0, "wretch", g.x - 3 * T, g.y); wi.hp = 20.0
	for i in 20 * 5: s.step(0.05)
	print("hum: Thrall 10 -> ", int(ht.hp), ", Wretch outside ", int(wo.hp), "/", int(wo.max_hp), ", inside ", int(wi.hp))
	if ht.hp < 13.5 or not ht.inhum or wo.hp > wo.max_hp - 4 or wi.hp < 20: return _fail("Hum healing or withering")
	ht.alive = false; wo.alive = false; wi.alive = false
	# living crystal cuts human infantry in the Hum, and the dead rise as Wretches
	var ot := -1
	for i in D.MW * D.MH:
		if s.ore[i] > 0 and s.in_hum(0, (i % D.MW) * T + 16, (i / D.MW) * T + 16): ot = i; break
	if ot < 0: return _fail("no crystal inside the Garden's Hum")
	var vr = s.spawn_unit(1, "rifle", (ot % D.MW) * T + 16, (ot / D.MW) * T + 16); vr.hp = 9.0
	var vt = s.spawn_unit(1, "tank", (ot % D.MW) * T + 16, (ot / D.MW) * T + 16)
	var tk0: float = vt.hp
	for i in 20 * 2: s.step(0.05)
	if vr.hp >= 9.0 and vr.alive: return _fail("crystal did not cut a soldier")
	if vt.hp < tk0: return _fail("crystal cut a tank")
	vt.alive = false
	for i in 20 * 6: s.step(0.05)
	var ws: Array = s.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "wretch")
	print("hollowing: soldier alive=", vr.alive, ", Wretches risen ", ws.size())
	if vr.alive or ws.size() != 1: return _fail("the dead soldier did not rise as one Wretch")
	for w in ws: w.alive = false
	# mutation: the third kill changes a form for good
	var mt = s.spawn_unit(0, "thrall", g.x + 2 * T, g.y + 3 * T); mt.kills = D.HUM.mut - 1
	var prey = s.spawn_unit(1, "rifle", mt.x + T * 2, mt.y); prey.hp = 1.0; prey.cd = 99.0
	for i in 20 * 4: s.step(0.05)
	if prey.alive or not mt.mut or abs(mt.max_hp - 45 * 1.4) > 0.5 or D.UN.thrall.hp != 45: return _fail("Thrall mutation")
	mt.alive = false
	for e in s.ents:
		if e.type == "wretch": e.alive = false
	# fusion: four Thralls make a Knot, three do not
	var fs: Array = []
	for i in 3: fs.append(s.spawn_unit(0, "thrall", hq.x + (4 + i) * T, hq.y + 4 * T))
	if s.fuse(0, fs) != null: return _fail("three Thralls fused")
	for i in 2: fs.append(s.spawn_unit(0, "thrall", hq.x + (4 + i) * T, hq.y + 5 * T))
	var kn = s.fuse(0, fs)
	if kn == null or kn.type != "knot" or kn.max_hp != 700 or fs.filter(func(u): return u.alive).size() != 1: return _fail("fusion")
	for u in fs: u.alive = false
	# a Knot crushes what stands beside its target
	var k1 = s.spawn_unit(1, "rifle", kn.x + T * 0.8, kn.y); var k2 = s.spawn_unit(1, "rifle", kn.x + T * 1.3, kn.y + 8)
	k1.hp = 999; k1.max_hp = 999; k2.hp = 999; k2.max_hp = 999; kn.stun = 0.0
	for i in 20 * 4: s.step(0.05)
	if k1.hp >= 999 or k2.hp >= 999: return _fail("Knot crush")
	k1.alive = false; k2.alive = false; kn.alive = false
	# Keener: its cry jams a tank and drops its shield; soldiers do not care
	var kt = s.spawn_unit(1, "tank", hq.x + 9 * T, hq.y + 9 * T); var ks = s.spawn_unit(1, "rifle", kt.x, kt.y + T); ks.cd = 99.0
	kt.hp = 9999; kt.max_hp = 9999
	if kt.sh_max <= 0: return _fail("the test tank has no shield")
	var ke = s.spawn_unit(0, "keener", kt.x + T * 1.5, kt.y); ke.hp = 9999
	for i in 12: s.step(0.05)
	if kt.jam_t <= s.time or kt.sh != 0.0 or ks.jam_t > s.time or ke.cry_t < 10: return _fail("Keener cry")
	var kh: float = ke.hp
	for i in 20 * 3: s.step(0.05)
	if ke.hp < kh - 1: return _fail("a jammed tank kept firing")
	ke.alive = false; kt.alive = false; ks.alive = false
	# Burster: it is its own charge
	var bt = s.add_building(1, "turret", hq.tx + 12, hq.ty + 6); bt.jam_t = 1e9
	var bu = s.spawn_unit(0, "sapper", bt.x - T * 3, bt.y)
	bu.target = bt; bu.order = "attack"
	for i in 20 * 8: s.step(0.05)
	print("burster: alive=", bu.alive, " turret ", int(bt.hp), "/", int(bt.max_hp))
	if bu.alive or bt.hp > bt.max_hp - 100: return _fail("Burster")
	s.kill(bt)
	# Carillon: it carries the Hum, and its toll only falls on soldiers
	var cx: float = hq.x + 16 * T; var cy: float = hq.y - 12 * T
	if s.in_hum(0, cx, cy): return _fail("test spot already in the Hum")
	var ca0 = s.spawn_unit(0, "carillon", cx, cy)
	s.calc_hum()
	if not s.in_hum(0, cx + 4 * T, cy) or not s.at_limit(0, "carillon"): return _fail("Carillon Hum or limit")
	var c1 = s.spawn_unit(1, "rifle", cx + 2 * T, cy); var c2 = s.spawn_unit(1, "rifle", cx + 2.8 * T, cy); var c3 = s.spawn_unit(1, "tank", cx + 2 * T, cy + T)
	for u in [c1, c2, c3]: u.hp = 9999; u.max_hp = 9999; u.cd = 99.0; u.jam_t = 1e9
	var sh3: float = c3.sh
	for i in 20 * 5: s.step(0.05)
	if c1.hp >= 9999 or c2.hp >= 9999 or c3.hp < 9999 or c3.sh < sh3: return _fail("Carillon toll")
	for u in [c1, c2, c3, ca0]: u.alive = false
	s.calc_hum()
	# Thornglass cuts infantry that lean on it
	var tg = s.add_building(0, "thorn", hq.tx + 3, hq.ty + 5)
	var tv = s.spawn_unit(1, "rifle", tg.x + T * 0.9, tg.y); tv.hp = 9999; tv.max_hp = 9999; tv.cd = 99.0; tv.jam_t = 1e9
	for i in 20 * 3: s.step(0.05)
	if tv.hp >= 9999 - 5: return _fail("Thornglass")
	tv.alive = false
	print("choir: Hum, Pods, ages, spread, Hollowing, mutation, fusion, Keener, Burster, Carillon, Thornglass ok")
	# tunnels: a far burrow, units walk into the yard and come out of the burrow
	var bp := Vector2i(hq.tx + 22, hq.ty - 22)
	var bur = s.add_building(0, "burrow", bp.x, bp.y)
	var us := []
	for i in 4: us.append(s.spawn_unit(0, "thrall", (hq.tx + 1 + i) * D.T + 16, (hq.ty + 4) * D.T + 16))
	s.group_move(us, (bp.x + 1) * D.T, (bp.y + 6) * D.T, "move")
	if us.filter(func(u): return u.tun != null).is_empty(): return _fail("no unit planned a tunnel trip")
	var went := false
	for i in 20 * 25:
		s.step(0.05)
		for u in us:
			if u.intun > 0: went = true
	var arrived := us.filter(func(u): return Vector2(u.x - (bp.x + 1) * D.T, u.y - (bp.y + 6) * D.T).length() < D.T * 4)
	print("tunnel: underground=", went, " arrived ", arrived.size(), "/", us.size(), " in 25 s")
	if not went or arrived.size() < 3: return _fail("tunnel trip")
	# a unit in a tunnel cannot be hit; a moving sapper is burrowed
	var sp = s.spawn_unit(0, "sapper", (hq.tx + 2) * D.T, (hq.ty + 6) * D.T)
	s.group_move([sp], (hq.tx + 9) * D.T, (hq.ty + 6) * D.T, "move")
	for i in 10: s.step(0.05)
	var en = s.spawn_unit(1, "rifle", sp.x + D.T * 2, sp.y)
	if not sp.under or s.find_target(en, D.T * 6) == sp: return _fail("moving sapper not burrowed")
	en.alive = false
	# geode lobber: splash plus a lingering shard field
	var gl = s.spawn_unit(0, "geode", (hq.tx + 4) * D.T, (hq.ty + 12) * D.T)
	var vic = s.spawn_unit(1, "rifle", gl.x + D.T * 6, gl.y)
	vic.hp = 9999; vic.max_hp = 9999
	gl.target = vic; gl.order = "attack"
	var saw_field := false
	for i in 20 * 8:
		s.step(0.05)
		if s.fields.size(): saw_field = true
	print("geode: fields seen=", saw_field, " victim hp ", int(vic.hp))
	if not saw_field or vic.hp >= 9999: return _fail("geode lobber left no shard field")
	vic.alive = false; gl.alive = false
	# the Cantor: one at a time, lifts nearby units
	var ca = s.spawn_unit(0, "cantor", (hq.tx + 6) * D.T, (hq.ty + 8) * D.T)
	var th = s.spawn_unit(0, "thrall", ca.x + D.T, ca.y)
	for i in 30: s.step(0.05)
	if th.aura_t <= 0: return _fail("Cantor aura")
	if not s.at_limit(0, "cantor"): return _fail("a second Cantor allowed")
	# Chorus Well: a burst and a long shard field
	var ch = s.add_building(0, "chorus", hq.tx - 6, hq.ty + 6)
	s.fields = []
	s.launch_sw(ch, (hq.tx + 20) * D.T, (hq.ty - 10) * D.T)
	for i in 20 * 4: s.step(0.05)
	if s.fields.filter(func(f): return f.r > D.T * 3).is_empty(): return _fail("Chorus Well left no field")
	print("choir tests ok")
	return true

func _ufail(msg: String) -> bool:
	print("UPGRADE TEST FAILED: ", msg); return false

## Building upgrades: cost, requirements, cancel, sell, each effect, and the campaign AI rule (Hard only).
func upgrade_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	var hq = s.find_hq(0)
	var pw = s.add_building(0, "power", hq.tx + 4, hq.ty)
	if s.upg_block(pw) == "": return _ufail("reactor upgrade allowed without a refinery")
	var rf = s.add_building(0, "refinery", hq.tx - 5, hq.ty + 4)
	if s.upg_block(pw) != "": return _ufail("reactor upgrade blocked: " + s.upg_block(pw))
	if s.upg_block(rf) == "": return _ufail("refinery upgrade allowed without a comms array")
	# cancel refunds what was paid
	s.teams[0].credits = 5000.0
	s.start_upgrade(pw)
	for i in 40: s.step(0.05)
	if pw.upg <= 0 or s.teams[0].credits >= 5000: return _ufail("upgrade did not start paying")
	s.cancel_upgrade(pw)
	if abs(s.teams[0].credits - 5000.0) > 4 or pw.upg >= 0: return _ufail("cancel did not refund")
	# full reactor upgrade: +150 power, more hp, costs 450, new name
	var pm0: int = s.teams[0].pmade
	s.start_upgrade(pw)
	for i in 20 * 14: s.step(0.05)
	print("reactor: lv ", pw.lv, " ", pw.d.name, " power ", pm0, " -> ", s.teams[0].pmade, " paid ", int(5000.0 - s.teams[0].credits), " hp ", int(pw.hp), "/", int(pw.max_hp))
	if pw.lv != 2 or pw.d.name != "Roaring Furnace" or s.teams[0].pmade != pm0 + 150 or pw.max_hp != 1000: return _ufail("reactor upgrade")
	if abs((5000.0 - s.teams[0].credits) - 450) > 14: return _ufail("reactor upgrade cost")
	if s.upg_block(pw) == "" or not s.upg_def(pw).is_empty(): return _ufail("upgraded twice")
	# selling an upgraded building refunds half of both prices
	var cr: float = s.teams[0].credits
	var got: int = s.sell(pw)
	if got != int((300 + 450) * 0.5): return _ufail("sell refund %d" % got)
	# barracks: faster training once upgraded
	s.add_building(0, "factory", hq.tx + 4, hq.ty + 5)
	var bk = s.add_building(0, "barracks", hq.tx - 4, hq.ty - 4)
	if s.prod_speed(0, "inf") != 1.0: return _ufail("speed before upgrade")
	s.finish_upgrade(bk)
	if abs(s.prod_speed(0, "inf") - 1.35) > 0.001 or s.prod_speed(0, "veh") != 1.0: return _ufail("Drill Hall speed")
	# sentry: the upgraded def carries the new weapon numbers
	var tu = s.add_building(0, "turret", hq.tx + 1, hq.ty + 5)
	s.finish_upgrade(tu)
	if tu.d.dmg != 85 or tu.d.range != 5.5 or tu.d.weapon != "shell": return _ufail("Heavy Sentry stats")
	# refinery yield: a full load is worth 25% more
	var ld := 0.0
	for k in 2:
		if k == 1: s.finish_upgrade(rf)
		var hv = s.spawn_unit(0, "harv", (rf.tx + 1) * D.T + 16, (rf.ty + 3) * D.T + 16)
		hv.load = 700.0; hv.ref = rf; hv.hs = "unload"; hv.mt = 0.0
		var c0: float = s.teams[0].credits
		for i in 20 * 3: s.step(0.05)
		hv.alive = false
		var gain: float = s.teams[0].credits - c0
		print("refinery lv", rf.lv, ": one load gave ", int(gain))
		if k == 1 and gain < ld * 1.2: return _ufail("Deep Refinery yield")
		ld = gain
	# campaign AI: never upgrades on Normal, may on Hard
	var m = null
	for C in D.CAMPAIGNS:
		for mm in C.missions:
			if m == null and mm.aiBuild and mm.ehq == "hq": m = mm
	for lv in ["normal", "hard"]:
		s.new_game("normal", {"mission": m, "level": lv})
		s.teams[1].credits = 50000.0
		var any := false
		for i in 20 * 60 * 3:
			s.step(0.05)
			if i % 40 == 0:
				for e in s.ents:
					if e.alive and e.team == 1 and e.kind == "b" and (e.lv > 1 or e.upg >= 0): any = true
			if any or s.over: break
		print("campaign AI on ", lv, " (", m.title, ") upgraded: ", any)
		if lv == "normal" and any: return _ufail("campaign AI upgraded on Normal")
		if lv == "hard" and not any: return _ufail("campaign AI never upgraded on Hard")
	print("upgrade tests ok")
	return true

func _tfail(msg: String) -> bool:
	print("TUTORIAL TEST FAILED: ", msg); return false

## The unit tutorial: every line fits a phone, every unit and building the player can have in a
## campaign has its card by the mission it first shows up, and every lesson and drill is well formed.
func tutorial_tests(s, h) -> bool:
	for k in TD.CARDS:
		var c: Dictionary = TD.CARDS[k]
		if c.job.length() > 60 or c.get("tip", "").length() > 60: return _tfail(k + " job or tip too long")
		if c.say.length() > 64: return _tfail(k + " line too long")
		if not D.SPEAKERS.has(c.who): return _tfail(k + " unknown speaker " + c.who)
		if not k.begins_with("l_") and D.def_of(k).is_empty(): return _tfail(k + " is not a unit or building")
	for camp in TD.ENEMY:
		for k in TD.ENEMY[camp]:
			var e: Dictionary = TD.ENEMY[camp][k]
			if e.text.length() > 64 or e.say.length() > 64: return _tfail("enemy " + k + " text too long")
	for id in TD.LESSONS:
		if not D.SPEAKERS.has(TD.LESSONS[id].who): return _tfail("lesson " + id + " unknown speaker")
		for st in TD.LESSONS[id].steps:
			if st.hint.length() > 60 or st.get("say", "").length() > 64: return _tfail("lesson " + id + " line too long: " + st.hint)
	var kinds := ["kill", "heal", "made", "rally", "group_recall", "all_army", "upgrade", "eng_fix", "revive", "launch"]
	var seen := {}
	var late := []
	for camp in TD.MISSIONS:
		var C: Dictionary = D.camp(camp)
		if TD.MISSIONS[camp].size() != C.missions.size(): return _tfail(camp + " has " + str(TD.MISSIONS[camp].size()) + " tutorial entries for " + str(C.missions.size()) + " missions")
		for i in C.missions.size():
			var T: Dictionary = TD.MISSIONS[camp][i]
			if T.has("lesson") and not TD.LESSONS.has(T.lesson): return _tfail("unknown lesson " + T.lesson)
			for k in T.get("cards", []):
				if not TD.CARDS.has(k): return _tfail("unknown card " + k)
			for dr in T.get("drills", []):
				if dr.text.length() > 48: return _tfail("drill text too long: " + dr.text)
				var ck: Dictionary = dr.check
				if ck.has("ev") and not kinds.has(ck.ev): return _tfail("unknown drill event " + ck.ev)
				if not (ck.has("ev") or ck.has("have") or ck.has("raid") or ck.has("arrived") or ck.has("spot")): return _tfail("drill with no check: " + dr.text)
			# what the player has or can build here must already have its card
			s.new_game("normal", {"mission": C.missions[i]})
			# owned from the start: its card is due in this mission. Only buildable: a card must exist (it opens when built).
			var types := {}
			for t in D.UN.keys() + D.BLD.keys():
				if s.avail(0, t) and s.mission.tech != null: types[t] = false
			for ev in C.missions[i].get("events", []):
				for t in ev.get("tech", []): types[t] = false
			for e in s.ents:
				if e.team == 0: types[e.type] = true
			for t in types:
				if TD.LESSON_ONLY.has(t): continue
				if not TD.CARDS.has(t): return _tfail(C.id + " " + str(i + 1) + ": " + t + " has no card")
				var hm: Array = TD.CARDS[t].home
				if types[t] and hm[0] == camp and int(hm[1]) > i: late.append(t + " in " + str(i + 1) + " (card in " + str(int(hm[1]) + 1) + ")")
				seen[t] = true
	if late.size(): return _tfail("cards come too late: " + ", ".join(late))
	print("tutorial: ", TD.CARDS.size(), " cards, ", seen.size(), " met in play, ", TD.LESSONS.size(), " lessons")
	print("tutorial tests ok")
	return true

func _gfail(msg: String) -> bool:
	print("GROUNDWORK TEST FAILED: ", msg); return false

## Faction redesign groundwork: per-faction rules (power, unit cap, producers) and living fields.
func groundwork_tests(s, h) -> bool:
	if not D.rule("ashen", "cap") or D.producer("ashen", "inf") != "muster" or D.producer("ashen", "veh") != "workshop":
		return _gfail("the Pact should have a unit cap and train from its Muster Hall and Workshop")
	if D.rule("vanguard", "power") or not D.rule("vanguard", "cap") or D.rule("vanguard", "place") != "signal" or D.producer("vanguard", "veh") != "lz":
		return _gfail("the Vanguard should run on Signal and Command and fly its vehicles in to a Landing Zone")
	if D.rule("choir", "power") or D.rule("choir", "cap") or D.rule("choir", "place") != "hum" or not D.rule("choir", "pods") or D.producer("choir", "veh") != "garden":
		return _gfail("the Choir should grow inside its Hum, with Pods and no cap, all from Gardens")
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	var hq = s.find_hq(0)
	# living fields: drain, death, regrowth up to what vitality allows
	var tiles: Array = []
	for i in D.MW * D.MH:
		if s.ore[i] >= 200: tiles.append(i)
	if tiles.size() < 2: return _gfail("no ore on the test map")
	var a: int = tiles[0]; var b: int = tiles[1]
	s.take_ore(a, s.ore[a], 100.0)
	if not s.field_dead(a) or s.ore[a] != 0: return _gfail("a full drain did not kill the tile")
	var full: int = s.ore0[b]
	s.take_ore(b, full / 2, 20.0)
	if s.vit[b] != 90: return _gfail("half a tile at drain 20 should leave 90 vitality, got %d" % s.vit[b])
	s.take_ore(b, 0, 20.0)
	s.time += 31.0
	for i in 200: s.field_t = 0.0; s.upd_field_life(0.05)
	print("living fields: dead tile ore ", s.ore[a], ", tired tile ", s.ore[b], "/", full, " vitality ", s.vit[b])
	if s.ore[a] != 0: return _gfail("a dead tile regrew")
	if s.ore[b] < int(full * 0.9) - 1 or s.ore[b] > full: return _gfail("tired tile did not regrow to its vitality cap")
	if s.vit[b] <= 90: return _gfail("vitality did not come back on a rested tile")
	# a harvester tires the field it works
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	hq = s.find_hq(0)
	var rf = s.place_near(0, "refinery", hq.tx, hq.ty + 4)
	for i in 1200: s.step(0.05)
	var tired := 0
	for i in D.MW * D.MH:
		if s.ore0[i] > 0 and s.vit[i] < 100: tired += 1
	print("harvester tired ", tired, " tiles")
	if rf == null or tired == 0: return _gfail("harvesting did not touch any field's vitality")
	return true

func _pfail(msg: String) -> bool:
	print("PACT TEST FAILED: ", msg); return false

## The Ashen Pact: its own buildings stand in for the shared ones, Furnaces burn aurite, Hearths house and muster,
## Brutes shrug off bullets, boars charge in packs, the Kettle Ram only hits buildings, wrecks revive or strip,
## and the Pact AI builds and fights with its own roster.
func pact_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	var hq = s.find_hq(0)
	if s.count(0, "rifle") != 3 or s.count(0, "militia") != 3: return _pfail("the Pact should start with Militia, counted as its rifles")
	if s.avail(0, "rifle") or s.avail(0, "barracks") or not s.avail(0, "militia") or not s.avail(0, "muster"): return _pfail("shared types should be swapped for the Pact's own")
	if s.avail(0, "wasp") or s.avail(1, "wasp"): return _pfail("the Wasp is retired")
	var m = s.add_building(0, "barracks", hq.tx + 4, hq.ty)
	if m.type != "muster": return _pfail("a Barracks order should raise a Muster Hall, got " + m.type)
	if s.req_of(0, ["barracks", "comms"]) != ["muster"]: return _pfail("requirements should map to Pact buildings, got " + str(s.req_of(0, ["barracks", "comms"])))
	# Furnace: burns aurite for power, cold without it; spending keeps its fuel aside
	var k = s.add_building(0, "kiln", hq.tx - 3, hq.ty)
	s.teams[0].credits = 0.0
	s.step(0.05)
	var cold_pw: int = s.teams[0].pmade
	if not k.cold: return _pfail("a Furnace with no aurite should go cold")
	s.teams[0].credits = 200.0
	s.step(0.05)
	if k.cold or s.teams[0].pmade != cold_pw + 100: return _pfail("a fed Furnace should make 100 power")
	s.teams[0].prod.inf.queue.append("militia")
	for i in 20: s.step(0.05)
	if s.teams[0].credits < s.fuel_reserve(0) - 2: return _pfail("training ate into the Furnace fuel: %d left" % int(s.teams[0].credits))
	s.teams[0].prod.inf.queue.clear(); s.teams[0].prod.inf.cur = ""
	# Hearth: +10 cap and one muster a match
	var c0: int = s.cap_max(0)
	s.add_building(0, "hearth", hq.tx - 3, hq.ty + 3)
	if s.cap_max(0) != c0 + 10: return _pfail("a Hearth should add 10 to the cap")
	var mil: int = s.count(0, "militia")
	if s.muster(0) != 3 or s.count(0, "militia") != mil + 3 or s.muster(0) != 0: return _pfail("a Hearth should muster 3 Militia, once")
	# Rivet Brute: 30% less from bullets
	var br = s.spawn_unit(0, "brute", hq.x + 200, hq.y)
	s.damage(br, 100, "bullet", null)
	if absf(br.hp - (200 - 70)) > 0.01: return _pfail("a Brute should take 70 from a 100 bullet hit, took %f" % (200 - br.hp))
	# Slag Boars: a pack of three; the first gore is a charge that knocks down
	var before: int = s.count(0, "boars")
	s.produce_done(s.teams[0], "boars")
	if s.count(0, "boars") != before + 3: return _pfail("Slag Boars should come as a pack of 3")
	var boar = s.ents.filter(func(e): return e.alive and e.type == "boars")[0]
	var vic = s.spawn_unit(1, "rifle", boar.x + 20, boar.y)
	vic.max_hp = 1000.0; vic.hp = 1000.0
	var hp0: float = vic.hp
	s.fire(boar, vic, boar.d)
	var hit: float = hp0 - vic.hp
	if absf(hit - 20 * D.MOD.gore.inf * 3) > 0.5 or (vic.alive and vic.stun <= 0): return _pfail("a boar charge should hit x3 and knock down, hit %f" % hit)
	vic.hp = vic.max_hp; vic.stun = 0.0
	s.fire(boar, vic, boar.d)
	if absf(vic.max_hp - vic.hp - 20 * D.MOD.gore.inf) > 0.5: return _pfail("a winded boar should hit normally")
	# Kettle Ram hits buildings only
	var kr = s.spawn_unit(0, "kettle", hq.x + 260, hq.y)
	if s.can_hit(kr.d, vic) or not s.can_hit(kr.d, hq): return _pfail("the Kettle Ram should hit buildings only")
	# Juggernaut: two shells a shot
	var jg = s.spawn_unit(0, "jugg", hq.x + 300, hq.y + 100)
	var np: int = s.proj.size()
	s.fire(jg, vic, jg.d)
	if s.proj.size() != np + 2: return _pfail("the Juggernaut should fire a salvo of 2")
	if s.cap_full(0, "jugg") == false and s.at_limit(0, "jugg") == false: return _pfail("only one Juggernaut at a time")
	# wrecks: a fresh one is revived, an old one is stripped
	var tk = s.spawn_unit(1, "tank", hq.x + 120, hq.y + 140)
	s.kill(tk)
	if s.wrecks.size() != 1: return _pfail("a destroyed tank should leave a wreck")
	var sc = s.spawn_unit(0, "scrapper", hq.x + 100, hq.y + 140)
	s.scrap_order([sc], s.wrecks[0])
	var tanks: int = s.count(0, "tank")
	for i in 20 * 16: s.step(0.05)
	if s.count(0, "tank") != tanks + 1 or s.wrecks.size() != 0: return _pfail("a Scrapper should revive a fresh wreck for its side")
	var tk2 = s.spawn_unit(1, "tank", hq.x + 120, hq.y + 180)
	s.kill(tk2)
	s.wrecks[0].intact = 0.2
	var cr: float = s.teams[0].credits
	s.scrap_order([sc], s.wrecks[0])
	for i in 20 * 12: s.step(0.05)
	var gain: float = s.teams[0].credits - cr
	print("pact: scrapper stripped a wreck for ", int(gain))
	if s.wrecks.size() != 0 or gain < D.UN.tank.cost * D.WRECK.strip - 60: return _pfail("a Scrapper should strip an old wreck for aurite")
	# water: a Slipway needs a shore, an Ironclad sails only on water and gets where it is sent
	var wt := []
	for i in s.MW * s.MH:
		if s.terr[i] == D.WATER: wt.append(i)
	if wt.size() < 20: return _pfail("the skirmish map should have a river")
	# sail between the two far ends of the stretch of river the first water tile belongs to (fords cut the river)
	var a: int = wt[wt.size() / 4]; var z: int = a
	var seen := {a: 0}; var q := [a]; var qi := 0
	while qi < q.size():
		var c: int = q[qi]; qi += 1
		if seen[c] > seen[z]: z = c
		for o in [1, -1, s.MW, -s.MW]:
			var n: int = c + o
			if n >= 0 and n < s.MW * s.MH and not seen.has(n) and s.terr[n] == D.WATER and abs(n % s.MW - c % s.MW) <= 1:
				seen[n] = seen[c] + 1; q.append(n)
	print("pact: river stretch of ", seen.size(), " tiles, sailing ", seen[z], " steps")
	var ax: int = a % s.MW; var ay: int = a / s.MW
	var dry := false
	for y in range(4, s.MH - 4):
		for x in range(4, s.MW - 4):
			if not s.water_beside(x, y, 2, 2) and s.walk(x, y) and s.walk(x + 1, y) and s.walk(x, y + 1) and s.walk(x + 1, y + 1):
				dry = true
				for v in s.vis.size(): s.vis[v] = 2
				if s.can_place(0, "slipway", x, y, false): return _pfail("a Slipway should need water beside it")
				break
		if dry: break
	var ic = s.spawn_unit(0, "ironclad", ax * D.T + 16, ay * D.T + 16)
	if s.terr[s.t_idx(ic)] != D.WATER: return _pfail("an Ironclad should be put on water")
	s.set_path(ic, z % s.MW, z / s.MW)
	if ic.path.is_empty(): return _pfail("no water path for the Ironclad")
	var d0: float = Vector2(ic.x - (z % s.MW) * D.T, ic.y - (z / s.MW) * D.T).length()
	var wet := true
	for i in 20 * 25:
		s.step(0.05)
		if s.terr[s.t_idx(ic)] != D.WATER: wet = false
	var d1: float = Vector2(ic.x - (z % s.MW) * D.T, ic.y - (z / s.MW) * D.T).length()
	print("pact: ironclad sailed ", int(d0 / D.T), " -> ", int(d1 / D.T), " tiles from its goal, always on water: ", wet)
	if not wet or d1 > d0 * 0.6: return _pfail("the Ironclad should sail along the river")
	# the Pact AI: builds its own base and army, and holds for ten minutes against the Vanguard
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 777})
	var c = {}   # every type the Pact AI had at some point (the enemy may have destroyed it since)
	for i in 20 * 60 * 10:
		s.step(0.05)
		if i % 20 == 0:
			s.ai_think(s.teams[0])
			for e in s.ents:
				if e.alive and e.team == 0: c[e.type] = maxi(c.get(e.type, 0), s.count(0, e.type))
		if s.over: break
	print("pact AI in 10 min, most of each at once: ", c)
	if s.find_hq(0) == null: print("note: the Pact AI lost its base inside 10 minutes this run (balance pass will look at it)")
	for t in ["kiln", "muster", "workshop", "smelter", "crawler"]:
		if not c.has(t): return _pfail("the Pact AI never built a " + t)
	if not (c.has("brute") or c.has("boars") or c.has("grenadier") or c.has("scorpion") or c.has("anvilf") or c.has("kettle")):
		return _pfail("the Pact AI fielded none of its own units")
	# with a river by its base, the Pact AI lays a Slipway and launches Ironclads
	var sd := 5
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": sd})
	for e in s.ents:
		if e.alive and e.team == 1 and e.kind == "u": e.alive = false   # a quiet enemy: this is about the shipyard
	var slips := 0; var ships := 0
	for i in 20 * 60 * 9:
		s.step(0.05)
		if i % 20 == 0:
			for v in s.vis.size(): s.vis[v] = 2
			s.teams[0].credits = maxf(s.teams[0].credits, 3000)
			s.ai_think(s.teams[0])
			slips = maxi(slips, s.count(0, "slipway")); ships = maxi(ships, s.count(0, "ironclad"))
		if s.over or ships > 0: break
	print("pact AI by a river (seed ", sd, "): slipways ", slips, ", ironclads ", ships)
	if slips == 0: return _pfail("the Pact AI by a river never laid a Slipway")
	print("pact tests ok")
	return true

func _vfail(msg: String) -> bool:
	print("VANGUARD TEST FAILED: ", msg); return false

## The Vanguard (high tech): Signal and Command, Deep Drills, dropship deliveries, Aegis shields, cloak, jump, rail, drones.
func vanguard_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 4242})
	s.teams[1].credits = 0; s.ai_t = 1e9
	for v in s.vis.size(): s.vis[v] = 2
	var tm: Dictionary = s.teams[0]
	var hq = s.find_hq(0)
	for e in s.ents:
		if e.team == 1 and e.kind == "u": e.alive = false
	# Signal: prefabs only land inside it; Masts carry it further and raise Command
	if s.uses_power(0) or s.low_power(0): return _vfail("the Vanguard should not use power")
	if s.cap_max(0) != 20: return _vfail("the Yard alone should give 20 Command, got %d" % s.cap_max(0))
	var spot = null; var far = null
	var free2 := func(x: int, y: int) -> bool:
		for yy in 2:
			for xx in 2:
				if not s.inb(x + xx, y + yy) or not s.walk(x + xx, y + yy) or s.ore[(y + yy) * s.MW + x + xx] > 0: return false
		return true
	for y in range(hq.ty - 20, hq.ty + 3):
		for x in range(hq.tx + 5, hq.tx + 24):
			if not free2.call(x, y): continue
			var ins: bool = s.in_signal(0, x + 1.0, y + 1.0)
			var dd: float = Vector2(x - hq.tx, y - hq.ty).length()
			if ins and spot == null and dd > 7: spot = Vector2i(x, y)
			if not ins and far == null and dd > 13 and free2.call(x + 2, y) and free2.call(x + 2, y + 3): far = Vector2i(x, y)
	if spot == null or far == null: return _vfail("no test spots inside and outside Signal")
	if not s.can_place(0, "barracks", spot.x, spot.y, false): return _vfail("a prefab should land inside Signal")
	if s.can_place(0, "barracks", far.x, far.y, false): return _vfail("a prefab landed outside Signal")
	var bk = s.add_building(0, "barracks", far.x, far.y)
	if not bk.dark: return _vfail("a building outside Signal should be dark")
	tm.credits = 5000.0; tm.prod.inf.queue.append("rifle")
	var n0: int = s.count(0, "rifle")
	for i in 200: s.step(0.05)
	if s.count(0, "rifle") != n0: return _vfail("a dark Barracks trained a Trooper")
	var ms = s.add_building(0, "sigmast", far.x + 2, far.y)
	if bk.dark or s.cap_max(0) != 30: return _vfail("a Signal Mast should light the Barracks and add 10 Command")
	for i in 200: s.step(0.05)
	if s.count(0, "rifle") != n0 + 1: return _vfail("the Barracks did not train once it was back in Signal")
	s.kill(ms)
	if not bk.dark or s.cap_max(0) != 20: return _vfail("losing the Mast should darken the Barracks again")
	ms = s.add_building(0, "sigmast", far.x + 2, far.y + 3)
	print("vanguard: Signal ok, Command ", s.cap_used(0), "/", s.cap_max(0))
	# Deep Drill: pumps a field straight into the bank and kills it
	var oi := -1; var bd := 1e9
	for i in s.MW * s.MH:
		if s.ore[i] > 0:
			var dd: float = Vector2(i % s.MW - hq.tx, i / s.MW - hq.ty).length()
			if dd < bd: bd = dd; oi = i
	if oi < 0: return _vfail("no ore on the test map")
	var ox: int = oi % s.MW; var oy: int = oi / s.MW
	s.add_building(0, "sigmast", ox - 2, oy)
	if not s.can_place(0, "drill", ox, oy, false): return _vfail("a Deep Drill should go on a field inside Signal")
	if s.can_place(0, "drill", hq.tx + 4, hq.ty + 4, false): return _vfail("a Deep Drill landed away from any field")
	var dr = s.add_building(0, "drill", ox, oy)
	var c0: float = tm.credits
	for i in 20 * 60: s.step(0.05)
	var dead := 0
	for i in s.MW * s.MH:
		if s.field_dead(i): dead += 1
	print("vanguard: Deep Drill pumped ", int(tm.credits - c0), " in a minute, ", dead, " tiles dead")
	if tm.credits - c0 < 1200 or tm.credits - c0 > 1800 or dead == 0: return _vfail("Deep Drill income or dead tiles")
	for i in s.MW * s.MH:
		if s.ore0[i] > 0 and Vector2(i % s.MW - ox - 1, i / s.MW - oy - 1).length() < 6: s.ore[i] = 0; s.vit[i] = 0
	for i in 60: s.step(0.05)
	if not dr.dry: return _vfail("a drill on an empty field should report dry")
	# deliveries: a dropship flies the order in to the Landing Zone; shot down, half the cost comes back
	var lz = s.place_near(0, "lz", hq.tx + 5, hq.ty - 5)
	if lz == null or lz.dark: return _vfail("no Landing Zone")
	tm.credits = 9000.0; tm.prod.veh.queue.append("tank")
	var ship = null
	for i in 20 * 40:
		s.step(0.05)
		for e in s.ents:
			if e.alive and e.type == "dropship": ship = e
		if ship != null: break
	if ship == null or ship.cargo != ["tank"] or s.count(0, "tank") != 0: return _vfail("no dropship left for the Landing Zone")
	if s.cap_used(0) < 3: return _vfail("cargo in flight should count toward Command")
	for i in 20 * 30:
		s.step(0.05)
		if s.count(0, "tank") > 0: break
	var tk = null
	for e in s.ents:
		if e.alive and e.type == "tank" and e.team == 0: tk = e
	if tk == null or Vector2(tk.x - lz.x, tk.y - lz.y).length() > 6 * D.T: return _vfail("the tank was not set down at the Landing Zone")
	for i in 20 * 20: s.step(0.05)
	if s.count(0, "dropship") != 0: return _vfail("the dropship did not leave the map")
	tm.prod.veh.queue.append("pk_strike")
	c0 = -1.0
	for i in 20 * 60:
		s.step(0.05)
		for e in s.ents:
			if e.alive and e.type == "dropship" and not e.leaving and c0 < 0:
				c0 = tm.credits; s.kill(e)
		if c0 >= 0: break
	if c0 < 0 or abs(tm.credits - c0 - D.UN.pk_strike.cost * 0.5) > 1 or s.count(0, "tank") != 1: return _vfail("a downed dropship should lose its cargo and refund half")
	tm.prod.veh.queue.append("pk_strike")
	for i in 20 * 60:
		s.step(0.05)
		if s.count(0, "tank") == 3 and s.count(0, "buggy") >= 2: break
	if s.count(0, "tank") != 3: return _vfail("the Strike Package did not land two tanks and a scout")
	print("vanguard: deliveries ok (tank, a downed dropship, a Strike Package)")
	# Aegis: the shield soaks the hit, arcs drain it twice as fast, and it comes back after a rest
	if tk.sh != 150.0: return _vfail("a Warden should carry a 150 Aegis shield")
	s.damage(tk, 60.0, "shell", null)
	if tk.hp != tk.max_hp or abs(tk.sh - 90.0) > 0.01: return _vfail("the shield did not soak a shell")
	s.damage(tk, 20.0, "arc", null)
	if abs(tk.sh - (90.0 - 20.0 * D.MOD.arc.heavy * 2.0)) > 0.01: return _vfail("arcs should drain a shield twice as fast")
	s.damage(tk, 200.0, "shell", null)
	if tk.sh != 0.0 or tk.hp >= tk.max_hp: return _vfail("a broken shield should let the rest through")
	for i in 20 * 5: s.step(0.05)
	if tk.sh != 0.0: return _vfail("the shield came back too soon")
	for i in 20 * 12: s.step(0.05)
	if tk.sh != 150.0: return _vfail("the shield did not come back after a rest")
	# Shield Dome: soaks hits on what stands under it
	var dm = s.place_near(0, "dome", hq.tx - 3, hq.ty - 4)
	var hp0: float = hq.hp; var hs0: float = hq.sh
	s.damage(hq, 100.0, "shell", null)
	if dm == null or dm.sh != 700.0 or hq.hp != hp0 or hq.sh != hs0: return _vfail("the Shield Dome did not soak a hit on the Yard")
	# Ranger: cloaked after standing still, sniffed out by a K9, seen again when it fires
	var rg = s.spawn_unit(0, "ranger", (hq.tx - 4) * D.T, (hq.ty - 3) * D.T)
	var en = s.spawn_unit(1, "militia", rg.x, rg.y); en.x = rg.x + 4 * D.T; en.y = rg.y; en.captive = true
	for i in 20 * 4: s.step(0.05)
	rg.target = null
	en.captive = false
	if not rg.cloak or not s.hid(rg) or s.find_target(en, 9 * D.T) == rg: return _vfail("a Ranger standing still should be cloaked")
	var dog = s.spawn_unit(1, "k9", rg.x, rg.y); dog.x = rg.x + 3 * D.T; dog.y = rg.y + D.T; dog.stun = 99.0
	s.upd_sense()
	if s.hid(rg): return _vfail("a K9 should sniff out a cloaked Ranger")
	dog.alive = false; en.alive = false
	# Jump Trooper: jumps on a long move
	var jt = s.spawn_unit(0, "jump", (hq.tx + 2) * D.T, (hq.ty + 6) * D.T)
	s.group_move([jt], jt.x + 12 * D.T, jt.y, "move")
	var hopped := false
	for i in 20 * 3:
		s.step(0.05)
		if jt.hop != null: hopped = true
	if not hopped: return _vfail("the Jump Trooper never jumped")
	# Railtank: the slug goes through everything in its line
	var rt = s.spawn_unit(0, "railtank", (hq.tx - 4) * D.T, (hq.ty + 6) * D.T)
	var e1 = s.spawn_unit(1, "militia", rt.x, rt.y); var e2 = s.spawn_unit(1, "militia", rt.x, rt.y)
	e1.x = rt.x + 3 * D.T; e1.y = rt.y; e2.x = rt.x + 5 * D.T; e2.y = rt.y; e1.stun = 99.0; e2.stun = 99.0
	e1.max_hp = 999; e1.hp = 999; e2.max_hp = 999; e2.hp = 999
	s.fire(rt, e1, rt.d)
	if e1.hp >= 999 or e2.hp >= 999: return _vfail("a rail slug should hit everything in its line")
	# Spotter Drone: what it sees takes a quarter more
	var sp = s.spawn_unit(0, "spotter", e1.x + D.T, e1.y)
	s.upd_sense()
	var h1: float = e2.hp
	s.damage(e2, 40.0, "bullet", null)
	if abs((h1 - e2.hp) - 40.0 * 1.25) > 0.01: return _vfail("a spotted target should take 25% more")
	e1.alive = false; e2.alive = false; sp.alive = false
	# recovery: hold a lost vehicle's beacon and 40% of its cost comes back
	var lost = s.spawn_unit(0, "tank", (hq.tx + 3) * D.T, (hq.ty + 7) * D.T)
	s.kill(lost)
	var tr = s.spawn_unit(0, "rifle", lost.x + 8, lost.y)
	c0 = tm.credits
	for i in 20 * 7: s.step(0.05)
	if abs(tm.credits - c0 - D.UN.tank.cost * 0.4) > 1: return _vfail("holding a beacon should recover 40%% of a Warden, got %d" % int(tm.credits - c0))
	# Hydrofoil: flown in and set down on the river
	if not s.avail(0, "hydrofoil"): return _vfail("no Hydrofoil")
	s.add_building(0, "uplink", lz.tx, lz.ty - 3)
	tm.credits = 9000.0; tm.prod.veh.queue.append("hydrofoil")
	var hy = null
	for i in 20 * 90:
		s.step(0.05)
		for e in s.ents:
			if e.alive and e.type == "hydrofoil": hy = e
		if hy != null: break
	if hy == null or s.terr[s.t_idx(hy)] != D.WATER: return _vfail("the Hydrofoil was not set down on water")
	print("vanguard: shields, dome, cloak, jump, rail, spotter, recovery, hydrofoil ok")
	# the Vanguard AI: Masts, drills, a Landing Zone and an army flown in
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 777})
	var c = {}
	for i in 20 * 60 * 10:
		s.step(0.05)
		if i % 20 == 0:
			s.ai_think(s.teams[0])
			for e in s.ents:
				if e.alive and e.team == 0: c[e.type] = maxi(c.get(e.type, 0), s.count(0, e.type))
		if s.over: break
	print("vanguard AI in 10 min, most of each at once: ", c, " earned ", int(s.teams[0].earned))
	for t in ["sigmast", "drill", "barracks", "lz", "rifle"]:
		if not c.has(t): return _vfail("the Vanguard AI never had a " + t)
	if not (c.has("tank") or c.has("buggy") or c.has("railtank")): return _vfail("the Vanguard AI flew in no vehicles")
	if c.has("power") or c.has("refinery") or c.has("harv") or c.has("factory"): return _vfail("the Vanguard AI built something from the old rules")
	print("vanguard tests ok")
	return true

## Premium look (scripts/gfx.gd): every level builds the same models with the same named parts and a baked crease
## shadow in UV that stays in range; High rounds more parts than Low (more vertices). The removed Classic level (0)
## and anything else out of range load as High, and the menu cycle never reaches it.
func gfx_tests() -> bool:
	var GFX = load("res://scripts/gfx.gd")
	var keep: int = GFX.level
	var fog := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_L8))
	var rb: Array = Models.bevel_box(Vector3(.1, .1, .1))
	if rb.size() != 44:
		print("GFX TEST FAILED: a rounded box has ", rb.size(), " triangles, not 44"); return false
	if GFX._valid(0) != GFX.HIGH or GFX._valid(7) != GFX.HIGH or GFX._valid(GFX.LOW) != GFX.LOW:
		print("GFX TEST FAILED: a saved Classic or unknown level does not load as High"); return false
	var seen := {}; var l: int = GFX.HIGH
	for i in 6:
		l = GFX.next_level(l); seen[l] = true
	if seen.keys().size() != 3 or seen.has(0):
		print("GFX TEST FAILED: the menu cycle is not High, Medium, Low (", seen.keys(), ")"); return false
	var counts := {}
	for lvl in [1, 2, 3]:
		GFX.level = lvl
		Models.init_materials(fog)
		for m in [["b", "hq", "vanguard"], ["u", "tank", "vanguard"], ["b", "hq", "ashen"], ["u", "tank", "ashen"], ["b", "hq", "choir"], ["u", "rifle", "choir"]]:
			var n: Node3D = Models.get_model(m[0], m[1], 0, m[2])
			var nv := 0
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
				nv += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var uv = arr[Mesh.ARRAY_TEX_UV]
				if uv == null or (uv as PackedVector2Array).size() != (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
					print("GFX TEST FAILED: ", m, " at level ", lvl, " has no crease shadow UVs"); GFX.level = keep; Models.init_materials(fog); return false
				for v in uv:
					if v.x < 0.0 or v.x > 0.5 or v.y < 0.0 or v.y > 0.2:
						print("GFX TEST FAILED: ", m, " UV out of range ", v); GFX.level = keep; Models.init_materials(fog); return false
			var names := n.find_children("*", "Node3D", true, false).map(func(c): return String(c.name)).filter(func(x): return x != "m")
			names.sort()
			var k: String = str(m)
			if lvl == 1: counts[k] = [nv, names]
			elif names != counts[k][1]:
				print("GFX TEST FAILED: ", m, " parts differ from Low at level ", lvl); GFX.level = keep; Models.init_materials(fog); return false
			elif lvl == 3 and nv <= counts[k][0]:
				print("GFX TEST FAILED: ", m, " is not rounder at High than at Low (", nv, " vs ", counts[k][0], " vertices)"); GFX.level = keep; Models.init_materials(fog); return false
			if lvl == 3: print("gfx ", m, " vertices low ", counts[k][0], " high ", nv)
	GFX.level = keep
	Models.init_materials(fog)
	print("GFX TESTS OK")
	return true

func _qfail(msg: String) -> bool:
	print("SQUAD TEST FAILED: ", msg); return false

## Squads (scripts/squads.gd): forming on an order, split, merge, the five-squad limit, deaths, NEW and JOIN.
func squad_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 77})
	var q := Squads.new()
	var mk := func(n: int) -> Array:
		var a := []
		for i in n: a.append(s.spawn_unit(0, "rifle", 300 + i * 8, 300))
		return a
	var a: Array = mk.call(6); var b: Array = mk.call(4)
	if q.formed(s, [a[0]]) != 0: return _qfail("one unit formed a squad")
	if q.formed(s, a) != 1 or q.formed(s, b) != 2: return _qfail("the first two orders should form squads 1 and 2")
	if q.formed(s, a) != 1 or q.list.size() != 2: return _qfail("ordering squad 1 again changed the squads")
	if q.fresh(s).any(func(e): return a.has(e) or b.has(e)): return _qfail("squad members are listed as new")
	# split three off squad 1: they become squad 3, squad 1 keeps three
	if q.formed(s, a.slice(0, 3)) != 3 or q.members(s, 1).size() != 3: return _qfail("splitting three off squad 1 failed")
	# merge squads 1 and 2: the lowest number takes everyone
	if q.formed(s, a.slice(3) + b) != 1 or q.find(2) != null or q.members(s, 1).size() != 7: return _qfail("merging squads 1 and 2 failed")
	# a split that leaves one unit behind breaks that squad up
	if q.formed(s, a.slice(1, 3)) != 2 or q.find(3) != null or q.of(a[0]) != 0: return _qfail("a squad cut down to one unit should break up")
	# deaths shrink a squad; a lone survivor keeps its number, nobody left frees it
	q.reset(); q.formed(s, a.slice(0, 2)); q.formed(s, a.slice(2, 4))
	s.kill(a[0])
	for i in 5: s.step(0.05)
	q.prune(s)
	if q.members(s, 1).size() != 1: return _qfail("a lone survivor should keep squad 1")
	q.formed(s, b.slice(0, 2))
	if q.find(1) == null: return _qfail("an unrelated order broke up a lone survivor's squad")
	s.kill(a[1])
	for i in 5: s.step(0.05)
	q.prune(s)
	if q.find(1) != null or q.find(2) == null: return _qfail("an emptied squad should go away and the others keep their numbers")
	# five squads at most
	q.reset()
	var more: Array = mk.call(12)
	for i in 5: q.formed(s, more.slice(i * 2, i * 2 + 2))
	if q.list.size() != 5 or q.formed(s, more.slice(10, 12)) != -1: return _qfail("a sixth squad should be refused")
	if q.formed(s, more.slice(0, 4)) != 1 or q.list.size() != 4: return _qfail("merging two squads should free a number")
	# NEW and JOIN
	var fr: Array = q.fresh(s)
	if not fr.has(more[10]) or fr.has(more[0]): return _qfail("NEW should hold exactly the units in no squad")
	if q.join(s, 1, [more[10], more[11]]) != 2 or q.of(more[11]) != 1: return _qfail("JOIN did not add the new units to the squad")
	if q.matching(s, q.members(s, 1)) != 1: return _qfail("matching does not find squad 1")
	var st: Dictionary = q.status(s, 1)
	if st.n != 6 or st.hp <= 0.9 or st.name == "": return _qfail("bad status for squad 1: " + str(st))
	print("squads ok")
	return true

func _ofail(msg: String) -> bool:
	print("ORDER TEST FAILED: ", msg); return false

## Unit orders from the side panel: Hold ground (fights only what is in reach), Hold fire, JUMP and the Scrapper's strip.
func order_tests(s, h) -> bool:
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 91})
	for e in s.ents:
		if e.team == 1: e.alive = false
	s.ents = s.ents.filter(func(e): return e.alive)
	var x := 20.0 * D.T + 16; var y := 30.0 * D.T + 16
	# an enemy in sight but out of reach: a free rifle goes for it, a holding one stays put
	var free = s.spawn_unit(0, "rifle", x, y); var held = s.spawn_unit(0, "rifle", x, y + 0.6 * D.T); var quiet = s.spawn_unit(0, "rifle", x, y - 0.6 * D.T)
	held.hold = true; quiet.nofire = true
	var foe = s.spawn_unit(1, "militia", x + (free.d.range + free.d.sight) / 2.0 * D.T, y)
	foe.post = true; foe.d = foe.d.duplicate(); foe.d.dmg = 0; foe.d.spd = 0.0
	var h0 := Vector2(held.x, held.y)
	for i in 60: s.step(0.05)
	print("orders: free moved ", snappedf(Vector2(free.x, free.y).distance_to(Vector2(x, y)) / D.T, 0.1), " held moved ", snappedf(Vector2(held.x, held.y).distance_to(h0) / D.T, 0.1), " quiet target ", quiet.target != null)
	if free.target != foe: return _ofail("a free rifle did not take the enemy in sight")
	if Vector2(held.x, held.y).distance_to(h0) > D.T * 0.6: return _ofail("a rifle holding ground chased an enemy out of reach")
	if quiet.target != null: return _ofail("a rifle holding fire picked a target")
	# JUMP: a Jump Trooper leaps toward the spot at once, then must wait for its jets
	var j = s.spawn_unit(0, "jump", x, y + 8 * D.T)
	var j0 := Vector2(j.x, j.y)
	if not s.jump_to(j, x + 10 * D.T, y + 8 * D.T): return _ofail("jump_to refused a ready Jump Trooper")
	for i in 20: s.step(0.05)
	if Vector2(j.x, j.y).distance_to(j0) < 3 * D.T: return _ofail("the Jump Trooper did not leap")
	if s.jump_to(j, x, y + 8 * D.T): return _ofail("a second jump went off during the cooldown")
	# Strip: a Scrapper set to strip takes a fresh wreck apart for aurite instead of reviving it
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 92})
	var sc = s.spawn_unit(0, "scrapper", x, y)
	sc.strip = true
	var tank = s.spawn_unit(1, "tank", x + D.T, y)
	s.kill(tank)
	if s.wrecks.is_empty(): return _ofail("a destroyed tank left no wreck")
	var w: Dictionary = s.wrecks[-1]
	if w.intact < D.WRECK.revive: return _ofail("the fresh wreck could not be revived anyway")
	var c0: float = s.teams[0].credits; var n0: int = s.count(0, w.type)
	s.scrap_order([sc], w)
	for i in 20 * 30: s.step(0.05)
	print("orders: strip credits +", int(s.teams[0].credits - c0), " ", w.type, " ", n0, " -> ", s.count(0, w.type), " wreck left ", s.wrecks.has(w))
	if s.wrecks.has(w) or s.count(0, w.type) > n0: return _ofail("a stripping Scrapper revived the wreck or left it")
	# LOOP on the Barracks: a finished Trooper goes back into the line; off: the line empties
	s.new_game("normal", {"fac": "vanguard", "enemy": "ashen", "seed": 93})
	var tm: Dictionary = s.teams[0]
	if s.count(0, "barracks") == 0: s.add_building(0, "barracks", 12, 44)
	tm.credits = 5000; tm.loop = {"barracks": true}
	tm.prod.inf.queue = ["rifle"]
	var r0: int = s.count(0, "rifle")
	for i in 20 * 12: s.step(0.05)
	var made: int = s.count(0, "rifle") - r0
	print("orders: loop made ", made, " queue ", tm.prod.inf.queue, " cur ", tm.prod.inf.cur)
	if made < 2 or (tm.prod.inf.cur == "" and tm.prod.inf.queue.is_empty()): return _ofail("LOOP did not keep the Barracks training")
	tm.loop = {}
	for i in 20 * 12: s.step(0.05)
	if tm.prod.inf.cur != "" or tm.prod.inf.queue.size(): return _ofail("the line kept going after LOOP was turned off")
	# building on your own units: they no longer block placement and step out of the footprint; enemies still block
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 94})
	var hq: Ent = s.find_hq(0)
	var spot := Vector2i(-1, -1)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if spot.x < 0 and s.can_place(0, "hearth", hq.tx + dx, hq.ty + dy, false): spot = Vector2i(hq.tx + dx, hq.ty + dy)
	if spot.x < 0: return _ofail("no spot for a Hearth near the Yard")
	var mine = s.spawn_unit(0, "militia", (spot.x + 1) * D.T, (spot.y + 1) * D.T)
	if not s.can_place(0, "hearth", spot.x, spot.y, false): return _ofail("an own unit still blocks placement")
	var hb = s.add_building(0, "hearth", spot.x, spot.y)
	s.clear_footprint(hb)
	for i in 40: s.step(0.05)
	var mx := int(mine.x / D.T); var my := int(mine.y / D.T)
	print("orders: unit under a new Hearth walked to ", Vector2i(mx, my), " footprint ", Rect2i(spot.x, spot.y, hb.w, hb.h))
	if Rect2i(spot.x, spot.y, hb.w, hb.h).has_point(Vector2i(mx, my)): return _ofail("the unit stayed inside the new building")
	var spot2 := Vector2i(-1, -1)
	for dy in range(-7, 8):
		for dx in range(-7, 8):
			if spot2.x < 0 and s.can_place(0, "hearth", hq.tx + dx, hq.ty + dy, false): spot2 = Vector2i(hq.tx + dx, hq.ty + dy)
	var foe2 = s.spawn_unit(1, "rifle", (spot2.x + 1) * D.T, (spot2.y + 1) * D.T)
	if s.can_place(0, "hearth", spot2.x, spot2.y, false): return _ofail("an enemy unit no longer blocks placement")
	print("ORDER TESTS OK")
	return true

# ---------------- announcer (voice alerts, scripts/voice.gd) ----------------
func _vofail(msg: String) -> bool:
	print("VOICE TEST FAILED: ", msg)
	return false

func voice_tests(s, h) -> bool:
	var A = preload("res://scripts/voice.gd").new()
	# every event has a clip for each faction that has a line for it, and every clip has an event
	for fac in ["vanguard", "ashen", "choir"]:
		var n := 0
		for k in A.EV:
			if ResourceLoader.exists("res://voice/%s/%s.ogg" % [fac, k]): n += 1
		if n < 18: return _vofail("only %d clips for %s" % [n, fac])
	for k in ["base_attack", "units_attack", "no_aurite", "built", "unit_ready", "won", "lost"]:
		for fac in ["vanguard", "ashen", "choir"]:
			if not ResourceLoader.exists("res://voice/%s/%s.ogg" % [fac, k]): return _vofail("missing " + fac + "/" + k)
	# a line plays, then the same line is held back by its cooldown
	if A.request("built", 0.0) != "play": return _vofail("first line should play")
	A.started(0.0, 1.5)
	if A.request("built", 1.0) != "": return _vofail("cooldown ignored")
	# priority 3 while talking or just after: dropped
	if A.request("unit_ready", 1.0) != "": return _vofail("priority 3 should drop while talking")
	if A.request("unit_ready", 3.0) != "": return _vofail("priority 3 should drop in the quiet gap")
	# priority 2 while talking waits, and plays once the gap is over
	if A.request("no_aurite", 1.0) != "wait": return _vofail("priority 2 should wait")
	if A.poll(2.0) != "": return _vofail("waiting line started too early")
	if A.request("cap", 1.2) != "": return _vofail("only one line may wait")
	# priority 1 replaces a waiting priority 2
	if A.request("bld_lost", 1.2) != "wait": return _vofail("priority 1 should take the waiting slot")
	if A.poll(1.6) != "bld_lost": return _vofail("priority 1 should start right after the current line")
	A.started(1.6, 1.0)
	# priority 1 skips the quiet gap
	A.reset(); A.started(0.0, 1.0)
	if A.request("base_attack", 1.5, Vector2(100, 100)) != "play": return _vofail("priority 1 should skip the gap")
	A.started(1.5, 1.5)
	# a long siege in one spot stays quiet past the cooldown; a new spot gets its warning
	for t in [10.0, 20.0, 29.0, 40.0, 55.0]:
		if A.request("base_attack", t, Vector2(140, 120)) != "": return _vofail("same fight warned again at %s" % t)
	if A.request("base_attack", 60.0, Vector2(2000, 1800)) != "play": return _vofail("attack on a new spot should warn")
	# a waiting line goes stale
	A.reset(); A.started(0.0, 3.0)
	A.request("wave", 1.0)
	if A.poll(9.0) != "": return _vofail("stale line still played")
	# once-per-match lines
	A.reset()
	if A.request("won", 0.0) != "play" or A.request("won", 100.0) != "": return _vofail("won should play once")
	# the simulation asks for lines through the host
	h.log.clear()
	s.new_game("normal", {"fac": "ashen", "enemy": "vanguard", "seed": 77})
	var hq = s.find_hq(0)
	if hq == null: return _vofail("no Yard to hit")
	s.last_alert = -100.0
	s.damage(hq, 1.0, "bullet", null)
	if not h.log.has("SAY base_attack"): return _vofail("hitting the base did not ask for base_attack: " + str(h.log.slice(-3)))
	print("voice tests ok")
	return true
