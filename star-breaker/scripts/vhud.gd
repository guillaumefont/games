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
signal exit_pressed
signal pause_pressed
signal ult_pressed

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

var menu_scr: Control
var pause_scr: Control
var result_scr: Control
var _ship_btns := {}
## Edge mode (rock walls, Lance's guns quiet while charging) or the softer first preview.
var edge := true
var _edge_btns := {}
var _result_title: Label
var _result_sub: Label
var _result_next: Button
var _banner: Label
var _banner_sub: Label
var _banner_t := 0
var btn_pause: Button
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
	var s := _label("VERTICAL PREVIEW", 18, 700, C_LANCE, 4.0)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
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
	var fl := _label("FEEL", 16, 700, C_MUTED, 3.0)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(fl)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 16)
	for on in [true, false]:
		var b := Button.new()
		b.text = "EDGE" if on else "SOFT"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 16) / 2.0, 60)
		b.pressed.connect(func(): select_edge(on))
		row2.add_child(b)
		_edge_btns[on] = b
	v.add_child(row2)
	var how := _label("", 16, 500, C_MUTED)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = COL_W
	how.name = "how"
	v.add_child(_center(how))
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 12
	v.add_child(gap2)
	for i in VStage.STAGES.size():
		var st: Dictionary = VStage.STAGES[i]
		var b := _button("%d  %s" % [i + 1, st.name], i == 0)
		b.pressed.connect(func(): stage_chosen.emit(i, ship))
		v.add_child(_center(b))
	var ex := _button("Back to the main game", false, 60)
	ex.add_theme_font_size_override("font_size", 18)
	ex.pressed.connect(func(): exit_pressed.emit())
	v.add_child(_center(ex))
	select_ship(ship)
	select_edge(edge)
	return v.get_parent()


func select_ship(k: String) -> void:
	ship = k
	for key in _ship_btns:
		_style_button(_ship_btns[key], key == k)
	_update_how()


func select_edge(on: bool) -> void:
	edge = on
	for key in _edge_btns:
		_style_button(_edge_btns[key], key == on)
	_update_how()


func _update_how() -> void:
	var how: Label = menu_scr.find_child("how", true, false) if menu_scr else (find_child("how", true, false) as Label)
	if not how:
		return
	var k := ship
	var t := "%s: %s. Drag to fly, it fires on its own. Second finger: %s." % [VShips.KITS[k].name, VShips.KITS[k].sub, VShips.KITS[k].ult_name]
	if edge:
		t += " Rock walls hurt; skim them for points."
		if k == "lance":
			t += " Charging silences your guns."
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
