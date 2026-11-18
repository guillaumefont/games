class_name VHud
extends Control
## HUD and menus of the portrait game, built for a tall screen: score and hull at the top
## left, pause and the ultimate gauge at the top right, nothing near the bottom where the
## thumb is. Menus are one centred column of glass buttons.

signal stage_chosen(stage: int, ship: String)
signal resume_pressed
signal retry_pressed
signal next_pressed
signal menu_pressed
signal mute_pressed
signal safe_toggled
signal refresh_pressed
signal pause_pressed
signal ult_pressed
signal tier_pressed(tier: int)
signal paint_chosen(ship: String, id: String)

const C_TEXT := Color("f4f2ff")
const C_MUTED := Color("bdb6e0")
const C_SPORE := Color("ff4fa3")
const C_LANCE := Color("3ff0e0")
const C_AMBER := Color("ffb547")
const C_VIOLET := Color("8c7bff")
const C_INK := Color("0b0830")
const COL_W := 520.0

var fonts := {}
var ship := "lance"
var score := "0"
var hull := 3
var ships := 3
var ult := 0.0
var ult_ready := false
var charge := 0.0
var charge_lv := 0
var boss := -1.0
var boss_name := ""
var stage_name := ""
var playing := false
## Replay progress (set by the game after loading the save) and the tier picked on the menu.
var prog: Progress
var tier := 0

var menu_scr: Control
var pause_scr: Control
var result_scr: Control
var _ship_btns := {}
## The stage map: six world tabs and the selected world's eight stages.
var _stage_btns: Array = []
var _world_btns: Array = []
var _world_lbl: Label
var world_sel := 0
var bests: Array = []
var _crash: PanelContainer
var _crash_txt: Label
var _crash_report := ""
var _btn_copy: Button
var _btn_gfx: Button
var btn_mute: Button
var btn_build: Button
var _build_id := ""
var _result_title: Label
var _result_sub: Label
var _result_next: Button
var _banner: Label
var _banner_sub: Label
var _banner_t := 0
var btn_pause: Button
var _tier_btns: Array = []
var _stage_pips: Array = []
var _btn_medals: Button
var medals_scr: Control
var _medals_total: Label
var _paint_btns := {}
var _result_pips: Pips
var _result_lines: Label
var _result_tier: Button
var ult_rect := Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for w in [500, 700, 800]:
		fonts[w] = load("res://assets/fonts/rubik-latin-%d-normal.woff2" % w)
	btn_pause = Button.new()
	btn_pause.focus_mode = Control.FOCUS_NONE
	btn_pause.text = "II"
	_style_button(btn_pause, false, 26)
	btn_pause.add_theme_font_size_override("font_size", 22)
	btn_pause.pressed.connect(func(): pause_pressed.emit())
	add_child(btn_pause)
	_banner = _label("", 54, 800, C_TEXT, 4.0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner)
	_banner_sub = _label("", 18, 700, C_MUTED, 3.0)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner_sub)
	menu_scr = _build_menu()
	pause_scr = _build_pause()
	result_scr = _build_result()
	medals_scr = _build_medals()
	get_viewport().size_changed.connect(_layout)
	_layout()
	show_screen("menu")


func _label(text: String, size: int, weight := 500, color := C_TEXT, spacing := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	var fv := FontVariation.new()
	fv.base_font = fonts[weight]
	fv.spacing_glyph = int(spacing)
	l.add_theme_font_override("font", fv)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _style_button(b: Button, accent: bool, radius := 22) -> void:
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(C_LANCE, 0.9) if accent else Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7)
		if st == "pressed":
			s.bg_color = s.bg_color.lightened(0.15)
		s.border_color = Color(1, 1, 1, 0.18)
		s.set_border_width_all(0 if accent else 1)
		s.set_corner_radius_all(radius)
		s.shadow_color = Color(C_LANCE, 0.35) if accent else Color(0, 0, 0, 0.35)
		s.shadow_size = 16 if accent else 8
		s.content_margin_left = 18
		s.content_margin_right = 18
		s.anti_aliasing = true
		b.add_theme_stylebox_override(st, s)
	var fv := FontVariation.new()
	fv.base_font = fonts[800]
	fv.spacing_glyph = 2
	b.add_theme_font_override("font", fv)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", C_INK if accent else C_TEXT)
	b.add_theme_color_override("font_hover_color", C_INK if accent else C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_INK if accent else C_TEXT)


