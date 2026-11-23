class_name Hud
extends CanvasLayer
## The interface: glass HUD (hull, coins, coffre, maps, balls), speed gauge, the joystick
## that appears under the thumb, the green aim stick in a fight, edge arrows, enemy labels, toasts, the attack prompt and the
## parchment port with its 3D shipyard preview. Built in code.

const INK := Color8(0x2e, 0x1f, 0x15)
const PARCH := Color8(0xf1, 0xe6, 0xcd)
const WOOD := Color8(0x4b, 0x33, 0x22)
const WAX := Color8(0x9b, 0x3a, 0x22)
const RUST := Color8(0xb4, 0x53, 0x2f)
const GOLD := Color8(0xe0, 0xb4, 0x5a)
const FOAM := Color8(0xf3, 0xf6, 0xf3)
const GLASS := Color(22 / 255.0, 34 / 255.0, 38 / 255.0, 0.42)
const JOY_R := 90.0
const AIM_R := 80.0
## Below this reach the green stick does nothing (let go there to cancel a shot).
const AIM_DEAD := 0.2
const AIM_GREEN := Color8(0x5f, 0xd0, 0x6a)
const NO_ID := -99
const MOUSE_ID := -10

var game: Game
var root: Control
var joy_active := false
var joy_origin := Vector2.ZERO
var joy_vec := Vector2.ZERO
var joy_mag := 0.0
## The green aim stick: direction and reach (0..1); releasing it fires.
var aim_active := false
var aim_vec := Vector2.ZERO
var aim_mag := 0.0
var aim_shown := false
var _joy_id := NO_ID
var _aim_id := NO_ID
var _aim: Aim

var f_body: Font
var f_bold: Font
var f_title: Font
var f_italic: Font
var f_caps: Font

var _touch: Control
var _joy: Control
var _ship_name: Label
var _hp_num: Label
var _hull_bar: Bar
var _vals := {}
var _hud_panel: PanelContainer
var _gauge: Gauge
var _edges := {}
var _toasts: VBoxContainer
var _prompt: PanelContainer
var _prompt_title: Label
var _prompt_text: Label
var _actions: HFlowContainer
var _actions_key := ""
var _labels := []
var _hint: Label
var _flash := 0.0
var _port: Control
var _tab := "coffre"
var _tabs := {}
var _money := {}
var _body: VBoxContainer
var _scroll: ScrollContainer
var _pv_idx := 0
var _pv_vp: SubViewport
var _pv_cam: Camera3D
var _pv_ship: Node3D
var _pv_key := ""
var _pv_ang := 0.6
var _confirm_reset := false


# ---------------------------------------------------------------- little drawn pieces

## A 16 x 16 icon drawn in code: coin, chest, map or ball.
class Icon:
	extends Control
	var kind := "coin"

	func _init(k: String, sz := 30.0) -> void:
		kind = k
		custom_minimum_size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := size.x / 16.0
		draw_set_transform(Vector2.ZERO, 0, Vector2(k, k))
		match kind:
			"coin":
				draw_circle(Vector2(8, 8), 7, Color8(0xd8, 0xb2, 0x5a))
				draw_arc(Vector2(8, 8), 4.3, 0, TAU, 20, Color8(0xa7, 0x80, 0x2f), 1.3, true)
			"chest":
				draw_rect(Rect2(1.5, 6.5, 13, 8), Color8(0x9a, 0x6a, 0x3a))
				draw_colored_polygon(PackedVector2Array([Vector2(1.5, 6.5), Vector2(4, 3.6), Vector2(8, 2.6), Vector2(12, 3.6), Vector2(14.5, 6.5)]), Color8(0xb7, 0x83, 0x4a))
				draw_rect(Rect2(7, 7.5, 2, 3), Color8(0xe2, 0xc1, 0x72))
			"map":
				draw_colored_polygon(PackedVector2Array([Vector2(1.5, 3.5), Vector2(5.5, 2), Vector2(10.5, 3.5), Vector2(14.5, 2), Vector2(14.5, 12.5), Vector2(10.5, 14), Vector2(5.5, 12.5), Vector2(1.5, 14)]), Color8(0xe6, 0xdc, 0xc2))
				draw_line(Vector2(8.5, 6), Vector2(11.5, 9), RUST, 1.4)
				draw_line(Vector2(11.5, 6), Vector2(8.5, 9), RUST, 1.4)
			"ball":
				draw_circle(Vector2(8, 8.5), 6, Color8(0x2b, 0x31, 0x34))
				draw_circle(Vector2(6, 6.5), 1.6, Color8(0x6d, 0x77, 0x7b))


