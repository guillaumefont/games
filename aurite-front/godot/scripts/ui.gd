class_name UI
extends Control
const Cutscenes := preload("res://scripts/cutscenes.gd")  # no class_name: an installed shell would not know a new global class
const Squads := preload("res://scripts/squads.gd")
const Radial := preload("res://scripts/radial.gd")   # the corner wheel and the ring menus around structures
## All screen UI, built in code: HUD, corner wheel and structure rings (scripts/radial.gd), overlays. Game logic lives in main.gd.

const C_BG := Color("0b0f12")
const C_PANEL := Color("141a1e")
const C_PANEL2 := Color("1b2328")
const C_LINE := Color("2a353c")
const C_FG := Color("e4ebee")
const C_DIM := Color("8b9aa3")
const C_AUR := Color("f0b93f")
const C_ACC := Color("e5483f")
## Menu art stage, following the campaign's descent: 0 pulpy (campaign I), 1 cracked (II), 2 grim (III).
## Sketch: picked with AF_STAGE for now.
static var stage := 0
var _stage_fx: Array[Callable] = []   # re-applies stage colours and words to the menu when the stage changes

## Sets the menu art stage (main.menu_stage() picks it from campaign progress) and restyles every menu screen.
func set_stage(st: int) -> void:
	if OS.get_environment("AF_STAGE") != "": st = int(OS.get_environment("AF_STAGE"))   # screenshots of one stage
	stage = clampi(st, 0, 2)
	for f in _stage_fx: f.call()
	for k in overlays: _redraw_tree(overlays[k])

func _redraw_tree(n: Node) -> void:
	if n is CanvasItem: (n as CanvasItem).queue_redraw()
	for ch in n.get_children(): _redraw_tree(ch)
static var _glow_tex: GradientTexture2D
## Soft radial light (smooth, no banding): a white disc fading to nothing, tinted and stretched to r.
static func glow(ci: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new(); _glow_tex.gradient = g; _glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5); _glow_tex.fill_to = Vector2(1.0, 0.5); _glow_tex.width = 256; _glow_tex.height = 256
	ci.draw_texture_rect(_glow_tex, Rect2(c - r, r * 2), false, col)
const C_OK := Color("7fd68e")
const C_BAD := Color("ff5a52")
const PANEL_W := 188.0
const RADAR_TINT := """shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
uniform float k = 0.0;
void fragment() {
	vec3 c = texture(scr, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 t = vec3(g) * vec3(0.66, 0.84, 0.78) + vec3(0.02, 0.05, 0.045);
	COLOR = vec4(mix(c, t, 0.6 * k) * (1.0 - 0.2 * k), 1.0);
}"""

var main  # main.gd
var f_disp: FontFile
var f_disp6: FontFile
var f_disp7: FontFile
var f_body: FontFile
var f_body6: FontFile

var hud: Control
var credits_l: Label
var power_l: Label
var power_bar: PowerMeter
var power_box: PanelContainer
var power_parts: Array = []   # separator, glyph and stat of the power readout (hidden for factions without power)
var cap_parts: Array = []     # same for the unit cap readout (only for factions with a cap)
var cap_l: Label
var sw_box: Plate
var sw_name: Label
var sw_time: Label
var obj_l: RichTextLabel
var obj_box: Plate
var toast_box: Plate
var toast_l: Label
var toast_t := 0.0
var radio_box: Plate
var radio_face: Portrait
var radio_who: Label
var radio_l: Label
var radio_q: Array = []   # lines waiting: [who, line, warn]
var radio_t := 0.0        # time left on the line showing
var cmd_row: VBoxContainer     # the thumb dock at the bottom of the side column: squads, then Attack / Stop / ✕
var cmd_top: GridContainer     # type chips of a mixed selection (two per row)
var cmd_bot: GridContainer     # squad chips (two per row)
var panel_top: VBoxContainer   # the part of the side column above the dock (header, build list, orders); folds away
var btn := {}
var left_hand := false         # the side column (every button) on the left, the map thumb on the right
var place_bar: VBoxContainer  # while placing a building: its hint, Build here and Cancel, in the dock's place
var place_hint: Label
var panel: PanelContainer     # the old side column: no longer shown; it keeps the build items and order buttons the radial controls read
var wheel: Control            # Radial.Wheel: the corner wheel under the action thumb
var ring: Control             # Radial.Ring: the ring menu around a selected structure
var plates: VBoxContainer     # above the wheel: what is picked, type chips, JOIN, Launch, ✕
var plate_row: HBoxContainer
var radar_tint: ColorRect  # greys and cools the 3D view while zoomed out to radar (main.gd sets its "k")
var prod_chips := {}      # building type -> ProdChip in the top bar: what that kind of producer is making
var chip_box: VBoxContainer  # the producer shortcut column, on the side away from the wheel
var ctx_box: Plate        # side panel header: what is selected
var ctx_kick: Label
var ctx_name: Label
var ctx_sub: Label
var ctx_hp: HpBar
var ctx_tabs: HBoxContainer   # sub-tabs of a producer that makes several kinds (Landing Zone, Garden)
var ctx_acts: GridContainer   # what the selected building or units can do
var obj_btn: Button       # brings the objective back after it hides itself
var type_btns: Array = []   # type chips of a mixed selection (keep only that type)
var tabs := {}
var grid: GridContainer
var grid_scroll: ScrollContainer
var items := {}
var overlays := {}
var camp_pane: VBoxContainer
var camp_scroll: ScrollContainer
var press_scroll := 0
var sk_pane: VBoxContainer
var seg_btns := {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func font(path: String) -> FontFile:
	var f: FontFile = load(path)
	return f

func build() -> void:
	f_disp = font("res://fonts/chakra-petch-latin-600-normal.woff2")
	f_disp7 = font("res://fonts/chakra-petch-latin-700-normal.woff2")
	f_disp6 = font("res://fonts/chakra-petch-latin-500-normal.woff2")
	f_body = font("res://fonts/barlow-latin-500-normal.woff2")
	f_body6 = font("res://fonts/barlow-latin-600-normal.woff2")
	var th := Theme.new()
	th.default_font = f_body; th.default_font_size = 14
	th.set_color("font_color", "Label", C_FG)
	th.set_color("font_color", "Button", C_FG)
	th.set_color("font_hover_color", "Button", C_FG)
	th.set_color("font_pressed_color", "Button", C_FG)
	th.set_color("font_focus_color", "Button", C_FG)
	th.set_color("font_disabled_color", "Button", C_DIM)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		th.set_stylebox(st, "Button", sb(Color(0.08, 0.1, 0.12, 0.92), C_LINE))
	th.set_stylebox("hover", "Button", sb(Color(0.11, 0.14, 0.16, 0.95), Color("3b4a54")))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("panel", "PanelContainer", sb(Color(0.047, 0.063, 0.075, 0.84), C_LINE))
	theme = th
	_wide_fonts()
	_build_hud()
	_build_panel()
	_build_radial()
	_build_overlays()

static func sb(bg: Color, border := Color(0, 0, 0, 0), bw := 1, rad := 3, pad := 6.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(rad)
	s.content_margin_left = pad + 2; s.content_margin_right = pad + 2; s.content_margin_top = pad; s.content_margin_bottom = pad
	return s

func lbl(text: String, f: Font, size: int, col := C_FG) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", f); l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A HUD button: a chamfered olive plate with a brass glyph (see `glyph`) left of its text, or centred when it has no text.
func mkbtn(text: String, cb: Callable, w := 0.0, h := 42.0, size := 12, g := "") -> Button:
	var b := HudBtn.new(); b.text = text.to_upper(); b.glyph = g
	b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(max(w, 48.0), h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	restyle(b)
	return b

# HUD plate colours: olive-black field plates with brass trim, like the menus
const H_BG := Color(0.055, 0.062, 0.045, 0.9)
const H_BG2 := Color(0.09, 0.1, 0.07, 0.94)
const H_ON := Color("3a1512")

var _sb_cache := {}
## Plate stylebox for a HUD button state, cached (update_cmd restyles buttons several times a second).
func hsb(state: String, on: bool, ml: float, mr: float) -> StyleBoxFlat:
	var key := "%s%s%d_%d" % [state, on, ml, mr]
	if _sb_cache.has(key): return _sb_cache[key]
	var bg := H_ON if on else H_BG
	var bd := C_ACC if on else W_LINE
	match state:
		"hover": bd = C_ACC.lightened(0.15) if on else W_SAND
		"pressed": bg = bg.darkened(0.35); bd = W_BRASS
		"disabled": bg = Color(bg, 0.6); bd = Color(W_LINE, 0.5)
	var s := cut(bg, bd, 2 if on else 1, 7, 6.0)
	s.content_margin_left = ml; s.content_margin_right = mr
	s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = 3; s.shadow_offset = Vector2(0, 2)
	s.anti_aliasing = true
	_sb_cache[key] = s
	return s

## Applies the plate styles to a HUD button for its current glyph, text and on state.
func restyle(b: Button) -> void:
	var on: bool = b.get_meta("on", false)
	var g: String = b.glyph if b is HudBtn else ""
	var ml := 10.0; var mr := 10.0
	if g != "" and b.text != "" and not (b is HudBtn and b.cap != ""): ml = 36.0; mr = 12.0
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, hsb(st, on, ml, mr))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color("ffd8d2") if on else W_KHAKI)
	b.queue_redraw()

func set_on(b: Button, on: bool) -> void:
	if b.get_meta("on", false) == on and b.has_theme_stylebox_override("normal"): return
	b.set_meta("on", on); restyle(b)

# ---------------- HUD ----------------
func _build_hud() -> void:
	hud = Control.new(); hud.name = "HUD"; hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.anchor_right = 1; hud.anchor_bottom = 1; hud.offset_right = -PANEL_W
	add_child(hud)
	# radar: a screen pass under every HUD control that greys the view as the camera pulls back
	radar_tint = ColorRect.new(); radar_tint.set_anchors_preset(Control.PRESET_FULL_RECT); radar_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := Shader.new(); rs.code = RADAR_TINT; var rm := ShaderMaterial.new(); rm.shader = rs; radar_tint.material = rm
	radar_tint.visible = false; hud.add_child(radar_tint)
	var draw := HudDraw.new(); draw.ui = self; draw.set_anchors_preset(Control.PRESET_FULL_RECT); draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(draw); hud.set_meta("draw", draw)
	var top := HBoxContainer.new(); top.position = Vector2(8, 8); top.add_theme_constant_override("separation", 6); top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_right = 1; top.offset_right = -8
	hud.add_child(top)
	# resource strip: one brass-trimmed plate, aurite then power with a segmented meter
	var res := Plate.new(); res.mouse_filter = Control.MOUSE_FILTER_IGNORE
	res.add_theme_stylebox_override("panel", plate_sb(8.0)); top.add_child(res)
	var rh := HBoxContainer.new(); rh.add_theme_constant_override("separation", 10); rh.mouse_filter = Control.MOUSE_FILTER_IGNORE; res.add_child(rh)
	rh.add_child(_glyph_box("aur", 24, C_AUR))
	var cv := _stat(rh, "AURITE"); credits_l = lbl("0", f_disp7, 18, C_AUR); credits_l.custom_minimum_size.x = 62; cv.add_child(credits_l)
	var sep := Rule.new(); sep.vertical = true; sep.custom_minimum_size = Vector2(2, 0); rh.add_child(sep)
	rh.add_child(_glyph_box("pwr", 22, C_OK))
	power_box = res
	var pv := _stat(rh, "POWER"); power_l = lbl("0 / 0", f_disp7, 18); pv.add_child(power_l)
	power_bar = PowerMeter.new(); power_bar.custom_minimum_size = Vector2(92, 6); power_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE; pv.add_child(power_bar)
	power_parts = [sep, rh.get_child(rh.get_child_count() - 2), pv]
	var sep2 := Rule.new(); sep2.vertical = true; sep2.custom_minimum_size = Vector2(2, 0); rh.add_child(sep2)
	var cg := _glyph_box("inf", 22, C_FG); rh.add_child(cg)
	var kv := _stat(rh, "UNITS"); cap_l = lbl("0 / 0", f_disp7, 18); kv.add_child(cap_l)
	cap_parts = [sep2, cg, kv]
	for c in cap_parts: c.visible = false
	sw_box = Plate.new(); sw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; sw_box.accent = C_ACC
	sw_box.add_theme_stylebox_override("panel", plate_sb(8.0, Color(0.13, 0.05, 0.04, 0.9), Color("6a2a22"))); top.add_child(sw_box)
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 8); sh.mouse_filter = Control.MOUSE_FILTER_IGNORE; sw_box.add_child(sh)
	sh.add_child(_glyph_box("launch", 22, Color("ff9a8c")))
	var sv := _stat(sh, "SKYFALL"); sw_name = sv.get_child(0); sw_time = lbl("0:00", f_disp7, 18, Color("ffd0cc")); sv.add_child(sw_time); sw_box.visible = false
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp.mouse_filter = Control.MOUSE_FILTER_IGNORE; top.add_child(sp)
	# one chip per kind of producer you own (Yard, Barracks, ...): what it is making; tap to select it
	chip_box = VBoxContainer.new(); chip_box.add_theme_constant_override("separation", 6); chip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chip_box)
	var pb := mkbtn("", func(): main.toggle_panel(), 48, 48, 13, "hide"); top.add_child(pb); btn["panel"] = pb
	var mb := mkbtn("", func(): main.open_menu(), 48, 48, 16, "pause"); top.add_child(mb); btn["pause"] = mb
	# the objective shows for a few seconds, then folds into this button (tap the box to fold it sooner)
	obj_btn = mkbtn("Objective", func(): main.show_objective(), 0, 40, 11, "obj"); obj_btn.position = Vector2(8, 70); obj_btn.visible = false
	hud.add_child(obj_btn)
	obj_box = Plate.new(); obj_box.position = Vector2(8, 70); obj_box.custom_minimum_size = Vector2(310, 0); obj_box.mouse_filter = Control.MOUSE_FILTER_STOP
	obj_box.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT: main.hide_objective())
	obj_box.add_theme_stylebox_override("panel", plate_sb(10.0, H_BG, W_LINE, W_BRASS))
	var ov := VBoxContainer.new(); ov.add_theme_constant_override("separation", 4); ov.mouse_filter = Control.MOUSE_FILTER_IGNORE; obj_box.add_child(ov)
	var oh := HBoxContainer.new(); oh.add_theme_constant_override("separation", 6); oh.mouse_filter = Control.MOUSE_FILTER_IGNORE; ov.add_child(oh)
	oh.add_child(_glyph_box("obj", 14, W_BRASS)); oh.add_child(lbl("OBJECTIVE", f_wide, 11, W_BRASS))
	var orule := Rule.new(); orule.custom_minimum_size = Vector2(0, 2); ov.add_child(orule)
	obj_l = RichTextLabel.new(); obj_l.fit_content = true; obj_l.custom_minimum_size = Vector2(286, 0); obj_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj_l.add_theme_font_override("normal_font", f_body); obj_l.add_theme_font_size_override("normal_font_size", 13)
	obj_l.add_theme_color_override("default_color", Color("e2dac2")); ov.add_child(obj_l)
	obj_box.visible = false; hud.add_child(obj_box)
	toast_box = Plate.new(); toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := HBoxContainer.new(); th.add_theme_constant_override("separation", 8); th.mouse_filter = Control.MOUSE_FILTER_IGNORE; toast_box.add_child(th)
	toast_g = _glyph_box("info", 14, C_ACC); th.add_child(toast_g)
	toast_l = lbl("", f_disp, 13); th.add_child(toast_l); toast_box.visible = false
	toast_box.anchor_left = 0.5; toast_box.anchor_right = 0.5; toast_box.offset_top = 70; toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.add_child(toast_box)
	# radio panel: the speaker's portrait and the line typing out, top centre (toasts drop below it while it shows)
	radio_box = Plate.new(); radio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rdh := HBoxContainer.new(); rdh.add_theme_constant_override("separation", 12); rdh.mouse_filter = Control.MOUSE_FILTER_IGNORE; radio_box.add_child(rdh)
	radio_face = Portrait.new(); radio_face.custom_minimum_size = Vector2(68, 68); radio_face.live = true; rdh.add_child(radio_face)
	var rdv := VBoxContainer.new(); rdv.add_theme_constant_override("separation", 2); rdv.alignment = BoxContainer.ALIGNMENT_CENTER; rdv.mouse_filter = Control.MOUSE_FILTER_IGNORE; rdh.add_child(rdv)
	radio_who = lbl("", f_wide, 11, W_BRASS); rdv.add_child(radio_who)
	radio_l = lbl("", f_body, 16, W_KHAKI); radio_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; radio_l.custom_minimum_size.x = 380; rdv.add_child(radio_l)
	radio_box.anchor_left = 0.5; radio_box.anchor_right = 0.5; radio_box.offset_top = 66; radio_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	radio_box.visible = false; hud.add_child(radio_box)
	hud.move_child(obj_box, -1)

## A titled stat inside a plate: small sand caption, then whatever the caller adds.
func _stat(par: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", -1); v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(lbl(title, f_wide, 9, W_SAND))
	par.add_child(v)
	return v

func _glyph_box(g: String, sz: float, col: Color) -> Glyph:
	var gl := Glyph.new(); gl.kind = g; gl.col = col; gl.custom_minimum_size = Vector2(sz, sz)
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER; gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gl

## Chamfered olive plate for HUD readouts; `bar` draws a coloured strip down the left edge.
func plate_sb(pad := 8.0, bg := H_BG, border := W_LINE, bar := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := cut(bg, border, 1, 8, pad)
	s.content_margin_left = pad + 4; s.content_margin_right = pad + 4
	s.shadow_color = Color(0, 0, 0, 0.35); s.shadow_size = 4; s.shadow_offset = Vector2(0, 2); s.anti_aliasing = true
	if bar.a > 0:
		s.border_width_left = 3; s.border_color = border
		s.set_meta("bar", bar)
		s.content_margin_left = pad + 6
	return s

func _left_bar(c: Color) -> StyleBoxFlat:
	var s := sb(Color(0.047, 0.063, 0.075, 0.86), C_LINE)
	s.border_width_left = 3; s.border_color = C_LINE
	var s2 := s.duplicate(); s2.border_color = c; s2.border_width_top = 0; s2.border_width_right = 0; s2.border_width_bottom = 0
	return s2

var toast_g: Glyph
func toast(msg: String, kind := "") -> void:
	toast_l.text = msg.to_upper()
	var c := C_ACC
	if kind == "warn": c = C_BAD
	elif kind == "gold": c = C_AUR
	toast_box.add_theme_stylebox_override("panel", plate_sb(8.0, H_BG, W_LINE, c))
	toast_g.kind = "warn" if kind == "warn" else ("aur" if kind == "gold" else "info"); toast_g.col = c; toast_g.queue_redraw()
	toast_box.accent = c
	toast_l.add_theme_color_override("font_color", Color("ffd2cf") if kind == "warn" else W_KHAKI)
	toast_box.visible = true; toast_t = 2.4
	toast_box.reset_size()
	toast_box.offset_left = -toast_box.size.x / 2; toast_box.offset_right = toast_box.size.x / 2

## A radio line: the speaker's portrait, name and role, the line typing out. Lines queue; each stays long enough to read.
func radio(who: String, line: String, warn := false) -> void:
	radio_q.append([who, line, warn])
	if not radio_box.visible: _radio_next()

func _radio_next() -> void:
	if radio_q.is_empty():
		radio_box.visible = false; toast_box.offset_top = 70; return
	var r: Array = radio_q.pop_front()
	var sp: Dictionary = D.SPEAKERS.get(r[0], D.SPEAKERS.pact_hq)
	radio_face.sp = sp; radio_face.queue_redraw()
	radio_who.text = (sp.name + "  //  " + sp.role).to_upper()
	radio_who.add_theme_color_override("font_color", C_BAD if r[2] else sp.flash)
	radio_l.text = r[1]; radio_l.visible_ratio = 0.0
	radio_box.add_theme_stylebox_override("panel", plate_sb(8.0, H_BG, W_LINE, C_BAD if r[2] else sp.flash)); radio_box.accent = C_BAD if r[2] else sp.flash
	radio_box.visible = true; radio_t = 2.6 + r[1].length() * 0.055
	radio_box.reset_size(); radio_box.offset_left = -radio_box.size.x / 2; radio_box.offset_right = radio_box.size.x / 2
	toast_box.offset_top = 70 + radio_box.size.y + 8

func _radio_tick(dt: float) -> void:
	if not radio_box.visible: return
	radio_t -= dt
	radio_l.visible_ratio = minf(1.0, radio_l.visible_ratio + dt * 40.0 / maxf(1.0, radio_l.text.length()))
	radio_face.live = radio_l.visible_ratio < 1.0
	if radio_t <= 0: _radio_next()

## Debrief on the end screen: one row per line, portrait, name, the line. lines: [{"who", "say"}]
func set_debrief(lines: Array) -> void:
	for ch in btn.end_debrief.get_children(): ch.queue_free()
	btn.end_debrief.visible = lines.size() > 0
	for ln in lines:
		var sp: Dictionary = D.SPEAKERS.get(ln.who, D.SPEAKERS.pact_hq)
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12)
		var pf := Portrait.new(); pf.sp = sp; pf.custom_minimum_size = Vector2(54, 54); h.add_child(pf)
		var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 0); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
		v.add_child(lbl(sp.name.to_upper(), f_wide, 11, sp.flash))
		var l := lbl("\u201c" + ln.say + "\u201d", f_body, 16, W_KHAKI); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
		btn.end_debrief.add_child(h)

