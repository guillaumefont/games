extends SceneTree
## The spark unlock track: its data, the hangar screen, unlocking from a run's sparks, equipping.
## Run: godot --headless --path perigee --script tests/unlocks_test.gd
## Last line on success: UNLOCKS TEST DONE

const SAVE := "user://unlocks_test_save.json"

var fails := 0
var main: Node2D


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func tick(seconds: float) -> void:
	for i in int(round(seconds / Sim.DT)):
		main.advance(Sim.DT)


func new_main() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	main.ready.connect(func() -> void: main.save.data.tutorial_done = true)
	root.add_child(main)
	main.set_process(false)


func _initialize() -> void:
	print("Perigee unlocks test")

	# --- data ---
	var ids := {}
	var last_at := -1
	var ordered := true
	for it in Unlocks.TRACK:
		ids[it.id] = true
		ordered = ordered and int(it.at) >= last_at
		last_at = int(it.at)
	check(ids.size() == Unlocks.TRACK.size(), "item ids are unique")
	check(ordered, "the track is in unlock order")
	for kind in Unlocks.KINDS:
		var d: String = Unlocks.DEFAULT_EQUIPPED[kind]
		check(Unlocks.item(d).kind == kind and Unlocks.is_unlocked(d, 0), "the default %s is free" % kind)
	var pals_ok := true
	for it in Unlocks.TRACK:
		if it.kind == "palette":
			pals_ok = pals_ok and Unlocks.PALETTES.has(it.id) and Unlocks.PALETTES[it.id].size() == 4
	check(pals_ok, "every palette has four moon colours")
	check(SaveData.DEFAULTS.equipped == Unlocks.DEFAULT_EQUIPPED, "the save starts with the defaults equipped")
	var got := Unlocks.newly_unlocked(10, 45)
	check(got.size() == 2 and got[0].id == "trail_comet" and got[1].id == "ship_dart", "10 to 45 sparks unlocks Comet and Dart")
	check(Unlocks.newly_unlocked(45, 45).is_empty(), "nothing twice")
	check(Unlocks.next_item(45).id == "palette_aurora" and is_equal_approx(Unlocks.progress(60), 0.5), "next item and progress")
	check(Unlocks.next_item(100000).is_empty() and Unlocks.progress(100000) == 1.0, "a full track")

	# --- the hangar ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	new_main()
	await process_frame
	var hb: Button = main.hud.start_card.find_child("Hangar", true, false)
	check(hb != null, "the start card has a Hangar button")
	hb.pressed.emit()
	check(main.hud.hangar_card.visible and not main.hud.start_card.visible, "it opens the hangar")
	var dart: Button = main.hud.hangar_items.ship_dart
	check(dart.disabled and main.hud.hangar_next.text == "Next: Comet trail at 15", "locked items wait (%s)" % main.hud.hangar_next.text)
	main.equip("ship_dart")
	check(main.save.data.equipped.ship == "ship_pebble", "a locked item can't be equipped")
	main.hud.hangar_card.find_child("Done", true, false).pressed.emit()
	check(not main.hud.hangar_card.visible and main.hud.start_card.visible, "Done goes back")

	# a run's sparks move the track on
	main.save.data.sparks = 10
	main.start_mode("endless")
	tick(0.1)
	main.sim.sparks_got = 35
	main.sim.die("test")
	tick(0.6)
	check(int(main.save.data.sparks) == 45, "the run's sparks are banked (%d)" % main.save.data.sparks)
	check(main.hud.over_unlock.visible and main.hud.over_unlock.text == "Unlocked: Comet trail, Dart ship",
		"the game over card says what unlocked (%s)" % main.hud.over_unlock.text)
	main.on_press()
	main.on_release()
	tick(0.1)
	check(main.sim.state == "play" and not main.hud.over_unlock.visible, "the next run clears it")
	main.open_hangar()
	check(not main.hud.hangar_items.ship_dart.disabled, "Dart is open in the hangar")
	main.hud.hangar_items.ship_dart.pressed.emit()
	main.hud.hangar_items.trail_comet.pressed.emit()
	check(main.save.data.equipped.ship == "ship_dart" and main.save.data.equipped.trail == "trail_comet", "tapping equips")
	var sub: Label = main.hud.hangar_items.ship_dart.find_child("Sub", true, false)
	check(sub.text == "Equipped", "the hangar marks what is equipped")
	main.close_hangar()
	# draw every ship, trail and palette once
	for it in Unlocks.TRACK:
		main.save.data.equipped[it.kind] = it.id
		tick(0.05)
		main.queue_redraw()
		await process_frame
	check(main.sim.state == "play", "every cosmetic draws")
	main.save.data.equipped = Unlocks.DEFAULT_EQUIPPED.duplicate()
	main.save.data.equipped.ship = "ship_dart"
	main.save.save_file()
	main.queue_free()
	await process_frame
	new_main()
	await process_frame
	check(main.save.data.equipped.ship == "ship_dart" and int(main.save.data.sparks) == 45, "kept after a restart of the app")
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"sparks\": 3, \"equipped\": {\"ship\": \"ship_halo\"}}")
	f.close()
	var old := SaveData.new(SAVE)
	old.load_file()
	check(old.data.equipped.ship == "ship_halo" and old.data.equipped.trail == "trail_stardust", "a partial equipped list keeps defaults")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("UNLOCKS TEST DONE")
		quit(0)
