class_name CosmeticIcon
extends Control
## A small preview of one unlock-track item: a ship, a trail curving into a ship, or a palette's
## four moons.

var id := ""
var kind := ""
var locked := false
var _t := 0.0


func _init(id_in := "", kind_in := "") -> void:
	id = id_in
	kind = kind_in
	custom_minimum_size = Vector2(72, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var a := 0.3 if locked else 1.0
	modulate = Color(1, 1, 1, a)
	match kind:
		"palette":
			var cols := Unlocks.palette(id)
			for i in cols.size():
				draw_circle(c + Vector2((i - 1.5) * 15.0, 0), 6.5, cols[i], true, -1.0, true)
		"trail":
			var pts := []
			for i in 24:
				var f := i / 23.0
				pts.append(c + Vector2(lerpf(-30.0, 22.0, f), sin(f * 3.0 + 0.6) * 9.0))
			Looks.draw_trail(self, id, pts, pts[-1], Unlocks.palette("palette_pastel"), _t)
			Looks.draw_ship(self, "ship_pebble", pts[-1], Vector2.RIGHT, _t)
		"ship":
			Looks.draw_ship(self, id, c, Vector2(1, -1).normalized(), _t)
