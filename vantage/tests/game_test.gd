extends SceneTree
## The game: rules (upgrades, saves, grades), the vertical stage's controls, the swoop into
## the mid-boss's sections, the carrier chase (final boss: dodging, reactor shield), death
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


## Foes counted as they spawn in the vertical stage, and those that appeared on screen.
var entries := 0
var popped_in := 0


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
		if g.phase == "vert" and not g.boss_parts.is_empty():
			g.prel.x = lerpf(g.prel.x, g.boss_parts[0].pos.x, 0.08)
		if g.phase == "vert" and not g.boss_parts.is_empty():
			g.prel.x = lerpf(g.prel.x, g.boss_parts[0].pos.x, 0.08)
		if g.pov_mode():
			var best: Game.Obj = null
			for f in g.foes:
				if f.kind not in ["orb", "boss"] and not f.dead and not (f.kind == "core" and g.shielded()) and not g.cam.is_position_behind(f.pos):
					if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
						best = f
			if best:
				g.off = Vector2(best.pos.x, best.pos.y - Rules.PY)
		g.step(DT)
		if g.phase == "vert":
			for f in g.foes:
				if f.kind in ["dart", "swing", "heavy", "turret"] and f.t <= DT * 1.5:
					entries += 1
					if g.on_screen(f):
						popped_in += 1
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
	print("the stage: mid-boss, carrier chase (final boss)")
	var g := make_game()
	await process_frame
	g.s.up.missile = 2
	g.launch()
	# the mid-boss, top-down
	run(g, 40.0, func() -> bool: return g.boss != null)
	check(g.boss != null and g.phase == "vert", "the mid-boss arrives in the vertical stage")
	check(g.boss_parts.size() == 4 and g.boss_sec == 0, "its bow guns are the first section")
	var bridge_open := false
	for f in g.foes:
		if f.kind == "bridge":
			bridge_open = true
	check(not bridge_open, "the bridge isn't open yet")
	var t0 := g.stage_t
	run(g, 60.0, func() -> bool: return g.boss_sec == 1)
	check(g.boss_sec == 1 and not g.boss.node.get_node("bow").visible, "bow guns down: the bow breaks off, the wing batteries open")
	check(g.wave_i < Rules.STAGE.size() and Rules.STAGE[g.wave_i].kind == "boss", "the waves wait for the mid-boss")
	run(g, 60.0, func() -> bool: return g.boss_sec == 2)
	check(g.boss_sec == 2 and not g.boss.node.get_node("wings").visible, "batteries down: the wings break off, the bridge opens")
	var br: Game.Obj = g.boss_parts[0]
	check(br.kind == "bridge" and not g.boss_shielded(br), "the bridge can be hit now")
	run(g, 60.0, func() -> bool: return g.boss == null)
	check(g.boss == null and g.boss_done and g.phase == "vert", "mid-boss down, the sector carries on")
	check(g.stage_t < Rules.STAGE[g.wave_i].t + 1.0 and g.stage_t > t0 - 5.0, "the waves pick up where they stopped")
	check(entries > 20 and popped_in == 0, "foes enter from off-screen (%d entries, %d inside)" % [entries, popped_in])
	var froms := {}
	for w: Dictionary in Rules.STAGE:
		froms[w.get("from", "top")] = true
	check(froms.has("left") and froms.has("right") and froms.has("back") and froms.has("top"), "from every edge: top, left, right and back")
	# the final boss: the carrier, chased in third person
	check(g.vacuum_t > 0.0 or g.picks.is_empty(), "its scrap flies to the ship")
	run(g, 60.0, func() -> bool: return g.phase == "approach")
	check(g.phase == "approach" and g.carrier != null, "the carrier arrives and the swoop begins")
	check(g.cam_mode == "chase", "the camera comes down behind the ship")
	run(g, 5.0, func() -> bool: return g.phase == "pov")
	check(g.phase == "pov" and g.cam_mode == "chase", "on the carrier's tail, the camera behind the ship")
	check(absf(g.ppos.x) < 0.01 and absf(g.ppos.z - (g.stern_z + Rules.GAP_FAR)) < 0.5, "the ship lined up behind the carrier")
	check(g.car_sec == 0 and g.car_parts.size() == Rules.CARRIER_SECTIONS[0].mounts.size(), "its stern guns are the first section")
	for i in 20:
		g.step(DT)
	check(g.car_s == Rules.CARRIER_SCALE, "the carrier grew during the swoop")
	var vs := g.view_size()
	var left := g.cam.unproject_position(g.carrier_point(Vector3(-Rules.CARRIER_HW, Rules.PY, 0)))
	var right := g.cam.unproject_position(g.carrier_point(Vector3(Rules.CARRIER_HW, Rules.PY, 0)))
	var tower := g.cam.unproject_position(g.carrier_point(Vector3(0, Rules.TOWER_TOP, 0)))
	check(left.x < 0 and right.x > vs.x and tower.y < 0, "the final boss is bigger than the screen")
	run(g, 1.0)
	check(g.ship.visible and not g.cam.is_position_behind(g.ppos), "third person: the ship stays in view")
	# (above it unless the ship climbs the tower: the camera follows the climb only partly)
	check(g.ppos.z < g.cam.global_position.z and g.cam.global_position.y > minf(g.ppos.y, Rules.PY + 8.0), "the camera is behind and above it")
	var gap := g.ppos.z - g.stern_z
	var z0 := g.ppos.z
	run(g, 1.0)
	check(g.ppos.z < z0 - 15.0 and absf(g.ppos.z - g.stern_z - gap) < 3.0, "ship and carrier fly forward together, outside")
	var kills: int = g.run.kills
	g.off = Vector2.ZERO
	for i in 40:
		g.step(DT)
	g.drag_by(Vector2(150, -120))
	for i in 30:
		g.step(DT)
	check(g.ppos.x > 2.0 and g.ppos.y > Rules.PY + 1.5, "dragging up right moves the ship there (%.1f, %.1f)" % [g.ppos.x, g.ppos.y - Rules.PY])
	g.drag_by(Vector2(99999, -99999))
	for i in 30:
		g.step(DT)
	check(absf(g.ppos.x) <= Rules.POV_REACH.x + 0.01 and g.ppos.y <= Rules.PY + Rules.POV_REACH.y + 0.01, "but no further than the play area")
	var o := g.orb(g.ppos + Vector3(0, 0, -20), 10.0)
	check(o.vel.z + Rules.RAIL > 9.0, "foes' orbs come at the ship at their own speed, whatever the rail speed")
	run(g, 60.0, func() -> bool: return g.car_sec == 1)
	check(g.car_sec == 1 and not g.carrier.get_node("plating").visible, "stern guns down: the plating breaks off, the tower guns open")
	run(g, 60.0, func() -> bool: return g.phase == "core")
	check(g.car_sec == 2 and not g.carrier.get_node("tower").visible, "tower guns down: the tower breaks off, the reactor opens")
	check(g.phase == "core" and g.core != null and g.shielded(), "the reactor, shielded by its panels")
	check(g.run.kills > kills, "foes shot down in the chase")
	var hp: float = g.core.hp
	g.damage(g.core, 10.0)
	check(g.core.hp == hp, "the shield stops shots on the core")
	run(g, 40.0, func() -> bool: return g.phase == "escape")
	check(g.phase == "escape" and not g.shielded(), "panels and reactor down: the carrier goes down")
	run(g, Rules.CRASH_TIME * 0.6)
	check(g.carrier != null and g.carrier.visible and g.car_fall > 3.0 and g.carrier.rotation.x < -0.05,
		"it noses over and falls, in sight (%.1f m down)" % g.car_fall)
	check(not g.cam.is_position_behind(g.carrier.global_position) and g.sound.played.has("crash"), "with the crash heard")
	run(g, Rules.CRASH_TIME + 2.0, func() -> bool: return g.phase == "clear")
	check(g.phase == "clear" and g.cam_mode == "chase" and g.carrier == null, "the final boss is down: sector clear, still in the chase view")
	run(g, 10.0, func() -> bool: return g.phase == "results")
	check(g.phase == "results" and g.run.cleared, "results: sector cleared")
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


