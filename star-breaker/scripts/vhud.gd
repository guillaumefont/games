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
signal ground_pressed
signal refresh_pressed
signal pause_pressed
signal ult_pressed
signal tier_pressed(tier: int)
signal paint_chosen(ship: String, id: String)
signal level_pressed(ship: String)
signal ship_chosen(ship: String)
signal ship_buy_pressed(ship: String)
signal paint_buy_pressed(ship: String, id: String)
signal flux_buy_pressed

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
## The ship the hangar shows: the one you fly, or a locked one you are looking at.
var view_ship := "lance"
var _lock_lbl: Label
var score := "0"
var hull := 3
var ships := 3
var ult_ready := false
var charge := 0.0
var charge_lv := 0
## Ships with a kit: the line under the ultimate meter, and 1 right after the meter gains,
## fading to 0.
var kit_hint := ""
var shat_flash := 0.0
## Lance's bar marks as parts of the whole bar: LV 2, LV 3, the Nova (the Storm is the end).
var charge_marks := [50.0 / 300.0, 100.0 / 300.0, 160.0 / 300.0, 240.0 / 300.0]
var boss := -1.0
var boss_name := ""
var stage_name := ""
var playing := false
## Replay progress (set by the game after loading the save) and the tier picked on the menu.
var prog: Progress
var tier := 0

