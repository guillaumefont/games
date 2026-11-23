extends SceneTree
## The game: rules (upgrades, saves, grades), the vertical stage's controls, the swoop into
## the carrier, the third-person chase (dodging, reactor shield), the climb back out, the boss, death
## and results. Runs headless:
##   godot --headless --path . --script tests/game_test.gd

const SAVE := "user://test_save.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func rules() -> void:
	print("rules")
	var s := Rules.fresh()
	check(s.scrap == 0 and Rules.max_hp(s) == 3, "a new pilot has no scrap and 3 hull")
	check(not Rules.buy(s, "cannon"), "can't buy without scrap")
	s.scrap = 500
	check(Rules.buy(s, "cannon") and s.scrap == 380 and Rules.level(s, "cannon") == 1, "the first cannon level costs 120")
	s.scrap = 99999
	for i in 10:
		Rules.buy(s, "hull")
	check(Rules.level(s, "hull") == 3 and Rules.cost(s, "hull") == -1, "upgrades stop at their max")
	check(Rules.max_hp(s) == 6, "each hull level is one more hit")
	check(Rules.cannon(0).shots.size() == 2 and Rules.cannon(5).shots.size() == 7, "the cannon grows from 2 to 7 guns")
	check(Rules.cannon(5).period < Rules.cannon(0).period and Rules.cannon(5).dmg > Rules.cannon(0).dmg, "and fires faster and harder")
	check(Rules.missile_period(0) == 0.0 and Rules.missile_period(4) < Rules.missile_period(1), "missiles only once bought")
	var m := Rules.migrate({"scrap": -5, "up": {"cannon": 99, "magnet": 2}})
	check(m.scrap == 0 and m.up.cannon == 5 and m.up.magnet == 2 and m.up.hull == 0, "saves are clamped")
	check(Rules.migrate("garbage") == Rules.fresh(), "a broken save starts over")
	check(Rules.grade(100, 100, 0, true) == "S" and Rules.grade(10, 100, 5, false) == "-", "grades")
	check(Rules.fmt(1234567) == "1,234,567", "number format")
	Rules.save_game(s, SAVE)
	check(Rules.load_game(SAVE) == Rules.migrate(s), "saves and loads")


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 3
	return g


## Steps the game; in the chase the autopilot lines up with the nearest foe it can hurt.
func run(g: Game, secs: float, until := Callable(), immortal := true) -> void:
	for i in int(secs / DT):
		if immortal:
			g.hp = maxi(g.hp, 2)
		if g.pov_mode():
			var best: Game.Obj = null
			for f in g.foes:
				if f.kind != "orb" and not f.dead and not (f.kind == "core" and g.shielded()) and not g.cam.is_position_behind(f.pos):
					if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
						best = f
			if best:
				g.off = Vector2(best.pos.x, best.pos.y - Rules.PY)
		g.step(DT)
		if until.is_valid() and until.call():
			return


func controls() -> void:
	print("controls")
	var g := make_game()
	await process_frame
	check(g.phase == "hangar", "the game opens in the hangar")
	g.launch()
	check(g.phase == "vert" and g.hp == 3, "launch starts the vertical stage")
	var x0 := g.prel.x
	g.drag_by(Vector2(100, 0))
	var moved := g.prel.x - x0
	check(moved > 0.5 and moved < 3.0, "dragging moves the ship (%.2f m for 100 px)" % moved)
	g.drag_by(Vector2(99999, -99999))
	check(g.prel.x == Rules.HALF_W and g.prel.y == Rules.Z_TOP + 3.0, "the ship stays on the field")
	# real pointer events (touch is emulated as mouse)
	g.driven = false
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = Vector2(360, 900)
	root.push_input(p, true)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(260, 1000)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(mv, true)
	g.driven = true
	check(g.prel.x < Rules.HALF_W - 0.5 and g.prel.y > Rules.Z_TOP + 3.5, "a touch drag moves the ship")
	run(g, 3.0)
	check(g.shots.size() > 0, "the cannon fires on its own")
	g.queue_free()
	await process_frame