# ---------------- side panel ----------------
func _build_panel() -> void:
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel", sb(C_PANEL, C_LINE, 0, 0, 8))
	panel.anchor_left = 1; panel.anchor_right = 1; panel.anchor_bottom = 1; panel.offset_left = -PANEL_W
	panel.draw.connect(_draw_panel_bg)
	add_child(panel)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 8); panel.add_child(col)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6); v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(v); panel_top = v
	# header: what is selected (the Yard when nothing is), its health and one line about it
	ctx_box = Plate.new(); ctx_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctx_box.add_theme_stylebox_override("panel", plate_sb(7.0, H_BG, W_LINE, W_BRASS)); v.add_child(ctx_box)
	var cv := VBoxContainer.new(); cv.add_theme_constant_override("separation", 1); cv.mouse_filter = Control.MOUSE_FILTER_IGNORE; ctx_box.add_child(cv)
	ctx_kick = lbl("", f_wide, 9, W_BRASS); cv.add_child(ctx_kick)
	ctx_name = lbl("", f_disp7, 15, Color("f4ecd6")); ctx_name.clip_text = true; ctx_name.custom_minimum_size.x = 140; cv.add_child(ctx_name)
	ctx_hp = HpBar.new(); ctx_hp.custom_minimum_size = Vector2(0, 4); ctx_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE; cv.add_child(ctx_hp)
	ctx_sub = lbl("", f_body, 11, W_SAND); ctx_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ctx_sub.custom_minimum_size.x = 140
	ctx_sub.max_lines_visible = 2; ctx_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; cv.add_child(ctx_sub)
	ctx_tabs = HBoxContainer.new(); ctx_tabs.add_theme_constant_override("separation", 4); v.add_child(ctx_tabs)
	for c in ["inf", "veh", "air"]:
		var b := HudBtn.new(); b.cap = {"inf": "INF", "veh": "VEH", "air": "AIR"}[c]; b.glyph = c; b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", f_disp); b.add_theme_font_size_override("font_size", 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 44
		b.pressed.connect(func(): main.select_tab(c))
		var dot := ColorRect.new(); dot.color = C_ACC; dot.size = Vector2(6, 6); dot.position = Vector2(5, 5); dot.visible = false; dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot); b.set_meta("dot", dot)
		restyle(b)
		ctx_tabs.add_child(b); tabs[c] = b
	grid_scroll = ScrollContainer.new(); grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vsb := grid_scroll.get_v_scroll_bar(); vsb.custom_minimum_size.x = 4
	vsb.add_theme_stylebox_override("scroll", cut(Color(W_OLIVE2, 0.6), Color(0, 0, 0, 0), 0, 0, 0))
	for g in ["grabber", "grabber_highlight", "grabber_pressed"]: vsb.add_theme_stylebox_override(g, cut(Color(W_BRASS, 0.75), Color(0, 0, 0, 0), 0, 0, 0))
	v.add_child(grid_scroll)
	grid = GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)
	for cat in D.CAT_ORDER:
		for type in D.CATS[cat]:
			var it := BuildItem.new(); it.ui = self; it.cat = cat; it.type = type
			it.custom_minimum_size = Vector2((PANEL_W - 16 - 6) / 2.0, 82)
			grid.add_child(it); items[cat + ":" + type] = it
	# what the selection can do: building orders, and unit orders
	ctx_acts = GridContainer.new(); ctx_acts.columns = 3; ctx_acts.add_theme_constant_override("h_separation", 4); ctx_acts.add_theme_constant_override("v_separation", 6)
	v.add_child(ctx_acts)
	# building orders, then unit orders (stances for every army, then each army's own)
	for pair in [["loop", "Loop", "loop"], ["rally", "Rally", "move"], ["upgrade", "Upgrade", "up"], ["repair", "Repair", "repair"], ["muster", "Muster", "inf"], ["sell", "Sell", "sell"],
			["hold", "Hold", "hold"], ["nofire", "No fire", "nofire"], ["scatter", "Scatter", "scatter"], ["home", "To base", "home"],
			["jump", "Jump", "jump"], ["strip", "Strip", "strip"], ["fuse", "Fuse", "fuse"]]:
		var k: String = pair[0]
		var b := mkbtn("", func(): main.cmd_btn(k), 0, 46, 11, pair[2]); b.custom_minimum_size.x = (PANEL_W - 16 - 8) / 3.0
		b.cap = String(pair[1]).to_upper(); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctx_acts.add_child(b); btn[k] = b; b.visible = false
	_build_dock(col)

## Two thumbs (Guillaume 2026-11-28: "one thumb for moving and the other for actions"): the map has no buttons; every
## button lives in the side column, and the ones used most sit at its bottom, under the thumb: Launch and JOIN, the type
## chips of a mixed selection, the squads (two per row), then Attack / Stop / ✕. The dock stays when the panel is hidden.
func _build_dock(col: VBoxContainer) -> void:
	cmd_row = VBoxContainer.new(); cmd_row.add_theme_constant_override("separation", 6); cmd_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cmd_row)
	var sw := mkbtn("Launch", func(): main.cmd_btn("sw"), 0, 44, 12, "launch"); set_on(sw, true); sw.visible = false; cmd_row.add_child(sw); btn["sw"] = sw
	var jb := mkbtn("Join", func(): main.join_btn(), 0, 44, 12, "all"); jb.visible = false; set_on(jb, true)
	cmd_row.add_child(jb); btn["join"] = jb
	cmd_top = GridContainer.new(); cmd_top.columns = 2; cmd_top.add_theme_constant_override("h_separation", 6); cmd_top.add_theme_constant_override("v_separation", 6)
	cmd_top.mouse_filter = Control.MOUSE_FILTER_IGNORE; cmd_row.add_child(cmd_top)
	for i in 4:
		var tb := mkbtn("", func(): main.type_btn(type_btns[i].get_meta("type", "")), 0, 40, 10); tb.visible = false
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tb.custom_minimum_size.x = 0; tb.clip_text = true
		cmd_top.add_child(tb); type_btns.append(tb)
	# squads: ALL, NEW (units in no squad), squads 1 to 5 (only those that exist). See scripts/squads.gd.
	cmd_bot = GridContainer.new(); cmd_bot.columns = 2; cmd_bot.add_theme_constant_override("h_separation", 6); cmd_bot.add_theme_constant_override("v_separation", 6)
	cmd_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE; cmd_row.add_child(cmd_bot)
	for key in [0, -1] + range(1, Squads.MAX + 1):
		var c := SquadChip.new(); c.ui = self; c.key = key; c.focus_mode = Control.FOCUS_NONE
		c.custom_minimum_size = Vector2(0, 48); c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for st in ["normal", "hover", "pressed", "disabled", "focus"]: c.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		c.pressed.connect(func(): main.squad_tap(key))
		c.visible = false
		cmd_bot.add_child(c); btn["sq_all" if key == 0 else ("sq_new" if key == -1 else "sq%d" % key)] = c
	# the orders every army needs, last, right under the thumb
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; cmd_row.add_child(row)
	for pair in [["amove", "Attack", "atk"], ["stop", "Stop", "stop"], ["desel", "", "x"]]:
		var k: String = pair[0]
		var b := mkbtn(pair[1], func(): main.cmd_btn(k), 0, 56, 12, pair[2]); row.add_child(b); btn[k] = b; b.visible = false
	for k in ["amove", "stop"]:   # glyph over a caption, so both fit the column's width
		var b: Button = btn[k]
		b.cap = b.text; b.text = ""; b.custom_minimum_size.x = 0; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.amove.size_flags_stretch_ratio = 1.5
	btn.desel.custom_minimum_size.x = 48
	place_bar = VBoxContainer.new(); place_bar.add_theme_constant_override("separation", 6)
	var hb := Plate.new(); hb.add_theme_stylebox_override("panel", plate_sb(8.0)); place_hint = lbl("Drag to position · tap it to build", f_body6, 12, W_KHAKI)
	place_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; place_hint.custom_minimum_size.x = 140
	hb.add_child(place_hint); place_bar.add_child(hb)
	var bp := mkbtn("Build here", func(): main.confirm_place(), 0, 56, 13, "build"); set_on(bp, true); place_bar.add_child(bp)
	place_bar.add_child(mkbtn("Cancel", func(): main.end_placing(), 0, 48, 13, "x"))
	place_bar.visible = false; col.add_child(place_bar)

## Radial controls (Guillaume 2026-11-28): the ring around a structure, the corner wheel, and over the wheel the plates
## that go with a pick. The buttons they show come from the side column, which is now always hidden.
func _build_radial() -> void:
	ring = Radial.Ring.new(); ring.ui = self; ring.set_anchors_preset(Control.PRESET_FULL_RECT); hud.add_child(ring)
	hud.move_child(ring, 2)   # over the 3D view and the HUD drawing, under every button
	wheel = Radial.Wheel.new(); wheel.ui = self
	wheel.custom_minimum_size = Vector2(Radial.Wheel.R4 + 4, Radial.Wheel.R4 + 4); hud.add_child(wheel)
	plates = VBoxContainer.new(); plates.add_theme_constant_override("separation", 6); plates.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plates.alignment = BoxContainer.ALIGNMENT_END; hud.add_child(plates)
	ctx_box.reparent(plates)
	ctx_box.custom_minimum_size.x = 190
	cmd_top.reparent(plates); cmd_top.columns = 4
	for tb in type_btns: tb.custom_minimum_size = Vector2(84, 36)
	plate_row = HBoxContainer.new(); plate_row.add_theme_constant_override("separation", 6); plate_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plates.add_child(plate_row)
	for k in ["sq_new", "join", "sw", "desel"]:
		var b: Button = btn[k]; b.reparent(plate_row); b.custom_minimum_size = Vector2(48, 42)
	btn.sq_new.custom_minimum_size = Vector2(76, 42)
	place_bar.reparent(hud); place_bar.custom_minimum_size.x = 180
	panel.visible = false
	_place_radial()

## The wheel, its plates and the placing bar sit in the action thumb's corner: bottom right, bottom left when left-handed.
func _place_radial() -> void:
	if wheel == null: return
	var L := left_hand
	for c in [wheel, plates, place_bar]:
		c.anchor_left = 0.0 if L else 1.0; c.anchor_right = c.anchor_left; c.anchor_top = 1.0; c.anchor_bottom = 1.0
		c.grow_horizontal = Control.GROW_DIRECTION_END if L else Control.GROW_DIRECTION_BEGIN
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		c.offset_left = 0; c.offset_right = 0; c.offset_top = 0; c.offset_bottom = 0
	plates.offset_bottom = -(Radial.Wheel.R4 + 8)
	# the producer shortcuts: a column on the other side, under the top bar
	var R := not prod_col_left()
	chip_box.anchor_left = 1.0 if R else 0.0; chip_box.anchor_right = chip_box.anchor_left; chip_box.anchor_top = 0.0; chip_box.anchor_bottom = 0.0
	chip_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN if R else Control.GROW_DIRECTION_END
	chip_box.offset_left = 0; chip_box.offset_right = 0; chip_box.offset_top = 66; chip_box.offset_bottom = 66
	plate_row.alignment = BoxContainer.ALIGNMENT_BEGIN if L else BoxContainer.ALIGNMENT_END
	for c in [ctx_box, cmd_top]: c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if L else Control.SIZE_SHRINK_END
	wheel.queue_redraw()

## The producer shortcut column sits on the side away from the wheel.
func prod_col_left() -> bool:
	return not left_hand

## Does the dock show anything? A hidden panel folds down to the dock, or goes away when the dock is empty too.
func dock_used() -> bool:
	if place_bar.visible: return true
	for c in [btn.sw, btn.join, btn.amove, btn.stop, btn.desel] + type_btns: if c.visible: return true
	for c in cmd_bot.get_children(): if c.visible: return true
	return false

## Side panel backdrop: dark olive steel with a faint map grid and a brass seam along its inner edge.
func _draw_panel_bg() -> void:
	var s := panel.size
	panel.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color("171b13"), Color("171b13"), Color("0c0e0a"), Color("0c0e0a")]))
	var g := 23.0; var y := 0.0
	while y < s.y:
		panel.draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.85, 0.8, 0.64, 0.03), 1.0); y += g
	var x := 0.0
	while x < s.x:
		panel.draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0.85, 0.8, 0.64, 0.03), 1.0); x += g
	var ex := s.x - 2.0 if left_hand else 0.0   # the brass seam runs along the edge that faces the map
	panel.draw_rect(Rect2(ex, 0, 2, s.y), Color(W_BRASS, 0.55))
	if not panel_open: panel.draw_rect(Rect2(0, 0, s.x, 2), Color(W_BRASS, 0.55))
	panel.draw_rect(Rect2(s.x - 3.0 if left_hand else 2.0, 0, 1, s.y), Color(0, 0, 0, 0.6))
	for yy in [10.0, s.y - 10.0]:
		panel.draw_circle(Vector2(s.x - 9.0 if left_hand else 9.0, yy), 2.0, Color(W_BRASS, 0.5))

func set_tab(cat: String) -> void:
	for c in tabs:
		set_on(tabs[c], c == cat)

# ---------------- overlays (war-room look) ----------------
const W_KHAKI := Color("d8cba3")
const W_SAND := Color("a99c78")
const W_OLIVE := Color(0.075, 0.086, 0.059, 0.9)
const W_OLIVE2 := Color("21271a")
const W_LINE := Color("4a5238")
const W_BRASS := Color("d9a441")
const W_SEL := Color("33140f")
const W_GREEN := Color("8fcf7a")

var f_title: FontVariation
var f_wide: FontVariation

## Chamfered box: two cut corners, like stencilled military plates.
static func cut(bg: Color, border := Color(0, 0, 0, 0), bw := 1, c := 9, pad := 8.0) -> StyleBoxFlat:
	var s := sb(bg, border, bw, 0, pad)
	s.corner_radius_top_left = c; s.corner_radius_bottom_right = c; s.corner_detail = 1
	return s

func _wide_fonts() -> void:
	f_title = FontVariation.new(); f_title.base_font = f_disp7; f_title.spacing_glyph = 4
	f_wide = FontVariation.new(); f_wide.base_font = f_disp; f_wide.spacing_glyph = 2

## full: animated battlefield backdrop; otherwise a dim veil over the paused game.
## fit: the card fills the screen height instead of scrolling as a whole (its own lists scroll).
func _overlay(nm: String, maxw: float, full := true, fit := false) -> VBoxContainer:
	var o := Control.new(); o.name = nm; o.set_anchors_preset(Control.PRESET_FULL_RECT); o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := WarBG.new(); bg.full = full; bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; o.add_child(bg)
	var mc := MarginContainer.new(); for s in ["left", "right", "top", "bottom"]: mc.add_theme_constant_override("margin_" + s, 16)
	var card := VBoxContainer.new(); card.add_theme_constant_override("separation", 12)
	if fit:
		mc.set_anchors_preset(Control.PRESET_FULL_RECT); o.add_child(mc)
		o.resized.connect(func(): _fit_margins(o))
	else:
		var sc := ScrollContainer.new(); sc.set_anchors_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; o.add_child(sc)
		var cc := CenterContainer.new(); cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.add_child(cc)
		cc.add_child(mc)
		card.custom_minimum_size.x = maxw
		o.resized.connect(func(): card.custom_minimum_size.x = minf(maxw, o.size.x - 32 - ins_l - ins_r))
	mc.add_child(card)
	o.set_meta("card", card); o.set_meta("mc", mc); o.set_meta("fit", fit); o.set_meta("maxw", maxw)
	add_child(o); overlays[nm] = o; o.visible = false
	return card

var ins_l := 0.0
var ins_t := 0.0
var ins_r := 0.0
var ins_b := 0.0

## Safe-area insets in UI units: HUD, side panel content and menu cards move in; backgrounds still bleed.
func set_insets(l: float, t: float, r: float, b: float) -> void:
	ins_l = l; ins_t = t; ins_r = r; ins_b = b
	_place_hud()
	for k in overlays:
		var o: Control = overlays[k]
		if not o.has_meta("mc"): continue   # the splash places itself
		var mc: MarginContainer = o.get_meta("mc")
		mc.add_theme_constant_override("margin_top", int(16 + t)); mc.add_theme_constant_override("margin_bottom", int(16 + b))
		if o.get_meta("fit"): _fit_margins(o)
		else:
			mc.add_theme_constant_override("margin_left", int(16 + l)); mc.add_theme_constant_override("margin_right", int(16 + r))
			var card: Control = o.get_meta("card"); card.custom_minimum_size.x = minf(o.get_meta("maxw"), o.size.x - 32 - l - r)

var panel_open := true

## Width the side panel takes out of the 3D view (0 when hidden: it folds down to the dock), safe-area margin included.
func panel_px() -> float:
	return 0.0

## Show or hide the side panel; the HUD and the 3D view's centre follow. Hidden, it folds down to the thumb dock.
func set_panel(_open: bool) -> void:
	panel_open = false; panel_top.visible = false   # the radial controls replaced the side column (2026-11-28)
	btn.panel.visible = false
	_place_hud()

## The side column goes on the right, or on the left for left-handed players; open it runs the full height, folded it
## is only as tall as the dock, at the bottom.
func _place_panel() -> void:
	var side := ins_l if left_hand else ins_r
	panel.anchor_left = 0.0 if left_hand else 1.0; panel.anchor_right = panel.anchor_left
	panel.offset_left = 0.0 if left_hand else -PANEL_W - side; panel.offset_right = PANEL_W + side if left_hand else 0.0
	panel.anchor_top = 0.0 if panel_open else 1.0; panel.anchor_bottom = 1.0
	panel.offset_bottom = 0.0; panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.grow_horizontal = Control.GROW_DIRECTION_END if left_hand else Control.GROW_DIRECTION_BEGIN
	panel.offset_top = 0.0 if panel_open else -panel.get_combined_minimum_size().y
	var ps := sb(C_PANEL, C_LINE, 0, 0, 8)
	if left_hand: ps.content_margin_left = 8 + side
	else: ps.content_margin_right = 8 + side
	ps.content_margin_top = 8 + (ins_t if panel_open else 0.0); ps.content_margin_bottom = 8 + ins_b
	panel.add_theme_stylebox_override("panel", ps)

func _place_hud() -> void:
	var pw := 0.0
	hud.offset_left = ins_l + (pw if left_hand else 0.0); hud.offset_top = ins_t
	hud.offset_right = -ins_r - (0.0 if left_hand else pw); hud.offset_bottom = -ins_b
	var dr: Control = hud.get_meta("draw")
	dr.offset_left = -hud.offset_left; dr.offset_top = -ins_t; dr.offset_right = -hud.offset_right; dr.offset_bottom = ins_b
	if panel != null: _place_panel()
	_place_radial()

func _fit_margins(o: Control) -> void:
	var mc: MarginContainer = o.get_meta("mc")
	var side := maxf(0.0, (o.size.x - 32 - ins_l - ins_r - float(o.get_meta("maxw"))) / 2)
	mc.add_theme_constant_override("margin_left", int(16 + ins_l + side)); mc.add_theme_constant_override("margin_right", int(16 + ins_r + side))

## Olive panel with brass corner brackets.
func frame(par: Control, sep := 10, accent := W_BRASS) -> VBoxContainer:
	var p := Frame.new(); p.accent = accent
	p.add_theme_stylebox_override("panel", cut(W_OLIVE, W_LINE, 1, 14, 16.0))
	par.add_child(p)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", sep); p.add_child(v)
	return v

func eyebrow(t: String, col := W_BRASS) -> Label:
	return lbl(t.to_upper(), f_wide, 11, col)

func title(t: String, size := 64) -> Label:
	return lbl(t.to_upper(), f_title, size, W_KHAKI)

func cta(t: String, cb: Callable) -> Button:
	var b := mkbtn(t, cb, 0, 52, 17)
	b.add_theme_stylebox_override("normal", cut(C_ACC, Color("ff8a7a"), 0))
	b.add_theme_stylebox_override("hover", cut(C_ACC.lightened(0.08), C_ACC, 0))
	b.add_theme_stylebox_override("pressed", cut(C_ACC.darkened(0.15), C_ACC, 0))
	b.add_theme_color_override("font_color", Color.WHITE); b.add_theme_font_override("font", f_title)
	var hz := Hazard.new(); hz.set_anchors_preset(Control.PRESET_FULL_RECT); hz.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(hz)
	return b

func ghost(t: String, cb: Callable, h := 44.0) -> Button:
	var b := mkbtn(t, cb, 0, h, 13)
	b.add_theme_font_override("font", f_wide)
	b.add_theme_stylebox_override("normal", cut(W_OLIVE2, W_LINE))
	b.add_theme_stylebox_override("hover", cut(W_OLIVE2.lightened(0.06), W_SAND))
	b.add_theme_stylebox_override("pressed", cut(W_OLIVE2.darkened(0.2), W_SAND))
	b.add_theme_color_override("font_color", W_KHAKI); b.add_theme_color_override("font_hover_color", W_KHAKI); b.add_theme_color_override("font_pressed_color", W_KHAKI)
	return b

func seg(par: Control, group: String, opts: Array, cur: String, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 6); par.add_child(h)
	seg_btns[group] = {}
	for o in opts:
		var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(80, 48)
		var v := VBoxContainer.new(); v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.set_anchors_preset(Control.PRESET_FULL_RECT); v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.offset_left = 6; v.offset_right = -6; v.add_theme_constant_override("separation", 1)
		var l := lbl(o[1].to_upper(), f_wide, 14, W_KHAKI); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(l)
		if o.size() > 2:
			var s := lbl(o[2], f_body, 11, W_SAND); s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(s)
			b.custom_minimum_size.y = 74
		b.add_child(v)
		b.pressed.connect(func(): _seg_pick(group, o[0]); cb.call(o[0]))
		h.add_child(b); seg_btns[group][o[0]] = b
	_seg_pick(group, cur)
	return h

func _seg_pick(group: String, val: String) -> void:
	for k in seg_btns[group]:
		var on: bool = k == val
		var b: Button = seg_btns[group][k]
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, cut(W_SEL if on else W_OLIVE2, C_ACC if on else (W_SAND if st == "hover" else W_LINE), 2 if on else 1, 7))