var menu_scr: Control
## The menu's other screens: levels (the map of every stage, see VMap, with the ship you fly
## and a panel for the stage you pick) and the hangar (`medals_scr`: pick a ship, level it up,
## paint it). `screen` is the one showing.
var levels_scr: Control
## The stage panel on the level map: the picked stage, its tiers (pick one), medals, Play.
var sheet: PanelContainer
var sheet_stage := -1
var _sheet_title: Label
var _sheet_sub: Label
var _sheet_tiers: Array = []
var _sheet_pips: Pips
var _sheet_note: Label
var _sheet_play: Button
var _home_ship: ShipView
var screen := "menu"
## Where the hangar's Back goes: the screen it was opened from.
var _hangar_from := "menu"
var _btn_play: Button
var _home_next: Label
var _ship_secs := {}
var pause_scr: Control
var result_scr: Control
var carousel: ShipCarousel
## The level map (see VMap) and the world in view.
var map: VMap
var world_sel := 0
var bests: Array = []
var _crash: PanelContainer
var _crash_txt: Label
var _crash_report := ""
var _btn_copy: Button
var _btn_gfx: Button
var btn_mute: Button
var btn_build: Button
## World 1's ground design (preview switch, see `Terrain.DESIGNS`).
var btn_ground: Button
var _build_id := ""
var _result_title: Label
var _result_sub: Label
var _result_next: Button
var _banner: Label
var _banner_sub: Label
var _banner_t := 0
var btn_pause: Button
var _tier_btns: Array = []
var _btn_medals: Button
var medals_scr: Control
var _medals_total: Label
var _paint_btns := {}
var _flux_lbl: Label
const C_PRISM := Color("b9a8ff")
var _btn_flux_buy: Button
var _btn_ship_buy: Button
## ship -> the locked colour tapped last (offered for prisms by that ship's buy button)
var _want := {}
var _paint_buy := {}
var _level_lbls := {}
var _level_btns := {}
var _result_pips: Pips
var _result_lines: Label
var _result_tier: Button


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
	levels_scr = _build_levels()
	select_ship(ship)
	focus_next()
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
	var t := _label("STAR BREAKER", 52, 800, C_TEXT, 6.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var gap := Control.new()
	gap.custom_minimum_size.y = 36
	v.add_child(gap)
	# the ship you fly, drawn big, with its level, flux and medals: tap it for the hangar
	_btn_medals = _button("", false, 280)
	_btn_medals.add_theme_font_size_override("font_size", 20)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBoxFlat = _btn_medals.get_theme_stylebox(st)
		sb.content_margin_top = 196
	_btn_medals.pressed.connect(func(): show_screen("hangar"))
	_home_ship = ShipView.new(Vector2i(640, 240), 19.0)
	_home_ship.position = Vector2(2, 2)
	_home_ship.size = Vector2(COL_W - 4, 192)
	_btn_medals.add_child(_home_ship)
	var tag := _label("GARAGE  ›", 14, 800, C_MUTED, 2.0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.position = Vector2(COL_W - 150, 18)
	tag.size = Vector2(128, 20)
	_btn_medals.add_child(tag)
	v.add_child(_center(_btn_medals))
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 28
	v.add_child(gap2)
	_btn_play = _button("Play", true, 104)
	_btn_play.add_theme_font_size_override("font_size", 34)
	_btn_play.pressed.connect(func():
		show_screen("levels")
		focus_next())
	v.add_child(_center(_btn_play))
	_home_next = _label("", 16, 700, C_MUTED, 2.0)
	_home_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_home_next)
	var gap3 := Control.new()
	gap3.custom_minimum_size.y = 40
	v.add_child(gap3)
	_build_device(v)
	return v.get_parent()


## The level screen: the map of every stage (see VMap) filling the screen, a Back button, and the
## panel of the stage you pick. The ship lives on the home screen, not here.
func _build_levels() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	map = VMap.new(self)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.stage_tapped.connect(open_stage)
	root.add_child(map)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.custom_minimum_size = Vector2(COL_W, 84)
	bar.position = Vector2(-COL_W / 2.0, 36)
	bar.size = bar.custom_minimum_size
	bar.name = "bar"
	root.add_child(bar)
	var back := Button.new()
	back.text = "‹"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(84, 84)
	_style_button(back, false, 26)
	back.add_theme_font_size_override("font_size", 40)
	back.pressed.connect(func(): back())
	bar.add_child(back)
	sheet = _build_sheet()
	root.add_child(sheet)
	return root


## The panel of a picked stage: its name and world, a button per tier (locked ones say what
## opens them), the medals held on the chosen tier and its best score, and Play.
func _build_sheet() -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(11 / 255.0, 8 / 255.0, 38 / 255.0, 0.96)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(30)
	sb.set_content_margin_all(24)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 24
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pc.custom_minimum_size = Vector2(COL_W + 48, 0)
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.offset_bottom = -28
	pc.offset_left = -(COL_W + 48) / 2.0
	pc.offset_right = (COL_W + 48) / 2.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var head := HBoxContainer.new()
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_title = _label("", 28, 800, C_TEXT, 2.0)
	tv.add_child(_sheet_title)
	_sheet_sub = _label("", 15, 700, C_MUTED, 2.0)
	tv.add_child(_sheet_sub)
	head.add_child(tv)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(60, 60)
	_style_button(close, false, 30)
	close.add_theme_font_size_override("font_size", 30)
	close.pressed.connect(close_stage)
	head.add_child(close)
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for t in Progress.TIERS.size():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2((COL_W - 20) / 3.0, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): pick_tier(t))
		b.set_meta("tier", t)
		row.add_child(b)
		_sheet_tiers.append(b)
		_tier_btns.append(b)
	v.add_child(row)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	_sheet_pips = Pips.new()
	mrow.add_child(_sheet_pips)
	_sheet_note = _label("", 15, 700, C_MUTED, 1.0)
	_sheet_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sheet_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_sheet_note)
	v.add_child(mrow)
	_sheet_play = _button("Play", true, 84)
	_sheet_play.custom_minimum_size.x = 0
	_sheet_play.add_theme_font_size_override("font_size", 30)
	_sheet_play.pressed.connect(play_picked)
	v.add_child(_sheet_play)
	pc.hide()
	return pc


## Opens the panel of stage `i` on the tier picked last (or the highest one open for it).
func open_stage(i: int) -> void:
	sheet_stage = i
	map.picked = i
	# keep the stage in sight above the panel
	map.focus(i, false, 0.5)
	var id := Progress.stage_id(i)
	tier = prog.best_open(id, tier) if prog else 0
	sheet.show()
	_update_sheet()


func close_stage() -> void:
	sheet_stage = -1
	if map:
		map.picked = -1
	if sheet:
		sheet.hide()


## Picks tier `t` on the stage panel; a closed tier stays unpicked and the note says why.
func pick_tier(t: int) -> void:
	if sheet_stage < 0:
		return
	if prog and not prog.open(sheet_stage, t):
		_sheet_note.text = map.lock_reason(sheet_stage, t).to_upper()
		_sheet_note.add_theme_color_override("font_color", C_AMBER)
		return
	tier = t
	_update_sheet()


