extends RefCounted
## Preload it (`const Radar := preload("res://scripts/radar.gd")`); no class_name, so the self-update pack can carry it.
## Radar mode (Guillaume 2026-11-27: "a radar mode by zooming out, you can then handle units in bulk"; it replaces the
## minimap and the MAP button, and opens by pinching only). View3D pulls the camera back and tilts it as the player
## pinches out past View3D.Z_NEAR; this draws what the 3D view stops showing, over the 3D view:
## - a tactical grid and the map's edge, the ground greyed by UI.radar_tint;
## - buildings as footprints in their team colour (a star on a Command Yard), units as icons (circle infantry,
##   square vehicle, triangle air, diamond harvester), enemies only where the fog lets the player see them;
## - each squad as a ring and a numbered badge (size, health, "!" under fire), with a line to where it is heading;
## - red rings where the player's units or buildings are being hit, and the last "under attack" alert.
## main.gd asks `badge_at` on taps and drags: a badge tap adds or drops that squad, dragging one sends it.

const Squads := preload("res://scripts/squads.gd")
const T := 32
const GRID := 4          # a grid line every 4 tiles
const ICON := 3.6        # half size of a unit icon, UI units
const BADGE := Vector2(36, 19)

var badges: Array = []   # [{n, rect, c (ring centre), r (ring radius)}], filled by draw for taps
var drag_n := 0          # squad whose badge is being dragged, and where the finger is
var drag_p := Vector2()

static func team_col(team: int) -> Color:
	return D.MINI_COL[team] if team < D.MINI_COL.size() else Color("c9c3b0")

## The squad badge under a screen point, or 0. A little larger than drawn: fingers are wide.
func badge_at(p: Vector2) -> int:
	for b in badges:
		if (b.rect as Rect2).grow(7).has_point(p): return b.n
	return 0

func draw(c: Control, m, k: float) -> void:
	badges = []
	if k <= 0.0: return
	var S = m.S; var V = m.V; var U = m.U
	var a := k
	_grid(c, V, a)
	# buildings: footprints
	for e in S.ents:
		if not e.alive or e.kind != "b" or e.end_kind != "": continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var pts := PackedVector2Array()
		var gh: float = S.h_at(e.x, e.y)
		for q in [Vector2(e.tx, e.ty), Vector2(e.tx + e.w, e.ty), Vector2(e.tx + e.w, e.ty + e.h), Vector2(e.tx, e.ty + e.h)]:
			var s: Vector3 = V.w2s(q.x * T, q.y * T, gh)
			if s.z < 0: pts = PackedVector2Array(); break
			pts.append(Vector2(s.x, s.y))
		if pts.size() < 4: continue
		var col := team_col(e.team)
		c.draw_colored_polygon(pts, Color(col, 0.34 * a))
		pts.append(pts[0])
		c.draw_polyline(pts, Color(col.lightened(0.15), 0.95 * a), 1.4 if not e.sel else 2.4)
		if e.sel: c.draw_polyline(pts, Color(1, 1, 1, a), 1.0)
		if e.d.get("yard", false):
			var ctr := (pts[0] + pts[2]) / 2
			_star(c, ctr, 5.5, Color(1, 1, 1, 0.95 * a))
		if e.team == 0 and e.hit_t > 0: _alert(c, (pts[0] + pts[2]) / 2, 14.0, S.time, a)
	# squads: rings first, so the icons sit on top
	m.sq.prune(S)
	var info := []
	for q in m.sq.list:
		var mem: Array = m.sq.members(S, q.n).filter(func(e): return e.intun <= 0)
		if mem.is_empty(): continue
		var ctr := Vector2(); var pts := []
		for e in mem:
			var s := _spos(S, V, e)
			if s.z < 0: continue
			pts.append(Vector2(s.x, s.y)); ctr += Vector2(s.x, s.y)
		if pts.is_empty(): continue
		ctr /= pts.size()
		# the ring hugs most of the squad: one straggler should not blow it up
		var ds: Array = pts.map(func(p): return p.distance_to(ctr)); ds.sort()
		var r := clampf(float(ds[int((ds.size() - 1) * 0.75)]) + 9.0, 15.0, 40.0)
		var on: bool = mem.all(func(e): return e.sel)
		var st: Dictionary = m.sq.status(S, q.n)
		info.append({"n": q.n, "c": ctr, "r": r, "on": on, "st": st, "mem": mem})
	var own := team_col(0)
	for s in info:
		if s.st.hit: _alert(c, s.c, s.r, S.time, a)
		if s.on:
			c.draw_circle(s.c, s.r, Color(1, 1, 1, 0.1 * a))
			c.draw_arc(s.c, s.r, 0, TAU, 40, Color(1, 1, 1, 0.9 * a), 1.6, true)
		else:
			c.draw_circle(s.c, s.r, Color(own, 0.07 * a))
			_dashed_ring(c, s.c, s.r, Color(own, 0.65 * a))
		_heading(c, S, V, s, a)
	# units
	for e in S.ents:
		if not e.alive or e.kind != "u" or e.intun > 0: continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var s := _spos(S, V, e)
		if s.z < 0: continue
		var p := Vector2(s.x, s.y)
		if e.captive:
			c.draw_arc(p, 5, 0, TAU, 16, Color(Color("f0b93f"), a), 2.0); continue
		_icon(c, e, p, team_col(e.team), a)
	# badges last: they are what the player taps
	var vr: Rect2 = V.view_rect()
	for s in info:
		var rc := Rect2(s.c + Vector2(-BADGE.x / 2, -s.r - BADGE.y - 3), BADGE)
		rc.position = rc.position.clamp(vr.position + Vector2(4, 4), vr.end - BADGE - Vector2(4, 4))
		_badge(c, U, rc, s, a)
		badges.append({"n": s.n, "rect": rc, "c": s.c, "r": s.r})
	# the last "under attack" alert, as on the old minimap
	if S.ping != null and S.time - S.ping.t < 4:
		var f := fmod(S.time - S.ping.t, 1.0)
		var q: Vector3 = V.w2s(S.ping.x, S.ping.y, S.h_at(S.ping.x, S.ping.y))
		if q.z > 0: c.draw_arc(Vector2(q.x, q.y), 8 + f * 30, 0, TAU, 32, Color(1, .35, .32, (1 - f) * a), 2.0, true)
	# a badge being dragged: a line from it to the finger, and the badge there
	if drag_n > 0:
		for b in badges:
			if b.n != drag_n: continue
			var from: Vector2 = (b.rect as Rect2).get_center()
			c.draw_dashed_line(from, drag_p, Color("f3c74b"), 2.0, 6.0)
			c.draw_arc(drag_p, 10, 0, TAU, 24, Color("f3c74b"), 2.0, true)
			var g := Rect2(drag_p + Vector2(-BADGE.x / 2, -BADGE.y - 16), BADGE)
			c.draw_rect(g, Color(0.08, 0.09, 0.07, 0.85)); c.draw_rect(g, Color("f3c74b"), false, 1.5)
			c.draw_string(U.f_disp7, g.position + Vector2(6, 15), str(drag_n), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f3c74b"))

## Where a unit's icon goes: on the ground under it (air units a little higher, so they float over their shadow).
func _spos(S, V, e) -> Vector3:
	return V.w2s(e.x, e.y, S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0))

