extends SceneTree
## Replay tiers, medals and the medal track: stages open one by one on each tier (clear the
## previous stage, medals not needed; old saves keep what they reached), the stage map shows and
## enforces it, clearing a tier opens the next one for that stage, Nova and Supernova make enemies tougher (faster bullets, more fire, more
## hit points, two ships on Supernova), the four medals are judged from a run, medals are
## counted once and saved, the medal track unlocks ship colours that repaint the ship, runs bank
## flux, and flux buys ship levels that raise damage.

var vg: Node3D
var fails := 0


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


func run(over := {}) -> Dictionary:
	var s := {cleared = true, foes = 20, foes_killed = 18, breakables = 4, broken = 4, hits = 0, boss_ticks = 600, end = "big:shell", tier = 0}
	s.merge(over, true)
	return s


func _initialize() -> void:
	print("Star Breaker progress test")

	# --- judging medals ---
	check(Progress.judge(run()) == ["sweep", "untouched", "breaker", "swift"], "a perfect clear takes all four medals")
	check(Progress.judge(run({cleared = false})).is_empty(), "a failed run takes no medals")
	check(not Progress.judge(run({foes_killed = 17})).has("sweep"), "Sweep needs 90% of enemies (17 of 20 is not enough)")
	check(not Progress.judge(run({hits = 1})).has("untouched"), "one hit loses Untouched")
	check(not Progress.judge(run({broken = 3})).has("breaker"), "one wall left standing loses Breaker")
	var par := Progress.par_ticks("big:shell", 0)
	check(not Progress.judge(run({boss_ticks = par + 1})).has("swift"), "slower than par loses Swift")
	check(Progress.par_ticks("big:shell", 2) > par, "tougher tiers give the boss more par time")
	check(Progress.par_ticks("someboss", 0) == Progress.par_ticks("bloom", 0), "a world boss not listed gets a world boss's par")

	# --- unlocks and the track ---
	var p := Progress.new()
	check(p.unlocked("w1s1", 0) and not p.unlocked("w1s1", 1) and not p.unlocked("w1s1", 2), "only Normal is open at first")
	var r := p.record("w1s1", 0, true, ["sweep", "breaker"])
	check(r.unlocked_tier == 1 and p.unlocked("w1s1", 1) and not p.unlocked("w1s1", 2), "clearing Normal opens Nova, not Supernova")
	check(not p.unlocked("w1s2", 1), "tiers open per stage")
	check(r.new_medals == ["sweep", "breaker"] and p.total() == 2, "medals are counted")
	check(r.rewards.size() == 1 and r.rewards[0].scheme == "ember", "2 medals unlock the first ship colour")
	r = p.record("w1s1", 0, true, ["sweep", "untouched"])
	check(r.new_medals == ["untouched"] and p.total() == 3 and r.unlocked_tier == -1, "a medal already held isn't counted twice")
	r = p.record("w1s1", 1, false, [])
	check(r.new_medals.is_empty() and not p.unlocked("w1s1", 2), "failing Nova changes nothing")
	check(p.best_open("w1s1", 2) == 1 and p.best_open("w1s2", 2) == 0, "asking for a closed tier falls back to the highest open one")
	check(not p.set_paint("lance", "violet") and p.set_paint("lance", "ember"), "only unlocked colours can be chosen")
	var cfg := ConfigFile.new()
	p.save_to(cfg)
	var q := Progress.new()
	q.load_from(cfg)
	check(q.total() == 3 and q.unlocked("w1s1", 1) and q.paint_of("lance").id == "ember", "progress and colours survive a save and load")
	check(Progress.max_total() == VStage.STAGES.size() * 12, "each stage holds 12 medals (4 on each of 3 tiers)")

	# --- stage order: a stage opens once the one before it is cleared, on each tier ---
	var o := Progress.new()
	check(o.open(0, 0) and not o.open(1, 0), "a new save has only the first stage open")
	check(o.next_stage(0) == 0 and o.next_stage(1) == -1, "the next stage is the first one; nothing is open on Nova yet")
	r = o.record("w1s1", 0, false, [])
	check(not o.open(1, 0) and r.unlocked_next == -1, "losing every ship doesn't open the next stage")
	r = o.record("w1s1", 0, true, [])
	check(o.open(1, 0) and r.unlocked_next == 1, "clearing a stage without medals opens the next one")
	check(o.open(0, 1) and not o.open(1, 1), "Nova: stage 1 opens, stage 2 still needs Normal stage 2")
	o.record("w1s2", 0, true, [])
	check(not o.open(1, 1), "Nova stage 2 also needs Nova stage 1")
	o.record("w1s1", 1, true, [])
	check(o.open(1, 1) and not o.open(2, 1) and o.next_stage(1) == 1, "Nova stage 2 opens after Nova stage 1 and Normal stage 2")
	check(not o.open(2, 2), "Supernova follows its own chain")
	for k in range(2, 8):
		o.record("w1s%d" % (k + 1), 0, true, [])
	check(o.open(8, 0) and not o.open(9, 0) and o.next_stage(0) == 8, "clearing world 1's boss opens world 2")
	r = o.record("w1s8", 0, true, [])
	check(r.unlocked_next == -1, "a replay doesn't announce an unlock again")
	# saves from before the rule could clear stages in any order: everything they reached stays open
	var old := Progress.new()
	old.stages = {w1s1 = {m = [0, 0, 0], c = 1}, w1s5 = {m = [0, 0, 0], c = 1}}
	check(old.open(3, 0) and old.open(4, 0) and old.open(5, 0) and not old.open(6, 0), "an old save keeps every stage up to its furthest clear and the one after it")
	check(old.next_stage(0) == 1, "an old save's next stage is the first gap")
	check(not old.open(4, 1), "but Nova still needs the stage cleared on Normal")

	# --- in the game ---
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame
	vg.prog = Progress.new()
	vg.hud.prog = vg.prog
	vg.hud.select_tier(1)
	check(not vg.hud.map.is_open(0) and vg.hud.stage_label(0).contains("LOCKED"), "on the Nova tab a stage not yet cleared is locked")
	var tapped: Array = []
	vg.hud.stage_chosen.connect(func(i, _s): tapped.append(i))
	vg.hud.map.tap_stage(0)
	check(tapped.is_empty() and vg.hud.map._note.to_upper().contains("NORMAL"), "tapping a locked stage says what to clear instead of starting it")
	vg.hud.select_tier(0)
	check(vg.hud.map.is_open(0) and not vg.hud.map.is_open(1), "on the Normal tab stage 1 is open and stage 2 is locked")
	check(vg.hud.stage_label(0).contains("NEXT"), "the map marks the next stage")
	vg.hud.map.tap_stage(1)
	check(tapped.is_empty() and vg.hud.map._note.to_upper().contains("SPORE FIELDS"), "a locked stage names the stage to clear first")
	vg.hud.map.tap(vg.hud.map.node_pos(0))
	check(tapped == [0], "tapping an open stage on the map starts it")
	vg.hud.map.tap(Vector2(vg.hud.map.size.x * (3.5 / 6.0), 40))
	check(vg.hud.world_sel == 3 and vg.hud.map.world == 3, "tapping a world in the strip shows its route")
	check(not vg.hud.map.world_open(3) and vg.hud.map.world_cleared(0) == 0, "a world not reached is locked")
	vg.to_menu()
	vg.start_stage(0, "lance", 2)
	check(vg.G.tier == 0, "starting a closed tier plays the highest open one")
	vg.update()
	var normal_speed: float = vg.bspeed()
	var f0: int = vg.G.foes
	var e: Dictionary = vg.E("drifter", 60, 150)
	var normal_hp: float = e.hp
	check(vg.G.foes == f0 + 1, "spawned enemies are counted for Sweep")
	var k0: int = vg.G.foes_killed
	vg.kill_e(e)
	check(vg.G.foes_killed == k0 + 1, "kills are counted for Sweep")
	var b0n: int = vg.G.breakables
	var r0: int = vg.G.broken
	var g: Dictionary = vg.E("generator", 20, 150)
	vg.kill_e(g)
	check(vg.G.breakables == b0n + 1 and vg.G.broken == r0 + 1 and vg.G.foes == f0 + 1, "generators count for Breaker, not Sweep")
	vg.hurt()
	check(vg.G.hits == 1, "hull hits are counted for Untouched")
	vg.G.clear_t = 1
	vg.finish(true)
	check(vg.prog.cleared("w1s1", 0) and vg.prog.unlocked("w1s1", 1), "clearing a stage saves the clear and opens Nova")
	check(vg.prog.open(1, 0) and vg.hud._result_lines.text.contains("STAGE 2 CRYSTAL GATE UNLOCKED"), "and opens the next stage, which the result screen says")
	check(vg.hud._result_next.visible, "Next is offered once the next stage is open")
	check(vg.hud._result_tier.visible and vg.hud._result_tier.text == "REPLAY ON NOVA", "the result screen offers to replay on Nova")
	check(vg.hud._result_lines.text.contains("NOVA UNLOCKED"), "the result screen says Nova is unlocked")
	vg.hud._result_tier.pressed.emit()
	check(vg.mode == "play" and vg.G.tier == 1 and vg.G.stage == 0, "replay on Nova starts the same stage on Nova")
	vg.update()
	check(vg.bspeed() > normal_speed * 1.15, "Nova bullets are faster")
	var e2: Dictionary = vg.E("drifter", 60, 150)
	check(absf(e2.hp - normal_hp * 1.5) < 0.01, "Nova enemies have 50% more hit points")
	check(vg.tier_mul("fire") > 1.0, "Nova enemies fire more often")
	check(vg.hud.stage_name.contains("Nova"), "the HUD names the tier")
	vg.G.clear_t = 1
	vg.finish(true)
	vg.start_stage(0, "warden", 2)
	check(vg.G.tier == 2 and vg.G.lives == 2, "Supernova opens after Nova and gives two ships")

	# --- ship colours ---
	vg.prog.stages["w1s2"] = {m = [15, 15, 15], c = 7}
	vg.prog.stages["w1s3"] = {m = [15, 15, 15], c = 7}
	check(not vg.prog.set_paint("lance", "obsidian"), "Obsidian Lance needs 32 medals")
	vg.prog.stages["w1s4"] = {m = [15, 15, 15], c = 7}
	check(vg.prog.total() >= 32 and vg.prog.set_paint("lance", "obsidian"), "32 medals open Obsidian Lance")
	vg.start_stage(0, "lance", 0)
	var found := false
	var stack: Array = [vg.ship_m]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var m := (n as MeshInstance3D).get_surface_override_material(0)
			if m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color.is_equal_approx(Color("3a3648")):
				found = true
		stack.append_array(n.get_children())
	check(found, "the chosen colour repaints the ship")
	check(Models.M.hull.albedo_color.is_equal_approx(Color("dfe8f2")), "repainting leaves the shared stock material alone")
	vg.hud.refresh_progress()
	check(vg.hud._btn_medals.text.contains("MEDALS %d" % vg.prog.total()) and vg.hud._btn_medals.text.contains("FLUX"), "the menu shows flux and the medal count")
	vg.hud.show_screen("medals")
	check(vg.hud.medals_scr.visible and not vg.hud.menu_scr.visible, "the medals screen opens from the menu")

	# --- flux and ship levels ---
	check(Progress.power(1) == 1.0 and is_equal_approx(Progress.power(Progress.MAX_LEVEL), 2.0), "ship levels add up to double damage at level 50")
	check(Progress.level_cost(1) < Progress.level_cost(10) and Progress.level_cost(10) < Progress.level_cost(49), "each level costs more than the last")
	var early := 0
	for lv in range(1, 10):
		early += Progress.level_cost(lv)
	check(early < 2000, "level 10 costs under 2,000 flux (about 5 Normal stages)")
	var fp := Progress.new()
	check(fp.bank_run(25000, 0, 2) == 250 + 2 * Progress.MEDAL_FLUX[0], "a run banks 1 flux per 100 points plus a bonus per new medal")
	check(not fp.buy_level("warden") or fp.level("warden") == 2, "levelling spends flux")
	fp.flux = 0
	check(not fp.buy_level("lance") and fp.level("lance") == 1, "no level without the flux")
	fp.flux = 100000
	check(fp.buy_level("lance") and fp.level("lance") == 2 and fp.flux == 100000 - Progress.level_cost(1), "a level up costs its price")
	var fc := ConfigFile.new()
	fp.save_to(fc)
	var fq := Progress.new()
	fq.load_from(fc)
	check(fq.flux == fp.flux and fq.level("lance") == 2, "flux and levels are saved")
	vg.prog.flux = 0
	vg.prog.levels = {lance = 1, warden = 1}
	vg.start_stage(0, "lance", 0)
	var e3: Dictionary = vg.E("drifter", 60, 150)
	var h3: float = e3.hp
	vg.dmg_e(e3, 1)
	var d1: float = h3 - e3.hp
	vg.prog.levels.lance = Progress.MAX_LEVEL
	vg.start_stage(0, "lance", 0)
	var e4: Dictionary = vg.E("drifter", 60, 150)
	var h4: float = e4.hp
	vg.dmg_e(e4, 1)
	check(is_equal_approx(h4 - e4.hp, d1 * 2.0), "a level 50 ship deals double damage")
	vg.G.score = 30000
	vg.G.clear_t = 1
	var f0b: int = vg.prog.flux
	vg.finish(true)
	check(vg.prog.flux >= f0b + 300 and vg.hud._result_lines.text.contains("FLUX"), "a cleared run banks its flux and the result says how much")
	vg.prog.levels.warden = 1
	vg.prog.flux = Progress.level_cost(1)
	vg.hud.refresh_progress()
	check(not vg.hud._level_btns.warden.disabled, "the hangar's level up button is on when you can afford it")
	vg.hud._level_btns.warden.pressed.emit()
	check(vg.prog.level("warden") == 2 and vg.prog.flux == 0 and vg.hud._level_btns.warden.disabled, "levelling up from the hangar spends the flux")
	check(vg.hud._level_lbls.warden.text.contains("LV 2"), "the hangar shows the new level")

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
