extends SceneTree
## The campaign's own foes (`Foes`): one new kind a level, met first thing and announced, kept in
## later levels; each kind comes in from off-screen, shows, attacks, flashes when hit and goes down.
##   godot --headless --path . --script tests/foes_test.gd

const SAVE := "user://test_foes_save.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func roster() -> void:
	print("one new kind a level, kept after")
	check(Foes.INTRO.size() == Campaign.count(), "a new kind for each of the %d levels" % Campaign.count())
	var seen := {}
	for k: String in Foes.INTRO:
		check(not seen.has(k) and Rules.FOES.has(k) and Foes.NAMES.has(k) and Foes.mesh(k) != null, "%s: stats, a name and a model" % k)
		seen[k] = true
		check((k in Rules.RAMMABLE) != Foes.is_ground(k), "%s: %s" % [k, "on the ground, passes under the ship" if Foes.is_ground(k) else "in the air, can be rammed"])
	for lv in Campaign.count():
		var ws: Array = Campaign.waves(lv)
		var kinds := {}
		for w: Dictionary in ws:
			kinds[w.kind] = true
		var first: Dictionary = ws[0]
		var d := Campaign.debut(lv)
		if lv == Campaign.PER_WORLD - 1:
			check(kinds.has(d), "%s (hand-made) has its new kind, %s" % [Campaign.code(lv), d])
		else:
			check(first.kind == d, "%s opens on its new kind, %s" % [Campaign.code(lv), d])
		var met := 0
		for k in range(lv):
			if kinds.has(Foes.INTRO[k]):
				met += 1
		var old := 0
		for k: String in ["dart", "swing", "turret", "heavy"]:
			if kinds.has(k) or k == "turret" and Towers.TYPES.any(func(t: String) -> bool: return kinds.has(t)):
				old += 1
		check(old >= 1, "%s keeps the first foes (%d of 4 kinds)" % [Campaign.code(lv), old])
		if lv >= 3 and lv != Campaign.PER_WORLD - 1:
			check(met >= 1, "%s brings back kinds met before (%d)" % [Campaign.code(lv), met])
		var mix := Campaign.mix_of(lv)
		check(mix.has(d) and not mix.has(Foes.INTRO[mini(lv + 1, Foes.INTRO.size() - 1)]) or lv == Campaign.count() - 1,
			"%s: nothing from later levels yet" % Campaign.code(lv))


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 5
	return g


func each_kind() -> void:
	print("each kind: in from off-screen, on screen, attacks, flashes, goes down")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	for lv in Foes.INTRO.size():
		var kind: String = Foes.INTRO[lv]
		g.launch(lv)
		g.step(DT)
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()   # no other waves
		var rng := RandomNumberGenerator.new()
		rng.seed = lv
		var w := Campaign.new_wave(kind, rng, 1.0)
		var before := g.foes.size()
		var mine: Array[Game.Obj] = []
		var inside := 0
		var shown := 0.0
		var fired := 0
		var closest := 1e9
		var t := 0.0
		var next := 0
		while t < 14.0:
			while next < int(w.n) and t >= next * float(w.gap):
				g.spawn_vert(kind, float(w.x), next, int(w.n), w.get("from", "top"))
				var f: Game.Obj = g.foes[g.foes.size() - 1]
				f.hp = 1e6   # the autofire would bring it down: this is about its flight
				if g.on_screen(f):
					inside += 1
				mine.append(f)
				next += 1
			var nb := g.bullets.size()
			g.hp = 5
			g.inv = 1.0   # no rams: this watches the foe
			g.prel.x = sin(t * 0.7) * 3.0
			g.step(DT)
			t += DT
			fired += maxi(0, g.bullets.size() - nb)
			var any := false
			for f in mine:
				if f in g.foes and not f.dead:
					any = true
					closest = minf(closest, g.flat_dist(g.seen(f.pos), g.ppos))
					if g.on_screen(f):
						shown += DT
			if not any and next >= int(w.n):
				break
		check(g.foes.size() >= before and inside == 0, "%s: comes in from off-screen" % kind)
		check(shown >= 1.5, "%s: shows on screen (%.1f s)" % [kind, shown])
		if kind == "seeker":
			check(closest < 2.5, "%s: flies at the ship (%.1f m)" % [kind, closest])
		else:
			check(fired > 0, "%s: fires (%d shots)" % [kind, fired])
		# hit flash on the body and its moving parts, then down
		g.clear_all()
		g.spawn_vert(kind, 0.0, 0, 1)
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.under = false
		g.damage(f, 0.5)
		g.update_objs(0.0)
		var mi := f.node as MeshInstance3D
		var parts_flash := true
		for c in mi.get_children():
			if c.has_meta("part"):
				parts_flash = parts_flash and (c as MeshInstance3D).material_overlay != null
		check(mi.material_overlay != null and parts_flash, "%s: flashes when hit" % kind)
		var kills: int = g.run.kills
		g.damage(f, 1e6)
		check(f.dead and g.run.kills == kills + 1, "%s: goes down" % kind)
	g.queue_free()
	await process_frame