func _grid(c: Control, V, a: float) -> void:
	var lc := Color(0.5, 0.89, 0.77, 0.11 * a)
	for i in range(0, 64 / GRID + 1):
		var u := float(i * GRID * T)
		var p0: Vector3 = V.w2s(u, 0, 0); var p1: Vector3 = V.w2s(u, D.WH, 0)
		if p0.z > 0 and p1.z > 0: c.draw_line(Vector2(p0.x, p0.y), Vector2(p1.x, p1.y), lc, 1.0)
		var q0: Vector3 = V.w2s(0, u, 0); var q1: Vector3 = V.w2s(D.WW, u, 0)
		if q0.z > 0 and q1.z > 0: c.draw_line(Vector2(q0.x, q0.y), Vector2(q1.x, q1.y), lc, 1.0)
	var edge := PackedVector2Array()
	for q in [Vector2(0, 0), Vector2(D.WW, 0), Vector2(D.WW, D.WH), Vector2(0, D.WH), Vector2(0, 0)]:
		var s: Vector3 = V.w2s(q.x, q.y, 0)
		if s.z < 0: return
		edge.append(Vector2(s.x, s.y))
	c.draw_polyline(edge, Color(0.5, 0.89, 0.77, 0.4 * a), 1.5)

func _icon(c: Control, e, p: Vector2, col: Color, a: float) -> void:
	var s := ICON + (0.8 if e.sel else 0.0)
	var dark := Color(0.03, 0.04, 0.05, 0.9 * a)
	var fill := Color(col, a)
	var poly: PackedVector2Array
	if e.d.harv:
		poly = PackedVector2Array([p + Vector2(0, -s - 1), p + Vector2(s + 1, 0), p + Vector2(0, s + 1), p + Vector2(-s - 1, 0)])
	elif e.d.air:
		poly = PackedVector2Array([p + Vector2(0, -s - 1), p + Vector2(s + 0.5, s * 0.8), p + Vector2(-s - 0.5, s * 0.8)])
	elif e.d.get("cat", "") == "inf":
		c.draw_circle(p, s * 0.82 + 1.0, dark)
		c.draw_circle(p, s * 0.82, fill)
		if e.sel: c.draw_arc(p, s * 0.82 + 1.6, 0, TAU, 16, Color(1, 1, 1, a), 1.4, true)
		return
	else:
		poly = PackedVector2Array([p + Vector2(-s, -s), p + Vector2(s, -s), p + Vector2(s, s), p + Vector2(-s, s)])
	var out := poly.duplicate(); out.append(poly[0])
	c.draw_polyline(out, dark, 2.6)
	c.draw_colored_polygon(poly, fill)
	if e.sel: c.draw_polyline(out, Color(1, 1, 1, a), 1.4)

