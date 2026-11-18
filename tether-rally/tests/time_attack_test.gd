# Time attack is the plain layout only (Guillaume, 2026-11-13): one record and one ghost per
# track. Its track screen has no variant tiles and no world grid, just one world chip that
# steps through the opened worlds. Special Stages show no medal (Guillaume, 2026-11-18): a list
# card is the track's name and its best lap (and rank), see tests/stage_rank_test.gd.
# 2-player races keep the four variants.
#   godot --headless --path . --script tests/time_attack_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Menu = preload("res://scripts/menu.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

# buttons on the event screen whose tooltip names a variant
func _variant_tiles(menu) -> Array:
	var names := Defs.VARIANTS.map(func(v): return String(v[1]).to_upper().capitalize())
	return menu.body.find_children("*", "Button", true, false).filter(func(b): return b.tooltip_text in names)

func _chips(menu) -> Array:
	return menu.body.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("world_chip"))

func _init() -> void:
	Records.reset()
	check(Menu.variants_for("attack") == ["standard"], "Time attack offers the Standard layout only")
	check(Menu.variants_for("versus").size() == Defs.VARIANTS.size(), "2-player races keep all %d variants" % Defs.VARIANTS.size())

	# a Road Trip medal never shows on a Special Stage card
	var t := 0
	var name: String = Defs.TRACKS[t]["name"]
	Records.award_medal(Records.key(name, "standard"), "trial", 2)
	check(Menu.stage_line(t) == "No time yet", "a Road Trip medal is not a Special Stage time (%s)" % Menu.stage_line(t))

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var menu = main.ui.menu
	main.ui.loading.visible = false
	root.size = Vector2i(1280, 720)
	await frames(2)

	# the list: each card is the track's name and its stage line (no number box, no medal)
	for tt in Defs.TRACKS:
		Records.set_flag("attack", tt["name"])
	menu.kind = "attack"
	menu.show_list()
	await frames(3)
	var order: Array = menu._track_order()
	var cards: Array = menu._scroller.content.get_child(0).get_children()
	var named := true
	for p in cards.size():
		var labels: Array = cards[p].find_children("*", "Label", true, false)
		if labels.size() != 2 or labels[0].text != String(Defs.TRACKS[order[p]]["name"]).to_upper() \
				or labels[1].text != Menu.stage_line(order[p]):
			named = false
			print("  card %d: %s" % [p, labels.map(func(l): return l.text)])
	check(named, "list cards show the track name and its best / rank line")
	var with_rings: Array = cards.filter(func(c): return not c.find_children("*", "MedalStrip", true, false).is_empty() \
		or c.find_children("*", "", true, false).any(func(n): return n.get_script() == preload("res://scripts/medal_strip.gd")))
	check(with_rings.is_empty(), "no medal rings on Special Stage cards (%d)" % with_rings.size())

	# one world open: no chip, no variant tiles, even if the event came in as a variant
	menu.kind = "attack"
	menu.ev = { "track": t, "variant": "collect", "mode": "trial", "humans": 1, "kind": "attack", "idx": t, "theme": "snow" }
	menu.show_event()
	await frames(2)
	check(menu.ev["variant"] == "standard", "a Time attack event always runs Standard")
	check(_variant_tiles(menu).is_empty(), "no variant tiles on the Time attack screen")
	check(_chips(menu).is_empty(), "one world open: no world chip")

	# two worlds open: one chip, a tap steps to the next world and the track opens in it
	Records.set_flag("campaign", "done_" + String(Campaign.CHAPTERS[1]["theme"]))
	menu.show_event()
	await frames(2)
	var chips := _chips(menu)
	check(chips.size() == 1 and chips[0].get_meta("world_chip") == "snow", "two worlds open: one chip, on Snow")
	chips[0].pressed.emit()
	await frames(2)
	var w1 := String(Campaign.CHAPTERS[1]["theme"])
	check(menu.ev["theme"] == w1 and _chips(menu)[0].get_meta("world_chip") == w1, "a tap moves the track to %s (%s)" % [w1, menu.ev["theme"]])
	_chips(menu)[0].pressed.emit()
	await frames(2)
	check(menu.ev["theme"] == "snow", "and back round to Snow")
	var locked := _locked_worlds()
	check(locked.all(func(x): return x != menu.ev["theme"]), "locked worlds are never offered")

	# 2-player race: still the four variant tiles
	menu.kind = "versus"
	menu.ev = { "track": t, "variant": "standard", "mode": "race", "humans": 2, "kind": "versus", "idx": t, "theme": "snow" }
	menu.show_event()
	await frames(2)
	check(_variant_tiles(menu).size() == Defs.VARIANTS.size() and _chips(menu).is_empty(), "2-player screen: 4 variant tiles, no world chip")

	Records.reset()
	print("time attack test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)

func _locked_worlds() -> Array:
	var out := []
	for c in Campaign.CHAPTERS:
		if not Campaign.theme_unlocked(c["theme"]): out.append(c["theme"])
	return out
