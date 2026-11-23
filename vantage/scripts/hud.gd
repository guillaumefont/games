class_name Hud
extends Control
## The interface: the in-flight HUD (hull, score, scrap, banners, boss bar), the cockpit's
## canopy and reticle in the carrier, the hangar (upgrades, launch) and the results.

const FONT := preload("res://fonts/Inter-Variable.ttf")
const INK := Color8(0xf2, 0xf6, 0xfa)
const DIM := Color(0.86, 0.92, 1.0, 0.7)
const GOLD := Color8(0xff, 0xd2, 0x4a)
const CY := Color8(0x5f, 0xe2, 0xff)
const RED := Color8(0xff, 0x4d, 0x6d)

var game: Game
var score_l: Label
var scrap_l: Label
var banner_l: Label
var sub_l: Label
var hangar: Control
var results: Control
var hangar_scrap: Label
var hangar_best: Label
var rows := {}
var res_title: Label
var res_body: Label
var res_hint: Label
var hurt_t := 0.0
var scrap_t := 0.0


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
	var tag := label(26, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	tag.text = "Sector 1 · Glass Coast"
	tag.reparent(hangar)
	place(tag, Rect2(0, 0, 1, 0), Rect2(0, 218, 0, 40))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", glass())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_top = 1.0
	panel.offset_left = 24
	panel.offset_right = -24
	panel.offset_top = -700
	panel.offset_bottom = -30
	hangar.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
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
	hangar_best = label(22, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	hangar_best.reparent(v)
	var go := button("LAUNCH", CY, 40)
	go.custom_minimum_size = Vector2(0, 104)
	go.pressed.connect(func() -> void: game.launch())
	v.add_child(go)


func refresh_hangar() -> void:
	var s := game.s
	hangar_scrap.text = "◆ " + Rules.fmt(s.scrap)
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
	var build: String = ProjectSettings.get_setting("application/config/version", "")
	if build != "":
		hangar_best.text += "   ·   " + build


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
	res_title.text = "SECTOR CLEAR" if r.cleared else "SHOT DOWN"
	res_title.add_theme_color_override("font_color", CY if r.cleared else RED)
	var lines := ["Score  %s%s" % [Rules.fmt(r.score), "  (best!)" if r.new_best else ""],
		"Scrap  ◆ %s" % Rules.fmt(r.scrap),
		"Kills  %d / %d" % [r.kills, Rules.stage_foes()],
		"Hits taken  %d" % r.hits]
	if r.cleared:
		lines.append("Grade  %s" % r.grade)
	res_body.text = "\n".join(lines)


# ---------------------------------------------------------------- in flight

func ping_scrap() -> void:
	scrap_t = 0.25


func flash_hurt() -> void:
	hurt_t = 0.35


func sync() -> void:
	var dt := get_process_delta_time()
	hurt_t = maxf(0.0, hurt_t - dt)
	scrap_t = maxf(0.0, scrap_t - dt)
	var playing := game.phase not in ["hangar", "results"]
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
	var ck := game.cockpit_k()
	if ck > 0.0:
		draw_cockpit(v, ck)
	if game.pov_mode() and ck > 0.5:
		draw_locks()
		draw_reticle(game.aim, ck)
	if game.phase not in ["hangar", "results"]:
		# hull pips
		var mx := Rules.max_hp(game.s)
		for i in mx:
			var r := Rect2(30 + i * 42, 34, 32, 32)
			draw_rect(r, Color(1, 1, 1, 0.16), true)
			if i < game.hp:
				draw_rect(r.grow(-5), CY if game.hp > 1 else RED, true)
		# boss / reactor bar
		var b := game.boss if game.boss else game.core
		if b and not b.dead:
			var w := v.x - 120
			var frac := clampf(b.hp / b.max_hp, 0, 1)
			draw_rect(Rect2(60, 120, w, 12), Color(1, 1, 1, 0.18))
			draw_rect(Rect2(60, 120, w * frac, 12), RED if not (b == game.core and game.shielded()) else CY)
	if hurt_t > 0.0:
		draw_rect(Rect2(Vector2.ZERO, v), Color(1, 0.2, 0.25, hurt_t * 0.5))


## The canopy frame and dashboard, faded in as the camera enters the cockpit.
func draw_cockpit(v: Vector2, k: float) -> void:
	var frame := Color(0.07, 0.09, 0.12, 0.96 * k)
	var edge := Color(0.55, 0.7, 0.85, 0.5 * k)
	var sway := game.pvel * Vector2(-4, 4)
	sway = sway.clamp(Vector2(-30, -20), Vector2(30, 20))
	# canopy struts from the dashboard's corners up to the top
	var dash_y := v.y * 0.84 + sway.y
	var l := PackedVector2Array([Vector2(0, dash_y), Vector2(0, 0), Vector2(v.x * 0.07, 0),
		Vector2(v.x * 0.2 + sway.x, dash_y)])
	var r := PackedVector2Array([Vector2(v.x, dash_y), Vector2(v.x * 0.8 + sway.x, dash_y),
		Vector2(v.x * 0.93, 0), Vector2(v.x, 0)])
	draw_colored_polygon(l, frame)
	draw_colored_polygon(r, frame)
	draw_line(Vector2(v.x * 0.07, 0), Vector2(v.x * 0.2 + sway.x, dash_y), edge, 3)
	draw_line(Vector2(v.x * 0.93, 0), Vector2(v.x * 0.8 + sway.x, dash_y), edge, 3)
	draw_rect(Rect2(0, 0, v.x, v.y * 0.035), frame)
	# dashboard
	var dash := PackedVector2Array([Vector2(0, v.y), Vector2(0, dash_y), Vector2(v.x * 0.3 + sway.x, dash_y - 26),
		Vector2(v.x * 0.7 + sway.x, dash_y - 26), Vector2(v.x, dash_y), Vector2(v.x, v.y)])
	draw_colored_polygon(dash, frame)
	draw_polyline(PackedVector2Array([Vector2(0, dash_y), Vector2(v.x * 0.3 + sway.x, dash_y - 26),
		Vector2(v.x * 0.7 + sway.x, dash_y - 26), Vector2(v.x, dash_y)]), edge, 3)
	# two small screens: hull and scrap
	var sy := dash_y + 20
	var a := k
	var scr := Color(0.1, 0.35, 0.45, 0.8 * a)
	draw_rect(Rect2(v.x * 0.14, sy, v.x * 0.26, 70), scr)
	draw_rect(Rect2(v.x * 0.6, sy, v.x * 0.26, 70), scr)
	draw_string(FONT, Vector2(v.x * 0.14 + 14, sy + 30), "HULL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(CY, a))
	for i in Rules.max_hp(game.s):
		var c := CY if i < game.hp else Color(1, 1, 1, 0.15)
		draw_rect(Rect2(v.x * 0.14 + 14 + i * 26, sy + 42, 18, 14), Color(c, a))
	draw_string(FONT, Vector2(v.x * 0.6 + 14, sy + 30), "RAIL", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(CY, a))
	var prog := clampf(game.rail_s / Rules.CORE_AT, 0, 1)
	draw_rect(Rect2(v.x * 0.6 + 14, sy + 44, v.x * 0.26 - 28, 10), Color(1, 1, 1, 0.15 * a))
	draw_rect(Rect2(v.x * 0.6 + 14, sy + 44, (v.x * 0.26 - 28) * prog, 10), Color(GOLD, a))


func draw_reticle(p: Vector2, k: float) -> void:
	var c := Color(CY, 0.95 * k)
	draw_arc(p, 34, 0, TAU, 40, c, 3, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(p + d * 22, p + d * 46, c, 3)
	draw_circle(p, 4, c)


## Brackets on the foes ahead, so they read inside the dark tunnel.
func draw_locks() -> void:
	for f: Game.Obj in game.foes:
		if f.dead or f.kind == "orb":
			continue
		if game.cam.is_position_behind(f.pos):
			continue
		var p := game.cam.unproject_position(f.pos)
		var dist := game.cam.global_position.distance_to(f.pos)
		var r := clampf(f.r * 700.0 / maxf(dist, 1.0), 14, 90)
		var c := Color(RED, 0.85)
		if f.kind == "core" and game.shielded():
			c = Color(CY, 0.7)
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				var corner := p + Vector2(sx, sy) * r
				draw_line(corner, corner - Vector2(sx * r * 0.4, 0), c, 2)
				draw_line(corner, corner - Vector2(0, sy * r * 0.4), c, 2)
