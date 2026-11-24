extends SceneTree
## The game: rules (upgrades, saves, grades), the vertical stage's controls, the swoop into
## the mid-boss's sections, the fortress chase (final boss: dodging, reactor shield), death
## and results, the scenery. Runs headless:
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
	check(Rules.cannon(0).shots.size() == 2 and Rules.cannon(Rules.POWER_MAX).shots.size() == 7, "power grows the cannon from 2 to 7 guns")
	check(Rules.cannon(Rules.POWER_MAX).period < Rules.cannon(0).period, "and fires faster at full power")
	check(Rules.cannon(0, 5).shots.size() == 2 and Rules.cannon(0, 5).dmg > Rules.cannon(0, 0).dmg, "the Cannon upgrade hits harder, but never widens the spread")
	# the upgrade can't take a run's start anywhere near full power (Guillaume: it got too easy)
	var top := Rules.cannon(Rules.POWER_MAX, 0)
	var bought := Rules.cannon(0, 5)
	check(bought.shots.size() * bought.dmg / bought.period < 0.5 * top.shots.size() * top.dmg / top.period,
		"a maxed Cannon at the start of a level has under half the fire of a bare ship at full power")
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


## In-level power (Guillaume, 2026-11-24: "how about keeping an in level progress"): every level
## starts on the twin gun, cores dropped by foes widen it, a hit costs a step.
func power() -> void:
	print("in-level power")
	var g := make_game()
	await process_frame
	g.s.up.cannon = 5
	g.launch(0)
	g.time_k = 1.0
	check(g.power == 0, "a level starts at power 0, whatever was bought")
	g.step(0.2)
	check(g.shots.size() == 2, "on the twin gun")
	for i in Rules.POWER_EVERY:
		g.count_core(g.ppos + Vector3(0, 0, -4))
	var cores := g.picks.filter(func(p: Game.Obj) -> bool: return p.kind == "power")
	check(cores.size() == 1, "every %d kills leave a power core" % Rules.POWER_EVERY)
	cores[0].pos = g.ppos
	g.step(DT)
	check(g.power == 1, "picking it up is a power step")
	for i in 10:
		g.power_up()
	check(g.power == Rules.POWER_MAX, "power stops at its max")
	g.clear_all()
	g.fire_cd = 0.0
	g.step(DT)
	check(g.shots.size() == 7, "at full power the whole spread fires")
	g.inv = 0.0
	g.hurt()
	check(g.power == Rules.POWER_MAX - 1 and g.hp == Rules.max_hp(g.s) - 1, "a hit costs a power step and a hull pip")
	g.to_hangar()
	g.launch(0)
	check(g.power == 0, "the next level starts over")
	g.queue_free()
	await process_frame


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
				if f.kind not in ["orb", "boss"] and g.lockable(f) and not g.cam.is_position_behind(f.pos) and f.pos.z < g.ppos.z - 4.0:
					if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
						best = f
			if best:
				# line the dipped guns up with it
				g.off = g.line_up(best)
		g.step(DT)
		if g.phase == "vert":
			for f in g.foes:
				if (f.kind in ["dart", "swing", "heavy"] or f.kind in Foes.INTRO or Towers.is_tower(f.kind)) and f.t <= DT * 1.5:
					entries += 1
					if g.on_screen(f):
						popped_in += 1
		if until.is_valid() and until.call():
			return


