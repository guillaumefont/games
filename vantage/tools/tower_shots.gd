extends SceneTree
## Screenshots of the four gun towers (`Towers`) in every world, side by side (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/tower_shots.gd -- /tmp/towers

var out := "/tmp/towers"
var g: Game


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://tower_shots_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 3
	root.add_child(g)
	await process_frame
	for w in Campaign.WORLDS.size():
		g.launch(w * Campaign.PER_WORLD)
		g.touching = true
		for i in 3:
			g.step(1.0 / 60.0)
			await process_frame
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		var xs := [-4.4, -1.5, 1.5, 4.4]
		for k in Towers.TYPES.size():
			g.spawn_vert(Towers.TYPES[k], xs[k] / 1.25, 0, 1)
		var t := 0.0
		while t < 3.2:
			g.hp = 5
			g.time_k = 1.0
			g.touching = true
			g.fire_cd = 99.0   # hold fire, so the towers stay whole for the picture
			g.step(1.0 / 60.0)
			t += 1.0 / 60.0
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%d-%s.png" % [out, w + 1, Campaign.WORLDS[w].theme])
		print("shot ", Campaign.WORLDS[w].theme)
	quit()
