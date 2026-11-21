extends SceneTree
## Frame cost of a stage, for chasing lag: plays a stage with the thumb down, weaving, and prints the
## CPU time of the game tick (update) and of the scene sync (_process), plus draw calls and
## primitives, per stretch of the stage (flight, canyon run, fortress, boss).
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/perf_bench.gd -- [stage=1] [ticks=3600] [ship=lance]

var vg: Node3D


func _initialize() -> void:
	var stage := 1
	var ticks := 3600
	var ship := "lance"
	var every := 4
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"stage": stage = int(kv[1])
			"ticks": ticks = int(kv[1])
			"ship": ship = kv[1]
			"every": every = int(kv[1])
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.set_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for i in 10:
		await process_frame
	# the menu (the level map is drawn behind it)
	var menu := []
	for i in 120:
		var t0 := Time.get_ticks_usec()
		vg.update()
		vg._process(1.0 / 60.0)
		await process_frame
		menu.append([Time.get_ticks_usec() - t0, 0, 0, 0, _gpu()])
	_report("menu", menu)
	var t_start := Time.get_ticks_usec()
	vg.start_stage(stage, ship)
	print("start_stage: %.1f ms" % ((Time.get_ticks_usec() - t_start) / 1000.0))
	var seg := {}
	var order := []
	var worst := []
	for i in ticks:
		vg.inp = {hold = (i % 600) < 560, fire = true, dx = sin(i * 0.05) * 0.6, dy = 0.0, ult = false, pause = false}
		if not vg.P.is_empty():
			vg.P.inv = 2 if vg.P.inv <= 2 else vg.P.inv
			vg.P.hull = 3
		if vg.mode != "play":
			break
		var t0 := Time.get_ticks_usec()
		vg.update()
		var t1 := Time.get_ticks_usec()
		vg._process(1.0 / 60.0)
		var t2 := Time.get_ticks_usec()
		# render one tick in `every` (llvmpipe is slow); the game still runs every tick
		if i % every != 0:
			continue
		await process_frame
		var name := "flight"
		if vg.G.has("run"):
			name = "run"
		elif not vg.G.boss.is_empty():
			name = "boss"
		elif not vg.G.bars.is_empty():
			name = "fortress"
		if not seg.has(name):
			seg[name] = []
			order.append(name)
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var pr := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		seg[name].append([t1 - t0, t2 - t1, dc, pr, _gpu()])
		worst.append([t2 - t0, i, name, t1 - t0, t2 - t1])
	for n in order:
		_report(n, seg[n])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("worst ticks (total ms, tick, stretch, update ms, sync ms):")
	for w in worst.slice(0, 8):
		print("  %.1f  #%d %s  %.1f + %.1f" % [w[0] / 1000.0, w[1], w[2], w[3] / 1000.0, w[4] / 1000.0])
	quit()


func _report(name: String, rows: Array) -> void:
	var up := []
	var sy := []
	var dc := 0.0
	var pr := 0.0
	var gp := []
	for r in rows:
		up.append(r[0])
		sy.append(r[1])
		dc += r[2]
		pr += r[3]
		gp.append(r[4])
	up.sort()
	sy.sort()
	var n := rows.size()
	if n == 0:
		return
	print("%-9s %5d ticks  update avg %.2f p95 %.2f max %.2f ms | sync avg %.2f p95 %.2f max %.2f ms | %d draws %dk prims | render avg %.1f ms" % [
		name, n, _avg(up) / 1000.0, up[int(n * 0.95)] / 1000.0, up[n - 1] / 1000.0,
		_avg(sy) / 1000.0, sy[int(n * 0.95)] / 1000.0, sy[n - 1] / 1000.0, dc / n, pr / n / 1000.0, _avg(gp)])


func _avg(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1, a.size())


## GPU (here: llvmpipe, so CPU-side raster) time of the last rendered frame, ms.
func _gpu() -> float:
	var rid := root.get_viewport_rid()
	return RenderingServer.viewport_get_measured_render_time_gpu(rid) + RenderingServer.viewport_get_measured_render_time_cpu(rid)