## Lifting the finger slows time down to a pause; touching again ramps it back up.
func slow_pause() -> void:
	print("slow-motion pause")
	var g := make_game()
	await process_frame
	g.touching = false
	g.tick(DT)
	check(g.time_k == 1.0, "the hangar never pauses")
	g.launch()
	check(g.paused(), "after the launch tap the stage waits for a finger")
	var t0 := g.stage_t
	g.tick(DT)
	check(g.stage_t == t0, "paused, the stage doesn't move")
	g.touching = true
	g.tick(DT)
	var k1 := g.time_speed()
	check(k1 > 0.0 and k1 < 0.2 and g.stage_t > t0, "touching starts time again, gently (%.3f)" % k1)
	for i in int(Rules.SLOW_RESUME / DT) + 2:
		g.tick(DT)
	check(g.time_speed() == 1.0, "and soon at full speed")
	var t1 := g.stage_t
	g.tick(DT)
	check(is_equal_approx(g.stage_t - t1, DT), "full speed is real time")
	g.touching = false
	var last := DT
	var slowing := true
	for i in int(Rules.SLOW_STOP / DT) + 2:
		var before := g.stage_t
		g.tick(DT)
		var d := g.stage_t - before
		slowing = slowing and d <= last + 1e-6
		last = d
		if i == int(1.0 / DT):
			check(g.time_speed() > 0.3 and not g.paused(), "a second after lifting, time still runs (%.2f): the slowdown is gradual" % g.time_speed())
	check(slowing, "lifting the finger slows time steadily")
	check(g.paused(), "until the game is paused (after %.1f s)" % Rules.SLOW_STOP)
	var x0 := g.prel.x
	t0 = g.stage_t
	for i in 60:
		g.tick(DT)
	check(g.stage_t == t0 and g.prel.x == x0, "and it stays paused")
	g.touching = true
	g.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not g.touching, "leaving the app lifts the finger")
	# the chase pauses the same way
	g.touching = true
	g.spawn_fortress()
	g.begin_approach()
	for i in 30:
		g.tick(DT)
	g.touching = false
	for i in int(Rules.SLOW_STOP / DT) + 2:
		g.tick(DT)
	check(g.paused() and g.phase == "approach", "the swoop into the chase pauses too")
	g.queue_free()
	await process_frame


