extends SceneTree
## Replay tiers, medals and the medal track: Normal is open and clearing a tier opens the next
## one for that stage, Nova and Supernova make enemies tougher (faster bullets, more fire, more
## hit points, two ships on Supernova), the four medals are judged from a run, medals are
## counted once and saved, and the medal track unlocks ship colours that repaint the ship.

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
	var b0: Button = vg.hud._stage_btns[0]
	check(b0.disabled and b0.text.contains("LOCKED"), "on the Nova tab a stage not yet cleared is locked")
	vg.hud.select_tier(0)
	check(not vg.hud._stage_btns[0].disabled, "on the Normal tab it is open")
	vg.start_stage(0, "lance", 2)
	check(vg.G.tier == 0, "starting a closed tier plays the highest open one")
	vg.update()
	var normal_speed: float = vg.bspeed()
	var e: Dictionary = vg.E("drifter", 60, 150)
	var normal_hp: float = e.hp
	check(vg.G.foes == 1, "spawned enemies are counted for Sweep")
	vg.kill_e(e)
	check(vg.G.foes_killed == 1, "kills are counted for Sweep")
	var g: Dictionary = vg.E("generator", 20, 150)
	vg.kill_e(g)
	check(vg.G.breakables == 1 and vg.G.broken == 1 and vg.G.foes == 1, "generators count for Breaker, not Sweep")
	vg.hurt()
	check(vg.G.hits == 1, "hull hits are counted for Untouched")
	vg.G.clear_t = 1
	vg.finish(true)
	check(vg.prog.cleared("w1s1", 0) and vg.prog.unlocked("w1s1", 1), "clearing a stage saves the clear and opens Nova")
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
	vg.prog.stages["w1s4"] = {m = [15, 0, 0], c = 1}
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
	check(vg.hud._btn_medals.text.begins_with("MEDALS %d" % vg.prog.total()), "the menu shows the medal count")
	vg.hud.show_screen("medals")
	check(vg.hud.medals_scr.visible and not vg.hud.menu_scr.visible, "the medals screen opens from the menu")

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
