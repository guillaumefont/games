extends SceneTree
## Every fortress side by side (needs a display): each one from above as it arrives, on its tail
## in the chase, an overview with no fog, and in the chase after its first section breaks off.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/fortress_lineup.gd -- /tmp/fortresses

var out := "/tmp/fortresses"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick(n := 1) -> void:
	for i in n:
		g.hp = maxi(g.hp, 2)
		g.time_k = 1.0
		g.step(1.0 / 60.0)
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://fortress_lineup_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	var env: Environment = (g.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
	var n := 1
	for id: String in Rules.FORTRESSES:
		var lv := 0
		while Campaign.fortress_of(lv) != id:
			lv += 1
		g.to_hangar()
		g.launch(lv)
		await tick(30)
		g.boss_done = true
		for k in g.waves.size():
			if g.waves[k].kind == "fortress":
				g.wave_i = k
				g.stage_t = g.waves[k].t
		while g.phase == "vert":
			await tick()
		await shot("%d-%s-1-above" % [n, id])
		while g.phase != "pov":
			await tick()
		await tick(90)
		await shot("%d-%s-2-chase" % [n, id])
		env.fog_enabled = false
		g.cam.far = 2000.0
		var mid := g.fort_point(Vector3(0, 8.0, -60.0))
		g.cam.global_transform = Transform3D(Basis(), mid + Vector3(-200.0, 100.0, 220.0)).looking_at(mid, Vector3.UP)
		await shot("%d-%s-3-overview" % [n, id])
		env.fog_enabled = true
		g.cam.far = 400.0
		for p in g.fort_parts.duplicate():
			g.damage(p, 99999.0)
		g.off = Vector2(0, 8.0)
		await tick(100)
		await shot("%d-%s-4-section2" % [n, id])
		n += 1
	quit()
