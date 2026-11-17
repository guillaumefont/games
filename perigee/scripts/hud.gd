class_name Hud
extends CanvasLayer
## Score, best, sound toggle, hint line, and the start, game over and pause cards.
## Built in code, styled after the web prototype (Unbounded for numbers and titles, Manrope for
## text, pastel on deep indigo).

signal sound_toggled
signal mode_picked(mode: String) ## "endless" or a kind of moon for the lab
signal voyage_opened
signal sector_picked(id: String)
signal clear_action(action: String) ## "next", "replay" or "map"
signal settings_opened
signal setting_changed(key: String, value: Variant)
signal settings_closed
signal tutorial_requested
signal hangar_opened
signal cosmetic_picked(id: String)
signal hangar_closed
signal menu_requested ## back to the start card (the main menu) from game over, pause or Voyage
signal refresh_pressed ## the build line was tapped: restart into the newest build

## The lab: a run of one new kind of moon, to try each one (plan: "Sandbox three new bodies").
## Shown on the start and game over cards while the vertical slice is built; not for release.
const LAB_MODES := [["endless", "Endless"], ["twin", "Twin"], ["retro", "Retro"], ["pulsar", "Pulsar"]]

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
var build_button: Button ## the build line on the start card ("Build b1050 · refresh")
var _build_id := ""
var over_card: Control
var over_why: Label
var over_score: Label
var over_best: Label
var over_stats: Label
var mode_label: Label
var timer_label: Label
var voyage_card: Control ## the Voyage map (VoyageMap)
var voyage_map: VoyageMap
var clear_card: Control
var clear_title: Label
var clear_score: Label
var clear_stars: Array[StarIcon] = []
var clear_lines: Array[Label] = []
var clear_pill_label: Label
var clear_big: Control ## the three big stars
var clear_buttons: Control ## Replay and Map
var clear_medals: Control ## the run's three medals
var clear_medal_icons: Array[MedalIcon] = []
var clear_medal_tiers: Array[Label] = []
var clear_medal_next: Array[Label] = []
var voyage_stars: Label ## "14 / 54": every star of the route, on the map's top bar
var voyage_tally: Label ## medals won and the bonus sparks they paid
var over_medal_row: Control ## Drift's points medal on the game over card
var over_medal: MedalIcon
var over_medal_label: Label
var over_lab_row: Control
var over_voyage_row: Control
var pause_card: Control
var pause_menu: Button ## "Main menu" on the pause card (hidden during the resume countdown)
var pause_title: Label
var pause_sub: Label
var start_pill_label: Label
var hangar_card: Control
var hangar_sparks: Label
var hangar_next: Label
var hangar_bar: ProgressBar
var hangar_items := {} ## item id -> Button
var over_unlock: Label
var settings_card: Control
var settings_sliders := {} ## setting key -> HSlider
var settings_toggles := {} ## setting key -> Button
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
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 6)
	bar.add_child(right)
	right.add_child(sound_button)
	mode_label = _label("", _spaced(body_700, 1.5), 11, SAND)
	mode_label.uppercase = true
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(mode_label)
	timer_label = _label("", body_700, 12, MUTED)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(timer_label)
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
	var start_pill := _pill("Tap to play Drift")
	start_pill_label = start_pill.get_child(0).get_child(0)
	_card(start_card).add_child(start_pill)
	var menu_row := HBoxContainer.new()
	menu_row.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_row.add_theme_constant_override("separation", 10)
	menu_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var voyage_button := _ghost_button("Voyage", 15, 44, 22)
	voyage_button.name = "Voyage"
	voyage_button.pressed.connect(func() -> void: voyage_opened.emit())
	menu_row.add_child(voyage_button)
	var hangar_button := _ghost_button("Hangar", 15, 44, 22)
	hangar_button.name = "Hangar"
	hangar_button.pressed.connect(func() -> void: hangar_opened.emit())
	menu_row.add_child(hangar_button)
	var settings_button := _ghost_button("Settings", 15, 44, 22)
	settings_button.name = "Settings"
	settings_button.pressed.connect(func() -> void: settings_opened.emit())
	menu_row.add_child(settings_button)
	_card(start_card).add_child(menu_row)
	_card(start_card).add_child(_lab_row())
	# Which build this is, and on test builds a newer one when it's out (see main.gd _check_update).
	_build_id = str(ProjectSettings.get_setting("application/config/version", ""))
	build_button = Button.new()
	build_button.name = "Build"
	build_button.flat = true
	build_button.focus_mode = Control.FOCUS_NONE
	build_button.add_theme_font_override("font", body_700)
	build_button.add_theme_font_size_override("font_size", 11)
	build_button.pressed.connect(func() -> void: refresh_pressed.emit())
	build_button.visible = _build_id != ""
	_card(start_card).add_child(_centered(build_button))
	set_build_state("idle")

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
	over_stats = _label("", body_500, 13, MUTED)
	over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(over_card).add_child(over_stats)
	over_unlock = _label("", body_700, 14, SAND)
	over_unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_unlock.visible = false
	_card(over_card).add_child(over_unlock)
	var mrow := HBoxContainer.new()
	mrow.alignment = BoxContainer.ALIGNMENT_CENTER
	mrow.add_theme_constant_override("separation", 8)
	mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_medal = MedalIcon.new(22.0, "points")
	over_medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mrow.add_child(over_medal)
	over_medal_label = _label("", body_700, 13, INK)
	mrow.add_child(over_medal_label)
	mrow.visible = false
	over_medal_row = mrow
	_card(over_card).add_child(mrow)
	_card(over_card).add_child(_pill("Tap to fly again"))
	over_lab_row = _lab_row()
	_card(over_card).add_child(over_lab_row)
	var vrow := HBoxContainer.new()
	vrow.alignment = BoxContainer.ALIGNMENT_CENTER
	vrow.add_theme_constant_override("separation", 8)
	vrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var map_b := _ghost_button("Map", 12, 32, 16)
	map_b.name = "Map"
	map_b.pressed.connect(func() -> void: clear_action.emit("map"))
	vrow.add_child(map_b)
	var drift_b := _ghost_button("Drift", 12, 32, 16)
	drift_b.name = "Drift"
	drift_b.pressed.connect(func() -> void: mode_picked.emit("endless"))
	vrow.add_child(drift_b)
	over_voyage_row = vrow
	over_voyage_row.visible = false
	_card(over_card).add_child(over_voyage_row)
	_card(over_card).add_child(_centered(_menu_button()))

	_build_voyage_card()
	_build_clear_card()
	_build_settings_card()
	_build_hangar_card()

	pause_card = _overlay()
	pause_card.visible = false
	pause_title = _label("Paused", display_800, 56, INK)
	pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(pause_card).add_child(pause_title)
	pause_sub = _label("Tap to resume", body_700, 15, SAND)
	pause_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card(pause_card).add_child(pause_sub)
	pause_menu = _menu_button()
	_card(pause_card).add_child(_centered(pause_menu))

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
	if voyage_map != null:
		voyage_map.top_bar.add_theme_constant_override("margin_top", int(12 + top_inset))
	hint_label.offset_top = -(28 + bottom_inset + 22)
	hint_label.offset_bottom = -(28 + bottom_inset)