## Guillaume (2026-11-24): foes that fly in and hold stopped "much too far from the ship" near the
## top of tall screens. They hold a few metres above the screen's centre, and come in from a side
## when the way down from the top edge is too long.
func holds() -> void:
	print("holders stop near the screen's centre, from a side on tall screens")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	g.launch(0)
	g.step(DT)
	for tall in [false, true]:
		for kind: String in ["rotor", "scarab", "lancer", "prism", "heavy", "gunship"]:
			g.clear_all()
			g.queue.clear()
			g.wave_i = g.waves.size()
			g.update_view()
			if tall:
				# a 9:20 phone: the top edge far above the ship
				g.view_top = -29.0
				g.view_hw_top = 12.6
			var mid := g.view_mid
			g.spawn_vert(kind, 2.0, 0, 2, "top")
			var f: Game.Obj = g.foes[g.foes.size() - 1]
			f.hp = 1e6
			var start := f.pos - Vector3(0, 0, g.frame_z)
			var from_side := absf(start.x) > g.view_hw(start.z) + 1.0
			if tall:
				check(from_side or kind == "heavy" and absf(start.x) > 9.0, "%s: in from a side on a tall screen (x %.1f)" % [kind, start.x])
			else:
				check(not g.side_entry(f.goal.z) or from_side, "%s: from the top only when the way down is short" % kind)
			var t := 0.0
			var near := 1e9
			while t < 2.6:
				g.hp = 5
				g.inv = 1.0
				g.step(DT)
				t += DT
				if tall:
					g.view_top = -29.0
					g.view_hw_top = 12.6
			var z := f.pos.z - g.frame_z
			near = z - mid
			check(near > -10.0 and near < 4.0 and absf(f.pos.x) < 8.0,
				"%s: holds near the screen's centre (%.1f m off it, ship %.1f m below)" % [kind, near, g.prel.y - z])
	g.queue_free()
	await process_frame


func extras() -> void:
	print("announced, shells burst, borers hide")
	var g := make_game()
	await process_frame
	g.s.open = 5
	g.launch(4)
	for i in int(4.0 / DT):
		g.hp = 5
		g.step(DT)
		if g.banner == "NEW FOE":
			break
	check(g.banner == "NEW FOE" and g.sub_banner == Foes.NAMES[Campaign.debut(4)], "the level's new kind is announced (%s)" % g.sub_banner)
	g.clear_all()
	var b := g.shell(Vector3(0, Rules.PY, g.frame_z - 8.0), Vector3(0, Rules.PY, g.frame_z - 2.0), 8.0, 7)
	var n := 0
	for i in int(2.0 / DT):
		g.hp = 5
		g.step(DT)
		if b.dead:
			n = g.bullets.size()
			break
	check(b.dead and n == 7, "a flak shell bursts into a ring of 7 (%d)" % n)
	g.clear_all()
	g.spawn_vert("borer", 0.0, 0, 1)
	var f: Game.Obj = g.foes[g.foes.size() - 1]
	var s := g.new_shot(g.seen(f.pos), Vector3.ZERO, 1.0)
	g.collide(DT)
	check(f.under and not s.dead and is_equal_approx(f.hp, f.max_hp * float(g.world.tough)), "a borer under the sand can't be hit")
	g.queue_free()
	await process_frame


## Every type of gun tower in every world: on its world's footing (a building in the city), its gun
## turning on top, firing, flashing when hit; the howitzer's shell is big.
func towers() -> void:
	print("gun towers, dressed for each world")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	var all := {}
	for w in Campaign.WORLDS.size():
		var lv := w * Campaign.PER_WORLD
		for t: String in Towers.BY_WORLD[w]:
			all[t] = true
		check(Towers.BY_WORLD[w].size() >= mini(2 + w, 4), "%s fields %d types of tower" % [Campaign.WORLDS[w].name, Towers.BY_WORLD[w].size()])
		var seen_types := {}
		for k in range(lv, lv + Campaign.PER_WORLD):
			for wave: Dictionary in Campaign.waves(k):
				if Towers.is_tower(wave.kind):
					seen_types[wave.kind] = true
		check(seen_types.size() >= 2, "%s's levels bring %d types of tower" % [Campaign.WORLDS[w].name, seen_types.size()])
		for t: String in Towers.TYPES:
			g.launch(lv)
			g.step(DT)
			g.clear_all()
			g.queue.clear()
			g.wave_i = g.waves.size()
			g.spawn_vert(t, 1.0, 0, 1)
			var f: Game.Obj = g.foes[g.foes.size() - 1]
			var theme: String = Campaign.WORLDS[w].theme
			var gy := g.ground_y(f.pos.x, f.pos.z)
			check(f.ground and f.node.mesh == Towers.base(theme) and f.node.has_node("top") and is_equal_approx(f.pos.y, gy + Towers.height(theme)),
				"%s: a %s on its world's footing, its gun %.1f m up" % [theme, t, Towers.height(theme)])
			f.hp = 1e6
			var fired := 0
			var big := false
			for i in int(9.0 / DT):
				var nb := g.bullets.size()
				g.hp = 5
				g.step(DT)
				fired += maxi(0, g.bullets.size() - nb)
				for b in g.bullets:
					big = big or b.size > 1.5
				if fired > 0 and (t != "howitzer" or big):
					break
			check(fired > 0, "%s: the %s fires" % [theme, t])
			if t == "howitzer":
				check(big, "%s: the howitzer's shell is big" % theme)
			f.hit = -1.0
			g.damage(f, 0.5)
			g.update_objs(0.0)
			var top := f.node.get_node("top") as MeshInstance3D
			check(f.node.material_overlay != null and top.material_overlay != null, "%s: the %s flashes, gun and all" % [theme, t])
	check(all.size() == Towers.TYPES.size(), "every type of tower is fielded somewhere")
	check(Towers.height("city") + 1.6 < Rules.PY, "a tower on a building stays under the flight altitude")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage foes test")
	roster()
	await towers()
	await each_kind()
	await holds()
	await extras()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