func _button(text: String, accent: bool, h := 76.0) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(COL_W, h)
	_style_button(b, accent)
	return b


func _screen() -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(5 / 255.0, 4 / 255.0, 26 / 255.0, 0.72)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.add_child(v)
	return v


func _center(c: Control) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(c)
	return h


func _build_menu() -> Control:
	var v := _screen()
	var t := _label("STAR BREAKER", 44, 800, C_TEXT, 6.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	var sl := _label("SHIP", 16, 700, C_MUTED, 3.0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	for k in VShips.ORDER:
		var b := Button.new()
		b.text = String(VShips.KITS[k].name).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 16) / 2.0, 70)
		b.pressed.connect(func(): select_ship(k))
		row.add_child(b)
		_ship_btns[k] = b
	v.add_child(row)
	var how := _label("", 16, 500, C_MUTED)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = COL_W
	how.name = "how"
	v.add_child(_center(how))
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 12
	v.add_child(gap2)
	v.add_child(_build_tier_row())
	_build_map(v)
	_btn_medals = _small_button("")
	_btn_medals.custom_minimum_size.x = COL_W
	_btn_medals.pressed.connect(func(): show_screen("medals"))
	v.add_child(_center(_btn_medals))
	_build_device(v)
	select_ship(ship)
	return v.get_parent()


## World tabs, the world's name, and a grid of its eight stages (2 x 4).
func _build_map(v: VBoxContainer) -> void:
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	var n: int = VStage.WORLDS.size()
	for w in n:
		var b := Button.new()
		b.text = str(w + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 8 * (n - 1)) / n, 56)
		b.pressed.connect(func(): select_world(w))
		tabs.add_child(b)
		_world_btns.append(b)
	v.add_child(tabs)
	_world_lbl = _label("", 18, 700, C_LANCE, 3.0)
	_world_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_world_lbl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	for j in VStage.PER_WORLD:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 12) / 2.0, 74)
		b.pressed.connect(func(): stage_chosen.emit(world_sel * VStage.PER_WORLD + j, ship))
		var pips := Pips.new()
		pips.position = Vector2(b.custom_minimum_size.x - 18 - Pips.WIDTH, b.custom_minimum_size.y - Pips.HEIGHT - 12)
		b.add_child(pips)
		_stage_pips.append(pips)
		grid.add_child(b)
		_stage_btns.append(b)
	v.add_child(_center(grid))
	select_world(0)


