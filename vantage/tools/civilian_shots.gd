extends SceneTree
## Screenshots of each world's civilian (`Civilians`) strolling by, then of its getaway once shot
## down (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/civilian_shots.gd -- /tmp/civilians

var out := "/tmp/civilians"
var g: Game


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://civilian_shots_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 3
	root.add_child(g)
	await process_frame
	for wi in Campaign.WORLDS.size():
		g.launch(wi * Campaign.PER_WORLD)
		g.touching = true
		for i in 3:
			g.step(1.0 / 60.0)
			await process_frame
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		g.stage_t = 0.0
		g.spawn_vert("gull", 0.0, 0, 1, "left")
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.hp = 1e6
		await run(1.0, f)
		while absf(g.seen(f.pos).x) > 1.5:
			await run(0.1, f)
		await shot("%d-%s-a" % [wi + 1, f.kind])
		var at := cam_at(f.pos)
		print("at ", wi + 1, " ", at.x, " ", at.y)
		g.kill(f)
		await run(0.55, null)
		await shot("%d-%s-b" % [wi + 1, f.kind])
		await run(0.75, null)
		await shot("%d-%s-c" % [wi + 1, f.kind])
	quit()


func run(secs: float, f: Game.Obj) -> void:
	var t := 0.0
	while t < secs:
		g.hp = 5
		g.time_k = 1.0
		g.touching = true
		g.fire_cd = 99.0   # hold fire
		for o in g.foes:
			o.hacked = false
		if f != null:
			# keep the ship out of the way, low on the screen
			g.prel = Vector2(-4.0 if f.pos.x > 0.0 else 4.0, g.view_bot - 4.0)
		g.step(1.0 / 60.0)
		t += 1.0 / 60.0
		await process_frame


## Where a point shows on the screen (px), for cropping.
func cam_at(p: Vector3) -> Vector2:
	return g.get_viewport().get_camera_3d().unproject_position(p)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
