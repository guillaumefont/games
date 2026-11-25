extends SceneTree
## Glass Coast's rocky heights (Relief.crag) from the vertical stage's camera and from low down (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/crag_shots.gd -- /tmp/crags

var out := "/tmp/crags"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://crag_shots_save.json"
	g.driven = true
	root.add_child(g)
	await process_frame
	g.hud.visible = false
	g.apply_theme("coast")
	# the stretches of screen with the most bare rock
	var spots := []
	var z := -20.0
	while z > -1400.0 and spots.size() < 3:
		var rock := 0
		for i in 9:
			for j in 5:
				if Relief.raw(g.noise, -14.0 + i * 3.5, z - j * 4.0) > 0.55:
					rock += 1
		if rock > 14:
			spots.append(z - 8.0)
			z -= 120.0
		z -= 10.0
	var shot := 0
	for sz: float in spots:
		g.frame_z = sz + 8.0
		for i in 3:
			g.step(1.0 / 60.0)
		g.ship.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/crag_%d_top.png" % [out, shot])
		var at := Vector3(0, 0, sz)
		g.cam.global_transform = Transform3D(Basis(), at + Vector3(6.0, 12.0, 26.0)).looking_at(at, Vector3.UP)
		g.cam.fov = 60.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/crag_%d_low.png" % [out, shot])
		shot += 1
	print("crag shots in ", out, " at ", spots)
	quit()
