extends SceneTree
## Rendering and script cost over a played level (needs a display), for battery work:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/perf.gd -- [level]
## Prints, every 2 s of game time, the phase, draw calls, objects and primitives drawn, the
## live node count and the CPU time of one step(). The autopilot is the one in shots.gd.

var g: Game


func tick() -> float:
	g.hp = maxi(g.hp, 2)
	if g.phase == "vert":
		var tx := sin(g.stage_t * 0.9) * 3.5
		if not g.boss_parts.is_empty():
			tx = g.boss_parts[0].pos.x
		g.prel.x = lerpf(g.prel.x, tx, 0.05)
	if g.pov_mode():
		var best: Game.Obj = null
		for f in g.foes:
			if f.kind not in ["orb", "boss"] and not f.dead and not (f.kind == "core" and g.shielded()) and not g.cam.is_position_behind(f.pos):
				if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
					best = f
		if best:
			g.off = g.off.lerp(g.line_up(best), 0.06)
	var t0 := Time.get_ticks_usec()
	g.step(1.0 / 60.0)
	var us := Time.get_ticks_usec() - t0
	await process_frame
	return us


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var lv := int(args[0]) if args.size() > 0 else 2
	var tmp := "user://perf_save.json"
	var s := Rules.fresh()
	s.open = 14
	s.up.cannon = 2
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	g.launch(lv)
	var worst := 0
	var sum := 0
	var n := 0
	for i in 60 * 90:
		var us: int = await tick()
		worst = maxi(worst, us)
		sum += us
		n += 1
		if i % 120 == 119:
			var rs := RenderingServer
			print("%-9s draws %4d  objects %4d  prims %7d  nodes %5d  step avg %5.2f ms max %5.2f ms" % [g.phase,
				rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
				g.get_tree().get_node_count(), sum / 1000.0 / n, worst / 1000.0])
			worst = 0
			sum = 0
			n = 0
		if g.phase == "results":
			break
	quit()
