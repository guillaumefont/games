class_name VMap
extends Control
## The level map: all 48 stages on one trail climbing from the bottom of the screen to the top,
## world after world. Drag to scroll. The sky shifts from one world's colours to the next, and a
## banner (planet, name, progress) marks the way into each world. Each stage shows which tiers
## it is cleared on (three pips); the trail is lit up to the next stage, marked with a target.
## Tap an open stage to open its panel (VHud picks the tier and plays it); a locked stage says
## what to clear first. Drawn in code, no child nodes. The stage order follows Normal: a stage
## is on the map once it is open on Normal, and its panel shows which harder tiers are open.

signal stage_tapped(stage: int)

const R := 21.0
const R_BOSS := 28.0
## Content layout, in pixels up from the bottom of the trail.
const BOTTOM := 150.0
const STEP := 104.0
const BANNER := 250.0
const TOP_PAD := 240.0
## The screen bands the menu's own controls cover (top bar, bottom bar).
const TOP_H := 150.0
const BOT_H := 130.0
const C_TEXT := Color("f4f2ff")
const C_MUTED := Color("bdb6e0")
const C_INK := Color("0b0830")
const C_GLASS := Color(22 / 255.0, 17 / 255.0, 50 / 255.0, 0.7)
const C_SPORE := Color("ff4fa3")

var hud: VHud
## The world in the middle of the view.
var world := 0
## How far the view has scrolled up the trail (content y at the bottom edge), and where it is
## gliding to (-1: nowhere, it coasts on `_vel`).
var scroll := 0.0
var _target := -1.0
var _vel := 0.0
## The stage whose panel is open (-1: none); it is ringed on the map.
var picked := -1
## A line over the bottom bar: why a tapped stage is locked (for `_note_t` frames).
var _note := ""
var _note_t := 0
var _press := Vector2(-1, -1)
var _drag := 0.0
var _flash := {}


func _init(h: VHud) -> void:
	hud = h
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(d: float) -> void:
	if not is_visible_in_tree():
		return
	if _note_t > 0:
		_note_t -= 1
	if _target >= 0.0:
		scroll = lerpf(scroll, _target, minf(1.0, d * 9.0))
		if absf(scroll - _target) < 0.5:
			scroll = _target
			_target = -1.0
	elif absf(_vel) > 1.0 and _press.x < 0:
		scroll += _vel * d
		_vel *= pow(0.04, d)
	_clamp()
	world = world_at_view()
	queue_redraw()


# ---------- progress ----------

func prog() -> Progress:
	return hud.prog


func is_open(i: int, t := 0) -> bool:
	return prog() == null or prog().open(i, t)


func is_cleared(i: int, t := 0) -> bool:
	return prog() != null and prog().cleared(Progress.stage_id(i), t)


## How many of world `w`'s stages are cleared on tier `t`.
func world_cleared(w: int, t := 0) -> int:
	var n := 0
	for j in VStage.PER_WORLD:
		if is_cleared(w * VStage.PER_WORLD + j, t):
			n += 1
	return n


func world_open(w: int) -> bool:
	return is_open(w * VStage.PER_WORLD)


## The next stage on the trail (Normal): the one the target marks.
func next_stage() -> int:
	return 0 if prog() == null else maxi(0, prog().next_stage(0))


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


## Why stage `i` is closed on tier `t`.
func lock_reason(i: int, t := 0) -> String:
	var tn: String = Progress.tier(t).name
	if t > 0:
		# a higher tier only needs this stage cleared on the tier below
		if t > 1 and prog() and not prog().open(i, t - 1):
			return "Clear this stage on %s, then %s" % [Progress.tier(t - 2).name, Progress.tier(t - 1).name]
		return "Clear this stage on %s first" % Progress.tier(t - 1).name
	if i > 0 and prog() and prog().reach(0) + 1 < i:
		var p: Dictionary = VStage.STAGES[i - 1]
		if p.world != VStage.STAGES[i].world:
			return "Clear %s on %s to reach %s" % [p.name, tn, Worlds.LIST[VStage.STAGES[i].world].name]
		return "Clear %d %s on %s first" % [p.j + 1, p.name, tn]
	return "Locked"


