extends SceneTree
## Frames of the canyon run for reviews: stage 1 from just before the canyon's mouth to the
## top-down view after it, flown along the racing line (every `EVERY` ticks a PNG), plus a few
## named stills. Make a GIF from the frames with ffmpeg.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/run_shots.gd -- OUT_DIR

const EVERY := 3
var vg: Node3D
var out := "user://runshots"


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func tick(dx := 0.0, dy := 0.0) -> void:
	vg.inp = {hold = true, fire = true, dx = dx, dy = dy, ult = false, pause = false}
	vg.P.inv = mini(vg.P.inv, 0) if vg.G.has("run") else maxi(vg.P.inv, 2)
	vg.update()
	await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out.path_join("frames"))
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 20:
		await process_frame
	vg.start_stage(0, "lance")
	for i in 150:
		await tick()
	# jump to a little before the canyon's mouth
	var d0: float = VStage.STAGES[0].run
	vg.G.scroll = d0 - vg.top() - 10.0 - 70.0
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + vg.top() and vg.script_list[vg.G.si].type != "run":
		vg.G.si += 1
	for e in vg.G.enemies:
		e.dead = true
	var f := 0
	var t := 0
	var after := 0
	var stills := {"run_swing": -40.0, "run_pillars": 190.0, "run_pillars2": 310.0, "run_arch": 570.0, "run_spine": 690.0, "run_basin": 1120.0, "run_fork": 1200.0, "run_window": 1495.0, "run_arch3": 1610.0, "run_window2": 1715.0, "run_window3": 1920.0}
	while after < 150:
		var dx := 0.0
		var dy := 0.0
		if vg.G.has("run"):
			var R: Dictionary = vg.G.run
			var tgt := VRun.line(R.d + 6.0)
			var g := lerpf(1.0, VRun.GAIN, R.k)
			dx = clampf((tgt.x - vg.P.x) / g, -2.5, 2.5)
			dy = clampf((tgt.y - vg.P.z) / VRun.GAIN, -2.5, 2.5)
			for k in stills.keys():
				if R.d >= stills[k]:
					await snap(k)
					stills.erase(k)
		elif vg.G.get("run_medal", -2) != -2:
			after += 1
			if after == 30:
				await snap("run_medal")
		await tick(dx, dy)
		t += 1
		if t % EVERY == 0:
			await snap("frames/f%04d" % f)
			f += 1
	print("frames ", f)
	quit()
