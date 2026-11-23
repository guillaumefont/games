extends SceneTree
## Quick look at the final boss, the capital ship, without playing the stage (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/fortress_shots.gd -- /tmp/fortress [id]
## From above as it arrives, the swoop, each section in the chase (and the glide to the next), an
## overview with no fog, then its break-up in the air.

var out := "/tmp/fortress"
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


## Shoots down the current section's parts (pylons and panels first).
func clear_section() -> void:
	var parts: Array = g.fort_parts.duplicate()
	parts.sort_custom(func(a: Game.Obj, b: Game.Obj) -> bool: return a.kind in ["pylon", "panel"] and b.kind not in ["pylon", "panel"])
	for p: Game.Obj in parts:
		if not p.dead:
			g.damage(p, 99999.0)
		await tick(8)


func overview(name: String, from: Vector3, at: Vector3) -> void:
	var env: Environment = (g.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
	env.fog_enabled = false
	g.cam.far = 2000.0
	g.cam.global_transform = Transform3D(Basis(), from).looking_at(at, Vector3.UP)
	await shot(name)
	env.fog_enabled = true
	g.cam.far = 400.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var id := args[1] if args.size() > 1 else "goliath"
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://fortress_shots_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	var lv := 0
	while Campaign.fortress_of(lv) != id:
		lv += 1
	g.launch(lv)
	await tick(30)
	g.boss_done = true
	for k in g.waves.size():
		if g.waves[k].kind == "fortress":
			g.wave_i = k
			g.stage_t = g.waves[k].t
	while g.phase == "vert":
		await tick()
	await shot("1-arrives")
	await tick(int(Rules.APPROACH * 60 * 0.5))
	await shot("2-swoop")
	while g.phase != "pov":
		await tick()
	await tick(90)
	await shot("3-engines")
	var L := Rules.fortress_len(id)
	var mid := g.fort_point(Vector3(0, 0, -L * 0.5))
	await overview("3a-overview", mid + Vector3(-190.0, 120.0, 210.0), mid)
	await overview("3b-from-above", mid + Vector3(0.0, 380.0, 1.0), mid)
	g.off = Vector2(-Rules.POV_REACH.x, 6.0)
	await tick(60)
	await shot("3c-flank")
	g.off = Vector2.ZERO
	var n := 4
	while g.phase == "pov":
		await clear_section()
		await tick(40)
		await shot("%d-glide" % n)
		await tick(100)
		await shot("%d-%s" % [n, g.fort.sections[g.fort_sec].name.to_lower().replace(" ", "-")])
		n += 1
	await tick(60)
	await shot("%d-reactor-open" % n)
	await clear_section()
	for t in [0.3, 1.0, 1.8, 2.6, 3.4, 4.4, 5.6]:
		while g.phase == "escape" and g.phase_t < t:
			await tick()
		await shot("9-breakup-%.1f" % t)
		if t == 2.6 and g.fortress:
			var at := g.fortress.global_position + Vector3(0, 0, -L * 0.5)
			await overview("9-breakup-overview", at + Vector3(-220.0, 90.0, 120.0), at)
	quit()
