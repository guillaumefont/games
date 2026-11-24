extends SceneTree
## The campaign: worlds and levels, their waves, progress and unlocks in the save, the level
## select in the hangar, the progress reset, each world's look, and full runs of a level, and every mid-boss flown down.
##   godot --headless --path . --script tests/campaign_test.gd

const SAVE := "user://test_campaign.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func data() -> void:
	print("worlds and levels")
	check(Campaign.WORLDS.size() >= 5 and Campaign.count() == Campaign.WORLDS.size() * 3, "five worlds of three levels")
	var themes := {}
	var names := {}
	for w: Dictionary in Campaign.WORLDS:
		themes[w.theme] = true
		check(Models.THEMES.has(w.theme), "%s has a theme (%s)" % [w.name, w.theme])
		for n: String in w.levels:
			names[n] = true
	check(themes.size() == Campaign.WORLDS.size(), "each world looks different")
	check(names.size() == Campaign.count(), "every level has its own name")
	check(Campaign.code(0) == "1-1" and Campaign.code(5) == "2-3", "level codes")
	for i in Campaign.WORLDS.size() - 1:
		var a: Dictionary = Campaign.WORLDS[i]
		var b: Dictionary = Campaign.WORLDS[i + 1]
		check(b.tough > a.tough and b.fire >= a.fire and b.scrap > a.scrap, "%s is tougher and richer than %s" % [b.name, a.name])
	for lv in Campaign.count():
		var ws := Campaign.waves(lv)
		var sorted := true
		var bosses := 0
		var fortresses := 0
		for k in ws.size():
			if k > 0 and ws[k].t < ws[k - 1].t:
				sorted = false
			if ws[k].kind == "boss":
				bosses += 1
			if ws[k].kind == "fortress":
				fortresses += 1
		var last: String = ws[-1].kind
		var boss_first := false
		for k in ws.size():
			if ws[k].kind == "boss":
				boss_first = k < ws.size() - 1 and ws.slice(k).any(func(w: Dictionary) -> bool: return w.kind == "fortress")
		check(sorted and bosses == 1 and fortresses == 1 and last == "fortress" and boss_first and ws.size() > 6 and Campaign.foes_in(lv) > 30,
			"%s %s: %d waves, in order, a mid-boss (%s) then the fortress" % [Campaign.code(lv), Campaign.level_name(lv), ws.size(), Campaign.midboss(lv).name])
	var used := {}
	for w in Campaign.WORLDS.size():
		var here := {}
		for k in Campaign.PER_WORLD:
			here[Campaign.midboss_of(w * Campaign.PER_WORLD + k)] = true
			used[Campaign.midboss_of(w * Campaign.PER_WORLD + k)] = true
		check(here.size() == Campaign.PER_WORLD, "%s: three levels, three different mid-bosses" % Campaign.WORLDS[w].name)
	check(used.size() == Rules.MIDBOSSES.size() and used.size() >= 5, "every mid-boss design is flown (%d)" % used.size())
	check(Campaign.midboss_of(Campaign.PER_WORLD - 1) == "bastion", "the hand-made sector keeps the Bastion")
	var layouts := {}
	for id: String in Rules.MIDBOSSES:
		var m: Dictionary = Rules.MIDBOSSES[id]
		var reach := true
		var pieces := true
		var key := ""
		for k in m.sections.size():
			var sec: Dictionary = m.sections[k]
			key += "%d," % sec.parts.size()
			for p: Dictionary in sec.parts:
				reach = reach and absf(p.at.x) <= 7.0 and p.at.z >= -5.0 and p.at.z <= 8.0
				reach = reach and Rules.FOES.has(p.kind) and p.kind in Rules.BOSS_PART_KINDS
				reach = reach and Models.boss_part(p.kind) != null
				key += p.kind
			if k < m.sections.size() - 1:
				pieces = pieces and sec.piece != "" and Models.midboss_piece(id, sec.piece).get_surface_count() > 0
		var heart: Dictionary = m.sections[-1]
		layouts[key] = true
		check(m.sections.size() >= 3 and pieces and Models.midboss_hull(id).get_surface_count() > 0,
			"%s: %d sections, each with a piece that breaks off" % [m.title, m.sections.size()])
		check(heart.parts.size() == 1 and heart.parts[0].kind in Rules.BOSS_HEARTS, "%s: its heart is the last section" % m.name)
		check(reach, "%s: every gun within reach and on screen" % m.name)
		var shapes := Models.midboss_shapes(id)
		var walls: bool = shapes.has("") and Geometry2D.is_point_in_polygon(Vector2.ZERO, shapes[""][0])
		for sec: Dictionary in m.sections:
			walls = walls and (sec.piece == "" or shapes.has(sec.piece) or id == "halo")
		check(walls, "%s: its hull and pieces can be rammed" % m.name)
	check(layouts.size() == Rules.MIDBOSSES.size(), "no two mid-bosses are laid out alike")
	var forts := {}
	var pairs := {}
	for w in Campaign.WORLDS.size():
		var here := {}
		for k in Campaign.PER_WORLD:
			var lv := w * Campaign.PER_WORLD + k
			here[Campaign.fortress_of(lv)] = true
			forts[Campaign.fortress_of(lv)] = true
			pairs[Campaign.midboss_of(lv) + "/" + Campaign.fortress_of(lv)] = true
		check(here.size() == Campaign.PER_WORLD, "%s: three levels, three different fortresses" % Campaign.WORLDS[w].name)
	check(forts.size() == Rules.FORTRESSES.size() and forts.size() >= 5, "every fortress is flown (%d)" % forts.size())
	check(pairs.size() == Campaign.count(), "no two levels have the same pair of bosses")
	check(Campaign.fortress_of(Campaign.PER_WORLD - 1) == "goliath", "the hand-made sector keeps the Goliath")
	var looks := {}
	for id: String in Rules.FORTRESSES:
		var f: Dictionary = Rules.FORTRESSES[id]
		var ok: bool = f.sections[-1].kind == "core" and f.sections[-1].guns.is_empty()
		var kinds := []
		for k in f.sections.size() - 1:
			var sec: Dictionary = f.sections[k]
			kinds.append(sec.kind)
			ok = ok and not sec.guns.is_empty() and Capital.segment(id, k).get_surface_count() > 0 \
				and Capital.piece(id, k).get_surface_count() > 0
			for g: Array in sec.guns:
				ok = ok and g[0] in Rules.SHIP_GUNS and Rules.FOES.has(g[0])
		ok = ok and kinds[-1] in Capital.HEARTS and Rules.fortress_len(id) > 130.0
		looks["%s/%s/%s" % [f.get("hull", Capital.bodies(id).size()), f.paint, kinds]] = true
		check(ok, "%s: %.0f m, %d sections from the stern to the bridge or gondola, each with its guns and a piece that breaks off, then the reactor" % [
			f.title, Rules.fortress_len(id), f.sections.size()])
	check(looks.size() == Rules.FORTRESSES.size(), "no two fortresses look alike")
	check(Campaign.waves(4) == Campaign.waves(4), "a level's waves are the same every time")
	check(Campaign.waves(Campaign.PER_WORLD - 1) == Rules.STAGE, "Glass Coast's fortress run is the hand-made sector")


