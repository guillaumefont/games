class_name VMap
extends Control
## The stage map on the menu: a strip of the six worlds (each a small planet in its own colours,
## ringed by how much of it is cleared on the chosen tier, locked ones padlocked), and under it
## the chosen world's route: eight stages climbing up the panel from stage 1 to the boss, the
## cleared stretch lit in the tier's colour, the next stage pulsing, the rest locked.
## Tap a world to look at it, tap an open stage to play it. Drawn in code, no child nodes.

signal stage_tapped(stage: int)
signal world_tapped(world: int)

const STRIP_H := 94.0
const GAP := 12.0
const PANEL_H := 440.0
const R := 17.0
const R_BOSS := 23.0
const C_TEXT := Color("f4f2ff")
const C_MUTED := Color("bdb6e0")
const C_INK := Color("0b0830")
const C_GLASS := Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7)

var hud: VHud
var world := 0
## The footer line: a hint, or why a tapped stage is locked (for `_note_t` frames).
var _note := ""
var _note_t := 0
var _press := Vector2(-1, -1)
var _flash := {}


func _init(h: VHud) -> void:
	hud = h
	custom_minimum_size = Vector2(VHud.COL_W, STRIP_H + GAP + PANEL_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false


func _process(_d: float) -> void:
	if is_visible_in_tree():
		if _note_t > 0:
			_note_t -= 1
		queue_redraw()


func tier() -> int:
	return hud.tier


func prog() -> Progress:
	return hud.prog


func stage_index(w: int, j: int) -> int:
	return w * VStage.PER_WORLD + j


func is_open(i: int) -> bool:
	return prog() == null or prog().open(i, tier())


func is_cleared(i: int) -> bool:
	return prog() != null and prog().cleared(Progress.stage_id(i), tier())


## How many of world `w`'s stages are cleared on the shown tier.
func world_cleared(w: int) -> int:
	var n := 0
	for j in VStage.PER_WORLD:
		if is_cleared(stage_index(w, j)):
			n += 1
	return n


func world_open(w: int) -> bool:
	return is_open(stage_index(w, 0))


## The stage to play next on the shown tier (-1 when none is open yet).
func next_stage() -> int:
	return 0 if prog() == null else prog().next_stage(tier())


## What a stage's label says: its number and name, then its best score, NEXT or LOCKED.
func stage_text(i: int) -> String:
	var st: Dictionary = VStage.STAGES[i]
	return ("%d  %s\n%s" % [st.j + 1, st.name, _sub(i)]).to_upper()


func _sub(i: int) -> String:
	var st: Dictionary = VStage.STAGES[i]
	var boss := ""
	if st.j == VStage.PER_WORLD - 1:
		boss = String(Worlds.LIST[st.world].boss_name)
	if not is_open(i):
		return "locked" if boss == "" else boss + " · locked"
	var best := ""
	if i < hud.bests.size() and int(hud.bests[i]) > 0:
		best = VHud._fmt(int(hud.bests[i]))
	if i == next_stage() and not is_cleared(i):
		return " · ".join(["next" if boss == "" else boss, best]) if best != "" else ("next" if boss == "" else boss)
	return best if best != "" else boss


## Why stage `i` is closed on the shown tier, for the footer.
func lock_reason(i: int) -> String:
	var t := tier()
	var tn: String = Progress.tier(t).name
	if i > 0 and not is_open_prev(i):
		var p: Dictionary = VStage.STAGES[i - 1]
		if p.world != VStage.STAGES[i].world:
			return "Clear %s on %s to reach %s" % [p.name, tn, Worlds.LIST[VStage.STAGES[i].world].name]
		return "Clear %d %s on %s first" % [p.j + 1, p.name, tn]
	if t > 0:
		return "Clear this stage on %s first" % Progress.tier(t - 1).name
	return "Locked"


func is_open_prev(i: int) -> bool:
	return prog() == null or prog().reach(tier()) + 1 >= i


# ---------- input ----------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
		elif _press.x >= 0:
			if _press.distance_to(e.position) < 40:
				tap(_press)
			_press = Vector2(-1, -1)
		accept_event()


## Handles a tap at `p` (local position): a world in the strip, or a stage on the route.
func tap(p: Vector2) -> void:
	if p.y < STRIP_H:
		var w := clampi(int(p.x / (size.x / VStage.WORLDS.size())), 0, VStage.WORLDS.size() - 1)
		tap_world(w)
		return
	for j in VStage.PER_WORLD:
		var c := node_pos(j)
		if p.distance_to(c) < _radius(j) + 14 or _label_rect(j).has_point(p):
			tap_stage(j)
			return


func tap_world(w: int) -> void:
	world_tapped.emit(w)


func tap_stage(j: int) -> void:
	var i := stage_index(world, j)
	_flash[j] = 12
	if is_open(i):
		stage_tapped.emit(i)
	else:
		_note = lock_reason(i)
		_note_t = 150


# ---------- layout ----------

func panel() -> Rect2:
	return Rect2(0, STRIP_H + GAP, size.x, PANEL_H)


func _radius(j: int) -> float:
	return R_BOSS if j == VStage.PER_WORLD - 1 else R


## Where stage `j` of the shown world sits: a trail climbing from the bottom of the panel to the
## boss at the top, swinging left and right.
func node_pos(j: int) -> Vector2:
	var pr := panel()
	var y0 := pr.end.y - 66.0
	var y1 := pr.position.y + 122.0
	var y := lerpf(y0, y1, float(j) / float(VStage.PER_WORLD - 1))
	var x := 0.35 if j % 2 == 0 else 0.65
	if j == VStage.PER_WORLD - 1:
		x = 0.5
	return Vector2(pr.position.x + pr.size.x * x, y)


## Labels sit outside the trail: left of the left nodes, right of the right ones (and the boss).
func _label_left(j: int) -> bool:
	return j % 2 == 0 and j != VStage.PER_WORLD - 1


func _label_rect(j: int) -> Rect2:
	var c := node_pos(j)
	var w := 170.0
	if _label_left(j):
		return Rect2(c.x - _radius(j) - 12 - w, c.y - 20, w, 40)
	return Rect2(c.x + _radius(j) + 12, c.y - 20, w, 40)


# ---------- drawing ----------

func _font(w: int) -> Font:
	return hud.fonts[w] if hud and hud.fonts.has(w) else ThemeDB.fallback_font


func _text(p: Vector2, s: String, sz: int, col: Color, w := 800, align := HORIZONTAL_ALIGNMENT_LEFT, max_w := -1.0) -> void:
	var f := _font(w)
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	if max_w > 0 and tw > max_w:
		sz = int(floor(sz * max_w / tw))
		tw = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := p.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= tw
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= tw / 2.0
	draw_string(f, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func tier_col() -> Color:
	return Color(String(Progress.tier(tier()).color))


func _draw() -> void:
	_draw_strip()
	_draw_panel()
	_draw_route()


## The six worlds as small planets with a ring of progress on the shown tier.
func _draw_strip() -> void:
	var n: int = VStage.WORLDS.size()
	var cw := size.x / n
	var tc := tier_col()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for w in n:
		var pal: Dictionary = Worlds.LIST[w].pal
		var sel := w == world
		var c := Vector2(cw * (w + 0.5), 40)
		var r := 25.0 if sel else 20.0
		var open := world_open(w)
		var done := world_cleared(w)
		var a := 1.0 if open else 0.45
		if sel:
			draw_circle(c, r + 15, Color(Color(pal.ring), 0.16))
		_planet(c, r, pal, a)
		# the progress ring: dim track, then the cleared share in the tier's colour
		var rr := r + 7.0
		draw_arc(c, rr, 0, TAU, 48, Color(1, 1, 1, 0.12 if open else 0.06), 3.0, true)
		if done > 0:
			var f := float(done) / VStage.PER_WORLD
			draw_arc(c, rr, -PI / 2, -PI / 2 + TAU * f, maxi(6, int(48 * f)), tc, 4.0, true)
		if done == VStage.PER_WORLD:
			draw_arc(c, rr + 4, 0, TAU, 48, Color(tc, 0.35 + 0.25 * pulse), 2.0, true)
		if not open:
			_lock(c, 1.0, Color(C_TEXT, 0.85))
		var lbl := "%d/%d" % [done, VStage.PER_WORLD] if open else str(w + 1)
		_text(Vector2(c.x, 87), lbl, 14 if sel else 13, (tc if done > 0 else C_TEXT) if sel else Color(C_MUTED, a), 800, HORIZONTAL_ALIGNMENT_CENTER)
		if sel:
			draw_line(Vector2(c.x - 14, 93), Vector2(c.x + 14, 93), Color(pal.ring), 3.0, true)


## A low poly planet: dark side, lit face, a highlight and a tilted ring.
func _planet(c: Vector2, r: float, pal: Dictionary, a: float) -> void:
	var body := Color(pal.planet)
	var dark := Color(pal.planet_e)
	var ring := Color(pal.ring)
	# the back half of the ring, behind the planet
	draw_set_transform(c, -0.35, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, r * 1.55, PI, TAU, 32, Color(ring, 0.55 * a), 3.0, true)
	draw_set_transform(Vector2.ZERO)
	draw_circle(c, r, Color(dark, a))
	draw_circle(c + Vector2(-r * 0.18, -r * 0.18), r * 0.8, Color(body, a))
	draw_circle(c + Vector2(-r * 0.36, -r * 0.36), r * 0.32, Color(body.lightened(0.35), a))
	draw_arc(c, r, 0, TAU, 40, Color(ring.lightened(0.2), 0.5 * a), 1.5, true)
	draw_set_transform(c, -0.35, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, r * 1.55, 0, PI, 32, Color(ring, 0.9 * a), 3.0, true)
	draw_set_transform(Vector2.ZERO)


## A padlock centred on `c`.
func _lock(c: Vector2, k: float, col: Color) -> void:
	var body := Rect2(c + Vector2(-7, -2) * k, Vector2(14, 11) * k)
	draw_arc(c + Vector2(0, -3) * k, 4.5 * k, PI, TAU, 12, col, 2.2 * k, true)
	draw_line(c + Vector2(-4.5, -3) * k, c + Vector2(-4.5, -1) * k, col, 2.2 * k)
	draw_line(c + Vector2(4.5, -3) * k, c + Vector2(4.5, -1) * k, col, 2.2 * k)
	draw_rect(body, col)
	draw_circle(c + Vector2(0, 3.2) * k, 1.6 * k, C_INK)


## The world's panel: a sky in the world's colours, its planet rising in a corner, stars, and
## the world's name with how much of it is cleared.
func _draw_panel() -> void:
	var pr := panel()
	var pal: Dictionary = Worlds.LIST[world].pal
	var top := Color(pal.top)
	var bot := Color(pal.bot)
	var pts := _rounded(pr, 26.0)
	var cols := PackedColorArray()
	for p in pts:
		var k := (p.y - pr.position.y) / pr.size.y
		cols.append(Color(top.lerp(bot, k), 0.92))
	draw_polygon(pts, cols)
	# stars: fixed per world
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + world * 17
	for s in 46:
		var p := Vector2(rng.randf_range(pr.position.x + 14, pr.end.x - 14), rng.randf_range(pr.position.y + 14, pr.end.y - 14))
		var col := Color(pal.star_b if rng.randf() < 0.3 else pal.star_a)
		draw_circle(p, rng.randf_range(0.8, 1.9), Color(col, rng.randf_range(0.25, 0.7)))
	# the world's planet, big and faint, in the top right corner
	var pc := Vector2(pr.end.x - 62, pr.position.y + 54)
	draw_circle(pc, 40, Color(Color(pal.planet_e), 0.6))
	draw_circle(pc + Vector2(-7, -7), 32, Color(Color(pal.planet), 0.32))
	draw_set_transform(pc, -0.35, Vector2(1.0, 0.3))
	draw_arc(Vector2.ZERO, 64, PI * 0.08, PI * 0.92, 40, Color(Color(pal.ring), 0.45), 2.5, true)
	draw_set_transform(Vector2.ZERO)
	# border
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(Color(pal.ring), 0.35), 1.5, true)
	# title
	var wd: Dictionary = Worlds.LIST[world]
	var x := pr.position.x + 24
	_text(Vector2(x, pr.position.y + 34), String(wd.sub).to_upper(), 14, Color(Color(pal.light), 0.9), 800)
	_text(Vector2(x, pr.position.y + 64), String(wd.name).to_upper(), 26, C_TEXT, 800, HORIZONTAL_ALIGNMENT_LEFT, pr.size.x - 60)
	var done := world_cleared(world)
	var tn: String = Progress.tier(tier()).name
	var line := "%d / %d CLEARED ON %s" % [done, VStage.PER_WORLD, tn.to_upper()]
	if not world_open(world):
		line = "LOCKED ON %s" % tn.to_upper()
	_text(Vector2(x, pr.position.y + 88), line, 13, tier_col() if done > 0 else C_MUTED, 700)
	# footer: why a stage is locked, or a hint
	var foot := _note if _note_t > 0 else ""
	if foot == "":
		if done == VStage.PER_WORLD:
			foot = "World cleared on %s" % tn
		elif world_open(world):
			foot = "Tap a stage to play"
		else:
			foot = lock_reason(stage_index(world, 0))
	_text(Vector2(pr.get_center().x, pr.end.y - 18), foot.to_upper(), 13,
			Color(VHud.C_AMBER, 0.95) if _note_t > 0 else Color(C_MUTED, 0.85), 700, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x - 40)


func _rounded(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for c in corners:
		for k in 7:
			var a: float = float(c[1]) + PI / 2 * k / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


## The trail between stage `j` and `j + 1`, as points.
func _seg(j: int) -> PackedVector2Array:
	var a := node_pos(j)
	var b := node_pos(j + 1)
	var dy := a.y - b.y
	var c0 := a + Vector2(0, -dy * 0.55)
	var c1 := b + Vector2(0, dy * 0.55)
	var pts := PackedVector2Array()
	for k in 17:
		var t := k / 16.0
		var u := 1.0 - t
		pts.append(a * u * u * u + c0 * 3 * u * u * t + c1 * 3 * u * t * t + b * t * t * t)
	return pts


func _draw_route() -> void:
	var tc := tier_col()
	var base := stage_index(world, 0)
	var nxt := next_stage()
	var ms := Time.get_ticks_msec()
	var pulse := 0.5 + 0.5 * sin(ms / 260.0)
	# the trail
	for j in VStage.PER_WORLD - 1:
		var pts := _seg(j)
		var i := base + j
		if is_cleared(i) and is_open(i + 1):
			draw_polyline(pts, Color(tc, 0.22), 11.0, true)
			draw_polyline(pts, tc, 4.0, true)
		elif is_open(i + 1) or i + 1 == nxt:
			_dashes(pts, Color(tc, 0.85), 3.0, ms / 40.0)
		else:
			_dashes(pts, Color(1, 1, 1, 0.22), 2.0, 0.0)
	# the stages
	for j in VStage.PER_WORLD:
		var i := base + j
		var c := node_pos(j)
		var r := _radius(j)
		var open := is_open(i)
		var done := is_cleared(i)
		var boss := j == VStage.PER_WORLD - 1
		var fl: int = _flash.get(j, 0)
		if fl > 0:
			_flash[j] = fl - 1
		if i == nxt and open and not done:
			draw_circle(c, r + 10 + 6 * pulse, Color(tc, 0.12 + 0.1 * pulse))
			draw_arc(c, r + 6 + 6 * pulse, 0, TAU, 40, Color(tc, 0.7 - 0.4 * pulse), 2.0, true)
		var shape := _node_shape(c, r, boss)
		if done:
			draw_colored_polygon(shape, tc)
			draw_colored_polygon(_node_shape(c, r - 4, boss), tc.darkened(0.18))
		elif open:
			draw_colored_polygon(shape, Color("140f36"))
		else:
			draw_colored_polygon(shape, Color(C_GLASS, 0.85))
		var ring := shape.duplicate()
		ring.append(shape[0])
		draw_polyline(ring, tc if open else Color(1, 1, 1, 0.25), 3.0 if open and not done else 1.5, true)
		if fl > 0:
			draw_polyline(ring, Color(1, 1, 1, fl / 12.0), 5.0, true)
		if open:
			var num := str(j + 1)
			_text(c + Vector2(0, 7 if not boss else 8), num, 20 if boss else 18, C_INK if done else C_TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_lock(c, 1.0 if not boss else 1.25, Color(1, 1, 1, 0.45))
		_draw_label(j, i, open, done)


func _node_shape(c: Vector2, r: float, boss: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 6 if boss else 28
	for k in n:
		var a := TAU * k / n + (PI / 2 if boss else 0.0)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


func _dashes(pts: PackedVector2Array, col: Color, w: float, phase: float) -> void:
	var dash := 7.0
	var gap := 7.0
	var along := -fmod(phase, dash + gap)
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var l := a.distance_to(b)
		var s := 0.0
		while s < l:
			var pos := along + s
			var m := fmod(pos, dash + gap)
			if m < 0:
				m += dash + gap
			var run := minf((dash - m) if m < dash else (dash + gap - m), l - s)
			if m < dash:
				draw_line(a.lerp(b, s / l), a.lerp(b, (s + run) / l), col, w, true)
			s += maxf(run, 0.01)
		along += l


func _draw_label(j: int, i: int, open: bool, done: bool) -> void:
	var st: Dictionary = VStage.STAGES[i]
	var rect := _label_rect(j)
	var left := _label_left(j)
	var al := HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	var x := rect.end.x if left else rect.position.x
	var tc := tier_col()
	var name_col := C_TEXT if open else Color(C_MUTED, 0.55)
	_text(Vector2(x, rect.position.y + 17), String(st.name).to_upper(), 16, name_col, 800, al, rect.size.x)
	var sub := _sub(i).to_upper()
	var sub_col := Color(C_MUTED, 0.9)
	if open and i == next_stage() and not done:
		sub_col = tc
	elif not open:
		sub_col = Color(C_MUTED, 0.45)
	# medal pips beside the second line once the stage is cleared on this tier
	var pip_w := 0.0
	if done and prog():
		pip_w = 4 * 11.0
		var m := prog().medals(Progress.stage_id(i), tier())
		var px := (x - pip_w) if left else x
		for k in Progress.MEDALS.size():
			var col := Color(String(Progress.MEDAL_INFO[Progress.MEDALS[k]].color))
			var pc := Vector2(px + 5 + k * 11, rect.position.y + 30)
			if m & (1 << k):
				draw_circle(pc, 4.0, col)
			else:
				draw_arc(pc, 3.5, 0, TAU, 12, Color(col, 0.5), 1.4, true)
		pip_w += 8
	if sub != "":
		var sx := (x - pip_w) if left else (x + pip_w)
		_text(Vector2(sx, rect.position.y + 36), sub, 13, sub_col, 700, al, rect.size.x - pip_w)
