# Special Stages are about time and rank, not medals (Guillaume, 2026-11-18). A Special Stage:
# - keeps its own best lap (Records.stage_key), seeded once from the old shared Standard record;
# - never awards a medal or medal coins, and its results show the lap, the best and the rank;
# - ranks against the world first; continent, country and zip code boards open by themselves
#   once enough players share the player's region (Ranking.OPEN_AT);
# - sends its best to the board server and shows the answer (checked here with a fake server).
#   godot --headless --path . --script tests/stage_rank_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Medals = preload("res://scripts/medals.gd")
const Menu = preload("res://scripts/menu.gd")
const Ranking = preload("res://scripts/ranking.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")

var fails := 0
var main: Node

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func start(ev: Dictionary) -> void:
	main.race = null
	main.phase = "menu"
	main._start_event(ev)
	for i in 300:
		await process_frame
		if main.race != null and not main.building:
			break

func finish_trial(lap: float) -> void:
	var me = main.race.cars[0]
	main._trial_lap(me, lap, [])
	me.finished = true
	me.finish_time = lap
	me.best_lap = lap
	main._trial_run(me)
	main._show_results()
	await frames(2)

func table_text() -> Array:
	return main.ui.res_table.get_children().filter(func(l): return not l.is_queued_for_deletion()).map(func(l): return l.text)

func ranks(world: Array, cont := [], country := [], zip := []) -> Dictionary:
	var r := { "world": { "rank": world[0], "total": world[1] } }
	if not cont.is_empty(): r["continent"] = { "rank": cont[0], "total": cont[1], "name": "Europe" }
	if not country.is_empty(): r["country"] = { "rank": country[0], "total": country[1], "name": "France" }
	if not zip.is_empty(): r["zip"] = { "rank": zip[0], "total": zip[1], "name": "75011" }
	return r

func _initialize() -> void:
	_run()