func play_picked() -> void:
	if sheet_stage < 0:
		return
	var i := sheet_stage
	close_stage()
	stage_chosen.emit(i, ship)


func _update_sheet() -> void:
	if sheet_stage < 0 or _sheet_title == null:
		return
	var i := sheet_stage
	var st: Dictionary = VStage.STAGES[i]
	var wd: Dictionary = Worlds.LIST[st.world]
	_sheet_title.text = ("%d  %s" % [st.j + 1, st.name]).to_upper()
	var sub := "%s  ·  %s" % [wd.sub, wd.name]
	if st.j == VStage.PER_WORLD - 1:
		sub += "  ·  " + String(wd.boss_name)
	_sheet_sub.text = sub.to_upper()
	var id := Progress.stage_id(i)
	for b in _sheet_tiers:
		var t: int = b.get_meta("tier")
		var open: bool = prog == null or prog.open(i, t)
		b.text = String(Progress.TIERS[t].name).to_upper() + ("" if open else "\nLOCKED")
		_style_tier(b, t)
		b.add_theme_font_size_override("font_size", 16 if open else 14)
		b.modulate.a = 1.0 if open else 0.45
	_sheet_pips.set_medals(prog.medals(id, tier) if prog else 0)
	var best := int(bests[i]) if i < bests.size() else 0
	var note := "%s  ·  %d of 4 medals" % [Progress.tier(tier).name, Progress.bits(prog.medals(id, tier) if prog else 0)]
	if best > 0:
		note += "  ·  best " + _fmt(best)
	_sheet_note.text = note.to_upper()
	_sheet_note.add_theme_color_override("font_color", C_MUTED)
	var col := Color(String(Progress.tier(tier).color))
	_sheet_play.text = ("Play on " + String(Progress.tier(tier).name)).to_upper()
	for stn in ["normal", "hover", "pressed", "focus"]:
		var sb: StyleBoxFlat = _sheet_play.get_theme_stylebox(stn)
		sb.bg_color = col if stn != "pressed" else col.lightened(0.15)
		sb.shadow_color = Color(col, 0.35)


## Shows world `w` on the stage map.
func select_world(w: int) -> void:
	world_sel = clampi(w, 0, VStage.WORLDS.size() - 1)
	if map:
		map.focus_world(world_sel, true)
	refresh_progress()


## Scrolls the map to stage `i` (or the next stage to play, when -1).
func focus_next(i := -1) -> void:
	if i < 0:
		i = map.next_stage() if map else 0
	world_sel = VStage.world_of(maxi(i, 0))
	if map:
		map.focus(maxi(i, 0), true)
	refresh_progress()


## A stage's text on the map: number and name, then its best score, NEXT or LOCKED.
func stage_label(i: int) -> String:
	return map.stage_text(i) if map else ""


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
	btn_ground = _small_button("")
	btn_ground.pressed.connect(func(): ground_pressed.emit())
	v.add_child(_center(btn_ground))
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


func set_ground(name: String) -> void:
	btn_ground.text = "WORLD 1 GROUND: %s" % name.to_upper()


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
	if map != null:
		select_world(world_sel)


## Redraws everything that shows progress: the tier row, the shown world's stage labels, medals
## and locks, the medal count and the ship colours.
func refresh_progress() -> void:
	for b in _tier_btns:
		_style_tier(b, int(b.get_meta("tier")))
	_update_home()
	_update_sheet()
	if map:
		map.queue_redraw()
	if prog and _btn_medals:
		_medals_total.text = "MEDALS %d / %d" % [prog.total(), Progress.max_total()]
		_flux_lbl.text = "%s FLUX  ·  %s PRISMS" % [_fmt(prog.flux), _fmt(prog.prisms)]
		_btn_flux_buy.text = "+%d FLUX  ·  %d PRISMS" % [Progress.FLUX_PACK, Progress.FLUX_PACK_PRISMS]
		_btn_flux_buy.disabled = prog.prisms < Progress.FLUX_PACK_PRISMS
		_btn_flux_buy.modulate.a = 0.45 if _btn_flux_buy.disabled else 1.0
		for k in _paint_buy:
			var pb: Button = _paint_buy[k]
			var want: String = _want.get(k, "")
			pb.visible = want != "" and not prog.scheme_open(k, want)
			if pb.visible:
				pb.text = ("Unlock %s  ·  %d prisms" % [Progress.scheme(k, want).name, Progress.PAINT_PRISMS]).to_upper()
				pb.disabled = prog.prisms < Progress.PAINT_PRISMS
				pb.modulate.a = 0.45 if pb.disabled else 1.0
		_update_ship_buy()
		for k in _level_btns:
			var lv := prog.level(k)
			_level_lbls[k].text = "%s  ·  LV %d  ·  +%d%% DAMAGE" % [VShips.rank_text(k), lv, int(round((Progress.power(lv) - 1.0) * 100.0))]
			var b: Button = _level_btns[k]
			if lv >= Progress.MAX_LEVEL:
				b.text = "MAX LEVEL"
				b.disabled = true
			else:
				var cost := Progress.level_cost(lv)
				b.text = "LEVEL UP  ·  %s FLUX" % _fmt(cost)
				b.disabled = prog.flux < cost
			b.modulate.a = 0.5 if b.disabled else 1.0
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


