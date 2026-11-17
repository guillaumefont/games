class_name MedalIcon
extends Control
## A medal: a disc in its tier's colour (bronze, silver, gold; faint when not won yet) with the
## mark of what it is for: a swoosh for speed, a spark for points, a star for stars. Drawn, so it
## needs no font glyph. See Medals.

const COLORS: Array[Color] = [
	Color(0.953, 0.925, 0.875, 0.16), # not won
	Color("d9905f"), # bronze
	Color("cdd3ec"), # silver
	Color("f2c879"), # gold
]
const MARK := Color("141634")

var kind := "speed" ## "speed", "points" or "stars"
var tier := 0:
	set(v):
		tier = clampi(v, 0, 3)
		queue_redraw()


func _init(px := 24.0, kind_in := "speed", tier_in := 0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	kind = kind_in
	tier = tier_in


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	var won := tier > 0
	var fill := COLORS[tier]
	draw_circle(c, r, fill)
	if won:
		draw_arc(c, r * 0.8, 0.0, TAU, 32, Color(MARK, 0.25), maxf(1.0, r * 0.07), true)
	var ink := Color(MARK, 0.85) if won else Color(0.953, 0.925, 0.875, 0.35)
	match kind:
		"speed":
			# two chevrons pointing right
			var w := maxf(1.0, r * 0.16)
			for dx in [-0.22, 0.18]:
				var x: float = c.x + dx * r
				draw_polyline(PackedVector2Array([
					Vector2(x - r * 0.18, c.y - r * 0.32), Vector2(x + r * 0.14, c.y), Vector2(x - r * 0.18, c.y + r * 0.32),
				]), ink, w, true)
		"points":
			# a four-pointed spark
			var pts := PackedVector2Array()
			for i in 8:
				var rr := r * (0.5 if i % 2 == 0 else 0.16)
				var a := -PI / 2.0 + i * PI / 4.0
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, ink)
		_:
			var pts := PackedVector2Array()
			for i in 10:
				var rr := r * (0.5 if i % 2 == 0 else 0.22)
				var a := -PI / 2.0 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, ink)
