extends SceneTree
## The game (portrait): it opens on the stage menu, drag moves the ship 1:1,
## the main weapon fires while the thumb is down, lifting fires Lance's beam (LV 1 up to the
## Nova) or flings and recalls Warden's pod, holding to the end of the charge bar loads each
## ship's ultimate (Lance's Storm, Warden's Shatter), barriers and
## bullets cost hull points, losing every ship fails the stage, and the three stages of world 1
## end with their mid-bosses and the Bloom Mother.

var vg: Node3D
var fails := 0


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


## Runs `n` ticks with the given input. `god` keeps the ship invincible.
func tick(n := 1, hold := false, dx := 0.0, dy := 0.0, ult := false, god := true) -> void:
	for i in n:
		vg.inp = {hold = hold, fire = hold, dx = dx if i == 0 else 0.0, dy = dy if i == 0 else 0.0, ult = ult and i == 0, pause = false}
		if god and not vg.P.is_empty():
			vg.P.inv = maxi(vg.P.inv, 2)
		vg.update()
		vg._process(1.0 / 60.0)


## Ticks until the ship has flown in.
func settle() -> void:
	var t := 0
	while vg.P.entering and t < 200:
		t += 1
		tick()


func _initialize() -> void:
	print("Star Breaker play test")
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame
	check(vg.mode == "menu" and vg.hud.menu_scr.visible, "the game starts on its stage menu")

	# --- Lance ---
	vg.hud.stage_chosen.emit(0, "lance")
	check(vg.mode == "play" and vg.G.ship == "lance", "picking stage 1 with Lance starts it")
	settle()
	check(not vg.P.entering and vg.P.y >= 40, "the ship flies in from the bottom")
	var x0: float = vg.P.x
	var y0: float = vg.P.y
	tick(1, true, 10.0, 5.0)
	check(absf(vg.P.x - (x0 + 10.0)) < 0.01 and absf(vg.P.y - (y0 + 5.0)) < 0.01, "the ship moves exactly as far as the thumb")
	var shots: int = vg.G.pb.size()
	tick(6, true)
	check(vg.G.pb.size() > shots, "the main weapon fires while the thumb is down")
	tick(30, false)
	for b in vg.G.pb:
		b.dead = true
	vg._sweep(vg.G.pb)
	tick(1, false)
	var fired: int = vg.G.pb.size()
	tick(12, false)
	check(vg.G.pb.size() == fired, "with the thumb up nothing fires")
	# a short touch charges nothing: lifting fires no beam
	tick(20, true)
	tick(1, false)
	check(vg.G.beams.is_empty(), "a quick re-grip fires no beam")
	check(vg.G.slow > 0, "lifting the thumb slows time for a moment")
	tick(40, false)
	# hold for LV 1, then lift
	tick(60, true)
	check(vg.charge_lv(vg.P.charge) == 1, "holding 1 s charges the beam to LV 1")
	tick(1, false)
	check(vg.G.beams.size() == 1 and vg.G.beams[0].lv == 1 and not vg.G.beams[0].nova, "lifting fires a LV 1 beam")
	tick(60, false)
	check(vg.G.beams.is_empty(), "the beam fades")
	# on a phone a touch also arrives as a made-up mouse click, ahead of the touch itself: the
	# real touch decides the hold, so lifting the finger still releases
	var fake := func(pressed: bool) -> void:
		var mb := InputEventMouseButton.new()
		mb.device = InputEvent.DEVICE_ID_EMULATION
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = Vector2(270, 900)
		vg._input(mb)
	var finger := func(pressed: bool) -> void:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.pressed = pressed
		t.position = Vector2(270, 900)
		vg._input(t)
	fake.call(true)
	finger.call(true)
	vg.poll_input()
	var held_down: bool = vg.inp.hold
	finger.call(false)
	fake.call(false)
	vg.poll_input()
	check(held_down and not vg.inp.hold, "on a phone, lifting the finger ends the hold (the mouse copy of a touch is ignored)")
	vg._touch_seen = false
	vg._mouse_down = false
	vg._touch_id = -1
	# the Nova burns bullets in its path
	tick(250, true)
	check(vg.charge_lv(vg.P.charge) == 4, "holding 4 s reaches the Nova")
	vg.bullet(vg.P.x, vg.P.y + 40, 0, -0.1)
	var nb: Dictionary = vg.G.eb.back()
	tick(1, false)
	check(vg.G.beams.size() == 1 and vg.G.beams[0].nova, "lifting fires the Nova")
	tick(3, false)
	check(not vg.G.eb.has(nb), "the Nova burns enemy bullets")
	tick(60, false)
	# the beam damages enemies in its line
	var e: Dictionary = vg.E("shell", vg.P.x, vg.P.y + 60, {hold = 0.0})
	var hp0: float = e.hp
	tick(120, true)
	tick(1, false)
	tick(3, false)
	check(e.hp < hp0 - 10 or e.get("dead", false), "the beam hits an enemy above the ship")
	e.dead = true
	tick(60, false)

	# Lance's ultimate, the Storm: the charge bar's stage after the Nova, no kills needed
	check(not "ult" in vg.P and not "ult_rect" in vg.hud, "no ship has a separate ultimate gauge any more")
	tick(60, false)
	tick(vg.ULT_AT + 20, true)
	check(vg.P.charge == vg.ULT_AT, "with no kills at all, holding runs the charge on past the Nova to the Storm")
	check(vg.hud.charge >= 1.0 and vg.hud.charge_marks[3] < 1.0, "the bar shows the Storm as its last stage, after the Nova")
	var foes := []
	for k in 5:
		foes.append(vg.E("drifter", 15 + k * 24, 120 + (k % 2) * 60, {move = "sine", amp = 0.0, ph = 0.0, x0 = 15.0 + k * 24}))
	var big: Dictionary = vg.E("shell", 30, 190, {hold = 0.0})
	var bhp: float = big.hp
	var far: Dictionary = vg.E("drifter", 60, vg.view.end.y + 40, {move = "sine", amp = 0.0, ph = 0.0, x0 = 60.0})
	var fhp: float = far.hp
	vg.bullet(100, 200, 0, 0)
	var beams: int = vg.G.beams.size()
	tick(1, false)
	var on_screen := 0
	for en in vg.G.enemies:
		if vg.view.grow(-1.0).has_point(Vector2(en.x, en.y)):
			on_screen += 1
	check(vg.G.has("storm") and vg.G.beams.size() == beams, "lifting at the Storm lets loose the lightning, not a beam")
	check(vg.G.storm.hops.size() == on_screen and on_screen >= 6, "the lightning targets every enemy on screen, and only those (%d of %d)" % [vg.G.storm.hops.size(), on_screen])
	var wiped := true
	for b in vg.G.eb:
		wiped = wiped and b.get("dead", false)
	check(wiped, "the Storm wipes the enemy bullets on screen")
	check(vg.G.storm.hops[0].src == -1 and vg.G.storm.hops[1].src == 0, "the lightning jumps from the ship, then target to target")
	# lifting slows time a moment, so give it the slow-motion ticks too
	tick(vg.STORM_SPREAD + vg.SLOW_TICKS + 4, false)
	var all_dead := true
	for f in foes:
		all_dead = all_dead and f.get("dead", false)
	check(all_dead, "every small flyer on screen dies")
	check(not big.get("dead", false) and big.hp <= bhp - vg.STORM_DMG + 0.01, "big flyers take one hit and live")
	check(not far.get("dead", false) and far.hp == fhp, "enemies off screen are spared")
	check(vg.G.has("storm") and (vg.G.storm.m as Node3D).get_child_count() > 3, "the bolts crackle on after striking")
	tick(vg.STORM_LIFE, false)
	check(not vg.G.has("storm") and vg.G.ult_t == 0, "the Storm ends")
	tick(vg.CHARGE_MAX - 20, true)
	tick(1, false)
	check(not vg.G.has("storm"), "lifting before the Storm stage fires no lightning")
	tick(60, false)
	big.dead = true
	far.dead = true

	# hull: a bullet costs a hull point; three cost a ship
	tick(60, false)
	var lives: int = vg.G.lives
	vg.P.inv = 0
	vg.bullet(vg.P.x, vg.P.y + 1, 0, 0)
	tick(1, false, 0, 0, false, false)
	check(vg.P.hull == 2, "a bullet hit costs one hull point, not the ship")
	for i in 2:
		vg.P.inv = 0
		vg.bullet(vg.P.x, vg.P.y + 1, 0, 0)
		tick(1, false, 0, 0, false, false)
	check(not vg.P.alive and vg.G.lives == lives - 1, "the third hit destroys the ship")
	tick(100, false)
	settle()
	check(vg.P.alive and vg.P.hull == 3, "the next ship flies in with a full hull")

	# barriers: solid outside the opening, and a locked one opens when its generator dies
	vg.add_bar({d = vg.G.scroll + 120, mode = "locked", gx = 63.0, gw = 30.0, key = "kt"})
	var bar: Dictionary = vg.G.bars.back()
	vg._update_bars()
	check(vg.bar_solid(bar, 10, bar.y, 0) and vg.bar_solid(bar, 63, bar.y, 0), "a locked barrier is solid, opening included")
	var gen: Dictionary = vg.E("generator", 20, 150, {wy = vg.G.scroll + 150, key = "kt"})
	vg.dmg_e(gen, 99)
	check(not bar.locked and not vg.bar_solid(bar, 63, bar.y, 0) and vg.bar_solid(bar, 10, bar.y, 0), "destroying its generator opens the gap")
	vg.P.inv = 0
	var hull0: int = vg.P.hull
	vg.P.x = maxf(10.0, vg.walls_at(bar.y).x + 5.0)
	vg.P.y = bar.y
	tick(1, false, 0, 0, false, false)
	check(vg.P.hull == hull0 - 1 and vg.P.y < bar.y, "flying into a barrier costs a hull point and pushes the ship back")

	# losing every ship fails the stage
	vg.G.lives = 1
	vg.kill_player()
	tick(120, false)
	check(vg.mode == "result" and vg.hud.result_scr.visible and not vg.hud._result_next.visible, "losing every ship ends the stage with Retry")

	# --- Warden ---
	vg.hud.select_ship("warden")
	vg.hud.stage_chosen.emit(1, "warden")
	settle()
	check(vg.G.ship == "warden" and vg.pod.state == "dock", "Warden starts with the pod docked at the nose")
	tick(10, true)
	check(vg.G.pb.size() >= 3, "Warden fires a wide spread")
	tick(1, false)
	check(vg.pod.state == "out", "lifting flings the pod up the screen")
	tick(60, false)
	check(vg.pod.y > vg.P.y + 40, "the pod flies up and holds")
	vg.bullet(vg.pod.x, vg.pod.y + 1, 0, 0)
	var pb: Dictionary = vg.G.eb.back()
	tick(1, false)
	check(not vg.G.eb.has(pb), "the pod blocks bullets")
	tick(5, true)
	tick(1, false)
	check(vg.pod.state == "back", "lifting again calls the pod back")
	tick(80, false)
	check(vg.pod.state == "dock", "the pod docks again")
	# Shatter: its own mechanic, filled by the pod's work and fired by recalling the pod
	vg.P.shat = 0.0
	tick(vg.ULT_AT + 20, true)
	check(vg.P.charge == 0 and vg.P.shat < vg.SHATTER_FULL, "holding loads nothing on Warden (only the pod's work fills Shatter)")
	tick(1, false)
	check(vg.pod.state == "out" and vg.G.ult_t == 0, "so a lift after a long hold is just a pod fling")
	tick(40, false)
	var s0: float = vg.P.shat
	vg.bullet(vg.pod.x, vg.pod.y + 1, 0, 0)
	tick(1, false)
	check(vg.P.shat == s0 + vg.SHAT_BLOCK, "a bullet the pod blocks fills the Shatter meter")
	s0 = vg.P.shat
	vg.E("drifter", vg.pod.x, vg.pod.y, {move = "sine", amp = 0.0, ph = 0.0, x0 = vg.pod.x})
	tick(1, false)
	check(vg.P.shat >= s0 + vg.SHAT_RAM + vg.SHAT_KILL, "a ram that kills fills it more")
	vg.P.shat = vg.SHATTER_FULL - 1.0
	vg.bullet(vg.pod.x, vg.pod.y + 1, 0, 0)
	tick(1, false)
	check(vg.shatter_full() and vg.hud.charge >= 1.0, "the meter fills up and the bar shows it")
	tick(5, true)
	check(vg.shatter_full() and vg.G.ult_t == 0, "a stored Shatter survives holding and doesn't fire on its own")
	var px: float = vg.pod.x
	var py: float = vg.pod.y
	tick(1, false)
	check(vg.pod.state == "shatter" and vg.G.shards.size() == 8, "recalling the pod with the meter full fires Shatter")
	var from_pod := true
	for sh in vg.G.shards:
		from_pod = from_pod and Vector2(sh.x - px, sh.y - py).length() < 4.0
	check(from_pod, "the shards burst out where the pod was")
	check(vg.P.shat == 0.0, "firing empties the meter")
	vg.P.inv = 0
	vg.bullet(vg.P.x, vg.P.y, 0, 0)
	tick(1, true, 0, 0, false, false)
	check(vg.P.hull == 3, "the ship is shielded during Shatter")
	tick(200, false)
	check(vg.pod.state == "dock" and vg.G.shards.is_empty(), "the pod reforms after Shatter")

	# --- stages ---
	check(VStage.STAGES.size() == 48, "six worlds of eight stages")
	for st in VStage.STAGES.size():
		var ev := VStage.build(st)
		var kinds := {}
		for x in ev:
			kinds[x.type + ("_" + x.mode if x.has("mode") else "")] = true
		check(kinds.has("drifter") and kinds.has("turret") and kinds.has("carrier") and kinds.has("end"), "stage %d has waves, ground turrets, carriers and an end" % (st + 1))
		check(kinds.has("barrier_locked") and kinds.has("barrier_wall") and kinds.has("barrier_slide") and kinds.has("generator"), "stage %d has sliding, wall and locked barriers" % (st + 1))
		check(str(VStage.build(st)) == str(ev), "stage %d is the same every time" % (st + 1))
	# stage 1 runs to its mid-boss and clears when it dies
	vg.hud.stage_chosen.emit(0, "lance")
	var t := 0
	while not vg.G.ended and t < 6000 and vg.mode == "play":
		t += 1
		tick(1, true)
	check(vg.G.ended and vg.G.get("mid_boss", false), "stage 1 scrolls to the Shell Matriarch (%d ticks)" % t)
	for e2 in vg.G.enemies:
		if e2.get("boss", false):
			vg.dmg_e(e2, 999)
	tick(200, true)
	check(vg.mode == "result" and vg.hud._result_next.visible, "killing the mid-boss clears the stage, with Next")
	# stage 8 ends with the Bloom Mother
	vg.hud.next_pressed.emit()
	check(vg.G.stage == 1, "Next starts stage 2")
	vg.start_stage(7, "lance")
	vg.G.scroll = VStage.STAGES[7].length - 200
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll:
		vg.G.si += 1
	settle()
	t = 0
	while vg.G.boss.is_empty() and t < 1000:
		t += 1
		tick(1, true)
	check(not vg.G.boss.is_empty() and vg.G.boss.kind == "bloom", "stage 8 ends with the Bloom Mother")
	tick(300, true)
	check(vg.G.boss.y < 224 and not vg.G.boss.enter, "the Bloom Mother settles at the top of the screen")
	for p in vg.G.boss.petals:
		p.hp = 0
		p.alive = false
	tick(60, true)
	check(vg.G.boss.phase2, "with its petals gone the eye starts opening")
	vg.G.boss.core.hp = 1
	vg.boss_damage({kind = "core", o = vg.G.boss.core, x = 0.0, y = 0.0}, 5)
	tick(400, true)
	check(vg.mode == "result" and vg.hud._result_next.visible, "the Bloom Mother's death clears world 1, with Next to world 2")
	vg.hud.next_pressed.emit()
	check(vg.G.stage == 8 and vg.G.world == 1 and vg.look == vg.LOOKS[1], "Next goes on to Frost Rift, in its own colours")
	await flyer_checks()
	vg.start_stage(47, "lance")
	vg.finish(true)
	check(not vg.hud._result_next.visible, "the last stage has no Next")
	await world_boss_checks()
	await fortress_checks()
	vg.hud.menu_pressed.emit()
	check(vg.mode == "menu" and vg.G.is_empty(), "Stages goes back to the stage menu")

	await rock_checks()
	print("FAILED: %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)


## Fortresses: full walls on the ground, guns on their front edge, shutters that close, and
## outpost pieces round them, more of them later in a world.
func fortress_checks() -> void:
	print("Fortresses")
	var n1 := 0
	var n8 := 0
	var guns := 0
	var shutters := 0
	for i in VStage.STAGES.size():
		for e in VStage.build(i):
			if e.type == "prop":
				if i % 8 == 0:
					n1 += 1
				elif i % 8 == 7:
					n8 += 1
			guns += 1 if e.type == "wallgun" else 0
			shutters += 1 if e.type == "barrier" and e.mode == "shutter" else 0
	check(n8 > n1 * 2, "outposts grow through a world (%d pieces on first stages, %d on last)" % [n1, n8])
	check(guns > 40 and shutters > 30, "walls carry guns (%d) and shutters close openings (%d)" % [guns, shutters])
	vg.start_stage(13, "lance")
	settle()
	vg.add_bar({d = vg.G.scroll + 150.0, mode = "shutter", gx = 63.0, gw = 36.0, key = "s", ph = 0.0})
	var b: Dictionary = vg.G.bars.back()
	var closed := false
	var opened := false
	for k in 400:
		tick(1, false)
		closed = closed or b.gw < 2.0
		opened = opened or b.gw > 35.0
	check(closed and opened, "a shutter closes its opening and opens it again")
	var wall: Node3D = b.nodes[0]
	check(wall.get_child(0).get_aabb().position.z < -60.0, "a fortress wall stands on the ground, not in the air")
	# a wall gun sits in front of its wall, where the ship's shots reach it
	vg.spawn({type = "wallgun", x = 30.0, d = b.wy - 6.5})
	var g: Dictionary = vg.G.enemies.back()
	tick(1, false)
	check(g.y < b.y - b.th / 2.0 and not vg.bar_solid(b, g.x, g.y - g.hh, 0.0), "a wall gun stands clear of the wall's band")
	vg.spawn({type = "prop", kind = "radar", x = 20.0, d = vg.G.scroll + 100.0})
	tick(2, false)
	check(vg.G.props.size() > 0 and vg.G.props.back().m.position.z < -30.0, "outpost pieces stand on the ground")


## The bosses of worlds 2 to 6: each arrives at the top, attacks, shrugs off hits on its
## armour, and dies (clearing the stage) once its guards and core are destroyed.
func world_boss_checks() -> void:
	print("World bosses")
	for w in range(1, 6):
		var i: int = w * 8 + 7
		vg.start_stage(i, "lance")
		settle()
		vg.G.scroll = VStage.STAGES[i].length - 200
		vg.G.si = 0
		while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll:
			vg.G.si += 1
		var t := 0
		while vg.G.boss.is_empty() and t < 1000:
			t += 1
			tick(1, false)
		var kind: String = Worlds.LIST[w].boss
		check(not vg.G.boss.is_empty() and vg.G.boss.kind == kind, "world %d ends with the %s" % [w + 1, Worlds.LIST[w].boss_name])
		for e in vg.G.enemies:
			e.dead = true
		tick(320, false)
		var B: Dictionary = vg.G.boss
		check(not B.enter and B.y < 224.0 and B.y > 140.0 and B.x > 20.0 and B.x < 106.0, "the %s settles at the top of the screen (%.0f, %.0f)" % [kind, B.x, B.y])
		var fired := false
		for k in 300:
			tick(1, false)
			if not vg.G.eb.is_empty():
				fired = true
		check(fired, "the %s attacks" % kind)
		var c: Dictionary = B.parts.core
		if c.armour:
			var hp0: float = c.hp
			vg.boss_damage({o = c, kind = "shield"}, 5)
			check(c.hp == hp0, "the %s's core is armoured while its guards live" % kind)
		for p in B.list:
			if not p.core and p.max < 9999:
				vg.boss_damage({o = p, kind = "part"}, 9999)
		tick(300, false)
		if kind == "titan":
			while not B.open:
				tick(1, false)
		check(not c.armour or kind == "titan", "with its guards gone the %s's core opens" % kind)
		vg.boss_damage({o = c, kind = "core"}, 99999)
		tick(400, false)
		check(vg.mode == "result" and vg.G.boss.is_empty(), "the %s's death clears the stage" % kind)


## The flyers of all six worlds, the stage ends, and ground targets in reach of the ship.
func flyer_checks() -> void:
	print("Flyers")
	settle()
	# every stage now has a canyon run, which clears the sky: keep it out of these checks
	vg.script_list = vg.script_list.filter(func(e): return e.type != "run")
	for k in ["shards", "drones", "seekers", "wasps", "lancers"]:
		var before: int = vg.G.enemies.size()
		vg.spawn({type = k, x = 63.0, d = vg.G.scroll + 224.0, n = 3})
		var group: Array = vg.G.enemies.slice(before)
		var y0: float = group[0].y
		tick(90, false)
		var moved := false
		for e in group:
			if e.y < y0 - 20.0:
				moved = true
		check(group.size() == 3 and y0 > 200.0 and moved, "%s come down from the top of the screen" % k)
	for k in ["flake", "hulk", "sentinel", "nest", "bulwark"]:
		for e in vg.G.enemies:
			e.dead = true
		for b in vg.G.eb:
			b.dead = true
		tick(1)
		vg.spawn({type = k, x = 63.0, d = vg.G.scroll + 224.0})
		tick(260, false)
		check(not vg.G.eb.is_empty() or vg.G.enemies.size() > 1, "a %s comes in and attacks" % k)
	var names := {}
	for i in VStage.STAGES.size():
		var ev := VStage.build(i)
		for e in ev:
			if e.type == "end":
				names[e.kind] = true
		for e in ev:
			if e.type == "turret" or e.type == "generator":
				if not VStage.in_reach(ev, e):
					check(false, "stage %d: a %s at %.0f sits behind a wall" % [i + 1, e.type, e.d])
	check(names.has("big:hulk") and names.has("twins:bulwark") and names.has("bloom") and names.has("heart"), "stages end with mid-bosses of every world's big flyer, worlds with their bosses")
	# the end of a Frost Rift stage: a Rime Hulk grown to mid-boss size
	for e in vg.G.enemies:
		e.dead = true
	tick(1)
	vg._spawn_end("big:hulk")
	check(vg.G.enemies.size() == 1 and vg.G.enemies[0].boss and vg.hud.boss_name == "Rime Hulk", "a mid-boss arrives with its name")
	# enemy bullets stop on a barrier's wall
	vg.add_bar({d = vg.G.scroll + 120.0, mode = "fixed", gx = 20.0, gw = 30.0, key = "t"})
	tick(1)
	var bar: Dictionary = vg.G.bars.back()
	vg.bullet(90.0, bar.y + 10.0, 0.0, -1.0)
	tick(20)
	var through := false
	for b in vg.G.eb:
		if absf(b.x - 90.0) < 0.1 and b.y < bar.y - 6.0:
			through = true
	check(not through, "enemy bullets stop on a wall")


## Rock set pieces: a short canyon and a couple of islands per stage, with open sky
## everywhere else. Touching rock costs a hull point, shots break on it, skimming it pays.
func rock_checks() -> void:
	print("Rock")
	vg.hud.select_ship("lance")
	vg.hud.stage_chosen.emit(0, "lance")
	# the layout: rock is occasional, canyons leave room, islands leave a way past on both
	# sides, barrier gaps and the boss stay clear of rock
	for i in VStage.STAGES.size():
		var st: Dictionary = VStage.STAGES[i]
		var narrowest := 999.0
		var rocky := 0
		var samples := 0
		var d := 0.0
		while d < st.length:
			var w := VStage.walls(i, d)
			narrowest = minf(narrowest, w.y - w.x)
			samples += 1
			var any := w.x > 0.0 or w.y < 126.0
			for isl in VStage.ISLANDS[i]:
				if VStage.island_half(isl, d) > 0.0:
					any = true
					var side := minf(float(isl[2]) - VStage.island_half(isl, d) - w.x, w.y - float(isl[2]) - VStage.island_half(isl, d))
					narrowest = minf(narrowest, side)
			if any:
				rocky += 1
			d += 3.0
		check(narrowest >= 30.0, "stage %d: there is always at least 30 units of room (%.1f)" % [i + 1, narrowest])
		check(rocky > 0 and float(rocky) / samples < 0.35, "stage %d: rock is an occasional feature (%d%% of the stage)" % [i + 1, 100 * rocky / samples])
		var clear := true
		for ev in VStage.build(i):
			if ev.type == "barrier":
				for dd in [ev.d - 10.0, ev.d, ev.d + 10.0]:
					var w2 := VStage.walls(i, dd)
					if w2.x > 0.0 or w2.y < 126.0 or VStage.on_island(i, ev.gx, dd, ev.gw / 2.0):
						clear = false
		check(clear, "stage %d: barriers never overlap rock" % [i + 1])
		var bclear := true
		var dd2: float = st.length - 224.0 - 10.0
		while dd2 < st.length:
			var w3 := VStage.walls(i, dd2)
			if w3.x > 0.0 or w3.y < 126.0:
				bclear = false
			for isl in VStage.ISLANDS[i]:
				if VStage.island_half(isl, dd2) > 0.0:
					bclear = false
			dd2 += 4.0
		check(bclear, "stage %d: the boss has the whole screen" % [i + 1])
	# canyon: touching the wall costs a hull point, and the ship never ends up inside it
	settle()
	var c0: Array = VStage.CANYONS[0][0]
	vg.G.scroll = c0[0] + 60.0
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + 224:
		vg.G.si += 1
	for e in vg.G.enemies:
		e.dead = true
	for b in vg.G.eb:
		b.dead = true
	tick(2)
	var w0: Vector2 = vg.walls_at(vg.P.y)
	check(w0.y - w0.x < 80.0, "a canyon narrows the screen (%.0f wide)" % (w0.y - w0.x))
	vg.P.inv = 0
	var hull0: int = vg.P.hull
	tick(1, true, -200.0, 0.0, false, false)
	check(vg.P.hull == hull0 - 1, "flying into a canyon wall costs a hull point")
	w0 = vg.walls_at(vg.P.y)
	check(vg.P.x >= w0.x + vg.ROCK_PAD, "the ship is pushed out of the rock")
	# scraping: close to the rock but not touching pays points
	vg.P.inv = 0
	vg.P.hull = 3
	vg.P.x = w0.x + vg.ROCK_PAD + 1.5
	var sc: int = vg.G.score
	# (the stage runs slow just after a hit: give it a dozen of its own ticks)
	tick(30, false, 0.0, 0.0, false, false)
	check(vg.G.score > sc and vg.P.hull == 3, "skimming the rock pays points without damage")
	# shots and bullets break on the rock
	vg.P.x = (w0.x + w0.y) / 2.0
	vg.shot(w0.x + 3.0, vg.P.y + 20, -3.0, 0.0, Models.M.shot, 1)
	var sh: Dictionary = vg.G.pb.back()
	tick(3)
	check(not vg.G.pb.has(sh), "shots break on the rock")
	vg.bullet(w0.x - 6.0, vg.P.y + 30, 0.0, 0.0)
	var bl: Dictionary = vg.G.eb.back()
	tick(1)
	check(not vg.G.eb.has(bl), "enemy bullets break on the rock")
	vg.spawn({type = "drifter", x = 2.0, d = vg.G.scroll + 230, move = "dive", stop = 170.0})
	var dr: Dictionary = vg.G.enemies.back()
	var dw := VStage.walls(0, vg.G.scroll + 230)
	check(dr.x > dw.x and dr.x < dw.y, "a drifter spawned over the rock moves into the passage")
	dr.dead = true
	var walls_drawn := false
	for c in vg.chunks.values():
		for ch in c.get_children():
			if ch.name == "Walls" and ch.get_child_count() > 0:
				walls_drawn = true
	check(walls_drawn, "the canyon walls are drawn")
	# island: in the middle of the screen, hitting it costs a hull point and pushes the ship
	# to one side; it is drawn
	var isl: Array = VStage.ISLANDS[0][0]
	vg.G.scroll = isl[0] + isl[1] / 2.0 - vg.P.y
	tick(1)
	check(vg.in_rock(isl[2], vg.P.y, 0.0) and not vg.in_rock(isl[2] - isl[3] - 8.0, vg.P.y, 0.0), "an island is rock in the open")
	vg.P.inv = 0
	vg.P.hull = 3
	vg.P.x = isl[2]
	vg.G.slow = 0
	tick(1, true, 0.0, 0.0, false, false)
	check(vg.P.hull == 2 and absf(vg.P.x - isl[2]) > isl[3], "flying into an island costs a hull point and slides the ship off it")
	check(vg.G.islands.size() == VStage.ISLANDS[0].size() and vg.G.islands[0].m.visible, "the islands are drawn")
	# charging is free again: the guns keep firing through a long hold
	vg.P.inv = 30
	tick(5, false)
	var fired := 0
	for i in 200:
		var n0: int = vg.G.pb.size()
		tick(1, true)
		if i > 120:
			fired += maxi(0, vg.G.pb.size() - n0)
	check(fired > 0 and vg.P.charge >= vg.CHARGE_AT[2], "the guns keep firing while Lance charges")
	tick(1, false)
	check(vg.G.beams.size() >= 1, "lifting fires the beam")
	# a whole stage: the ship (kept alive) follows a weaving thumb and is never inside rock
	vg.start_stage(0, "lance")
	settle()
	var inside := 0
	var t := 0
	while not vg.G.ended and t < 6000:
		t += 1
		vg.inp = {hold = true, fire = true, dx = sin(t * 0.03) * 2.5, dy = 0.0, ult = false, pause = false}
		vg.P.inv = maxi(vg.P.inv, 2)
		vg.update()
		if vg.P.alive and not vg.P.entering and vg.in_rock(vg.P.x, vg.P.y, vg.ROCK_PAD):
			inside += 1
	check(vg.G.ended and inside == 0, "a whole stage plays through without the ship inside rock (%d ticks)" % t)
	vg.to_menu()