## Shows ship `k` in the hangar, and flies it from now on if it is open.
func select_ship(k: String) -> void:
	view_ship = k
	var open := prog == null or prog.ship_open(k)
	if open and ship != k:
		ship = k
		ship_chosen.emit(k)
	if carousel:
		carousel.queue_redraw()
	for key in _ship_secs:
		_ship_secs[key].visible = key == k and open
	if _lock_lbl:
		_lock_lbl.visible = not open
		if not open:
			var need := int(VShips.KITS[k].unlock)
			_lock_lbl.text = "%s  ·  LOCKED\nCLEAR %d STAGES ON NORMAL (%d SO FAR)" % [VShips.rank_text(k), need, prog.cleared_count()]
	_update_ship_buy()
	_update_how()
	_update_home()


## The hangar's "unlock now" button under a locked ship: its price in prisms falls with every
## stage cleared, and it dims when you can't afford it.
func _update_ship_buy() -> void:
	if _btn_ship_buy == null or prog == null:
		return
	var price := prog.ship_price(view_ship)
	_btn_ship_buy.visible = price > 0
	if price > 0:
		_btn_ship_buy.text = "UNLOCK NOW  ·  %d PRISMS" % price
		_btn_ship_buy.disabled = prog.prisms < price
		_btn_ship_buy.modulate.a = 0.45 if _btn_ship_buy.disabled else 1.0


## The home screen's lines: the next stage under Play, and the ship button (ship, level, flux,
## medals).
func _update_home() -> void:
	if _btn_medals == null:
		return
	var kit: Dictionary = VShips.KITS[ship]
	var lv := prog.level(ship) if prog else 1
	var l2 := "HANGAR"
	if prog:
		l2 = "%s FLUX  ·  %s PRISMS  ·  MEDALS %d" % [_fmt(prog.flux), _fmt(prog.prisms), prog.total()]
	_btn_medals.text = "%s  ·  LV %d\n%s" % [String(kit.name).to_upper(), lv, l2]
	if _home_ship:
		_home_ship.show_ship(ship, prog.paint_of(ship) if prog else {})
	if carousel:
		carousel.refresh()
	if _home_next:
		var n := prog.next_stage(0) if prog else 0
		if n < 0:
			_home_next.text = ""
		else:
			var st: Dictionary = VStage.STAGES[n]
			_home_next.text = ("Next  ·  world %d  ·  %d %s" % [st.world + 1, st.j + 1, st.name]).to_upper()


func _update_how() -> void:
	var how: Label = medals_scr.find_child("how", true, false) if medals_scr else null
	if not how:
		return
	var k := view_ship
	var t := "%s. Drag to fly, the guns fire on their own." % VShips.KITS[k].sub
	if VShips.KITS[k].ult == "storm":
		t += " Keep charging past the Nova and lift for the %s: lightning on every enemy." % VShips.KITS[k].ult_name
	else:
		t += " %s: once the bar is full, your next lift fires it." % VShips.KITS[k].loads
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