func _build_overlays() -> void:
	_wide_fonts()
	# ---- start: title on the left, orders dossier on the right
	var c := _overlay("start", 1010, true, true)
	var bar := HBoxContainer.new(); bar.add_theme_constant_override("separation", 10); c.add_child(bar)
	var rec := RecDot.new(); rec.custom_minimum_size = Vector2(14, 28); bar.add_child(rec)
	var hq := lbl("", f_wide, 12, W_SAND); bar.add_child(hq)
	var hfx := func(): hq.text = ["FIELD HQ  //  SABLE VALLEY  //  ALL FRONTS ACTIVE", "FIELD HQ  //  SABLE VALLEY  //  CONTACT INTERMITTENT", "FIELD HQ  //  SABLE VALLEY  //  NO SIGNAL FROM THE DEEP"][stage]
	hfx.call(); _stage_fx.append(hfx)
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bar.add_child(sp)
	# build number and self-update status (scripts/updater.gd); tap to check, restart or get the new app
	var up := Button.new(); up.flat = true; up.focus_mode = Control.FOCUS_NONE; up.add_theme_font_override("font", f_wide); up.add_theme_font_size_override("font_size", 12)
	up.custom_minimum_size.y = 28; up.pressed.connect(func(): Updater.act()); bar.add_child(up)
	var upd := func():
		up.text = Updater.label().to_upper()
		var col: Color = {"ready": C_AUR, "apk": C_AUR, "downloading": W_SAND, "checking": W_SAND, "offline": C_DIM, "off": C_DIM}.get(Updater.status, W_GREEN)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]: up.add_theme_color_override(k, col)
	Updater.changed.connect(upd); upd.call()
	# two columns that shrink to the screen: the title on the left, the two doors on the right
	var cols := HBoxContainer.new(); cols.add_theme_constant_override("separation", 28); cols.size_flags_vertical = Control.SIZE_EXPAND_FILL; c.add_child(cols)
	var lc := VBoxContainer.new(); lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lc.size_flags_stretch_ratio = 0.85; lc.add_theme_constant_override("separation", 12); cols.add_child(lc)
	lc.alignment = BoxContainer.ALIGNMENT_CENTER
	var ins := Insignia.new(); ins.custom_minimum_size = Vector2(84, 84); ins.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; lc.add_child(ins)
	var tl := VBoxContainer.new(); tl.add_theme_constant_override("separation", -16)
	var t1 := title("Aurite", 70); var t2 := lbl("FRONT", f_title, 70, C_ACC); tl.add_child(t1); tl.add_child(t2); lc.add_child(tl)
	_title_fx(t1, t2, false)
	var rule := Hazard.new(); rule.stripe = true; rule.custom_minimum_size = Vector2(0, 8); lc.add_child(rule)
	var fm := ghost("Field manual", func(): show_overlay("manual"), 48); fm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; fm.custom_minimum_size.x = 190; lc.add_child(fm)
	var rc := VBoxContainer.new(); rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL; rc.add_theme_constant_override("separation", 14); cols.add_child(rc)
	rc.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.camp_tile = _tile(rc, "Campaign", true, func(): main.show_campaigns())
	btn.sk_tile = _tile(rc, "Skirmish", false, func(): show_overlay("skirmish"))
	btn.sk_tile.get_meta("l1").text = "PICK YOUR ARMY AND THE ENEMY"
	btn.sk_tile.get_meta("l2").text = "Vanguard  ·  Ashen Pact  ·  Hollow Choir"; btn.sk_tile.get_meta("l2").visible = true
	var tk := Ticker.new(); tk.custom_minimum_size = Vector2(0, 30); tk.font = f_wide; tk.clip_contents = true; c.add_child(tk)
	# ---- campaigns: chapters stacked in one list that scrolls on its own
	c = _overlay("campaign", 1010, true, true)
	var ch := HBoxContainer.new(); ch.add_theme_constant_override("separation", 16); c.add_child(ch)
	var cb := ghost("Back", func(): main.show_start(), 44); cb.custom_minimum_size.x = 130; ch.add_child(cb)
	var chv := VBoxContainer.new(); chv.add_theme_constant_override("separation", -4); chv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ch.add_child(chv)
	chv.alignment = BoxContainer.ALIGNMENT_CENTER; chv.add_child(title("Campaigns", 30))
	# wipe the story progress: the first tap arms it, a second tap within 4 s does it
	var tr := ghost("Reset tutorial", func(): pass, 44); tr.custom_minimum_size.x = 170; ch.add_child(tr); btn.reset_tut = tr
	_two_tap(tr, "RESET TUTORIAL", "TAP AGAIN TO RESET", func(): main.tut.reset())
	var rb := ghost("Reset progress", func(): pass, 44); rb.custom_minimum_size.x = 170; ch.add_child(rb); btn.reset = rb
	rb.pressed.connect(func():
		if rb.has_meta("armed"):
			rb.remove_meta("armed"); rb.text = "RESET PROGRESS"
			for k in ["font_color", "font_hover_color", "font_pressed_color"]: rb.add_theme_color_override(k, W_KHAKI)
			main.reset_progress(); return
		rb.set_meta("armed", true); rb.text = "TAP AGAIN TO WIPE"
		for k in ["font_color", "font_hover_color", "font_pressed_color"]: rb.add_theme_color_override(k, Color("ff6a5c"))
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(rb) and rb.has_meta("armed"):
				rb.remove_meta("armed"); rb.text = "RESET PROGRESS"
				for k in ["font_color", "font_hover_color", "font_pressed_color"]: rb.add_theme_color_override(k, W_KHAKI)))
	camp_scroll = ScrollContainer.new(); camp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; camp_scroll.custom_minimum_size.y = 100
	var vsb := camp_scroll.get_v_scroll_bar(); vsb.custom_minimum_size.x = 6
	vsb.add_theme_stylebox_override("scroll", cut(Color(W_OLIVE2, 0.6), Color(0, 0, 0, 0), 0, 0, 0))
	for g in ["grabber", "grabber_highlight", "grabber_pressed"]: vsb.add_theme_stylebox_override(g, cut(W_BRASS if g != "grabber" else Color(W_BRASS, 0.7), Color(0, 0, 0, 0), 0, 0, 0))
	c.add_child(camp_scroll)
	camp_pane = VBoxContainer.new(); camp_pane.add_theme_constant_override("separation", 10); camp_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL; camp_scroll.add_child(camp_pane)
	# ---- skirmish setup
	c = _overlay("skirmish", 860)
	sk_pane = frame(c, 8)
	sk_pane.add_child(title("Skirmish", 30))
	sk_pane.add_child(eyebrow("Choose your army", W_SAND))
	seg(sk_pane, "fac", [["vanguard", "Vanguard"], ["ashen", "Ashen Pact"], ["choir", "Hollow Choir"]], "vanguard", func(f): main.sk_fac = f)
	sk_pane.add_child(eyebrow("Enemy army", W_SAND))
	seg(sk_pane, "enemy", [["random", "Random"], ["vanguard", "Vanguard"], ["ashen", "Ashen"], ["choir", "Choir"]], "random", func(f): main.sk_enemy = f)
	sk_pane.add_child(eyebrow("Enemy strength", W_SAND))
	seg(sk_pane, "diff", [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "normal", func(dd): main.diff = dd)
	var skr := HBoxContainer.new(); skr.add_theme_constant_override("separation", 8); sk_pane.add_child(skr)
	var dep := cta("Deploy", func(): main.play({"fac": main.sk_fac, "enemy": main.sk_enemy, "diff": main.diff})); dep.size_flags_horizontal = Control.SIZE_EXPAND_FILL; skr.add_child(dep)
	var sb2 := ghost("Back", func(): main.show_start(), 52); sb2.custom_minimum_size.x = 130; skr.add_child(sb2)
	# ---- field manual (controls)
	c = _overlay("manual", 640)
	var d := frame(c, 10)
	d.add_child(eyebrow("Field manual  //  standing orders"))
	d.add_child(title("Controls", 40))
	for row in [["TOUCH", "One thumb for the map, the other for the wheel in the corner. Drag to move the map, pinch to zoom (pinch far out for the radar: see RADAR) · tap a unit to select it, then tap the ground to move there or an enemy to attack it · swipe across your units, starting on one of them, to pick every unit your finger passes over (it works with units already selected too) · double-tap a unit to grab every unit of that type on screen · ✕ (N PICKED, over the wheel) deselects. The wheel sits bottom left, under the thumb that does not select (Pause > Wheel: right moves it)."], ["MOUSE", "Click to select or command, drag to box-select, double-click a unit for all of its type, right-drag to face a formation, middle-drag or WASD to scroll, wheel to zoom."], ["WHEEL", "The wheel in the corner: the middle is ATTACK while units are picked (tap it, then a spot: they fight their way there), or YARD (READY when a structure waits): it opens the Yard's menu by the shortcut column. Its first ring: your squads (ALL, 1 to 5; NEW, the units in no squad, is a plate over the wheel). Outer ring: the picked units' orders, STOP, HOLD (fight only what is in reach), NO FIRE, SCATTER, TO BASE, plus JUMP (Jump Troopers: tap where to land), STRIP (Scrappers strip wrecks instead of reviving them) or FUSE (Thralls)."], ["SHORTCUTS", "The column on the other side holds your producers (the Yard, Barracks, Workshop...): what each is making, its queue and READY. Tap one: its whole menu opens as the half ring (see MENUS), without moving the map or touching your selection, so you can queue while your army stays picked. Slide a finger along the half ring to turn it like a dial and bring the rest into view (the brass arc shows where you are; a chevron marks an end with more). Tap the shortcut again, or tap the map, to close it. A READY structure also drags straight off its shortcut onto the map."], ["MENUS", "Every structure's menu is the same big half ring beside the shortcut column. Tap one of your structures on the map: its half ring opens with what it makes and its orders (Rally: tap it, then where new units gather; Upgrade, Repair, Loop, Muster, Sell). Tap to order, hold a unit to order five, tap the ✕ or ×N badge to cancel one (or hold a structure). Slide along the arc to turn it; a READY structure comes first: drag it out and let go where it should stand (it is drawn above your finger). Tap the map to close it."], ["SQUADS", "Select two or more units and give them an order: they become a squad on the wheel's inner ring. Tap a squad to select it, tap again to jump to it (keys 1 to 5 on a keyboard). Order part of a squad to split it off, order whole squads together to merge them. NEW holds units in no squad; with a squad selected, JOIN sends them to it. ALL selects everyone without changing squads. A mixed selection shows its unit types over the wheel: tap one to keep only those. The objective folds away after a few seconds; tap OBJECTIVE to see it again."], ["RADAR", "Pinch far out: the whole map shows, units become icons and each squad a numbered badge (how many, their health, ! under fire). Tap badges to add their squads to the selection (tap again to drop one), then tap where they should go or what to attack. Drag a badge to send that squad alone. One finger drags a selection box (from one of your icons it swipes them up instead); two fingers pan and zoom. Pinch in to dive back down. Red rings mark fights."]]:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); d.add_child(h)
		var k := lbl(row[0], f_wide, 11, W_BRASS); k.custom_minimum_size.x = 60; h.add_child(k)
		var t := lbl(row[1], f_body, 13, Color("d6cfba")); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	var mrow := HBoxContainer.new(); mrow.add_theme_constant_override("separation", 8); d.add_child(mrow)
	var mb2 := ghost("Back", func(): show_overlay("start")); mb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mrow.add_child(mb2)
	var mu := ghost("Units and lessons", func(): main.tut.open_manual("manual")); mu.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mrow.add_child(mu)
	# ---- pause
	c = _overlay("menu", 400, false)
	d = frame(c, 10)
	var ph := HBoxContainer.new(); d.add_child(ph)
	var pv := VBoxContainer.new(); pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pv.add_theme_constant_override("separation", -2); ph.add_child(pv)
	pv.add_child(eyebrow("Operation paused")); pv.add_child(title("Stand by", 38))
	var st := Stamp.new(); st.text = "HOLD"; st.col = C_ACC; st.custom_minimum_size = Vector2(96, 52); ph.add_child(st)
	d.add_child(cta("Resume", func(): main.resume()))
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 8); d.add_child(r1)
	btn.sound = ghost("Sound: on", func(): main.toggle_sound()); btn.sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(btn.sound)
	btn.music = ghost("Music: on", func(): main.toggle_music()); btn.music.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(btn.music)
	btn.voice = ghost("Voice: on", func(): main.toggle_voice()); btn.voice.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r1.add_child(btn.voice)
	var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 8); d.add_child(r2)
	var rs := ghost("Restart", func(): main.restart()); rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r2.add_child(rs)
	var mm := ghost("Main menu", func(): main.quit_to_menu()); mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r2.add_child(mm)
	# tutorial (scripts/tutorial.gd): Full / Cards only / Off, and the unit pages of the field manual
	var r3 := HBoxContainer.new(); r3.add_theme_constant_override("separation", 8); d.add_child(r3)
	btn.tut_mode = ghost("Tutorial: full", func(): main.tut.cycle_mode()); btn.tut_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r3.add_child(btn.tut_mode)
	var fmu := ghost("Field manual", func(): main.tut.open_manual("menu")); fmu.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r3.add_child(fmu)
	# graphics level (scripts/gfx.gd): High, Medium, Low; main.cycle_gfx() rebuilds the battle at the new level
	var r4 := HBoxContainer.new(); r4.add_theme_constant_override("separation", 8); d.add_child(r4)
	btn.gfx = ghost("Graphics: high", func(): main.cycle_gfx()); btn.gfx.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r4.add_child(btn.gfx)
	# which side the buttons go: the other thumb has the map to itself
	btn.hand = ghost("Wheel: left", func(): main.toggle_hand()); btn.hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL; r4.add_child(btn.hand)
	# ---- end
	c = _overlay("end", 700)
	d = frame(c, 12)
	var eh := HBoxContainer.new(); d.add_child(eh)
	var ev := VBoxContainer.new(); ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL; ev.add_theme_constant_override("separation", -4); eh.add_child(ev)
	btn.end_eye = eyebrow("Operation complete"); ev.add_child(btn.end_eye)
	btn.end_title = title("Victory", 60); ev.add_child(btn.end_title)
	btn.end_stamp = Stamp.new(); btn.end_stamp.custom_minimum_size = Vector2(170, 70); eh.add_child(btn.end_stamp)
	btn.end_why = lbl("", f_body, 14, Color("ffb0a8")); btn.end_why.visible = false; d.add_child(btn.end_why)
	btn.end_debrief = VBoxContainer.new(); btn.end_debrief.add_theme_constant_override("separation", 8); btn.end_debrief.visible = false; d.add_child(btn.end_debrief)
	btn.end_stats = GridContainer.new(); btn.end_stats.columns = 5; btn.end_stats.add_theme_constant_override("h_separation", 8); btn.end_stats.add_theme_constant_override("v_separation", 8); d.add_child(btn.end_stats)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); d.add_child(row)
	btn.next = cta("Next mission", func(): main.next_mission()); btn.next.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.next)
	btn.again = cta("Play again", func(): main.play(main.last_opt)); btn.again.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(btn.again)
	var em := ghost("Main menu", func(): main.show_start(), 52); em.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(em)
	# ---- briefing dossier: story on the left, objectives on the right, then difficulty and the buttons
	c = _overlay("brief", 940)
	d = frame(c, 10)
	var bh := HBoxContainer.new(); d.add_child(bh)
	var bv := VBoxContainer.new(); bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bv.add_theme_constant_override("separation", -4); bh.add_child(bv)
	btn.br_eye = eyebrow("Mission 1"); btn.br_eye.add_theme_font_size_override("font_size", 13); bv.add_child(btn.br_eye)
	btn.br_title = title("Landfall", 40); bv.add_child(btn.br_title)
	var cl := Stamp.new(); cl.text = "CLASSIFIED"; cl.col = C_ACC; cl.custom_minimum_size = Vector2(170, 56); bh.add_child(cl)
	btn.br_theatre = lbl("", f_wide, 11, W_SAND); btn.br_theatre.visible = false; d.add_child(btn.br_theatre)
	var bc := HBoxContainer.new(); bc.add_theme_constant_override("separation", 16); d.add_child(bc)
	var bl := VBoxContainer.new(); bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bl.add_theme_constant_override("separation", 10); bc.add_child(bl)
	btn.br_text = lbl("", f_body, 15, Color("d6cfba")); btn.br_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; bl.add_child(btn.br_text)
	btn.br_heroes = VBoxContainer.new(); btn.br_heroes.add_theme_constant_override("separation", 6); bl.add_child(btn.br_heroes)
	var ob := PanelContainer.new(); ob.add_theme_stylebox_override("panel", _left_bar(W_BRASS)); ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bc.add_child(ob)
	var obv := VBoxContainer.new(); ob.add_child(obv); var oe := eyebrow("Objectives"); oe.add_theme_font_size_override("font_size", 13); obv.add_child(oe)
	btn.br_obj = lbl("", f_body, 15, W_KHAKI); btn.br_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; obv.add_child(btn.br_obj)
	row = HBoxContainer.new(); row.add_theme_constant_override("separation", 8); d.add_child(row)
	var lsg := seg(row, "level", [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "normal", func(l): main.set_camp_level(l))
	lsg.size_flags_horizontal = Control.SIZE_EXPAND_FILL; lsg.size_flags_stretch_ratio = 1.2
	btn.br_tips = ghost("Tutorial tips: on", func(): main.tut.toggle_tips(), 52); btn.br_tips.custom_minimum_size.x = 150; row.add_child(btn.br_tips)
	var go := cta("Begin", func(): main.begin_mission()); go.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(go)
	var bk := ghost("Back", func(): main.show_campaigns(), 52); bk.custom_minimum_size.x = 110; row.add_child(bk)

## A button that needs a second tap within 4 s to act (resets): the first tap turns it red and changes its words.
func _two_tap(b: Button, idle: String, armed: String, act: Callable) -> void:
	b.pressed.connect(func():
		if b.has_meta("armed"):
			b.remove_meta("armed"); b.text = idle
			for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, W_KHAKI)
			act.call(); return
		b.set_meta("armed", true); b.text = armed
		for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, Color("ff6a5c"))
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_instance_valid(b) and b.has_meta("armed"):
				b.remove_meta("armed"); b.text = idle
				for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, W_KHAKI)))

## Title treatment per stage: colours age, a hard drop shadow, and the TitleMark overlay (crack, crystals).
func _title_fx(a: Label, b: Label, center: bool) -> void:
	var fx := func():
		a.add_theme_color_override("font_color", [W_KHAKI, Color("c4bfae"), Color("a3aaa0")][stage])
		b.add_theme_color_override("font_color", [C_ACC, Color("b4453b"), Color("8e2a22")][stage])
	fx.call(); _stage_fx.append(fx)
	for l in [a, b]:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7)); l.add_theme_constant_override("shadow_offset_x", 0); l.add_theme_constant_override("shadow_offset_y", 5)
	var fs := a.get_theme_font_size("font_size")
	var m := TitleMark.new(); m.mouse_filter = Control.MOUSE_FILTER_IGNORE; m.center = center
	m.w = f_title.get_string_size("AURITE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x; m.lh = fs; m.b = b
	m.set_anchors_preset(Control.PRESET_FULL_RECT); a.add_child(m)

## Boot splash art (AF_MODE=splash renders it to res://splash.png).
func build_splash() -> void:
	# fixed, never scrolls: the art keeps its design size and is scaled down as a whole to fit short screens
	var o := Control.new(); o.name = "splash"; o.set_anchors_preset(Control.PRESET_FULL_RECT); o.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := WarBG.new(); bg.full = true; bg.hero = true; bg.t = 3.0; bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; o.add_child(bg)
	var c := VBoxContainer.new(); c.mouse_filter = Control.MOUSE_FILTER_IGNORE; c.custom_minimum_size.x = 720; o.add_child(c)
	add_child(o); overlays["splash"] = o; o.visible = false
	var fit := func():
		var ms := c.get_combined_minimum_size(); c.size = ms
		var k := minf(1.0, minf((o.size.x - 32 - ins_l - ins_r) / ms.x, (o.size.y - 32 - ins_t - ins_b) / ms.y))
		c.scale = Vector2.ONE * k; c.position = (o.size - ms * k) * 0.5
	o.resized.connect(fit); c.minimum_size_changed.connect(fit)
	c.alignment = BoxContainer.ALIGNMENT_CENTER; c.add_theme_constant_override("separation", 8)
	var ins := Insignia.new(); ins.custom_minimum_size = Vector2(150, 150); ins.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; c.add_child(ins)
	var e := eyebrow("Vanguard  vs  Ashen Pact"); e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; e.add_theme_font_size_override("font_size", 14); c.add_child(e)
	var tl := VBoxContainer.new(); tl.add_theme_constant_override("separation", -26); c.add_child(tl)
	var tw := []
	for w in [["AURITE", W_KHAKI], ["FRONT", C_ACC]]:
		var l := lbl(w[0], f_title, 110, w[1]); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; tl.add_child(l); tw.append(l)
	_title_fx(tw[0], tw[1], true)
	var hz := Hazard.new(); hz.stripe = true; hz.custom_minimum_size = Vector2(440, 10); hz.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; c.add_child(hz)
	var sub := lbl("", f_wide, 14, W_SAND); sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; c.add_child(sub)
	var fx := func():
		e.text = ["VANGUARD  VS  ASHEN PACT", "VANGUARD  VS  ASHEN PACT", "THE CHOIR IS SINGING"][stage]
		sub.text = ["THE WAR FOR AURITE", "THE GROUND IS LISTENING", "IT WAS NEVER OURS"][stage]
	fx.call(); _stage_fx.append(fx)

func show_overlay(nm: String) -> void:
	for k in overlays: overlays[k].visible = k == nm

func set_end_result(win: bool) -> void:
	btn.end_title.add_theme_color_override("font_color", W_KHAKI if win else C_ACC)
	btn.end_stamp.text = "SECURED" if win else "OVERRUN"
	btn.end_stamp.col = W_GREEN if win else C_ACC
	btn.end_stamp.queue_redraw()

const HERO_LINES := {
	"vey": "Pact commando. Arc carbine that jumps between targets.",
	"furnace": "Old Brann's arc tank, forged from a smelter.",
	"harrow": "Vanguard marksman. Rail rifle, long reach.",
	"saint": "Marshal Dace's command tank. Heavy twin cannon.",
	"cantor": "Voice of the Choir. Nearby allies fire faster and mend.",
	"deepmaw": "A beast of the deep caves. Crushes armour.",
}

func set_brief_heroes(list: Array, fac: String) -> void:
	for ch in btn.br_heroes.get_children(): ch.queue_free()
	btn.br_heroes.visible = list.size() > 0
	for h in list:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", cut(W_OLIVE2, W_BRASS, 1, 7, 7.0)); p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); p.add_child(v)
		var own: bool = D.UN[h].fac == fac
		v.add_child(lbl(("HERO  //  " if own else "ENEMY HERO  //  ") + D.UN[h].name.to_upper(), f_wide, 13, W_BRASS if own else C_ACC))
		if list.size() <= 2:   # three or more heroes: names only, so Begin stays on a phone screen
			var t := lbl(HERO_LINES.get(h, ""), f_body, 14, W_SAND); t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(t)
		btn.br_heroes.add_child(p)

## A big two-line door on the start screen (red for the main action).
func _tile(par: Control, t: String, main_action: bool, cb: Callable) -> Button:
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 96); b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 1.0; b.clip_contents = true
	var art := DoorArt.new(); art.main_action = main_action
	art.set_anchors_preset(Control.PRESET_FULL_RECT); art.mouse_filter = Control.MOUSE_FILTER_IGNORE; b.add_child(art)
	b.pressed.connect(cb)
	var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 20; h.offset_right = -16; h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 2); h.add_child(v)
	v.add_child(lbl(t.to_upper(), f_title, 30, Color.WHITE if main_action else W_KHAKI))
	var l1 := lbl("", f_wide, 14, W_SAND); v.add_child(l1)
	l1.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; l1.clip_text = true; l1.custom_minimum_size.x = 60
	var l2 := lbl("", f_body, 15, W_SAND); l2.visible = false; v.add_child(l2)
	b.set_meta("art", art)
	var ar := GoMark.new(); ar.main_action = main_action; ar.size_flags_vertical = Control.SIZE_SHRINK_CENTER; ar.custom_minimum_size = Vector2(58, 58); ar.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(ar)
	b.mouse_entered.connect(func(): ar.hot = true); b.mouse_exited.connect(func(): ar.hot = false)
	b.add_child(h); b.set_meta("l1", l1); b.set_meta("l2", l2)
	par.add_child(b)
	# the campaign door ages with the story: red, then rust, then near black with a green edge
	var fx := func():
		var bg: Color = [C_ACC.darkened(0.55), Color("3a1e19"), Color("0d1712")][stage] if main_action else W_OLIVE2
		var bd: Color = [C_ACC, Color("a8483c"), Color("3fbf7a")][stage] if main_action else W_LINE
		art.accent = bd if main_action else W_SAND
		b.add_theme_stylebox_override("normal", cut(bg, bd, 2 if main_action else 1, 12))
		b.add_theme_stylebox_override("hover", cut(bg.lightened(0.06), bd if main_action else W_SAND, 2 if main_action else 1, 12))
		b.add_theme_stylebox_override("pressed", cut(bg.darkened(0.2), W_SAND, 2, 12))
		l1.add_theme_color_override("font_color", [W_BRASS, Color("c9ae7e"), Color("8fe3b4")][stage] if main_action else W_SAND)
	fx.call(); _stage_fx.append(fx)
	return b