## Shows world `w` on the stage map.
func select_world(w: int) -> void:
	world_sel = clampi(w, 0, VStage.WORLDS.size() - 1)
	for k in _world_btns.size():
		_style_button(_world_btns[k], k == world_sel)
	var wd: Dictionary = Worlds.LIST[world_sel]
	_world_lbl.text = ("%s  ·  %s" % [wd.sub, wd.name]).to_upper()
	for j in _stage_btns.size():
		var b: Button = _stage_btns[j]
		b.text = stage_label(world_sel * VStage.PER_WORLD + j)
		_style_button(b, false)
		b.add_theme_font_size_override("font_size", 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	refresh_progress()


## A stage button's text: number and name, and the best score under it.
func stage_label(i: int) -> String:
	var st: Dictionary = VStage.STAGES[i]
	var t: String = "%d  %s" % [st.j + 1, st.name]
	if prog and not prog.unlocked(Progress.stage_id(i), tier):
		t += "\nlocked"
	elif i < bests.size() and int(bests[i]) > 0:
		t += "\n" + _fmt(int(bests[i]))
	else:
		t += "\n "  # keeps the name on the top line, clear of the medal pips
	return t.to_upper()


## The crash notice (after a session that didn't end cleanly) and the device row: sound,
## graphics (safe turns glow and MSAA off) and the build line (tap to restart and update).
func _build_device(v: VBoxContainer) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	v.add_child(gap)
	_crash = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.85)
	sb.border_color = Color(C_AMBER, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(14)
	_crash.add_theme_stylebox_override("panel", sb)
	_crash.custom_minimum_size.x = COL_W
	var cv := VBoxContainer.new()
	_crash.add_child(cv)
	var ct := _label("THE GAME CLOSED UNEXPECTEDLY LAST TIME · SAFE GRAPHICS ARE ON", 13, 700, C_AMBER, 1.0)
	ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ct.custom_minimum_size.x = COL_W - 28
	cv.add_child(ct)
	_crash_txt = _label("", 14, 500, C_MUTED)
	_crash_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_crash_txt.custom_minimum_size.x = COL_W - 28
	cv.add_child(_crash_txt)
	_btn_copy = _small_button("Copy crash report")
	_btn_copy.pressed.connect(func():
		DisplayServer.clipboard_set(_crash_report)
		_btn_copy.text = "COPIED")
	cv.add_child(_btn_copy)
	_crash.hide()
	v.add_child(_center(_crash))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	btn_mute = _small_button("")
	btn_mute.pressed.connect(func(): mute_pressed.emit())
	row.add_child(btn_mute)
	_btn_gfx = _small_button("")
	_btn_gfx.pressed.connect(func():
		Diag.set_safe(not Diag.safe)
		_update_gfx()
		safe_toggled.emit())
	row.add_child(_btn_gfx)
	v.add_child(row)
	_build_id = str(ProjectSettings.get_setting("application/config/version", ""))
	if _build_id == "":
		_build_id = "dev"
	btn_build = _small_button("")
	btn_build.pressed.connect(func(): refresh_pressed.emit())
	v.add_child(_center(btn_build))
	set_muted(false)
	_update_gfx()
	set_build_state("idle")


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b, false, 999)
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size.y = 48
	return b


func set_muted(m: bool) -> void:
	btn_mute.text = "SOUND: OFF" if m else "SOUND: ON"


func _update_gfx() -> void:
	_btn_gfx.text = "GRAPHICS: SAFE" if Diag.safe else "GRAPHICS: FULL"


## What the build line says: "idle" (the build, tap to refresh), "new" (a newer build is
## out, `build` is its number), or "restarting".
func set_build_state(state: String, build := 0) -> void:
	match state:
		"new":
			btn_build.text = "NEW BUILD %d · TAP TO UPDATE" % build
			btn_build.add_theme_color_override("font_color", C_AMBER)
		"restarting":
			btn_build.text = "RESTARTING…"
			btn_build.add_theme_color_override("font_color", C_TEXT)
		_:
			btn_build.text = "BUILD %s  ⟳  REFRESH" % _build_id.to_upper()
			btn_build.add_theme_color_override("font_color", C_MUTED)


func show_crash_notice(summary: String, report: String) -> void:
	_crash_report = report
	_crash_txt.text = summary
	_crash.show()
	_update_gfx()


## Each stage's best score, shown on its button.
func set_bests(b: Array) -> void:
	bests = b.duplicate()
	if _world_lbl != null:
		select_world(world_sel)


