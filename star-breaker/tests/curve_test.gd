extends SceneTree
## The campaign gets harder stage by stage and the ships come in power order (Guillaume,
## 2026-11-22: "with the same ship I can win almost any level"): `VStage.heat` rises through
## each world and from world to world, waves get bigger and closer, enemies tougher and faster
## to fire, small flyers get a parting shot from mid-campaign, and every ship after the two
## starters hits harder than they do, in the order they unlock.

var vg: Node3D
var fails := 0


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


func flyers(i: int) -> int:
	var n := 0
	for e in VStage.build(i):
		if not e.type in ["prop", "barrier", "run", "end", "carrier", "generator"]:
			n += int(e.get("n", 1))
	return n


func _initialize() -> void:
	print("Star Breaker difficulty curve and ship order test")
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame

	# --- the curve ---
	var n: int = VStage.STAGES.size()
	check(VStage.heat(0) == 0.0 and VStage.heat(n - 1) == 1.0, "heat runs from 0 at world 1 stage 1 to 1 at the last stage")
	var rising := true
	var breath := true
	for i in range(1, n):
		if i % VStage.PER_WORLD:
			rising = rising and VStage.heat(i) > VStage.heat(i - 1)
		else:
			# a new world: easier than the boss stage before it, harder than that world's start
			breath = breath and VStage.heat(i) < VStage.heat(i - 1) and VStage.heat(i) > VStage.heat(i - VStage.PER_WORLD)
	check(rising, "every stage of a world is harder than the one before")
	check(breath, "a new world opens under the last stage of the world before, over that world's first")
	var per_world := []
	for w in 6:
		var c := 0
		for j in VStage.PER_WORLD - 1:
			c += flyers(w * VStage.PER_WORLD + j)
		per_world.append(c)
	var more := true
	for w in range(1, 6):
		more = more and per_world[w] > per_world[0] and per_world[w] <= per_world[5]
	check(more and per_world[5] > per_world[0] * 2, "later worlds send more enemies, the last the most and over twice the first (%s)" % str(per_world))
	check(VStage.build(n - 2).any(func(e): return e.type == VStage.WORLDS[5].big and e.d < VStage.STAGES[n - 2].length - 200.0),
		"big flyers escort the waves late in the campaign")

	# --- what a stage does with it ---
	vg.start_stage(0, "lance", 0)
	var hp0: float = vg.E("seeker", 60, 150, {vx = 0.0, vy = -1.3}).hp
	var f0: float = vg.fire_mul()
	var b0: float = vg.bspeed()
	check(vg.volley() == 0, "enemies fire single shots at the start")
	vg.start_stage(n - 1, "lance", 0)
	var late: Dictionary = vg.E("seeker", 60, 150, {vx = 0.0, vy = -1.3})
	check(late.hp > hp0 * 2.0, "enemies are over twice as tough in the last stage (%s to %s)" % [hp0, late.hp])
	check(vg.fire_mul() > f0 * 1.8 and vg.bspeed() > b0 * 1.3, "they fire nearly twice as often, with faster bullets")
	check(vg.volley() == 2, "and in fuller patterns")
	var tur: Dictionary = vg.E("turret", 60, 150, {wy = vg.G.scroll + 150.0})
	tur.cd = 0
	vg.P.merge({entering = false, y = 40.0, inv = 999}, true)
	vg.G.eb.clear()
	vg._update_enemies()
	check(vg.G.eb.size() == 3, "a late turret fires a fan of three (%d)" % vg.G.eb.size())

	# --- parting shots ---
	vg.G.eb.clear()
	var shot := 0
	for k in 40:
		var e: Dictionary = vg.E("drifter", 60, 180, {move = "sine", amp = 0.0, x0 = 60.0})
		e.erase("glide")
		vg.kill_e(e)
	shot = vg.G.eb.size()
	check(shot > 8 and shot < 30, "late on, some small flyers fire once as they die (%d of 40)" % shot)
	vg.G.eb.clear()
	for k in 20:
		vg.kill_e(vg.E("drifter", vg.P.x + 10.0, vg.P.y + 30.0, {move = "sine", amp = 0.0, x0 = 60.0}))
	check(vg.G.eb.is_empty(), "never from close to the ship")
	for k in 20:
		vg.kill_e(vg.E("turret", 60, 180, {wy = vg.G.scroll + 180.0}))
	check(vg.G.eb.is_empty(), "ground targets have no parting shot")
	vg.start_stage(0, "lance", 0)
	vg.P.merge({entering = false, y = 40.0}, true)
	for k in 40:
		vg.kill_e(vg.E("drifter", 60, 180, {move = "sine", amp = 0.0, x0 = 60.0}))
	check(vg.G.eb.is_empty(), "and nothing fires back from the grave early in the campaign")

	# --- ships in power order ---
	var order: Array = VShips.ORDER
	var sorted_unlocks := true
	for i in range(1, order.size()):
		sorted_unlocks = sorted_unlocks and int(VShips.KITS[order[i]].unlock) >= int(VShips.KITS[order[i - 1]].unlock)
	check(order.size() == 12 and sorted_unlocks, "the twelve ships unlock in the order they are listed")
	check(order[0] == "lance" and order[1] == "warden" and VShips.might("lance") == 1.0 and VShips.might("warden") == 1.0,
		"Lance and Warden are the starters, at base power")
	var stronger := true
	for i in range(2, order.size()):
		stronger = stronger and VShips.might(order[i]) > 1.0
	check(stronger, "every ship unlocked later hits harder than the starters")
	vg.prog.levels["hornet"] = 1
	vg.start_stage(0, "hornet", 0)
	check(is_equal_approx(vg.G.power, VShips.might("hornet")), "a ship's might goes into every hit")
	var dr: Dictionary = vg.E("shell", 60, 150)
	var h0: float = dr.hp
	vg.dmg_e(dr, 2.0)
	check(is_equal_approx(h0 - dr.hp, 2.0 * VShips.might("hornet")), "a 2 point hit from Hornet takes %s" % (h0 - dr.hp))
	check(vg.STORM_DMG < vg.BEAM_DMG[4] / 2.0, "Lance's Storm hits for less than half a Nova: free, so light")
	vg.to_menu()
	vg.hud.show_screen("medals")
	vg.hud.select_ship("hornet")
	var lbl: String = vg.hud._lock_lbl.text if vg.hud._lock_lbl.visible else vg.hud._level_lbls["hornet"].text
	check(lbl.contains("POWER 12 / 12"), "the hangar prints a ship's place in the power order (%s)" % lbl.replace("\n", " | "))

	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
