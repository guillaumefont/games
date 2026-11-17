class_name VoyageMap
extends ColorRect
## The Voyage map (Guillaume's ask of 2026-11-17: "a map that shows levels"): every level of the
## route as a numbered stop on one winding, scrolling path, system after system. Each stop shows its
## stars and its three medals (speed, points, all stars), locked stops are dimmed with a padlock and
## the furthest open one pulses. After each system's last level, a reward stop shows the cosmetic its
## every-star medal wins. Tapping a level opens its card: the three star goals, each medal with what
## its next tier needs and the sparks it pays, the best run, and Play.
##
## Built in code by Hud, which owns the fonts; signals go back through Hud (sector_picked,
## menu_requested).

signal level_picked(id: String)
signal back_pressed

const NODE := 64.0 ## a level stop's diameter
const STEP := 132.0 ## vertical distance between two stops
const HEADER := 112.0 ## a system's title block
const REWARD := 150.0 ## a system's reward stop and its caption
const SWAY := 92.0 ## how far the path swings left and right
## One colour per system, from the moon palette (Cradle coral, Backwash teal, Lantern violet).
const SYSTEM_COLORS: Array[Color] = [Color("ff8a6b"), Color("6fd6c5"), Color("b49cff"), Color("f2c879")]

var hud: Hud
var scroll: ScrollContainer
var content: Control
var top_bar: MarginContainer
var stars_label: Label ## "14 / 54 stars"
var tally_label: Label ## medals won and bonus sparks
var nodes := {} ## level id -> Button
var centers := {} ## level id -> Vector2, in content coordinates
var headers: Array[Control] = []
var reward_stops: Array[Control] = []
var reward_centers: Array[Vector2] = []
var progress := {}
var current := ""

var sheet: ColorRect ## the level card, over the map
var sheet_title: Label
var sheet_sub: Label
var sheet_stars: Array[StarIcon] = []
var sheet_goals: Array[Label] = []
var sheet_medals: Array[MedalIcon] = []
var sheet_medal_titles: Array[Label] = []
var sheet_medal_next: Array[Label] = []
var sheet_best: Label
var picked := ""
var _t := 0.0


func _init(hud_in: Hud) -> void:
	hud = hud_in
	name = "VoyageMap"
	color = Hud.SPACE
	mouse_filter = Control.MOUSE_FILTER_STOP # taps here never start a run


