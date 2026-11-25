extends SceneTree
## Each world's falls (Relief "fall") from the vertical stage's camera and from the side (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/fall_shots.gd -- /tmp/falls

var out := "/tmp/falls"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://fall_shots_save.json"
	g.driven = true
	root.add_child(g)
	await process_frame
	g.hud.visible = false
	for theme: String in ["coast", "dunes", "volcano"]:
		g.apply_theme(theme)
		var shot := 0
		for n in 8:
			for e: Dictionary in Relief.stretch_events(n, g.noise):
				if e.t != "fall" or shot >= 2:
					continue
				var foot: Vector3 = e.at
				g.frame_z = foot.z - 2.0
				for i in 3:
					g.step(1.0 / 60.0)
				g.ship.visible = false
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%d_top.png" % [out, theme, shot])
				var at := foot + Vector3(0, -1.0, -10.0)
				g.cam.global_transform = Transform3D(Basis(), at + Vector3(12.0, 9.0, 20.0)).looking_at(at, Vector3.UP)
				g.cam.fov = 60.0
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s/%s_%d_side.png" % [out, theme, shot])
				shot += 1
	print("fall shots in ", out)
	quit()