## Paused, a "Main menu" button quits the run back to the hangar after a confirming second tap.
func pause_menu() -> void:
	print("pause menu")
	var g := make_game()
	await process_frame
	g.launch()
	g.touching = true
	for i in 30:
		g.tick(DT)
	check(not g.hud.quit_btn.visible, "no main menu button while flying")
	g.run.scrap = 7
	var scrap0: int = g.s.scrap
	g.touching = false
	for i in int(Rules.SLOW_STOP / DT) + 2:
		g.tick(DT)
	check(g.paused() and g.hud.quit_btn.visible, "paused, the main menu button shows")
	g.hud.quit_tap()
	check(g.phase == "vert" and g.hud.quit_armed, "one tap only arms it")
	g.hud.quit_tap()
	check(g.phase == "hangar" and g.hud.hangar.visible, "a second tap quits to the hangar")
	check(g.s.scrap == scrap0 + 7, "the scrap picked up is kept (%d)" % g.s.scrap)
	check(int(g.s.runs) == 0, "a quit run isn't counted")
	g.tick(DT)
	check(not g.hud.quit_btn.visible and g.time_k == 1.0, "the hangar shows no pause menu")
	g.queue_free()
	await process_frame


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
	print("the stage: mid-boss, fortress chase (final boss)")
	var g := make_game()
	await process_frame
	g.s.up.missile = 2
	g.s.open = 2
	g.launch(2)   # Glass Coast's fortress run: the hand-made sector
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
	# the final boss: the fortress, chased in third person
	check(g.vacuum_t > 0.0 or g.picks.is_empty(), "its scrap flies to the ship")
	run(g, 60.0, func() -> bool: return g.phase == "approach")
	check(g.phase == "approach" and g.fortress != null, "the fortress arrives and the swoop begins")
	check(g.cam_mode == "chase", "the camera comes down behind the ship")
	run(g, 5.0, func() -> bool: return g.phase == "pov")
	check(g.phase == "pov" and g.cam_mode == "chase", "behind the fortress's stern, the camera behind the ship")
	var st := Rules.station(g.fort_id, 0)
	check(absf(g.ppos.x) < 0.01 and absf(g.ppos.z - (g.stern_z - st.x)) < 0.5 and absf(g.ppos.y - (g.deck_y + st.y)) < 0.6,
		"the ship lined up %.0f m behind its stern, level with its engines" % -st.x)
	check(g.fort_sec == 0 and g.fort_parts.size() == Rules.FORTRESS_SECTIONS[0].guns.size(), "its engines are the first section")
	check(g.fort_s == 1.0 and g.deck_y > Rules.CHASE_DECK - 0.5, "the fortress grew during the swoop and climbed to its height")
	# Guillaume (2026-11-23): a huge fortress-class ship, no tunnel: a capital ship far longer and
	# wider than the screen, cut into sections along its length
	var L := Rules.fortress_len(g.fort_id)
	check(L > 200.0 and g.segs.size() == Rules.FORTRESS_SECTIONS.size() - 1, "a %.0f m capital ship in %d hull segments" % [L, g.segs.size()])
	var vs := g.view_size()
	var left := g.cam.unproject_position(g.fort_point(Vector3(-Rules.FORTRESS_HW, 0, -10.0)))
	var right := g.cam.unproject_position(g.fort_point(Vector3(Rules.FORTRESS_HW, 0, -10.0)))
	# (wider than a phone's screen; at least most of a landscape test window)
	check(right.x - left.x > vs.x * 0.8, "its hull fills the screen's width (%.0f..%.0f px of %.0f)" % [left.x, right.x, vs.x])
	var nz := 0
	for f in g.fort_parts:
		var p := g.cam.unproject_position(f.pos)
		if f.kind == "nozzle" and p.x > 0 and p.x < vs.x and p.y > 0 and p.y < vs.y:
			nz += 1
	check(nz >= 3, "its engines' nozzles on screen (%d)" % nz)
	run(g, 1.0)
	check(g.ship.visible and not g.cam.is_position_behind(g.ppos), "third person: the ship stays in view")
	check(g.ppos.z < g.cam.global_position.z and g.cam.global_position.y > g.ppos.y, "the camera is behind and above it")
	var gap := g.ppos.z - g.stern_z
	var z0 := g.ppos.z
	run(g, 1.0)
	check(g.ppos.z < z0 - 15.0 and absf(g.ppos.z - g.stern_z - gap) < 1.0, "ship and fortress fly forward together, outside")
	var kills: int = g.run.kills
	g.off = Vector2.ZERO
	for i in 40:
		g.step(DT)
	g.drag_by(Vector2(150, -120))
	for i in 30:
		g.step(DT)
	check(g.ppos.x > 2.0 and g.ppos.y > g.chase_y + 1.5, "dragging up right moves the ship there (%.1f, %.1f)" % [g.ppos.x, g.ppos.y - g.chase_y])
	g.drag_by(Vector2(99999, -99999))
	for i in 30:
		g.step(DT)
	check(absf(g.ppos.x) <= Rules.POV_REACH.x + 0.01 and g.ppos.y <= g.chase_y + Rules.POV_REACH.y + 0.01, "but no further than the play area")
	var o := g.orb(g.ppos + Vector3(0, 0, -20), 10.0)
	check(o.vel.z + Rules.RAIL > 9.0, "foes' orbs come at the ship at their own speed, whatever the rail speed")
	# section by section along the ship, from the stern to the bow
	var along0 := g.along
	run(g, 60.0, func() -> bool: return g.fort_sec == 1)
	check(g.fort_sec == 1 and not g.fort_piece(0).visible, "engines down: their housings break off, the hangar deck opens")
	run(g, Rules.ADVANCE + 0.1)
	var st1 := Rules.station(g.fort_id, 1)
	check(absf(g.along - st1.x) < 0.5 and g.along > along0 + 40.0 and absf(g.fly - Rules.FLY) < 0.1,
		"the ship glides on along the hull, over the deck (%.0f m on)" % (g.along - along0))
	check(g.ppos.y > g.deck_y + 3.0 and g.ppos.z < g.stern_z, "now flying over the deck")
	# the gun deck's shield pylon guards its guns until it falls
	run(g, 90.0, func() -> bool: return g.fort_sec == 2)
	var pylon: Game.Obj = null
	var guarded: Game.Obj = null
	for f in g.fort_parts:
		if f.kind == "pylon":
			pylon = f
		elif not f.dead:
			guarded = f
	check(pylon != null and guarded != null and g.fort_guarded(guarded) and not g.lockable(guarded), "a shield pylon guards the gun deck's guns")
	if pylon and guarded:
		var ghp := guarded.hp
		g.damage(guarded, 5.0)
		check(guarded.hp == ghp, "shots bounce off a shielded gun")
		g.damage(pylon, 9999.0)
		check(not g.fort_guarded(guarded) and g.lockable(guarded), "the pylon down, its guns can be hit")
	run(g, 90.0, func() -> bool: return g.phase == "core")
	check(g.phase == "core" and g.core != null and g.shielded(), "bridge guns down: its armour breaks off, the reactor shows, shielded by its panels")
	check(not g.fort_piece(g.segs.size() - 1).visible, "(the bridge's armour is gone)")
	check(g.run.kills > kills, "foes shot down in the chase")
	var hp: float = g.core.hp
	g.damage(g.core, 10.0)
	check(g.core.hp == hp, "the shield stops shots on the core")
	run(g, 40.0, func() -> bool: return g.phase == "escape")
	check(g.phase == "escape" and not g.shielded(), "panels and reactor down: the fortress breaks up")
	# Guillaume: it dies in the air and drifts off the screen, not into the ground
	var starts: Array[Vector3] = []
	for seg in g.segs:
		starts.append(seg.global_position)
	var low := 1e9
	var spread := true
	for i in int(Rules.BREAKUP_TIME * 0.6 / DT):
		g.step(DT)
		for seg in g.segs:
			low = minf(low, seg.global_position.y - Rules.HULL_DEPTH * 0.6)
	for k in g.segs.size() - 1:
		spread = spread and g.segs[k].global_position.distance_to(g.segs[k + 1].global_position) > \
			starts[k].distance_to(starts[k + 1]) + 3.0
	check(spread, "its hull parts at the seams and the pieces drift apart")
	check(low > 4.0, "in the air: no piece comes near the ground (lowest %.1f m)" % low)
	check(g.stern_z > g.ppos.z - Rules.fortress_len(g.fort_id) + 20.0 and g.sound.played.has("crash"), "the wreck drops back towards the ship, with the blasts heard")
	run(g, Rules.BREAKUP_TIME, func() -> bool: return g.phase_t > Rules.BREAKUP_TIME - 0.1)
	var shown := 0
	for seg in g.segs:
		var p: Vector3 = seg.global_position
		if not g.cam.is_position_behind(p):
			var px := g.cam.unproject_position(p)
			if px.x > 0 and px.x < vs.x and px.y > 0 and px.y < vs.y:
				shown += 1
	check(shown == 0, "and drifts off the screen (%d pieces still on it)" % shown)
	run(g, 3.0, func() -> bool: return g.phase == "clear")
	check(g.phase == "clear" and g.cam_mode == "chase" and g.fortress == null, "the final boss is down: sector clear, still in the chase view")
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