class Bar:
	extends Control
	var ratio := 1.0
	var bg := Color(1, 1, 1, 0.18)

	func _init(h := 8.0) -> void:
		custom_minimum_size = Vector2(0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := size.y / 2
		_round(Rect2(Vector2.ZERO, size), bg, r)
		if ratio > 0:
			var low := ratio < 0.35
			_round(Rect2(0, 0, maxf(size.y, size.x * ratio), size.y), Color8(0xe5, 0x8a, 0x6a) if low else Color8(0xee, 0xf3, 0xee), r)

	func _round(rc: Rect2, c: Color, r: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		draw_style_box(sb, rc)


## Pips for an upgrade level: filled up to `lvl` of `cap`.
class Pips:
	extends Control
	var lvl := 0
	var cap := 1

	func _init(l: int, c: int) -> void:
		lvl = l
		cap = c
		custom_minimum_size = Vector2(c * 22, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in cap:
			var c := Vector2(11 + i * 22, 11)
			var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
			if i < lvl:
				draw_colored_polygon(pts, Color8(0xb4, 0x53, 0x2f))
			pts.append(pts[0])
			draw_polyline(pts, Color(0.18, 0.12, 0.08, 0.7), 1.6, true)


## The round speed gauge: the arc is the speed, the gold dot the sail (throttle).
class Gauge:
	extends Control
	var speed := 0.0
	var max_speed := 6.0
	var throttle := 0.0
	var font: Font

	func _draw() -> void:
		var c := size / 2
		var r := size.x * 0.36
		draw_circle(c, size.x * 0.41, Color(22 / 255.0, 34 / 255.0, 38 / 255.0, 0.42))
		var a0 := deg_to_rad(135)
		draw_arc(c, r, a0, a0 + deg_to_rad(270), 40, Color(1, 1, 1, 0.22), 7, true)
		var k := clampf(speed / max_speed, 0, 1)
		if k > 0.01:
			draw_arc(c, r, a0, a0 + deg_to_rad(270) * k, 40, Color8(0xee, 0xf3, 0xee), 7, true)
		var at := a0 + deg_to_rad(270) * throttle
		draw_circle(c + Vector2(cos(at), sin(at)) * r, 6, Color8(0xe0, 0xb4, 0x5a))
		var txt := ("%.1f" % speed).replace(".", ",")
		draw_string(font, Vector2(0, c.y + 8), txt, HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color8(0xf3, 0xf6, 0xf3))
		draw_string(font, Vector2(0, c.y + 34), "nœuds", HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, Color(0.93, 0.95, 0.94, 0.75))


## An arrow at the screen's edge pointing at something off screen, with its name.
class Edge:
	extends Control
	var color := Color.WHITE
	var angle := 0.0
	var label: Label

	func _init(c: Color, f: Font) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(0, 0)
		label = Label.new()
		label.add_theme_font_override("font", f)
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color8(0xf3, 0xf6, 0xf3))
		label.add_theme_color_override("font_shadow_color", Color(0.08, 0.13, 0.15, 0.7))
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(240, 26)
		label.position = Vector2(-120, 30)
		add_child(label)

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 25, Color(22 / 255.0, 34 / 255.0, 38 / 255.0, 0.5))
		draw_arc(Vector2.ZERO, 25, 0, TAU, 32, Color(color, 0.8), 2, true)
		var pts := PackedVector2Array([Vector2(0, -12), Vector2(10, 11), Vector2(0, 5), Vector2(-10, 11)])
		var rot := Transform2D(angle, Vector2.ZERO)
		for i in pts.size():
			pts[i] = rot * pts[i]
		draw_colored_polygon(pts, color)


class Joy:
	extends Control
	var knob := Vector2.ZERO

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 90, Color(22 / 255.0, 34 / 255.0, 38 / 255.0, 0.22))
		draw_arc(Vector2.ZERO, 90, 0, TAU, 48, Color(0.95, 0.97, 0.95, 0.45), 3, true)
		draw_circle(knob, 36, Color(0.95, 0.97, 0.95, 0.75))


## The green aim stick, bottom right while fighting: drag toward where the balls should land.
class Aim:
	extends Control
	var knob := Vector2.ZERO
	var held := false

	func _draw() -> void:
		var g := Hud.AIM_GREEN
		draw_circle(Vector2.ZERO, Hud.AIM_R, Color(g.darkened(0.55), 0.38))
		draw_arc(Vector2.ZERO, Hud.AIM_R, 0, TAU, 48, Color(g, 0.9), 4, true)
		draw_arc(Vector2.ZERO, Hud.AIM_R * Hud.AIM_DEAD, 0, TAU, 24, Color(g, 0.45), 2, true)
		var kc := knob
		draw_circle(kc, 34, Color(g, 0.95 if held else 0.8))
		# a little crosshair on the knob
		var w := Color(0.06, 0.16, 0.08, 0.85)
		draw_arc(kc, 13, 0, TAU, 24, w, 3, true)
		draw_line(kc + Vector2(-21, 0), kc + Vector2(-7, 0), w, 3, true)
		draw_line(kc + Vector2(7, 0), kc + Vector2(21, 0), w, 3, true)
		draw_line(kc + Vector2(0, -21), kc + Vector2(0, -7), w, 3, true)
		draw_line(kc + Vector2(0, 7), kc + Vector2(0, 21), w, 3, true)


# ---------------------------------------------------------------- set-up

func _ready() -> void:
	layer = 1
	f_body = _font("Inter-Variable.ttf", 450)
	f_bold = _font("Inter-Variable.ttf", 650)
	f_title = load("res://fonts/IMFellEnglish-Regular.ttf")
	f_italic = load("res://fonts/IMFellEnglish-Italic.ttf")
	f_caps = load("res://fonts/IMFellEnglishSC-Regular.ttf")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _glass_theme()
	add_child(root)
	_build_touch()
	_build_hud()
	_build_prompt()
	_build_port()


