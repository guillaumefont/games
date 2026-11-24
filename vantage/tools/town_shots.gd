extends SceneTree
## Each world's town (Towns) from the vertical stage's camera and from low down (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/town_shots.gd -- /tmp/towns

var out := "/tmp/towns"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://town_shots_save.json"
	g.driven = true
	root.add_child(g)
	await process_frame
	g.hud.visible = false
	for theme: String in ["dunes", "coast", "ice", "volcano"]:
		g.apply_theme(theme)
		var n := -1
		for k in 10:
			if Relief.has_town(k):
				n = k
				break
		var c := Relief.town_c(n)
		g.frame_z = c.y + 4.0
		g.step(1.0 / 60.0)
		g.ship.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_top.png" % [out, theme])
		var at := Vector3(c.x, 0, c.y)
		g.cam.global_transform = Transform3D(Basis(), at + Vector3(0, 16.0, 44.0)).looking_at(at, Vector3.UP)
		g.cam.fov = 55.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_low.png" % [out, theme])
	print("town shots in ", out)
	quit()