## Guillaume: the fortress's sides were out of reach, ground turrets were hit above where they
## show, and hits need a flash.
func aiming() -> void:
	print("aiming and hits")
	for id: String in Rules.FORTRESSES:
		# every gun within the chase's reach from its section's lane (over the top, along a flank,
		# beneath, between hulls): across, and between the lowest and highest the ship's dipped
		# guns reach at that distance (the small aim assist and the gun's own size included)
		var reach := true
		var secs: Array = Rules.FORTRESSES[id].sections
		for i in secs.size():
			var l := Capital.lane(id, i)
			var r: Vector4 = l.reach
			for g: Array in secs[i].guns:
				var at := Rules.gun_at(id, i, g)
				var slack: float = Rules.AIM_ASSIST + float(Rules.FOES[g[0]].r)
				var dist: float = -at.z - float(l.along)
				var dip: float = dist * float(l.dip)
				var dx: float = at.x - float(l.x)
				var ok: bool = dx >= r.x - slack and dx <= r.y + slack \
					and at.y >= float(l.y) + r.z - dip - slack and at.y <= float(l.y) + r.w - dip + slack and dist > 8.0 and dist <= 45.0
				if not ok:
					print("    out of reach: ", id, " ", g, " dist ", dist, " at ", at, " lane ", l.x, ", ", l.y)
				reach = reach and ok
		check(reach, "every gun of the %s within the chase's reach" % Rules.FORTRESSES[id].name)
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