func progress() -> void:
	print("progress")
	var s := Rules.fresh()
	check(s.open == 0 and s.sel == 0 and s.grades.is_empty(), "a new pilot starts at 1-1")
	check(Campaign.is_open(s, 0) and not Campaign.is_open(s, 1), "only 1-1 is open")
	check(Campaign.cleared(s, 0, "B") and s.open == 1 and s.sel == 1, "clearing 1-1 opens and selects 1-2")
	check(not Campaign.cleared(s, 0, "A") and s.grades["1-1"] == "A", "a replay keeps the better grade")
	Campaign.cleared(s, 0, "C")
	check(s.grades["1-1"] == "A", "and never a worse one")
	s.open = Campaign.count() - 1
	Campaign.cleared(s, Campaign.count() - 1, "S")
	check(s.open == Campaign.count() - 1, "the last level opens nothing past the end")
	var old := Rules.migrate({"scrap": 50, "clears": 2})
	check(old.open == Campaign.PER_WORLD and old.sel == Campaign.PER_WORLD, "a pilot who cleared the old sector starts in world 2")
	var bad := Rules.migrate({"open": 999, "sel": 50, "grades": {"1-1": "Z", "1-2": "A"}})
	check(bad.open == Campaign.count() - 1 and bad.sel <= bad.open and not bad.grades.has("1-1") and bad.grades["1-2"] == "A",
		"saves are clamped")
	Rules.save_game(s, SAVE)
	check(Rules.load_game(SAVE) == Rules.migrate(s), "progress is saved")


