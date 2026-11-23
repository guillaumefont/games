extends SceneTree
## Quick look at the final boss, the flying fortress, without playing the stage (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/fortress_shots.gd -- /tmp/fortress
## From above as it arrives, the swoop, each section in the chase, then its fall out of the sky.

var out := "/tmp/fortress"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick(n := 1) -> void:
	for i in n:
		g.hp = maxi(g.hp, 2)
		g.step(1.0 / 60.0)
		await process_frame


## Shoots down the current section's parts (panels before the reactor).
func clear_section() -> void:
	var parts: Array = g.fort_parts.duplicate()
	parts.sort_custom(func(a: Game.Obj, b: Game.Obj) -> bool: return a.kind != "core" and b.kind == "core")
	for p: Game.Obj in parts:
		if not p.dead:
			g.damage(p, 99999.0)
		await tick(6)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://fortress_shots_save.json"
	Rules.save_game(Rules.fresh(), tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	g.launch()
	await tick(60)
	g.wave_i = Rules.STAGE.size()
	g.spawn_fortress()
	while g.phase == "vert":
		await tick()
	await shot("1-arrives")
	await tick(int(Rules.APPROACH * 60 * 0.5))
	await shot("2-swoop")
	while g.phase != "pov":
		await tick()
	await tick(90)
	await shot("3-tail-guns")
	# the whole aircraft, from a camera off to its side (the game's camera is put back next step)
	var env: Environment = (g.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
	env.fog_enabled = false
	g.cam.far = 2000.0
	var mid := g.fort_point(Vector3(0, 8.0, -75.0))
	g.cam.global_transform = Transform3D(Basis(), mid + Vector3(-210.0, 110.0, 230.0)).looking_at(mid, Vector3.UP)
	await shot("3a-overview")
	g.cam.global_transform = Transform3D(Basis(), mid + Vector3(0.0, 420.0, 1.0)).looking_at(mid, Vector3.UP)
	await shot("3c-from-above")
	env.fog_enabled = true
	g.cam.far = 400.0
	g.off = Vector2(-Rules.POV_REACH.x, 10.0)
	await tick(60)
	await shot("3b-flank")
	g.off = Vector2.ZERO
	await clear_section()
	await tick(60)
	await shot("4-gun-tower")
	await clear_section()
	await tick(90)
	await shot("5-reactor")
	await clear_section()
	for t in [0.6, 1.5, 2.4, 3.3, 4.2]:
		while g.phase == "escape" and g.phase_t < t:
			await tick()
		await shot("6-down-%.1f" % t)
		if t == 2.4:
			env = (g.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
			env.fog_enabled = false
			g.cam.far = 2000.0
			var at := g.fortress.global_position + Vector3(-20.0, -20.0, -80.0)
			g.cam.global_transform = Transform3D(Basis(), at + Vector3(-200.0, 60.0, 190.0)).looking_at(at, Vector3.UP)
			await shot("6-down-overview")
			env.fog_enabled = true
			g.cam.far = 400.0
	quit()