## Start screen campaign door: where the player left off.
func set_camp_tile(line1: String, line2: String) -> void:
	btn.camp_tile.get_meta("l1").text = line1.to_upper(); btn.camp_tile.get_meta("l2").text = line2
	btn.camp_tile.get_meta("l2").visible = true

## Campaign door art: the chapter numeral and one pip per mission, filled as they are won.
func set_camp_progress(num: String, done: int, total: int) -> void:
	var a: DoorArt = btn.camp_tile.get_meta("art"); a.num = num; a.done = done; a.total = total; a.queue_redraw()

## Every campaign as a chapter: a header, then its missions two to a row. rows: [{C, open, done}].
func render_campaigns(rows: Array, focus_id: String) -> void:
	for ch in camp_pane.get_children(): ch.queue_free()
	var focus: Control = null
	for r in rows:
		var C: Dictionary = r.C; var op: bool = r.open; var done: int = r.done if op else -1
		var hp := PanelContainer.new(); hp.add_theme_stylebox_override("panel", _left_bar(C_ACC if op else W_LINE)); camp_pane.add_child(hp)
		var hh := HBoxContainer.new(); hh.add_theme_constant_override("separation", 16); hp.add_child(hh)
		var num := lbl(C.num, f_title, 36, C_ACC if op else W_SAND); num.custom_minimum_size.x = 44; num.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hh.add_child(num)
		var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.add_theme_constant_override("separation", 0); hh.add_child(hv)
		hv.add_child(lbl(C.name.to_upper(), f_wide, 18, W_KHAKI))
		hv.add_child(lbl(D.FACS[C.fac].name.to_upper() + "  ·  " + ("%d OF %d SECURED" % [mini(done, C.missions.size()), C.missions.size()] if op else "WIN CAMPAIGN %s FIRST" % _prev_num(C.id)), f_wide, 13, W_BRASS if op else W_SAND))
		var op_id := Cutscenes.opening_of(C.id)
		if op and Cutscenes.has(op_id):
			var wb := mkbtn("Opening", func(): main.watch_cutscene(op_id), 0, 40, 12, "launch"); wb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hh.add_child(wb)
		var hs := Stamp.new(); hs.small = true; hs.custom_minimum_size = Vector2(120, 44); hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hs.text = "LOCKED" if not op else ("COMPLETE" if done >= C.missions.size() else ("IN PROGRESS" if done > 0 else "NEW"))
		hs.col = W_SAND if not op else (W_GREEN if done >= C.missions.size() else W_BRASS)
		hh.add_child(hs)
		if not op: hp.modulate.a = 0.7
		if C.id == focus_id and focus == null: focus = hp
		var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8); camp_pane.add_child(grid)
		for i in C.missions.size():
			var b := _mission_btn(C, i, done)
			grid.add_child(b)
			if C.id == focus_id and i == done: focus = b
		var gap := Control.new(); gap.custom_minimum_size.y = 6; camp_pane.add_child(gap)
	if focus: _show_next.call_deferred(focus)

## Roman number of the campaign before this one ("I" for campaign II).
func _prev_num(id: String) -> String:
	for i in range(1, D.CAMPAIGNS.size()):
		if D.CAMPAIGNS[i].id == id: return D.CAMPAIGNS[i - 1].num
	return ""

func _mission_btn(C: Dictionary, i: int, done: int) -> Button:
	var m: Dictionary = C.missions[i]
	var b := Button.new(); b.focus_mode = Control.FOCUS_NONE; b.custom_minimum_size = Vector2(0, 64); b.disabled = i > done; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nx: bool = i == done
	b.add_theme_stylebox_override("normal", cut(W_SEL if nx else W_OLIVE2, C_ACC if nx else W_LINE, 2 if nx else 1, 9))
	b.add_theme_stylebox_override("hover", cut(W_SEL if nx else W_OLIVE2, W_SAND, 1, 9))
	b.add_theme_stylebox_override("pressed", cut(W_OLIVE2.darkened(0.2), W_SAND, 1, 9))
	b.add_theme_stylebox_override("disabled", cut(Color(W_OLIVE2, 0.45), Color(W_LINE, 0.45), 1, 9))
	var h := HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_left = 12; h.offset_right = -10; h.add_theme_constant_override("separation", 10); h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := lbl("%02d" % (i + 1), f_title, 22, C_ACC if nx else W_SAND); n.custom_minimum_size.x = 38; n.size_flags_vertical = Control.SIZE_SHRINK_CENTER; h.add_child(n)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.alignment = BoxContainer.ALIGNMENT_CENTER; v.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_theme_constant_override("separation", 1)
	var t := lbl(m.title.to_upper(), f_wide, 14, W_KHAKI); t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; t.clip_text = true; v.add_child(t)
	var tg := lbl(m.tag, f_body, 14, W_SAND); tg.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; tg.clip_text = true; v.add_child(tg)
	h.add_child(v)
	var st := Stamp.new(); st.small = true; st.custom_minimum_size = Vector2(98, 38); st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.text = "SECURED" if i < done else ("ORDERS IN" if nx else "CLASSIFIED")
	st.col = W_GREEN if i < done else (W_BRASS if nx else W_SAND)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE; h.add_child(st)
	if i > done: h.modulate.a = 0.45
	b.add_child(h)
	# PASS lets a drag that starts on a mission scroll the list; a press that scrolled is not a tap
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.button_down.connect(func(): press_scroll = camp_scroll.scroll_vertical)
	b.pressed.connect(func(): if absi(camp_scroll.scroll_vertical - press_scroll) < 8: main.camp_id = C.id; main.open_brief(i))
	return b

func _show_next(b: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(b): camp_scroll.ensure_control_visible(b)

func set_end_stats(rows: Array) -> void:
	for ch in btn.end_stats.get_children(): ch.queue_free()
	for r in rows:
		var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", cut(W_OLIVE2, W_LINE, 1, 7)); p.custom_minimum_size.x = 118; p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); p.add_child(v)
		v.add_child(lbl(r[0].to_upper(), f_wide, 9, W_SAND)); v.add_child(lbl(str(r[1]), f_title, 20, W_KHAKI))
		btn.end_stats.add_child(p)

func tick(dt: float) -> void:
	_radio_tick(dt)
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0: toast_box.visible = false
	hud.get_meta("draw").queue_redraw()

# ---------------- custom controls ----------------
## Menu backdrop: a dusk battlefield (ridges, tank silhouettes, searchlights, shell flashes,
## smoke, embers, wire). Without `full` it is only a dark veil over the paused game.
class WarBG extends Control:
	var full := true
	var hero := false   # splash art: crossed searchlights, big tanks in the foreground, frozen frame
	var icon := false   # app icon backdrop: sky, glow, searchlights and ridges only (small sizes read cleanly)
	var t := 0.0
	# per UI.stage: sky top, sky mid, horizon, ground, far ridge, mid ridge, near earth, glow colour
	const PAL := [
		["0b0a08", "1a100c", "5a1f10", "140b08", "2c1610", "0f0907", "060403", Color(1.0, 0.42, 0.14)],
		["08090b", "121518", "2a2d2c", "0d0e0e", "1c1e1e", "0b0c0c", "040505", Color(0.80, 0.66, 0.48)],
		["020304", "050c09", "0c3020", "040706", "0a1310", "050908", "020303", Color(0.25, 1.0, 0.6)],
	]
	func _process(dt: float) -> void:
		if full and not hero and is_visible_in_tree():
			t += dt; queue_redraw()
	static func _h(i: float) -> float:
		return fposmod(sin(i * 127.1 + 311.7) * 43758.5453, 1.0)
	func _ridge(x: float, base: float, amp: float, sd: float, u: float) -> float:
		var q := x / u
		return base - amp * (sin(q * 0.006 + sd) * 0.55 + sin(q * 0.017 + sd * 2.3) * 0.3 + sin(q * 0.043 + sd * 4.1) * 0.15)
	func _band(y0: Callable, col: Color, step: float) -> void:
		var pts := PackedVector2Array(); var x := 0.0
		while x <= size.x + step:
			pts.append(Vector2(x, y0.call(x))); x += step
		pts.append(Vector2(size.x + step, size.y)); pts.append(Vector2(0, size.y))
		draw_colored_polygon(pts, col)
	## Thin light line along the top of a ridge: rim light from the horizon behind it.
	func _rim(y0: Callable, col: Color, step: float, w: float) -> void:
		var pts := PackedVector2Array(); var x := 0.0
		while x <= size.x + step:
			pts.append(Vector2(x, y0.call(x))); x += step
		draw_polyline(pts, col, w, true)
	func _grad(r: Rect2, top: Color, bot: Color) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	func _tank(p: Vector2, u: float, col: Color, flip := false, ang := 0.0) -> void:
		draw_set_transform(p, ang, Vector2(-u if flip else u, u))
		draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(31, -6), Vector2(25, -11), Vector2(-25, -11), Vector2(-31, -6)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(-13, -11), Vector2(12, -11), Vector2(9, -19), Vector2(-9, -19)]), col)
		draw_rect(Rect2(8, -16.5, 30, 3), col)
		draw_line(Vector2(-6, -19), Vector2(-9, -30), col, 1.2)
		draw_set_transform(Vector2.ZERO)
	## A knocked-out tank: hull nose-down, turret thrown off, barrel bent.
	func _wreck(p: Vector2, u: float, col: Color, flip := false, ang := 0.0) -> void:
		draw_set_transform(p, ang, Vector2(-u if flip else u, u))
		draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(31, -6), Vector2(25, -11), Vector2(-25, -11), Vector2(-31, -6)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -11), Vector2(-4, -15), Vector2(2, -11)]), col)
		draw_set_transform(p + Vector2(34 * u * (-1 if flip else 1), 3 * u), ang + 0.9, Vector2(-u if flip else u, u))
		draw_colored_polygon(PackedVector2Array([Vector2(-13, 0), Vector2(12, 0), Vector2(9, -8), Vector2(-9, -8)]), col)
		draw_polyline(PackedVector2Array([Vector2(10, -5), Vector2(26, -6), Vector2(36, 2)]), col, 3.0)
		draw_set_transform(Vector2.ZERO)
	## Crystal spire silhouette with a lit green edge.
	func _spire(b: Vector2, h: float, w: float, ang: float, col: Color, lit: Color) -> void:
		var d := Vector2(sin(ang), -cos(ang)); var pp := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([b + pp * w, b + d * h * 0.8 + pp * w * 0.8, b + d * h, b + d * h * 0.75 - pp * w * 0.9, b - pp * w])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([b + pp * w * 0.15, b + d * h * 0.8 + pp * w * 0.1, b + d * h]), lit, maxf(1.0, w * 0.08), true)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), Color(lit, lit.a * 0.6), maxf(1.0, w * 0.06), true)
	func _draw() -> void:
		var s := size
		if not full:
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.035, 0.025, 0.72))
			return
		var st: int = UI.stage; var P: Array = PAL[st]; var gc: Color = P[7]
		var u := s.y / 486.0
		var hz := s.y * 0.62
		# sky
		_grad(Rect2(0, 0, s.x, hz * 0.55), Color(P[0]), Color(P[1]))
		_grad(Rect2(0, hz * 0.55, s.x, hz * 0.45 + 2), Color(P[1]), Color(P[2]))
		draw_rect(Rect2(0, hz, s.x, s.y - hz), Color(P[3]))
		# a broad smooth glow sitting on the horizon
		UI.glow(self, Vector2(s.x * 0.5, hz), Vector2(s.x * 0.75, s.y * (0.22 if st < 2 else 0.32)), Color(gc, [0.30, 0.12, 0.24][st]))
		if icon: UI.glow(self, Vector2(s.x * 0.5, s.y * 0.6), Vector2(s.x * 0.6, s.y * 0.45), Color(gc, [0.45, 0.2, 0.4][st]))
		# cloud banks lit from below
		for i in 9:
			var cx := fposmod(s.x * _h(i + 80) + t * (3 + 2 * _h(i + 81)) * u, s.x + 600 * u) - 300 * u
			var cy := s.y * (0.12 + 0.32 * _h(i + 82)); var cw := (220 + 260 * _h(i + 83)) * u
			var ca: float = [0.10, 0.16, 0.10][st]
			UI.glow(self, Vector2(cx, cy), Vector2(cw, cw * 0.16), Color(Color(P[1]).darkened(0.5), 0.6))
			UI.glow(self, Vector2(cx, cy + cw * 0.07), Vector2(cw * 0.8, cw * 0.07), Color(gc, ca * (cy / hz)))
		if st == 2:
			# aurora: slow green curtains over the night sky
			for b in 3:
				var pts := PackedVector2Array(); var cols := PackedColorArray(); var x := -20.0
				while x <= s.x + 40:
					var yy := s.y * (0.16 + 0.07 * b) + sin(x / (180.0 * u) + t * 0.15 + b * 1.7) * 18 * u + sin(x / (61.0 * u) + b) * 6 * u
					pts.append(Vector2(x, yy)); cols.append(Color(gc, 0.0))
					x += 20
				var n := pts.size()
				for k in range(n - 1, -1, -1):
					pts.append(pts[k] + Vector2(0, (70 + 30 * b) * u)); cols.append(Color(gc, 0.07 * (0.6 + 0.4 * sin(pts[k].x / (90.0 * u) + t * 0.4 + b))))
				draw_polygon(pts, cols)
		# map grid
		var g := 46.0 * u; var x := 0.0
		while x < s.x:
			draw_line(Vector2(x, 0), Vector2(x, s.y), Color(0.85, 0.8, 0.64, 0.025), 1.0); x += g
		var y := 0.0
		while y < s.y:
			draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.85, 0.8, 0.64, 0.025), 1.0); y += g
		# fires behind the far ridge: four in the first war, two dying ones later, none at the end
		var nf: int = [4, 2, 0][st]
		for i in nf:
			var fx := s.x * (0.18 + 0.23 * i + 0.05 * _h(i + 3)) if st == 0 else s.x * (0.27 + 0.48 * i)
			var fl := 0.85 + 0.15 * sin(t * (2.0 + i) + i)
			UI.glow(self, Vector2(fx, hz), Vector2(190, 70) * u * fl, Color(gc, 0.55 if st == 0 else 0.25))
			UI.glow(self, Vector2(fx, hz - 4 * u), Vector2(60, 22) * u * fl, Color(1, 0.8, 0.5, 0.45 if st == 0 else 0.15))
		# searchlights: two sweeping, then one stuttering, then dark
		var nl: int = [2, 1, 0][st]
		for i in nl:
			var o := Vector2(s.x * (0.58 + 0.3 * i), hz + 26 * u)
			var a := -PI / 2 + sin(t * (0.23 + 0.07 * i) + i * 2.0) * 0.6
			var al := 0.16
			if st == 1: al = 0.10 * (0.4 + 0.6 * float(int(t * 9.0) % 7 != 0)); a = -PI / 2 - 0.35
			if hero:
				o = Vector2(s.x * (0.3 + 0.4 * i), hz + 30 * u); a = -PI / 2 + (0.42 if i == 0 else -0.42); al = 0.2
				if st == 1: o = Vector2(s.x * 0.66, hz + 30 * u); a = -PI / 2 - 0.5; al = 0.12
			var L := s.y * 1.1; var w := 0.07
			var lc := Color(1, 0.93, 0.75) if st == 0 else Color(0.85, 0.9, 0.95)
			draw_polygon(PackedVector2Array([o, o + Vector2(cos(a - w), sin(a - w)) * L, o + Vector2(cos(a + w), sin(a + w)) * L]),
				PackedColorArray([Color(lc, al), Color(lc, 0.0), Color(lc, 0.0)]))
			UI.glow(self, o, Vector2(26, 26) * u, Color(lc, al * 2.5))
		if hero and st == 0:
			for fx in [0.12, 0.88]:
				UI.glow(self, Vector2(s.x * fx, hz - 4 * u), Vector2(110, 110) * u, Color(1, 0.55, 0.2, 0.35))
				UI.glow(self, Vector2(s.x * fx, hz - 4 * u), Vector2(36, 36) * u, Color(1, 0.85, 0.55, 0.55))
		# shell bursts and tracers (the first war is loud)
		var nb: int = [3, 1, 0][st]
		for i in nb:
			var ph := t * 0.55 + i * 0.37; var k := floorf(ph); var f := ph - k
			if f < 0.3:
				var bx := s.x * (0.08 + 0.84 * _h(k * 3.0 + i)); var e := 1.0 - f / 0.3
				UI.glow(self, Vector2(bx, hz - 6 * u), Vector2.ONE * 70 * u * (0.4 + f * 2), Color(1, 0.6, 0.25, 0.30 * e))
				UI.glow(self, Vector2(bx, hz - 6 * u), Vector2.ONE * 20 * u * (0.5 + f * 2), Color(1, 0.9, 0.6, 0.7 * e))
		# far ridge
		var far := func(px): return _ridge(px + 300, hz + 4 * u, 22 * u, 1.3, u)
		var fc := Color(P[4])
		if st == 2:
			# crystal spires rising behind the ridge, lit from the green horizon
			for i in 7:
				var sx := s.x * (0.06 + 0.14 * i + 0.05 * _h(i + 120)); var sy: float = far.call(sx) + 6 * u
				var hh := (60 + 150 * _h(i + 121)) * u * (1.4 if i == 4 else 1.0)
				UI.glow(self, Vector2(sx, sy - hh * 0.5), Vector2(hh * 0.45, hh * 0.7), Color(gc, 0.10))
				_spire(Vector2(sx, sy), hh, (10 + 10 * _h(i + 122)) * u, (_h(i + 123) - 0.5) * 0.5, fc, Color(gc, 0.55))
				_spire(Vector2(sx + 16 * u, sy), hh * 0.55, 7 * u, 0.35, fc, Color(gc, 0.4))
		_band(far, fc, 8)
		_rim(far, Color(gc, [0.25, 0.10, 0.35][st]), 8, 1.5 * u)
		var mx := s.x * 0.7; var my: float = far.call(mx)
		if icon: pass
		elif st == 0:
			draw_line(Vector2(mx, my), Vector2(mx, my - 54 * u), fc, 2.0 * u)
			draw_line(Vector2(mx - 10 * u, my), Vector2(mx, my - 54 * u), fc, 1.0 * u)
			draw_line(Vector2(mx + 10 * u, my), Vector2(mx, my - 54 * u), fc, 1.0 * u)
			if hero or int(t * 1.2) % 2 == 0:
				draw_circle(Vector2(mx, my - 56 * u), 2.2 * u, Color(1, 0.25, 0.2, 0.9))
				UI.glow(self, Vector2(mx, my - 56 * u), Vector2.ONE * 12 * u, Color(1, 0.25, 0.2, 0.5))
		elif st == 1:
			# the mast is down, folded over the ridge; something green glints near its foot
			var top := Vector2(mx + 40 * u, my - 22 * u)
			draw_line(Vector2(mx, my), Vector2(mx + 8 * u, my - 30 * u), fc, 2.0 * u)
			draw_line(Vector2(mx + 8 * u, my - 30 * u), top, fc, 2.0 * u)
			draw_line(Vector2(mx - 10 * u, my), Vector2(mx + 8 * u, my - 30 * u), fc, 1.0 * u)
			var gp := Vector2(s.x * 0.41, float(far.call(s.x * 0.41)) + 2 * u)
			UI.glow(self, gp, Vector2(40, 22) * u, Color(0.3, 1.0, 0.6, 0.28 + 0.06 * sin(t * 1.3)))
			_spire(gp + Vector2(0, 2 * u), 26 * u, 4 * u, 0.2, fc, Color(0.4, 1.0, 0.7, 0.7))
			_spire(gp + Vector2(6 * u, 2 * u), 14 * u, 3 * u, -0.3, fc, Color(0.4, 1.0, 0.7, 0.5))
		# drifting smoke: thicker and greyer as the war drags on
		var ns: int = [7, 12, 6][st]
		var smc: Color = [Color(0.22, 0.15, 0.12, 0.10), Color(0.16, 0.17, 0.17, 0.16), Color(0.05, 0.12, 0.09, 0.14)][st]
		for i in ns:
			var sx := fposmod(s.x * _h(i + 10) - t * (8 + 6 * _h(i)) * u, s.x + 400 * u) - 200 * u
			var sy := hz - (10 + 70 * _h(i + 20)) * u
			for k in 3:
				UI.glow(self, Vector2(sx + k * 40 * u, sy - k * 6 * u), Vector2(1.6, 0.9) * (70 + 30 * k) * u, smc)
		# mid ridge with an armored column (or what is left of it)
		var mid := func(px): return _ridge(px, hz + 46 * u, 26 * u, 4.2, u)
		var mc := Color(P[5])
		_band(mid, mc, 8)
		_rim(mid, Color(gc, [0.16, 0.07, 0.2][st]), 8, 1.2 * u)
		for i in 4:
			var tx := fposmod(s.x * [0.03, 0.13, 0.80, 0.91][i] + (t * 4 * u if st == 0 else 0.0), s.x + 80 * u) - 40 * u
			var ty: float = mid.call(tx)
			var slope := atan2(float(mid.call(tx + 10)) - ty, 10.0)
			if icon: continue
			if st == 0 or (st == 1 and i != 2):
				_tank(Vector2(tx, ty + 2 * u), u * (1.0 - 0.1 * (i % 2)), mc, false, slope)
			else:
				_wreck(Vector2(tx, ty + 5 * u), u * (1.0 - 0.1 * (i % 2)), mc, i % 2 == 1, slope + (0.18 if i % 2 == 0 else -0.14))
				if st == 1:
					# the burning wreck: a low fire and a column of smoke leaning with the wind
					UI.glow(self, Vector2(tx, ty - 6 * u), Vector2(40, 22) * u, Color(1, 0.55, 0.2, 0.35 + 0.1 * sin(t * 6)))
					for k in 6:
						var ff := fposmod(t * 0.15 + k / 6.0, 1.0)
						UI.glow(self, Vector2(tx + ff * 70 * u, ty - 10 * u - ff * 150 * u), Vector2.ONE * (14 + 50 * ff) * u, Color(0.12, 0.12, 0.12, 0.35 * (1.0 - ff)))
		if st == 2:
			for i in 5:
				var cx := s.x * (0.22 + 0.15 * i + 0.04 * _h(i + 140)); var cy: float = mid.call(cx) + 4 * u
				UI.glow(self, Vector2(cx, cy - 10 * u), Vector2(40, 30) * u, Color(gc, 0.16))
				_spire(Vector2(cx, cy), (22 + 30 * _h(i + 141)) * u, 5 * u, (_h(i + 142) - 0.5) * 0.9, mc, Color(gc, 0.7))
		# foreground: earth, tank traps and barbed wire
		var near := func(px): return _ridge(px + 900, s.y * 0.9, 16 * u, 7.7, u)
		var nc := Color(P[6])
		_band(near, nc, 8)
		_rim(near, Color(gc, [0.10, 0.05, 0.14][st]), 8, 1.0 * u)
		var px := 30.0 * u; var prev := Vector2(-1, -1); var idx := 0
		while px < s.x + 80 * u and not icon:
			var py: float = near.call(px)
			var lean := 0.0 if st == 0 else (_h(px + 7) - 0.5) * (0.35 if st == 1 else 0.7)
			var top := Vector2(px, py) + Vector2(sin(lean), -cos(lean)) * 30 * u
			var broken := st == 2 and _h(px + 3) > 0.45 or st == 1 and _h(px + 3) > 0.8
			draw_line(Vector2(px, py + 4 * u), top, nc, 3.0 * u)
			if prev.x >= 0 and not broken:
				var pts := PackedVector2Array()
				for k in 13:
					var f2 := k / 12.0
					pts.append(prev.lerp(top, f2) + Vector2(0, sin(f2 * PI) * (7 + 10 * st) * u))
				draw_polyline(pts, nc, 1.4 * u)
				for k in range(1, 12, 2):
					var bp := pts[k]
					draw_line(bp + Vector2(-3, -3) * u, bp + Vector2(3, 3) * u, nc, 1.0 * u)
			elif prev.x >= 0:
				# snapped wire hanging from the post
				draw_polyline(PackedVector2Array([top, top + Vector2(-12, 14) * u, top + Vector2(-18, 30) * u]), nc, 1.4 * u)
			prev = top
			if _h(px) > 0.55:
				var hx := px + 40 * u; var hy: float = near.call(hx)
				draw_line(Vector2(hx - 10 * u, hy), Vector2(hx + 10 * u, hy - 18 * u), nc, 2.5 * u)
				draw_line(Vector2(hx + 10 * u, hy), Vector2(hx - 10 * u, hy - 18 * u), nc, 2.5 * u)
				draw_line(Vector2(hx, hy + 2 * u), Vector2(hx + 2 * u, hy - 20 * u), nc, 2.5 * u)
			if st == 2 and idx % 3 == 1:
				var cx := px + 70 * u; var cy: float = near.call(cx) + 6 * u
				UI.glow(self, Vector2(cx, cy - 18 * u), Vector2(60, 40) * u, Color(gc, 0.2))
				_spire(Vector2(cx, cy), (40 + 50 * _h(px + 9)) * u, 9 * u, (_h(px + 11) - 0.5) * 0.8, nc, Color(gc, 0.8))
				_spire(Vector2(cx + 12 * u, cy), (20 + 20 * _h(px + 13)) * u, 6 * u, 0.5, nc, Color(gc, 0.6))
			px += 120 * u; idx += 1
		if hero and not icon:
			for tk in [[0.84, 3.4, true, 0.06], [0.15, 2.4, false, -0.04]]:
				var tp := Vector2(s.x * tk[0], float(near.call(s.x * tk[0])) + 6 * u)
				if st == 0:
					_tank(tp + Vector2(0, -2.5 * u), tk[1] * u, Color(1.0, 0.45, 0.15, 0.6), tk[2], tk[3])
					_tank(tp, tk[1] * u, nc, tk[2], tk[3])
				elif st == 1:
					_tank(tp + Vector2(0, -2.0 * u), tk[1] * u, Color(0.75, 0.78, 0.8, 0.25), tk[2], tk[3])
					_tank(tp, tk[1] * u, nc, tk[2], tk[3])
				else:
					_wreck(tp + Vector2(0, -2.0 * u), tk[1] * u, Color(gc, 0.35), tk[2], tk[3] + 0.12)
					_wreck(tp, tk[1] * u, nc, tk[2], tk[3] + 0.12)
		# particles: embers rising, then ash falling, then aurite motes drifting up
		if st == 0:
			for i in 46:
				var sp := (14 + 22 * _h(i + 40)) * u
				var ey := s.y - fposmod(t * sp + _h(i + 50) * s.y, s.y * 0.85)
				var ex := s.x * _h(i + 60) + sin(t * 0.8 + i) * 14 * u
				var life := (s.y - ey) / (s.y * 0.85)
				var ec := Color(1, 0.55 + 0.3 * _h(i), 0.2, 0.8 * (1.0 - life))
				draw_circle(Vector2(ex, ey), (1.0 + _h(i + 70) * 1.4) * u, ec)
				if _h(i + 75) > 0.6: UI.glow(self, Vector2(ex, ey), Vector2.ONE * 7 * u, Color(ec, ec.a * 0.4))
		elif st == 1:
			for i in 70:
				var sp := (6 + 10 * _h(i + 40)) * u
				var ey := fposmod(t * sp + _h(i + 50) * s.y, s.y)
				var ex := fposmod(s.x * _h(i + 60) + sin(t * 0.5 + i) * 20 * u - t * 6 * u, s.x)
				var r := (0.8 + _h(i + 70) * 1.6) * u
				draw_set_transform(Vector2(ex, ey), t * (0.5 + _h(i)) + i, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, r, Color(0.72, 0.72, 0.7, 0.35 + 0.3 * _h(i + 77)))
				draw_set_transform(Vector2.ZERO)
		else:
			for i in 38:
				var sp := (4 + 8 * _h(i + 40)) * u
				var ey := s.y - fposmod(t * sp + _h(i + 50) * s.y, s.y * 0.9)
				var ex := s.x * _h(i + 60) + sin(t * 0.3 + i) * 10 * u
				var life := (s.y - ey) / (s.y * 0.9)
				var al := sin(PI * life) * (0.5 + 0.5 * _h(i + 71))
				var r := (1.5 + 2.5 * _h(i + 70)) * u; var c := Vector2(ex, ey)
				UI.glow(self, c, Vector2.ONE * r * 5, Color(gc, 0.25 * al))
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.8), c + Vector2(r * 0.7, 0), c + Vector2(0, r * 1.8), c + Vector2(-r * 0.7, 0)]), Color(0.7, 1.0, 0.85, 0.85 * al))
			# low fog hugging the ground
			for i in 6:
				var fx := fposmod(s.x * _h(i + 160) + t * 5 * u, s.x + 600 * u) - 300 * u
				UI.glow(self, Vector2(fx, s.y * (0.82 + 0.08 * _h(i + 161))), Vector2(320, 50) * u, Color(0.1, 0.25, 0.18, 0.18))
		# vignette, darker on the left behind the title
		_grad(Rect2(0, 0, s.x, s.y * 0.25), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0))
		_grad(Rect2(0, s.y * 0.8, s.x, s.y * 0.2), Color(0, 0, 0, 0), Color(0, 0, 0, 0.5))
		if not hero:
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.5, 0), Vector2(s.x * 0.5, s.y), Vector2(0, s.y)]),
				PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45)]))

