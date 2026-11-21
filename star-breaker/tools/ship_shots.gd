extends SceneTree
## Frames of one ship at work for a GIF: it flies a busy stretch of a stage, holding and lifting
## on a rhythm, with its ultimate meter topped up half way through so the ultimate shows.
## rm -f ~/.local/share/godot/app_userdata/"Star Breaker"/{diag.log,settings.cfg}
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/ship_shots.gd -- OUT_DIR SHIP [STAGE] [HOLD_TICKS]
## then: ffmpeg -framerate 20 -i OUT_DIR/f%03d.png -vf "scale=360:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" ship.gif

var vg: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ship: String = args[1]
	var stage := int(args[2]) if args.size() > 2 else 9
	var hold_n := int(args[3]) if args.size() > 3 else 70
	DirAccess.make_dir_recursive_absolute(out)
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 20:
		await process_frame
	vg.start_stage(stage, ship, 0)
	# skip to a busy stretch after the canyon run
	vg.G.scroll = VStage.STAGES[stage].run + 420.0
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + 100:
		vg.G.si += 1
	if vg.run_b != null:
		vg.run_b.node.queue_free()
		vg.run_b = null
	var frame := 0
	var total := 60 * 14
	for i in total + 90:
		var cyc := i % (hold_n + 14)
		var hold := cyc < hold_n
		var dx := sin(i * 0.035) * 0.9
		var dy := sin(i * 0.021) * 0.25
		if i == total / 2 and vg.kit:
			vg.kit.meter = 1.0
		vg.inp = {hold = hold, fire = hold, dx = dx, dy = dy, ult = false, pause = false}
		if not vg.P.is_empty():
			vg.P.inv = maxi(vg.P.inv, 2) if vg.P.inv > 2 else 2
			vg.P.hull = 3
		vg.update()
		await process_frame
		if i >= 90 and i % 3 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("f%03d.png" % frame))
			frame += 1
	print("frames ", frame)
	quit()