func set_score(v: int) -> void:
	score_label.text = str(v)


func set_best(v: int) -> void:
	best_label.text = "Best %d" % v
	best_label.add_theme_color_override("font_color", MUTED)


## During a run the line under the score shows the combo, teal once it multiplies.
func set_combo(combo: int, mult: int) -> void:
	best_label.text = ("×%d · combo %d" % [mult, combo]) if mult > 1 else "combo %d" % combo
	best_label.add_theme_color_override("font_color", TEAL if mult > 1 else MUTED)


func set_sound(on: bool) -> void:
	sound_button.text = "SOUND ON" if on else "SOUND OFF"


## Voyage clock under the mode tag: teal while under par, coral once over it. Empty hides it.
func set_timer(run_t: float, par: float) -> void:
	if par <= 0.0:
		timer_label.text = ""
		return
	timer_label.text = "%.1f s · par %d s" % [run_t, int(par)]
	timer_label.add_theme_color_override("font_color", TEAL if run_t <= par else CORAL)


## Drift's points medal on the game over card: this run's tier and what the next one needs.
## A negative tier hides the row (other modes).
func set_over_medal(tier: int, text: String) -> void:
	over_medal_row.visible = tier >= 0
	if tier < 0:
		return
	over_medal.tier = tier
	over_medal_label.text = text
	over_medal_label.add_theme_color_override("font_color", INK if tier > 0 else MUTED)