## Shows one of "menu" (home), "levels", "hangar", "pause", "result" or "play" (no menu, the
## HUD only).
func show_screen(which: String) -> void:
	if which == "medals":
		which = "hangar"
	if which == "hangar" and screen != "hangar":
		_hangar_from = screen if screen in ["menu", "levels"] else "menu"
	screen = which
	menu_scr.visible = which == "menu"
	medals_scr.visible = which == "hangar"
	if levels_scr:
		levels_scr.visible = which == "levels"
		if which != "levels":
			close_stage()
	pause_scr.visible = which == "pause"
	result_scr.visible = which == "result"
	playing = which == "play" or which == "pause"
	btn_pause.visible = which == "play"
	queue_redraw()


## Back from a menu screen to the one before it (a stage panel closes first; levels and the
## hangar go home). False on the home screen, where back leaves the app.
func back() -> bool:
	match screen:
		"levels":
			if sheet_stage >= 0:
				close_stage()
			else:
				show_screen("menu")
		"hangar":
			show_screen(_hangar_from)
		_:
			return false
	return true


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
	_banner.position = Vector2(0, sz.y * 0.36)
	_banner.size = Vector2(sz.x, 70)
	_banner_sub.position = Vector2(0, sz.y * 0.36 + 74)
	_banner_sub.size = Vector2(sz.x, 30)


## True when `p` (canvas position) is on a HUD control, so a touch there is not a thumb.
func on_control(p: Vector2) -> bool:
	return btn_pause.visible and btn_pause.get_global_rect().grow(12).has_point(p)


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
	_draw_charge_bar(f)
	# boss bar along the top
	if boss >= 0.0:
		# right of the score, left of the pause button
		var bw2 := sz.x - 210.0 - 120.0
		var r2 := Rect2(210, 52, bw2, 10)
		draw_rect(r2, Color(1, 1, 1, 0.12))
		draw_rect(Rect2(r2.position, Vector2(bw2 * clampf(boss, 0, 1), 10)), C_SPORE)
		draw_string(fonts[700], Vector2(210, 44), boss_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_SPORE)