## Guillaume: flying into enemies damages the ship. Small foes break up, big ones take a knock,
## the ship blinks (passing through) and is thrown back; ground targets and scenery pass under.
func ramming() -> void:
	print("ramming")
	var g := make_game()
	await process_frame
	g.launch()
	run(g, 0.5)
	g.foes.clear()
	g.bullets.clear()
	var hp := g.hp
	var d := g.new_foe("dart", Models.dart())
	d.rel = true
	d.pos = g.ppos + Vector3(0, 0, -0.5)
	g.step(DT)
	check(d.dead and g.hp == hp - 1 and g.inv > 0.0, "flying into a dart: it breaks up and the ship takes a hit")
	check(g.knock.y > 0.0, "and the ship is thrown back from it")
	var y0 := g.prel.y
	for i in 10:
		g.step(DT)
	check(g.prel.y > y0 + 0.5 and g.knock.length() < Rules.KNOCK, "the throw moves the ship and eases off")
	var d2 := g.new_foe("dart", Models.dart())
	d2.rel = true
	d2.pos = g.ppos
	g.step(DT)
	check(not d2.dead and g.hp == hp - 1, "while it blinks the ship passes through")
	d2.dead = true
	g.inv = 0.0
	var h := g.new_foe("heavy", Models.heavy())
	h.rel = true
	h.t = 5.0
	h.pos = g.ppos
	var hhp := h.hp
	g.step(DT)
	check(not h.dead and is_equal_approx(h.hp, hhp - Rules.RAM_DMG) and g.hp == hp - 2, "a heavy takes a knock, the ship a hit")
	g.shots.clear()
	for i in 30:
		g.collide(DT)
	check(is_equal_approx(h.hp, hhp - Rules.RAM_DMG), "and only once per hit")
	h.dead = true
	g.inv = 0.0
	g.hp = 5
	g.bullets.clear()
	var t := g.new_foe("turret", Models.turret())
	t.ground = true
	t.pos = Vector3(g.ppos.x, 0.4, g.ppos.z)
	g.step(DT)
	check(g.hp == 5 and not t.dead, "ground turrets pass under the ship")
	t.dead = true
	# the Bastion: its hull is a wall that hurts, its wings only until they break off
	g.mid_id = "bastion"
	g.mid = Rules.MIDBOSSES.bastion
	g.spawn_vert("boss", 0.0, 0, 1)
	var b := g.boss
	b.pos = Vector3(0, Rules.PY, g.frame_z - 6.0)
	check(g.boss_rammed(b.pos) and g.boss_rammed(b.pos + Vector3(0, 0, 9.0)), "the Bastion's hull and bow can be rammed")
	check(g.boss_rammed(b.pos + Vector3(10.0, 0, -3.0)), "and its wings")
	check(not g.boss_rammed(b.pos + Vector3(0, 0, 11.0)) and not g.boss_rammed(b.pos + Vector3(10.0, 0, 3.0)), "but not past them")
	g.inv = 0.0
	g.prel = Vector2(0.0, b.pos.z + 3.0 - g.frame_z - Rules.SCROLL * DT)
	g.step(DT)
	check(g.hp == 4 and g.knock.y > 0.0, "ramming the Bastion costs a hit and throws the ship back")
	b.node.get_node("wings").visible = false
	check(not g.boss_rammed(b.pos + Vector3(10.0, 0, -3.0)), "its wings stop counting once broken off")
	g.queue_free()
	await process_frame
	# the chase: drones rammed in 3D
	g = make_game()
	await process_frame
	g.launch()
	g.spawn_fortress()
	g.begin_approach()
	g.begin_pov()
	for f in g.foes:
		if f.kind == "drone":
			f.dead = true
	g.drone_t = 99.0
	hp = g.hp
	var dr := g.new_foe("drone", Models.drone())
	dr.pos = g.ppos + Vector3(0.3, 0.3, 0)
	dr.t = 20.0
	g.collide(DT)
	check(dr.dead and g.hp == hp - 1 and g.knock.length() > 0.0, "in the chase a rammed drone breaks up and the ship takes a hit")
	g.inv = 0.0
	var far := g.new_foe("drone", Models.drone())
	far.pos = g.ppos + Vector3(0, 3.0, 0)
	g.collide(DT)
	check(not far.dead and g.hp == hp - 1, "a drone above the ship misses it (3D)")
	g.queue_free()
	await process_frame


