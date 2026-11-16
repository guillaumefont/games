class_name Hud
extends CanvasLayer
## Score, best, sound toggle, hint line, and the start, game over and pause cards.
## Built in code, styled after the web prototype (Unbounded for numbers and titles, Manrope for
## text, pastel on deep indigo).

signal sound_toggled

const INK := Color("f3ecdf")
const MUTED := Color("9aa0cf")
const CORAL := Color("ff8a6b")
const SAND := Color("f2c879")
const TEAL := Color("6fd6c5")
const SPACE := Color("141634")

var display_800: Font
var display_500: Font
var body_500: Font
var body_700: Font

var root: Control
var top: MarginContainer
var score_label: Label
var best_label: Label
var sound_button: Button
var hint_label: Label
var start_card: Control
var over_card: Control
var over_why: Label
var over_score: Label
var over_best: Label
var pause_card: Control
var pause_title: Label
var pause_sub: Label
var _pills: Array[Control] = []
var _t := 0.0


func _ready() -> void:
	layer = 10
	display_800 = _font("res://fonts/unbounded-latin-800-normal.woff2")
	display_500 = _font("res://fonts/unbounded-latin-500-normal.woff2")
	body_500 = _font("res://fonts/manrope-latin-500-normal.woff2")
	body_700 = _font("res://fonts/manrope-latin-700-normal.woff2")

	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# top bar: score and best on the left, sound on the right
	top = MarginContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(bar)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(left)
	score_label = _label("0", display_800, 40, INK)
	left.add_child(score_label)
	best_label = _label("Best 0", _spaced(body_700, 1.5), 12, MUTED)
	best_label.uppercase = true
	left.add_child(best_label)
	sound_button = Button.new()
	sound_button.focus_mode = Control.FOCUS_NONE
	sound_button.custom_minimum_size = Vector2(0, 36)
	sound_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sound_button.add_theme_font_override("font", _spaced(body_700, 1.2))
	sound_button.add_theme_font_size_override("font_size", 12)
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.06 if s == "pressed" else 0.0)
		sb.border_color = Color(INK, 0.25)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(18)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.anti_aliasing = true
		sound_button.add_theme_stylebox_override(s, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		sound_button.add_theme_color_override(c, INK)
	sound_button.pressed.connect(func() -> void: sound_toggled.emit())
	bar.add_child(sound_button)
	set_sound(false)

	hint_label = _label("", body_700, 15, SAND)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

	start_card = _overlay()
	var title := HBoxContainer.new()
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	title.add_theme_constant_override("separation", 0)
	title.add_child(_label("Peri", display_800, 56, INK))
	title.add_child(_label("gee", display_800, 56, CORAL))
	_card(start_card).add_child(title)
	var sub := _label("Hop from moon to moon. Don't drift into the dark.", body_500, 15, MUTED)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size.x = 300
	_card(start_card).add_child(sub)
	var steps := GridContainer.new()
	steps.columns = 2
	steps.add_theme_constant_override("h_separation", 12)
	steps.add_theme_constant_override("v_separation", 8)
	for row in [["Release", "to fling off along your orbit."],
			["Hold", "while you cross a dotted ring to get caught."],
			["Sparks", "between moons are worth a bonus point."]]:
		var k := _label(row[0], _spaced(display_500, 1.0), 12, SAND)
		k.uppercase = true
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		steps.add_child(k)
		var v := _label(row[1], body_500, 15, INK)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size.x = 210
		steps.add_child(v)
	_card(start_card).add_child(steps)
	_card(start_card).add_child(_pill("Tap to start"))

	over_card = _overlay()
	over_card.visible = false
	over_why = _label("Lost in the dark", _spaced(body_700, 1.7), 12, MUTED)
	over_why.uppercase = true
	over_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(over_card).add_child(over_why)
	over_score = _label("0", display_800, 72, INK)
	over_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(over_card).add_child(over_score)
	over_best = _label("Best 0", _spaced(body_700, 1.7), 12, MUTED)
	over_best.uppercase = true
	over_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(over_card).add_child(over_best)
	_card(over_card).add_child(_pill("Tap to fly again"))

	pause_card = _overlay()
	pause_card.visible = false
	pause_title = _label("Paused", display_800, 56, INK)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(pause_card).add_child(pause_title)
	pause_sub = _label("Tap to resume", body_700, 15, SAND)
	pause_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(pause_card).add_child(pause_sub)

	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()


func _process(delta: float) -> void:
	_t += delta
	# the "tap" pills breathe like the prototype's CSS pulse (1.6 s)
	var s := 1.0 + 0.025 * (1.0 - cos(_t * TAU / 1.6))
	for p in _pills:
		p.pivot_offset = p.size / 2.0
		p.scale = Vector2(s, s)


## Keeps the HUD clear of notches and rounded corners.
func apply_safe_area() -> void:
	var vp := get_viewport().get_visible_rect().size
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(Vector2.ZERO, win)
	if OS.has_feature("mobile"):
		safe = Rect2(DisplayServer.get_display_safe_area())
	var k := vp.x / win.x if win.x > 0 else 1.0
	var top_inset := safe.position.y * k
	var bottom_inset := maxf(0.0, (win.y - safe.end.y) * k)
	var left_inset := safe.position.x * k
	var right_inset := maxf(0.0, (win.x - safe.end.x) * k)
	top.add_theme_constant_override("margin_top", int(10 + top_inset))
	top.add_theme_constant_override("margin_left", int(maxf(16, left_inset)))
	top.add_theme_constant_override("margin_right", int(maxf(16, right_inset)))
	hint_label.offset_top = -(28 + bottom_inset + 22)
	hint_label.offset_bottom = -(28 + bottom_inset)


func set_score(v: int) -> void:
	score_label.text = str(v)


func set_best(v: int) -> void:
	best_label.text = "Best %d" % v


func set_sound(on: bool) -> void:
	sound_button.text = "SOUND ON" if on else "SOUND OFF"


func set_hint(text: String) -> void:
	if hint_label.text != text:
		hint_label.text = text


func show_start(on: bool) -> void:
	start_card.visible = on


func show_over(score: int, why: String, best: int, new_best: bool) -> void:
	over_score.text = str(score)
	over_why.text = why
	if new_best and score > 0:
		over_best.text = "New best"
		over_best.add_theme_color_override("font_color", TEAL)
	else:
		over_best.text = "Best %d" % best
		over_best.add_theme_color_override("font_color", MUTED)
	over_card.visible = true


func hide_over() -> void:
	over_card.visible = false


## Pause card: "Paused / Tap to resume", or a countdown number while resuming.
func show_pause(on: bool, countdown := 0) -> void:
	pause_card.visible = on
	if countdown > 0:
		pause_title.text = str(countdown)
		pause_sub.text = "Get ready"
	else:
		pause_title.text = "Paused"
		pause_sub.text = "Tap to resume"


# ---------- building blocks ----------

func _font(path: String) -> Font:
	var f: Font = load(path)
	return f if f != null else ThemeDB.fallback_font


func _spaced(base: Font, spacing: float) -> Font:
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = int(spacing)
	return fv


func _label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _overlay() -> Control:
	var dim := ColorRect.new()
	dim.color = Color(SPACE, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.name = "Card"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)
	return dim


func _card(overlay: Control) -> VBoxContainer:
	return overlay.get_child(0).get_child(0)


func _pill(text: String) -> Control:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = SAND
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var l := _label(text, _spaced(display_500, 1.8), 13, SPACE)
	l.uppercase = true
	p.add_child(l)
	wrap.add_child(p)
	_pills.append(p)
	return wrap