## Panel with brass L-brackets in its corners.
class Frame extends PanelContainer:
	var accent := Color("d9a441")
	func _draw() -> void:
		var r := Rect2(Vector2(-3, -3), size + Vector2(6, 6)); var L := 16.0; var w := 2.0
		for c in [[r.position, Vector2(1, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 1)], [r.end, Vector2(-1, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, -1)]]:
			var p: Vector2 = c[0]; var d: Vector2 = c[1]
			draw_line(p, p + Vector2(d.x * L, 0), accent, w); draw_line(p, p + Vector2(0, d.y * L), accent, w)

## Rubber stamp: rotated double-ruled box with a word in it.
class Stamp extends Control:
	var text := "CLASSIFIED"
	var col := Color("e5483f")
	var small := false
	func _draw() -> void:
		var f: Font = load("res://fonts/chakra-petch-latin-700-normal.woff2")
		var fs := 11 if small else 18
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bw := tw + (14.0 if small else 24.0); var bh := fs + (10.0 if small else 18.0)
		draw_set_transform(size / 2, -0.12 if small else -0.16)
		var r := Rect2(-bw / 2, -bh / 2, bw, bh); var c := Color(col, 0.85)
		draw_rect(r, c, false, 2.0)
		if not small: draw_rect(r.grow(-4), Color(col, 0.6), false, 1.0)
		draw_string(f, Vector2(-tw / 2, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		draw_set_transform(Vector2.ZERO)

## Hazard stripes: along the bottom of a button, or as a full strip when `stripe`.
class Hazard extends Control:
	var stripe := false
	func _draw() -> void:
		var h := size.y if stripe else 5.0
		var y0 := 0.0 if stripe else size.y - h
		var x := -h; var i := 0
		var st: int = UI.stage if stripe else 0
		var a: Color = [Color("d9a441", 0.9), Color("a88d55", 0.75), Color("5b4a30", 0.6)][st] if stripe else Color(0, 0, 0, 0.35)
		while x < size.x:
			var wear := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			if i % 2 == 0 and not (st == 1 and wear > 0.86) and not (st == 2 and wear > 0.6):
				a.a = [0.9, 0.5 + 0.35 * wear, 0.35 + 0.4 * wear][st] if stripe else 0.35
				var pts := PackedVector2Array([Vector2(x, y0 + h), Vector2(x + h, y0), Vector2(x + 2 * h, y0), Vector2(x + h, y0 + h)])
				for k in pts.size(): pts[k].x = clampf(pts[k].x, 0, size.x)
				draw_colored_polygon(pts, a)
			x += h; i += 1
		if stripe: draw_rect(Rect2(0, 0, size.x, h), Color("d9a441", 0.25), false, 1.0)

## Unit insignia: a riveted brass shield with three chevrons and a star.
## UI.stage ages it with the campaign: 0 polished, 1 tarnished and cracked with aurite glinting through, 2 split open by crystals.
class Insignia extends Control:
	var chunky := false   # app icon: thick rim, bigger star, no fine detail, so it reads at launcher size
	var clip := PackedVector2Array()   # when set, every fill is cut to this shape (stage 2 draws each half on its own)
	const SH := [Vector2(0.5, 0), Vector2(1, 0.14), Vector2(0.92, 0.66), Vector2(0.5, 1), Vector2(0.08, 0.66), Vector2(0, 0.14)]
	const LIGHT := Vector2(-0.55, -0.83)
	const CRACK := [Vector2(0.78, 0.12), Vector2(0.69, 0.22), Vector2(0.74, 0.31), Vector2(0.57, 0.45), Vector2(0.62, 0.55), Vector2(0.45, 0.70), Vector2(0.50, 0.80), Vector2(0.40, 0.90)]
	const SPLIT := [Vector2(0.60, -0.3), Vector2(0.58, 0.04), Vector2(0.65, 0.17), Vector2(0.52, 0.35), Vector2(0.58, 0.47), Vector2(0.44, 0.66), Vector2(0.50, 0.79), Vector2(0.41, 1.3)]
	func _fill(p: PackedVector2Array, col: Color) -> void:
		var qs: Array = [p] if clip.is_empty() else Geometry2D.intersect_polygons(p, clip)
		for q: PackedVector2Array in qs:
			draw_colored_polygon(q, col)
			# polygons are not antialiased: a 1px smooth outline in the same colour softens the stair-steps
			var o := q.duplicate(); o.append(q[0]); draw_polyline(o, col, 1.0, true)
	func _dot(c: Vector2, r: float, col: Color) -> void:
		if clip.is_empty() or Geometry2D.is_point_in_polygon(c, clip): draw_circle(c, r, col)
	## Convex polygon moved inwards by d, keeping one vertex per corner (so rings can be cut into facets).
	static func inset(p: PackedVector2Array, d: float) -> PackedVector2Array:
		var c := Vector2.ZERO
		for v in p: c += v
		c /= p.size()
		var n := p.size(); var lines := []
		for i in n:
			var a: Vector2 = p[i]; var b: Vector2 = p[(i + 1) % n]; var e := (b - a).normalized(); var nn := Vector2(-e.y, e.x)
			if nn.dot(c - a) < 0: nn = -nn
			lines.append([a + nn * d, e])
		var out := PackedVector2Array()
		for i in n:
			var l0: Array = lines[(i - 1 + n) % n]; var l1: Array = lines[i]
			var hit = Geometry2D.line_intersects_line(l0[0], l0[1], l1[0], l1[1])
			out.append(hit if hit != null else l1[0])
		return out
	## Bevelled ring between two matching polygons, each facet shaded by how it faces the light.
	func _ring(o: PackedVector2Array, i: PackedVector2Array, base: Color, amt: float, flip := false) -> void:
		var c := Vector2.ZERO
		for v in o: c += v
		c /= o.size()
		for k in o.size():
			var k2 := (k + 1) % o.size()
			var mid := (o[k] + o[k2]) * 0.5; var nrm := (mid - c).normalized()
			var sh := nrm.dot(LIGHT.normalized()) * (-1.0 if flip else 1.0)
			var col := base.lightened(sh * amt) if sh > 0 else base.darkened(-sh * amt * 1.2)
			_fill(PackedVector2Array([o[k], o[k2], i[k2], i[k]]), col)
	func _chev(s: Vector2, i: int, top: float, th: float) -> PackedVector2Array:
		var m := -1.0 / 3.0; var dy := 0.042 * sqrt(1.0 + m * m); var sl := -3.2
		var cut := 0.53 + m * 0.25 + dy / 2 - sl * 0.25
		var ap := 0.53 + 0.12 * i + dy * top; var d2 := dy * th
		var u1 := (cut - ap) / (m - sl); var u2 := (cut - ap - d2) / (m - sl)
		return PackedVector2Array([Vector2(0.5, ap) * s, Vector2(0.5 + u1, ap + m * u1) * s, Vector2(0.5 + u2, ap + d2 + m * u2) * s, Vector2(0.5, ap + d2) * s, Vector2(0.5 - u2, ap + d2 + m * u2) * s, Vector2(0.5 - u1, ap + m * u1) * s])
	static func _pts(a: Array, s: Vector2) -> PackedVector2Array:
		var p := PackedVector2Array()
		for v in a: p.append(v * s)
		return p
	## Faceted aurite crystal: dark and lit halves, a bright ridge, a glow behind.
	func crystal(base: Vector2, ang: float, ln: float, w: float, bright := 1.0) -> void:
		var d := Vector2(cos(ang), sin(ang)); var pp := Vector2(-d.y, d.x)
		var tip := base + d * ln; var sh := base + d * ln * 0.72
		var r := 0.12
		UI.glow(self, base + d * ln * 0.5, Vector2.ONE * ln * 0.9, Color(0.3, 1.0, 0.6, 0.22 * bright))
		draw_colored_polygon(PackedVector2Array([base + pp * w, sh + pp * w, tip, sh - pp * w, base - pp * w]), Color("1d6a44"))
		draw_colored_polygon(PackedVector2Array([base + pp * w, sh + pp * w, tip, sh + pp * w * r, base + pp * w * r]), Color("2f9b62").lerp(Color("57d892"), 0.3 * bright))
		draw_colored_polygon(PackedVector2Array([base + pp * w * r, sh + pp * w * r, tip, sh - pp * w * 0.55, base - pp * w * 0.55]), Color("8ff5bf").lerp(Color("c9ffe2"), 0.4 * bright))
		draw_polyline(PackedVector2Array([base + pp * w * r, sh + pp * w * r, tip]), Color(0.9, 1.0, 0.95, 0.85), maxf(1.0, w * 0.12), true)
	func _draw() -> void:
		var s := size; var st: int = UI.stage
		if st == 2:
			_split(s); return
		var p := _pts(SH, s)
		# soft cast shadow, then a dark keyline so the rim reads on any backdrop
		var sp := p.duplicate()
		for k in sp.size(): sp[k] += Vector2(s.x * 0.035, s.y * 0.05)
		draw_colored_polygon(sp, Color(0, 0, 0, 0.45))
		_shield(s, st)
	func _shield(s: Vector2, st: int, wear := 0.0) -> void:
		var p := _pts(SH, s)
		var bw := maxf(3.0, s.x * (0.11 if chunky else 0.075))
		var brass: Color = [Color("d9a441"), Color("9c8a63"), Color("4d4842")][st]
		var keyl := inset(p, -maxf(1.5, s.x * 0.022))
		_fill(keyl, Color("0b0d08"))
		var i1 := inset(p, bw); var i2 := inset(p, bw + maxf(1.5, s.x * 0.03))
		_ring(p, i1, brass, 0.25 if chunky else 0.45)
		_ring(i1, i2, brass.darkened(0.15), 0.5, true)
		# field: olive drab, darker toward the point, with a heraldic split light/dark down the middle
		var fld: Color = [Color("232a1b"), Color("1e221c"), Color("161816")][st]
		var steps := 10; var y0 := i2[0].y; var y1 := i2[3].y
		for k in steps:
			var a := y0 + (y1 - y0) * k / steps; var b := y0 + (y1 - y0) * (k + 1) / steps
			var band := Geometry2D.intersect_polygons(i2, PackedVector2Array([Vector2(-s.x, a), Vector2(s.x * 2, a), Vector2(s.x * 2, b + 0.5), Vector2(-s.x, b + 0.5)]))
			for q in band: _fill(q, fld.lightened(0.10 * (1.0 - float(k) / steps)).darkened(0.25 * float(k) / steps))
		for q in Geometry2D.intersect_polygons(i2, PackedVector2Array([Vector2(-s.x, -s.y), Vector2(s.x * 0.5, -s.y), Vector2(s.x * 0.5, s.y * 2), Vector2(-s.x, s.y * 2)])):
			_fill(q, Color(1, 1, 1, 0.035))
		# rivets on the rim corners
		if s.x >= 44 and not chunky:
			for k in p.size():
				var rc := (p[k] + i1[k]) * 0.5; var rr := maxf(1.2, s.x * 0.022)
				_dot(rc + Vector2(rr * 0.35, rr * 0.45), rr, Color(0, 0, 0, 0.5))
				_dot(rc, rr, brass.darkened(0.1)); _dot(rc - Vector2(rr, rr) * 0.3, rr * 0.45, brass.lightened(0.45))
		# chevrons: shadow, body, a lit top edge
		var kh: Color = [Color("d8cba3"), Color("b9b39d"), Color("6f6d60")][st]
		for i in 3:
			var sh := _chev(s, i, 0.0, 1.0)
			for k in sh.size(): sh[k] += Vector2(s.x * 0.012, s.y * 0.018)
			_fill(sh, Color(0, 0, 0, 0.45))
			_fill(_chev(s, i, 0.0, 1.0), kh.darkened(0.12))
			_fill(_chev(s, i, 0.0, 0.55), kh)
			_fill(_chev(s, i, 0.0, 0.18), kh.lightened(0.35))
		if st == 1 and s.x >= 30:
			# a chip knocked out of the lowest chevron's right arm
			var cp := _pts([Vector2(0.735, 0.712), Vector2(0.795, 0.69), Vector2(0.775, 0.738)], s)
			_fill(cp, fld.darkened(0.2))
			draw_polyline(PackedVector2Array([cp[0], cp[1]]), kh.lightened(0.3), 1.0, true)
		if st < 2: _star(s, st)
		# gloss: a faint diagonal sheen over the top left
		var gl := PackedVector2Array([Vector2(-s.x, -s.y), Vector2(s.x * 0.62, -s.y), Vector2(s.x * 0.05, s.y * 0.62), Vector2(-s.x, s.y * 0.62)])
		for q in Geometry2D.intersect_polygons(p, gl): _fill(q, Color(1, 0.95, 0.8, 0.05 if st == 0 else 0.025))
		if st == 1: _crack(s)
		if st >= 1 and s.x >= 40 and not chunky: _scratches(s, i1)
	func _star(s: Vector2, st: int) -> void:
		var cc := Vector2(s.x * 0.5, s.y * 0.27); var ro := s.x * (0.19 if chunky else 0.15); var ri := s.x * (0.078 if chunky else 0.062)
		var red: Color = [Color("e5483f"), Color("9c4038"), Color("5a2a26")][st]
		var outer := PackedVector2Array()
		for i in 10:
			var a := -PI / 2 + i * PI / 5; outer.append(cc + Vector2(cos(a), sin(a)) * ((ro if i % 2 == 0 else ri) + s.x * 0.018))
		_fill(outer, Color("0b0d08"))
		for i in 5:
			var a := -PI / 2 + i * TAU / 5
			var tip := cc + Vector2(cos(a), sin(a)) * ro
			var l := cc + Vector2(cos(a - PI / 5), sin(a - PI / 5)) * ri; var r := cc + Vector2(cos(a + PI / 5), sin(a + PI / 5)) * ri
			var nl := ((tip + l) * 0.5 - cc).normalized(); var nr := ((tip + r) * 0.5 - cc).normalized()
			var L := LIGHT.normalized()
			_fill(PackedVector2Array([cc, l, tip]), red.lightened(0.12) if nl.dot(L) > 0.0 else red.darkened(0.18))
			_fill(PackedVector2Array([cc, tip, r]), red.lightened(0.12) if nr.dot(L) > 0.0 else red.darkened(0.18))
	func _crack(s: Vector2) -> void:
		var c := _pts(CRACK, s); var n := c.size()
		var a := PackedVector2Array(); var b := PackedVector2Array()
		for k in n:
			var d := (c[mini(k + 1, n - 1)] - c[maxi(k - 1, 0)]).normalized(); var pp := Vector2(-d.y, d.x)
			var w := s.x * 0.03 * sin(PI * (0.15 + 0.7 * float(k) / (n - 1)))
			a.append(c[k] + pp * w); b.append(c[k] - pp * w * 0.6)
		b.reverse(); a.append_array(b)
		draw_colored_polygon(a, Color("060705"))
		for k in range(2, n - 1): UI.glow(self, c[k], Vector2.ONE * s.x * 0.07, Color(0.35, 1.0, 0.6, 0.22))
		draw_polyline(c.slice(2, n - 1), Color(0.6, 1.0, 0.78, 0.8), maxf(1.0, s.x * 0.006), true)
		# lit lip on the upper side of the break
		var lip := PackedVector2Array()
		for k in n: lip.append(a[k])
		draw_polyline(lip, Color(1, 1, 0.9, 0.35), 1.0, true)
	func _scratches(s: Vector2, i1: PackedVector2Array) -> void:
		for k in 9:
			var h1 := fposmod(sin(k * 91.7 + 3.1) * 4375.5, 1.0); var h2 := fposmod(sin(k * 37.3 + 9.4) * 9137.1, 1.0)
			var c := Vector2(0.2 + 0.6 * h1, 0.12 + 0.7 * h2) * s; var a := h1 * 6.0
			var d := Vector2(cos(a), sin(a)) * s.x * (0.03 + 0.05 * h2)
			draw_line(c - d, c + d, Color(1, 1, 1, 0.08), 1.0, true)
	func _split(s: Vector2) -> void:
		var sp := _pts(SPLIT, s)
		var L := sp.duplicate(); L.append(Vector2(-s.x, s.y * 1.3)); L.append(Vector2(-s.x, -s.y * 0.3))
		var R := sp.duplicate(); R.append(Vector2(s.x * 2, s.y * 1.3)); R.append(Vector2(s.x * 2, -s.y * 0.3))
		# green light pouring out of the break
		UI.glow(self, s * Vector2(0.53, 0.45), s * Vector2(0.8, 0.9), Color(0.2, 1.0, 0.55, 0.35))
		UI.glow(self, s * Vector2(0.53, 0.45), s * Vector2(0.18, 0.5), Color(0.6, 1.0, 0.8, 0.5))
		var p := _pts(SH, s)
		for half in [[L, Vector2(-0.11, 0.04), -0.07], [R, Vector2(0.11, -0.01), 0.075]]:
			var off: Vector2 = half[1] * s
			draw_set_transform(off + s * 0.5 - (s * 0.5).rotated(half[2]), half[2], Vector2.ONE)
			clip = half[0]
			var sp2 := p.duplicate()
			for k in sp2.size(): sp2[k] += Vector2(s.x * 0.035, s.y * 0.05)
			_fill(sp2, Color(0, 0, 0, 0.5))
			_shield(s, 2)
			# green rim light along the broken edge
			for e: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(sp, p):
				draw_polyline(e, Color(0.55, 1.0, 0.75, 0.75), maxf(1.5, s.x * 0.016), true)
			clip = PackedVector2Array()
			draw_set_transform(Vector2.ZERO)
		# crystals growing out of the wound, the tallest where the star used to be
		var cr := [[0.56, 0.36, -2.25, 0.36, 0.06], [0.58, 0.45, -0.95, 0.34, 0.06], [0.57, 0.40, -1.62, 0.62, 0.09], [0.55, 0.46, -1.25, 0.44, 0.075],
			[0.47, 0.64, -2.7, 0.16, 0.035], [0.50, 0.76, -0.35, 0.14, 0.03]]
		for c in cr: crystal(Vector2(c[0], c[1]) * s, c[2], c[3] * s.y, c[4] * s.x)
		
## Marks laid over the AURITE / FRONT title for later stages: a crack through both words, then crystals and a green underglow.
class TitleMark extends Control:
	var w := 300.0      # width of the longer word
	var lh := 60.0      # font size of the title
	var center := false
	var b: Label        # the second word (FRONT)
	func _draw() -> void:
		var st: int = UI.stage
		if st == 0 or b == null: return
		var x0 := (size.x - w) * 0.5 if center else 0.0
		var top := size.y * 0.24; var off: float = b.position.y - (get_parent() as Control).position.y
		var base2: float = off + b.size.y * 0.78; var top2: float = off + b.size.y * 0.24
		if st == 2:
			UI.glow(self, Vector2(x0 + w * 0.5, base2), Vector2(w * 0.8, lh * 0.5), Color(0.25, 1.0, 0.6, 0.18))
		# crack: down through the U of AURITE, then on through the O of FRONT, each a tapered dark break with a green core
		for seg in [[Vector2(0.255, top), Vector2(0.235, top + (base2 - top2) * 0.35), Vector2(0.285, top + (base2 - top2) * 0.55), Vector2(0.25, size.y * 0.78)],
				[Vector2(0.43, top2), Vector2(0.41, top2 + (base2 - top2) * 0.3), Vector2(0.455, top2 + (base2 - top2) * 0.6), Vector2(0.43, base2)]]:
			var c := PackedVector2Array()
			for v: Vector2 in seg: c.append(Vector2(x0 + v.x * w, v.y))
			var a := PackedVector2Array(); var r := PackedVector2Array(); var n := c.size()
			for k in n:
				var d := (c[mini(k + 1, n - 1)] - c[maxi(k - 1, 0)]).normalized(); var pp := Vector2(-d.y, d.x)
				var wd := lh * (0.035 if st == 1 else 0.05) * sin(PI * (0.12 + 0.76 * float(k) / (n - 1)))
				a.append(c[k] + pp * wd); r.append(c[k] - pp * wd * 0.5)
			r.reverse(); a.append_array(r)
			draw_colored_polygon(a, Color(0.02, 0.025, 0.02))
			draw_polyline(c.slice(1, n - 1), Color(0.6, 1.0, 0.78, 0.5 if st == 1 else 0.85), 1.0, true)
			if st == 2: UI.glow(self, c[1], Vector2.ONE * lh * 0.3, Color(0.3, 1.0, 0.6, 0.3))
		if st == 2:
			# crystals pushing up through FRONT's baseline
			for cr in [[0.43, -1.75, 0.62, 0.05], [0.47, -1.25, 0.38, 0.04], [0.395, -2.3, 0.34, 0.035], [0.86, -1.8, 0.36, 0.035], [0.9, -1.3, 0.22, 0.028], [0.06, -1.9, 0.26, 0.03]]:
				_crystal(Vector2(x0 + cr[0] * w, base2 + lh * 0.04), cr[1], cr[2] * lh, cr[3] * w)
	func _crystal(base: Vector2, ang: float, ln: float, wd: float) -> void:
		var d := Vector2(cos(ang), sin(ang)); var pp := Vector2(-d.y, d.x)
		var tip := base + d * ln; var sh := base + d * ln * 0.72
		UI.glow(self, base + d * ln * 0.5, Vector2.ONE * ln * 0.9, Color(0.3, 1.0, 0.6, 0.25))
		draw_colored_polygon(PackedVector2Array([base + pp * wd, sh + pp * wd, tip, sh - pp * wd, base - pp * wd]), Color("1d6a44"))
		draw_colored_polygon(PackedVector2Array([base + pp * wd, sh + pp * wd, tip, sh + pp * wd * 0.1, base + pp * wd * 0.1]), Color("3fae72"))
		draw_colored_polygon(PackedVector2Array([base + pp * wd * 0.1, sh + pp * wd * 0.1, tip, sh - pp * wd * 0.55, base - pp * wd * 0.55]), Color("a8f8cf"))
		draw_polyline(PackedVector2Array([base + pp * wd * 0.1, sh + pp * wd * 0.1, tip]), Color(0.9, 1, 0.95, 0.8), 1.0, true)

## Speaker portrait for the radio panel and the debrief, drawn in code from a Data.SPEAKERS entry:
## a lit bust on a faction-tinted screen with scanlines and a little radio static.
class Portrait extends Control:
	var sp := {}          # Data.SPEAKERS entry
	var t := 0.0
	var live := false     # animates static and a talking mouth while a line is being typed
	func _process(dt: float) -> void:
		if live and is_visible_in_tree():
			t += dt; queue_redraw()
	func _ell(c: Vector2, r: Vector2, col: Color, n := 28) -> void:
		var p := PackedVector2Array()
		for i in n: p.append(c + Vector2(cos(TAU * i / n) * r.x, sin(TAU * i / n) * r.y))
		draw_colored_polygon(p, col)
		p.append(p[0]); draw_polyline(p, col, 1.0, true)
	func _poly(pts: Array, col: Color) -> void:
		var p := PackedVector2Array()
		for v in pts: p.append(v * size)
		draw_colored_polygon(p, col)
		p.append(p[0]); draw_polyline(p, col, 1.0, true)
	func _draw() -> void:
		var s := size
		if sp.is_empty(): return
		var tint: Color = sp.get("tint", Color("3a4030"))
		# screen: tinted glass, darker at the bottom
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]), PackedColorArray([tint.lightened(0.12), tint.lightened(0.12), tint.darkened(0.55), tint.darkened(0.55)]))
		UI.glow(self, Vector2(s.x * 0.35, s.y * 0.3), s * 0.7, Color(tint.lightened(0.5), 0.25))
		var skin: Color = sp.get("skin", Color("c99a78")); var hair: Color = sp.get("hair", Color("3a2a20"))
		var uni: Color = sp.get("uniform", Color("3d4530")); var gear: String = sp.get("gear", "")
		var lng: bool = sp.get("long", false); var old: float = sp.get("age", 0.3)
		var c := Vector2(0.5, 0.47)
		# long hair falls behind the head and onto the shoulders
		if lng: _poly([Vector2(0.30, 0.36), Vector2(0.70, 0.36), Vector2(0.74, 0.74), Vector2(0.62, 0.80), Vector2(0.38, 0.80), Vector2(0.26, 0.74)], hair.darkened(0.15))
		if gear == "hood": _poly([Vector2(0.26, 0.42), Vector2(0.5, 0.12), Vector2(0.74, 0.42), Vector2(0.80, 0.86), Vector2(0.20, 0.86)], uni.darkened(0.2))
		# shoulders, collar and a faction flash
		_poly([Vector2(0.04, 1.02), Vector2(0.10, 0.84), Vector2(0.30, 0.76), Vector2(0.70, 0.76), Vector2(0.90, 0.84), Vector2(0.96, 1.02)], uni)
		_poly([Vector2(0.70, 0.76), Vector2(0.90, 0.84), Vector2(0.96, 1.02), Vector2(0.66, 1.02)], uni.darkened(0.25))
		_poly([Vector2(0.38, 0.75), Vector2(0.5, 0.88), Vector2(0.62, 0.75), Vector2(0.58, 0.72), Vector2(0.42, 0.72)], uni.darkened(0.45))
		_poly([Vector2(0.30, 0.76), Vector2(0.42, 0.75), Vector2(0.5, 0.92), Vector2(0.40, 0.98)], uni.lightened(0.12))
		_poly([Vector2(0.70, 0.76), Vector2(0.58, 0.75), Vector2(0.5, 0.92), Vector2(0.60, 0.98)], uni.lightened(0.05))
		var flash: Color = sp.get("flash", Color("d9a441"))
		_poly([Vector2(0.14, 0.86), Vector2(0.26, 0.82), Vector2(0.27, 0.87), Vector2(0.15, 0.91)], flash)
		# neck in shadow, then the head: rounded skull, a jaw, ears
		_poly([Vector2(0.43, 0.60), Vector2(0.57, 0.60), Vector2(0.58, 0.76), Vector2(0.5, 0.80), Vector2(0.42, 0.76)], skin.darkened(0.3))
		_ell(Vector2(0.325, 0.48) * s, Vector2(0.03, 0.05) * s, skin.darkened(0.08))
		_ell(Vector2(0.675, 0.48) * s, Vector2(0.03, 0.05) * s, skin.darkened(0.2))
		var jw: float = sp.get("jaw", 0.13)
		_ell(Vector2(0.5, 0.42) * s, Vector2(0.17, 0.17) * s, skin)
		_poly([Vector2(0.33, 0.44), Vector2(0.67, 0.44), Vector2(0.5 + jw, 0.58), Vector2(0.56, 0.665), Vector2(0.44, 0.665), Vector2(0.5 - jw, 0.58)], skin)
		# shade the far side of the face (light from the upper left)
		_poly([Vector2(0.56, 0.27), Vector2(0.64, 0.32), Vector2(0.67, 0.44), Vector2(0.5 + jw, 0.58), Vector2(0.56, 0.665), Vector2(0.52, 0.665), Vector2(0.58, 0.55), Vector2(0.60, 0.40)], skin.darkened(0.16))
		# eyes, brows, nose, mouth
		var ey := 0.455
		for side: int in [-1, 1]:
			var ex := 0.5 + side * 0.07
			if sp.get("patch", false) and side == 1:
				_ell(Vector2(ex, ey) * s, Vector2(0.04, 0.03) * s, Color("141414"))
				draw_line(Vector2(0.33, 0.40) * s, Vector2(0.67, 0.44) * s, Color("141414"), maxf(1.0, s.x * 0.012), true)
			else:
				_ell(Vector2(ex, ey) * s, Vector2(0.028, 0.012) * s, Color(0.95, 0.93, 0.88) if not sp.get("glow", false) else Color(0.6, 1.0, 0.8))
				_ell(Vector2(ex + 0.004, ey) * s, Vector2(0.012, 0.012) * s, Color("1d1712") if not sp.get("glow", false) else Color(0.3, 1.0, 0.6))
				if sp.get("glow", false): UI.glow(self, Vector2(ex, ey) * s, Vector2.ONE * s.x * 0.06, Color(0.3, 1.0, 0.6, 0.6))
			var bt: float = sp.get("brow", 0.0)   # positive: frowning
			draw_line(Vector2(ex - side * 0.045, ey - 0.042 + bt * 0.01) * s, Vector2(ex + side * 0.035, ey - 0.042 - bt * 0.012) * s, hair.darkened(0.2), maxf(1.5, s.x * 0.018), true)
			if old > 0.5:
				draw_line(Vector2(ex + side * 0.04, ey + 0.012) * s, Vector2(ex + side * 0.06, ey + 0.03) * s, skin.darkened(0.3), 1.0, true)
		draw_line(Vector2(0.505, 0.47) * s, Vector2(0.515, 0.535) * s, skin.darkened(0.3), maxf(1.0, s.x * 0.012), true)
		_poly([Vector2(0.48, 0.545), Vector2(0.53, 0.545), Vector2(0.515, 0.555)], skin.darkened(0.35))
		var talk := 0.0
		if live: talk = absf(sin(t * 13.0)) * 0.018
		var sm: float = sp.get("smile", 0.0)
		_poly([Vector2(0.455, 0.595 - sm * 0.01), Vector2(0.5, 0.592 + sm * 0.012), Vector2(0.545, 0.595 - sm * 0.01), Vector2(0.5, 0.6 + talk)], Color("4a2420").lerp(skin.darkened(0.4), 0.4))
		if old > 0.5:
			draw_line(Vector2(0.44, 0.34) * s, Vector2(0.56, 0.335) * s, skin.darkened(0.2), 1.0, true)
		if sp.get("scar", false):
			draw_line(Vector2(0.40, 0.42) * s, Vector2(0.45, 0.56) * s, skin.lightened(0.25), maxf(1.0, s.x * 0.01), true)
		# facial hair
		var bd: String = sp.get("beard", "")
		if bd == "full":
			_poly([Vector2(0.35, 0.50), Vector2(0.42, 0.57), Vector2(0.58, 0.57), Vector2(0.65, 0.50), Vector2(0.62, 0.66), Vector2(0.5, 0.74), Vector2(0.38, 0.66)], hair)
			_poly([Vector2(0.45, 0.6), Vector2(0.55, 0.6), Vector2(0.5, 0.615)], Color("3a201c"))
		if bd == "full" or bd == "moustache":
			_poly([Vector2(0.43, 0.585), Vector2(0.5, 0.565), Vector2(0.57, 0.585), Vector2(0.56, 0.6), Vector2(0.5, 0.585), Vector2(0.44, 0.6)], hair.lightened(0.05))
		# hair on top, then headgear
		if sp.get("hair_top", true) and gear != "helmet" and gear != "hood":
			_poly([Vector2(0.33, 0.42), Vector2(0.34, 0.30), Vector2(0.42, 0.25), Vector2(0.56, 0.245), Vector2(0.65, 0.29), Vector2(0.675, 0.42), Vector2(0.64, 0.34), Vector2(0.52, 0.31), Vector2(0.40, 0.33)], hair)
		match gear:
			"cap":
				var cc: Color = sp.get("cap", uni)
				_poly([Vector2(0.30, 0.31), Vector2(0.33, 0.20), Vector2(0.5, 0.15), Vector2(0.70, 0.19), Vector2(0.72, 0.31)], cc)
				_poly([Vector2(0.31, 0.29), Vector2(0.71, 0.29), Vector2(0.71, 0.33), Vector2(0.31, 0.33)], sp.get("band", flash))
				_poly([Vector2(0.32, 0.33), Vector2(0.68, 0.33), Vector2(0.62, 0.38), Vector2(0.38, 0.38)], Color("15140f"))
				_ell(Vector2(0.5, 0.24) * s, Vector2(0.025, 0.025) * s, flash.lightened(0.2))
			"helmet":
				var hc: Color = sp.get("cap", uni.lightened(0.05))
				_poly([Vector2(0.29, 0.40), Vector2(0.30, 0.26), Vector2(0.40, 0.17), Vector2(0.60, 0.17), Vector2(0.70, 0.26), Vector2(0.71, 0.40), Vector2(0.66, 0.36), Vector2(0.34, 0.36)], hc)
				_poly([Vector2(0.27, 0.36), Vector2(0.73, 0.36), Vector2(0.73, 0.39), Vector2(0.27, 0.39)], hc.darkened(0.3))
				_poly([Vector2(0.36, 0.22), Vector2(0.46, 0.18), Vector2(0.45, 0.21)], hc.lightened(0.3))
				# headset boom
				draw_polyline(PackedVector2Array([Vector2(0.31, 0.47) * s, Vector2(0.33, 0.58) * s, Vector2(0.43, 0.6) * s]), Color("1a1a1a"), maxf(1.0, s.x * 0.014), true)
			"goggles":
				_poly([Vector2(0.32, 0.31), Vector2(0.68, 0.31), Vector2(0.68, 0.35), Vector2(0.32, 0.35)], Color("2a2420"))
				for gx: float in [0.42, 0.58]:
					_ell(Vector2(gx, 0.31) * s, Vector2(0.055, 0.045) * s, Color("6b5a3a"))
					_ell(Vector2(gx, 0.31) * s, Vector2(0.04, 0.032) * s, Color(0.55, 0.75, 0.8))
					_ell(Vector2(gx - 0.012, 0.3) * s, Vector2(0.012, 0.009) * s, Color(1, 1, 1, 0.8))
			"hood":
				_poly([Vector2(0.29, 0.46), Vector2(0.32, 0.27), Vector2(0.5, 0.17), Vector2(0.68, 0.27), Vector2(0.71, 0.46), Vector2(0.66, 0.36), Vector2(0.5, 0.29), Vector2(0.34, 0.36)], uni.darkened(0.1))
		# screen effects: scanlines, a soft vignette, static, glass sheen and a hard frame
		var y := 0.0
		while y < s.y:
			draw_line(Vector2(0, y), Vector2(s.x, y), Color(0, 0, 0, 0.12), 1.0); y += 3.0
		for i in 18:
			var hx := fposmod(sin(i * 12.9 + floorf(t * 12.0) * 7.1) * 43758.5, 1.0); var hy := fposmod(sin(i * 78.2 + floorf(t * 12.0) * 3.3) * 24634.6, 1.0)
			draw_rect(Rect2(Vector2(hx, hy) * s, Vector2(2, 1)), Color(1, 1, 1, 0.12))
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x * 0.55, 0), Vector2(0, s.y * 0.45)]), PackedColorArray([Color(1, 1, 1, 0.09), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.9), false, 3.0)
		draw_rect(Rect2(Vector2(1.5, 1.5), s - Vector2(3, 3)), Color(flash, 0.75), false, 1.0)

