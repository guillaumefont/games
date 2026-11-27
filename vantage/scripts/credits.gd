class_name Credits
extends Control
## The ending's credits roll (release audit, 2026-11-27: clearing 5-3 used to just say "WORLD CLEAR").
## Once the last fortress is down and the results are read, the credits scroll up over the land
## flying by, then the game returns to the hangar (`Game.start_credits`, phase "credits"). The
## hangar's "Credits" button rolls them too. Driven by time (`roll(t)`), so tests can step it.

## Each entry: [heading, line]. An empty heading is a lone line; "" for both is a gap.
const LINES := [
	["", "The last fortress is down."],
	["", "The skies are free again."],
	["", ""],
	["A GAME BY", "Guillaume Font"],
	["DESIGN AND DIRECTION", "Guillaume Font"],
	["CODE, MODELS, SOUND AND MUSIC", "Built with Claude Code"],
	["ENGINE", "Godot Engine"],
	["", "© 2014-present Godot Engine contributors."],
	["", "© 2007-2014 Juan Linietsky, Ariel Manzur."],
	["", "MIT licence, godotengine.org/license"],
	["FONT", "Inter by Rasmus Andersson"],
	["", "SIL Open Font License 1.1"],
	["", ""],
	["", "THANK YOU FOR PLAYING"],
]
## Pixels a second the roll climbs.
const SPEED := 70.0
## Seconds before a tap may skip it (so the tap that opened it doesn't close it).
const SKIP_AFTER := 1.0

const FONT := preload("res://fonts/Inter-Variable.ttf")
var box: VBoxContainer
var shade: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade = ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.08, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	line("VANTAGE", 84, Hud.CY, 900)
	gap(40)
	for i in LINES.size():
		var e: Array = LINES[i]
		if e[0] == "" and e[1] == "":
			gap(48)
			continue
		if e[0] != "":
			gap(34)
			line(e[0], 22, Hud.GOLD, 700)
		# names, the opening words and the farewell stand out; licence notes stay quiet
		var lead: bool = e[0] != "" or i < 2 or i == LINES.size() - 1
		line(e[1], 30 if lead else 24, Hud.INK if lead else Hud.DIM, 600)
	visible = false


func line(text: String, size: int, col: Color, weight: int) -> void:
	var l := Label.new()
	var f := FontVariation.new()
	f.base_font = FONT
	f.variation_opentype = {"wght": weight}
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	box.add_child(l)


func gap(h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


## Height of the whole roll in pixels at the screen's width, measured from the text itself (a
## wrapped label only knows its height once laid out, which may not have happened yet).
func roll_h() -> float:
	var w := maxf(size.x - 64.0, 100.0)
	var h := 0.0
	for c in box.get_children():
		if c is Label:
			var l: Label = c
			var f: Font = l.get_theme_font("font")
			var fs := l.get_theme_font_size("font_size")
			h += f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs).y
		else:
			h += (c as Control).custom_minimum_size.y
	return h + box.get_theme_constant("separation") * (box.get_child_count() - 1)


## Places the roll `t` seconds in: it starts just below the bottom edge and climbs.
func roll(t: float) -> void:
	box.size = Vector2(maxf(size.x - 64.0, 100.0), roll_h())
	box.position = Vector2(32.0, size.y - t * SPEED)


## The roll has climbed off the top of the screen.
func done(t: float) -> bool:
	return size.y - t * SPEED + roll_h() < 0.0
