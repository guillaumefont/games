extends SceneTree
## Screenshots of every campaign foe (`Foes.INTRO`) in play over its world, a moment after it
## comes in (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/foe_shots.gd -- /tmp/foes

var out := "/tmp/foes"
var g: Game


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://foe_shots_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	s.up.cannon = 2
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 3
	root.add_child(g)
	await process_frame
	var wait := {"gull": 1.2, "borer": 2.4, "gunship": 2.4, "lancer": 1.7, "prism": 3.0, "tank": 2.6, "hover": 2.4,
		"aa": 2.6, "mortar": 2.8, "pillbox": 2.4, "seeker": 1.8, "wyrm": 2.6}
	for lv in Foes.INTRO.size():
		var kind: String = Foes.INTRO[lv]
		g.launch(lv)
		g.touching = true
		for i in 3:
			g.step(1.0 / 60.0)
			await process_frame
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = lv
		var w := Campaign.new_wave(kind, rng, 1.0)
		for i in int(w.n):
			g.queue.append({"at": g.stage_t + i * float(w.gap), "kind": kind, "x": float(w.x), "i": i, "n": int(w.n),
				"from": w.get("from", "top")})
		var t := 0.0
		while t < float(wait.get(kind, 2.0)):
			g.hp = 5
			g.time_k = 1.0
			g.touching = true
			g.fire_cd = 99.0   # hold fire, so the foes stay whole for the picture
			g.run_waves()
			g.step(1.0 / 60.0)
			for f in g.foes:
				f.hp = maxf(f.hp, 1.0)
			t += 1.0 / 60.0
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d-%s.png" % [out, lv + 1, kind])
		print("shot ", kind)
	quit()