## The "go" mark on a door: a riveted plate with a bold arrow that leans forward on hover.
class GoMark extends Control:
	var main_action := false
	var hot := false
	var k := 0.0
	func _process(dt: float) -> void:
		var want := 1.0 if hot else 0.0
		if absf(k - want) > 0.01: k = move_toward(k, want, dt * 6.0); queue_redraw()
	func _draw() -> void:
		var s := size; var c := s * 0.5; var r := minf(s.x, s.y) * 0.5 - 2
		var st: int = UI.stage
		var acc: Color = ([Color("e5483f"), Color("a8483c"), Color("3fbf7a")][st] if main_action else Color("a99c78"))
		var p := PackedVector2Array()
		for i in 8: p.append(c + Vector2(cos(PI / 8 + i * PI / 4), sin(PI / 8 + i * PI / 4)) * r)
		var q := p.duplicate(); q.append(p[0])
		var sh := p.duplicate()
		for i in sh.size(): sh[i] += Vector2(0, 3)
		draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
		draw_colored_polygon(p, acc.darkened(0.6).lerp(acc.darkened(0.35), k))
		var ins := Insignia.inset(p, 4.0); var iq := ins.duplicate(); iq.append(ins[0])
		draw_polyline(q, acc, 2.0, true); draw_polyline(iq, Color(acc, 0.35), 1.0, true)
		for i in 4:
			var rv := c + Vector2(cos(PI / 4 + i * PI / 2), sin(PI / 4 + i * PI / 2)) * (r - 6)
			draw_circle(rv, 1.8, Color(acc.lightened(0.4), 0.8))
		var fw := Color.WHITE if main_action else Color("d8cba3")
		var o := c + Vector2(r * 0.12 * k - r * 0.05, 0); var a := r * 0.5
		var arrow := PackedVector2Array([o + Vector2(-a, -a * 0.22), o + Vector2(a * 0.05, -a * 0.22), o + Vector2(a * 0.05, -a * 0.62), o + Vector2(a * 0.75, 0),
			o + Vector2(a * 0.05, a * 0.62), o + Vector2(a * 0.05, a * 0.22), o + Vector2(-a, a * 0.22)])
		var ash := arrow.duplicate()
		for i in ash.size(): ash[i] += Vector2(0, 2)
		draw_colored_polygon(ash, Color(0, 0, 0, 0.5)); draw_colored_polygon(arrow, fw)
		var aq := arrow.duplicate(); aq.append(arrow[0]); draw_polyline(aq, fw, 1.0, true)
		if k > 0.01: UI.glow(self, c, Vector2.ONE * r * 1.4, Color(acc, 0.25 * k))

