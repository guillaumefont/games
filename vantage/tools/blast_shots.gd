extends SceneTree
## Screenshots of explosions over time, from the stage camera and the chase camera (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/blast_shots.gd -- /tmp/blasts
## Writes <view>-<size>-<ms>.png: a blast of each size at a few moments of its life.

var out := "/tmp/blasts"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick() -> void:
	g.hp = 3
	g.inv = 1.0
	g.step(1.0 / 60.0)
	await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://blast_shots_save.json"
	Rules.save_game(Rules.fresh(), tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	g.launch()
	for i in 60:
		await tick()
	for view in ["top", "chase"]:
		if view == "chase":
			g.set_cam("chase", 0.0)
		for size in [1.3, 3.0, 6.0]:
			g.clear_all()
			g.blasts.rng.seed = 11
			await tick()
			var at := g.ppos + (Vector3(0, 0, -9) if view == "top" else Vector3(1.5, 1.5, -16))
			g.pop(at, size, Models.AMBER)
			g.shake = maxf(g.shake, 0.12 * size)
			var t := 0.0
			for ms in [60, 200, 450, 900, 1500]:
				while t * 1000.0 < ms:
					await tick()
					t += 1.0 / 60.0
				await shot("%s-%s-%04d" % [view, size, ms])
	quit()