# ---------- layout ----------

func _col_w() -> float:
	return minf(size.x, 600.0)


func _x0() -> float:
	return (size.x - _col_w()) / 2.0


## Where each stage sits, like a tactical map rather than a zigzag: [height up the trail, x as a
## share of the column]. Seeded, so the map is always the same. Steps between stages vary, the
## route swings by uneven amounts and sometimes keeps going the same way, and bosses sit near
## the middle.
static var _LAYOUT: Array = _make_layout()


static func _make_layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var out: Array = []
	var u := BOTTOM
	var x := 0.3
	var dir := 1.0
	for i in VStage.STAGES.size():
		var j: int = VStage.STAGES[i].j
		if j == 0:
			u += BANNER if i == 0 else BANNER + STEP
		else:
			u += STEP * rng.randf_range(0.72, 1.45) + (18.0 if j == VStage.PER_WORLD - 1 else 0.0)
		if j == VStage.PER_WORLD - 1:
			x = 0.5 + rng.randf_range(-0.07, 0.07)
		elif i > 0:
			if rng.randf() < 0.55:
				dir = -dir
			var nx := x + dir * rng.randf_range(0.12, 0.5)
			if nx < 0.12 or nx > 0.88:
				dir = -dir
				nx = x + dir * rng.randf_range(0.15, 0.4)
			x = clampf(nx, 0.12, 0.88)
		out.append([u, x])
	return out


## Where stage `i` sits on the trail, in pixels up from the bottom.
static func stage_u(i: int) -> float:
	return float(_LAYOUT[i][0])


## Stage `i`'s place across the column (0 left, 1 right).
static func stage_x(i: int) -> float:
	return float(_LAYOUT[i][1])


## The middle of world `w`'s banner (between the last stage before it and its first).
static func banner_u(w: int) -> float:
	var first := w * VStage.PER_WORLD
	if first == 0:
		return stage_u(0) - BANNER * 0.6
	return (stage_u(first - 1) + stage_u(first)) / 2.0


static func total_u() -> float:
	return stage_u(VStage.STAGES.size() - 1) + TOP_PAD


func _y(u: float) -> float:
	return size.y - (u - scroll)


func max_scroll() -> float:
	return maxf(0.0, total_u() - size.y)


func _clamp() -> void:
	scroll = clampf(scroll, 0.0, max_scroll())


## Screen position of stage `i` (see `_LAYOUT`).
func node_pos(i: int) -> Vector2:
	return Vector2(_x0() + _col_w() * stage_x(i), _y(stage_u(i)))


func _radius(i: int) -> float:
	return R_BOSS if VStage.STAGES[i].j == VStage.PER_WORLD - 1 else R


## A label goes on the roomier side of its stage.
func _label_left(i: int) -> bool:
	return stage_x(i) > 0.5


func _label_rect(i: int) -> Rect2:
	var c := node_pos(i)
	var room := (c.x - _x0()) if _label_left(i) else (_x0() + _col_w() - c.x)
	var w := minf(190.0, room - _radius(i) - 20)
	if _label_left(i):
		return Rect2(c.x - _radius(i) - 14 - w, c.y - 22, w, 46)
	return Rect2(c.x + _radius(i) + 14, c.y - 22, w, 46)


## The world whose stretch of trail is in the middle of the view.
func world_at_view() -> int:
	var u := scroll + size.y * 0.5
	var w := 0
	for k in VStage.WORLDS.size():
		if u >= banner_u(k) - BANNER * 0.5:
			w = k
	return w


## Scrolls so stage `i` sits `at` of the way up the view (a little below the middle by default).
func focus(i: int, instant := false, at := 0.42) -> void:
	var t := clampf(stage_u(clampi(i, 0, VStage.STAGES.size() - 1)) - size.y * at, 0.0, max_scroll())
	_vel = 0.0
	if instant or size.y <= 0.0:
		scroll = t
		_target = -1.0
		world = world_at_view()
	else:
		_target = t