## A blinking red "on air" dot for the start screen's header.
class RecDot extends Control:
	var t := 0.0
	func _process(dt: float) -> void:
		if is_visible_in_tree(): t += dt; queue_redraw()
	func _draw() -> void:
		var on := fposmod(t, 1.6) < 1.1
		var c := Vector2(7, size.y * 0.5)
		var col := Color("e5483f") if UI.stage < 2 else Color("3fbf7a")
		if on:
			UI.glow(self, c, Vector2(12, 12), Color(col, 0.45)); draw_circle(c, 3.5, col)
		else: draw_circle(c, 3.5, Color(col, 0.3))

## Dispatch ticker along the bottom of the start screen: war news scrolling past, darker as the story descends.
class Ticker extends Control:
	var font: Font
	var t := 0.0
	const NEWS := [
		["KETTLEFORD FOUNDRY LIGHTS ITS FIRES", "VANGUARD BARGES SIGHTED OFF THE SABLE COAST", "PACT MILITIA MUSTERS AT THE RIVER", "AURITE PRICE DOUBLES IN THE CAPITAL", "MARSHAL DACE PROMISES PEACE BY WINTER"],
		["IRON TIDE MAKES LANDFALL", "FOUNDRY TOWNS EMPTY OVERNIGHT", "MINERS REPORT SINGING IN THE DEEP SHAFTS", "RELAY MASTS DOWN ACROSS THE VALLEY", "ORE FIELDS GROWING BACK FASTER THAN MINED"],
		["THE CHOIR IS SINGING", "NO REPORTS FROM THE DEEP", "GLASS WHERE THE TOWNS WERE", "DO NOT LISTEN TO THE HUM", "IT WAS NEVER OURS"],
	]
	func _process(dt: float) -> void:
		if is_visible_in_tree(): t += dt; queue_redraw()
	func _draw() -> void:
		var s := size; var st: int = UI.stage
		var acc: Color = [Color("d9a441"), Color("a88d55"), Color("3fbf7a")][st]
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
		draw_line(Vector2(0, 0.5), Vector2(s.x, 0.5), Color(acc, 0.5), 1.0)
		draw_line(Vector2(0, s.y - 0.5), Vector2(s.x, s.y - 0.5), Color(acc, 0.25), 1.0)
		var line := ""
		for n in NEWS[st]: line += n + "      ///      "
		var fs := 12; var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := 120.0 - fposmod(t * 40.0, w)
		while x < s.x:
			draw_string(font, Vector2(x, s.y * 0.5 + fs * 0.36), line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("d8cba3") if st < 2 else Color("a3c9b0"))
			x += w
		# tag on the left, over the scrolling text
		draw_rect(Rect2(0, 1, 110, s.y - 2), Color(acc.darkened(0.55), 1.0))
		draw_colored_polygon(PackedVector2Array([Vector2(110, 1), Vector2(122, 1), Vector2(110, s.y - 1)]), Color(acc.darkened(0.55), 1.0))
		draw_string(font, Vector2(14, s.y * 0.5 + 4.5), "DISPATCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, acc.lightened(0.2))

## Craft layer behind a start-screen door: inner bevel, hatching, rivets and a faint emblem; aged with UI.stage.
class DoorArt extends Control:
	var main_action := false
	var accent := Color("e5483f")
	var num := "I"
	var done := 0
	var total := 8
	var t := 0.0
	func _process(dt: float) -> void:
		if main_action and is_visible_in_tree():
			t += dt; queue_redraw()
	func _draw() -> void:
		var s := size; var st: int = UI.stage
		# top lit edge and a darker floor
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y * 0.45), Vector2(0, s.y * 0.45)]),
			PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
		draw_polygon(PackedVector2Array([Vector2(0, s.y * 0.6), Vector2(s.x, s.y * 0.6), Vector2(s.x, s.y), Vector2(0, s.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0.3)]))
		# fine diagonal hatching
		var x := -s.y
		while x < s.x:
			draw_line(Vector2(x, s.y), Vector2(x + s.y, 0), Color(1, 1, 1, 0.022), 1.0); x += 9
		# inner keyline
		draw_rect(Rect2(Vector2(7, 7), s - Vector2(14, 14)), Color(accent, 0.22), false, 1.0)
		# rivets
		for c in [Vector2(16, s.y - 14), Vector2(s.x - 16, 14), Vector2(s.x - 16, s.y - 14), Vector2(28, 14)]:
			draw_circle(c + Vector2(0.6, 0.8), 2.6, Color(0, 0, 0, 0.5)); draw_circle(c, 2.6, Color(accent.darkened(0.3), 0.9)); draw_circle(c - Vector2(0.8, 0.8), 1.0, Color(1, 1, 1, 0.35))
		# emblem, big and faint on the right: the shield for the campaign, a tank for skirmish
		var ec := Color(1, 1, 1, 0.03)
		if not main_action:
			var h := s.y / 60.0
			draw_set_transform(Vector2(s.x - 40 * h - 50, s.y * 0.78), -0.04, Vector2(h, h))
			draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(31, -6), Vector2(25, -11), Vector2(-25, -11), Vector2(-31, -6)]), ec)
			draw_colored_polygon(PackedVector2Array([Vector2(-13, -11), Vector2(12, -11), Vector2(9, -19), Vector2(-9, -19)]), ec)
			draw_rect(Rect2(8, -16.5, 30, 3), ec)
			draw_set_transform(Vector2.ZERO)
		var f: Font = load("res://fonts/chakra-petch-latin-700-normal.woff2")
		if main_action:
			# the chapter numeral, huge and stencilled, behind everything
			var fs := int(s.y * 0.95)
			var nw := f.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(s.x - nw - s.x * 0.16, s.y * 0.86), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.05))
			# one pip per mission along the bottom: won ones filled, the next one pulsing
			var pw := 30.0; var gap := 8.0; var px := 22.0; var py := s.y - 40.0
			draw_string(f, Vector2(px, py - 8), "OPERATIONS", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
			for i in total:
				var r := Rect2(px + i * (pw + gap), py, pw, 12)
				var pts := PackedVector2Array([r.position + Vector2(4, 0), Vector2(r.end.x, r.position.y), r.end - Vector2(4, 0), Vector2(r.position.x, r.end.y)])
				if i < done:
					draw_colored_polygon(pts, Color(accent.lightened(0.35), 0.95))
				elif i == done:
					var pl := 0.5 + 0.5 * sin(t * 4.0)
					draw_colored_polygon(pts, Color(accent.lightened(0.5), 0.25 + 0.35 * pl))
					UI.glow(self, r.get_center(), Vector2(30, 16), Color(accent, 0.25 * pl))
				pts.append(pts[0]); draw_polyline(pts, Color(1, 1, 1, 0.35), 1.0, true)
		else:
			# the three armies as small shields, top right
			var cols := [Color("3fb4e8"), Color("e5483f"), Color("3fbf7a")]
			for i in 3:
				var o := Vector2(s.x - 190 + i * 44, 22); var h := 36.0
				var p := PackedVector2Array()
				for v in Insignia.SH: p.append(o + v * Vector2(h * 0.86, h))
				var k := p.duplicate(); k.append(p[0])
				draw_colored_polygon(p, Color(cols[i].darkened(0.55), 0.9)); draw_polyline(k, Color(cols[i], 0.9), 1.5, true)
				var c := o + Vector2(h * 0.43, h * 0.45)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -2), c + Vector2(0, 4), c + Vector2(7, -2), c + Vector2(7, 2), c + Vector2(0, 8), c + Vector2(-7, 2)]), Color(cols[i], 0.9))
		if st >= 1:
			for k in 7:
				var h1 := fposmod(sin(k * 51.7 + (3.1 if main_action else 7.7)) * 4375.5, 1.0); var h2 := fposmod(sin(k * 17.3 + 9.4) * 9137.1, 1.0)
				var c := Vector2(s.x * h1, s.y * h2); var a := 0.3 + h1 * 0.6
				draw_line(c, c + Vector2(cos(a), sin(a)) * (20 + 50 * h2), Color(1, 1, 1, 0.05), 1.0, true)
		if st == 2 and main_action:
			# aurite pushing in through the door's bottom right corner
			UI.glow(self, Vector2(s.x - 30, s.y - 10), Vector2(170, 110), Color(0.25, 1.0, 0.6, 0.22))
			for cr in [[s.x - 40, -2.0, 0.55, 12.0], [s.x - 64, -2.4, 0.35, 8.0], [s.x - 18, -1.6, 0.4, 8.0], [s.x - 90, -2.7, 0.2, 6.0]]:
				_crystal(Vector2(cr[0], s.y + 4), cr[1], cr[2] * s.y, cr[3])
	func _crystal(base: Vector2, ang: float, ln: float, wd: float) -> void:
		var d := Vector2(cos(ang), sin(ang)); var pp := Vector2(-d.y, d.x)
		var tip := base + d * ln; var sh := base + d * ln * 0.72
		draw_colored_polygon(PackedVector2Array([base + pp * wd, sh + pp * wd, tip, sh - pp * wd, base - pp * wd]), Color("1d6a44"))
		draw_colored_polygon(PackedVector2Array([base + pp * wd, sh + pp * wd, tip, sh + pp * wd * 0.1, base + pp * wd * 0.1]), Color("3fae72"))
		draw_colored_polygon(PackedVector2Array([base + pp * wd * 0.1, sh + pp * wd * 0.1, tip, sh - pp * wd * 0.55, base - pp * wd * 0.55]), Color("a8f8cf"))
		draw_polyline(PackedVector2Array([base + pp * wd * 0.1, sh + pp * wd * 0.1, tip]), Color(0.9, 1, 0.95, 0.8), 1.0, true)

class HudDraw extends Control:
	var ui
	func _draw() -> void:
		if ui.main: ui.main.draw_hud(self)

class BuildItem extends Control:
	var ui
	var cat := ""
	var type := ""
	var icon: Texture2D
	var prog := 0.0
	var is_ready := false
	var active := false
	var n := 0
	var locked := false
	var lp_t := -1.0
	var did := false
	var press_at := Vector2()
	var dragging := false   # a ready building being dragged out onto the map
	const CANCEL := Vector2(26, 26)   # top-left corner of an item with orders: tap it to cancel one
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
	func _process(dt: float) -> void:
		if lp_t >= 0:
			lp_t += dt
			if lp_t > 0.55 and not did:
				# hold: units queue five at once; a building cancels
				did = true
				if cat == "bld": ui.main.cancel_item(cat, type)
				else: ui.main.queue_many(cat, type, 5)
	func _has_orders() -> bool:
		return active or n > 0 or is_ready
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				ui.main.cancel_item(cat, type); accept_event(); return
			if ev.button_index != MOUSE_BUTTON_LEFT: return
			if ev.pressed:
				lp_t = 0.0; did = false; press_at = ev.position; dragging = false
			else:
				if dragging:
					dragging = false; ui.main.drag_build_end(get_global_transform() * ev.position); accept_event()
				elif lp_t >= 0 and not did and Rect2(Vector2.ZERO, size).has_point(ev.position):
					if _has_orders() and Rect2(Vector2.ZERO, CANCEL).has_point(ev.position): ui.main.cancel_item(cat, type)
					else: ui.main.click_item(cat, type)
				lp_t = -1.0
		elif ev is InputEventMouseMotion and (lp_t >= 0 or dragging):
			if dragging:
				ui.main.drag_build_move(get_global_transform() * ev.position); accept_event()
			elif cat == "bld" and is_ready and ev.position.distance_to(press_at) > 10:
				dragging = true; lp_t = -1.0; did = true
				ui.main.drag_build_start(type, get_global_transform() * ev.position); accept_event()
			elif ev.relative.length() > 6:
				lp_t = -1.0  # it's a scroll, not a press
	func _draw() -> void:
		var d: Dictionary = D.def_of(type)
		var a := 0.4 if locked else 1.0
		var hot := active or is_ready
		# chamfered card; brass trim while it is in production
		draw_style_box(UI.cut(Color("1a1f15") if not hot else Color("221f12"), Color("d9a441") if hot else Color("3a4130"), 2 if hot else 1, 8, 0), Rect2(Vector2.ZERO, size))
		# icon well: dark steel with a spotlight behind the model and a floor line
		var ir := Rect2(4, 4, size.x - 8, 46)
		draw_rect(ir, Color("0d100b"))
		var lc := ir.get_center() + Vector2(0, 4)
		for k in 4: draw_circle(lc, (26 - k * 6) * 1.0, Color(0.85, 0.78, 0.55, 0.035 * a))
		draw_line(Vector2(ir.position.x, ir.end.y - 8), Vector2(ir.end.x, ir.end.y - 8), Color(0.85, 0.8, 0.64, 0.06), 1.0)
		if icon:
			var iw := 58.0; var ih := 46.0
			draw_texture_rect(icon, Rect2(ir.get_center().x - iw / 2, ir.position.y, iw, ih), false, Color(1, 1, 1, a))
		var nm: String = d.name
		var f: Font = ui.f_body6
		var tw := f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var fs := 11 if tw <= size.x - 6 else 10
		draw_string(f, Vector2(3, 63), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, fs, Color(Color("e2dac2"), a))
		if locked:
			var lw: float = ui.f_disp.get_string_size("LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var x0: float = (size.x - lw - 14) / 2
			UI.glyph(self, "lock", Rect2(x0, 67, 10, 11), Color("8b8a78"))
			draw_string(ui.f_disp, Vector2(x0 + 14, 77), "LOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8b8a78"))
		else:
			var cs := str(d.cost)
			var cw: float = ui.f_disp7.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var x0: float = (size.x - cw - 12) / 2
			UI.glyph(self, "aur", Rect2(x0, 67, 8, 11), UI.C_AUR)
			draw_string(ui.f_disp7, Vector2(x0 + 12, 77), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.C_AUR)
		if active and not is_ready:
			# darken the part still to build, clockwise from the top, over the icon well
			var c := ir.get_center(); var r := ir.size.length() / 2
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in range(int(prog * steps), steps + 1):
				var ang: float = -PI / 2 + TAU * max(prog, float(i) / steps)
				pts.append(c + Vector2(cos(ang), sin(ang)) * r)
			if pts.size() > 2:
				var cp := PackedVector2Array()
				for p in pts: cp.append(Vector2(clamp(p.x, ir.position.x, ir.end.x), clamp(p.y, ir.position.y, ir.end.y)))
				draw_colored_polygon(cp, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(ir.position.x, ir.end.y - 3, ir.size.x, 3), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(ir.position.x, ir.end.y - 3, ir.size.x * clampf(prog, 0, 1), 3), UI.C_AUR)
		if n > 1:
			var bw := 24.0; var br := Rect2(size.x - bw - 3, 3, bw, 16)
			draw_style_box(UI.cut(Color("d9a441"), Color(0, 0, 0, 0), 0, 4, 0), br)
			draw_string(ui.f_disp7, Vector2(br.position.x, br.position.y + 12.5), "×%d" % n, HORIZONTAL_ALIGNMENT_CENTER, bw, 11, Color("1a1408"))
		if _has_orders():  # cancel corner
			draw_style_box(UI.cut(Color(0.1, 0.03, 0.02, 0.85), Color("e5483f", 0.7), 1, 4, 0), Rect2(Vector2(3, 3), CANCEL - Vector2(8, 8)))
			draw_line(Vector2(8, 8), Vector2(16, 16), Color("ffd0cc"), 2); draw_line(Vector2(16, 8), Vector2(8, 16), Color("ffd0cc"), 2)
		if is_ready:
			UI.ready_banner(self, ui, Rect2(0, 18, size.x, 18))

## Top-bar chip for one kind of producer you own (bt: "hq" for the Yard, else a building type): what it is making,
## its progress and queue. Tap: place a ready building, otherwise select that building (tap again: the next one).
class ProdChip extends Control:
	var ui
	var bt := ""
	var cat := ""     # the production line its current item is on ("" when idle)
	var type := ""    # what it is making ("" when idle)
	var prog := 0.0
	var n := 0
	var is_ready := false
	var lit := false  # that building is selected
	var loop := false # LOOP is on for it
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	var down := false
	var down_at := Vector2()
	var dragging := false
	## A tap opens the building's half ring. A READY structure (Guillaume 2026-11-28: "drag a built structure directly
	## from the side menu") also drags straight off the shortcut onto the map and is built where it is let go.
	func _gui_input(ev: InputEvent) -> void:
		var m = ui.main
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if ev.pressed:
				down = true; down_at = ev.position; dragging = false; return
			if not down: return
			down = false
			if dragging:
				dragging = false
				m.drag_build_end(get_global_transform() * ev.position); return
			ui.ring.toggle_dock(bt); m.sfx("click"); m.buzz(8)
		elif ev is InputEventMouseMotion and down:
			accept_event()
			if dragging:
				m.drag_build_move(get_global_transform() * ev.position); return
			if is_ready and cat == "bld" and type != "" and ev.position.distance_to(down_at) > 10:
				dragging = true
				if ui.ring.docked != "": ui.ring.toggle_dock(ui.ring.docked)
				m.drag_build_start(type, get_global_transform() * ev.position); m.buzz(10)
	func _draw() -> void:
		draw_style_box(ui.hsb("normal", lit, 6, 6), Rect2(Vector2.ZERO, size))
		if is_ready: draw_style_box(UI.cut(Color(0, 0, 0, 0), UI.C_AUR, 2, 7, 0), Rect2(Vector2.ZERO, size))
		var ir := Rect2(4, 3, size.x - 8, size.y - 13)
		var it = ui.items.get(cat + ":" + type) if type != "" else null
		if it and it.icon: draw_texture_rect(it.icon, ir, false)
		else:
			# idle: the building itself, dimmed (a crane for the Yard)
			var own = ui.items.get("bld:" + bt)
			if own and own.icon: draw_texture_rect(own.icon, ir, false, Color(1, 1, 1, 0.55))
			else:
				var gs := minf(ir.size.x, ir.size.y) * 0.7
				UI.glyph(self, "bld_crane" if bt == "hq" else "bld", Rect2(ir.get_center() - Vector2(gs, gs) / 2, Vector2(gs, gs)), Color(Color("d9a441"), 0.7))
		if type != "":
			draw_rect(Rect2(5, size.y - 8, size.x - 10, 4), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(5, size.y - 8, (size.x - 10) * clampf(prog, 0, 1), 4), UI.C_AUR)
		UI.ticks(self, size, Color(Color("e5483f") if lit else Color("d9a441"), 0.7 if lit else 0.5), 6.0)
		if n > 1:
			var br := Rect2(size.x - 22, 3, 19, 14)
			draw_style_box(UI.cut(Color("d9a441"), Color(0, 0, 0, 0), 0, 4, 0), br)
			draw_string(ui.f_disp7, Vector2(br.position.x, br.position.y + 11.5), str(n), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 11, Color("1a1408"))
		if loop: UI.glyph(self, "loop", Rect2(4, 3, 14, 14), Color("8fcf7a"))
		if is_ready:
			UI.ready_banner(self, ui, Rect2(0, size.y / 2 - 9, size.x, 16))
			if cat == "bld":   # it drags out towards the map: an arrow on that side
				var l: bool = not ui.prod_col_left()
				var x := -2.0 if l else size.x + 2.0; var y := size.y / 2; var dx := -7.0 if l else 7.0
				draw_colored_polygon(PackedVector2Array([Vector2(x + dx, y), Vector2(x, y - 7), Vector2(x, y + 7)]), UI.C_AUR)

## Builds the top-bar chips for this match's producers (list of building types, the Yard first).
func set_producers(list: Array) -> void:
	for c in chip_box.get_children(): c.queue_free()
	prod_chips.clear()
	for bt in list:
		var pc := ProdChip.new(); pc.ui = self; pc.bt = bt; pc.custom_minimum_size = Vector2(64, 54); pc.visible = false
		chip_box.add_child(pc); prod_chips[bt] = pc

## READY strip across a build card or chip: hazard stripes behind white text, blinking.
static func ready_banner(c: CanvasItem, ui, r: Rect2) -> void:
	var blink := int(Time.get_ticks_msec() / 500) % 2 == 0
	c.draw_rect(r, Color("e5483f") if blink else Color("8a231d"))
	var x := r.position.x - r.size.y; var i := 0
	while x < r.end.x:
		if i % 2 == 0:
			var pts := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y), Vector2(x + r.size.y * 1.5, r.position.y), Vector2(x + r.size.y * 0.5, r.end.y)])
			for k in pts.size(): pts[k].x = clampf(pts[k].x, r.position.x, r.end.x)
			c.draw_colored_polygon(pts, Color(0, 0, 0, 0.18))
		x += r.size.y * 0.5; i += 1
	c.draw_line(Vector2(r.position.x, r.position.y + 0.5), Vector2(r.end.x, r.position.y + 0.5), Color("d9a441"), 1.0)
	c.draw_line(Vector2(r.position.x, r.end.y - 0.5), Vector2(r.end.x, r.end.y - 0.5), Color("d9a441"), 1.0)
	c.draw_string(ui.f_disp7, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 4.5), "READY", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 12, Color.WHITE)

# ---------------- HUD widgets ----------------
## Maps a flat [x0, y0, x1, y1, ...] list in 0..1 into rect r.
static func _pts(r: Rect2, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2): out.append(r.position + Vector2(a[i], a[i + 1]) * r.size)
	return out

