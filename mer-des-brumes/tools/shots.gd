extends SceneTree
## Screenshots of the real game for PRs (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/shots.gd -- /tmp/shots

var out := "/tmp/shots"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://shots_save.json"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.rng.seed = 7
	root.add_child(g)
	await frames(30)
	g.P.h = 2.6
	g.throttle = 0.8
	await frames(90)
	await shot("1-sea")
	# a fight: an enemy off our quarter
	var e: Game.Boat = g.enemies[0]
	var pp := g.P.pos()
	g.P.node.position = Vector3(60, 0, 60)
	g.camera.position = g.P.node.position + g.cam_off
	e.node.position = Vector3(72, 0, 66)
	e.h = 2.0
	g.start_combat(e, "pending")
	await frames(40)
	await shot("2-attack")
	g.on_fight()
	await frames(150)
	await shot("3-fight")
	g.end_combat()
	g.P.node.position = Rules.DOCK
	g.camera.position = g.P.node.position + g.cam_off
	g.s.coins = 6200
	g.open_port()
	await frames(10)
	await shot("4-port-coffre")
	g.hud._tab = "bateau"
	g.hud.refresh_port()
	await frames(30)
	await shot("5-port-chantier")
	g.hud._pv_idx = 2
	g.hud.refresh_port()
	await frames(30)
	await shot("6-port-fregate")
	g.hud._tab = "equipage"
	g.hud.refresh_port()
	await frames(5)
	await shot("7-port-equipage")
	g.hud._tab = "base"
	g.hud.refresh_port()
	await frames(5)
	await shot("8-port-fort")
	quit()