func _badge(c: Control, U, rc: Rect2, s: Dictionary, a: float) -> void:
	var on: bool = s.on
	var edge := Color(1, 1, 1, a) if on else Color(team_col(0), a)
	c.draw_rect(rc.grow(1), Color(0, 0, 0, 0.55 * a))
	c.draw_rect(rc, Color(0.23, 0.07, 0.06, 0.94 * a) if on else Color(0.07, 0.08, 0.07, 0.92 * a))
	c.draw_rect(rc, edge, false, 1.6 if on else 1.1)
	c.draw_string(U.f_disp7, rc.position + Vector2(5, 15), str(s.n), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, a))
	var cnt := "×%d" % s.st.n
	var tw: float = U.f_disp7.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	c.draw_string(U.f_disp7, rc.position + Vector2(rc.size.x - tw - 3, 10), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.86, 0.81, 0.7, a))
	if s.st.hit: c.draw_string(U.f_disp7, rc.position + Vector2(16, 13), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.3, 0.26, a))
	var hb := Rect2(rc.position + Vector2(3, rc.size.y - 4), Vector2(rc.size.x - 6, 2))
	c.draw_rect(hb, Color(0.2, 0.2, 0.2, a))
	var hp: float = s.st.hp
	c.draw_rect(Rect2(hb.position, Vector2(hb.size.x * hp, 2)), Color(Color("8fcf7a") if hp > .6 else (Color("f0c23f") if hp > .3 else Color("ff5a52")), a))

## A line from the squad to where most of it is heading: red to an enemy it attacks, pale to a place it moves to.
func _heading(c: Control, S, V, s: Dictionary, a: float) -> void:
	var tgt = null; var dst := Vector2(); var nd := 0
	var by := {}
	for e in s.mem:
		if e.target != null and e.target.alive and e.target.team != 0 and e.order == "attack":
			by[e.target.id] = by.get(e.target.id, 0) + 1
			if tgt == null or by[e.target.id] > by[tgt.id]: tgt = e.target
		elif e.dest != null and (e.moving or e.path.size() > 0):
			dst += Vector2(e.dest.x * T + 16, e.dest.y * T + 16); nd += 1
	var to := Vector2(); var col: Color
	if tgt != null and (tgt.kind == "b" or S.visible_to_player(tgt)) and by[tgt.id] * 2 >= s.mem.size():
		var q: Vector3 = V.w2s(tgt.x, tgt.y, S.h_at(tgt.x, tgt.y))
		if q.z < 0: return
		to = Vector2(q.x, q.y); col = Color(1, 0.42, 0.3, 0.9 * a)
	elif nd * 2 >= s.mem.size() and nd > 0:
		dst /= nd
		var q: Vector3 = V.w2s(dst.x, dst.y, S.h_at(dst.x, dst.y))
		if q.z < 0: return
		to = Vector2(q.x, q.y); col = Color(0.95, 0.9, 0.78, 0.75 * a)
	else: return
	var d: Vector2 = to - s.c
	if d.length() < s.r + 10: return
	var from: Vector2 = s.c + d.normalized() * s.r
	var tip: Vector2 = to - d.normalized() * 6
	c.draw_dashed_line(from, tip, col, 1.6, 5.0)
	var n := d.normalized(); var pp := Vector2(-n.y, n.x)
	c.draw_colored_polygon(PackedVector2Array([to, tip - n * 3 + pp * 4, tip - n * 3 - pp * 4]), col)

func _dashed_ring(c: Control, p: Vector2, r: float, col: Color) -> void:
	var n := 20
	for i in n:
		if i % 2: continue
		c.draw_arc(p, r, TAU * i / n, TAU * (i + 1) / n, 4, col, 1.1, true)

## Pulsing red rings: something of the player's is being hit there.
func _alert(c: Control, p: Vector2, r: float, t: float, a: float) -> void:
	var f := fmod(t * 1.2, 1.0)
	c.draw_circle(p, r + 4, Color(1, 0.23, 0.19, 0.08 * a))
	c.draw_arc(p, r + 4 + f * 14, 0, TAU, 32, Color(1, 0.23, 0.19, (1 - f) * 0.7 * a), 1.4, true)

func _star(c: Control, p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2 + PI * i / 5
		pts.append(p + Vector2(cos(ang), sin(ang)) * (r if i % 2 == 0 else r * 0.45))
	c.draw_colored_polygon(pts, col)