## Small vector icons for the HUD, drawn in rect r. Kept to a few flat shapes so they read at 14-24 UI units.
static func glyph(c: CanvasItem, k: String, r: Rect2, col: Color, lw := 2.0) -> void:
	var P := func(x: float, y: float) -> Vector2: return r.position + Vector2(x, y) * r.size
	var dk := col.darkened(0.4)
	match k:
		"aur":  # faceted crystal, lit on the left
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.86, 0.34, 0.5, 1.0, 0.14, 0.34]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.86, 0.34, 0.5, 1.0, 0.56, 0.34]), dk)
			c.draw_colored_polygon(_pts(r, [0.5, 0.0, 0.3, 0.34, 0.5, 0.42]), col.lightened(0.45))
		"pwr":
			c.draw_colored_polygon(_pts(r, [0.62, 0.0, 0.14, 0.58, 0.46, 0.58, 0.36, 1.0, 0.86, 0.4, 0.54, 0.4, 0.74, 0.0]), col)
		"atk":
			var ctr: Vector2 = P.call(0.5, 0.5); var rad := r.size.x * 0.32
			c.draw_arc(ctr, rad, 0, TAU, 24, col, lw, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(ctr + d * r.size.x * 0.16, ctr + d * r.size.x * 0.5, col, lw)
			c.draw_circle(ctr, r.size.x * 0.06, col)
		"stop":
			var oc := PackedVector2Array(); var ctr: Vector2 = P.call(0.5, 0.5)
			for i in 9: oc.append(ctr + Vector2.from_angle(PI / 8 + i * PI / 4) * r.size.x * 0.46)
			c.draw_polyline(oc, col, lw, true)
			c.draw_rect(Rect2(P.call(0.33, 0.33), r.size * 0.34), col)
		"x":
			c.draw_line(P.call(0.2, 0.2), P.call(0.8, 0.8), col, lw + 0.5, true); c.draw_line(P.call(0.8, 0.2), P.call(0.2, 0.8), col, lw + 0.5, true)
		"form":  # two ranks advancing behind a chevron
			c.draw_polyline(_pts(r, [0.24, 0.34, 0.5, 0.1, 0.76, 0.34]), col, lw, true)
			for row in 2:
				for i in 3: c.draw_rect(Rect2(P.call(0.14 + i * 0.27, 0.48 + row * 0.27), r.size * 0.18), col if row == 0 else dk)
		"all":
			var st := PackedVector2Array(); var ctr: Vector2 = P.call(0.5, 0.55)
			for i in 10: st.append(ctr + Vector2.from_angle(-PI / 2 + i * PI / 5) * r.size.x * (0.5 if i % 2 == 0 else 0.21))
			c.draw_colored_polygon(st, col)
		"inf":  # helmeted soldier, head and shoulders
			c.draw_colored_polygon(_pts(r, [0.26, 0.36, 0.3, 0.16, 0.5, 0.06, 0.7, 0.16, 0.74, 0.36, 0.86, 0.38, 0.14, 0.38]), col)
			c.draw_rect(Rect2(P.call(0.36, 0.38), r.size * Vector2(0.28, 0.16)), dk)
			c.draw_colored_polygon(_pts(r, [0.1, 1.0, 0.16, 0.66, 0.36, 0.56, 0.64, 0.56, 0.84, 0.66, 0.9, 1.0]), col)
		"veh":  # tank in profile
			c.draw_colored_polygon(_pts(r, [0.04, 0.8, 0.96, 0.8, 1.0, 0.64, 0.92, 0.52, 0.08, 0.52, 0.0, 0.64]), col)
			c.draw_colored_polygon(_pts(r, [0.24, 0.52, 0.66, 0.52, 0.6, 0.3, 0.3, 0.3]), col)
			c.draw_rect(Rect2(P.call(0.6, 0.36), r.size * Vector2(0.4, 0.08)), col)
			for i in 4: c.draw_circle(P.call(0.2 + i * 0.2, 0.68), r.size.x * 0.06, dk)
		"air":  # aircraft from above
			c.draw_colored_polygon(_pts(r, [0.45, 0.06, 0.5, 0.0, 0.55, 0.06, 0.56, 0.96, 0.44, 0.96]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.3, 0.98, 0.56, 0.98, 0.64, 0.5, 0.52, 0.02, 0.64, 0.02, 0.56]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.78, 0.74, 0.94, 0.26, 0.94]), col)
		"idle":  # hourglass
			c.draw_line(P.call(0.18, 0.06), P.call(0.82, 0.06), col, lw); c.draw_line(P.call(0.18, 0.94), P.call(0.82, 0.94), col, lw)
			c.draw_polyline(_pts(r, [0.26, 0.06, 0.5, 0.5, 0.26, 0.94]), col, lw, true); c.draw_polyline(_pts(r, [0.74, 0.06, 0.5, 0.5, 0.74, 0.94]), col, lw, true)
			c.draw_colored_polygon(_pts(r, [0.5, 0.62, 0.68, 0.9, 0.32, 0.9]), dk)
		"map":  # folded map
			var m := _pts(r, [0.04, 0.2, 0.36, 0.06, 0.64, 0.2, 0.96, 0.06, 0.96, 0.82, 0.64, 0.96, 0.36, 0.82, 0.04, 0.96])
			c.draw_colored_polygon(_pts(r, [0.36, 0.06, 0.64, 0.2, 0.64, 0.96, 0.36, 0.82]), Color(col, 0.35))
			m.append(m[0]); c.draw_polyline(m, col, lw, true)
			c.draw_line(P.call(0.36, 0.06), P.call(0.36, 0.82), col, lw * 0.6); c.draw_line(P.call(0.64, 0.2), P.call(0.64, 0.96), col, lw * 0.6)
		"pause":
			c.draw_rect(Rect2(P.call(0.22, 0.14), r.size * Vector2(0.2, 0.72)), col); c.draw_rect(Rect2(P.call(0.58, 0.14), r.size * Vector2(0.2, 0.72)), col)
		"hide":
			c.draw_polyline(_pts(r, [0.16, 0.18, 0.46, 0.5, 0.16, 0.82]), col, lw + 0.5, true); c.draw_polyline(_pts(r, [0.52, 0.18, 0.82, 0.5, 0.52, 0.82]), col, lw + 0.5, true)
		"build", "bld_crane":  # tower crane
			c.draw_line(P.call(0.32, 0.96), P.call(0.32, 0.08), col, lw + 0.5)
			c.draw_line(P.call(0.06, 0.12), P.call(0.96, 0.12), col, lw)
			c.draw_line(P.call(0.32, 0.0), P.call(0.86, 0.12), col, lw * 0.6); c.draw_line(P.call(0.32, 0.0), P.call(0.1, 0.12), col, lw * 0.6)
			c.draw_line(P.call(0.82, 0.12), P.call(0.82, 0.5), col, lw * 0.6)
			c.draw_rect(Rect2(P.call(0.72, 0.5), r.size * Vector2(0.2, 0.16)), col)
			c.draw_rect(Rect2(P.call(0.14, 0.88), r.size * Vector2(0.38, 0.12)), col)
			c.draw_rect(Rect2(P.call(0.04, 0.08), r.size * Vector2(0.12, 0.12)), dk)
		"bld":  # factory: saw-tooth roof and a stack
			c.draw_colored_polygon(_pts(r, [0.02, 0.96, 0.02, 0.5, 0.3, 0.32, 0.3, 0.5, 0.58, 0.32, 0.58, 0.5, 0.7, 0.5, 0.7, 0.08, 0.86, 0.08, 0.86, 0.5, 0.98, 0.5, 0.98, 0.96]), col)
			for i in 3: c.draw_rect(Rect2(P.call(0.1 + i * 0.27, 0.66), r.size * Vector2(0.14, 0.14)), dk)
		"repair":  # wrench
			var ctr: Vector2 = P.call(0.68, 0.32)
			c.draw_line(P.call(0.16, 0.84), P.call(0.56, 0.44), col, lw + 2.0)
			c.draw_arc(ctr, r.size.x * 0.2, -PI / 4 + 0.75, -PI / 4 + TAU - 0.75, 16, col, lw + 1.0)
		"sell":  # coin stamped with a crystal
			c.draw_arc(P.call(0.5, 0.5), r.size.x * 0.44, 0, TAU, 24, col, lw, true)
			glyph(c, "aur", Rect2(P.call(0.3, 0.22), r.size * Vector2(0.4, 0.56)), col)
		"up":
			c.draw_polyline(_pts(r, [0.16, 0.5, 0.5, 0.18, 0.84, 0.5]), col, lw + 1.0, true); c.draw_polyline(_pts(r, [0.16, 0.86, 0.5, 0.54, 0.84, 0.86]), col, lw + 1.0, true)
		"launch":  # missile
			c.draw_colored_polygon(_pts(r, [0.4, 0.28, 0.5, 0.0, 0.6, 0.28, 0.6, 0.74, 0.4, 0.74]), col)
			c.draw_colored_polygon(_pts(r, [0.4, 0.5, 0.2, 0.8, 0.4, 0.74]), col); c.draw_colored_polygon(_pts(r, [0.6, 0.5, 0.8, 0.8, 0.6, 0.74]), col)
			c.draw_colored_polygon(_pts(r, [0.43, 0.8, 0.57, 0.8, 0.5, 1.0]), Color(col, 0.6))
		"obj":  # pennant on a pole
			c.draw_line(P.call(0.22, 0.04), P.call(0.22, 0.98), col, lw)
			c.draw_colored_polygon(_pts(r, [0.22, 0.06, 0.9, 0.2, 0.64, 0.33, 0.9, 0.48, 0.22, 0.48]), col)
		"loop":  # two arrows chasing round a circle
			var ctr: Vector2 = P.call(0.5, 0.5); var rad := r.size.x * 0.34
			c.draw_arc(ctr, rad, 0.3, PI - 0.3, 12, col, lw + 0.5, true)
			c.draw_arc(ctr, rad, PI + 0.3, TAU - 0.3, 12, col, lw + 0.5, true)
			for a in [PI - 0.3, TAU - 0.3]:
				var tip: Vector2 = ctr + Vector2.from_angle(a) * rad; var tg := Vector2.from_angle(a + PI / 2)
				c.draw_colored_polygon(PackedVector2Array([tip + tg * r.size.x * 0.16, tip + Vector2.from_angle(a) * r.size.x * 0.14, tip - Vector2.from_angle(a) * r.size.x * 0.14]), col)
		"hold":  # shield
			c.draw_colored_polygon(_pts(r, [0.5, 0.04, 0.88, 0.18, 0.84, 0.56, 0.5, 0.96, 0.16, 0.56, 0.12, 0.18]), col)
			c.draw_colored_polygon(_pts(r, [0.5, 0.18, 0.74, 0.27, 0.71, 0.54, 0.5, 0.8]), dk)
		"nofire":  # crosshair struck through
			var ctr: Vector2 = P.call(0.5, 0.5)
			c.draw_arc(ctr, r.size.x * 0.34, 0, TAU, 24, col, lw, true)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				c.draw_line(ctr + d * r.size.x * 0.2, ctr + d * r.size.x * 0.48, col, lw)
			c.draw_line(P.call(0.12, 0.88), P.call(0.88, 0.12), Color("ff5a52"), lw + 1.0, true)
		"scatter":  # four arrows out from the middle
			var ctr: Vector2 = P.call(0.5, 0.5)
			for kk in 4:
				var dv := Vector2.from_angle(PI / 4 + kk * PI / 2)
				var tip := ctr + dv * r.size.x * 0.48; var base := ctr + dv * r.size.x * 0.14
				c.draw_line(base, tip, col, lw, true)
				c.draw_colored_polygon(PackedVector2Array([tip, tip - dv * r.size.x * 0.2 + dv.orthogonal() * r.size.x * 0.1, tip - dv * r.size.x * 0.2 - dv.orthogonal() * r.size.x * 0.1]), col)
		"home":  # house
			c.draw_colored_polygon(_pts(r, [0.5, 0.06, 0.96, 0.46, 0.84, 0.46, 0.84, 0.94, 0.16, 0.94, 0.16, 0.46, 0.04, 0.46]), col)
			c.draw_rect(Rect2(P.call(0.42, 0.62), r.size * Vector2(0.16, 0.32)), dk)
		"jump":  # arc with an arrow at its end
			c.draw_arc(P.call(0.5, 0.8), r.size.x * 0.4, PI, TAU - 0.35, 18, col, lw + 0.5, true)
			c.draw_colored_polygon(_pts(r, [0.98, 0.66, 0.72, 0.62, 0.9, 0.42]), col)
			c.draw_rect(Rect2(P.call(0.04, 0.82), r.size * Vector2(0.92, 0.08)), dk)
		"strip":  # pickaxe
			c.draw_line(P.call(0.2, 0.92), P.call(0.66, 0.34), col, lw + 1.0, true)
			c.draw_arc(P.call(0.6, 0.48), r.size.x * 0.42, -PI * 0.95, -PI * 0.2, 14, col, lw + 1.5, true)
		"fuse":  # three dots drawn into one
			for kk in 3:
				var a := -PI / 2 + kk * TAU / 3
				c.draw_circle(P.call(0.5, 0.52) + Vector2.from_angle(a) * r.size.x * 0.36, r.size.x * 0.11, dk)
				c.draw_line(P.call(0.5, 0.52) + Vector2.from_angle(a) * r.size.x * 0.24, P.call(0.5, 0.52) + Vector2.from_angle(a) * r.size.x * 0.12, col, lw)
			c.draw_circle(P.call(0.5, 0.52), r.size.x * 0.17, col)
		"lock":
			c.draw_arc(P.call(0.5, 0.42), r.size.x * 0.2, PI, TAU, 12, col, lw)
			c.draw_line(P.call(0.3, 0.42), P.call(0.3, 0.5), col, lw); c.draw_line(P.call(0.7, 0.42), P.call(0.7, 0.5), col, lw)
			c.draw_rect(Rect2(P.call(0.2, 0.48), r.size * Vector2(0.6, 0.46)), col)
			c.draw_rect(Rect2(P.call(0.46, 0.6), r.size * Vector2(0.08, 0.18)), dk)
		"warn":  # hazard triangle
			c.draw_colored_polygon(_pts(r, [0.5, 0.04, 0.98, 0.94, 0.02, 0.94]), col)
			c.draw_rect(Rect2(P.call(0.45, 0.34), r.size * Vector2(0.1, 0.34)), Color(0, 0, 0, 0.85)); c.draw_rect(Rect2(P.call(0.45, 0.74), r.size * Vector2(0.1, 0.1)), Color(0, 0, 0, 0.85))
		"info":  # chevron: a field order
			c.draw_colored_polygon(_pts(r, [0.1, 0.1, 0.55, 0.5, 0.1, 0.9, 0.35, 0.9, 0.8, 0.5, 0.35, 0.1]), col)
		"move":
			c.draw_colored_polygon(_pts(r, [0.5, 0.02, 0.86, 0.42, 0.62, 0.42, 0.62, 0.96, 0.38, 0.96, 0.38, 0.42, 0.14, 0.42]), col)
		"box":
			for q in [[0.1, 0.1, 1, 1], [0.9, 0.1, -1, 1], [0.9, 0.9, -1, -1], [0.1, 0.9, 1, -1]]:
				var o: Vector2 = P.call(q[0], q[1])
				c.draw_line(o, o + Vector2(q[2] * r.size.x * 0.3, 0), col, lw); c.draw_line(o, o + Vector2(0, q[3] * r.size.y * 0.3), col, lw)
			c.draw_rect(Rect2(P.call(0.38, 0.38), r.size * 0.24), col)

## Thin health bar under the panel header (val 0..1, hidden below 0).
class HpBar extends Control:
	var val := -1.0
	func set_val(x: float) -> void:
		if absf(x - val) < 0.005: return
		val = x; queue_redraw()
	func _draw() -> void:
		if val < 0: return
		draw_rect(Rect2(Vector2.ZERO, size), Color("2a2f22"))
		draw_rect(Rect2(0, 0, size.x * clampf(val, 0, 1), size.y), Color("8fcf7a") if val > 0.5 else (Color("f0b93f") if val > 0.25 else Color("ff5a52")))

class Glyph extends Control:
	var kind := ""
	var col := Color.WHITE
	func _draw() -> void:
		UI.glyph(self, kind, Rect2(Vector2.ZERO, size), col)

## Brass hairline with a dark shadow line beside it, as a divider.
class Rule extends Control:
	var vertical := false
	func _draw() -> void:
		if vertical:
			var x := size.x / 2
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), Color("d9a441", 0.45), 1.0)
			draw_line(Vector2(x + 1, 2), Vector2(x + 1, size.y - 2), Color(0, 0, 0, 0.5), 1.0)
		else:
			draw_line(Vector2(0, 0.5), Vector2(size.x, 0.5), Color("d9a441", 0.45), 1.0)
			draw_line(Vector2(0, 1.5), Vector2(size.x, 1.5), Color(0, 0, 0, 0.5), 1.0)

## HUD plate: draws its stylebox, then brass ticks on the two square corners and an optional coloured left bar.
class Plate extends PanelContainer:
	var accent := Color("d9a441")
	func _draw() -> void:
		var s := get_theme_stylebox("panel")
		if s and s.has_meta("bar"):
			draw_rect(Rect2(0, 7, 3, size.y - 7), s.get_meta("bar"))
		UI.ticks(self, size, Color(accent, 0.85))

## Brass L-ticks on the top-right and bottom-left corners (the other two are chamfered).
static func ticks(c: CanvasItem, s: Vector2, col: Color, L := 7.0) -> void:
	c.draw_line(Vector2(s.x - L, 0.75), Vector2(s.x - 0.75, 0.75), col, 1.5); c.draw_line(Vector2(s.x - 0.75, 0.75), Vector2(s.x - 0.75, L), col, 1.5)
	c.draw_line(Vector2(0.75, s.y - L), Vector2(0.75, s.y - 0.75), col, 1.5); c.draw_line(Vector2(0.75, s.y - 0.75), Vector2(L, s.y - 0.75), col, 1.5)

## HUD button with a glyph: left of the text, centred when there is no text, or above a caption (`cap`, the build tabs).
class HudBtn extends Button:
	var glyph := ""
	var cap := ""
	func _draw() -> void:
		var on: bool = get_meta("on", false)
		var col: Color = Color("ffd8d2") if on else Color("d9a441")
		if disabled: col = Color(col, 0.45)
		if is_hovered() or button_pressed: col = col.lightened(0.15)
		UI.ticks(self, size, Color(Color("e5483f") if on else Color("d9a441"), 0.7 if on else 0.4), 6.0)
		if glyph == "": return
		if cap != "":
			var gs := 18.0
			UI.glyph(self, glyph, Rect2(size.x / 2 - gs / 2, 6, gs, gs), col)
			var f := get_theme_font("font")
			draw_string(f, Vector2(0, size.y - 7), cap, HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color("ffd8d2") if on else Color("a99c78"))
		elif text == "":
			var gs := minf(20.0, size.y * 0.42)
			UI.glyph(self, glyph, Rect2((size - Vector2(gs, gs)) / 2, Vector2(gs, gs)), col)
		else:
			var gs := 18.0
			UI.glyph(self, glyph, Rect2(12, (size.y - gs) / 2, gs, gs), col)

## A chip on the squad strip. key > 0: a squad (number, count, main unit type, health bar, a red mark under fire, a
## dim one while idle). 0: ALL. -1: NEW, the units in no squad.
class SquadChip extends Button:
	var ui
	var key := 0
	var st := {}
	var lit := false
	func set_state(s: Dictionary, on: bool) -> void:
		if s == st and on == lit: return
		st = s.duplicate(); lit = on; queue_redraw()
	func _draw() -> void:
		var state := "pressed" if button_pressed else ("hover" if is_hovered() else "normal")
		draw_style_box(ui.hsb(state, lit, 6, 6), Rect2(Vector2.ZERO, size))
		var n: int = st.get("n", 0)
		var kh := Color("ffd8d2") if lit else Color("d8cba3")
		var brass := Color("d9a441")
		if key == 0:
			UI.glyph(self, "all", Rect2(9, size.y / 2 - 13, 16, 16), kh)
			draw_string(ui.f_disp, Vector2(29, size.y / 2 + 1), "ALL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, kh)
			draw_string(ui.f_body, Vector2(10, size.y - 8), "%d units" % n, HORIZONTAL_ALIGNMENT_LEFT, size.x - 14, 10, Color("a99c78"))
			return
		if key == -1:
			draw_string(ui.f_disp, Vector2(9, size.y / 2 + 1), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, brass)
			draw_string(ui.f_disp, Vector2(0, size.y / 2 + 1), "×%d" % n, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 9, 12, brass)
			draw_string(ui.f_body, Vector2(9, size.y - 8), "no squad", HORIZONTAL_ALIGNMENT_LEFT, size.x - 14, 10, Color("a99c78"))
			return
		draw_string(ui.f_disp7, Vector2(9, size.y / 2 + 9), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, kh)
		draw_string(ui.f_disp, Vector2(0, 17), "×%d" % n, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 12, brass)
		if st.get("hit", false):
			draw_string(ui.f_disp, Vector2(28, 17), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ff5a52"))
		elif st.get("idle", false):
			draw_string(ui.f_body, Vector2(28, 16), "idle", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("a99c78"))
		draw_string(ui.f_body, Vector2(0, size.y - 13), String(st.get("name", "")).to_upper().left(13), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 9, Color("a99c78"))
		var hp: float = st.get("hp", 0.0)
		var bw := size.x - 16
		draw_rect(Rect2(8, size.y - 8, bw, 3), Color("2a2f22"))
		draw_rect(Rect2(8, size.y - 8, bw * hp, 3), Color("8fcf7a") if hp > 0.5 else (Color("f0b93f") if hp > 0.25 else Color("ff5a52")))

## Power use against supply as ten segments; red when the base is short of power.
class PowerMeter extends Control:
	var frac := 0.0
	var low := false
	func set_val(f: float, l: bool) -> void:
		if is_equal_approx(f, frac) and l == low: return
		frac = f; low = l; queue_redraw()
	func _draw() -> void:
		var n := 10; var gap := 2.0; var w := (size.x - gap * (n - 1)) / n
		var on := Color("ff5a52") if low else Color("8fcf7a")
		for i in n:
			var lit := (i + 0.5) / n <= frac or (i == 0 and frac > 0)
			draw_rect(Rect2(i * (w + gap), 0, w, size.y), on if lit else Color("2a2f22"))
