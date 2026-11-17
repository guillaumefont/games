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
	check(Voyage.next_sector("1-1").id == "1-2" and Voyage.next_sector("1-6").id == "2-1" and Voyage.next_sector("3-6").is_empty(), "sectors run in order, system after system")
	check(Voyage.system_of("1-3").name == "Cradle" and Voyage.system_of("2-1").name == "Backwash" and Voyage.system_of("3-6").name == "Lantern", "systems 1 to 3: Cradle, Backwash, Lantern")
	check(Voyage.all_sectors().size() >= 12, "at least a dozen levels (Guillaume, 2026-11-17): %d" % Voyage.all_sectors().size())
	check(Voyage.level_number("1-1") == 1 and Voyage.level_number("2-1") == 7 and Voyage.level_number("3-6") == 18 and Voyage.level_number("9-9") == 0, "levels are numbered along the route")
	check(Voyage.current_id({}) == "1-1" and Voyage.current_id({"1-1": {"stars": 1}, "1-2": {"stars": 2}}) == "1-3", "the current level is the furthest open one")
	# each system brings in its own kind of moon, and the route gets longer and harder
	var new_kind := {"Backwash": "retro", "Lantern": "pulsar"}
	for sys in Voyage.SYSTEMS:
		var every := true
		for sec in sys.sectors:
			every = every and (not new_kind.has(sys.name) or sec.get("mix", {}).has(new_kind[sys.name]))
		check(sys.sectors.size() == 6 and every, "%s has 6 levels, each with its new kind of moon" % sys.name)
	var prev_k := -1
	for sys in Voyage.SYSTEMS:
		check(int(sys.sectors[0].k_offset) >= prev_k, "%s starts at least as hard as the system before ends easy (k_offset %d)" % [sys.name, sys.sectors[0].k_offset])
		prev_k = int(sys.sectors[0].k_offset)

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

	# --- medals: speed, points, all stars per sector; all stars per system; Drift points ---
	for sec in Voyage.all_sectors():
		var pm := Medals.points_marks(sec)
		var sm := Medals.speed_marks(sec)
		var deep := sector_sim(sec)
		bot_play(deep, true)
		check(pm.size() == 3 and pm[0] < pm[1] and pm[1] < pm[2] and sm[0] == float(sec.par) and sm[0] > sm[1] and sm[1] > sm[2],
			"%s: bronze, silver and gold marks rise (points %s, speed %s)" % [sec.id, pm, sm])
		check(Medals.speed_tier(sec, deep.run_t) == Medals.GOLD,
			"%s: the bot's best line wins speed gold (%.1f s, gold under %.1f s)" % [sec.id, deep.run_t, sm[2]])
		check(Medals.points_tier(sec, deep.score) == Medals.SILVER,
			"%s: all perigees and no leaps win points silver; gold needs more (%d, gold at %d)" % [sec.id, deep.score, pm[2]])
	check(Medals.speed_tier(s1, 20.0) == Medals.BRONZE and Medals.speed_tier(s1, 20.1) == Medals.NONE
		and Medals.speed_tier(s1, 17.6) == Medals.SILVER and Medals.speed_tier(s1, 15.2) == Medals.GOLD, "speed tiers at par, 88% and 76% of par")
	check(Medals.points_tier(s1, 34) == Medals.NONE and Medals.points_tier(s1, 35) == Medals.BRONZE
		and Medals.points_tier(s1, 60) == Medals.SILVER and Medals.points_tier(s1, 500) == Medals.GOLD, "points tiers at the sector's marks")
	check(Medals.of_sector(s1, {}) == {"speed": 0, "points": 0, "stars": 0}, "no medals before a clear")
	check(Medals.of_sector(s1, {"stars": 3, "score": 90, "time": 15.0}) == {"speed": 3, "points": 3, "stars": 3}, "a best record wins every medal")
	check(Medals.of_sector(s1, {"stars": 2, "score": 40, "time": 19.0}) == {"speed": 1, "points": 1, "stars": 0}, "two stars win no all-stars medal")
	check(Medals.of_run(s1, [true, false, false], 25.0, 10) == {"speed": 0, "points": 0, "stars": 0}, "a slow, low clear wins nothing")
	var all3 := {}
	for sec in Voyage.SYSTEMS[0].sectors:
		all3[sec.id] = {"stars": 3, "score": 0, "time": 99.0}
	check(Medals.system_stars(Voyage.SYSTEMS[0], all3) == [18, 18], "every star of the system counts (%s)" % [Medals.system_stars(Voyage.SYSTEMS[0], all3)])
	var tally := Medals.tally(all3, 300)
	check(tally[Medals.GOLD] == 7 and tally[Medals.SILVER] == 1 and tally[Medals.BRONZE] == 0, "tally: 6 sector all-stars, the system's, and Drift silver (%s)" % [tally])
	# rewards: each tier pays once, gold straight away pays all three steps
	var r1 := Medals.rewards({"1-1": {"stars": 3, "score": 90, "time": 15.0}}, 0)
	var r1_sparks := 0
	for r in r1:
		r1_sparks += int(r.sparks)
	check(r1.size() == 7 and r1_sparks == 6 + 6 + Medals.ALL_STARS_SPARKS, "a perfect 1-1 earns 7 rewards worth %d sparks (%d)" % [15, r1_sparks])
	# balance: every medal of the route pays less than the whole unlock track, so collected sparks still count
	var perfect := {}
	for sec in Voyage.all_sectors():
		perfect[sec.id] = {"stars": 3, "score": 99999, "time": 0.1}
	var route_sparks := 0
	for r in Medals.rewards(perfect, 0):
		route_sparks += int(r.sparks)
	var track_end: int = Unlocks.TRACK[-1].at
	check(route_sparks < track_end and route_sparks > track_end / 2, "every Voyage medal pays %d sparks, between half and all of the %d-spark track" % [route_sparks, track_end])
	for sys in Voyage.SYSTEMS:
		var it := Unlocks.reward_item("%s:stars" % sys.name)
		check(not it.is_empty() and not Unlocks.TRACK.has(it), "%s's every star wins a cosmetic of its own (%s)" % [sys.name, it.get("name", "none")])
	var claimed1: Array = ["1-1:speed:1", "1-1:speed:2", "1-1:speed:3"]
	check(Medals.unclaimed({"1-1": {"stars": 3, "score": 90, "time": 15.0}}, 0, claimed1).size() == 4, "claimed rewards never pay again")
	var all_r := Medals.rewards(all3, 0)
	check(all_r[-1].id == "Cradle:stars" and Unlocks.reward_item("Cradle:stars").id == "ship_laurel", "every Cradle star wins the Laurel ship")
	check(not Unlocks.is_unlocked("ship_laurel", 100000) and Unlocks.is_unlocked("ship_laurel", 0, ["Cradle:stars"]),
		"no amount of sparks unlocks Laurel, only its reward")
	check(Medals.drift_tier(99) == Medals.NONE and Medals.drift_tier(100) == Medals.BRONZE and Medals.drift_tier(750) == Medals.GOLD, "Drift points medals")
	check(Medals.next_speed_text(s1, Medals.BRONZE) == "Silver under 17.6 s · +2" and Medals.next_points_text([35, 60, 90], Medals.GOLD) == "", "the next tier's text")

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
	check(main.hud.voyage_card.visible and not main.hud.start_card.visible, "it opens the level map")
	var vmap: VoyageMap = main.hud.voyage_map
	var b11: Button = main.hud.voyage_card.find_child("Sector_1-1", true, false)
	var b12: Button = main.hud.voyage_card.find_child("Sector_1-2", true, false)
	check(b11 != null and not b11.disabled and b12 != null and b12.disabled, "1-1 is open, 1-2 is locked")
	check(vmap.nodes.size() == Voyage.all_sectors().size() and (b11.find_child("Number", true, false) as Label).text == "1"
		and (vmap.nodes["3-6"].find_child("Number", true, false) as Label).text == "18", "the map shows every level, numbered")
	check(vmap.current == "1-1" and vmap.centers["1-1"].y < vmap.centers["1-2"].y and vmap.centers["1-6"].y < vmap.centers["2-1"].y
		and absf(vmap.centers["1-1"].x - vmap.centers["1-2"].x) > 20.0, "one winding path, level after level")
	check(vmap.reward_stops.size() == Voyage.SYSTEMS.size()
		and (vmap.reward_stops[0].find_child("Caption", true, false) as Label).text.contains("Laurel"), "each system ends at its reward (%s)" % (vmap.reward_stops[0].find_child("Caption", true, false) as Label).text)
	b12.pressed.emit()
	check(not vmap.sheet.visible, "a locked level has no card")
	b11.pressed.emit()
	check(vmap.sheet.visible and vmap.sheet_title.text == "Level 1" and vmap.sheet_goals[2].text == "4 perigees"
		and vmap.sheet_medal_next[0].text.begins_with("Bronze under 20.0 s · +1") and main.sim.state != "play",
		"tapping a level opens its card: goals and what each medal pays (%s; %s)" % [vmap.sheet_title.text, vmap.sheet_medal_next[0].text])
	vmap.sheet.find_child("Close", true, false).pressed.emit()
	check(not vmap.sheet.visible and main.hud.voyage_card.visible, "Close goes back to the map")
	b11.pressed.emit()
	vmap.sheet.find_child("Play", true, false).pressed.emit()
	tick(0.1)
	check(main.mode == "voyage" and main.sim.state == "play" and main.sim.recipe.moons == 10 and not main.hud.voyage_card.visible, "Play starts level 1")
	check(main.hud.mode_label.text == "Level 1 · Cradle", "the HUD names the level (%s)" % main.hud.mode_label.text)
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
	check(main.hud.clear_card.visible and main.hud.clear_title.text == "Level 1 clear", "the clear card shows (%s)" % main.hud.clear_title.text)
	var won_m := Medals.of_run(Voyage.sector("1-1"), Voyage.stars(Voyage.sector("1-1"), main.sim), main.sim.run_t, main.sim.score)
	check(main.hud.clear_medals.visible and main.hud.clear_medal_icons[0].tier == won_m.speed
		and main.hud.clear_medal_icons[1].tier == won_m.points and main.hud.clear_medal_icons[2].tier == won_m.stars
		and won_m.speed == Medals.GOLD,
		"the clear card shows the run's medals (%s; %s / %s / %s)" % [won_m, main.hud.clear_medal_tiers[0].text, main.hud.clear_medal_tiers[1].text, main.hud.clear_medal_tiers[2].text])
	var saved := SaveData.new(SAVE)
	saved.load_file()
	var paid := 0
	for r in Medals.rewards({"1-1": saved.data.voyage.get("1-1", {})}, 0):
		paid += int(r.sparks)
	check(saved.data.rewards.has("1-1:speed:3") and int(saved.data.sparks) == main.sim.sparks_got + paid
		and main.hud.clear_medal_next[0].text == "+6 sparks",
		"the clear pays its rewards into the unlock track once (%d sparks, %d run + %d rewards; %s)" % [saved.data.sparks, main.sim.sparks_got, paid, main.hud.clear_medal_next[0].text])
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
	check(main.hud.voyage_card.visible and not main.hud.over_card.visible and main.hud.voyage_map.current == "1-2", "Map opens the level map")
	b12 = main.hud.voyage_card.find_child("Sector_1-2", true, false)
	check(not b12.disabled, "1-2 is open now")
	b11 = main.hud.voyage_card.find_child("Sector_1-1", true, false)
	var map_medals: Control = b11.find_child("MedalRow", true, false)
	check((map_medals.get_child(0) as MedalIcon).tier == Medals.GOLD and (map_medals.get_child(1) as MedalIcon).tier == won_m.points,
		"the map shows 1-1's best medals")
	check(main.hud.voyage_stars.text.ends_with("/ 54") and main.hud.voyage_tally.text.begins_with("Rewards"),
		"the map counts every star of the route and every medal (%s; %s)" % [main.hud.voyage_stars.text, main.hud.voyage_tally.text])
	# the system's all-stars reward unlocks Laurel in the hangar
	for sec in Voyage.SYSTEMS[0].sectors:
		main.save.data.voyage[sec.id] = {"stars": 3, "score": 0, "time": 99.0}
	main.open_hangar()
	var laurel_sub: Label = main.hud.hangar_items.ship_laurel.find_child("Sub", true, false)
	check(main.hud.hangar_items.ship_laurel.disabled and laurel_sub.text == "All Cradle stars", "Laurel shows how to win it (%s)" % laurel_sub.text)
	main.close_hangar()
	main.sim.sparks_got = 0
	main._bank_sparks()
	main.equip("ship_laurel")
	check(main.save.data.rewards.has("Cradle:stars") and main.save.data.equipped.ship == "ship_laurel"
		and main.hud.over_unlock.text.contains("Laurel"), "the all-stars reward unlocks Laurel and it can be equipped (%s)" % main.hud.over_unlock.text)
	main.save.data.equipped.ship = "ship_pebble"
	# Drift's game over card shows its points medal; Voyage's doesn't
	main.start_mode("endless")
	main.sim.score = 320
	main.sim.die("test")
	tick(0.6)
	check(main.hud.over_medal_row.visible and main.hud.over_medal.tier == Medals.SILVER and main.hud.over_medal_label.text.contains("Gold at 750 · +3")
		and main.hud.over_medal_label.text.contains("+3 sparks"),
		"Drift's game over card shows the run's points medal (%s)" % main.hud.over_medal_label.text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("VOYAGE TEST DONE")
		quit(0)
