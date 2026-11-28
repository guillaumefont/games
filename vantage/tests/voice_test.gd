extends SceneTree
## Radio callouts (Guillaume, 2026-11-28: "Add voice effects"): every callout has its clip, one line plays at a
## time, urgent lines cut the queue, chatter is dropped rather than queued, stale lines are forgotten, the music
## dips under the voice, and the game's moments ask for their lines. Runs headless:
##   godot --headless --path . --script tests/voice_test.gd

const SAVE := "user://test_voice_save.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 3
	return g


## Advances the sound's clock by `t` seconds in small steps, as frames would.
func run(snd: Sound, t: float) -> void:
	var n := int(ceil(t / 0.05))
	for i in n:
		snd._process(0.05)


func _initialize() -> void:
	print("Vantage voice test")
	for key: String in Sound.VOICE:
		for f: String in Sound.variants(key):
			var st = load(f)
			check(st is AudioStreamOggVorbis and not st.loop and st.get_length() > 0.5 and st.get_length() < 4.0,
				"%s is a short one-shot clip" % f.get_file())
	check(Sound.variants("launch").size() == 3, "the launch callout has three variants")

	var g := make_game()
	await process_frame
	var snd := g.sound
	check(AudioServer.get_bus_index("Voice") >= 0, "callouts have their own bus")
	snd.hush()
	run(snd, 5.0)
	snd.said.clear()

	check(snd.speak("warning") == "play" and snd.talking(), "a callout plays at once on a quiet radio")
	check(snd.speak("section") == "", "chatter is dropped while the radio talks")
	check(snd.speak("boss_down") == "wait", "an important line waits its turn")
	check(snd.speak("reactor") == "", "only one line waits")
	check(snd.speak("down") == "wait", "an urgent line takes the waiting slot")
	run(snd, 0.5)
	var bus := AudioServer.get_bus_index("Music")
	check(AudioServer.get_bus_volume_db(bus) < -3.0, "the music dips under the voice")
	run(snd, 2.5)
	check(snd.said.back() == "down", "the urgent line goes as soon as the first ends, without the gap")
	run(snd, 3.0)
	check(not snd.talking() and snd.said.size() == 2, "the bumped line is gone, nothing else plays")
	run(snd, 1.0)
	check(AudioServer.get_bus_volume_db(bus) > -0.5, "the music comes back up")

	snd.speak("victory")
	snd.speak("launch")
	run(snd, 6.0)
	check(snd.said.back() == "victory", "a waiting line too old to matter is forgotten")
	check(snd.speak("power") == "play" and snd.speak("power") == "", "a line on cooldown isn't repeated")
	run(snd, 5.0)
	snd.voice_on = false
	check(snd.speak("warning") == "" and not snd.talking(), "switched off, the radio stays quiet")
	snd.voice_on = true

	# the game's moments
	snd.hush()
	run(snd, 5.0)
	snd.said.clear()
	g.pick_level(0)
	g.launch()
	check(snd.said.has("launch"), "launching a level calls it")
	snd.hush()
	run(snd, 5.0)
	g.spawn_vert("boss", 0.0, 0, 1)
	check(snd.said.back() == "warning", "the mid-boss warning is called")
	snd.hush()
	run(snd, 5.0)
	g.spawn_fortress()
	check(snd.said.back() == "fortress", "the fortress ahead is called")
	snd.hush()
	run(snd, 5.0)
	g.inv = 0.0
	g.hp = 2
	g.phase = "vert"
	g.hurt()
	check(snd.said.back() == "critical", "the last hit point left calls hull critical")
	snd.hush()
	g.inv = 0.0
	g.hurt()
	check(snd.said.back() == "down", "getting shot down is called")
	g.queue_free()
	await process_frame
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