## Guillaume: one swipe should carry the ship from one flank of the fortress to the other.
func swipe() -> void:
	print("the chase swipe")
	var g := make_game()
	await process_frame
	var d := g.pov_drag()
	var across := g.view_size().x * Rules.POV_SWIPE
	check(across * d.x >= 2.0 * Rules.POV_REACH.x - 0.01, "a %.0f px swipe crosses the whole fortress (%.1f m)" % [across, across * d.x])
	check(g.view_size().y * Rules.POV_SWIPE * d.y >= Rules.POV_REACH.y + Rules.POV_DOWN - 0.01, "and one swipe up climbs to the bridge")
	g.queue_free()
	await process_frame


## Guillaume: shots stopped short of the screen edge, and foes left too quickly.
func lingering() -> void:
	print("shot range and time on screen")
	var g := make_game()
	await process_frame
	g.s.open = 2
	g.launch(2)
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
	for p in g.picks:
		before += int(p.dmg) if not p.dead else 0   # scrap already about (from foes shot down)
	var c := g.drop(Vector3(5, Rules.PY, g.frame_z - 10), 7.0)
	g.begin_approach()
	check(c.dead and g.run.scrap == before + 7, "scrap left on screen is collected when the stage ends")
	g.queue_free()
	await process_frame


## Shadows go into a mask only the mask camera sees, and one plane under the game camera darkens
## the ground from it, so overlapping faces and shadows can't stack into dark patches.
func shadows() -> void:
	var g := make_game()
	await process_frame
	g.launch()
	run(g, 3.0)
	check(not g.shadows.is_empty(), "models cast shadows")
	var ok := true
	for sh in g.shadows:
		ok = ok and sh.layers == Game.SHADOW_LAYER
	check(ok, "every shadow is drawn only into the shadow mask")
	check(g.cam.cull_mask & Game.SHADOW_LAYER == 0 and g.shadow_cam.cull_mask == Game.SHADOW_LAYER, "the game camera skips shadow casters, the mask camera sees only them")
	check(g.shadow_cam.global_transform.is_equal_approx(g.cam.global_transform) and is_equal_approx(g.shadow_cam.fov, g.cam.fov), "the mask camera follows the game camera")
	var c := g.cam.global_position
	check(is_equal_approx(g.shadow_plane.global_position.y, Game.SHADOW_Y) and Vector2(g.shadow_plane.global_position.x - c.x, g.shadow_plane.global_position.z - c.z).length() < 0.01, "the shadow plane lies under the camera at shadow height")
	var hw := (g.shadow_plane.mesh as PlaneMesh).size.x * 0.5
	check(hw >= g.cam.far, "the shadow plane reaches the far plane")
	g.queue_free()
	await process_frame


## The chase camera looks far across the land: the ground must run past the fog's end in every
## direction it can see, at both flanks of the reach and up high, so no edge of the world shows.
## Bullets must read on every world's ground (Guillaume, 2026-11-23: invisible on sand; then a
## black outline was ugly): each shot has a soft halo, and enemy fire takes its world's `fire`
## colour, which must stand apart from every colour of that world's ground.
func readable_fire() -> void:
	print("readable fire")
	var g := make_game()
	await process_frame
	g.launch()
	var b := g.bullet(Vector3(0, Rules.PY, g.frame_z), Vector3.ZERO)
	var sh := g.new_shot(g.ppos, Vector3(0, 0, -40), 1.0)
	for o: Game.Obj in [b, sh]:
		var h := o.node.get_node_or_null("halo") as MeshInstance3D
		check(h != null and h.material_override is ShaderMaterial and h.scale.x > 0.2, "%s glows with a soft halo" % o.kind)
		check(o.node.get_node_or_null("rim") == null, "%s has no dark outline" % o.kind)
	var keep := Models.theme
	var lost := []
	for theme: String in Models.THEMES:
		Models.theme = theme
		var d := Models.fire_col()
		for i in 41:
			var c := Models.ground_col(-1.0 + i * 0.05)
			if Vector3(c.r - d.r, c.g - d.g, c.b - d.b).length() < 0.5:
				lost.append("%s %s" % [theme, c.to_html(false)])
	Models.theme = keep
	check(lost.is_empty(), "each world's fire colour stands out from its ground %s" % ("" if lost.is_empty() else str(lost)))
	g.queue_free()
	await process_frame