## The game over card's lower row: lab buttons, or Map and Drift in Voyage.
func set_over_row(voyage: bool) -> void:
	over_lab_row.visible = not voyage
	over_voyage_row.visible = voyage


## Opens the Voyage map. `claimed` is save.data.rewards; `focus` the level to scroll to (the furthest
## open one when empty).
func show_voyage(progress: Dictionary, drift_best := 0, claimed: Array = [], focus := "") -> void:
	start_card.visible = false
	over_card.visible = false
	clear_card.visible = false
	voyage_card.visible = true
	voyage_map.refresh(progress, drift_best, claimed, focus)


func hide_voyage() -> void:
	voyage_card.visible = false


## The sector clear card: stars earned, with what each one is for.
## `medals` is this run's {"speed", "points", "stars"} tiers and `next` what each next tier needs
## ("" once won at the top).
## `won` is the bonus sparks each medal's new rewards paid this run.
func show_clear(id: String, score: int, stars: Array, lines: Array, has_next: bool,
		medals := {}, next := {}, won := {}) -> void:
	clear_title.text = "Level %d clear" % Voyage.level_number(id)
	clear_score.text = str(score)
	for i in 3:
		clear_stars[i].lit = stars[i]
		clear_lines[i].text = lines[i]
		clear_lines[i].add_theme_color_override("font_color", INK if stars[i] else MUTED)
	clear_pill_label.text = "TAP FOR NEXT SECTOR" if has_next else "TAP FOR THE MAP"
	for i in 3:
		var kind := clear_medal_icons[i].kind
		var tier := int(medals.get(kind, 0))
		clear_medal_icons[i].tier = tier
		if kind == "stars":
			clear_medal_tiers[i].text = "Won" if tier > 0 else "Not yet"
		else:
			clear_medal_tiers[i].text = Medals.TIER_NAMES[tier] if tier > 0 else "Not yet"
		clear_medal_tiers[i].add_theme_color_override("font_color", MedalIcon.COLORS[tier] if tier > 0 else MUTED)
		var paid := int(won.get(kind, 0))
		clear_medal_next[i].text = ("+%d sparks" % paid) if paid > 0 else str(next.get(kind, ""))
		clear_medal_next[i].add_theme_color_override("font_color", SAND if paid > 0 else MUTED)
	clear_medals.visible = not medals.is_empty()
	clear_big.visible = true
	clear_buttons.visible = true
	clear_card.visible = true


func hide_clear() -> void:
	clear_card.visible = false


func _build_voyage_card() -> void:
	voyage_map = VoyageMap.new(self)
	voyage_map.visible = false
	root.add_child(voyage_map)
	voyage_map.build()
	voyage_map.level_picked.connect(func(id: String) -> void: sector_picked.emit(id))
	voyage_map.back_pressed.connect(func() -> void: menu_requested.emit())
	voyage_card = voyage_map
	voyage_stars = voyage_map.stars_label
	voyage_tally = voyage_map.tally_label