func build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# top bar: Back, the title, every star and medal won so far
	top_bar = MarginContainer.new()
	top_bar.add_theme_constant_override("margin_left", 16)
	top_bar.add_theme_constant_override("margin_right", 16)
	top_bar.add_theme_constant_override("margin_top", 12)
	top_bar.add_theme_constant_override("margin_bottom", 8)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top_bar)
	var bar := VBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 4)
	top_bar.add_child(bar)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)
	var back := hud._ghost_button("Back", 12, 32, 16)
	back.name = "Back"
	back.pressed.connect(func() -> void: back_pressed.emit())
	row.add_child(back)
	var title := hud._label("Voyage", hud.display_800, 26, Hud.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var srow := HBoxContainer.new()
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_theme_constant_override("separation", 4)
	srow.custom_minimum_size.x = 74
	srow.alignment = BoxContainer.ALIGNMENT_END
	var star := StarIcon.new(14.0, true)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(star)
	stars_label = hud._label("", hud.body_700, 13, Hud.INK)
	srow.add_child(stars_label)
	row.add_child(srow)
	tally_label = hud._label("", hud.body_500, 12, Hud.MUTED)
	tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(tally_label)

	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	content = Control.new()
	content.name = "Path"
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.draw.connect(_draw_path)
	content.resized.connect(_layout)
	scroll.add_child(content)

	for si in Voyage.SYSTEMS.size():
		var sys: Dictionary = Voyage.SYSTEMS[si]
		headers.append(_system_header(si, sys))
		for sec in sys.sectors:
			_level_stop(sec)
		reward_stops.append(_reward_stop(si, sys))
	_build_sheet()
	_layout()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		content.queue_redraw()


## Fills the map from the save: `progress` is save.data.voyage. `focus` is the level to scroll to
## (the furthest open one when empty).
func refresh(progress_in: Dictionary, drift_best: int, claimed: Array, focus := "") -> void:
	progress = progress_in
	current = Voyage.current_id(progress)
	var got := 0
	var total := 0
	for si in Voyage.SYSTEMS.size():
		var sys: Dictionary = Voyage.SYSTEMS[si]
		var ss := Medals.system_stars(sys, progress)
		got += ss[0]
		total += ss[1]
		var h := headers[si]
		(h.find_child("Stars", true, false) as Label).text = "%d / %d stars" % ss
		(h.find_child("Medal", true, false) as MedalIcon).tier = Medals.GOLD if ss[0] >= ss[1] else Medals.NONE
		var open := Voyage.unlocked(sys.sectors[0].id, progress)
		h.modulate.a = 1.0 if open else 0.55
		var item := Unlocks.reward_item("%s:stars" % sys.name)
		var won := claimed.has("%s:stars" % sys.name) or ss[0] >= ss[1]
		var stop := reward_stops[si]
		(stop.find_child("Icon", true, false) as CosmeticIcon).locked = not won
		var cap: Label = stop.find_child("Caption", true, false)
		if item.is_empty():
			cap.text = "All %d stars · +%d sparks" % [ss[1], Medals.SYSTEM_STARS_SPARKS]
		elif won:
			cap.text = "%s %s won" % [item.name, item.kind]
		else:
			cap.text = "All %d stars: %s %s · +%d sparks" % [ss[1], item.name, item.kind, Medals.SYSTEM_STARS_SPARKS]
		cap.add_theme_color_override("font_color", Hud.SAND if won else Hud.MUTED)
		for sec in sys.sectors:
			var b: Button = nodes[sec.id]
			var lvl_open := Voyage.unlocked(sec.id, progress)
			b.disabled = not lvl_open
			b.modulate.a = 1.0 if lvl_open else 0.45
			var rec: Dictionary = progress.get(sec.id, {})
			var n := int(rec.get("stars", 0))
			var srow: Control = b.find_child("StarRow", true, false)
			for i in 3:
				(srow.get_child(i) as StarIcon).lit = i < n
			var m := Medals.of_sector(sec, rec)
			var mrow: Control = b.find_child("MedalRow", true, false)
			for i in 3:
				var icon := mrow.get_child(i) as MedalIcon
				icon.tier = m[icon.kind]
			mrow.visible = lvl_open
	stars_label.text = "%d / %d" % [got, total]
	var t := Medals.tally(progress, drift_best)
	var bonus := 0
	for r in Medals.rewards(progress, drift_best):
		bonus += int(r.sparks)
	tally_label.text = "Rewards  %d gold · %d silver · %d bronze · +%d sparks" % [t[Medals.GOLD], t[Medals.SILVER], t[Medals.BRONZE], bonus]
	close_level()
	content.queue_redraw()
	scroll_to(focus if focus != "" else current)


## Scrolls so level `id` sits a little above the middle of the screen.
func scroll_to(id: String) -> void:
	if not centers.has(id):
		return
	var view_h := scroll.size.y if scroll.size.y > 0 else get_viewport_rect().size.y - 90.0
	var y: float = centers[id].y - view_h * 0.42
	scroll.scroll_vertical = int(clampf(y, 0.0, maxf(0.0, content.custom_minimum_size.y - view_h)))


# ---------- the level card ----------

## Opens the card of level `id` (only open levels have one).
func open_level(id: String) -> void:
	var sec := Voyage.sector(id)
	if sec.is_empty() or not Voyage.unlocked(id, progress):
		return
	picked = id
	var sys := Voyage.system_of(id)
	sheet_title.text = "Level %d" % Voyage.level_number(id)
	sheet_sub.text = "%s · sector %s" % [sys.name, id]
	var rec: Dictionary = progress.get(id, {})
	var n := int(rec.get("stars", 0))
	for i in 3:
		sheet_stars[i].lit = i < n
	sheet_goals[0].text = "Reach moon %d" % sec.moons
	sheet_goals[1].text = "Under %d s" % int(sec.par)
	sheet_goals[2].text = Voyage.goal_text(sec.goal)
	var m := Medals.of_sector(sec, rec)
	for i in 3:
		var icon := sheet_medals[i]
		var tier := int(m[icon.kind])
		icon.tier = tier
		var nxt := ""
		match icon.kind:
			"speed":
				sheet_medal_titles[i].text = "Speed · %s" % (Medals.TIER_NAMES[tier] if tier > 0 else "not won")
				nxt = Medals.next_speed_text(sec, tier)
			"points":
				sheet_medal_titles[i].text = "Points · %s" % (Medals.TIER_NAMES[tier] if tier > 0 else "not won")
				nxt = Medals.next_points_text(Medals.points_marks(sec), tier)
			_:
				sheet_medal_titles[i].text = "All stars · %s" % ("won" if tier > 0 else "not won")
				nxt = "" if tier > 0 else "Win all 3 stars · +%d" % Medals.ALL_STARS_SPARKS
		sheet_medal_next[i].text = (nxt + " sparks") if nxt != "" else "Every reward won"
		sheet_medal_next[i].add_theme_color_override("font_color", Hud.MUTED if nxt != "" else Hud.SAND)
	if rec.is_empty():
		sheet_best.text = "Not cleared yet"
	else:
		sheet_best.text = "Best %d points · %.1f s" % [int(rec.get("score", 0)), float(rec.get("time", 0.0))]
	sheet.visible = true


func close_level() -> void:
	picked = ""
	if sheet != null:
		sheet.visible = false


func _build_sheet() -> void:
	sheet = ColorRect.new()
	sheet.name = "LevelCard"
	sheet.color = Color(Hud.SPACE, 0.7)
	sheet.visible = false
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(sheet)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_level())
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP # taps on the card don't close it
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1d2048")
	sb.border_color = Color(Hud.INK, 0.12)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size.x = 330
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	sheet_title = hud._label("", hud.display_800, 28, Hud.INK)
	sheet_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sheet_title)
	sheet_sub = hud._label("", hud._spaced(hud.body_700, 1.5), 12, Hud.SAND)
	sheet_sub.uppercase = true
	sheet_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sheet_sub)
	var big := HBoxContainer.new()
	big.alignment = BoxContainer.ALIGNMENT_CENTER
	big.add_theme_constant_override("separation", 8)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var s := StarIcon.new(26.0)
		sheet_stars.append(s)
		big.add_child(s)
	box.add_child(big)
	var goals := HBoxContainer.new()
	goals.alignment = BoxContainer.ALIGNMENT_CENTER
	goals.add_theme_constant_override("separation", 10)
	goals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var g := hud._label("", hud.body_500, 12, Hud.MUTED)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sheet_goals.append(g)
		goals.add_child(g)
		if i < 2:
			goals.add_child(hud._label("·", hud.body_500, 12, Hud.MUTED))
	box.add_child(goals)
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(Hud.INK, 0.1)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	box.add_child(sep)
	var rewards := hud._label("Rewards", hud._spaced(hud.body_700, 1.5), 11, Hud.MUTED)
	rewards.uppercase = true
	box.add_child(rewards)
	for kind in ["speed", "points", "stars"]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := MedalIcon.new(30.0, kind)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sheet_medals.append(icon)
		r.add_child(icon)
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := hud._label("", hud.body_700, 14, Hud.INK)
		sheet_medal_titles.append(t)
		c.add_child(t)
		var nx := hud._label("", hud.body_500, 12, Hud.MUTED)
		sheet_medal_next.append(nx)
		c.add_child(nx)
		r.add_child(c)
		box.add_child(r)
	sheet_best = hud._label("", hud.body_500, 12, Hud.MUTED)
	sheet_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sheet_best)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var close := hud._ghost_button("Close", 13, 44, 22)
	close.name = "Close"
	close.pressed.connect(close_level)
	btns.add_child(close)
	var play := Button.new()
	play.name = "Play"
	play.text = "PLAY"
	play.focus_mode = Control.FOCUS_NONE
	play.custom_minimum_size = Vector2(150, 44)
	play.add_theme_font_override("font", hud._spaced(hud.display_500, 1.8))
	play.add_theme_font_size_override("font_size", 14)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var psb := StyleBoxFlat.new()
		psb.bg_color = Hud.SAND if st != "pressed" else Hud.SAND.darkened(0.12)
		psb.set_corner_radius_all(22)
		psb.anti_aliasing = true
		play.add_theme_stylebox_override(st, psb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		play.add_theme_color_override(c, Hud.SPACE)
	play.pressed.connect(func() -> void:
		if picked != "":
			var id := picked
			close_level()
			level_picked.emit(id))
	btns.add_child(play)
	box.add_child(btns)


# ---------- the path ----------

func _system_header(si: int, sys: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "System_%d" % (si + 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	var l := hud._label("System %d · %s" % [si + 1, sys.name], hud._spaced(hud.body_700, 1.5), 13, SYSTEM_COLORS[si % SYSTEM_COLORS.size()])
	l.uppercase = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var intro := hud._label(sys.intro, hud.body_500, 14, Hud.MUTED)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var medal := MedalIcon.new(18.0, "stars")
	medal.name = "Medal"
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(medal)
	var st := hud._label("", hud.body_700, 13, Hud.INK)
	st.name = "Stars"
	row.add_child(st)
	box.add_child(row)
	content.add_child(box)
	return box


func _level_stop(sec: Dictionary) -> void:
	var b := Button.new()
	b.name = "Sector_" + sec.id
	b.set_meta("id", sec.id)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS # a drag that starts on a stop still scrolls the map
	b.flat = true
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.size = Vector2(104, NODE + 44)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 5)
	b.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var num := hud._label(str(Voyage.level_number(sec.id)), hud.display_800, 22, Hud.INK)
	num.name = "Number"
	num.custom_minimum_size = Vector2(0, NODE)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(num)
	var srow := HBoxContainer.new()
	srow.name = "StarRow"
	srow.alignment = BoxContainer.ALIGNMENT_CENTER
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_theme_constant_override("separation", 2)
	for i in 3:
		srow.add_child(StarIcon.new(12.0))
	col.add_child(srow)
	var mrow := HBoxContainer.new()
	mrow.name = "MedalRow"
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mrow.add_theme_constant_override("separation", 3)
	for kind in ["speed", "points", "stars"]:
		mrow.add_child(MedalIcon.new(13.0, kind))
	col.add_child(mrow)
	var id: String = sec.id
	b.pressed.connect(func() -> void: open_level(id))
	content.add_child(b)
	nodes[sec.id] = b


func _reward_stop(si: int, sys: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "Reward_%s" % sys.name
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var item := Unlocks.reward_item("%s:stars" % sys.name)
	var icon := CosmeticIcon.new(item.get("id", ""), item.get("kind", "ship"))
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(72, 72)
	icon.pivot_offset = Vector2(36, 36)
	icon.scale = Vector2(1.5, 1.5)
	box.add_child(hud._centered(icon))
	var cap := hud._label("", hud.body_700, 12, Hud.MUTED)
	cap.name = "Caption"
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	content.add_child(box)
	return box


## Places every stop for the current width: the path swings left and right down the screen.
func _layout() -> void:
	if content == null:
		return
	var w := content.size.x if content.size.x > 0 else get_viewport_rect().size.x
	var y := 18.0
	var i := 0
	for si in Voyage.SYSTEMS.size():
		var sys: Dictionary = Voyage.SYSTEMS[si]
		var h := headers[si]
		h.position = Vector2(0, y)
		h.size = Vector2(w, HEADER - 24)
		y += HEADER
		for j in sys.sectors.size():
			var c := Vector2(w / 2.0 + SWAY * sin(i * 1.05 + 0.5), y + NODE / 2.0)
			centers[sys.sectors[j].id] = c
			var b: Button = nodes[sys.sectors[j].id]
			b.position = c - Vector2(b.size.x / 2.0, NODE / 2.0)
			y += STEP
			i += 1
		var rc := Vector2(w / 2.0, y + 36.0)
		reward_centers.resize(Voyage.SYSTEMS.size())
		reward_centers[si] = rc
		var stop := reward_stops[si]
		stop.position = Vector2(0, y)
		stop.size = Vector2(w, REWARD - 30)
		y += REWARD
	content.custom_minimum_size = Vector2(0, y + 20.0)
	content.queue_redraw()


func _draw_path() -> void:
	var all := Voyage.all_sectors()
	# the route, as dots: lit up to the furthest open level
	var pts: Array[Vector2] = []
	var lit: Array[bool] = []
	var si := 0
	var k := 0
	for sys in Voyage.SYSTEMS:
		for sec in sys.sectors:
			pts.append(centers.get(sec.id, Vector2.ZERO))
			lit.append(int(progress.get(sec.id, {}).get("stars", 0)) > 0)
			k += 1
		pts.append(reward_centers[si] if si < reward_centers.size() else Vector2.ZERO)
		lit.append(false)
		si += 1
	# the dots stop short of text: level labels, system titles, reward captions
	var keep_out: Array[Rect2] = []
	for id in nodes:
		var btn: Button = nodes[id]
		keep_out.append(Rect2(btn.position + Vector2(btn.size.x / 2.0 - 28.0, NODE + 2.0), Vector2(56.0, btn.size.y - NODE - 2.0)))
	for h in headers:
		keep_out.append(Rect2(h.position + Vector2(0, 8), h.size - Vector2(0, 8)))
	for st in reward_stops:
		var cap: Control = st.find_child("Caption", true, false)
		keep_out.append(Rect2(cap.global_position - content.global_position, cap.size).grow(4))
	for n in pts.size() - 1:
		var a := pts[n]
		var b := pts[n + 1]
		var mid := (a + b) / 2.0
		var ctrl := Vector2(lerpf(a.x, b.x, 0.15), mid.y)
		var length := a.distance_to(b)
		var steps := int(length / 10.0)
		var col := Color(Hud.SAND, 0.75) if lit[n] else Color(Hud.INK, 0.16)
		for s in range(1, steps):
			var t := float(s) / steps
			var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
			if p.distance_to(a) < NODE / 2.0 + 4.0 or p.distance_to(b) < NODE / 2.0 + 4.0:
				continue
			var hidden := false
			for rect in keep_out:
				hidden = hidden or rect.has_point(p)
			if hidden:
				continue
			content.draw_circle(p, 2.2, col, true, -1.0, true)
	# a system's reward stop: a ring the cosmetic sits in
	for r in reward_centers.size():
		var ss := Medals.system_stars(Voyage.SYSTEMS[r], progress)
		var won := ss[0] >= ss[1]
		var c: Color = SYSTEM_COLORS[r % SYSTEM_COLORS.size()]
		content.draw_circle(reward_centers[r], 40.0, Color(c, 0.12 if won else 0.05), true, -1.0, true)
		content.draw_arc(reward_centers[r], 40.0, 0, TAU, 48, Color(Hud.SAND, 0.9) if won else Color(c, 0.35), 2.0, true)
		if ss[1] > 0 and not won:
			content.draw_arc(reward_centers[r], 40.0, -PI / 2.0, -PI / 2.0 + TAU * ss[0] / ss[1], 48, Hud.SAND, 3.0, true)
	# the level stops: a moon in its system's colour; gold rim for all three stars
	for idx in all.size():
		var sec: Dictionary = all[idx]
		var c: Vector2 = centers.get(sec.id, Vector2.ZERO)
		var sys_i := 0
		for q in Voyage.SYSTEMS.size():
			if Voyage.SYSTEMS[q].sectors.has(sec):
				sys_i = q
		var hue: Color = SYSTEM_COLORS[sys_i % SYSTEM_COLORS.size()]
		var open := Voyage.unlocked(sec.id, progress)
		var n := int(progress.get(sec.id, {}).get("stars", 0))
		var r := NODE / 2.0
		if sec.id == current:
			var pulse := 0.5 + 0.5 * sin(_t * 3.2)
			content.draw_arc(c, r + 7.0 + 3.0 * pulse, 0, TAU, 48, Color(Hud.SAND, 0.35 + 0.4 * pulse), 2.5, true)
		if not open:
			content.draw_circle(c, r, Color(Hud.INK, 0.04), true, -1.0, true)
			content.draw_arc(c, r, 0, TAU, 48, Color(Hud.INK, 0.14), 2.0, true)
			_draw_lock(c + Vector2(r * 0.62, r * 0.62))
			continue
		content.draw_circle(c, r, Color(hue, 0.2 if n > 0 else 0.1), true, -1.0, true)
		var rim := Hud.SAND if n >= 3 else Color(hue, 0.85 if n > 0 else 0.5)
		content.draw_arc(c, r, 0, TAU, 48, rim, 3.0 if n >= 3 else 2.0, true)


func _draw_lock(at: Vector2) -> void:
	content.draw_circle(at, 11.0, Color("1d2048"), true, -1.0, true)
	content.draw_arc(at + Vector2(0, -2.5), 4.0, PI, TAU, 12, Color(Hud.INK, 0.6), 1.8, true)
	content.draw_rect(Rect2(at + Vector2(-5.5, -2.5), Vector2(11, 8)), Color(Hud.INK, 0.6), true)
