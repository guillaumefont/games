extends SceneTree
## Saves survive the app being killed mid-save: temp file, backup, and recovery on load.
##   godot --headless --path . --script tests/saves_test.gd

const SAVE := "user://test_saves.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func clean() -> void:
	for p: String in [SAVE, SAVE + ".tmp", SAVE + ".bak"]:
		DirAccess.remove_absolute(p)


func write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func progress(scrap: int) -> Dictionary:
	var s := Rules.fresh()
	s.scrap = scrap
	return s


func _init() -> void:
	print("saves")
	clean()
	check(Rules.load_game(SAVE) == Rules.fresh(), "no save is a fresh start")

	check(Rules.save_game(progress(10), SAVE), "first save works")
	check(Rules.load_game(SAVE).scrap == 10, "and loads back")
	check(not FileAccess.file_exists(SAVE + ".tmp"), "no temp file is left behind")
	check(Rules.save_game(progress(20), SAVE), "second save works")
	check(Rules.load_game(SAVE).scrap == 20, "the newest save loads")
	check(Rules._read_save(SAVE + ".bak").scrap == 10, "the one before is kept as a backup")

	print("killed mid-save")
	write(SAVE, "")
	check(Rules.load_game(SAVE).scrap == 10, "an empty save falls back to the backup")
	write(SAVE, '{"scrap": 30, "be')
	check(Rules.load_game(SAVE).scrap == 10, "a half-written save falls back to the backup")
	DirAccess.remove_absolute(SAVE)
	write(SAVE + ".tmp", JSON.stringify(progress(40)))
	check(Rules.load_game(SAVE).scrap == 40, "killed between renames: the whole temp file is used")
	write(SAVE + ".tmp", "{")
	check(Rules.load_game(SAVE).scrap == 10, "a broken temp file is skipped for the backup")

	print("a broken save is never copied over the backup")
	write(SAVE, "garbage")
	DirAccess.remove_absolute(SAVE + ".tmp")
	check(Rules.save_game(progress(50), SAVE), "saving over a broken file works")
	check(Rules._read_save(SAVE + ".bak").scrap == 10, "the good backup is kept")
	check(Rules.load_game(SAVE).scrap == 50, "and the new save loads")

	print("reset")
	check(Rules.save_game(Rules.fresh(), SAVE), "a progress reset saves")
	check(Rules.load_game(SAVE) == Rules.fresh(), "and loads as fresh, not from the backup")

	clean()
	print("FAILED %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)
