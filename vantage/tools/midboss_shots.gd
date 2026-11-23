extends SceneTree
## Every mid-boss without playing its level's waves (needs a display): each one as it arrives,
## then after its first section has broken off.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/midboss_shots.gd -- /tmp/midbosses

var out := "/tmp/midbosses"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick(n := 1) -> void:
	for i in n:
		g.hp = maxi(g.hp, 2)
		g.time_k = 1.0
		if not g.boss_parts.is_empty() and g.boss.t > 3.0:
			g.prel.x = lerpf(g.prel.x, g.boss_parts[0].pos.x, 0.05)
		g.step(1.0 / 60.0)
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://midboss_shots_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	s.up.cannon = 3
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	var n := 1
	for id: String in Rules.MIDBOSSES:
		var lv := 0
		while Campaign.midboss_of(lv) != id:
			lv += 1
		g.to_hangar()
		g.launch(lv)
		await tick()
		# straight to the mid-boss's wave
		for k in g.waves.size():
			if g.waves[k].kind == "boss":
				g.wave_i = k
				g.stage_t = g.waves[k].t
		while g.boss == null or g.boss.t < 4.5:
			await tick()
		await shot("%d-%s-a" % [n, id])
		for p in g.boss_parts.duplicate():
			g.damage(p, 99999.0)
		await tick(150)
		await shot("%d-%s-b" % [n, id])
		n += 1
	quit()
