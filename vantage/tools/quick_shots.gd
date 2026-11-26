extends SceneTree
## Iron Sprawl's first two levels in play, every few seconds, to check that foes and bullets
## stand out against the city (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/city_shots.gd -- /tmp/city

var out := "/tmp/city"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick() -> void:
	g.hp = maxi(g.hp, 2)
	if g.phase == "vert":
		var tx := sin(g.stage_t * 0.9) * 3.5
		if not g.boss_parts.is_empty():
			tx = g.boss_parts[0].pos.x
		g.prel.x = lerpf(g.prel.x, tx, 0.05)
	g.step(1.0 / 60.0)
	await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://worlds_save.json"
	var s := Rules.fresh()
	s.scrap = 1450
	s.up.cannon = 3
	s.up.missile = 2
	s.open = Campaign.count() - 1
	s.grades = {"1-1": "S", "1-2": "A", "1-3": "B", "2-1": "A"}
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	for lv in 1:
		g.to_hangar()
		g.pick_level(2 * Campaign.PER_WORLD + 1 + lv)
		g.launch()
		for k in 3:
			for i in 60 * (5 if k == 0 else 6):
				await tick()
			await shot("city-%d-%d" % [lv, k])
	quit()