func world_edges() -> void:
	print("world edges")
	var g := make_game()
	await process_frame
	g.launch()
	g.spawn_fortress()
	g.begin_approach()
	g.begin_pov()
	var fog := 0.0
	for we in g.find_children("*", "WorldEnvironment", false, false):
		fog = (we as WorldEnvironment).environment.fog_depth_end
	check(fog > 0.0, "the world has depth fog")
	for o: Vector2 in [Vector2(-Rules.POV_REACH.x, 0), Vector2(Rules.POV_REACH.x, 0), Vector2(0, Rules.POV_REACH.y)]:
		g.off = o
		for i in 120:
			g.off = o
			g.step(DT)
		var cam: Vector3 = g.cam.global_position
		var box := AABB()
		var first := true
		for k in g.chunks:
			var mi: MeshInstance3D = g.chunks[k]
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var ok := box.position.x <= cam.x - fog and box.end.x >= cam.x + fog and box.position.z <= cam.z - fog
		check(ok, "ground runs past the fog from the chase camera at %s (x %.0f..%.0f, z to %.0f, camera %.0f, %.0f)" % [
			o, box.position.x, box.end.x, box.position.z - cam.z, cam.x, cam.z])
	g.queue_free()
	await process_frame


## The hangar on tall and short phones: the panel is whole on screen (its LAUNCH button
## included, with a bottom margin), below the title, and the ship idles in the sky above it.
## A tall phone once pushed the panel's bottom off the screen and the ship sat on its top edge.
## Each screen is a SubViewport as wide as the game's 720 px and as tall as the phone's ratio.
func hangar_fits() -> void:
	print("hangar layout")
	for res: Vector2i in [Vector2i(1080, 2410), Vector2i(720, 1280), Vector2i(1080, 1920), Vector2i(1200, 1600)]:
		var sv := SubViewport.new()
		sv.size = Vector2i(720, roundi(720.0 * res.y / res.x))
		root.add_child(sv)
		var g: Game = load("res://scenes/main.tscn").instantiate()
		g.save_path = SAVE
		g.driven = true
		sv.add_child(g)
		await process_frame
		g.new_build = 99   # the update button makes the panel its tallest
		g.hud.refresh_hangar()
		for i in 3:
			await process_frame
		g.step(DT)
		var vp := g.view_size()
		var p := g.hud.hangar_panel
		var r := p.get_global_rect()
		var top := r.position.y   # the global rect is the scaled panel
		var bottom := r.end.y
		check(absf(top - g.hud.hangar_panel_top()) < 1.0, "%s: the ship is placed against the panel's real top" % res)
		check(vp.y == sv.size.y and bottom <= vp.y - 20.0 and top >= Hud.HANGAR_TOP - 1.0,
			"%s: the hangar panel fits (%.0f to %.0f of %.0f)" % [res, top, bottom, vp.y])
		var sy := g.cam.unproject_position(g.ppos).y
		check(sy > Hud.HANGAR_TOP and sy < top - 40.0, "%s: the ship idles above the panel (y %.0f)" % [res, sy])
		sv.free()


## Guillaume (2026-11-23): more detailed houses, rocks on the beaches and other scenery, drawn
## big, then comically big, with fun landmarks in every world (a stepped pyramid in the dunes, a
## giant rubber duck, a snowman, a stone head); the tallest still stays under the flight altitude.
func scenery() -> void:
	print("scenery")
	var g := make_game()
	await process_frame
	var want := {"coast": ["house", "rocks", "sea rocks", "palm", "driftwood", "boat", "lighthouse", "broadleaf", "conifer", "bush", "duck"],
		"dunes": ["boulder", "cactus", "adobe", "pyramid", "meteorite"], "city": ["building", "duck", "water tower", "car", "bridge", "expressway", "park", "helipad", "fire", "ruin", "crater", "wreck", "rubble"], "ice": ["pine", "snowman"],
		"volcano": ["spire", "stone head"]}
	var before := Models.theme
	for theme: String in want:
		Models.theme = theme
		Models.scenery.clear()
		Models.marks.clear()
		var top := -INF
		var flames := -INF
		for k in 16:
			var m := Models.ground_chunk(g.noise, -k * Game.CHUNK, Vector2(Game.CHUNK_W, Game.CHUNK), 2.0)
			for i in m.get_surface_count():
				for v: Vector3 in m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]:
					top = maxf(top, v.y)
			# the city's flames at their tallest flicker (tongues up to 1.9 s, stretched by up to 1.45)
			for f: Dictionary in City.fires if theme == "city" else []:
				flames = maxf(flames, f.p.y + f.s * 1.9 * 1.45)
		for mk: Dictionary in Models.marks:
			var lm := Models.landmark(mk.kind, mk.r)
			top = maxf(top, mk.pos.y + Models.mark_h(mk.kind) + lm.get_aabb().end.y)
		for kind: String in want[theme]:
			check(Models.scenery.get(kind, 0) > 0, "%s has %s (%d)" % [theme, kind, Models.scenery.get(kind, 0)])
		check(top < Rules.PY - 0.5, "%s: scenery stays under the flight altitude (top %.1f)" % [theme, top])
		if theme == "city":
			check(flames < Rules.PY - 0.5 and City.SMOKE_TOP < Rules.PY - 0.5, "city: flames (%.1f) and smoke stay under the ship" % flames)
		if theme == "coast":
			check(Models.scenery.get("house", 0) >= 12, "villages, not just the odd farmhouse (%d houses)" % Models.scenery.get("house", 0))
	Models.theme = before
	g.queue_free()
	await process_frame


