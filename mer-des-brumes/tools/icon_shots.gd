extends SceneTree
## Renders the game's own sloop for the app icon to store/ship.png (transparent), then run
## python3 tools/icon.py. Needs a display:
##   xvfb-run -a -s "-screen 0 1200x1200x24" godot --path . --rendering-method gl_compatibility --resolution 1024x1024 --script tools/icon_shots.gd


func _initialize() -> void:
	root.transparent_bg = true
	var w := Node3D.new()
	root.add_child(w)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xd8, 0xd6, 0xcc)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color8(0xff, 0xf0, 0xda)
	w.add_child(sun)
	sun.look_at_from_position(Vector3(-6, 10, 8), Vector3.ZERO, Vector3.UP)
	var ship := Models.ship(Models.ship_cfg("sloop", {"voiles": 3, "canons": 1}, [], {}))
	w.add_child(ship)
	ship.rotation.y = -0.75
	Models.billow(ship, 0.55, 0.0)
	var cam := Camera3D.new()
	cam.fov = 26
	w.add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.5, 17), Vector3(0, 2.4, 0), Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://store")
	root.get_texture().get_image().save_png("res://store/ship.png")
	print("saved store/ship.png")
	quit()
