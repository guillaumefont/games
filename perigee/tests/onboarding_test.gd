extends SceneTree
## The first-run tutorial and the settings screen.
## Run: godot --headless --path perigee --script tests/onboarding_test.gd
## Last line on success: ONBOARDING TEST DONE

const SAVE := "user://onboarding_test_save.json"
const Bot = preload("res://tests/sim_test.gd").Bot

var fails := 0
var main: Node2D


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func tick(seconds: float) -> void:
	for i in int(round(seconds / Sim.DT)):
		main.advance(Sim.DT)


func button(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = Vector2(200, 400)
	main._unhandled_input(e)


func new_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	main.set_process(false)


func play_bot(seconds: float, deep := false) -> void:
	var bot = Bot.new()
	bot.deep = deep
	for i in int(seconds * 120):
		match bot.decide(main.sim):
			"press":
				main.on_press()
			"release":
				main.on_release()
			"tap":
				main.on_press()
				main.on_release()
		main.advance(Sim.DT)
		if main.sim.state != "play":
			break


func _initialize() -> void:
	print("Perigee onboarding test")

	# --- the tutorial's rules: a miss puts you back on the last moon ---
	var s := Sim.new(main_seed(), 400, 700)
	s.recipe = {"moons": 6, "rescue": true}
	s.new_run(4242)
	s.press()
	s.release()
	for i in 120 * 8:
		s.step()
		if s.state != "play" or s.events.any(func(e): return e.type == "rescue"):
			break
	check(s.state == "play" and s.player.planet == s.planets[0] and s.events.any(func(e): return e.type == "rescue"),
		"in the tutorial, drifting off puts you back in orbit round the moon you left")
	s.step()
	check(s.state == "play" and s.player.planet != null, "and the run goes on")

	# --- first run: the start card leads to the tutorial ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	new_main()
	await process_frame
	check(main.hud.start_pill_label.text == "Tap to learn to fly", "a first run offers the tutorial (%s)" % main.hud.start_pill_label.text)
	button(true)
	button(false)
	tick(0.1)
	check(main.mode == "tutorial" and main.sim.state == "play" and not main.hud.start_card.visible, "the first tap starts the tutorial")
	check(main.sim.player.planet != null, "and does not fling")
	check(main.hud.hint_label.text == "Tap to fling off your moon", "it says what to do (%s)" % main.hud.hint_label.text)
	# miss on purpose: fling and never hold
	main.on_press()
	main.on_release()
	tick(0.2)
	check(main.hud.hint_label.text == "Hold when you reach the dotted ring", "in flight it says when to hold (%s)" % main.hud.hint_label.text)
	for i in 120 * 8:
		main.advance(Sim.DT)
		if main.tutorial_misses > 0:
			break
	check(main.tutorial_misses == 1 and main.sim.state == "play" and main.hud.hint_label.text.begins_with("Missed"),
		"a miss is not game over (%s)" % main.hud.hint_label.text)
	play_bot(90.0, true)
	check(main.sim.state == "clear", "the bot finishes the tutorial")
	tick(1.0)
	check(main.hud.clear_card.visible and main.hud.clear_title.text == "You're ready to fly" and not main.hud.clear_big.visible,
		"a last card with tips")
	var saved := SaveData.new(SAVE)
	saved.load_file()
	check(saved.data.tutorial_done and saved.data.best == 0, "the tutorial is marked done, and never sets the best")
	main.on_press()
	main.on_release()
	tick(0.1)
	check(main.mode == "endless" and main.sim.state == "play" and main.sim.recipe.is_empty(), "a tap goes on to Drift")

	# --- after a restart: no tutorial, the start card plays Drift ---
	main.queue_free()
	await process_frame
	new_main()
	await process_frame
	check(main.hud.start_pill_label.text == "Tap to play Drift", "the tutorial is offered once")

	# --- settings ---
	var sb: Button = main.hud.start_card.find_child("Settings", true, false)
	check(sb != null, "the start card has a Settings button")
	sb.pressed.emit()
	check(main.hud.settings_card.visible and not main.hud.start_card.visible, "it opens the settings card")
	var music: HSlider = main.hud.settings_sliders.music_volume
	check(is_equal_approx(music.value, 0.7), "sliders show the saved volumes (%.1f)" % music.value)
	music.value = 0.3
	var mi := AudioServer.get_bus_index("Music")
	check(absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.3)) < 0.01, "the music slider sets the Music bus")
	main.hud.settings_sliders.sfx_volume.value = 0.0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Sfx")), "effects at zero are muted")
	for key in ["vibration", "aim_guide", "reduced_motion", "high_contrast"]:
		var b: Button = main.hud.settings_toggles[key]
		var before := bool(main.save.get_setting(key))
		b.button_pressed = not before
		check(bool(main.save.get_setting(key)) == not before and b.text == b.get_meta("labels")[0 if not before else 1],
			"%s toggles (%s)" % [key, b.text])
	main.hud.settings_card.find_child("Done", true, false).pressed.emit()
	check(not main.hud.settings_card.visible and main.hud.start_card.visible, "Done goes back to the start card")
	main.queue_free()
	await process_frame
	new_main()
	await process_frame
	check(is_equal_approx(float(main.save.get_setting("music_volume")), 0.3) and main.save.get_setting("aim_guide") == true
		and main.save.get_setting("vibration") == false, "settings are kept after a restart of the app")
	# the aim guide shows the fling guide past the first hops; the view must still draw
	main.start_mode("endless")
	main.sim.hops = 10
	tick(0.1)
	main.queue_redraw()
	await process_frame
	check(main.sim.state == "play", "drawing with every option on works")
	# How to play replays the tutorial
	main.sim.die("test")
	tick(0.6)
	main.open_settings()
	main.hud.settings_card.find_child("HowToPlay", true, false).pressed.emit()
	tick(0.1)
	check(main.mode == "tutorial" and main.sim.state == "play" and not main.hud.settings_card.visible, "How to play replays the tutorial")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("ONBOARDING TEST DONE")
		quit(0)


func main_seed() -> int:
	return 4242
