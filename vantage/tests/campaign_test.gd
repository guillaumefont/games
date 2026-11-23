extends SceneTree
## The campaign: worlds and levels, their waves, progress and unlocks in the save, the level
## select in the hangar, each world's look, and full runs of a patrol and a battleship level.
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
		var carriers := 0
		for k in ws.size():
			if k > 0 and ws[k].t < ws[k - 1].t:
				sorted = false
			if ws[k].kind == "boss":
				bosses += 1
			if ws[k].kind == "carrier":
				carriers += 1
		var kind := Campaign.kind_of(lv)
		var last: String = ws[-1].kind
		var shape := false
		match kind:
			"patrol":
				shape = bosses == 0 and carriers == 0 and last == "end"
			"battleship":
				shape = bosses == 1 and carriers == 0 and last == "end" and ws[-2].kind == "boss"
			"carrier":
				shape = bosses == 1 and carriers == 1 and last == "carrier"
		check(sorted and shape and ws.size() > 8 and Campaign.foes_in(lv) > 30,
			"%s %s (%s): %d waves, in order, ends right" % [Campaign.code(lv), Campaign.level_name(lv), kind, ws.size()])
	check(Campaign.waves(4) == Campaign.waves(4), "a level's waves are the same every time")
	check(Campaign.waves(Campaign.PER_WORLD - 1) == Rules.STAGE, "Glass Coast's carrier run is the hand-made sector")


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


## Plays until `until` (immortal), weaving under the foes or lining up with the boss's parts.
func run(g: Game, secs: float, until: Callable) -> void:
	for i in int(secs / DT):
		g.hp = maxi(g.hp, 2)
		var tx := sin(g.stage_t * 0.9) * 3.5
		if not g.boss_parts.is_empty():
			tx = g.boss_parts[0].pos.x
		g.prel.x = lerpf(g.prel.x, tx, 0.08)
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
	g.step(DT)
	var dart := g.new_foe("dart", Models.dart())
	check(is_equal_approx(dart.hp, Rules.FOES.dart.hp * 1.3), "foes are tougher in world 2")
	var b := g.bullet(Vector3.ZERO, Vector3(0, 0, 10))
	check(b.vel.length() > 10.0, "and fire faster")
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
	run(g, 120.0, func() -> bool: return g.phase == "results")
	check(g.phase == "results" and g.run.cleared, "1-1, a patrol, ends once its waves are done")
	check(g.boss == null and g.carrier == null, "without a boss")
	check(g.s.open == 1 and g.s.sel == 1 and g.run.opened == 1 and g.s.grades.has("1-1"), "it opens 1-2 and keeps the grade")
	check(g.hud.res_body.text.contains("Unlocked"), "the results say what opened")
	g.to_hangar()
	check(g.level == 1 and g.hud.go_btn.text.contains("1-2"), "back in the hangar, 1-2 is selected")
	g.launch()
	var met := [false]   # lambdas capture by value: an array to write into
	run(g, 200.0, func() -> bool:
		met[0] = met[0] or g.boss != null
		return g.phase == "results")
	check(met[0] and g.phase == "results" and g.run.cleared, "1-2 ends with the battleship")
	check(g.s.open == 2, "and opens 1-3")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage campaign test")
	data()
	progress()
	await select()
	looks()
	await levels()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