func focus_world(w: int, instant := false) -> void:
	var i := w * VStage.PER_WORLD
	var nx := next_stage()
	if VStage.world_of(nx) == w:
		i = nx
	focus(i, instant)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _target < 0.0:
		_clamp()


# ---------- input ----------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_press = e.position
			_drag = 0.0
			_vel = 0.0
			_target = -1.0
		elif _press.x >= 0:
			if _drag < 14.0:
				tap(_press)
				_vel = 0.0
			_press = Vector2(-1, -1)
		accept_event()
	elif e is InputEventMouseMotion and _press.x >= 0:
		var dy: float = e.relative.y
		_drag += absf(dy) + absf(e.relative.x)
		scroll += dy
		_clamp()
		_vel = lerpf(_vel, dy * 60.0, 0.5)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll += 60.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -60.0
		_target = -1.0
		_clamp()
		accept_event()


## Handles a tap at `p` (local position): the stage under it, if any.
func tap(p: Vector2) -> void:
	if p.y < TOP_H or p.y > size.y - BOT_H:
		return
	for i in VStage.STAGES.size():
		var c := node_pos(i)
		if c.y < -60 or c.y > size.y + 60:
			continue
		if p.distance_to(c) < _radius(i) + 16 or _label_rect(i).has_point(p):
			tap_stage(i)
			return


func tap_stage(i: int) -> void:
	_flash[i] = 12
	if is_open(i):
		picked = i
		stage_tapped.emit(i)
	else:
		_note = lock_reason(i)
		_note_t = 150


# ---------- drawing helpers ----------

func _font(w: int) -> Font:
	return hud.fonts[w] if hud and hud.fonts.has(w) else ThemeDB.fallback_font