func _run() -> void:
	Records.reset()
	Ranking.reset()
	Wallet.reset()
	Daily.fake_day = Daily.day_of(2030, 1, 1)

	# ---- the rank rules, on their own
	check(Ranking.parse({ "ranks": {} }).is_empty(), "a reply without a world rank is dropped")
	check(Ranking.parse({ "ranks": { "world": { "rank": 5, "total": 3 } } }).is_empty(), "a rank past the board size is dropped")
	var one := Ranking.parse({ "best": 12.3, "ranks": ranks([1234, 56789], [300, 9000], [40, 150], [3, 10]) })
	check(Ranking.shown_scopes(one["ranks"]) == ["world", "country"], "world, then the narrowest region with enough players (%s)" % str(Ranking.shown_scopes(one["ranks"])))
	var few := Ranking.parse({ "ranks": ranks([7, 20], [7, 20], [7, 20], [3, 5]) })
	check(Ranking.shown_scopes(few["ranks"]) == ["world"], "early on, the world ranking only")
	var many := Ranking.parse({ "ranks": ranks([7, 90000], [7, 30000], [7, 4000], [2, 60]) })
	check(Ranking.shown_scopes(many["ranks"]) == ["world", "zip"], "zip code rank once the zip code has enough players")
	check(Ranking.rank_lines(one) == [["World", "#1,234 of 56,789"], ["France", "#40 of 150"]], "rank lines: %s" % str(Ranking.rank_lines(one)))
	check(Ranking.card_line(-1.0, {}) == "No time yet", "a card without a time")
	check(Ranking.card_line(12.3, {}) == "Best 0:12.30", "a card with a time, no rank yet")
	check(Ranking.card_line(12.3, one) == "Best 0:12.30  ·  France #40", "a card shows the narrowest rank (%s)" % Ranking.card_line(12.3, one))

	# ---- an old save: the Special Stage keeps the best it shared with the Road Trip
	var name: String = Defs.TRACKS[0]["name"]
	var gold: float = Medals.targets(name, "standard")[2]
	var cf := ConfigFile.new()
	cf.set_value(Records.key(name, "standard"), "best", gold + 1.0)
	cf.set_value(Records.META, "layouts", Records.LAYOUT_VERSION)
	cf.save(Records.PATH)
	Records._cfg = null
	check(is_equal_approx(Menu.stage_best(0), gold + 1.0), "an old Standard record seeds the Special Stage best")
	Records.set_best(Records.key(name, "standard"), gold - 2.0)
	check(is_equal_approx(Menu.stage_best(0), gold + 1.0), "seeded once: Road Trip times stay apart afterwards")
	Records.reset()

	# ---- a Special Stage run: a time, no medal, no medal coins
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	main.ui.loading.visible = false
	var ev := { "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" }
	await start(ev)
	check(main.stage_run and main.gold_ghost.is_empty(), "a Special Stage run, no Gold ghost")
	check(main.medal_targets.is_empty(), "no medal pace on a first Special Stage run")
	await finish_trial(gold - 0.5)
	check(Campaign.medal(name, "standard", "trial") == 0, "a Gold-fast Special Stage lap wins no medal")
	check(is_equal_approx(Menu.stage_best(0), gold - 0.5), "the lap is the stage best")
	check(Records.get_best(Records.key(name, "standard")) < 0.0, "and not a Road Trip record")
	check(main.pay_total == 0, "no medal coins (%d)" % main.pay_total)
	var badges: Array = main.ui.res_rewards.get_children().map(func(b): return b.get_meta("label").text if b.has_meta("label") else "")
	check(not badges.any(func(t): return "MEDAL" in t), "no medal badge (%s)" % str(badges))
	var cells := table_text()
	check(cells.has("World rank") and cells.has("offline"), "results show the world rank row, offline with no server (%s)" % str(cells))
	check(not ("medal" in main.ui.res_note.text.to_lower() and "next medal" in main.ui.res_note.text.to_lower()), "no next-medal target in the note")

	# the next run chases your own best, not a medal
	await start(ev)
	check(main.medal_targets.size() == 1 and is_equal_approx(main.medal_targets[0], gold - 0.5), "the HUD gap is to your best lap")

	# ---- the board server: the best is sent, the rank comes back into the open results
	var srv := TCPServer.new()
	var port := 0
	for p in range(18431, 18471):
		if srv.listen(p, "127.0.0.1") == OK:
			port = p
			break
	check(port > 0, "fake board server listening")
	Ranking._url_override = "http://127.0.0.1:%d" % port
	var reply := JSON.stringify({ "best": gold - 0.9, "ranks": ranks([1234, 56789], [300, 9000], [40, 150]) })
	await finish_trial(gold - 0.9)
	check(table_text().has("checking…"), "while the board answers: checking…")
	var got := ""
	var peer: StreamPeerTCP = null
	for i in 600:
		await process_frame
		if peer == null and srv.is_connection_available():
			peer = srv.take_connection()
		if peer:
			peer.poll()
			if peer.get_available_bytes() > 0:
				got += peer.get_utf8_string(peer.get_available_bytes())
			if got.contains("\r\n\r\n") and got.contains("}"):
				var resp := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [reply.to_utf8_buffer().size(), reply]
				peer.put_data(resp.to_utf8_buffer())
				break
	check(got.begins_with("POST /v1/boards/%s" % Ranking.board(name).uri_encode()), "a new best is posted to its board (%s)" % got.get_slice("\r\n", 0))
	var body = JSON.parse_string(got.get_slice("\r\n\r\n", 1))
	check(body is Dictionary and String(body.get("player", "")).length() == 32 and is_equal_approx(float(body.get("time", 0)), gold - 0.9),
		"it carries the player's id and the best lap only (%s)" % str(body))
	var ranked := false
	for i in 300:
		await process_frame
		if table_text().has("#1,234 of 56,789"):
			ranked = true
			break
	check(ranked and table_text().has("France rank") and table_text().has("#40 of 150"), "the rank fills in on the results (%s)" % str(table_text()))
	check(Menu.stage_line(0) == "Best %s  ·  France #40" % Ranking.fmt2(gold - 0.9), "the card shows the rank from then on (%s)" % Menu.stage_line(0))
	if peer:
		peer.disconnect_from_host()
	srv.stop()

	# a faster lap makes the cached rank stale until the board answers again
	Records.set_best(Records.stage_key(name), gold - 1.5)
	check(Menu.stage_line(0) == "Best %s" % Ranking.fmt2(gold - 1.5), "a stale rank is not shown")

	# ---- the Special Stage page: best and rank, no medal strip
	Ranking._url_override = ""
	var menu = main.ui.menu
	main._to_menu()
	await frames(2)
	menu.kind = "attack"
	menu.ev = ev.duplicate()
	menu.show_event()
	await frames(2)
	var strips: Array = menu.body.find_children("*", "", true, false).filter(func(n): return n.get_script() == preload("res://scripts/medal_strip.gd"))
	check(strips.is_empty(), "no medal strip on a Special Stage page")
	var labels: Array = menu.body.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(labels.has("Best lap") and labels.has(Ranking.fmt2(gold - 1.5)) and labels.has("World rank"), "the page shows the best lap and the world rank (%s)" % str(labels))

	Records.reset()
	Ranking.reset()
	Wallet.reset()
	print("stage rank test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails > 0 else 0)
