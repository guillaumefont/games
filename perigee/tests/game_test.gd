extends SceneTree
## Headless test of the game scene: start card, input through the real input path, HUD,
## game over card, best score saved to the versioned save file, restart, pausing when the app
## loses focus (with the resume countdown), and the sound setting being kept.
## Run: godot --headless --path perigee --script tests/game_test.gd
## Last line on success: GAME TEST DONE

const SAVE := "user://game_test_save.json"

var main: Node2D
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func tick(seconds: float) -> void:
	for i in int(round(seconds / Sim.DT)):
		main.advance(Sim.DT)


## The one button, through Godot's input like a real tap (mouse emulates touch).
func button(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = Vector2(200, 400)
	main._unhandled_input(e)


func key(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SPACE
	e.pressed = down
	main._unhandled_input(e)


func new_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	# a fixed world: with a random one the bot below sometimes crashes before moon 5
	main.vis_seed = int(OS.get_environment("PERIGEE_TEST_SEED")) if OS.has_environment("PERIGEE_TEST_SEED") else 7
	# the first-run tutorial has its own test
	main.ready.connect(func() -> void: main.save.data.tutorial_done = true)
	root.add_child(main)
	main.set_process(false)


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	new_main()
	await process_frame
	print("Perigee game test")
	check(main.sim.state == "start" and main.hud.start_card.visible, "starts on the start card")
	check(main.hud.score_label.text == "0" and main.hud.best_label.text == "Best 0", "HUD shows score 0 and best 0")
	tick(0.5)
	check(main.sim.player.planet != null and main.sim.t > 0.4, "the ship orbits behind the start card")

	button(true)
	button(false)
	tick(0.1)
	check(main.sim.state == "play" and not main.hud.start_card.visible, "a tap starts the game and hides the card")
	check(main.sim.player.planet != null, "the starting tap does not fling")
	check(main.hud.hint_label.text != "", "the first hops show a hint (%s)" % main.hud.hint_label.text)

	# play with the bot from the sim test, through the scene's own input functions
	var bot := preload("res://tests/sim_test.gd").Bot.new()
	for i in 120 * 60:
		match bot.decide(main.sim):
			"press":
				key(true)
			"release":
				key(false)
			"tap":
				key(true)
				key(false)
		main.advance(Sim.DT)
		if main.sim.hops >= 5:
			break
	check(main.sim.hops >= 5, "the bot hops 5 moons with the Space key (%d)" % main.sim.hops)
	check(main.hud.score_label.text == str(main.sim.score), "HUD shows the score")
	check(main.hud.best_label.text.contains("combo %d" % main.sim.combo), "during a run the HUD shows the combo (%s)" % main.hud.best_label.text)

	# pause: losing focus freezes the run
	main.on_press() # a finger down when focus goes
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.paused and main.hud.pause_card.visible and not main.sim.holding, "losing focus pauses and lets go")
	check(main.music.ducked, "the music is lowered while paused")
	var t0: float = main.sim.t
	tick(2.0)
	check(main.sim.t == t0, "nothing moves while paused")
	button(true)
	button(false)
	check(main.hud.pause_title.text == "3", "a tap starts a 3 second countdown")
	tick(1.2)
	check(main.paused and main.hud.pause_title.text == "2", "the countdown counts down")
	tick(2.0)
	check(not main.paused and not main.hud.pause_card.visible and main.sim.t > t0, "the run resumes after the countdown")
	check(not main.music.ducked, "and the music comes back up")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.paused, "a second focus loss keeps it paused")
	button(true)
	tick(3.2)
	button(false)
	check(not main.paused, "resumes again")

	# fly off: game over
	tick(0.3)
	if main.sim.player.planet != null:
		button(true)
		button(false)
	for i in 120 * 8:
		main.advance(Sim.DT)
		if main.sim.state == "over":
			break
	check(main.sim.state == "over", "flinging into the dark ends the run (%s)" % main.sim.death_why)
	var final: int = main.sim.score
	check(not main.hud.over_card.visible, "the game over card waits a moment")
	button(true)
	button(false)
	check(main.sim.state == "over", "a tap right away does not restart")
	tick(0.6)
	check(main.hud.over_card.visible and main.hud.over_score.text == str(final), "the game over card shows the score")
	check(main.hud.over_best.text == "New best", "it says New best")
	check(main.hud.over_stats.text.contains("perigee") and main.hud.over_stats.text.contains("best combo"), "it sums up the run (%s)" % main.hud.over_stats.text)
	check(main.hud.best_label.text == "Best %d" % final, "HUD best updated")
	var saved := SaveData.new(SAVE)
	saved.load_file()
	check(saved.data.best == final and saved.data.runs == 1, "best score and run count saved (%s)" % [saved.data])
	check(FileAccess.get_file_as_string(SAVE).contains("\"version\": 1"), "the save file is versioned")

	button(true)
	tick(0.1)
	button(false)
	check(main.sim.state == "play" and main.sim.score == 0 and not main.hud.over_card.visible, "a tap restarts from zero")
	check(main.sim.player.planet != null, "the restart tap does not fling")

	# the lab: a run of one new kind of moon, never counted for the best score
	main.sim.die("test")
	tick(0.6)
	var lab_button: Button = main.hud.over_card.find_child("Lab_twin", true, false)
	check(lab_button != null, "the game over card has the lab buttons")
	lab_button.pressed.emit()
	tick(0.1)
	var kinds := {}
	for pl in main.sim.planets:
		kinds[pl.kind] = true
	check(main.sim.state == "play" and main.mode == "twin" and kinds.has("twin") and not main.hud.over_card.visible, "Twin starts a lab run with twin moons")
	check(main.hud.mode_label.text == "Lab · Twin moons", "the HUD says which lab is running")
	main.sim.score = 999
	main.sim.die("test")
	tick(0.6)
	saved.load_file()
	check(saved.data.best == final, "a lab run never sets the best score")
	main.hud.start_card.find_child("Lab_endless", true, false).pressed.emit()
	tick(0.1)
	check(main.mode == "endless" and main.sim.recipe.is_empty() and main.hud.mode_label.text == "", "Endless goes back to the normal mode")

	# settings: sound toggles and is kept
	main.hud.sound_button.pressed.emit()
	check(main.sfx.enabled and main.hud.sound_button.text == "SOUND ON", "the sound button turns sound on")
	check(main.music.enabled and main.music.player.playing and main.music.target_db() == Music.VOLUME_DB
		and main.music.player.bus == "Music", "and starts the music on the Music bus")
	var track: AudioStreamOggVorbis = main.music.player.stream
	check(track != null and track.loop and track.get_length() > 30.0, "the music track loops (%.1f s)" % (track.get_length() if track else 0.0))
	var missing: Array[String] = []
	for n in Sfx.NAMES + range(12).map(func(i): return "catch%d" % i):
		if not main.sfx.has_clip(n):
			missing.append(n)
	check(missing.is_empty(), "every sound effect loads (missing: %s)" % [missing])
	main.hud.sound_button.pressed.emit()
	check(not main.music.enabled and main.music.target_db() == Music.SILENT, "sound off fades the music out")
	main.hud.sound_button.pressed.emit()
	main.queue_free()
	await process_frame
	new_main()
	await process_frame
	check(main.sfx.enabled and main.hud.best_label.text == "Best %d" % final, "sound setting and best come back after a restart of the app")

	# the build line on the start card (test builds; see scripts/boot.gd for the updater itself)
	check(main.build_number("b1050 pr12 abc1234") == 1050 and main.build_number("") == 0, "reads the build number")
	ProjectSettings.set_setting("application/config/version", "b1050 test")
	main.queue_free()
	await process_frame
	new_main()
	await process_frame
	var bb: Button = main.hud.build_button
	check(bb.visible and bb.text.begins_with("Build b1050"), "the start card shows which build this is: " + bb.text)
	main.show_update(1049)
	check(bb.text.begins_with("Build b1050"), "an older build on the server changes nothing")
	main.show_update(1052)
	check(bb.text == "New build 1052 · tap to update", "says when a newer build is out: " + bb.text)
	var restarted := [false]
	main.restart_fn = func() -> void: restarted[0] = true
	bb.pressed.emit()
	await create_timer(0.3).timeout
	check(restarted[0] and bb.text == "Restarting…", "tapping it restarts into the new build")
	check(main.sim.state == "start", "tapping the build line doesn't start a run")
	ProjectSettings.set_setting("application/config/version", "")

	# older or broken save files
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{\"best\": 12}")
	f.close()
	saved = SaveData.new(SAVE)
	saved.load_file()
	check(saved.data.best == 12 and saved.data.settings.sound == false and saved.data.runs == 0, "a save without a version or fields loads with defaults")
	f = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	saved.load_file()
	check(saved.data.best == 0, "an unreadable save starts fresh")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("GAME TEST DONE")
		quit(0)