func _text(p: Vector2, s: String, sz: int, col: Color, w := 800, align := HORIZONTAL_ALIGNMENT_LEFT, max_w := -1.0, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
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
	ci.draw_string(f, Vector2(x, p.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


static func tier_color(t: int) -> Color:
	return Color(String(Progress.tier(t).color))


## A low poly planet: dark side, lit face, a highlight and a tilted ring.
func _planet(c: Vector2, r: float, pal: Dictionary, a: float, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var body := Color(pal.planet)
	var dark := Color(pal.planet_e)
	var ring := Color(pal.ring)
	ci.draw_set_transform(c, -0.35, Vector2(1.0, 0.32))
	ci.draw_arc(Vector2.ZERO, r * 1.55, PI, TAU, 32, Color(ring, 0.55 * a), 3.0, true)
	ci.draw_set_transform(Vector2.ZERO)
	ci.draw_circle(c, r, Color(dark, a))
	ci.draw_circle(c + Vector2(-r * 0.18, -r * 0.18), r * 0.8, Color(body, a))
	ci.draw_circle(c + Vector2(-r * 0.36, -r * 0.36), r * 0.32, Color(body.lightened(0.35), a))
	ci.draw_arc(c, r, 0, TAU, 40, Color(ring.lightened(0.2), 0.5 * a), 1.5, true)
	ci.draw_set_transform(c, -0.35, Vector2(1.0, 0.32))
	ci.draw_arc(Vector2.ZERO, r * 1.55, 0, PI, 32, Color(ring, 0.9 * a), 3.0, true)
	ci.draw_set_transform(Vector2.ZERO)


## A padlock centred on `c`.
func _lock(c: Vector2, k: float, col: Color, ci: CanvasItem = null) -> void:
	if ci == null:
		ci = self
	var body := Rect2(c + Vector2(-7, -2) * k, Vector2(14, 11) * k)
	ci.draw_arc(c + Vector2(0, -3) * k, 4.5 * k, PI, TAU, 12, col, 2.2 * k, true)
	ci.draw_line(c + Vector2(-4.5, -3) * k, c + Vector2(-4.5, -1) * k, col, 2.2 * k)
	ci.draw_line(c + Vector2(4.5, -3) * k, c + Vector2(4.5, -1) * k, col, 2.2 * k)
	ci.draw_rect(body, col)
	ci.draw_circle(c + Vector2(0, 3.2) * k, 1.6 * k, C_INK)


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


# ---------- drawing ----------

## World `w`'s colour on the map: its sky, pulled towards its ring colour so worlds tell apart.
static func world_color(w: int) -> Color:
	var pal: Dictionary = Worlds.LIST[w].pal
	return Color(pal.top).lerp(Color(pal.ring), 0.28)


## The sky colour at trail height `u`: each world's colour around its own stretch, blending into
## the next world's across the banner between them.
func sky(u: float) -> Color:
	var n: int = VStage.WORLDS.size()
	var keys: Array = []
	for w in n:
		var pal: Dictionary = Worlds.LIST[w].pal
		var a := stage_u(w * VStage.PER_WORLD)
		var b := stage_u(w * VStage.PER_WORLD + VStage.PER_WORLD - 1)
		# the world's own colour holds across its whole stretch (a touch lighter at its top) and
		# only changes across the banner into the next world
		var col := world_color(w)
		keys.append([a - STEP * 0.4, col])
		keys.append([b + STEP * 0.4, col.lightened(0.06)])
	if u <= keys[0][0]:
		return Color(Worlds.LIST[0].pal.bot).lerp(keys[0][1], clampf(u / keys[0][0], 0.0, 1.0))
	for k in keys.size() - 1:
		if u <= keys[k + 1][0]:
			var f := (u - float(keys[k][0])) / (float(keys[k + 1][0]) - float(keys[k][0]))
			return (keys[k][1] as Color).lerp(keys[k + 1][1], smoothstep(0.0, 1.0, f))
	return keys[keys.size() - 1][1]


func _draw() -> void:
	_draw_sky()
	_draw_tactical()
	_draw_trail()
	for w in VStage.WORLDS.size():
		_draw_banner(w)
	_draw_stages()
	_draw_fades()


func _draw_sky() -> void:
	var band := 24.0
	var y := size.y
	while y > -band:
		var u0 := scroll + (size.y - y)
		var u1 := u0 + band
		var pts := PackedVector2Array([Vector2(0, y), Vector2(size.x, y), Vector2(size.x, y - band), Vector2(0, y - band)])
		var c0 := sky(u0)
		var c1 := sky(u1)
		draw_polygon(pts, PackedColorArray([c0, c0, c1, c1]))
		y -= band
	# stars, fixed to the trail so they scroll with it
	var cell := 140.0
	var k0 := int(floor(scroll / cell))
	var k1 := int(ceil((scroll + size.y) / cell))
	for k in range(k0, k1 + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7741 + k * 131
		var pal: Dictionary = Worlds.LIST[_world_of_u(k * cell)].pal
		for s in 5:
			var p := Vector2(rng.randf_range(0, size.x), _y(k * cell + rng.randf_range(0, cell)))
			var col := Color(pal.star_b if rng.randf() < 0.3 else pal.star_a)
			draw_circle(p, rng.randf_range(0.8, 2.0), Color(col, rng.randf_range(0.25, 0.75)))
	# each world's planet, big and faint, beside its stretch of trail
	for w in VStage.WORLDS.size():
		var pal: Dictionary = Worlds.LIST[w].pal
		var u := (stage_u(w * VStage.PER_WORLD + 3) + stage_u(w * VStage.PER_WORLD + 4)) / 2.0
		var pc := Vector2(size.x * (0.92 if w % 2 == 0 else 0.08), _y(u))
		if pc.y < -200 or pc.y > size.y + 200:
			continue
		draw_circle(pc, 120, Color(Color(pal.planet_e), 0.45))
		draw_circle(pc + Vector2(-18, -18), 98, Color(Color(pal.planet), 0.18))
		draw_set_transform(pc, -0.35, Vector2(1.0, 0.3))
		draw_arc(Vector2.ZERO, 190, 0, PI, 48, Color(Color(pal.ring), 0.25), 4.0, true)
		draw_set_transform(Vector2.ZERO)


## The tactical layer: a survey grid with sector numbers, and terrain contours (nested rings of
## uneven hills and craters) in each world's colour. All fixed to the trail, so they scroll.
const GRID := 48.0


func _draw_tactical() -> void:
	var w0 := _world_of_u(scroll + size.y * 0.5)
	var lc := world_color(w0).lightened(0.45)
	var x := fposmod(size.x / 2.0, GRID)
	var n := 0
	while x < size.x:
		var major := int(round((x - size.x / 2.0) / GRID)) % 4 == 0
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(lc, 0.17 if major else 0.07), 1.0)
		x += GRID
		n += 1
	var k0 := int(floor(scroll / GRID))
	var k1 := int(ceil((scroll + size.y) / GRID))
	for k in range(k0, k1 + 1):
		var y := _y(k * GRID)
		var major := k % 4 == 0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(lc, 0.17 if major else 0.07), 1.0)
		if major and k >= 0:
			_text(Vector2(8, y - 5), "%03d" % (k / 4), 11, Color(lc, 0.35), 700)
			_text(Vector2(size.x - 8, y - 5), "%s-%02d" % [char(65 + _world_of_u(k * GRID)), (k / 4) % 100], 11, Color(lc, 0.35), 700, HORIZONTAL_ALIGNMENT_RIGHT)
	# contours: a few features per world
	for w in VStage.WORLDS.size():
		var lo := banner_u(w)
		var hi := banner_u(w + 1) if w + 1 < VStage.WORLDS.size() else total_u()
		if _y(hi) > size.y + 200 or _y(lo) < -200:
			continue
		var col := world_color(w).lightened(0.4)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3301 + w * 977
		for f in 6:
			var cu := rng.randf_range(lo, hi)
			var cx := rng.randf_range(-0.05, 1.05) * size.x
			var base := rng.randf_range(70.0, 160.0)
			var rings := rng.randi_range(3, 5)
			var p1 := rng.randf() * TAU
			var p2 := rng.randf() * TAU
			var stretch := rng.randf_range(0.6, 1.0)
			var c := Vector2(cx, _y(cu))
			if c.y < -base - 20 or c.y > size.y + base + 20:
				continue
			for k in rings:
				var r := base * (1.0 - 0.2 * k)
				var pts := PackedVector2Array()
				for a in 49:
					var t := TAU * a / 48.0
					var rr := r * (1.0 + 0.16 * sin(3.0 * t + p1 + k * 0.4) + 0.09 * sin(5.0 * t + p2))
					pts.append(c + Vector2(cos(t) * rr, sin(t) * rr * stretch))
				draw_polyline(pts, Color(col, 0.13 + 0.05 * k), 1.6 if k == rings - 1 else 1.2, true)
			# a survey mark on the summit
			draw_line(c + Vector2(-4, 0), c + Vector2(4, 0), Color(col, 0.3), 1.0)
			draw_line(c + Vector2(0, -4), c + Vector2(0, 4), Color(col, 0.3), 1.0)


func _world_of_u(u: float) -> int:
	var w := 0
	for k in VStage.WORLDS.size():
		if u >= banner_u(k):
			w = k
	return w


## The trail between stage `i` and `i + 1`, as points.
func _seg(i: int) -> PackedVector2Array:
	var a := node_pos(i)
	var b := node_pos(i + 1)
	var dy := a.y - b.y
	# a seeded sideways kick so each leg of the route bends its own way
	var wob := (fposmod(sin(i * 12.9898) * 43758.5453, 1.0) - 0.5) * 90.0
	var c0 := a + Vector2(wob, -dy * 0.5)
	var c1 := b + Vector2(-wob * 0.6, dy * 0.45)
	var pts := PackedVector2Array()
	for k in 17:
		var t := k / 16.0
		var u := 1.0 - t
		pts.append(a * u * u * u + c0 * 3 * u * u * t + c1 * 3 * u * t * t + b * t * t * t)
	return pts


func _draw_trail() -> void:
	var tc := tier_color(0)
	var ms := Time.get_ticks_msec()
	var nxt := next_stage()
	for i in VStage.STAGES.size() - 1:
		var ya := _y(stage_u(i))
		var yb := _y(stage_u(i + 1))
		if ya < -40 or yb > size.y + 40:
			continue
		var pts := _seg(i)
		if is_cleared(i) and is_open(i + 1):
			draw_polyline(pts, Color(tc, 0.22), 12.0, true)
			draw_polyline(pts, tc, 4.0, true)
		elif is_open(i + 1) or i + 1 == nxt:
			_dashes(pts, Color(tc, 0.85), 3.0, ms / 40.0)
		else:
			_dashes(pts, Color(1, 1, 1, 0.22), 2.0, 0.0)


## The way into world `w`: a glass plate with its planet, name, progress on each tier, and a
## line of the story under them.
func _draw_banner(w: int) -> void:
	var cy := _y(banner_u(w))
	if cy < -120 or cy > size.y + 120:
		return
	var wd: Dictionary = Worlds.LIST[w]
	var pal: Dictionary = wd.pal
	var open := world_open(w)
	var a := 1.0 if open else 0.6
	var bw := minf(_col_w() - 40, 440.0)
	var r := Rect2(size.x / 2.0 - bw / 2.0, cy - 84, bw, 172)
	var pts := _rounded(r, 24.0)
	draw_colored_polygon(pts, Color(Color(pal.bg), 0.82))
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, Color(Color(pal.ring), 0.6 * a), 2.0, true)
	var pc := r.position + Vector2(62, 64)
	_planet(pc, 32, pal, a)
	if not open:
		_lock(pc, 1.4, Color(C_TEXT, 0.9))
	var x := r.position.x + 124
	_text(Vector2(x, r.position.y + 34), String(wd.sub).to_upper(), 14, Color(Color(pal.light), 0.9 * a), 800)
	_text(Vector2(x, r.position.y + 66), String(wd.name).to_upper(), 26, Color(C_TEXT, a), 800, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - 16)
	# the story so far, shown even before the world opens
	var story := String(wd.get("story", ""))
	if story != "":
		draw_multiline_string(_font(500), Vector2(r.position.x + 22, r.position.y + 146), story, HORIZONTAL_ALIGNMENT_LEFT,
			r.size.x - 44, 14, 2, Color(C_MUTED, 0.95 * a))
	if not open:
		_text(Vector2(x, r.position.y + 100), "LOCKED", 14, Color(C_MUTED, 0.8), 800)
		return
	# one short bar per tier: how much of the world is cleared on it
	var bwid := (r.end.x - x - 24) / 3.0
	for t in Progress.TIERS.size():
		var n := world_cleared(w, t)
		var bx := x + t * (bwid + 6)
		var col := tier_color(t)
		draw_rect(Rect2(bx, r.position.y + 88, bwid - 6, 6), Color(1, 1, 1, 0.12))
		if n > 0:
			draw_rect(Rect2(bx, r.position.y + 88, (bwid - 6) * n / float(VStage.PER_WORLD), 6), col)
		_text(Vector2(bx, r.position.y + 114), "%s %d/8" % [String(Progress.TIERS[t].name).to_upper(), n], 11, Color(col, 0.95 if n > 0 else 0.5), 800, HORIZONTAL_ALIGNMENT_LEFT, bwid - 6)


func _draw_stages() -> void:
	var tc := tier_color(0)
	var nxt := next_stage()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for i in VStage.STAGES.size():
		var c := node_pos(i)
		if c.y < -60 or c.y > size.y + 60:
			continue
		var r := _radius(i)
		var open := is_open(i)
		var done := is_cleared(i)
		var boss: bool = VStage.STAGES[i].j == VStage.PER_WORLD - 1
		var fl: int = _flash.get(i, 0)
		if fl > 0:
			_flash[i] = fl - 1
		if i == nxt and open and not done:
			# a target reticle: corner brackets closing in, cross hairs
			draw_circle(c, r + 8, Color(tc, 0.1 + 0.08 * pulse))
			var e := r + 14 + 5 * pulse
			for q in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var corner: Vector2 = c + q * e
				draw_line(corner, corner - Vector2(q.x * 9, 0), tc, 2.5)
				draw_line(corner, corner - Vector2(0, q.y * 9), tc, 2.5)
			for q in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(c + q * (r + 3), c + q * (r + 10), Color(tc, 0.8), 2.0)
		if boss:
			# a danger ring round the world boss
			var ph := Time.get_ticks_msec() / 2000.0
			for d in 12:
				var a0 := ph + TAU * d / 12.0
				draw_arc(c, r + 7, a0, a0 + TAU / 24.0, 4, Color(C_SPORE, 0.75 if open else 0.3), 2.0, true)
		if i == picked:
			draw_arc(c, r + 9, 0, TAU, 40, C_TEXT, 3.0, true)
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
			_text(c + Vector2(0, 8 if not boss else 9), str(VStage.STAGES[i].j + 1), 22 if boss else 20, C_INK if done else C_TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER)
			# which tiers it's cleared on: three pips under the node
			for t in Progress.TIERS.size():
				var pc := c + Vector2((t - 1) * 11, r + 9)
				var col := tier_color(t)
				if is_cleared(i, t):
					draw_circle(pc, 4.2, col)
				else:
					draw_arc(pc, 3.6, 0, TAU, 12, Color(col, 0.45), 1.4, true)
		else:
			_lock(c, 1.0 if not boss else 1.25, Color(1, 1, 1, 0.45))
		_draw_label(i, open, done)


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
		if l <= 0.0:
			continue
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


func _draw_label(i: int, open: bool, done: bool) -> void:
	var st: Dictionary = VStage.STAGES[i]
	var rect := _label_rect(i)
	var left := _label_left(i)
	var al := HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	var x := rect.end.x if left else rect.position.x
	var name_col := C_TEXT if open else Color(C_MUTED, 0.55)
	_text(Vector2(x, rect.position.y + 17), String(st.name).to_upper(), 18, name_col, 800, al, rect.size.x)
	var sub := _sub(i).to_upper()
	var sub_col := Color(C_MUTED, 0.9)
	if open and i == next_stage() and not done:
		sub_col = tier_color(0)
	elif not open:
		sub_col = Color(C_MUTED, 0.45)
	if sub != "":
		_text(Vector2(x, rect.position.y + 40), sub, 14, sub_col, 700, al, rect.size.x)


## The top and bottom bars fade the trail out under the menu's controls; the bottom one carries
## the note on a locked stage.
func _draw_fades() -> void:
	var dark := Color(5 / 255.0, 4 / 255.0, 26 / 255.0)
	var clear := Color(dark, 0.0)
	draw_rect(Rect2(0, 0, size.x, TOP_H - 20), Color(dark, 0.9))
	draw_polygon(PackedVector2Array([Vector2(0, TOP_H - 20), Vector2(size.x, TOP_H - 20), Vector2(size.x, TOP_H + 50), Vector2(0, TOP_H + 50)]),
		PackedColorArray([Color(dark, 0.9), Color(dark, 0.9), clear, clear]))
	var y := size.y - BOT_H - 50
	draw_polygon(PackedVector2Array([Vector2(0, y), Vector2(size.x, y), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([clear, clear, Color(dark, 0.95), Color(dark, 0.95)]))
	if _note_t > 0:
		_text(Vector2(size.x / 2.0, size.y - BOT_H - 14), _note.to_upper(), 15, Color(VHud.C_AMBER, minf(1.0, _note_t / 20.0)), 700,
			HORIZONTAL_ALIGNMENT_CENTER, _col_w() - 40)
