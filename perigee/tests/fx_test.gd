extends SceneTree
## Headless test of the light and feel pass: the living sky (nebula, stars, far planets, shooting
## stars), the additive glow layer, shockwaves and the screen flash on catches, the combo-tinted
## trail, and score text that pops in above the caught moon. Reduced motion leaves out the flash,
## the pop and the shooting stars. Looks only, so it also checks the sim is untouched.
## Run: godot --headless --path perigee --script tests/fx_test.gd
## Last line on success: FX TEST DONE

const SAVE := "user://fx_test_save.json"

var main: Node2D
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func tick(seconds: float) -> void:
	for i in int(round(seconds / Sim.DT)):
		main.advance(Sim.DT)


func catch_event(perigee: bool, skipped := 0) -> Dictionary:
	var p: Sim.Player = main.sim.player
	return {"type": "capture", "x": p.x, "y": p.y, "col": 0, "first": true, "perigee": perigee,
		"points": 2 if perigee else 1, "skipped": skipped, "leap_points": 3, "kind": "", "hops": 1, "mult": 2}


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	main.vis_seed = 7
	main.ready.connect(func() -> void: main.save.data.tutorial_done = true)
	root.add_child(main)
	main.set_process(false)
	await process_frame
	print("Perigee fx test")

	# --- layers ---
	var sky: SkyLayer = main.sky
	var glow: GlowLayer = main.glow
	check(sky != null and sky.get_parent() == main and sky.show_behind_parent, "the sky is drawn behind the game")
	check(glow != null and glow.get_parent() == main and glow.get_index() > sky.get_index(), "the glow layer is drawn over the game")
	var mat := glow.material as CanvasItemMaterial
	check(mat != null and mat.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "the glow layer adds light (additive blending)")
	check(sky.nebula != null and sky.nebula.get_width() == SkyLayer.NEBULA_W and sky.nebula.get_height() == SkyLayer.NEBULA_H,
		"the nebula is a small texture made once")
	var img := sky.nebula.get_image()
	var top_row := 0.0
	var bottom_row := 0.0
	var dense := 0
	for x in SkyLayer.NEBULA_W:
		top_row += img.get_pixel(x, 0).a
		bottom_row += img.get_pixel(x, SkyLayer.NEBULA_H - 1).a
	for y in range(0, SkyLayer.NEBULA_H, 4):
		for x in range(0, SkyLayer.NEBULA_W, 4):
			if img.get_pixel(x, y).a > 0.1:
				dense += 1
	var cells := (SkyLayer.NEBULA_W / 4) * (SkyLayer.NEBULA_H / 4)
	check(absf(top_row - bottom_row) / SkyLayer.NEBULA_W < 0.06, "the nebula tiles without a seam (%.2f vs %.2f)" % [top_row, bottom_row])
	check(dense > cells / 10 and dense < cells * 3 / 4, "the nebula has clouds and clear sky (%d of %d)" % [dense, cells])
	check(sky.stars.size() >= 100 and sky.planets.size() >= 2, "stars and far planets fill the sky")
	check(main.bloom_texture() != null, "one bloom texture serves every halo")

	# --- the sim is untouched: same seed, same world as a bare Sim ---
	# the old star field took 560 numbers from the looks RNG before the first world's seed; the
	# seeds tests pin with vis_seed must stay the same
	var old := RandomNumberGenerator.new()
	old.seed = 7
	for i in 560:
		old.randf()
	check(main.sim.seed_value == old.randi(), "the worlds' seeds are the same as before the new sky")
	var bare := Sim.new(main.sim.seed_value, main.sim.W, main.sim.H)
	check(bare.planets.size() == main.sim.planets.size() and is_equal_approx(bare.planets[1].y, main.sim.planets[1].y),
		"the looks do not change the world")

	# --- catches ---
	tick(0.3)
	var pl = main.sim.player.planet
	check(pl != null, "the ship orbits a moon")
	main.sim.events.append(catch_event(false))
	main._handle_events()
	check(main.shockwaves.size() == 1, "a catch sends out a shockwave")
	check(main.pulse == 0.0, "a plain catch does not flash the screen")
	var pop: Dictionary = main.popups[-1]
	check(pop.y < pl.y - pl.pr, "the score text sits above the moon, not over it (%.0f < %.0f)" % [pop.y, pl.y - pl.pr])
	main.sim.events.append(catch_event(true, 1))
	main._handle_events()
	check(main.shockwaves.size() == 4, "a perigee and a leap send out more rings (%d)" % main.shockwaves.size())
	check(main.pulse > 0.1 and main.pulse_col == main.CORAL, "a leap flashes the screen coral (%.2f)" % main.pulse)
	var texts: Array = main.popups.map(func(q: Dictionary) -> String: return q.text)
	check(texts.has("Perigee +2") and texts.has("Leap ×1  +3"), "perigee and leap text show (%s)" % [texts])
	tick(1.5)
	check(main.shockwaves.is_empty() and main.pulse == 0.0 and main.popups.is_empty(), "rings, flash and text fade away")

	# --- popping text and the combo trail ---
	check(main.popup_scale(0.0) < 0.5 and main.popup_scale(0.12) > 1.05 and is_equal_approx(main.popup_scale(0.5), 1.0),
		"score text pops in with an overshoot (%.2f, %.2f, %.2f)" % [main.popup_scale(0.0), main.popup_scale(0.12), main.popup_scale(0.5)])
	check(GlowLayer.combo_color(1) == GlowLayer.INK and GlowLayer.combo_color(2) == GlowLayer.TEAL and GlowLayer.combo_color(5) == GlowLayer.CORAL
		and GlowLayer.combo_color(9) == GlowLayer.CORAL, "the trail warms up with the combo")

	# --- shooting stars come and go ---
	var seen := false
	for i in 60 * 30:
		sky.tick(1.0 / 60.0)
		if not sky.meteor.is_empty():
			seen = true
	check(seen, "a shooting star crosses the sky now and then")

	# --- reduced motion ---
	main.change_setting("reduced_motion", true)
	sky.meteor = {}
	var any := false
	for i in 60 * 30:
		sky.tick(1.0 / 60.0)
		if not sky.meteor.is_empty():
			any = true
	check(not any, "reduced motion: no shooting stars")
	main.sim.events.append(catch_event(true, 2))
	main._handle_events()
	check(main.pulse == 0.0, "reduced motion: no screen flash")
	check(main.shockwaves.size() > 0, "reduced motion keeps the rings (they show the catch)")

	# draws without errors in every state
	main.advance(Sim.DT)
	await process_frame
	main.sim.die("Drifted off into the dark")
	main._handle_events()
	main.advance(Sim.DT)
	await process_frame
	check(true, "draws through a catch and a game over")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d failures" % fails)
	print("FX TEST DONE" if fails == 0 else "FX TEST FAILED")
	quit(1 if fails > 0 else 0)
