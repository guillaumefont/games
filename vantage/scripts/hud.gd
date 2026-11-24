class_name Hud
extends Control
## The interface: the in-flight HUD (hull, score, scrap, banners, boss bar), the reticle and
## target brackets of the fortress chase, the hangar (upgrades, launch) and the results.

const FONT := preload("res://fonts/Inter-Variable.ttf")
const INK := Color8(0xf2, 0xf6, 0xfa)
const DIM := Color(0.86, 0.92, 1.0, 0.7)
const GOLD := Color8(0xff, 0xd2, 0x4a)
const CY := Color8(0x5f, 0xe2, 0xff)
const RED := Color8(0xff, 0x4d, 0x6d)
## In-level power steps (the cores are the same cyan-white).
const POWER := Color8(0x6a, 0xf4, 0xff)
## Below the title, tag line and version; the hangar panel and the ship stay under it.
const HANGAR_TOP := 330.0
## Open sky kept between that and the hangar panel for the idling ship.
const SHIP_ROOM := 140.0

var game: Game
var score_l: Label
var scrap_l: Label
var banner_l: Label
var sub_l: Label
var hangar: Control
var hangar_panel: PanelContainer
var results: Control
var hangar_scrap: Label
var hangar_best: Label
var update_btn: Button
var version_btn: Button
## Wipes the progress; the first tap arms it, a second within `RESET_ARM` s confirms.
var reset_btn: Button
var reset_armed := false
const RESET_ARM := 4.0
## On the pause screen: quits the run back to the hangar, with the same two-tap confirmation.
var quit_btn: Button
var quit_armed := false
## A short note under the version ("Checking…", "Up to date"), cleared on the next refresh.
var version_note := ""
var rows := {}
## The campaign timeline in the hangar: the world's name, its arrows and its three levels.
var world_l: Label
var world_tag: Label
var world_prev: Button
var world_next: Button
var level_btns: Array[Button] = []
var go_btn: Button
var res_title: Label
var res_body: Label
var res_hint: Label
var hurt_t := 0.0
var scrap_t := 0.0
var power_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = FONT
	th.default_font_size = 26
	theme = th
	score_l = label(30, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	place(score_l, Rect2(1, 0, 0, 0), Rect2(-360, 26, 330, 40))
	scrap_l = label(26, GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	place(scrap_l, Rect2(1, 0, 0, 0), Rect2(-360, 66, 330, 36))
	banner_l = label(64, INK, HORIZONTAL_ALIGNMENT_CENTER, 900)
	place(banner_l, Rect2(0, 0.3, 1, 0), Rect2(0, -50, 0, 80))
	sub_l = label(28, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	place(sub_l, Rect2(0, 0.3, 1, 0), Rect2(0, 32, 0, 40))
	build_hangar()
	build_results()
	build_quit()
	get_viewport().size_changed.connect(fit_hangar)
	hangar_panel.resized.connect(fit_hangar)
	fit_hangar()


## Anchors (x, y, width, height as fractions of the parent) and offsets (x, y, extra width,
## height in pixels) in one call.
func place(c: Control, anchors: Rect2, px: Rect2) -> void:
	c.anchor_left = anchors.position.x
	c.anchor_top = anchors.position.y
	c.anchor_right = anchors.position.x + anchors.size.x
	c.anchor_bottom = anchors.position.y + anchors.size.y
	c.offset_left = px.position.x
	c.offset_top = px.position.y
	c.offset_right = px.position.x + px.size.x
	c.offset_bottom = px.position.y + px.size.y


func label(size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, weight := 600) -> Label:
	var l := Label.new()
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {"wght": weight}
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func glass(radius := 28) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.13, 0.8)
	sb.border_color = Color(1, 1, 1, 0.14)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(26)
	return sb


func button(text: String, col: Color, size := 28) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if st != "disabled" else Color(1, 1, 1, 0.08)
		if st == "pressed":
			sb.bg_color = col.darkened(0.2)
		if st == "focus":
			sb.draw_center = false
		sb.set_corner_radius_all(18)
		sb.set_content_margin_all(14)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color8(0x0b, 0x12, 0x1c))
	b.add_theme_color_override("font_hover_color", Color8(0x0b, 0x12, 0x1c))
	b.add_theme_color_override("font_pressed_color", Color8(0x0b, 0x12, 0x1c))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	b.focus_mode = Control.FOCUS_NONE
	return b


# ---------------------------------------------------------------- hangar

func build_hangar() -> void:
	hangar = Control.new()
	hangar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hangar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hangar)
	var title := label(96, INK, HORIZONTAL_ALIGNMENT_CENTER, 850)
	title.text = "VANTAGE"
	title.reparent(hangar)
	place(title, Rect2(0, 0, 1, 0), Rect2(0, 110, 0, 110))
	world_tag = label(26, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	world_tag.reparent(hangar)
	place(world_tag, Rect2(0, 0, 1, 0), Rect2(0, 218, 0, 40))
	# the running version; a tap checks for a newer one and reloads into it
	version_btn = Button.new()
	version_btn.flat = true
	version_btn.focus_mode = Control.FOCUS_NONE
	version_btn.add_theme_font_size_override("font_size", 22)
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		version_btn.add_theme_color_override(c, DIM)
	version_btn.pressed.connect(func() -> void: game.version_tap())
	hangar.add_child(version_btn)
	place(version_btn, Rect2(0, 0, 1, 0), Rect2(120, 262, -240, 48))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", glass())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_top = 1.0
	panel.offset_left = 24
	panel.offset_right = -24
	# sized by its content and pinned to the bottom: it grows upwards, never off the screen
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = -30
	panel.offset_bottom = -30
	hangar_panel = panel
	hangar.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	build_campaign(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var h := label(34, INK, HORIZONTAL_ALIGNMENT_LEFT, 800)
	h.text = "Hangar"
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.reparent(head)
	hangar_scrap = label(32, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 750)
	hangar_scrap.reparent(head)
	for key: String in Rules.ORDER:
		var u: Dictionary = Rules.UPGRADES[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		v.add_child(row)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		var name_l := label(30, INK, HORIZONTAL_ALIGNMENT_LEFT, 700)
		name_l.text = u.name
		name_l.reparent(col)
		var pips := label(22, CY, HORIZONTAL_ALIGNMENT_LEFT, 700)
		pips.reparent(col)
		var desc := label(20, DIM)
		desc.text = u.desc
		desc.reparent(col)
		var b := button("", GOLD, 26)
		b.custom_minimum_size = Vector2(170, 72)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			if game.buy(key):
				refresh_hangar())
		row.add_child(b)
		rows[key] = {"pips": pips, "buy": b}
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	hangar_best = label(22, DIM, HORIZONTAL_ALIGNMENT_LEFT)
	hangar_best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hangar_best.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hangar_best.reparent(foot)
	reset_btn = Button.new()
	reset_btn.flat = true
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(0, 48)
	reset_btn.add_theme_font_size_override("font_size", 22)
	reset_btn.pressed.connect(reset_tap)
	foot.add_child(reset_btn)
	update_btn = button("", GOLD, 26)
	update_btn.visible = false
	update_btn.pressed.connect(func() -> void: game.refresh_game())
	v.add_child(update_btn)
	go_btn = button("LAUNCH", CY, 40)
	go_btn.custom_minimum_size = Vector2(0, 104)
	go_btn.pressed.connect(func() -> void: game.launch())
	v.add_child(go_btn)


## Reset progress, with a confirmation: the first tap turns the button red ("tap again"), a
## second tap within RESET_ARM seconds wipes the save; otherwise it calms down again.
func reset_tap() -> void:
	if not reset_armed:
		reset_armed = true
		game.sound.play("tap")
		refresh_reset()
		get_tree().create_timer(RESET_ARM).timeout.connect(func() -> void:
			if reset_armed:
				reset_armed = false
				refresh_reset())
		return
	reset_armed = false
	game.reset_progress()
	refresh_hangar()


func refresh_reset() -> void:
	reset_btn.text = "Tap again to wipe all" if reset_armed else "Reset progress"
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		reset_btn.add_theme_color_override(c, RED if reset_armed else DIM)


## The campaign as a timeline: ‹ WORLD › on top, then the world's three levels on a track,
## cleared ones with their best grade, locked ones greyed out. Tapping one selects it (its
## world shows behind the menu); LAUNCH plays it.
func build_campaign(v: VBoxContainer) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	world_prev = button("‹", Color(1, 1, 1, 0.85), 40)
	world_prev.custom_minimum_size = Vector2(72, 64)
	world_prev.pressed.connect(func() -> void: step_world(-1))
	top.add_child(world_prev)
	world_l = label(30, INK, HORIZONTAL_ALIGNMENT_CENTER, 800)
	world_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	world_l.reparent(top)
	world_next = button("›", Color(1, 1, 1, 0.85), 40)
	world_next.custom_minimum_size = Vector2(72, 64)
	world_next.pressed.connect(func() -> void: step_world(1))
	top.add_child(world_next)
	# the level nodes on a track
	var lane := Control.new()
	lane.custom_minimum_size = Vector2(0, 118)
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lane)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.35)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.add_child(track)
	place(track, Rect2(0, 0.5, 1, 0), Rect2(40, -2, -80, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	lane.add_child(row)
	place(row, Rect2(0, 0, 1, 1), Rect2(0, 0, 0, 0))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in Campaign.PER_WORLD:
		var b := button("", CY, 22)
		b.custom_minimum_size = Vector2(150, 118)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void:
			game.pick_level(int(game.level) / Campaign.PER_WORLD * Campaign.PER_WORLD + k)
			game.sound.play("tap")
			refresh_hangar())
		row.add_child(b)
		level_btns.append(b)
	v.add_child(line)


## Shows the previous or next world (its first open level), if any of it is open.
func step_world(d: int) -> void:
	var w := game.level / Campaign.PER_WORLD + d
	var lv := w * Campaign.PER_WORLD
	if w < 0 or w >= Campaign.WORLDS.size() or not Campaign.is_open(game.s, lv):
		return
	# the furthest open level of that world
	game.pick_level(mini(lv + Campaign.PER_WORLD - 1, int(game.s.open)))
	game.sound.play("tap")
	refresh_hangar()


func level_style(col: Color, filled: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col if filled else Color(0.05, 0.08, 0.13, 0.82)
	sb.border_color = col
	sb.set_border_width_all(0 if filled else 3)
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(10)
	return sb


func refresh_campaign() -> void:
	var s := game.s
	var w := game.level / Campaign.PER_WORLD
	var open_worlds := int(s.open) / Campaign.PER_WORLD + 1
	world_tag.text = "Campaign  ·  World %d of %d" % [w + 1, Campaign.WORLDS.size()]
	world_l.text = "WORLD %d  ·  %s" % [w + 1, Campaign.WORLDS[w].name.to_upper()]
	world_prev.disabled = w == 0
	world_next.disabled = w + 1 >= open_worlds
	for k in Campaign.PER_WORLD:
		var lv := w * Campaign.PER_WORLD + k
		var b := level_btns[k]
		var open := Campaign.is_open(s, lv)
		var sel := lv == game.level
		var grade: String = s.grades.get(Campaign.code(lv), "")
		var kind: String = Campaign.midboss(lv).name
		b.disabled = not open
		b.text = "%s\n%s\n%s" % [Campaign.code(lv), Campaign.level_name(lv) if open else "Locked",
			("Grade " + grade) if grade != "" else kind]
		var col := CY if sel else (GOLD if grade != "" else Color(1, 1, 1, 0.8))
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, level_style(col, sel))
		var ink := Color8(0x0b, 0x12, 0x1c) if sel else INK
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(c, ink)
	go_btn.text = "LAUNCH  %s" % Campaign.code(game.level)


## The bottom of the screen hidden by the system (gesture bar, rounded corners), in HUD pixels.
func bottom_inset() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or safe.size.y <= 0.0:
		return 0.0
	return maxf(0.0, (win.y - safe.end.y) * get_viewport().get_visible_rect().size.x / win.x)


## Keeps the hangar panel whole: lifted clear of the gesture bar and, on a short screen, scaled
## down from its bottom edge so it stays below the title, the version and the ship.
func fit_hangar() -> void:
	var vp := get_viewport().get_visible_rect().size
	var p := hangar_panel
	var h := p.get_combined_minimum_size().y
	var margin := 30.0 + bottom_inset()
	p.offset_bottom = -margin
	p.offset_top = -margin - h
	var room := vp.y - margin - HANGAR_TOP - SHIP_ROOM
	var k := clampf(room / maxf(h, 1.0), 0.5, 1.0)
	p.pivot_offset = Vector2((vp.x - 48.0) * 0.5, h)
	p.scale = Vector2(k, k)


## Where the hangar panel starts on screen (its top edge, scaled), in HUD pixels.
func hangar_panel_top() -> float:
	var p := hangar_panel
	return p.position.y + p.pivot_offset.y * (1.0 - p.scale.y)


func refresh_hangar() -> void:
	var s := game.s
	hangar_scrap.text = "◆ " + Rules.fmt(s.scrap)
	refresh_campaign()
	for key: String in Rules.ORDER:
		var r: Dictionary = rows[key]
		var lv := Rules.level(s, key)
		var mx: int = Rules.UPGRADES[key].max
		r.pips.text = "■ ".repeat(lv) + "□ ".repeat(mx - lv)
		var c := Rules.cost(s, key)
		var b: Button = r.buy
		b.text = "MAX" if c < 0 else "◆ " + Rules.fmt(c)
		b.disabled = not Rules.can_buy(s, key)
	hangar_best.text = "Best score  %s   ·   Sorties  %d" % [Rules.fmt(s.best), s.runs]
	refresh_reset()
	var build: String = ProjectSettings.get_setting("application/config/version", "")
	if build == "":
		build = "dev"
	if game.new_build > 0:
		version_btn.text = "Version %s  ·  build %d is out, tap to update" % [build, game.new_build]
		version_btn.add_theme_color_override("font_color", GOLD)
	else:
		version_btn.text = "Version %s%s" % [build, ("  ·  " + version_note) if version_note != "" else ""]
		version_btn.add_theme_color_override("font_color", DIM)
	update_btn.visible = game.new_build > 0
	update_btn.text = "New version %d · restart" % game.new_build


func show_hangar() -> void:
	refresh_hangar()
	hangar.visible = true
	results.visible = false


func show_play() -> void:
	hangar.visible = false
	results.visible = false


# ---------------------------------------------------------------- results

func build_results() -> void:
	results = PanelContainer.new()
	results.add_theme_stylebox_override("panel", glass())
	results.set_anchors_preset(Control.PRESET_CENTER)
	results.offset_left = -300
	results.offset_right = 300
	results.offset_top = -260
	results.offset_bottom = 260
	results.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(results)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	results.add_child(v)
	res_title = label(54, INK, HORIZONTAL_ALIGNMENT_CENTER, 850)
	res_title.reparent(v)
	res_body = label(30, INK, HORIZONTAL_ALIGNMENT_CENTER, 550)
	res_body.reparent(v)
	res_hint = label(24, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	res_hint.text = "Tap to return to the hangar"
	res_hint.reparent(v)
	results.visible = false


func show_results() -> void:
	var r := game.run
	hangar.visible = false
	results.visible = true
	var last: bool = int(r.level) % Campaign.PER_WORLD == Campaign.PER_WORLD - 1
	res_title.text = ("WORLD CLEAR" if last else "LEVEL CLEAR") if r.cleared else "SHOT DOWN"
	res_title.add_theme_color_override("font_color", CY if r.cleared else RED)
	var lines := ["%s  ·  %s" % [Campaign.code(r.level), Campaign.level_name(r.level)],
		"Score  %s%s" % [Rules.fmt(r.score), "  (best!)" if r.new_best else ""],
		"Scrap  ◆ %s" % Rules.fmt(r.scrap),
		"Kills  %d / %d" % [r.kills, r.total],
		"Hits taken  %d" % r.hits]
	if r.cleared:
		lines.append("Grade  %s" % r.grade)
	if r.opened >= 0:
		var nw: bool = int(r.opened) % Campaign.PER_WORLD == 0
		lines.append(("New world: " + Campaign.world_of(r.opened).name) if nw else
			("Unlocked  %s  %s" % [Campaign.code(r.opened), Campaign.level_name(r.opened)]))
	res_body.text = "\n".join(lines)


# ---------------------------------------------------------------- pause menu

## "Main menu" under the pause title and hint (Guillaume's call). Only shown once time has stopped, so a finger coming back
## down to fly never lands on it; the button takes its tap, so pressing it doesn't resume.
func build_quit() -> void:
	quit_btn = Button.new()
	quit_btn.focus_mode = Control.FOCUS_NONE
	quit_btn.add_theme_font_size_override("font_size", 28)
	var sb := glass(24)
	sb.set_content_margin_all(18)
	for st in ["normal", "hover", "pressed"]:
		quit_btn.add_theme_stylebox_override(st, sb)
	place(quit_btn, Rect2(0.5, 0.42, 0, 0), Rect2(-170, 110, 340, 76))
	quit_btn.pressed.connect(quit_tap)
	add_child(quit_btn)
	quit_btn.visible = false
	refresh_quit()


## First tap arms it ("Tap again to quit"), a second within RESET_ARM seconds ends the run.
func quit_tap() -> void:
	if not quit_armed:
		quit_armed = true
		game.sound.play("tap")
		refresh_quit()
		get_tree().create_timer(RESET_ARM).timeout.connect(func() -> void:
			if quit_armed:
				quit_armed = false
				refresh_quit())
		return
	quit_armed = false
	refresh_quit()
	game.quit_run()


func refresh_quit() -> void:
	quit_btn.text = "Tap again to quit" if quit_armed else "Main menu"
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		quit_btn.add_theme_color_override(c, RED if quit_armed else INK)


# ---------------------------------------------------------------- in flight

func ping_scrap() -> void:
	scrap_t = 0.25


func ping_power() -> void:
	power_t = 0.5


func flash_hurt() -> void:
	hurt_t = 0.35


func sync() -> void:
	var dt := get_process_delta_time()
	hurt_t = maxf(0.0, hurt_t - dt)
	scrap_t = maxf(0.0, scrap_t - dt)
	power_t = maxf(0.0, power_t - dt)
	var playing := game.phase not in ["hangar", "results"]
	quit_btn.visible = game.paused() and game.started
	if not quit_btn.visible and quit_armed:
		quit_armed = false
		refresh_quit()
	score_l.visible = playing
	scrap_l.visible = playing
	if playing:
		score_l.text = Rules.fmt(game.run.score)
		scrap_l.text = "◆ " + Rules.fmt(game.run.scrap)
		var sc := 1.0 + scrap_t * 0.8
		scrap_l.scale = Vector2(sc, sc)
		scrap_l.pivot_offset = Vector2(330, 18)
	var a := clampf(game.banner_t / 0.4, 0.0, 1.0) if playing else 0.0
	banner_l.text = game.banner
	sub_l.text = game.sub_banner
	banner_l.modulate.a = a
	sub_l.modulate.a = a
	if results.visible:
		res_hint.modulate.a = 0.5 + 0.5 * sin(game.phase_t * 4.0) if game.phase_t > 0.8 else 0.0
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var v := size
	if game.pov_mode():
		var k := smoothstep(0.0, 0.6, game.phase_t) if game.phase == "pov" else 1.0
		if game.phase == "escape":
			k = 1.0 - smoothstep(0.0, 0.8, game.phase_t)
		draw_locks()
		draw_reticle(game.aim, k)
	if game.phase not in ["hangar", "results"]:
		# hull pips
		var mx := Rules.max_hp(game.s)
		for i in mx:
			var r := Rect2(30 + i * 42, 34, 32, 32)
			draw_rect(r, Color(1, 1, 1, 0.16), true)
			if i < game.hp:
				draw_rect(r.grow(-5), CY if game.hp > 1 else RED, true)
		# power: the in-level spread, a bar of steps under the hull (pulses when it changes)
		for i in Rules.POWER_MAX:
			var r := Rect2(30 + i * 30, 76, 24, 12)
			draw_rect(r.grow(power_t * 6.0), Color(1, 1, 1, 0.16 + power_t * 0.5), true)
			if i < game.power:
				draw_rect(r, POWER if game.power < Rules.POWER_MAX else INK, true)
		draw_string(FONT, Vector2(36 + Rules.POWER_MAX * 30, 89), "MAX" if game.power >= Rules.POWER_MAX else "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(INK, 0.7 + power_t * 0.6))
		# boss / reactor bar
		var bar := game.boss_bar()
		if not bar.is_empty():
			var w := v.x - 120
			var frac := clampf(bar[0], 0, 1)
			draw_rect(Rect2(60, 132, w, 12), Color(1, 1, 1, 0.18))
			draw_rect(Rect2(60, 132, w * frac, 12), CY if game.core and game.shielded() else RED)
			draw_string(FONT, Vector2(60, 124), bar[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.85))
	if hurt_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, v), Color(1, 0.2, 0.25, hurt_t * 0.5))
	draw_pause(v)


## Before the first touch of a level, "Touch to start". Then, the finger is lifted: the screen dims as time slows, and once it stops, a pulsing hint.
func draw_pause(v: Vector2) -> void:
	if not game.pausable():
		return
	var still := 1.0 - game.time_speed()
	if still <= 0.0:
		return
	if not game.started:
		# a level waiting for its first touch: not a pause, just the prompt
		# under the level banner, with a shadow so it reads on any ground
		var a := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.004)
		var p := Vector2(0, v.y * 0.62)
		draw_string(FONT, p + Vector2(0, 3), "Touch to start", HORIZONTAL_ALIGNMENT_CENTER, v.x, 44, Color(0, 0, 0, 0.45 * a))
		draw_string(FONT, p, "Touch to start", HORIZONTAL_ALIGNMENT_CENTER, v.x, 44, Color(INK, a))
		return
	draw_rect(Rect2(Vector2.ZERO, v), Color(0.02, 0.04, 0.08, 0.35 * still))
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.004)
	var c := Color(INK, still * still * pulse)
	var y := v.y * 0.42
	draw_string(FONT, Vector2(0, y), "PAUSED", HORIZONTAL_ALIGNMENT_CENTER, v.x, 56, c)
	draw_string(FONT, Vector2(0, y + 50), "Touch to fly", HORIZONTAL_ALIGNMENT_CENTER, v.x, 28, Color(DIM, c.a))


func draw_reticle(p: Vector2, k: float) -> void:
	var c := Color(CY, 0.95 * k)
	draw_arc(p, 34, 0, TAU, 40, c, 3, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + d * 22, p + d * 46, c, 3)
	draw_circle(p, 4, c)


## Brackets on the foes ahead, so they read against the ground.
func draw_locks() -> void:
	for f: Game.Obj in game.foes:
		if f.dead or (f.kind == "orb" and f.homing <= 0.0) or f.ground:
			continue
		# on the fortress, only the section being fought is bracketed
		if f.on_fort and f.sec != game.fort_sec:
			continue
		if game.cam.is_position_behind(f.pos):
			continue
		var p := game.cam.unproject_position(f.pos)
		var dist := game.cam.global_position.distance_to(f.pos)
		var r := clampf(f.r * 700.0 / maxf(dist, 1.0), 14, 90)
		var c := Color(RED, 0.85)
		if (f.kind == "core" and game.shielded()) or game.fort_guarded(f):
			c = Color(CY, 0.7)
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var corner := p + Vector2(sx, sy) * r
				draw_line(corner, corner - Vector2(sx * r * 0.4, 0), c, 2)
				draw_line(corner, corner - Vector2(0, sy * r * 0.4), c, 2)
