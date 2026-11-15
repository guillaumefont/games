# Graphics quality switch: the first switch into Low (or back up from a Low start) compiles new
# shaders and froze the game for a moment with nothing on screen (the "slow switch to Low" case).
# That switch now runs behind the static loading screen, drawn before the freeze; switches
# between shader sets already drawn this run stay instant, with no screen.
#   godot --headless --path . --script tests/quality_switch_test.gd
extends SceneTree

const Settings = preload("res://scripts/settings.gd")
var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	root.size = Vector2i(1280, 720)
	var cfg := Settings._load()
	cfg.set_value("options", "tutorial_done", true)
	var was = Settings.get_opt("quality")
	Settings.set_opt("quality", 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var ui = main.ui
	var view = main.view
	ui.loading.visible = false

	# Medium -> High: same shaders, no screen
	main._option_changed("quality", 2)
	await frames(1)
	check(view.quality == 2 and not ui.loading.visible, "Medium to High is instant, no loading screen")

	# High -> Low the first time: the screen is up before the quality changes
	main._option_changed("quality", 0)
	await frames(1)
	check(ui.loading.visible, "first switch to Low shows the loading screen")
	check(view.quality == 2, "the quality changes only once the screen is drawn")
	await frames(6)
	check(view.quality == 0, "Low is applied")
	var t0 := Time.get_ticks_msec()
	while ui.loading.visible and Time.get_ticks_msec() - t0 < 5000:
		await frames(1)
	check(not ui.loading.visible, "the loading screen goes away")

	# both sets drawn now: Low and back are instant
	main._option_changed("quality", 0)
	await frames(1)
	check(view.quality == 0 and not ui.loading.visible, "switching to Low again is instant (q %d, screen %s)" % [view.quality, ui.loading.visible])
	main._option_changed("quality", 2)
	await frames(1)
	check(view.quality == 2 and not ui.loading.visible, "and back up too")

	# a new run (only Medium/High drawn): a tap during the screen is kept, the last one wins
	view._drawn_sets.clear()
	view._drawn_sets[1] = true
	main._option_changed("quality", 0)
	main._option_changed("quality", 2)
	t0 = Time.get_ticks_msec()
	while (ui.loading.visible or main._quality_busy) and Time.get_ticks_msec() - t0 < 5000:
		await frames(1)
	check(view.quality == 2, "a second tap during the screen is applied after it (quality %d)" % view.quality)

	Settings.set_opt("quality", was if was != null else Settings.default_quality())
	if fails > 0:
		printerr("quality_switch_test: %d failure(s)" % fails)
		quit(1)
	else:
		print("quality_switch_test: ok")
		quit(0)