func _build_clear_card() -> void:
	clear_card = _overlay()
	clear_card.visible = false
	var card := _card(clear_card)
	clear_title = _label("", _spaced(body_700, 1.7), 12, MUTED)
	clear_title.uppercase = true
	clear_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(clear_title)
	clear_score = _label("0", display_800, 64, INK)
	clear_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(clear_score)
	var big := HBoxContainer.new()
	big.alignment = BoxContainer.ALIGNMENT_CENTER
	big.add_theme_constant_override("separation", 8)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var st := StarIcon.new(34.0)
		big.add_child(st)
		clear_stars.append(st)
	card.add_child(big)
	clear_big = big
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 10)
	list.add_theme_constant_override("v_separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var st := StarIcon.new(14.0)
		st.lit = true
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		list.add_child(st)
		var l := _label("", body_500, 14, INK)
		list.add_child(l)
		clear_lines.append(l)
	card.add_child(_centered(list))
	var medals := HBoxContainer.new()
	medals.alignment = BoxContainer.ALIGNMENT_CENTER
	medals.add_theme_constant_override("separation", 6)
	medals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for m in [["speed", "Speed"], ["points", "Points"], ["stars", "All stars"]]:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(104, 0)
		col.alignment = BoxContainer.ALIGNMENT_BEGIN
		col.add_theme_constant_override("separation", 2)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := MedalIcon.new(32.0, m[0])
		col.add_child(_centered(icon))
		var name_l := _label(m[1], _spaced(body_700, 1.2), 10, MUTED)
		name_l.uppercase = true
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_l)
		var tier_l := _label("", body_700, 13, INK)
		tier_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tier_l)
		var next_l := _label("", body_500, 11, MUTED)
		next_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(next_l)
		medals.add_child(col)
		clear_medal_icons.append(icon)
		clear_medal_tiers.append(tier_l)
		clear_medal_next.append(next_l)
	var rewards_box := VBoxContainer.new()
	rewards_box.add_theme_constant_override("separation", 6)
	rewards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := _label("Rewards", _spaced(body_700, 1.7), 11, SAND)
	head.uppercase = true
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_box.add_child(head)
	rewards_box.add_child(medals)
	card.add_child(rewards_box)
	clear_medals = rewards_box
	var pill := _pill("Tap for next sector")
	clear_pill_label = pill.get_child(0).get_child(0)
	card.add_child(pill)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a in [["Replay", "replay"], ["Map", "map"]]:
		var b := _ghost_button(a[0], 12, 32, 16)
		b.name = a[0]
		var act: String = a[1]
		b.pressed.connect(func() -> void: clear_action.emit(act))
		row.add_child(b)
	card.add_child(row)
	clear_buttons = row


## The tutorial's last card, on the clear card's layout: three tips instead of stars.
func show_tutorial_done(score: int) -> void:
	clear_title.text = "You're ready to fly"
	clear_score.text = str(score)
	clear_big.visible = false
	clear_buttons.visible = false
	clear_medals.visible = false
	var tips := ["Perigees score double and build your combo",
		"Fling past a moon to leap it for big points",
		"Voyage has hand-made sectors with stars to win"]
	for i in 3:
		clear_lines[i].text = tips[i]
		clear_lines[i].add_theme_color_override("font_color", INK)
	clear_pill_label.text = "TAP TO PLAY DRIFT"
	clear_card.visible = true


## The words on the start card's pill: "Tap to play Drift", or the tutorial's on a first run.
func set_start_text(text: String) -> void:
	start_pill_label.text = text


# ---------- hangar: the spark unlock track ----------

