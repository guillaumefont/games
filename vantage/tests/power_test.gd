extends SceneTree
## Battery: the frame rate cap by moment (60 in flight, 30 in the hangar, the results and a
## full pause) and the 3D view's resolution cap on big screens. Runs headless:
##   godot --headless --path . --script tests/power_test.gd

const SAVE := "user://test_power_save.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func render_scale() -> void:
	print("3D resolution")
	check(Game.render_scale(720.0) == 1.0 and Game.render_scale(1080.0) == 1.0, "720 and 1080 px wide screens draw the 3D view at full size")
	check(Game.render_scale(1260.0) == 1.0, "a 1260 px wide screen draws it at full size too")
	check(is_equal_approx(Game.render_scale(1440.0), 0.875), "a 1440 px wide screen draws it 1260 px wide (0.875)")
	check(Game.render_scale(5000.0) == 0.5 and Game.render_scale(0.0) == 1.0, "never below half size, and a zero size is harmless")


func frame_cap() -> void:
	print("frame rate")
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	await process_frame
	var vp := g.get_viewport()
	check(vp.scaling_3d_scale == Game.render_scale(g.get_window().size.x), "the view's 3D scale is set from the window's width")
	check(g.phase == "hangar" and g.fps_cap() == Game.IDLE_FPS, "the hangar runs at %d fps" % Game.IDLE_FPS)
	g.launch(0)
	g.touching = true
	for i in 30:
		g.tick(1.0 / 60.0)
	check(g.phase == "vert" and g.fps_cap() == Game.PLAY_FPS, "flying with a finger down runs at %d fps" % Game.PLAY_FPS)
	g.touching = false
	g.tick(1.0 / 60.0)
	check(not g.paused() and g.fps_cap() == Game.PLAY_FPS, "the slow-motion on lifting the finger stays smooth")
	for i in int(Rules.SLOW_STOP * 60.0) + 10:
		g.tick(1.0 / 60.0)
	check(g.paused() and g.fps_cap() == Game.IDLE_FPS, "a full pause drops to %d fps" % Game.IDLE_FPS)
	g.touching = true
	g.tick(1.0 / 60.0)
	check(g.fps_cap() == Game.PLAY_FPS, "touching again is back to %d fps at once" % Game.PLAY_FPS)
	g.end_run(true)
	check(g.phase == "results" and g.fps_cap() == Game.IDLE_FPS, "the results run at %d fps" % Game.IDLE_FPS)
	g.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _initialize() -> void:
	print("Vantage power test")
	render_scale()
	await frame_cap()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