## Redraws everything that shows progress: the tier row, the shown world's stage labels, medals
## and locks, the medal count and the ship colours.
func refresh_progress() -> void:
	for t in _tier_btns.size():
		_style_tier(_tier_btns[t], t)
	for j in _stage_btns.size():
		var i: int = world_sel * VStage.PER_WORLD + j
		var b: Button = _stage_btns[j]
		b.text = stage_label(i)
		var id := Progress.stage_id(i)
		var open: bool = prog == null or prog.unlocked(id, tier)
		b.disabled = not open
		b.modulate.a = 1.0 if open else 0.45
		if j < _stage_pips.size():
			_stage_pips[j].set_medals(prog.medals(id, tier) if prog else 0)
			_stage_pips[j].visible = open
	if prog and _btn_medals:
		_btn_medals.text = "MEDALS %d / %d  ·  SHIP COLOURS" % [prog.total(), Progress.max_total()]
		_medals_total.text = "%d / %d" % [prog.total(), Progress.max_total()]
		for k in _paint_btns:
			for sw in _paint_btns[k]:
				_style_swatch(sw, k)


static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func select_ship(k: String) -> void:
	ship = k
	for key in _ship_btns:
		_style_button(_ship_btns[key], key == k)
	_update_how()


func _update_how() -> void:
	var how: Label = menu_scr.find_child("how", true, false) if menu_scr else (find_child("how", true, false) as Label)
	if not how:
		return
	var k := ship
	var t := "%s: %s. Drag to fly, it fires on its own. Double tap: %s." % [VShips.KITS[k].name, VShips.KITS[k].sub, VShips.KITS[k].ult_name]
	t += " Rock hurts; skim it for points."
	how.text = t


func _build_pause() -> Control:
	var v := _screen()
	var t := _label("PAUSED", 48, 800, C_TEXT, 6.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	for d in [["Resume", true, resume_pressed], ["Retry stage", false, retry_pressed], ["Stages", false, menu_pressed]]:
		var b := _button(d[0], d[1])
		var sig: Signal = d[2]
		b.pressed.connect(func(): sig.emit())
		v.add_child(_center(b))
	return v.get_parent()


func _build_result() -> Control:
	var v := _screen()
	_result_title = _label("", 48, 800, C_TEXT, 6.0)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result_title)
	_result_sub = _label("", 22, 700, C_MUTED, 2.0)
	_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_result_sub)
	_result_pips = Pips.new()
	_result_pips.big = true
	_result_pips.custom_minimum_size = Vector2(Pips.WIDTH_BIG, Pips.HEIGHT_BIG)
	v.add_child(_center(_result_pips))
	_result_lines = _label("", 18, 700, C_TEXT, 1.0)
	_result_lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_lines.custom_minimum_size.x = COL_W
	v.add_child(_center(_result_lines))
	_result_tier = _button("", true)
	_result_tier.pressed.connect(func(): tier_pressed.emit(int(_result_tier.get_meta("tier", 0))))
	v.add_child(_center(_result_tier))
	_result_next = _button("Next stage", true)
	_result_next.pressed.connect(func(): next_pressed.emit())
	v.add_child(_center(_result_next))
	for d in [["Retry stage", retry_pressed], ["Stages", menu_pressed]]:
		var b := _button(d[0], false)
		var sig: Signal = d[1]
		b.pressed.connect(func(): sig.emit())
		v.add_child(_center(b))
	return v.get_parent()


## Shows one of "menu", "pause", "result" or "play" (no menu, the HUD only).
func show_screen(which: String) -> void:
	menu_scr.visible = which == "menu"
	medals_scr.visible = which == "medals"
	pause_scr.visible = which == "pause"
	result_scr.visible = which == "result"
	playing = which == "play" or which == "pause"
	btn_pause.visible = which == "play"
	queue_redraw()


func set_result(cleared: bool, score_txt: String, has_next: bool) -> void:
	_result_title.text = "STAGE CLEAR" if cleared else "SHIPS LOST"
	_result_title.add_theme_color_override("font_color", C_LANCE if cleared else C_SPORE)
	_result_sub.text = "SCORE  " + score_txt
	_result_next.visible = cleared and has_next


