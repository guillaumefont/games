extends SceneTree
## In-level power: a level's start on the twin gun, a power core falling, and full power.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/power_shots.gd -- /tmp/power

var g: Game
var out := "/tmp/power"


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func play(secs: float) -> void:
	for i in int(secs * 60.0):
		g.hp = maxi(g.hp, 2)
		g.prel.x = lerpf(g.prel.x, sin(g.stage_t * 0.9) * 3.0, 0.05)
		g.step(1.0 / 60.0)
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://power_save.json"
	var s := Rules.fresh()
	s.up.cannon = 5
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	g.launch(0)
	g.time_k = 1.0
	await play(3.0)
	await shot("1-start-twin-gun")
	g.drop_core(g.ppos + Vector3(0, 0, -7))
	await play(0.6)
	await shot("2-power-core")
	g.power = Rules.POWER_MAX
	g.hud.ping_power()
	await play(0.3)
	await shot("3-full-power")
	quit()