func _build_hangar_card() -> void:
	hangar_card = _overlay()
	hangar_card.visible = false
	hangar_card.color = Color(SPACE, 0.94)
	hangar_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card := _card(hangar_card)
	var title := _label("Hangar", display_800, 36, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)
	hangar_sparks = _label("", _spaced(body_700, 1.5), 12, SAND)
	hangar_sparks.uppercase = true
	hangar_sparks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(hangar_sparks)
	hangar_bar = ProgressBar.new()
	hangar_bar.show_percentage = false
	hangar_bar.custom_minimum_size = Vector2(300, 8)
	hangar_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(INK, 0.15)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = SAND
	fg.set_corner_radius_all(4)
	hangar_bar.add_theme_stylebox_override("background", bg)
	hangar_bar.add_theme_stylebox_override("fill", fg)
	card.add_child(_centered(hangar_bar))
	hangar_next = _label("", body_500, 13, MUTED)
	hangar_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(hangar_next)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for it in Unlocks.TRACK + Unlocks.REWARD_ITEMS:
		var b := Button.new()
		b.name = "Item_" + it.id
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(104, 92)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 2)
		b.add_child(box)
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon := CosmeticIcon.new(it.id, it.kind)
		icon.name = "Icon"
		box.add_child(_centered(icon))
		var name := _label(it.name, body_700, 13, INK)
		name.name = "Name"
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(name)
		var sub := _label(it.kind, body_500, 11, MUTED)
		sub.name = "Sub"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(sub)
		var id: String = it.id
		b.pressed.connect(func() -> void: cosmetic_picked.emit(id))
		grid.add_child(b)
		hangar_items[id] = b
	card.add_child(_centered(grid))
	var note := _label("Collect sparks and win medals to move along the track.", body_500, 12, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(note)
	var done := _ghost_button("Done", 13, 36, 18)
	done.name = "Done"
	done.pressed.connect(func() -> void: hangar_closed.emit())
	card.add_child(_centered(done))


## Opens (or refreshes) the hangar for `sparks` collected all-time and the `equipped` ids.
func show_hangar(sparks: int, equipped: Dictionary, claimed: Array = []) -> void:
	hangar_sparks.text = "%d sparks collected" % sparks
	hangar_bar.value = Unlocks.progress(sparks)
	var nxt := Unlocks.next_item(sparks)
	hangar_next.text = ("Next: %s at %d" % [Unlocks.label(nxt), nxt.at]) if not nxt.is_empty() else "Track complete"
	for it in Unlocks.TRACK + Unlocks.REWARD_ITEMS:
		var b: Button = hangar_items[it.id]
		var open := Unlocks.is_unlocked(it.id, sparks, claimed)
		var on: bool = equipped.get(it.kind, "") == it.id
		b.disabled = not open
		b.find_child("Icon", true, false).locked = not open
		var sub: Label = b.find_child("Sub", true, false)
		var how: String = it.get("how", "%d sparks" % int(it.get("at", 0)))
		sub.text = ("Equipped" if on else it.kind.capitalize()) if open else how
		sub.add_theme_color_override("font_color", SAND if on else MUTED)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.06 if on else 0.0)
			sb.border_color = SAND if on else Color(INK, 0.1 if not open else 0.25)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(14)
			sb.anti_aliasing = true
			b.add_theme_stylebox_override(st, sb)
	hangar_card.visible = true
	start_card.visible = false


func hide_hangar() -> void:
	hangar_card.visible = false


## A line on the game over card for cosmetics a run just unlocked ("" hides it).
func set_over_unlock(text: String) -> void:
	over_unlock.text = text
	over_unlock.visible = text != ""


# ---------- settings ----------

const SLIDERS := [["music_volume", "Music"], ["sfx_volume", "Effects"]]
const TOGGLES := [
	["vibration", "Vibration", "On", "Off"],
	["aim_guide", "Aim guide", "Every hop", "First hops"],
	["reduced_motion", "Reduced motion", "On", "Off"],
	["high_contrast", "High-contrast rings", "On", "Off"],
]


