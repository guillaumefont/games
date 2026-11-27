extends SceneTree
## Ember Dunes' cliff dwellings (Dwellings) on each set piece that hosts them, from the vertical
## stage's camera and from low down (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/dwelling_shots.gd -- /tmp/dwellings

var out := "/tmp/dwellings"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = "user://dwelling_shots_save.json"
	g.driven = true
	root.add_child(g)
	await process_frame
	g.hud.visible = false
	g.apply_theme("dunes")
	for n in 6:
		var kind := Relief.kind_of(n)
		if not kind in Dwellings.HOSTS:
			continue
		for f: float in [0.3, 0.6]:
			var z := Relief.START - n * Relief.SEG - Relief.SEG * f
			g.frame_z = z
			g.step(1.0 / 60.0)
			g.ship.visible = false
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%d_%s_%d_top.png" % [out, n, kind, roundi(f * 10)])
			var at := Vector3(0, -4.0, z - 14.0)
			g.cam.global_transform = Transform3D(Basis(), at + Vector3(0, 9.0, 13.0)).looking_at(at, Vector3.UP)
			g.cam.fov = 55.0
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%d_%s_%d_low.png" % [out, n, kind, roundi(f * 10)])
	print("dwelling shots in ", out, " (", Models.scenery.get("cliff dwelling", 0), " built)")
	quit()