func banner(t: String, sub: String, frames := 150) -> void:
	_banner.text = t.to_upper()
	_banner_sub.text = sub.to_upper()
	_banner_t = frames
	_banner.visible = true
	_banner_sub.visible = true


func tick_banner() -> void:
	if _banner_t > 0:
		_banner_t -= 1
		if _banner_t == 0:
			_banner.visible = false
			_banner_sub.visible = false


func _layout() -> void:
	var sz := get_viewport_rect().size
	btn_pause.position = Vector2(sz.x - 28 - 64, 28)
	btn_pause.size = Vector2(64, 64)
	ult_rect = Rect2(sz.x - 28 - 92, 108, 92, 92)
	_banner.position = Vector2(0, sz.y * 0.36)
	_banner.size = Vector2(sz.x, 70)
	_banner_sub.position = Vector2(0, sz.y * 0.36 + 74)
	_banner_sub.size = Vector2(sz.x, 30)


## True when `p` (canvas position) is on a HUD control, so a touch there is not a thumb.
func on_control(p: Vector2) -> bool:
	return (btn_pause.visible and btn_pause.get_global_rect().grow(12).has_point(p)) or (playing and ult_rect.grow(12).has_point(p))


func _gui_input(_e: InputEvent) -> void:
	pass


func _draw() -> void:
	if not playing:
		return
	var f: Font = fonts[800]
	var sz := size
	draw_string(f, Vector2(28, 64), score, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, C_TEXT)
	draw_string(fonts[700], Vector2(30, 92), stage_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_MUTED)
	# hull pips, then the ships left
	for i in 3:
		var r := Rect2(30 + i * 30, 108, 24, 12)
		draw_rect(r, Color(C_LANCE, 0.95) if i < hull else Color(1, 1, 1, 0.15))
	draw_string(fonts[700], Vector2(30 + 3 * 30 + 6, 121), "x%d" % ships, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TEXT)
	# ultimate gauge: a ring that fills, glowing when ready
	var c := ult_rect.get_center()
	var rad := ult_rect.size.x / 2.0 - 6
	draw_circle(c, rad + 4, Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7))
	draw_arc(c, rad, 0, TAU, 48, Color(1, 1, 1, 0.14), 8, true)
	var col := C_SPORE if ult_ready else C_VIOLET
	if ult > 0.0:
		draw_arc(c, rad, -PI / 2, -PI / 2 + TAU * clampf(ult, 0, 1), 48, col, 8, true)
	var label := "ULT" if not ult_ready else "GO"
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_string(f, c + Vector2(-lw / 2, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col if ult_ready else C_MUTED)
	# Lance's charge meter under the score: four notches (LV 1-3 and the Nova)
	if ship == "lance" and charge > 0.0:
		var bx := 30.0
		var by := 140.0
		var bw := 200.0
		draw_rect(Rect2(bx, by, bw, 8), Color(1, 1, 1, 0.12))
		var cc: Color = [C_TEXT, C_TEXT, C_LANCE, C_SPORE][maxi(0, charge_lv - 1)] if charge_lv > 0 else Color(1, 1, 1, 0.5)
		draw_rect(Rect2(bx, by, bw * clampf(charge, 0, 1), 8), cc)
		for t in [50 / 240.0, 100 / 240.0, 160 / 240.0]:
			draw_rect(Rect2(bx + bw * t - 1, by - 2, 2, 12), Color(1, 1, 1, 0.6))
	# boss bar along the top
	if boss >= 0.0:
		# right of the score, left of the pause button
		var bw2 := sz.x - 210.0 - 120.0
		var r2 := Rect2(210, 52, bw2, 10)
		draw_rect(r2, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(r2.position, Vector2(bw2 * clampf(boss, 0, 1), 10)), C_SPORE)
		draw_string(fonts[700], Vector2(210, 44), boss_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_SPORE)


# ---------- tiers, medals and ship colours ----------

## Normal, Nova, Supernova: the tier the stage buttons start.
func _build_tier_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	for t in Progress.TIERS.size():
		var b := Button.new()
		b.text = String(Progress.TIERS[t].name).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 20) / 3.0, 56)
		b.pressed.connect(func(): select_tier(t))
		row.add_child(b)
		_tier_btns.append(b)
		_style_tier(b, t)
	return row


