extends SceneTree
## The portrait game (vertical slice): the main menu opens it, drag moves the ship 1:1,
## the main weapon fires while the thumb is down, lifting fires Lance's beam (LV 1 up to the
## Nova) or flings and recalls Warden's pod, a second finger fires the ultimate, barriers and
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
	print("Vertical slice test")
	# the main menu has a button that opens the portrait game
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.set_process(false)
	await process_frame
	var opened := [false]
	main.vertical_fn = func(): opened[0] = true
	check(main.hud.btn_vertical != null and main.hud.btn_vertical.is_visible_in_tree(), "the main menu shows a Vertical preview button")
	main.hud.btn_vertical.pressed.emit()
	main.update()
	check(opened[0], "the button opens the portrait game")
	main.queue_free()
	await process_frame

	vg = load("res://scenes/vertical.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame
	check(vg.mode == "menu" and vg.hud.menu_scr.visible, "the portrait game starts on its stage menu")

	# --- Lance ---
	check(vg.hud.edge, "the menu starts on Edge")
	# the first part checks the softer game (no rock walls); edge mode is checked at the end
	vg.hud.select_edge(false)
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

	# ultimate: the gauge fills from kills, a second finger fires Starbreak
	check(vg.P.ult < 1.0, "the ultimate gauge starts short of full")
	tick(1, true, 0, 0, true)
	check(vg.G.ult_t == 0, "the ultimate does nothing until the gauge is full")
	for i in 30:
		var d: Dictionary = vg.E("drifter", 60, 150, {move = "sine", amp = 0.0, ph = 0.0, x0 = 60.0})
		vg.kill_e(d)
	check(vg.P.ult >= 1.0, "kills fill the ultimate gauge")
	tick(1, true, 0, 0, true)
	check(vg.G.ult_t > 0 and vg.G.beams.size() >= 1 and vg.G.beams.back().ult, "a second finger fires Starbreak")
	var tgt: Dictionary = vg.E("shell", 100, 150, {hold = 0.0})
	var thp: float = tgt.hp
	tick(125, true)
	check(tgt.hp < thp or tgt.get("dead", false), "Starbreak sweeps across the screen and hits")
	check(vg.G.ult_t == 0 and vg.P.ult == 0.0, "the ultimate ends and the gauge is spent")
	tgt.dead = true

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
	vg.P.x = 10.0
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
	vg.P.ult = 1.0
	for i in 3:
		vg.E("drifter", 30 + i * 30, 170, {move = "sine", amp = 0.0, ph = 0.0, x0 = 30.0 + i * 30})
	tick(1, true, 0, 0, true)
	check(vg.pod.state == "shatter" and vg.G.shards.size() == 8, "Shatter bursts the pod into eight shards")
	vg.P.inv = 0
	vg.bullet(vg.P.x, vg.P.y, 0, 0)
	tick(1, true, 0, 0, false, false)
	check(vg.P.hull == 3, "the ship is shielded during Shatter")
	tick(200, true)
	check(vg.pod.state == "dock" and vg.G.shards.is_empty(), "the pod reforms after Shatter")

	# --- stages ---
	for st in 3:
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
	# stage 3 ends with the Bloom Mother
	vg.hud.next_pressed.emit()
	check(vg.G.stage == 1, "Next starts stage 2")
	vg.start_stage(2, "lance")
	vg.G.scroll = VStage.STAGES[2].length - 200
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll:
		vg.G.si += 1
	settle()
	t = 0
	while vg.G.boss.is_empty() and t < 1000:
		t += 1
		tick(1, true)
	check(not vg.G.boss.is_empty() and vg.G.boss.kind == "bloom", "stage 3 ends with the Bloom Mother")
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
	check(vg.mode == "result" and not vg.hud._result_next.visible, "the Bloom Mother's death clears world 1")
	vg.hud.menu_pressed.emit()
	check(vg.mode == "menu" and vg.G.is_empty(), "Stages goes back to the stage menu")

	await edge_checks()
	print("FAILED: %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)


## Edge mode: rock walls along the stage, Lance's guns quiet while it charges, a shorter
## safety window after a hit and no slow-motion after a lift.
func edge_checks() -> void:
	print("Edge mode")
	vg.hud.select_edge(true)
	vg.hud.select_ship("lance")
	vg.hud.stage_chosen.emit(0, "lance")
	check(vg.edge and vg.mode == "play", "Edge on the menu starts the stage in edge mode")
	# the stage layout: canyons narrow the screen, the fortress keeps its barrier gaps clear,
	# the boss gets the whole width, and the passage is never too tight
	for i in VStage.STAGES.size():
		var st: Dictionary = VStage.STAGES[i]
		var narrowest := 999.0
		var d := 0.0
		while d < st.length + 224:
			var w := VStage.walls(i, d)
			narrowest = minf(narrowest, w.y - w.x)
			d += 3.0
		check(narrowest >= 50.0, "stage %d: the passage is never narrower than 50 (%.1f)" % [i + 1, narrowest])
		var c: Array = VStage.CANYONS[i][0]
		var cw := VStage.walls(i, (c[0] + c[1]) / 2.0)
		var ow := VStage.walls(i, 120.0)
		check(cw.y - cw.x < 80.0 and ow.y - ow.x > 105.0, "stage %d: canyons are much narrower than open ground" % [i + 1])
		var bw := VStage.walls(i, st.length - 120)
		check(bw.y - bw.x > 118.0, "stage %d: the walls open up for the boss" % [i + 1])
		var clear := true
		for ev in VStage.build(i):
			if ev.type == "barrier":
				var w2 := VStage.walls(i, ev.d)
				if ev.gx - ev.gw / 2.0 < w2.x + 4 or ev.gx + ev.gw / 2.0 > w2.y - 4:
					clear = false
		check(clear, "stage %d: every barrier gap is inside the passage" % [i + 1])
	# rock: touching it costs a hull point, and the ship never ends up inside it
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
	vg.P.inv = 0
	var hull0: int = vg.P.hull
	tick(1, true, -200.0, 0.0, false, false)
	check(vg.P.hull == hull0 - 1 and vg.P.inv == vg.EDGE_INV, "flying into the rock costs a hull point, with a short safety window")
	w0 = vg.walls_at(vg.P.y)
	check(vg.P.x >= w0.x + vg.ROCK_PAD, "the ship is pushed out of the rock")
	# scraping: close to the rock but not touching pays points
	vg.P.inv = 0
	vg.P.hull = 3
	vg.P.x = w0.x + vg.ROCK_PAD + 1.5
	var sc: int = vg.G.score
	tick(12, false, 0.0, 0.0, false, false)
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
	# enemies are placed inside the passage
	vg.spawn({type = "drifter", x = 2.0, d = vg.G.scroll + 230, move = "dive", stop = 170.0})
	var dr: Dictionary = vg.G.enemies.back()
	var dw := VStage.walls(0, vg.G.scroll + 230)
	check(dr.x > dw.x and dr.x < dw.y, "a drifter spawned over the rock moves into the passage")
	dr.dead = true
	# Lance: short holds keep the guns firing, a long hold silences them; no slow-mo on a lift
	tick(5, false)
	for b in vg.G.pb:
		b.dead = true
	tick(1, false)
	var fired := 0
	for i in 40:
		var n0: int = vg.G.pb.size()
		tick(1, true)
		fired += maxi(0, vg.G.pb.size() - n0)
	check(fired > 0, "the guns fire during a short hold")
	tick(20, true)
	var quiet := 0
	for i in 60:
		var n1: int = vg.G.pb.size()
		tick(1, true)
		quiet += maxi(0, vg.G.pb.size() - n1)
	check(quiet == 0 and vg.P.charge >= vg.CHARGE_AT[1], "past LV 1 the charge silences Lance's guns")
	tick(1, false)
	check(vg.G.get("slow", 0) == 0 and vg.G.beams.size() >= 1, "lifting fires the beam with no slow-motion")
	# the walls are drawn: chunks carry a rock-wall node
	var walls_drawn := false
	for c in vg.chunks.values():
		if c.get_child_count() > 0 and c.get_child(c.get_child_count() - 1).get_child_count() == 4:
			walls_drawn = true
	check(walls_drawn, "the rock walls are drawn")
	# a whole stage in edge mode: the ship (kept alive) follows a weaving thumb and is never
	# inside the rock, and the stage still ends with its boss
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
	check(vg.G.ended and inside == 0, "a whole edge stage plays through without the ship inside rock (%d ticks)" % t)
	vg.to_menu()