func _build_settings_card() -> void:
	settings_card = _overlay()
	settings_card.visible = false
	settings_card.color = Color(SPACE, 0.94)
	settings_card.mouse_filter = Control.MOUSE_FILTER_STOP # taps here never start a run
	var card := _card(settings_card)
	var title := _label("Settings", display_800, 36, INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	card.add_child(grid)
	for row in SLIDERS:
		var key: String = row[0]
		var l := _label(row[1], body_700, 15, INK)
		l.custom_minimum_size.x = 150
		grid.add_child(l)
		var sl := HSlider.new()
		sl.name = "Slider_" + key
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.1
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(150, 36)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_slider(sl)
		sl.value_changed.connect(func(v: float) -> void: setting_changed.emit(key, v))
		grid.add_child(sl)
		settings_sliders[key] = sl
	for row in TOGGLES:
		var key: String = row[0]
		var l := _label(row[1], body_700, 15, INK)
		grid.add_child(l)
		var b := _ghost_button(row[3], 13, 36, 18)
		b.name = "Toggle_" + key
		b.toggle_mode = true
		b.custom_minimum_size.x = 150
		b.set_meta("labels", [row[2], row[3]])
		b.toggled.connect(func(on: bool) -> void:
			b.text = b.get_meta("labels")[0 if on else 1]
			setting_changed.emit(key, on))
		grid.add_child(b)
		settings_toggles[key] = b
	var note := _label("The aim guide and high-contrast rings only change what you see.", body_500, 12, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size.x = 300
	card.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var howto := _ghost_button("How to play", 13, 36, 18)
	howto.name = "HowToPlay"
	howto.pressed.connect(func() -> void: tutorial_requested.emit())
	row.add_child(howto)
	var done := _ghost_button("Done", 13, 36, 18)
	done.name = "Done"
	done.pressed.connect(func() -> void: settings_closed.emit())
	row.add_child(done)
	card.add_child(row)


## Opens the settings card showing `values` (the save's settings); no signals fire while filling it.
func show_settings(values: Dictionary) -> void:
	for key in settings_sliders:
		settings_sliders[key].set_value_no_signal(float(values.get(key, 1.0)))
	for key in settings_toggles:
		var b: Button = settings_toggles[key]
		var on := bool(values.get(key, false))
		b.set_pressed_no_signal(on)
		b.text = b.get_meta("labels")[0 if on else 1]
	settings_card.visible = true
	start_card.visible = false


func hide_settings() -> void:
	settings_card.visible = false


func _style_slider(sl: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.18)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = SAND
	fill.set_corner_radius_all(3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 22:
			var d := Vector2(x - 10.5, y - 10.5).length()
			img.set_pixel(x, y, Color(INK, clampf(10.0 - d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	sl.add_theme_icon_override("grabber", tex)
	sl.add_theme_icon_override("grabber_highlight", tex)


func _centered(c: Control) -> Control:
	var w := CenterContainer.new()
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.add_child(c)
	return w


func _ghost_button(text: String, font_size: int, height: int, radius: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, height)
	_style_ghost(b, font_size, radius)
	return b


func _style_ghost(b: Button, font_size: int, radius := 16) -> void:
	b.add_theme_font_override("font", body_700)
	b.add_theme_font_size_override("font_size", font_size)
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.08 if st == "pressed" else 0.0)
		sb.border_color = Color(INK, 0.25)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(radius)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.anti_aliasing = true
		b.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(c, INK)


## What the build line says: "idle" (this build, tap to check), "checking", "latest" (no newer
## build), "offline" (couldn't check), "new" (build `build` is out, tap to update) or "restarting".
func set_build_state(state: String, build := 0) -> void:
	var color := MUTED
	match state:
		"new":
			build_button.text = "New build %d · tap to update" % build
			color = SAND
		"restarting":
			build_button.text = "Restarting…"
		"checking":
			build_button.text = "Checking for a new build…"
		"offline":
			build_button.text = "Build %s · can't check (offline)" % _build_id
		"latest":
			build_button.text = "Build %s · up to date" % _build_id
		_:
			build_button.text = "Build %s  ⟳" % _build_id
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		build_button.add_theme_color_override(c, color)


## The small tag under the sound button: which lab is running, or nothing in the endless mode.
func set_mode(text: String) -> void:
	mode_label.text = text


func set_hint(text: String) -> void:
	if hint_label.text != text:
		hint_label.text = text


func show_start(on: bool) -> void:
	start_card.visible = on


func show_over(score: int, why: String, best: int, new_best: bool, stats := "", line := "") -> void:
	over_stats.text = stats
	over_score.text = str(score)
	over_why.text = why
	if line != "":
		over_best.text = line
		over_best.add_theme_color_override("font_color", MUTED)
	elif new_best and score > 0:
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
	pause_menu.visible = countdown <= 0
	if countdown > 0:
		pause_title.text = str(countdown)
		pause_sub.text = "Get ready"
	else:
		pause_title.text = "Paused"
		pause_sub.text = "Tap to resume"


# ---------- building blocks ----------

## A "Main menu" button: back to the start card, where the build line and the menus are.
func _menu_button() -> Button:
	var b := _ghost_button("Main menu", 12, 32, 16)
	b.name = "MainMenu"
	b.pressed.connect(func() -> void: menu_requested.emit())
	return b


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


func _lab_row() -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := _label("Lab: try one kind of moon", body_500, 12, MUTED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for m in LAB_MODES:
		var b := Button.new()
		b.name = "Lab_" + m[0]
		b.text = m[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_override("font", body_700)
		b.add_theme_font_size_override("font_size", 12)
		for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(1, 1, 1, 0.08 if st == "pressed" else 0.0)
			sb.border_color = Color(INK, 0.25)
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(16)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.anti_aliasing = true
			b.add_theme_stylebox_override(st, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, INK)
		var mode: String = m[0]
		b.pressed.connect(func() -> void: mode_picked.emit(mode))
		row.add_child(b)
	return box


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