func select_tier(t: int) -> void:
	tier = clampi(t, 0, Progress.TIERS.size() - 1)
	refresh_progress()


func _style_tier(b: Button, t: int) -> void:
	var col := Color(String(Progress.TIERS[t].color))
	for st in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(col, 0.9) if t == tier else Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7)
		s.border_color = Color(col, 0.7)
		s.set_border_width_all(0 if t == tier else 2)
		s.set_corner_radius_all(999)
		s.anti_aliasing = true
		b.add_theme_stylebox_override(st, s)
	var fv := FontVariation.new()
	fv.base_font = fonts[800]
	fv.spacing_glyph = 2
	b.add_theme_font_override("font", fv)
	b.add_theme_font_size_override("font_size", 16)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, C_INK if t == tier else col)


## The end of a run: the medals of this tier (new ones ringed), what got unlocked, and a
## button to replay the stage on the next tier once it's open.
func set_report(r: Dictionary) -> void:
	_result_pips.set_medals(int(r.get("held", 0)), r.get("new_medals", []))
	var lines: Array = []
	var tname: String = Progress.tier(int(r.get("tier", 0))).name
	if r.get("cleared", false):
		lines.append("%s · %d of 4 medals" % [tname, Progress.bits(int(r.get("held", 0)))])
	else:
		lines.append("Clear the stage to earn medals")
	if int(r.get("unlocked_tier", -1)) > 0:
		lines.append("%s unlocked for this stage" % Progress.tier(r.unlocked_tier).name)
	for rw in r.get("rewards", []):
		lines.append("New ship colour: %s" % Progress.reward_name(rw))
	_result_lines.text = "\n".join(lines).to_upper()
	var nt := int(r.get("tier", 0)) + 1
	var show_tier: bool = r.get("cleared", false) and nt < Progress.TIERS.size()
	_result_tier.visible = show_tier
	if show_tier:
		_result_tier.text = ("Replay on " + String(Progress.TIERS[nt].name)).to_upper()
		_result_tier.set_meta("tier", nt)
		_style_button(_result_tier, true)
		var col := Color(String(Progress.TIERS[nt].color))
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = _result_tier.get_theme_stylebox(st)
			sb.bg_color = col if st != "pressed" else col.lightened(0.15)
			sb.shadow_color = Color(col, 0.35)


