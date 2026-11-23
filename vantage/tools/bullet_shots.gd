extends SceneTree
## Enemy bullets and the ship's shots over every world's ground, no foes (readability check).
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/bullet_shots.gd -- /tmp/bullets

var out := "/tmp/bullets"
var g: Game


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://bullet_shots_save.json"
	var s := Rules.fresh()
	s.up.cannon = 3
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	for w in Campaign.WORLDS.size():
		g.to_hangar()
		g.launch(w * Campaign.PER_WORLD + 1)
		for i in 60 * 6:
			g.hp = maxi(g.hp, 2)
			g.step(1.0 / 60.0)
		for b in g.bullets:
			b.node.visible = false
		# a spread of bullets across the field, ahead of the ship
		for i in 7:
			for j in 4:
				g.bullet(Vector3(-6.0 + i * 2.0, Rules.PY, g.frame_z - 4.0 - j * 3.0 + (i % 2) * 1.2), Vector3.ZERO)
		g.step(1.0 / 60.0)
		g.time_k = 1.0   # no pause dimming
		for f in g.foes:
			f.node.visible = false   # only bullets on the ground
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%d.png" % [out, w + 1])
		print("shot ", w + 1)
	quit()
