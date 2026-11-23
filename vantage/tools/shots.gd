extends SceneTree
## Screenshots of the real game for PRs (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/shots.gd -- /tmp/shots
## The game is driven (fixed 1/60 s steps, one per rendered frame) with a simple autopilot
## that weaves in the vertical stage and lines up with the nearest foe in the chase.

var out := "/tmp/shots"
var g: Game
var wanted := {}
var taken := {}


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func tick() -> void:
	g.hp = maxi(g.hp, 2)
	if g.phase == "vert":
		g.prel.x = lerpf(g.prel.x, sin(g.stage_t * 0.9) * 3.5, 0.05)
	if g.pov_mode():
		var best: Game.Obj = null
		for f in g.foes:
			if f.kind != "orb" and not f.dead and not (f.kind == "core" and g.shielded()) and not g.cam.is_position_behind(f.pos):
				if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
					best = f
		if best:
			g.off = g.off.lerp(Vector2(best.pos.x, best.pos.y - Rules.PY), 0.06)
	g.step(1.0 / 60.0)
	await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://shots_save.json"
	var s := Rules.fresh()
	s.scrap = 1450
	s.up.cannon = 2
	s.up.missile = 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	g.rng.seed = 7
	root.add_child(g)
	await process_frame
	for i in 40:
		await tick()
	await shot("1-hangar")
	g.launch()
	var marks := {"2-vertical": func() -> bool: return g.phase == "vert" and g.stage_t > 16.2,
		"3-swoop": func() -> bool: return g.phase == "approach" and g.phase_t > 1.3,
		"4-tail": func() -> bool: return g.phase == "pov" and g.phase_t > 0.6,
		"5-chase": func() -> bool: return g.phase == "pov" and g.rail_s > 150.0,
		"6-reactor": func() -> bool: return g.phase == "core" and g.phase_t > 2.0,
		"7-carrier-down": func() -> bool: return g.phase == "escape" and g.phase_t > 1.1,
		"7b-climb-out": func() -> bool: return g.phase == "exit" and g.phase_t > 0.7,
		"8-boss": func() -> bool: return g.boss != null and g.boss.t > 6.0,
		"9-results": func() -> bool: return g.phase == "results" and g.phase_t > 1.0}
	for i in 60 * 150:
		await tick()
		for k: String in marks:
			if not taken.has(k) and marks[k].call():
				taken[k] = true
				await shot(k)
		if taken.size() == marks.size():
			break
	quit()