## Guillaume: the carrier's sides were out of reach, ground turrets were hit above where they
## show, and hits need a flash.
func aiming() -> void:
	print("aiming and hits")
	for sec: Dictionary in Rules.CARRIER_SECTIONS:
		for m: Vector2 in sec.mounts:
			var x := m.x * Rules.CARRIER_SCALE
			check(absf(x) <= Rules.POV_REACH.x, "carrier mount at x %.1f within the chase's reach" % x)
	var g := make_game()
	await process_frame
	g.launch()
	run(g, 2.0)
	var t := g.new_foe("turret", Models.turret())
	t.ground = true
	t.pos = Vector3(3.0, 0.4, g.frame_z - 6.0)
	g.step(DT)
	await process_frame
	var shown := g.cam.unproject_position(t.pos)
	var plane := g.cam.unproject_position(g.seen(t.pos))
	check(shown.distance_to(plane) < 2.0, "a ground turret is hit where it shows on screen (%.1f px)" % shown.distance_to(plane))
	check(g.cam.unproject_position(Vector3(t.pos.x, Rules.PY, t.pos.z)).distance_to(shown) > 20.0, "(straight above it would miss by a lot)")
	var hp := t.hp
	g.damage(t, 1.0)
	g.step(DT)
	check(t.hp < hp and (t.node as MeshInstance3D).material_overlay == Models.hit_mat(), "a hit foe flashes")
	for i in 12:
		g.step(DT)
	check(t.dead or (t.node as MeshInstance3D).material_overlay == null, "and the flash fades")
	g.queue_free()
	await process_frame


