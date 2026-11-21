class_name VWorlds
extends Control
## The world screen: six cards (two columns, three rows), each a world in its own colours with
## its planet, name, boss and a bar of its eight stages filled in the tier's colour as they are
## cleared. Worlds not reached yet are padlocked (they still open, to look at their route).
## The world of the next stage to play pulses. Drawn in code; tap a card to see its levels.

signal world_tapped(world: int)

const CARD_H := 196.0
const GAP := 14.0

var hud: VHud
var _press := Vector2(-1, -1)


func _init(h: VHud) -> void:
	hud = h
	var rows := ceili(VStage.WORLDS.size() / 2.0)
	custom_minimum_size = Vector2(VHud.COL_W, rows * CARD_H + (rows - 1) * GAP)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func card(w: int) -> Rect2:
	var cw := (size.x - GAP) / 2.0
	return Rect2((w % 2) * (cw + GAP), (w / 2) * (CARD_H + GAP), cw, CARD_H)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
		elif _press.x >= 0:
			if _press.distance_to(e.position) < 40:
				tap(_press)
			_press = Vector2(-1, -1)
		accept_event()


func tap(p: Vector2) -> void:
	for w in VStage.WORLDS.size():
		if card(w).has_point(p):
			world_tapped.emit(w)
			return


func _draw() -> void:
	var m := hud.map
	var tc := m.tier_col()
	var nxt := m.next_stage()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for w in VStage.WORLDS.size():
		var r := card(w)
		var wd: Dictionary = Worlds.LIST[w]
		var pal: Dictionary = wd.pal
		var open := m.world_open(w)
		var done := m.world_cleared(w)
		var here := nxt >= 0 and VStage.world_of(nxt) == w and done < VStage.PER_WORLD
		var a := 1.0 if open else 0.55
		var pts := m._rounded(r, 22.0)
		var cols := PackedColorArray()
		for q in pts:
			var k := (q.y - r.position.y) / r.size.y
			cols.append(Color(Color(pal.top).lerp(Color(pal.bot), k), 0.92 * a))
		draw_polygon(pts, cols)
		var ring := pts.duplicate()
		ring.append(pts[0])
		if here:
			draw_polyline(ring, Color(tc, 0.35 + 0.35 * pulse), 3.0, true)
		else:
			draw_polyline(ring, Color(Color(pal.ring), 0.35 * a), 1.5, true)
		# the planet, top right
		var pc := r.position + Vector2(r.size.x - 52, 54)
		m._planet(pc, 30, pal, a, self)
		if not open:
			m._lock(pc, 1.4, Color(VMap.C_TEXT, 0.9), self)
		var x := r.position.x + 18
		m._text(Vector2(x, r.position.y + 34), String(wd.sub).to_upper(), 13, Color(Color(pal.light), 0.9 * a), 800, HORIZONTAL_ALIGNMENT_LEFT, -1.0, self)
		# the name, on up to two lines
		var words: PackedStringArray = String(wd.name).to_upper().split(" ")
		var l1 := words[0]
		var l2 := ""
		if words.size() > 1:
			if words[0] == "THE":
				l1 = words[0] + " " + words[1]
				l2 = " ".join(words.slice(2))
			else:
				l2 = " ".join(words.slice(1))
		m._text(Vector2(x, r.position.y + 66), l1, 22, Color(VMap.C_TEXT, a), 800, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 104, self)
		if l2 != "":
			m._text(Vector2(x, r.position.y + 92), l2, 22, Color(VMap.C_TEXT, a), 800, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, self)
		m._text(Vector2(x, r.position.y + 122), String(wd.boss_name).to_upper(), 12, Color(VMap.C_MUTED, 0.85 * a), 700, HORIZONTAL_ALIGNMENT_LEFT, -1.0, self)
		# eight stages as a bar of segments
		var sw := (r.size.x - 36 - 7 * 5) / 8.0
		for j in VStage.PER_WORLD:
			var i := w * VStage.PER_WORLD + j
			var sr := Rect2(x + j * (sw + 5), r.position.y + 140, sw, 10)
			var col := Color(1, 1, 1, 0.14)
			if m.is_cleared(i):
				col = tc
			elif i == nxt:
				col = Color(tc, 0.3 + 0.5 * pulse)
			draw_rect(sr, col)
		var line := "%d / %d" % [done, VStage.PER_WORLD]
		if not open:
			line = "LOCKED"
		elif done == VStage.PER_WORLD:
			line = "CLEARED"
		elif here:
			line = "%d / %d  ·  NEXT: %d" % [done, VStage.PER_WORLD, VStage.STAGES[nxt].j + 1]
		m._text(Vector2(x, r.position.y + 178), line, 14, tc if (done > 0 or here) and open else Color(VMap.C_MUTED, a), 800, HORIZONTAL_ALIGNMENT_LEFT, -1.0, self)
