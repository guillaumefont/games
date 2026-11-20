extends SceneTree
## Crash report, safe graphics and screen fill: a log without a clean ending is reported on
## the menu (with a copy button) and turns on safe graphics; every model is drawn once behind
## the menu; tall phones, 16:9 and tablets all show the whole stage width; the menu's sound
## and build lines work and best scores are saved.

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func _initialize() -> void:
	print("Star Breaker crash report + screen fill test")
	# a previous session that died mid-game
	var f := FileAccess.open(Diag.PATH, FileAccess.WRITE)
	f.store_string("   0.01 START test\n   3.20 VSTAGE 0 lance\n   6.80 FIRST venemy carrier\n   7.00 TICK t=240\n")
	f.close()
	Diag.set_safe(false)
	if FileAccess.file_exists("user://save.cfg"):
		DirAccess.remove_absolute("user://save.cfg")
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "the app runs in portrait")
	check(int(ProjectSettings.get_setting("display/window/size/viewport_width")) < int(ProjectSettings.get_setting("display/window/size/viewport_height")),
		"the base canvas is portrait")
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.set_process(false)
	await process_frame
	check(Diag.crashed, "an unfinished log is detected as a crash")
	check(Diag.safe, "safe graphics switched on after a crash")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility",
		"Android uses the Compatibility renderer (Vulkan crashed on a Pixel's PowerVR GPU)")
	for i in 6:
		await process_frame
	check(FileAccess.get_file_as_string(Diag.PATH).contains(" WARM "), "every model drawn once behind the menu")
	check(main.get_child_count() < 40, "warm-up objects are removed")
	check(Diag.summary().contains("carrier"), "summary names the last new thing: " + Diag.summary())
	check(Diag.report().contains("TICK t=240"), "report holds the previous log")
	check(main.hud._crash.visible and main.hud._btn_copy.visible, "the menu shows the crash notice with a copy button")
	check(not main._env.glow_enabled and main.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "glow and MSAA off in safe mode")
	main.hud._btn_gfx.pressed.emit()
	check(not Diag.safe and main._env.glow_enabled, "toggle back to full graphics")
	check(FileAccess.get_file_as_string(Diag.PATH).contains("START"), "this session is logging")

	# sound, build line, best scores
	main.hud.btn_mute.pressed.emit()
	check(main.muted and main.hud.btn_mute.text.contains("OFF"), "the sound button mutes")
	main.hud.btn_mute.pressed.emit()
	check(not main.muted, "and unmutes")
	main.show_update(999999)
	check(main.hud.btn_build.text.contains("BUILD") , "the build line shows the build")
	var restarted := [false]
	main.restart_fn = func(): restarted[0] = true
	main.hud.btn_build.pressed.emit()
	await create_timer(0.3).timeout
	check(restarted[0], "tapping the build line restarts to update")
	# Android restarts by killing the process: the log must say it was a clean exit
	var log_txt := FileAccess.get_file_as_string(Diag.PATH)
	var at := log_txt.find(" REFRESH")
	check(at >= 0 and log_txt.find(" QUIT", at) > at, "a refresh restart is logged as a clean exit, not a crash")
	check(main.build_number("b73 abc1234") == 73, "build number read from the version")
	main.driven = true
	main.start_stage(0, "lance")
	main.G.score = 4321
	main.finish(false)
	var cfg := ConfigFile.new()
	cfg.load("user://save.cfg")
	check(int((cfg.get_value("portrait", "bests", [0])[0])) == 4321 and main.hud._stage_btns[0].text.contains("4,321"), "a stage's best score is saved and shown")
	main.to_menu()

	# screen shapes: the whole stage width is always visible
	for sz in [Vector2i(1080, 2400), Vector2i(720, 1280), Vector2i(1536, 2048), Vector2i(1280, 720)]:
		root.size = sz
		await process_frame
		main._on_resize()
		var vs: Vector2 = main.get_viewport().get_visible_rect().size
		var cam: Camera3D = main.camera
		var l := cam.unproject_position(Vector3(main.X(0), main.Y(112), 0))
		var r := cam.unproject_position(Vector3(main.X(main.W), main.Y(112), 0))
		var top := cam.unproject_position(Vector3(main.X(63), main.Y(main.H), 0))
		check(l.x >= -1 and r.x <= vs.x + 1 and top.y >= -1, "%s: the whole stage is on screen" % sz)

	Diag.note("QUIT")
	Diag.set_safe(false)
	print("FAILED %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)
