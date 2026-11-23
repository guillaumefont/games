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
			if kinds.has(k):
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


func _initialize() -> void:
	print("Vantage foes test")
	roster()
	await each_kind()
	await extras()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