## The ultimate bar under the score. Lance's is the charge bar while the thumb is down: LV 1-3,
## the Nova, then the Storm's pink stretch whose label lights up once the charge runs into it.
## Every other ship's is its kit's ultimate meter, kept through lifts: always shown, all pink,
## flashing each time it gains; the kit's line under the bar says what loads it, and once full,
## that a lift fires it.
func _draw_charge_bar(_f: Font) -> void:
	if ship != "lance" and playing:
		_draw_meter_bar()
		return
	if charge <= 0.0:
		return
	var bx := 30.0
	var by := 140.0
	var bw := 240.0
	var beam := ship == "lance"
	var nova: float = charge_marks[3] if beam else 0.0
	draw_rect(Rect2(bx, by, bw, 8), Color(1, 1, 1, 0.12))
	# the Storm's stretch
	var sx := bx + bw * nova
	var sw := bw * (1.0 - nova)
	draw_rect(Rect2(sx, by, sw, 8), Color(C_SPORE, 0.25))
	if charge > 0.0:
		var cc: Color = [C_TEXT, C_TEXT, C_LANCE, C_SPORE][maxi(0, charge_lv - 1)] if charge_lv > 0 else Color(1, 1, 1, 0.5)
		draw_rect(Rect2(bx, by, bw * minf(charge, nova), 8), cc)
		if charge > nova:
			draw_rect(Rect2(sx, by - 2, bw * (minf(charge, 1.0) - nova), 12), Color.WHITE)
	if beam:
		for k in 3:
			draw_rect(Rect2(bx + bw * float(charge_marks[k]) - 1, by - 2, 2, 12), Color(1, 1, 1, 0.6))
		draw_rect(Rect2(sx - 1, by - 4, 3, 16), Color(1, 1, 1, 0.85))
	# Lance's label lights up in the Storm stretch; Warden's once the bar is full
	if charge > nova and ult_ready and (beam or charge >= 1.0):
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
		draw_string(fonts[800], Vector2(bx + bw + 10, by + 10), String(VShips.KITS[ship].ult_name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				C_TEXT if charge >= 1.0 else Color(C_SPORE, pulse))


func _draw_meter_bar() -> void:
	var bx := 30.0
	var by := 140.0
	var bw := 240.0
	var full := charge >= 1.0 and ult_ready
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.012)
	draw_rect(Rect2(bx, by, bw, 8), Color(C_SPORE, 0.25))
	var fill := Color.WHITE if full else C_SPORE.lerp(Color.WHITE, shat_flash)
	var grow := 2.0 + 3.0 * shat_flash
	if charge > 0.0:
		draw_rect(Rect2(bx, by - grow, bw * minf(charge, 1.0), 8 + grow * 2), fill)
	draw_string(fonts[800], Vector2(bx + bw + 10, by + 10), String(VShips.KITS[ship].ult_name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			C_TEXT if full else Color(C_SPORE, 0.6))
	draw_string(fonts[700], Vector2(bx, by + 30), kit_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(C_TEXT, pulse) if full else Color(C_MUTED, 0.9))
	# what loads the gauge, said in play too (Guillaume, 2026-11-22: "how am I supposed to charge")
	if not full and charge < 1.0:
		draw_string(fonts[700], Vector2(bx, by + 52), String(VShips.KITS[ship].get("loads", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(C_SPORE, 0.75))


# ---------- tiers, medals and ship colours ----------

## The tier the stage panel plays (picked on the panel).
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
	var nx := int(r.get("unlocked_next", -1))
	if nx >= 0:
		var ns: Dictionary = VStage.STAGES[nx]
		if ns.j == 0:
			lines.append("%s unlocked" % Worlds.LIST[ns.world].name)
		else:
			lines.append("Stage %d %s unlocked" % [ns.j + 1, ns.name])
	if int(r.get("flux", 0)) > 0:
		lines.append("+%s flux" % _fmt(int(r.flux)))
	if int(r.get("prisms", 0)) > 0:
		lines.append("+%d prisms" % int(r.prisms))
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


## The hangar: flux in the bank and the medal count, then the ship you fly drawn big (swipe it
## for the other ship; Guillaume, 2026-11-21) with what it does, its level with a level-up button, and its colours (locked ones say how many
## medals they need).
func _build_medals() -> Control:
	var v := _screen()
	v.add_theme_constant_override("separation", 14)
	var t := _label("HANGAR", 44, 800, C_TEXT, 6.0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_flux_lbl = _label("", 26, 800, C_AMBER, 2.0)
	_flux_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_flux_lbl)
	_btn_flux_buy = _small_button("")
	_btn_flux_buy.add_theme_color_override("font_color", C_PRISM)
	_btn_flux_buy.add_theme_color_override("font_disabled_color", C_PRISM)
	_btn_flux_buy.pressed.connect(func(): flux_buy_pressed.emit())
	v.add_child(_center(_btn_flux_buy))
	_medals_total = _label("", 16, 700, C_MUTED, 2.0)
	_medals_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_medals_total)
	# what the four medals are (each stage has them on each tier)
	var legend := Pips.new()
	legend.big = true
	legend.custom_minimum_size = Vector2(Pips.WIDTH_BIG, Pips.HEIGHT_BIG)
	legend.size = legend.custom_minimum_size
	legend.set_medals(15)
	v.add_child(_center(legend))
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	v.add_child(gap)
	# the ship you fly, drawn big: swipe it (or tap an arrow) for the other ship
	carousel = ShipCarousel.new()
	carousel.hud = self
	carousel.custom_minimum_size = Vector2(COL_W, 300)
	v.add_child(_center(carousel))
	var how := _label("", 16, 500, C_MUTED)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = COL_W
	how.name = "how"
	v.add_child(_center(how))
	_lock_lbl = _label("", 16, 800, C_AMBER, 2.0)
	_lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_lbl.visible = false
	v.add_child(_lock_lbl)
	_btn_ship_buy = _prism_button()
	_btn_ship_buy.visible = false
	_btn_ship_buy.pressed.connect(func(): ship_buy_pressed.emit(view_ship))
	v.add_child(_center(_btn_ship_buy))
	for k in VShips.ORDER:
		var sec := VBoxContainer.new()
		sec.add_theme_constant_override("separation", 14)
		var g := Control.new()
		g.custom_minimum_size.y = 6
		sec.add_child(g)
		var sl := _label("", 18, 800, C_LANCE, 2.0)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sec.add_child(sl)
		_level_lbls[k] = sl
		var up := _button("", true, 64)
		up.pressed.connect(func(): level_pressed.emit(k))
		up.add_theme_stylebox_override("disabled", up.get_theme_stylebox("normal"))
		up.add_theme_color_override("font_disabled_color", C_INK)
		sec.add_child(_center(up))
		_level_btns[k] = up
		var cl := _label("COLOURS", 14, 700, C_MUTED, 3.0)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sec.add_child(cl)
		var prow := HBoxContainer.new()
		prow.alignment = BoxContainer.ALIGNMENT_CENTER
		prow.add_theme_constant_override("separation", 10)
		_paint_btns[k] = []
		for sc in Progress.schemes(k):
			var b := Button.new()
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(88, 70)
			b.set_meta("scheme", sc.id)
			var sid: String = sc.id
			b.pressed.connect(func(): _swatch_pressed(k, sid))
			prow.add_child(b)
			_paint_btns[k].append(b)
		sec.add_child(prow)
		var pb := _prism_button()
		pb.visible = false
		pb.pressed.connect(func(): paint_buy_pressed.emit(k, String(_want.get(k, ""))))
		sec.add_child(_center(pb))
		_paint_buy[k] = pb
		v.add_child(sec)
		_ship_secs[k] = sec
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 10
	v.add_child(gap2)
	var back := _button("Back", false)
	back.pressed.connect(func(): back())
	v.add_child(_center(back))
	return v.get_parent()


## A button that spends prisms (violet, the prism colour).
func _prism_button() -> Button:
	var b := _button("", true, 60)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal" if st == "disabled" else st).duplicate()
		sb.bg_color = C_PRISM if st != "pressed" else C_PRISM.lightened(0.15)
		sb.shadow_color = Color(C_PRISM, 0.35)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_disabled_color", C_INK)
	return b


## An open colour is put on; a locked one is offered for prisms by the button under the row
## (tap it again to take the offer back).
func _swatch_pressed(k: String, id: String) -> void:
	if prog == null or prog.scheme_open(k, id):
		_want.erase(k)
		paint_chosen.emit(k, id)
	else:
		if _want.get(k, "") == id:
			_want.erase(k)
		else:
			_want[k] = id
	refresh_progress()


## A colour swatch: hull colour with a dark trim ring and a glow dot; ringed when chosen, dimmed
## with the medals it needs when locked (violet ring when it is the one offered for prisms).
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
	if not open and _want.get(k, "") == id:
		for st in ["normal", "hover", "pressed", "focus"]:
			var wsb: StyleBoxFlat = b.get_theme_stylebox(st)
			wsb.border_color = C_PRISM
			wsb.set_border_width_all(5)
	b.text = "" if open else str(Progress.scheme_at(k, id))
	b.tooltip_text = s.name
	var fv := FontVariation.new()
	fv.base_font = fonts[800]
	b.add_theme_font_override("font", fv)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_disabled_color", C_MUTED)
	for fc in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(fc, C_INK if open else C_MUTED)


## Four medal pips in a row (Sweep, Untouched, Breaker, Swift): filled in the medal's colour
## when held, an empty ring when not. The big version names each medal and rings the new ones.
## The hangar's ship picker: the ship you fly drawn big in its paint with its name and a dot per
## ship. Drag it sideways and let go past a third of the way (or flick it) to slide to the next
## or previous ship; the arrows at the sides do the same with a tap. Ships wrap around.
class ShipCarousel:
	extends Control
	var hud: VHud
	var drag := 0.0      # how far the finger has pulled the ship sideways
	var slide := 0.0     # what's left of the slide after a switch, eased back to 0
	var views := {}      # ship -> ShipView, the real model of each ship, turning
	var _down := false
	var _moved := false
	var _start := 0.0
	var _last := 0.0
	var _vel := 0.0

	const VIEW_H := 236.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		set_process(true)
		for k in VShips.ORDER:
			var v := ShipView.new(Vector2i(640, 300), 21.0, 0.2)
			v.size = Vector2(COL_W, VIEW_H)
			add_child(v)
			views[k] = v

	func _index() -> int:
		return maxi(0, VShips.ORDER.find(hud.view_ship))

	func _ship_at(d: int) -> String:
		var n: int = VShips.ORDER.size()
		return VShips.ORDER[posmod(_index() + d, n)]

	## Repaints each ship's model (after a paint change).
	func refresh() -> void:
		for k in views:
			views[k].show_ship(k, hud.prog.paint_of(k) if hud.prog else {})

	## Moves to the ship `d` steps along (+1 = next) and slides it in from that side.
	func swipe(d: int) -> void:
		if d == 0 or VShips.ORDER.size() < 2:
			return
		var k := _ship_at(d)
		slide = d * size.x + drag
		drag = 0.0
		hud.select_ship(k)

	func _process(delta: float) -> void:
		if hud == null:
			return
		if not _down:
			drag = lerpf(drag, 0.0, minf(1.0, delta * 14.0))
		slide = lerpf(slide, 0.0, minf(1.0, delta * 10.0))
		if absf(slide) < 0.5:
			slide = 0.0
		var w := size.x
		var off := drag + slide
		# the current ship sits in the middle; while moving, the next one comes in from the side
		# the finger pulls toward
		var side := 1 if off < 0 else -1
		for k in views:
			var v: ShipView = views[k]
			var x := w / 2
			if k == hud.view_ship:
				x += off
			elif off != 0.0 and k == _ship_at(side):
				x += side * w + off
			else:
				v.visible = false
				continue
			v.visible = true
			v.modulate = Color(0.25, 0.25, 0.4) if hud.prog and not hud.prog.ship_open(k) else Color.WHITE
			v.size = Vector2(w, VIEW_H)
			v.position = Vector2(x - v.size.x / 2, 0)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT or e is InputEventScreenTouch:
			if e.pressed:
				_down = true
				_moved = false
				_start = e.position.x
				_last = e.position.x
				_vel = 0.0
			elif _down:
				_down = false
				if _moved:
					if drag < -size.x / 3.0 or _vel < -900.0:
						swipe(1)
					elif drag > size.x / 3.0 or _vel > 900.0:
						swipe(-1)
				elif e.position.x < 70:
					swipe(-1)
				elif e.position.x > size.x - 70:
					swipe(1)
			accept_event()
		elif (e is InputEventMouseMotion or e is InputEventScreenDrag) and _down:
			var x: float = e.position.x
			var dt := maxf(get_process_delta_time(), 1.0 / 120.0)
			_vel = lerpf(_vel, (x - _last) / dt, 0.5)
			_last = x
			drag = x - _start
			if absf(drag) > 12:
				_moved = true
			accept_event()

	## Under the ships: a turntable pad; over them (names, arrows, dots) is drawn here too, since
	## the names sit below the views.
	func _draw() -> void:
		if hud == null:
			return
		var w := size.x
		var cy := 124.0
		var off := drag + slide
		var pad := Rect2(w / 2 - 150, 176, 300, 56)
		_ellipse(pad.get_center(), pad.size / 2, Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.16))
		var side := 1 if off < 0 else -1
		for d: int in [0, side]:
			if d != 0 and off == 0.0:
				continue
			var x: float = w / 2 + d * w + off
			var k: String = hud.view_ship if d == 0 else _ship_at(d)
			var fade := clampf(1.0 - absf(x - w / 2) / w, 0.0, 1.0)
			var f: Font = hud.fonts[800]
			var name := String(VShips.KITS[k].name).to_upper()
			if hud.prog and not hud.prog.ship_open(k):
				fade *= 0.45
			var fs := 30
			var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, Vector2(x - tw / 2, 268), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35 + 0.65 * fade))
		# arrows and a dot per ship
		var ac := Color(1, 1, 1, 0.5)
		for sgn in [-1.0, 1.0]:
			var ax: float = w / 2 + sgn * (w / 2 - 26)
			var pts := PackedVector2Array([Vector2(ax - sgn * 8, cy - 18), Vector2(ax + sgn * 8, cy), Vector2(ax - sgn * 8, cy + 18)])
			draw_polyline(pts, ac, 4.0, true)
		var n: int = VShips.ORDER.size()
		for i in n:
			var dx := (i - (n - 1) / 2.0) * minf(22.0, 300.0 / n)
			var on := i == _index()
			draw_circle(Vector2(w / 2 + dx, 290), 6.0 if on else 4.0, Color(1, 1, 1, 0.9 if on else 0.3))

	func _ellipse(c: Vector2, r: Vector2, fill: Color, line: Color) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		draw_colored_polygon(pts.slice(0, 48), fill)
		draw_polyline(pts, line, 2.0, true)


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