func _font(file: String, weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/" + file)
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


func _sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0, pad := Vector4(18, 10, 18, 10)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = pad.x
	sb.content_margin_top = pad.y
	sb.content_margin_right = pad.z
	sb.content_margin_bottom = pad.w
	sb.anti_aliasing = true
	return sb


func _glass_theme() -> Theme:
	var t := Theme.new()
	t.default_font = f_body
	t.default_font_size = 24
	t.set_color("font_color", "Label", FOAM)
	var normal := _sb(GLASS, 30, Color(0.95, 0.97, 0.95, 0.25), 1, Vector4(26, 14, 26, 14))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", normal)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "Button", _sb(Color(GLASS, 0.6), 30, Color(0.95, 0.97, 0.95, 0.4), 1, Vector4(26, 14, 26, 14)))
	t.set_stylebox("disabled", "Button", _sb(Color(GLASS, 0.25), 30, Color(0.95, 0.97, 0.95, 0.12), 1, Vector4(26, 14, 26, 14)))
	t.set_font("font", "Button", f_bold)
	t.set_font_size("font_size", "Button", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", FOAM)
	t.set_color("font_disabled_color", "Button", Color(FOAM, 0.45))
	# the primary (rust) button
	t.set_type_variation("Primary", "Button")
	var p := _sb(RUST, 30, Color(1, 1, 1, 0.2), 1, Vector4(26, 14, 26, 14))
	t.set_stylebox("normal", "Primary", p)
	t.set_stylebox("hover", "Primary", p)
	t.set_stylebox("pressed", "Primary", _sb(RUST.darkened(0.2), 30, Color(1, 1, 1, 0.2), 1, Vector4(26, 14, 26, 14)))
	t.set_stylebox("disabled", "Primary", _sb(Color(RUST, 0.35), 30, Color(1, 1, 1, 0.1), 1, Vector4(26, 14, 26, 14)))
	t.set_stylebox("panel", "PanelContainer", _sb(GLASS, 26, Color(0.95, 0.97, 0.95, 0.16), 1, Vector4(20, 16, 20, 16)))
	return t


## The sea under the HUD takes the thumb: wherever it lands, the joystick appears.
func _build_touch() -> void:
	_touch = Control.new()
	_touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch.gui_input.connect(_on_touch)
	root.add_child(_touch)
	_joy = Joy.new()
	_joy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy.visible = false
	root.add_child(_joy)
	_aim = Aim.new()
	_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim.visible = false
	root.add_child(_aim)


## Each finger is followed by its index, so one thumb can steer while the other aims. A real
## mouse counts as one more finger; the mouse events Godot makes up from touches are skipped.
func _on_touch(ev: InputEvent) -> void:
	if ev is InputEventMouse and ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if ev is InputEventScreenTouch:
		_press(ev.index, ev.position, ev.pressed)
	elif ev is InputEventScreenDrag:
		_drag(ev.index, ev.position)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_press(MOUSE_ID, ev.position, ev.pressed)
	elif ev is InputEventMouseMotion:
		_drag(MOUSE_ID, ev.position)


func aim_center() -> Vector2:
	var sz := root.size
	return Vector2(sz.x - 130, sz.y - 250)


func _press(id: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if aim_shown and _aim_id == NO_ID and pos.distance_to(aim_center()) < AIM_R * 1.3:
			_aim_id = id
			aim_active = true
			aim_vec = Vector2.ZERO
			aim_mag = 0
			_aim.held = true
			_aim.knob = Vector2.ZERO
			_aim.queue_redraw()
			_drag(id, pos)
		elif _joy_id == NO_ID:
			_joy_id = id
			joy_active = true
			joy_origin = pos
			joy_vec = Vector2.ZERO
			joy_mag = 0
			_joy.position = pos
			_joy.knob = Vector2.ZERO
			_joy.visible = true
			_joy.queue_redraw()
		if _hint:
			_hint.visible = false
	elif id == _aim_id:
		_aim_end(true)
	elif id == _joy_id:
		_joy_end()


func _drag(id: int, pos: Vector2) -> void:
	if id == _aim_id:
		var d := pos - aim_center()
		var l := d.length()
		if l > AIM_R:
			d = d / l * AIM_R
		aim_vec = d / AIM_R
		aim_mag = minf(1.0, l / AIM_R)
		_aim.knob = d
		_aim.queue_redraw()
	elif id == _joy_id:
		var d := pos - joy_origin
		var l := d.length()
		if l > JOY_R:
			d = d / l * JOY_R
		joy_vec = d / JOY_R
		joy_mag = minf(1.0, l / JOY_R)
		_joy.knob = d
		_joy.queue_redraw()


func _joy_end() -> void:
	_joy_id = NO_ID
	joy_active = false
	joy_mag = 0
	_joy.visible = false


## Letting go of the green stick fires where it points, unless it is back in the middle.
func _aim_end(fire: bool) -> void:
	var shoot := fire and aim_active and aim_mag > AIM_DEAD
	if shoot:
		game.fire_aimed()
	_aim_id = NO_ID
	aim_active = false
	aim_mag = 0
	aim_vec = Vector2.ZERO
	_aim.held = false
	_aim.knob = Vector2.ZERO
	_aim.queue_redraw()


## Drops both sticks without firing (the player left the game).
func cancel_sticks() -> void:
	_joy_end()
	_aim_end(false)


func _label(text: String, size: int, font: Font = null, col := FOAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	# top left: the ship, its hull, and what it carries
	_hud_panel = PanelContainer.new()
	_hud_panel.position = Vector2(20, 24)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hud_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_hud_panel.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	_ship_name = _label("Chaloupe", 30, f_title)
	_ship_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ship_name)
	_hp_num = _label("100 / 100", 20, f_bold, Color(FOAM, 0.85))
	_hp_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_hp_num)
	_hull_bar = Bar.new(9)
	_hull_bar.custom_minimum_size.x = 330
	v.add_child(_hull_bar)
	var res := HBoxContainer.new()
	res.add_theme_constant_override("separation", 16)
	v.add_child(res)
	for k in ["coin", "chest", "map", "ball"]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(Icon.new(k, 26))
		var l := _label("0", 22, f_bold, FOAM if k != "chest" else Color(FOAM, 0.7))
		h.add_child(l)
		res.add_child(h)
		_vals[k] = l
	# top right: speed
	_gauge = Gauge.new()
	_gauge.font = f_bold
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_gauge.offset_left = -170
	_gauge.offset_right = -14
	_gauge.offset_top = 14
	_gauge.offset_bottom = 170
	root.add_child(_gauge)
	for k in [["base", FOAM, "Port"], ["tre", GOLD, "Trésor"], ["foe", Color8(0xe5, 0x8a, 0x6a), "Ennemi"]]:
		var e := Edge.new(k[1], f_bold)
		e.visible = false
		root.add_child(e)
		_edges[k[0]] = e
	# toasts, under the HUD
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 210
	_toasts.offset_left = -310
	_toasts.offset_right = 310
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 10)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)
	# context buttons at the bottom
	_actions = HFlowContainer.new()
	_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_actions.offset_left = 20
	_actions.offset_right = -20
	_actions.offset_top = -170
	_actions.offset_bottom = -40
	_actions.alignment = FlowContainer.ALIGNMENT_CENTER
	_actions.last_wrap_alignment = FlowContainer.LAST_WRAP_ALIGNMENT_CENTER
	_actions.add_theme_constant_override("h_separation", 12)
	_actions.add_theme_constant_override("v_separation", 12)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_actions)
	_hint = _label("Posez le pouce et glissez : la direction donne le cap, la distance donne la vitesse. En combat, visez avec le joystick vert et lâchez pour tirer.", 21, f_body, Color(FOAM, 0.92))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 60
	_hint.offset_right = -60
	_hint.offset_top = -300
	_hint.offset_bottom = -190
	_hint.add_theme_color_override("font_shadow_color", Color(0.08, 0.13, 0.15, 0.55))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_hint)
	get_tree().create_timer(14.0).timeout.connect(func(): if is_instance_valid(_hint): _hint.visible = false)


