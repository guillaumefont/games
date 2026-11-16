extends SceneTree
## Voyage sectors: the data is sound, the bot clears every sector (the plan's content gate:
## "the bot clears every sector at 1 star"), shortcut lines can be leapt, stars and unlocks work,
## and the scene's Voyage screens (sector list, clear card, retry, next sector) behave.
## Run: godot --headless --path perigee --script tests/voyage_test.gd
## Last line on success: VOYAGE TEST DONE

const SAVE := "user://voyage_test_save.json"
const Bot = preload("res://tests/sim_test.gd").Bot

var fails := 0
var main: Node2D


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func sector_sim(sec: Dictionary) -> Sim:
	var s := Sim.new(sec.seed, 400, 700)
	s.recipe = Voyage.recipe(sec)
	s.new_run(sec.seed)
	return s


func bot_play(s: Sim, deep: bool) -> void:
	var bot = Bot.new()
	bot.deep = deep
	for i in 120 * 120:
		match bot.decide(s):
			"press":
				s.press()
			"release":
				s.release()
			"tap":
				s.press()
				s.release()
		s.step()
		if s.state != "play":
			break


func tick(seconds: float) -> void:
	for i in int(round(seconds / Sim.DT)):
		main.advance(Sim.DT)


func _initialize() -> void:
	print("Perigee voyage test")

	# --- data ---
	var ids := {}
	for sec in Voyage.all_sectors():
		ids[sec.id] = true
	check(ids.size() == Voyage.all_sectors().size() and ids.size() >= 6, "%d sectors with unique ids" % ids.size())
	check(Voyage.next_sector("1-1").id == "1-2" and Voyage.next_sector("1-6").is_empty(), "sectors run in order")
	check(Voyage.system_of("1-3").name == "Cradle", "system 1 is Cradle")

	# --- every sector: fixed layout, a waypoint, cleared by the bot ---
	for sec in Voyage.all_sectors():
		var a := sector_sim(sec)
		var b := sector_sim(sec)
		var same := a.planets.size() == b.planets.size()
		for i in mini(a.planets.size(), b.planets.size()):
			same = same and a.planets[i].ox == b.planets[i].ox and a.planets[i].y == b.planets[i].y
		var shallow := sector_sim(sec)
		bot_play(shallow, false)
		var deep := sector_sim(sec)
		bot_play(deep, true)
		var finish: Sim.Planet = deep.planets[-1]
		check(same and finish.finish and finish.k == sec.moons and shallow.state == "clear" and deep.state == "clear",
			"%s: same layout every try, waypoint is moon %d, the bot clears it (%.1f s / %.1f s, par %.0f s)"
			% [sec.id, sec.moons, shallow.run_t, deep.run_t, sec.par])
		check(deep.run_t <= float(sec.par) or shallow.run_t <= float(sec.par), "%s: the par time can be beaten" % sec.id)
		var kinds := {}
		for pl in sector_sim(sec).planets:
			kinds[pl.kind] = true
		check(kinds.has("twin") == sec.get("mix", {}).has("twin"), "%s: twins appear only where the recipe has them" % sec.id)

	# --- a shortcut line: in 1-4, moons 1 and 3 line up; fling straight at 3 and leap over 2 ---
	var sec4 := Voyage.sector("1-4")
	var z := sector_sim(sec4)
	var m1: Sim.Planet = z.planets[1]
	var m3: Sim.Planet = z.planets[3]
	check(absf(m1.ox - m3.ox) < 1.0 and absf(z.planets[2].ox - m1.ox) > 80.0, "the zigzag lines up moons 1 and 3, moon 2 off to the side")
	# get to moon 1 with the bot, then aim at moon 3
	var bot = Bot.new()
	for i in 120 * 20:
		if z.player.planet == m1 and z.player.fly_t >= 0.0 and not bot.down:
			break
		match bot.decide(z):
			"press":
				z.press()
			"release":
				z.release()
			"tap":
				z.press()
				z.release()
		z.step()
	z.release()
	var aimed := false
	for i in 120 * 6:
		z.step()
		if z.t - z.player.cap_t > 0.3:
			var v := z.orbit_velocity()
			if absf(v.angle_to(Vector2(m3.x - z.player.x, m3.y - z.player.y))) < 0.05:
				aimed = true
				break
	z.press()
	z.release()
	for i in 120 * 3:
		var d := Vector2(z.player.x - m3.x, z.player.y - m3.y).length()
		if not z.holding and d < m3.perigee_radius():
			z.press()
		z.step()
		if z.player.planet == m3 or z.state != "play":
			break
	check(aimed and z.player.planet == m3 and z.leaps == 1 and z.planets[2].skipped, "flinging along the line leaps from moon 1 to moon 3 (%s %s, aimed %s, on moon %d, %d leaps; m1 %.0f,%.0f m2 %.0f,%.0f r%.0f m3 %.0f,%.0f)" % [z.state, z.death_why, aimed, z.player.planet.k if z.player.planet else -1, z.leaps, m1.x, m1.y, z.planets[2].x, z.planets[2].y, z.planets[2].ring, m3.x, m3.y])

	# --- stars and unlocks ---
	var s1 := Voyage.sector("1-1")
	var won := sector_sim(s1)
	bot_play(won, true)
	var st := Voyage.stars(s1, won)
	check(st[0] and st[1] == (won.run_t <= s1.par) and st[2] == (won.perigees >= 4), "stars: clear, par, goal (%s)" % [st])
	var lost := sector_sim(s1)
	lost.die("test")
	check(Voyage.stars(s1, lost) == [false, false, false], "no stars without clearing")
	check(Voyage.unlocked("1-1", {}) and not Voyage.unlocked("1-2", {}), "only the first sector is open at first")
	check(Voyage.unlocked("1-2", {"1-1": {"stars": 1}}) and not Voyage.unlocked("1-3", {"1-1": {"stars": 3}}), "clearing a sector opens the next")
	check(Voyage.goal_text({"type": "perigees", "count": 4}) == "4 perigees", "goal text")

	# --- the scene ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	main.set_process(false)
	await process_frame
	var vb: Button = main.hud.start_card.find_child("Voyage", true, false)
	check(vb != null, "the start card has a Voyage button")
	vb.pressed.emit()
	check(main.hud.voyage_card.visible and not main.hud.start_card.visible, "it opens the sector list")
	var b11: Button = main.hud.voyage_card.find_child("Sector_1-1", true, false)
	var b12: Button = main.hud.voyage_card.find_child("Sector_1-2", true, false)
	check(b11 != null and not b11.disabled and b12 != null and b12.disabled, "1-1 is open, 1-2 is locked")
	b11.pressed.emit()
	tick(0.1)
	check(main.mode == "voyage" and main.sim.state == "play" and main.sim.recipe.moons == 10 and not main.hud.voyage_card.visible, "1-1 starts a sector run")
	check(main.hud.mode_label.text.contains("1-1"), "the HUD names the sector (%s)" % main.hud.mode_label.text)
	# die once: tap retries the same layout
	var first_x: float = main.sim.planets[2].ox
	main.sim.die("test")
	tick(0.6)
	check(main.hud.over_card.visible and main.hud.over_best.text.contains("Moon"), "game over shows how far you got (%s)" % main.hud.over_best.text)
	main.on_press()
	main.on_release()
	tick(0.1)
	check(main.sim.state == "play" and main.sim.planets[2].ox == first_x and main.mode == "voyage", "a tap retries the same sector")
	# clear it with the bot
	var bot2 = Bot.new()
	bot2.deep = true
	for i in 120 * 60:
		match bot2.decide(main.sim):
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
	check(main.sim.state == "clear", "the bot clears 1-1 in the scene")
	tick(1.0)
	check(main.hud.clear_card.visible and main.hud.clear_title.text.contains("1-1"), "the clear card shows")
	var saved := SaveData.new(SAVE)
	saved.load_file()
	var rec: Dictionary = saved.data.voyage.get("1-1", {})
	check(int(rec.get("stars", 0)) >= 1 and int(rec.get("score", 0)) == main.sim.score, "stars and score are saved (%s)" % [rec])
	main.on_press()
	main.on_release()
	tick(0.1)
	check(main.sim.state == "play" and main.sector.id == "1-2", "a tap goes on to the next sector")
	main.sim.die("test")
	tick(0.6)
	var map_btn: Button = main.hud.over_card.find_child("Map", true, false)
	check(map_btn != null and map_btn.is_visible_in_tree(), "the game over card has a Map button in Voyage")
	map_btn.pressed.emit()
	check(main.hud.voyage_card.visible and not main.hud.over_card.visible, "Map opens the sector list")
	b12 = main.hud.voyage_card.find_child("Sector_1-2", true, false)
	check(not b12.disabled, "1-2 is open now")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("VOYAGE TEST DONE")
		quit(0)
