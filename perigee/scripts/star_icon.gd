class_name StarIcon
extends Control
## A five-pointed star, sand when earned and faint when not (Voyage stars). Drawn, so it needs
## no font glyph.

var lit := false:
	set(v):
		lit = v
		queue_redraw()


func _init(px := 16.0, on := false) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	lit = on


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color("f2c879") if lit else Color(0.953, 0.925, 0.875, 0.18))
