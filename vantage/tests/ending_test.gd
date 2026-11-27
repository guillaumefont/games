extends SceneTree
## The ending: after the last fortress (5-3) breaks up, a victory flight, "CAMPAIGN COMPLETE",
## then the credits roll back to the hangar; any other level goes straight back to the hangar.
## The hangar's Credits button rolls them too. Runs headless:
##   godot --headless --path . --script tests/ending_test.gd

const SAVE := "user://test_ending_save.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func tap(g: Game) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	g.handle(e)
	e = e.duplicate()
	e.pressed = false
	g.handle(e)


## Flies `lv` to the fortress's break-up and on until the results; returns the seconds after it.
func clear_level(g: Game, lv: int) -> float:
	g.launch(lv)
	g.set_cam("chase", 0.0)
	g.phase = "escape"
	g.phase_t = Rules.BREAKUP_TIME
	g.step(DT)
	var t := 0.0
	while g.phase == "clear" and t < 30.0:
		g.step(DT)
		t += DT
	return t


func ending(g: Game) -> void:
	print("ending")
	var last := Campaign.count() - 1
	g.launch(last)
	check(g.finale(), "5-3 is the campaign's last level")
	var t := clear_level(g, last)
	check(t >= Game.FINALE_T - 0.1, "a %.1f s victory flight after the last fortress (%.1f s)" % [Game.FINALE_T, t])
	check(g.phase == "results" and g.run.cleared, "then the results")
	check(g.hud.res_title.text == "CAMPAIGN COMPLETE", "titled CAMPAIGN COMPLETE (%s)" % g.hud.res_title.text)
	check(g.hud.res_hint.text.contains("credits"), "the hint says a tap rolls the credits")
	for i in 60:
		g.step(DT)
	tap(g)
	check(g.phase == "credits" and g.hud.credits.visible and not g.hud.results.visible, "a tap rolls the credits")
	g.step(DT)
	check(g.ship.visible, "the ship flies on under them")
	print("    roll %.0f px over a %s screen" % [g.hud.credits.roll_h(), g.hud.credits.size])
	tap(g)
	check(g.phase == "credits", "a tap at once doesn't skip them")
	var z0 := g.frame_z
	var y0 := g.hud.credits.box.position.y
	var secs := 0.0
	for i in int(5.0 / DT):
		g.step(DT)
		secs += DT
	check(g.frame_z < z0 - 10.0 and g.hud.credits.box.position.y < y0 - 200.0, "the land scrolls and the roll climbs")
	while g.phase == "credits" and secs < 120.0:
		g.step(DT)
		secs += DT
	check(g.phase == "hangar" and not g.hud.credits.visible and g.hud.hangar.visible, "the roll ends in the hangar (%.0f s)" % secs)
	check(secs > 10.0 and secs < 60.0, "it lasts a while, not forever")


func other_levels(g: Game) -> void:
	print("other levels")
	var t := clear_level(g, 2)
	check(t < 4.0, "a world's last level keeps its short flight (%.1f s)" % t)
	check(g.hud.res_title.text == "WORLD CLEAR", "and says WORLD CLEAR")
	for i in 60:
		g.step(DT)
	tap(g)
	check(g.phase == "hangar", "a tap goes back to the hangar, no credits")


func from_hangar(g: Game) -> void:
	print("credits from the hangar")
	g.to_hangar()
	g.start_credits()
	check(g.phase == "credits" and g.hud.credits.visible, "the hangar's Credits button rolls them")
	for i in int((Credits.SKIP_AFTER + 0.2) / DT):
		g.step(DT)
	tap(g)
	check(g.phase == "hangar" and g.hud.hangar.visible, "a tap after a moment skips back to the hangar")


func _initialize() -> void:
	print("Vantage ending test")
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	await process_frame
	g.s.open = Campaign.count() - 1   # every level open
	ending(g)
	other_levels(g)
	from_hangar(g)
	g.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("FAILS: %d" % fails if fails else "all passed")
	quit(1 if fails else 0)