func stage() -> void:
	print("the stage and the carrier episode")
	var g := make_game()
	await process_frame
	g.s.up.missile = 2
	g.launch()
	run(g, 60.0, func() -> bool: return g.phase == "approach")
	check(g.phase == "approach" and g.carrier != null, "the carrier arrives and the swoop begins")
	check(g.foes.is_empty() and g.cam_mode == "chase", "the field is cleared, the camera comes down behind the ship")
	run(g, 5.0, func() -> bool: return g.phase == "pov")
	check(g.phase == "pov" and g.cam_mode == "chase", "on the carrier's tail, the camera behind the ship")
	check(absf(g.ppos.x) < 0.01 and absf(g.ppos.z - (g.stern_z + Rules.GAP_FAR)) < 0.5, "the ship lined up behind the carrier")
	run(g, 1.0)
	check(g.ship.visible and not g.cam.is_position_behind(g.ppos), "third person: the ship stays in view")
	check(g.ppos.z < g.cam.global_position.z and g.cam.global_position.y > g.ppos.y, "the camera is behind and above it")
	var gap := g.ppos.z - g.stern_z
	var z0 := g.ppos.z
	run(g, 1.0)
	check(g.ppos.z < z0 - 15.0 and absf(g.ppos.z - g.stern_z - gap) < 3.0, "ship and carrier fly forward together, outside")
	var kills: int = g.run.kills
	# dragging moves the ship across the view (the way to dodge)
	g.drag_by(Vector2(150, -120))
	for i in 30:
		g.step(DT)
	check(g.ppos.x > 2.0 and g.ppos.y > Rules.PY + 1.5, "dragging up right moves the ship there (%.1f, %.1f)" % [g.ppos.x, g.ppos.y - Rules.PY])
	g.drag_by(Vector2(99999, -99999))
	for i in 30:
		g.step(DT)
	check(absf(g.ppos.x) <= Rules.POV_REACH.x + 0.01 and g.ppos.y <= Rules.PY + Rules.POV_REACH.y + 0.01, "but no further than the play area")
	var o := g.orb(g.ppos + Vector3(0, 0, -20), 10.0)
	var rel := o.vel.z + Rules.RAIL
	check(rel > 9.0, "foes' orbs come at the ship at their own speed, whatever the rail speed")
	run(g, 40.0, func() -> bool: return g.phase == "core")
	check(g.phase == "core" and g.core != null and g.shielded(), "the reactor, shielded by its panels")
	check(g.run.kills > kills, "foes shot down in the chase")
	var hp: float = g.core.hp
	g.damage(g.core, 10.0)
	check(g.core.hp == hp, "the shield stops shots on the core")
	run(g, 40.0, func() -> bool: return g.phase == "escape")
	check(g.phase == "escape" and not g.shielded(), "panels and reactor down: escape")
	run(g, 10.0, func() -> bool: return g.phase == "exit")
	check(g.phase == "exit" and g.cam_mode == "top", "the carrier goes down, the camera climbs back up")
	run(g, 3.0, func() -> bool: return g.phase == "vert")
	check(g.phase == "vert" and g.carrier_done and g.carrier == null and g.ship.visible, "back to the vertical stage, carrier destroyed")
	run(g, 1.0)
	check(g.carrier == null, "the carrier doesn't come back")
	run(g, 60.0, func() -> bool: return g.boss != null)
	check(g.boss != null, "the boss arrives")
	run(g, 80.0, func() -> bool: return g.phase == "results")
	check(g.phase == "results" and g.run.cleared, "boss down: sector clear")
	check(g.s.scrap == g.run.scrap and g.run.scrap > 300 and g.s.clears == 1, "scrap earned goes to the hangar (%d)" % g.run.scrap)
	check(Rules.load_game(SAVE).scrap == g.run.scrap, "and is saved")
	g.queue_free()
	await process_frame


func death() -> void:
	print("death")
	var g := make_game()
	await process_frame
	g.launch()
	for i in 3:
		g.inv = 0.0
		g.hurt()
	check(g.phase == "down" and not g.ship.visible, "three hits: shot down")
	g.inv = 0.0
	g.hurt()
	check(g.run.hits == 3, "no more hits once down")
	run(g, 4.0, Callable(), false)
	check(g.phase == "results" and not g.run.cleared and g.s.runs == 1, "results, not cleared")
	g.phase_t = 1.0
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	g.handle(p)
	check(g.phase == "hangar", "a tap goes back to the hangar")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage game test")
	rules()
	await controls()
	await stage()
	await death()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