## Guillaume: one swipe should carry the ship from one flank of the carrier to the other.
func swipe() -> void:
	print("the chase swipe")
	var g := make_game()
	await process_frame
	var d := g.pov_drag()
	var across := g.view_size().x * Rules.POV_SWIPE
	check(across * d.x >= 2.0 * Rules.POV_REACH.x - 0.01, "a %.0f px swipe crosses the whole carrier (%.1f m)" % [across, across * d.x])
	check(g.view_size().y * Rules.POV_SWIPE * d.y >= Rules.POV_REACH.y + Rules.POV_DOWN - 0.01, "and one swipe up climbs the tower")
	g.queue_free()
	await process_frame


## Guillaume: shots stopped short of the screen edge, and foes left too quickly.
func lingering() -> void:
	print("shot range and time on screen")
	var g := make_game()
	await process_frame
	g.launch()
	g.step(DT)
	var o := g.new_shot(Vector3(0, Rules.PY, g.frame_z + g.view_top + 0.5), Vector3(0, 0, -30), 1.0)
	check(not g.gone(o), "a shot still flies at the very top of the screen")
	for from: String in ["back", "left"]:
		g.spawn_vert("dart", 4.5 if from == "back" else 0.0, 0, 1, from)
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.hp = 1e6   # the autofire would bring it down; this is about its flight
		var seen_t := 0.0
		for i in int(10.0 / DT):
			g.hp = 3
			g.step(DT)
			if f.dead or not f in g.foes:
				break
			if g.on_screen(f):
				seen_t += DT
		var want := 4.0 if from == "back" else 2.8
		check(seen_t >= want, "a dart from the %s stays on screen %.1f s (at least %.1f)" % [from, seen_t, want])
	var before: int = g.run.scrap
	var c := g.drop(Vector3(5, Rules.PY, g.frame_z - 10), 7.0)
	g.begin_approach()
	check(c.dead and g.run.scrap == before + 7, "scrap left on screen is collected when the stage ends")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage game test")
	rules()
	await controls()
	await aiming()
	await swipe()
	await lingering()
	await stage()
	await death()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