func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -40
	_prompt.offset_bottom = 200
	_prompt.add_theme_stylebox_override("panel", _sb(Color(GLASS, 0.72), 28, Color8(0xe5, 0x8a, 0x6a, 0xb0), 2, Vector4(30, 24, 30, 24)))
	_prompt.visible = false
	root.add_child(_prompt)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_prompt.add_child(v)
	_prompt_title = _label("Attaque !", 36, f_title)
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_prompt_title)
	_prompt_text = _label("", 21, f_body, Color(FOAM, 0.88))
	_prompt_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_prompt_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var a := Button.new()
	a.text = "Riposter"
	a.theme_type_variation = "Primary"
	a.pressed.connect(func(): game.on_fight())
	h.add_child(a)
	var b := Button.new()
	b.text = "Fuir"
	b.pressed.connect(func(): game.on_flee())
	h.add_child(b)


# ---------------------------------------------------------------- per frame

func flash() -> void:
	_flash = 0.3


func toast(msg: String, kind := "") -> void:
	var p := PanelContainer.new()
	var border := Color(0.95, 0.97, 0.95, 0.16)
	var bg := Color(GLASS, 0.62)
	if kind == "gold":
		border = Color(GOLD, 0.8)
	elif kind == "bad":
		border = Color8(0xe5, 0x8a, 0x6a, 0xcc)
		bg = Color(0.25, 0.12, 0.09, 0.62)
	p.add_theme_stylebox_override("panel", _sb(bg, 22, border, 2 if kind else 1, Vector4(22, 12, 22, 12)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := _label(msg, 21, f_body, GOLD.lightened(0.3) if kind == "gold" else FOAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = minf(560, 18 * msg.length())
	p.add_child(l)
	_toasts.add_child(p)
	_toasts.move_child(p, 0)
	while _toasts.get_child_count() > 3:
		var last := _toasts.get_child(_toasts.get_child_count() - 1)
		_toasts.remove_child(last)
		last.queue_free()
	get_tree().create_timer(3.6).timeout.connect(func(): if is_instance_valid(p): p.queue_free())


func show_prompt(title: String, text: String) -> void:
	_prompt_title.text = title
	_prompt_text.text = text
	_prompt.visible = true


func hide_prompt() -> void:
	_prompt.visible = false


func prompt_visible() -> bool:
	return _prompt.visible


func set_actions(list: Array) -> void:
	var key := ""
	for a in list:
		key += "%s%s|" % [a.label, a.get("disabled", false)]
	if key == _actions_key:
		return
	_actions_key = key
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for a in list:
		var b := Button.new()
		b.text = a.label
		b.disabled = a.get("disabled", false)
		if a.get("primary", false):
			b.theme_type_variation = "Primary"
		b.pressed.connect(a.fn)
		_actions.add_child(b)


func action_labels() -> Array:
	var out := []
	for c in _actions.get_children():
		if not c.is_queued_for_deletion():
			out.append(c.text)
	return out


func press_action(prefix: String) -> bool:
	for c in _actions.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.begins_with(prefix) and not c.disabled:
			c.pressed.emit()
			return true
	return false


func update(dt: float) -> void:
	var s := game.s
	var st := game.pstats()
	_ship_name.text = Rules.HULLS[s.ship].name
	_hp_num.text = "%d / %d" % [maxi(0, ceili(game.P.hp)), st.max_hp]
	_hull_bar.ratio = maxf(0, game.P.hp / st.max_hp)
	_hull_bar.queue_redraw()
	_vals.coin.text = Rules.fmt(s.coins)
	_vals.chest.text = Rules.fmt(s.vault)
	_vals.map.text = str(s.maps)
	_vals.ball.text = str(s.balls)
	_gauge.speed = maxf(0, game.P.v)
	_gauge.max_speed = st.speed
	_gauge.throttle = game.throttle
	_gauge.queue_redraw()
	_flash = maxf(0, _flash - dt)
	_hud_panel.modulate = Color(1, 0.6, 0.55) if _flash > 0 else Color.WHITE
	var pp := game.P.pos()
	var open := port_open()
	_edge("base", Vector3.ZERO, "Port · %s m" % Rules.fmt(Vector2(pp.x, pp.z).length() * 10), open)
	var t := game.treasure
	_edge("tre", t.pos if t else Vector3.ZERO, ("Trésor · %s m" % Rules.fmt(Vector2(t.pos.x - pp.x, t.pos.z - pp.z).length() * 10)) if t else "", open)
	var foe: Game.Boat = game.combat.e if game.combat and game.combat.e.state != "sink" else null
	_edge("foe", foe.pos() if foe else Vector3.ZERO, foe.name if foe else "", open)
	_update_labels(open)
	aim_shown = game.can_aim()
	if not aim_shown and aim_active:
		_aim_end(false)
	_aim.visible = aim_shown
	if aim_shown and _hint:
		_hint.visible = false
	_aim.position = aim_center()
	if open and _tab == "bateau":
		_spin_preview(dt)


## Shows an arrow at the screen's edge toward a target that is off screen.
func _edge(k: String, target: Vector3, text: String, hide: bool) -> void:
	var el: Edge = _edges[k]
	if text == "" or hide or not game.alive:
		el.visible = false
		return
	var W := root.size.x
	var H := root.size.y
	var pad := 64.0
	var top := 230.0
	var bot := 210.0
	var cam := game.camera
	var sp := cam.unproject_position(target)
	if not cam.is_position_behind(target) and sp.x > pad and sp.x < W - pad and sp.y > top and sp.y < H - bot:
		el.visible = false
		return
	var pp := game.P.pos()
	var a := atan2(target.x - pp.x, -(target.z - pp.z))
	var u := Vector2(sin(a), -cos(a))
	var c := Vector2(W / 2, H / 2)
	var kx := INF
	var ky := INF
	if u.x > 1e-4:
		kx = (W - pad - c.x) / u.x
	elif u.x < -1e-4:
		kx = (pad - c.x) / u.x
	if u.y > 1e-4:
		ky = (H - bot - c.y) / u.y
	elif u.y < -1e-4:
		ky = (top - c.y) / u.y
	el.position = c + u * minf(kx, ky)
	el.angle = a
	el.label.text = text
	el.visible = true
	el.queue_redraw()


func _update_labels(hide: bool) -> void:
	var li := 0
	var pp := game.P.pos()
	var cam := game.camera
	for e in game.enemies:
		if hide or e.state == "sink":
			continue
		var ep := e.pos()
		if Vector2(ep.x - pp.x, ep.z - pp.z).length() > 85:
			continue
		var p3 := ep + Vector3(0, 7, 0)
		if cam.is_position_behind(p3):
			continue
		var sp := cam.unproject_position(p3)
		if sp.x < -40 or sp.x > root.size.x + 40 or sp.y < -40 or sp.y > root.size.y + 40:
			continue
		if li >= _labels.size():
			_labels.append(_make_label())
		var l: Control = _labels[li]
		li += 1
		l.visible = true
		l.position = sp - Vector2(130, 74)
		var foe: bool = game.combat and game.combat.e == e
		var name_l: Label = l.get_child(0)
		name_l.text = "%s · %s" % [e.name, Rules.HULLS[e.hk].name]
		name_l.add_theme_color_override("font_color", Color8(0xff, 0xc4, 0xae) if foe else FOAM)
		(l.get_child(1) as Label).text = "hors ligne · défense auto" if e.offline else "en ligne"
		var bar: Bar = l.get_child(2)
		bar.ratio = maxf(0, e.hp / e.max_hp)
		bar.queue_redraw()
	for i in range(li, _labels.size()):
		_labels[i].visible = false


func _make_label() -> Control:
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size = Vector2(260, 70)
	v.add_theme_constant_override("separation", 2)
	for k in [[19, f_bold], [15, f_body]]:
		var l := _label("", k[0], k[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_shadow_color", Color(0.08, 0.13, 0.15, 0.7))
		l.add_theme_constant_override("shadow_offset_y", 2)
		v.add_child(l)
	var bar := Bar.new(7)
	bar.bg = Color(0.08, 0.13, 0.15, 0.5)
	bar.custom_minimum_size.x = 120
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(bar)
	root.add_child(v)
	root.move_child(v, 1)
	return v


# ---------------------------------------------------------------- the port

func port_open() -> bool:
	return _port != null and _port.visible


func _parch_theme() -> Theme:
	var t := Theme.new()
	t.default_font = f_body
	t.default_font_size = 21
	t.set_color("font_color", "Label", INK)
	var btn := _sb(Color(1, 0.98, 0.93, 0.55), 12, Color(INK, 0.55), 2, Vector4(18, 9, 18, 9))
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "Button", _sb(Color(INK, 0.15), 12, Color(INK, 0.6), 2, Vector4(18, 9, 18, 9)))
	t.set_stylebox("disabled", "Button", _sb(Color(1, 0.98, 0.93, 0.25), 12, Color(INK, 0.22), 2, Vector4(18, 9, 18, 9)))
	t.set_font("font", "Button", f_bold)
	t.set_font_size("font_size", "Button", 21)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.4))
	t.set_type_variation("Primary", "Button")
	var p := _sb(WAX, 12, Color(0.2, 0.06, 0.03, 0.6), 2, Vector4(18, 9, 18, 9))
	t.set_stylebox("normal", "Primary", p)
	t.set_stylebox("hover", "Primary", p)
	t.set_stylebox("pressed", "Primary", _sb(WAX.darkened(0.25), 12, Color(0.2, 0.06, 0.03, 0.6), 2, Vector4(18, 9, 18, 9)))
	t.set_stylebox("disabled", "Primary", _sb(Color(WAX, 0.35), 12, Color(0.2, 0.06, 0.03, 0.25), 2, Vector4(18, 9, 18, 9)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "Primary", Color8(0xfd, 0xf6, 0xf2))
	t.set_color("font_disabled_color", "Primary", Color(1, 0.95, 0.92, 0.6))
	t.set_type_variation("Tab", "Button")
	t.set_stylebox("normal", "Tab", _sb(Color(0, 0, 0, 0), 0, Color(INK, 0.2), 0, Vector4(4, 10, 4, 12)))
	t.set_stylebox("hover", "Tab", _sb(Color(0, 0, 0, 0), 0, Color(INK, 0.2), 0, Vector4(4, 10, 4, 12)))
	t.set_stylebox("pressed", "Tab", _sb(Color(INK, 0.08), 0, Color(INK, 0.2), 0, Vector4(4, 10, 4, 12)))
	t.set_font("font", "Tab", f_caps)
	t.set_font_size("font_size", "Tab", 24)
	t.set_color("font_color", "Tab", Color(INK, 0.6))
	t.set_color("font_hover_color", "Tab", INK)
	t.set_color("font_pressed_color", "Tab", INK)
	t.set_type_variation("TabOn", "Button")
	var on := _sb(Color(0, 0, 0, 0), 0, WAX, 0, Vector4(4, 10, 4, 9))
	on.border_width_bottom = 3
	for k in ["normal", "hover", "pressed"]:
		t.set_stylebox(k, "TabOn", on)
	t.set_font("font", "TabOn", f_caps)
	t.set_font_size("font_size", "TabOn", 24)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(k, "TabOn", WAX)
	t.set_stylebox("panel", "PanelContainer", _sb(Color(1, 0.98, 0.93, 0.4), 12, Color(INK, 0.18), 1, Vector4(18, 14, 18, 14)))
	return t


## The port: a parchment sheet of constant size over the dimmed sea.
func _build_port() -> void:
	_port = Control.new()
	_port.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_port.visible = false
	_port.theme = _parch_theme()
	root.add_child(_port)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.04, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_port.add_child(dim)
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	var psb := _sb(PARCH, 18, WOOD, 3, Vector4(28, 24, 28, 22))
	psb.shadow_color = Color(0, 0, 0, 0.45)
	psb.shadow_size = 24
	sheet.add_theme_stylebox_override("panel", psb)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.offset_left = 18
	sheet.offset_right = -18
	sheet.offset_top = 40
	sheet.offset_bottom = -40
	_port.add_child(sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	sheet.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(_label("Le Port", 54, f_title, INK))
	tv.add_child(_label("Comptoir de la Mer des Brumes", 22, f_italic, Color(INK, 0.7)))
	var close := Button.new()
	close.name = "Close"
	close.text = "Larguer les amarres"
	close.theme_type_variation = "Primary"
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_port)
	head.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	v.add_child(tabs)
	for k in [["coffre", "Coffre"], ["bateau", "Chantier"], ["equipage", "Équipage"], ["base", "Fort"]]:
		var b := Button.new()
		b.text = k[1]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.pressed.connect(func(): _tab = k[0]; _confirm_reset = false; refresh_port())
		tabs.add_child(b)
		_tabs[k[0]] = b
	var rule := ColorRect.new()
	rule.color = Color(INK, 0.22)
	rule.custom_minimum_size.y = 2
	v.add_child(rule)
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 30)
	v.add_child(money)
	for k in [["coin", "à bord"], ["chest", "au coffre"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		h.add_child(Icon.new(k[0], 30))
		var n := _label("0", 28, f_bold, INK)
		h.add_child(n)
		var sub := _label(k[1], 20, f_italic, Color(INK, 0.65))
		sub.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(sub)
		money.add_child(h)
		_money[k[0]] = n
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)
	# the shipyard preview: its own little 3D world
	_pv_vp = SubViewport.new()
	_pv_vp.own_world_3d = true
	_pv_vp.transparent_bg = true
	_pv_vp.size = Vector2i(640, 330)
	_pv_vp.msaa_3d = Viewport.MSAA_4X
	_pv_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xd8, 0xcf, 0xbc)
	env.ambient_light_energy = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	_pv_vp.add_child(we)
	var dl := DirectionalLight3D.new()
	dl.light_color = Color8(0xff, 0xf0, 0xda)
	dl.light_energy = 0.85
	_pv_vp.add_child(dl)
	dl.look_at_from_position(Vector3(6, 10, 5), Vector3.ZERO, Vector3.UP)
	var wb := Models.Builder.new()
	wb.prim(Models.cyl(6.2, 6.7, 0.8, 10), Transform3D.IDENTITY, Color8(0x5b, 0x7f, 0x88), 0.5, 3, 3)
	var water := Models.instance(wb.commit(), null, false)
	water.position.y = -0.45
	_pv_vp.add_child(water)
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 30
	_pv_vp.add_child(_pv_cam)


func _exit_tree() -> void:
	if _pv_vp and not _pv_vp.is_inside_tree():
		_pv_vp.free()


func open_port() -> void:
	_pv_idx = maxi(0, Rules.yard_list(game.s).find(game.s.ship))
	_confirm_reset = false
	cancel_sticks()
	_port.visible = true
	_actions.visible = false
	refresh_port()
	game.check_update()


func close_port() -> void:
	_port.visible = false
	_actions.visible = true
	game.save()


func _item(title: String, lvl: Control, desc: String, buttons: Array) -> PanelContainer:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var t := _label(title, 28, f_title, INK)
	h.add_child(t)
	if lvl:
		lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lvl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	for b in buttons:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	var d := _label(desc, 19, f_body, Color(INK, 0.75))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return p


func _btn(text: String, primary: bool, enabled: bool, fn: Callable, coin := false) -> Button:
	var b := Button.new()
	b.text = text
	if coin:
		var img := _coin_tex()
		b.icon = img
		b.expand_icon = false
	if primary:
		b.theme_type_variation = "Primary"
	b.disabled = not enabled
	b.pressed.connect(fn)
	return b


var _coin: ImageTexture


func _coin_tex() -> ImageTexture:
	if _coin == null:
		var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		for y in 24:
			for x in 24:
				var d := Vector2(x + 0.5 - 12, y + 0.5 - 12).length()
				var c := Color(0, 0, 0, 0)
				if d < 10.5:
					c = Color8(0xd8, 0xb2, 0x5a)
					if absf(d - 6.4) < 1.0:
						c = Color8(0xa7, 0x80, 0x2f)
					c.a = clampf(10.5 - d, 0, 1)
				img.set_pixel(x, y, c)
		_coin = ImageTexture.create_from_image(img)
	return _coin


func _note(text: String) -> Label:
	var l := _label(text, 19, f_italic, Color(INK, 0.72))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _cap(text: String) -> Label:
	var l := _label(text, 22, f_body, INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Rebuilds the open tab from the game state.
func refresh_port() -> void:
	if not port_open():
		return
	var s := game.s
	for k in _tabs:
		_tabs[k].theme_type_variation = "TabOn" if k == _tab else "Tab"
	_money.coin.text = Rules.fmt(s.coins)
	_money.chest.text = Rules.fmt(s.vault)
	if _pv_vp.get_parent():
		_pv_vp.get_parent().remove_child(_pv_vp)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var total: int = s.coins + s.vault
	match _tab:
		"coffre":
			var free := Rules.vault_cap(s) - int(s.vault)
			_body.add_child(_cap("Place dans le coffre : %s / %s" % [Rules.fmt(s.vault), Rules.fmt(Rules.vault_cap(s))]))
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			h.add_child(_btn("Mettre les pièces à l'abri", true, s.coins > 0 and free > 0, func():
				var n := Rules.deposit(game.s)
				toast("%s pièces mises à l'abri" % Rules.fmt(n))
				_done("")))
			h.add_child(_btn("Prendre 500 pièces", false, s.vault > 0, func(): Rules.withdraw(game.s); _done("")))
			_body.add_child(h)
			_body.add_child(_note("Les pièces à bord sont en jeu : si votre bateau coule, vous en perdez la moitié. Le coffre reste au port."))
		"bateau":
			_yard(total)
		"equipage":
			var st := game.pstats()
			_body.add_child(_cap("Équipage : %d / %d places · force à l'abordage %s par seconde" % [Rules.crew_count(s), st.crew_cap, ("%.1f" % st.crew_dps).replace(".", ",")]))
			for c in Rules.CREW:
				var n: int = s.crew[c.k]
				var fire := _btn("−", false, n > 0, func(): game.s.crew[c.k] -= 1; _done("ship"))
				var hire := _btn("+ %s" % Rules.fmt(c.cost), true, total >= c.cost and Rules.crew_count(s) < st.crew_cap, func(): Rules.hire(game.s, c.k); _done("ship"), true)
				var lv := _label("×%d" % n, 22, f_bold, Color(INK, 0.7))
				_body.add_child(_item(c.name, lv, "%s · %s pièces" % [c.desc, Rules.fmt(c.cost)], [fire, hire]))
			_body.add_child(_note("L'équipage se bat quand les deux bateaux sont bord à bord (portée d'abordage %d, plus avec des grappins). Un meilleur capitaine donne plus de places." % int(st.board)))
		"base":
			for u in Rules.BASE_UPS:
				var l: int = s.base[u.k]
				var c := Rules.up_cost(u.k, l)
				var b := _btn("Au maximum", false, false, func(): pass) if l >= u.max else _btn(Rules.fmt(c), true, total >= c, func():
					if Rules.buy_base(game.s, u.k):
						toast("%s : niveau %d" % [u.name, game.s.base[u.k]])
					_done("base"), true)
				_body.add_child(_item(u.name, Pips.new(l, u.max), u.desc, [b]))
			_body.add_child(_note("Avec au moins une tour, les ennemis renoncent à vous poursuivre près du port."))
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			var ver := _label("Version %s" % game.build_id(), 19, f_body, Color(INK, 0.6))
			ver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ver)
			if game.new_build > 0:
				h.add_child(_btn("Nouvelle version %d : relancer" % game.new_build, true, true, game.refresh_game))
			_body.add_child(h)
			var reset := _btn("Confirmer : tout effacer" if _confirm_reset else "Recommencer la partie", _confirm_reset, true, func():
				if _confirm_reset:
					_confirm_reset = false
					game.reset_game()
				else:
					_confirm_reset = true
				refresh_port())
			reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_body.add_child(reset)


func _done(what: String) -> void:
	if what != "":
		game.after_purchase(what)
	else:
		game.save()
	refresh_port()


## The shipyard: a carousel of hulls with a turning 3D preview.
func _yard(total: int) -> void:
	var s := game.s
	var list := Rules.yard_list(s)
	_pv_idx = clampi(_pv_idx, 0, list.size() - 1)
	var k: String = list[_pv_idx]
	var X: Dictionary = Rules.HULLS[k]
	var own: bool = k == s.ship
	var zero := {}
	for u in X.caps:
		zero[u] = 0
	var lo := Rules.ship_stats(k, s.up if own else zero, 0)
	var mx := Rules.ship_stats(k, X.caps, 0)
	# preview
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(0, 300)
	slot.clip_contents = true
	var bg := Panel.new()
	var bsb := _sb(Color8(0xa9, 0xbd, 0xbd), 14, Color(INK, 0.35), 2)
	bg.add_theme_stylebox_override("panel", bsb)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(bg)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.add_child(_pv_vp)
	slot.add_child(svc)
	_set_preview(k, own)
	if list.size() > 1:
		for d in [[-1, "‹", Control.PRESET_CENTER_LEFT], [1, "›", Control.PRESET_CENTER_RIGHT]]:
			var nb := Button.new()
			nb.text = d[1]
			nb.add_theme_font_size_override("font_size", 40)
			nb.custom_minimum_size = Vector2(64, 64)
			nb.set_anchors_and_offsets_preset(d[2])
			nb.offset_left = 10 if d[0] < 0 else -74
			nb.offset_right = 74 if d[0] < 0 else -10
			nb.offset_top = -32
			nb.offset_bottom = 32
			nb.pressed.connect(func(): _pv_idx = (_pv_idx + d[0] + list.size()) % list.size(); refresh_port())
			slot.add_child(nb)
	var tag := Label.new()
	tag.text = "Votre navire" if own else "%s pièces" % Rules.fmt(X.price)
	tag.add_theme_font_override("font", f_bold)
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_color_override("font_color", Color8(0xfd, 0xf6, 0xf2))
	tag.add_theme_stylebox_override("normal", _sb(WAX if own else Color(INK, 0.8), 10, Color(0, 0, 0, 0), 0, Vector4(14, 6, 14, 6)))
	tag.position = Vector2(14, 246)
	slot.add_child(tag)
	_body.add_child(slot)
	var head := HBoxContainer.new()
	var title := _label(X.name, 40, f_title, INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label("%d / %d" % [_pv_idx + 1, list.size()], 20, f_body, Color(INK, 0.6)))
	_body.add_child(head)
	var fl := _label(X.desc, 20, f_italic, Color(INK, 0.8))
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(fl)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	var n1 := func(x): return ("%.1f" % x).replace(".", ",")
	var rg := func(a, b, f): return f.call(a) if a == b else "%s → %s" % [f.call(a), f.call(b)]
	var ident := func(x): return str(x)
	for row in [["Vitesse", rg.call(lo.speed, mx.speed, n1) + " nœuds"], ["Coque", rg.call(lo.max_hp, mx.max_hp, ident)],
			["Canons par flanc", rg.call(lo.side, mx.side, ident)], ["Avant / arrière", "%d / %d" % [X.bow, X.stern]]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(_label(row[0], 17, f_caps, Color(INK, 0.6)))
		cell.add_child(_label(row[1], 22, f_bold, INK))
		grid.add_child(cell)
	_body.add_child(grid)
	if own:
		var capped := true
		for u in Rules.UPS:
			var cap: int = X.caps[u.k]
			if cap == 0:
				continue
			var l: int = s.up[u.k]
			if l < cap:
				capped = false
			var locked: bool = u.k == "voiles" and s.up.rameurs < X.caps.rameurs
			var c := Rules.up_cost(u.k, l)
			var b := _btn("Au maximum", false, false, func(): pass) if l >= cap else _btn(Rules.fmt(c), true, not locked and total >= c, func():
				if Rules.buy_upgrade(game.s, u.k):
					toast("%s : niveau %d" % [u.name, game.s.up[u.k]])
				_done("coque" if u.k == "coque" else "ship"), true)
			_body.add_child(_item(u.name, Pips.new(l, cap), u.req if locked and l < cap else u.desc, [b]))
		_body.add_child(_item("Boulets de canon", _label("%d en cale" % s.balls, 20, f_bold, Color(INK, 0.7)), "%d boulets de plus. Chaque bordée en utilise un." % Rules.BALL_PACK,
			[_btn(str(Rules.BALL_COST), false, total >= Rules.BALL_COST, func():
				if Rules.spend(game.s, Rules.BALL_COST):
					game.s.balls += Rules.BALL_PACK
				_done(""), true)]))
		_body.add_child(_note("Ce navire est au maximum. Passez au suivant avec les flèches pour en changer." if capped else
			"Chaque navire a ses limites. Une fois au maximum, il faudra en changer : parcourez le chantier avec les flèches."))
	else:
		var buy := _btn("Acheter pour %s pièces" % Rules.fmt(X.price), true, total >= X.price, func():
			if Rules.buy_hull(game.s, k):
				toast("Nouveau bateau : %s" % X.name, "gold")
				_pv_idx = Rules.yard_list(game.s).find(game.s.ship)
			_done("hull"), true)
		buy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_body.add_child(buy)
		_body.add_child(_note("Le nouveau navire part sans améliorations. Les achats prennent d'abord les pièces à bord, puis celles du coffre."))


func _set_preview(hk: String, own: bool) -> void:
	var s := game.s
	var key := hk + (JSON.stringify(s.up) + JSON.stringify(s.crew) if own else "")
	if key == _pv_key and _pv_ship:
		return
	_pv_key = key
	if _pv_ship:
		_pv_ship.queue_free()
	var zero := {}
	for u in Rules.HULLS[hk].caps:
		zero[u] = 0
	var crew := []
	if own:
		for c in Rules.CREW:
			for i in int(s.crew[c.k]):
				crew.append(c.color)
	_pv_ship = Models.ship(Models.ship_cfg(hk, s.up if own else zero, crew, {}))
	_pv_vp.add_child(_pv_ship)
	_spin_preview(0)


func preview_hull() -> String:
	return _pv_key.substr(0, _pv_key.find("{")) if _pv_key.contains("{") else _pv_key


func _spin_preview(dt: float) -> void:
	if _pv_ship == null:
		return
	_pv_ang += dt * 0.35
	var list := Rules.yard_list(game.s)
	var sc: float = Rules.HULLS[list[clampi(_pv_idx, 0, list.size() - 1)]].scale.z
	var r := 10.5 * sc
	_pv_cam.look_at_from_position(Vector3(sin(_pv_ang) * r, 4.4 * sc, cos(_pv_ang) * r), Vector3(0, 2 * sc, 0), Vector3.UP)
	var t := game.time
	_pv_ship.position.y = sin(t * 1.2) * 0.08
	_pv_ship.get_meta("body").rotation.z = sin(t * 1.1) * 0.04
	Models.billow(_pv_ship, 0.4, t)
