extends SceneTree
## Drift's leaderboards (scripts/leaderboards.gd) and its fast-run reward on the game over card:
## ranking on both boards, ties, the board size, the save, the boards card and its star badges.
## Run: godot --headless --path perigee --script tests/boards_test.gd
## Last line on success: BOARDS TEST DONE

const SAVE := "user://boards_test_save.json"

var main: Node2D
var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func run(moons: int, score: int, stars := 0, date := 1000) -> Dictionary:
	return {"moons": moons, "score": score, "stars": stars, "perigees": 0, "leaps": 0, "time": 30.0, "date": date}


func _initialize() -> void:
	print("Perigee boards test")

	# --- ranking ---
	var lb := Leaderboards.new({})
	check(lb.data.has("farthest") and lb.data.has("score"), "a fresh save gets both boards")
	var r := lb.submit(run(20, 100, 1))
	check(r.farthest == 1 and r.score == 1, "the first run tops both boards")
	r = lb.submit(run(30, 60))
	check(r.farthest == 1 and r.score == 2, "farther but fewer points: #1 Farthest, #2 Top score")
	r = lb.submit(run(30, 80, 0, 2000))
	check(r.farthest == 1 and lb.top("farthest")[1].score == 60, "same moons: more points ranks higher")
	r = lb.submit(run(30, 80, 0, 3000))
	check(r.farthest == 2, "a full tie goes to the older run")
	r = lb.submit(run(0, 0))
	check(r.farthest == 0 and r.score == 0 and lb.top("farthest").size() == 4, "a run that reached no moon is not entered")
	for i in 12:
		lb.submit(run(40 + i, 500 + i, 2, 5000 + i))
	check(lb.top("farthest").size() == Leaderboards.SIZE and lb.top("score").size() == Leaderboards.SIZE,
		"each board keeps the best %d" % Leaderboards.SIZE)
	r = lb.submit(run(1, 1))
	check(r.farthest == 0 and r.score == 0, "a run below the 10th is not entered")
	check(lb.top("score")[0].score == 511 and lb.top("score")[0].stars == 2, "the top run keeps its star badge")
	check(Leaderboards.ranks_text({"farthest": 1, "score": 3}) == "New #1 Farthest · #3 Top score"
		and Leaderboards.ranks_text({"farthest": 0, "score": 0}) == "", "the game over line names the boards made")

	# --- saved with the game ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var sv := SaveData.new(SAVE)
	Leaderboards.new(sv.data.boards).submit(run(12, 34, 1))
	sv.save_file()
	var back := SaveData.new(SAVE)
	back.load_file()
	var top := Leaderboards.new(back.data.boards).top("farthest")
	check(top.size() == 1 and top[0].moons == 12 and top[0].score == 34 and top[0].stars == 1 and typeof(top[0].moons) == TYPE_INT,
		"the boards survive a save and load (%s)" % [top])

	# --- in the game: a Drift run lands on the boards, and the card shows them ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	main.vis_seed = 7
	main.ready.connect(func() -> void: main.save.data.tutorial_done = true)
	root.add_child(main)
	main.set_process(false)
	await process_frame
	var bb: Button = main.hud.start_card.find_child("Boards", true, false)
	check(bb != null, "the start card has a Boards button")
	bb.pressed.emit()
	check(main.hud.boards_card.visible and not main.hud.start_card.visible, "it opens the boards")
	check(main.hud.boards_note.text.begins_with("No runs yet") and main.hud.boards_list.get_child_count() == 0, "empty boards say so")
	main.hud.boards_card.find_child("Done", true, false).pressed.emit()
	check(not main.hud.boards_card.visible and main.hud.start_card.visible, "Done goes back to the start card")

	# a Drift run: reach a few moons fast with a scripted world, then die
	main.start_mode("endless")
	main.advance(Sim.DT)
	var s: Sim = main.sim
	check(s.rush_on, "Drift runs the lap clock")
	main.advance(Sim.DT)
	check(main.hud.timer_label.text.begins_with("Lap 1 · "), "the HUD shows the lap clock (%s)" % main.hud.timer_label.text)
	s.hops = Sim.LAP_MOONS
	s.run_t = 9.0
	s._check_lap(s.player.x, s.player.y)
	s.perigees = 4
	s.die("Drifted off into the dark")
	for i in 120:
		main.advance(Sim.DT)
	check(s.rush_stars == 1 and main.hud.over_card.visible, "the run ends with one speed star")
	check(main.hud.over_rush_row.visible and main.hud.over_rush_label.text.begins_with("1 speed star"),
		"the game over card shows the speed star (%s)" % main.hud.over_rush_label.text)
	check(main.hud.over_rank.visible and main.hud.over_rank.text == "New #1 Farthest · #1 Top score",
		"and the boards it made (%s)" % main.hud.over_rank.text)
	check(int(main.save.data.sparks) >= 1, "the speed star paid a bonus spark")
	var saved := SaveData.new(SAVE)
	saved.load_file()
	check(saved.data.boards.farthest.size() == 1 and int(saved.data.boards.farthest[0].moons) == Sim.LAP_MOONS,
		"the run is saved on the boards")
	main.hud.over_card.find_child("OverBoards", true, false).pressed.emit()
	check(main.hud.boards_card.visible and not main.hud.over_card.visible, "game over opens the boards too")
	var row: Control = main.hud.boards_list.get_child(0)
	var stars: Label = row.find_child("Stars", true, false)
	check(main.hud.boards_list.get_child_count() == 1 and stars.text == "1", "the entry wears its star badge")
	var sb: StyleBoxFlat = row.get_theme_stylebox("panel")
	check(sb.border_width_left > 0, "the run just played is highlighted")
	main.hud.boards_tabs.score.pressed.emit()
	check(main.hud.boards_tab == "score" and main.hud.boards_list.get_child_count() == 1, "the Top score tab switches boards")
	main.hud.boards_card.find_child("Done", true, false).pressed.emit()
	check(main.hud.over_card.visible, "Done goes back to the game over card")

	# lab runs never reach the boards
	main.start_mode("twin")
	main.advance(Sim.DT)
	main.sim.hops = 30
	main.sim.die("Drifted off into the dark")
	for i in 120:
		main.advance(Sim.DT)
	check(Leaderboards.new(main.save.data.boards).top("farthest").size() == 1 and not main.hud.over_rush_row.visible,
		"a lab run is not entered and shows no speed stars")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("BOARDS TEST DONE")
		quit(0)
