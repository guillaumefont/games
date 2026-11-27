extends SceneTree
## Music (Guillaume, 2026-11-27: "at least a music per world, with a change for bosses and
## fortress"): every world has its own looping track, the hangar plays the selected world's,
## and the mid-boss and the fortress switch to their own tracks. Runs headless:
##   godot --headless --path . --script tests/music_test.gd

const SAVE := "user://test_music_save.json"

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


func _initialize() -> void:
	print("Vantage music test")
	var files := {}
	for w: Dictionary in Campaign.WORLDS:
		check(Sound.TRACKS.has(w.theme), "%s has a track" % w.name)
		files[Sound.TRACKS.get(w.theme, "")] = true
	check(files.size() == Campaign.WORLDS.size(), "each world's track is its own")
	check(not files.has(Sound.TRACKS.boss) and not files.has(Sound.TRACKS.fortress)
		and Sound.TRACKS.boss != Sound.TRACKS.fortress, "the mid-boss and the fortress have tracks of their own")
	for name: String in Sound.TRACKS:
		var st = load(Sound.TRACKS[name])
		check(st is AudioStreamOggVorbis and st.loop and st.get_length() > 20.0, "%s loads and loops" % name)

	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	check(g.sound.track == Campaign.WORLDS[0].theme and g.sound.ducked, "the hangar plays Glass Coast, ducked")
	var last := Campaign.count() - 1
	g.pick_level(last)
	check(g.sound.track == Campaign.WORLDS[-1].theme, "picking a level of another world plays that world's track")
	g.pick_level(Campaign.PER_WORLD)
	g.launch()
	check(g.sound.track == Campaign.WORLDS[1].theme and not g.sound.ducked, "a level plays its world's track")
	g.spawn_vert("boss", 0.0, 0, 1)
	check(g.sound.track == "boss", "the mid-boss brings its track")
	g.spawn_fortress()
	check(g.sound.track == "fortress", "the fortress brings its own")
	g.queue_free()
	await process_frame
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