## The medals screen: the four medals explained, the total, and each ship's colours (locked
## ones say how many medals they need).
func _build_medals() -> Control:
	var v := _screen()
	var t := _label("MEDALS", 44, 800, C_TEXT, 6.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_medals_total = _label("", 22, 700, C_AMBER, 2.0)
	_medals_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_medals_total)
	var legend := VBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	for k in Progress.MEDALS.size():
		var info: Dictionary = Progress.MEDAL_INFO[Progress.MEDALS[k]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var p := Pips.new()
		p.only = k
		p.custom_minimum_size = Vector2(22, Pips.HEIGHT)
		p.set_medals(1 << k)
		row.add_child(p)
		var l := _label("%s  ·  %s" % [String(info.name).to_upper(), info.how], 17, 700, C_TEXT)
		row.add_child(l)
		legend.add_child(row)
	var note := _label("Each stage has 4 medals on each tier. Clear a tier to open the next.", 15, 500, C_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = COL_W
	legend.add_child(note)
	v.add_child(_center(legend))
	for k in VShips.ORDER:
		var sl := _label(String(VShips.KITS[k].name).to_upper() + " COLOURS", 16, 700, C_MUTED, 3.0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		_paint_btns[k] = []
		for s in Progress.SCHEMES[k]:
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(92, 92)
			b.set_meta("scheme", s.id)
			var sid: String = s.id
			b.pressed.connect(func(): paint_chosen.emit(k, sid))
			row.add_child(b)
			_paint_btns[k].append(b)
		v.add_child(row)
	var back := _button("Back", false)
	back.pressed.connect(func(): show_screen("menu"))
	v.add_child(_center(back))
	return v.get_parent()


## A colour swatch: hull colour with a dark trim ring and a glow dot; ringed when chosen, dimmed
## with the medals it needs when locked.
func _style_swatch(b: Button, k: String) -> void:
	var id: String = b.get_meta("scheme")
	var s := Progress.scheme(k, id)
	var open: bool = prog == null or prog.scheme_open(k, id)
	var chosen: bool = prog != null and prog.paint_of(k).id == id
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(s.hull) if open else Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7)
		sb.border_color = Color(s.glow) if chosen else (Color(s.dark) if open else Color(1, 1, 1, 0.18))
		sb.set_border_width_all(6 if chosen else 3)
		sb.set_corner_radius_all(20)
		sb.shadow_color = Color(Color(s.glow), 0.5) if chosen else Color(0, 0, 0, 0)
		sb.shadow_size = 12 if chosen else 0
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st, sb)
	b.disabled = not open
	b.text = "" if open else str(Progress.scheme_at(k, id))
	b.tooltip_text = s.name
	var fv := FontVariation.new()
	fv.base_font = fonts[800]
	b.add_theme_font_override("font", fv)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_disabled_color", C_MUTED)
	b.add_theme_color_override("font_color", C_INK)


## Four medal pips in a row (Sweep, Untouched, Breaker, Swift): filled in the medal's colour
## when held, an empty ring when not. The big version names each medal and rings the new ones.
class Pips:
	extends Control
	const WIDTH := 4 * 22.0
	const HEIGHT := 22.0
	const WIDTH_BIG := 4 * 120.0
	const HEIGHT_BIG := 70.0
	var held := 0
	var fresh: Array = []
	var big := false
	## Draw one medal only (index), or all four (-1).
	var only := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(WIDTH, HEIGHT)
		size = custom_minimum_size

	func set_medals(m: int, new_ones: Array = []) -> void:
		held = m
		fresh = new_ones
		queue_redraw()

	func _draw() -> void:
		var font: Font = ThemeDB.fallback_font
		var hud := get_parent()
		while hud and not hud is VHud:
			hud = hud.get_parent()
		if hud:
			font = hud.fonts[700]
		if not big and only < 0:
			# a dark pill behind the row so the pips read on a bright (accent) button too
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(11 / 255.0, 8 / 255.0, 48 / 255.0, 0.75)
			sb.set_corner_radius_all(999)
			draw_style_box(sb, Rect2(-4, -2, WIDTH + 8, HEIGHT + 4))
		for k in Progress.MEDALS.size():
			if only >= 0 and k != only:
				continue
			var key: String = Progress.MEDALS[k]
			var col := Color(String(Progress.MEDAL_INFO[key].color))
			var has := held & (1 << k) != 0
			var c: Vector2
			var r: float
			if big:
				c = Vector2(60 + k * 120, 20)
				r = 15.0
			else:
				c = Vector2(11 + (0 if only >= 0 else k * 22), 11)
				r = 7.0
			if has:
				draw_circle(c, r, col)
				draw_circle(c, r * 0.45, Color(1, 1, 1, 0.55))
			else:
				draw_arc(c, r - 1.0, 0, TAU, 24, Color(col, 0.45), 2.0, true)
			if big:
				if fresh.has(key):
					draw_arc(c, r + 6, 0, TAU, 32, Color(col, 0.9), 2.5, true)
				var name: String = String(Progress.MEDAL_INFO[key].name).to_upper()
				var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(font, Vector2(c.x - w / 2, 62), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col if has else Color(1, 1, 1, 0.4))