## Guillaume (2026-11-23): prominent scenery, the lighthouse for one, can be destroyed.
func landmarks() -> void:
	print("landmarks")
	var g := make_game()
	await process_frame
	g.launch()
	var found: Game.Obj = null
	for i in int(60.0 / DT):
		g.hp = 3
		g.step(DT)
		for f in g.foes:
			if g.landmark(f) and not f.dead and g.on_screen(f):
				found = f
		if found:
			break
	check(found != null, "a landmark comes into play in the vertical stage")
	if found == null:
		g.queue_free()
		return
	check(found.ground and found.node.get_parent() in g.chunks.values(), "it is part of the ground (%s)" % found.kind)
	# Guillaume: landmarks fell before they even showed; they take hits only well inside the screen
	var keep := found.pos
	for i in 5:
		found.pos.z += g.frame_z + g.view_top + 1.0 - g.seen(found.pos).z
	var hp0 := found.hp
	var probe := g.new_shot(g.seen(found.pos), Vector3.ZERO, 1.0)
	g.collide(DT)
	check(not probe.dead and found.hp == hp0, "a landmark at the top edge isn't hurt yet")
	probe.dead = true
	found.pos = keep
	check(found.hp >= 18.0, "landmarks are sturdy (%s: %.0f hp)" % [found.kind, found.hp])
	var kills: int = g.run.kills
	var score: int = g.run.score
	var picks := g.picks.size()
	var parent := found.node.get_parent()
	var children := parent.get_child_count()
	g.damage(found, 1.0)
	check(not found.dead and found.hit > 0.0, "a hit landmark flashes")
	g.damage(found, 999.0)
	check(found.dead and g.run.score > score and g.run.kills == kills, "shooting it down scores but isn't a kill")
	check(g.picks.size() > picks, "it drops scrap")
	check(parent.get_child_count() == children + 1 and g.ruined.size() == 1, "a ruin is left where it stood")
	# the chase lets standing landmarks go without blowing them up
	g.step(DT)
	var standing := 0
	for m: Dictionary in g.marks:
		if is_instance_valid(m.node):
			standing += 1
	g.spawn_fortress()
	g.begin_approach()
	g.step(DT)
	var after := 0
	for f in g.foes:
		if g.landmark(f):
			after += 1
	check(after == 0, "no landmark is a target in the chase")
	var still := 0
	for m: Dictionary in g.marks:
		if is_instance_valid(m.node):
			still += 1
	check(still >= standing - 1, "landmarks still stand in the chase (%d of %d)" % [still, standing])
	g.to_hangar()
	check(g.ruined.is_empty(), "back in the hangar, ruined ground is rebuilt for the next sortie")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage game test")
	rules()
	await shadows()
	await controls()
	await slow_pause()
	await pause_menu()
	await aiming()
	await ramming()
	await swipe()
	await lingering()
	await scenery()
	await landmarks()
	await stage()
	await power()
	await death()
	await readable_fire()
	await world_edges()
	await hangar_fits()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