func make_game(s: Dictionary) -> Game:
	Rules.save_game(s, SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 5
	return g


## Plays until `until` (immortal), weaving under the foes or lining up with the boss's parts,
## and in the chase with the nearest foe it can hurt.
func run(g: Game, secs: float, until: Callable) -> void:
	for i in int(secs / DT):
		g.hp = maxi(g.hp, 2)
		var tx := sin(g.stage_t * 0.9) * 3.5
		if not g.boss_parts.is_empty():
			tx = g.boss_parts[0].pos.x
		g.prel.x = lerpf(g.prel.x, tx, 0.08)
		if g.pov_mode():
			var best: Game.Obj = null
			for f in g.foes:
				if f.kind not in ["orb", "boss"] and g.lockable(f) and not g.cam.is_position_behind(f.pos) and f.pos.z < g.ppos.z - 4.0:
					if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
						best = f
			if best:
				# line the dipped guns up with it
				g.off = g.line_up(best)
		g.step(DT)
		if until.call():
			return


func select() -> void:
	print("level select")
	var s := Rules.fresh()
	s.scrap = 0
	var g := make_game(s)
	await process_frame
	check(g.level == 0 and g.hud.go_btn.text.contains("1-1"), "the hangar selects 1-1")
	check(not g.hud.level_btns[0].disabled and g.hud.level_btns[1].disabled, "1-2 is locked")
	g.pick_level(1)
	check(g.level == 0, "a locked level can't be picked")
	g.hud.level_btns[1].pressed.emit()
	check(g.level == 0, "nor tapped")
	check(g.hud.world_next.disabled, "nor the next world")
	g.s.open = 4
	g.hud.step_world(1)
	check(g.level == 4 and Models.theme == "dunes" and g.world.name == "Ember Dunes", "world 2 opens on its furthest level, in the dunes")
	check(g.chunks.size() > 0, "its land is rebuilt behind the hangar")
	g.hud.level_btns[0].pressed.emit()
	check(g.level == 3, "tapping a level selects it")
	g.hud.step_world(-1)
	check(g.level == 2 and Models.theme == "coast", "back to Glass Coast")
	g.launch(4)
	check(g.phase == "vert" and g.level == 4 and g.s.sel == 4, "launch plays the selected level")
	await process_frame   # the old world's chunks are freed now
	g.step(DT)
	check(g.marks.all(func(m: Dictionary) -> bool: return is_instance_valid(m.node)), "the old world's landmarks are let go")
	# a landmark still in play whose chunk goes first leaves play with it
	var mark := Game.Obj.new()
	mark.kind = "house"
	mark.ground = true
	mark.node = Node3D.new()
	g.foes.append(mark)
	mark.node.free()
	g.step(DT)
	check(not g.foes.has(mark), "a landmark whose chunk is gone leaves play")
	var dart := g.new_foe("dart", Models.dart())
	check(is_equal_approx(dart.hp, Rules.FOES.dart.hp * 1.3), "foes are tougher in world 2")
	var b := g.bullet(Vector3.ZERO, Vector3(0, 0, 10))
	check(b.vel.length() > 10.0, "and fire faster")
	g.queue_free()
	await process_frame


## The hangar's reset button: one tap only arms it, a second wipes scrap, upgrades, unlocks,
## grades and best score, saves that and goes back to 1-1.
func reset() -> void:
	print("progress reset")
	var s := Rules.fresh()
	s.scrap = 5000
	s.best = 99999
	s.runs = 12
	s.up.cannon = 4
	s.up.hull = 3
	s.open = 7
	s.sel = 7
	s.grades = {"1-1": "S", "2-1": "A"}
	var g := make_game(s)
	await process_frame
	check(g.level == 7 and g.hud.reset_btn.text == "Reset progress", "a veteran pilot on 3-2 sees the reset button")
	g.hud.reset_btn.pressed.emit()
	check(g.s.scrap == 5000 and g.s.open == 7 and g.hud.reset_armed, "one tap only asks for confirmation")
	check(g.hud.reset_btn.text.contains("again"), "and says to tap again")
	g.hud.reset_btn.pressed.emit()
	check(g.s == Rules.fresh(), "the second tap wipes everything back to a new pilot")
	check(Rules.load_game(SAVE) == Rules.fresh(), "and saves it")
	check(g.level == 0 and Models.theme == "coast" and g.hud.go_btn.text.contains("1-1"), "the hangar is back on 1-1")
	check(g.hud.level_btns[1].disabled and g.hud.world_next.disabled, "with the rest locked again")
	check(Rules.max_hp(g.s) == 3 and g.hud.hangar_scrap.text.contains("0"), "no upgrades, no scrap")
	check(not g.hud.reset_armed and g.hud.reset_btn.text == "Reset progress", "the button calms down")
	g.queue_free()
	await process_frame


func looks() -> void:
	print("each world's look")
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.frequency = 0.022
	noise.fractal_octaves = 3
	var cols := {}
	for th: String in Models.THEMES:
		Models.theme = th
		var m := Models.ground_chunk(noise, -400.0, Vector2(64, 40), 2.0)
		var props := m.get_surface_count() > 1
		cols[Models.ground_col(0.2).to_html()] = true
		check(props, "%s land has props" % th)
	Models.theme = "coast"
	check(cols.size() == Models.THEMES.size(), "every theme colours its land its own way")


func levels() -> void:
	print("playing levels")
	var s := Rules.fresh()
	s.up.cannon = 3
	s.up.missile = 2
	var g := make_game(s)
	await process_frame
	g.launch(0)
	var met := [false, false]   # lambdas capture by value: an array to write into
	run(g, 240.0, func() -> bool:
		met[0] = met[0] or g.boss != null
		met[1] = met[1] or g.fortress != null
		return g.phase == "results")
	check(g.phase == "results" and g.run.cleared, "1-1 is cleared")
	check(met[0] and met[1], "after its mid-boss and its fortress")
	check(g.s.open == 1 and g.s.sel == 1 and g.run.opened == 1 and g.s.grades.has("1-1"), "it opens 1-2 and keeps the grade")
	check(g.hud.res_body.text.contains("Unlocked"), "the results say what opened")
	g.to_hangar()
	check(g.level == 1 and g.hud.go_btn.text.contains("1-2"), "back in the hangar, 1-2 is selected")
	check(g.hud.level_btns[1].text.contains(Campaign.midboss(1).name), "its button names its mid-boss")
	# a mid-boss still far above the top (a tall screen) keeps its guns until it arrives
	g.launch(3)
	g.mid_id = "halo"
	g.mid = Rules.MIDBOSSES.halo
	g.spawn_vert("boss", 0.0, 0, 1)
	g.boss.pos.z = g.frame_z - 70.0
	for p in g.boss_parts:
		p.pos = g.mount_point(p.anchor)
	g.step(DT)
	check(g.boss_parts.all(func(p: Game.Obj) -> bool: return g.foes.has(p) and is_instance_valid(p.node)) and g.foes.has(g.boss),
		"a mid-boss far above the screen keeps its guns (2-1 was stuck)")
	g.to_hangar()
	# every mid-boss design, flown down section by section
	for id: String in Rules.MIDBOSSES:
		var lv := 0
		while Campaign.midboss_of(lv) != id:
			lv += 1
		g.s.open = Campaign.count() - 1
		g.launch(lv)
		var secs := [0]
		var hidden := [true]
		run(g, 200.0, func() -> bool:
			if g.boss != null and g.boss_sec > secs[0]:
				var piece: String = g.mid.sections[secs[0]].piece
				hidden[0] = hidden[0] and not g.boss.node.get_node(piece).visible
				secs[0] = g.boss_sec
			return g.boss_done or g.phase == "results")
		var m: Dictionary = Rules.MIDBOSSES[id]
		check(g.boss_done and secs[0] == m.sections.size() - 1 and hidden[0],
			"%s (%s): taken apart in %d sections, each breaking off" % [m.name, Campaign.code(lv), m.sections.size()])
		g.to_hangar()
	# every fortress, chased down section by section
	for id: String in Rules.FORTRESSES:
		var lv := 0
		while Campaign.fortress_of(lv) != id:
			lv += 1
		g.launch(lv)
		# straight to the fortress (the mid-boss counts as down)
		g.boss_done = true
		for k in g.waves.size():
			if g.waves[k].kind == "fortress":
				g.wave_i = k
				g.stage_t = g.waves[k].t
		var secs := [0]
		var hidden := [true]
		var broke := [false]
		run(g, 480.0, func() -> bool:
			if g.fortress != null and g.pov_mode() and g.fort_sec > secs[0] and secs[0] < g.segs.size():
				hidden[0] = hidden[0] and not g.fort_piece(secs[0]).visible
				secs[0] = g.fort_sec
			if g.phase == "escape" and g.fortress != null and g.segs.size() > 1:
				broke[0] = broke[0] or g.segs[0].position.distance_to(Capital.pivot(id, 0)) > 3.0
			return g.phase == "results")
		var f: Dictionary = Rules.FORTRESSES[id]
		check(g.run.cleared and secs[0] == f.sections.size() - 1 and hidden[0] and broke[0],
			"%s (%s): taken apart in %d sections from stern to bow, each breaking off, then breaks up" % [f.name, Campaign.code(lv), f.sections.size()])
		g.to_hangar()
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage campaign test")
	data()
	progress()
	await select()
	await reset()
	looks()
	await levels()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
