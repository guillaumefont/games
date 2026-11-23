extends SceneTree
## Look checks of the terrain's scenery, with no HUD or foes (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/scenery.gd -- /tmp/scenery [theme]
## (theme: coast, dunes, city, ice or volcano; coast by default)
## For each stretch of coast: the vertical stage's view, then a low view like the chase's.

var out := "/tmp/scenery"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://scenery_save.json"
	g.driven = true
	root.add_child(g)
	await process_frame
	g.hud.visible = false
	if args.size() > 1:
		g.apply_theme(args[1])
	for z: float in [-60.0, -180.0, -330.0, -470.0, -620.0]:
		g.frame_z = z
		g.step(1.0 / 60.0)
		g.ship.visible = false
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/top%d.png" % [out, -z])
		var at := Vector3(0, 0, z - 14.0)
		g.cam.global_transform = Transform3D(Basis(), at + Vector3(0, 9.0, 13.0)).looking_at(at, Vector3.UP)
		g.cam.fov = 55.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/low%d.png" % [out, -z])
	print("scenery shots in ", out)
	quit()
