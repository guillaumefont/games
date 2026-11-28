## Radial touch controls (Guillaume 2026-11-28: "radial controls on the bottom right corner", "use sectors", "ring menus
## around structures", "keep the structure visible in the middle, 8 sectors max").
##   Wheel: a quarter-circle of sectors in the action thumb's corner (bottom right, bottom left when left-handed).
##     hub: ATTACK while units are picked (STOP for an unarmed pick), else YARD (READY when a structure waits).
##     inner ring: the squads, ALL and 1 to 5, each with its health arc (NEW is a plate over the wheel).
##     outer ring, the widest sectors (Guillaume: too many buttons sat near the corner, where sectors are smallest): the
##     picked units' orders. The producers have their own shortcut column on the other side (`docked` half rings).
##   Ring: the one menu for structures (Guillaume 2026-11-28: "keep only the half ring", "scrollable with big sectors"):
##     a big half ring beside the producer shortcut column. A shortcut opens its building's (`docked`, selection and map
##     untouched); a tap on one of your structures opens that structure's, with its orders (Rally, Upgrade, Repair, Loop,
##     Muster, Sell). Everything is on one strip that turns like a dial; a READY structure leads it and drags out of it.
extends RefCounted

const Radial := preload("res://scripts/radial.gd")

const BR := Color("d9a441")
const LINE := Color("5d5236")
const RED := Color("e5483f")
const SAND := Color("a99c78")
const KH := Color("e8dcb8")
const LIT_FG := Color("ffd8d2")
const PL0 := Color(0.125, 0.15, 0.1, 0.94)
const PL1 := Color(0.05, 0.063, 0.04, 0.94)
const ON0 := Color(0.29, 0.106, 0.086, 0.95)
const ON1 := Color(0.14, 0.063, 0.05, 0.95)
const HOLD := 0.55

## Outline of an annulus sector from angle a0 to a1 (radians, a0 < a1), with a gap of `gap` UI units between sectors.
static func wedge(c: Vector2, r0: float, r1: float, a0: float, a1: float, gap := 3.0) -> PackedVector2Array:
	var g1 := gap / 2 / r1; var g0 := gap / 2 / maxf(r0, 1.0) if r0 > 0 else 0.0
	var n := maxi(3, int((a1 - a0) / 0.06))
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0 + g1, a1 - g1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	if r0 <= 0:
		pts.append(c)
	else:
		for i in n + 1:
			var a := lerpf(a1 - g0, a0 + g0, float(i) / n)
			pts.append(c + Vector2(cos(a), sin(a)) * r0)
	return pts

static func arc_pts(c: Vector2, r: float, a0: float, a1: float) -> PackedVector2Array:
	var n := maxi(2, int(absf(a1 - a0) / 0.05))
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

## A sector plate: olive steel (dark red while lit), a hairline edge, a brass lip on its outer arc.
static func plate(ci: CanvasItem, c: Vector2, r0: float, r1: float, a0: float, a1: float, lit: bool, edge := Color(0, 0, 0, 0), alpha := 1.0) -> void:
	var pts := wedge(c, r0, r1, a0, a1)
	var cols := PackedColorArray()
	var half := (pts.size() - 1) / 2 if r0 > 0 else pts.size() - 1
	for i in pts.size():
		var outer := i < half + 1 if r0 > 0 else i < pts.size() - 1
		var col: Color = (ON0 if outer else ON1) if lit else (PL0 if outer else PL1)
		col.a *= alpha
		cols.append(col)
	ci.draw_polygon(pts, cols)
	var line: Color = edge if edge.a > 0 else (RED if lit else LINE)
	var closed := pts.duplicate(); closed.append(pts[0])
	ci.draw_polyline(closed, Color(line, line.a * alpha), 1.5 if edge.a == 0 else 2.5, true)
	var g := 3.0 / r1
	ci.draw_polyline(arc_pts(c, r1 - 2.5, a0 + g * 1.5, a1 - g * 1.5), Color(RED if lit else BR, 0.7 * alpha), 1.5, true)

static func mid(c: Vector2, r0: float, r1: float, a0: float, a1: float) -> Vector2:
	var a := (a0 + a1) / 2; var r := (r0 + r1) / 2
	return c + Vector2(cos(a), sin(a)) * r

static func text(ci: CanvasItem, f: Font, p: Vector2, s: String, size: int, col: Color, w := 90.0) -> void:
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var fs := size
	while tw > w and fs > 7:
		fs -= 1; tw = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, Vector2(p.x - w / 2, p.y), s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

## The polar hit test shared by both: which sector of `secs` holds point p (or null).
static func hit(secs: Array, c: Vector2, p: Vector2):
	var d := p - c; var r := d.length()
	var a := fposmod(d.angle(), TAU)
	for s in secs:
		if r < s.r0 or r > s.r1: continue
		if s.r0 <= 0 and r <= s.r1:
			var a0h: float = fposmod(s.a0, TAU); var a1h: float = a0h + (s.a1 - s.a0)
			if (a >= a0h and a <= a1h) or (a + TAU >= a0h and a + TAU <= a1h): return s
			continue
		var a0: float = fposmod(s.a0, TAU); var a1: float = a0 + (s.a1 - s.a0)
		if (a >= a0 and a <= a1) or (a + TAU >= a0 and a + TAU <= a1): return s
	return null

# =====================================================================================================================
class Wheel extends Control:
	var ui
	const R_HUB := 70.0
	const R1 := 76.0     # inner ring: the squads
	const R2 := 150.0
	const R3 := 156.0    # outer ring, the widest sectors: the orders, or the producers
	const R4 := 228.0
	var secs: Array = []
	var press = null
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	## The wheel's corner, in its own coordinates.
	func corner() -> Vector2:
		return Vector2(0.0 if ui.left_hand else size.x, size.y)

	## Angle for a position f (0..1) along the quarter circle: 0 lies along the bottom edge, 1 straight up.
	func ang(f: float) -> float:
		return (PI + f * PI / 2) if not ui.left_hand else (TAU - f * PI / 2)

	func _span(i: int, n: int) -> Array:
		var a := ang(float(i) / n); var b := ang(float(i + 1) / n)
		return [minf(a, b), maxf(a, b)]

	func _has_point(p: Vector2) -> bool:
		return visible and p.distance_to(corner()) <= R4 + 2

	func _process(dt: float) -> void:
		t += dt
		if t >= 0.1:
			t = 0.0; rebuild(); queue_redraw()

	func rebuild() -> void:
		var m = ui.main
		secs = []
		if m == null or m.S.teams.is_empty(): return
		var us: Array = m._my_units()
		var B: Dictionary = ui.btn
		# hub
		var hub := {"r0": 0.0, "r1": R_HUB, "ring": 0}
		var hs := _span(0, 1); hub.a0 = hs[0]; hub.a1 = hs[1]
		if not us.is_empty():
			if B.amove.visible: hub.merge({"key": "amove", "g": "atk", "cap": "ATTACK", "lit": m.amove})
			else: hub.merge({"key": "stop", "g": "stop", "cap": "STOP", "lit": false})
		else:
			var q: Dictionary = m.S.teams[0].prod.bld
			var has_yard: bool = m.S.count(0, "hq") > 0 or q.cur != ""
			var sb: Ent = m.S.sel[0] if (m.S.sel.size() == 1 and m.S.sel[0].kind == "b" and m.S.sel[0].team == 0) else null
			hub.merge({"key": "yard", "g": "bld_crane", "cap": "READY" if q.ready else "YARD", "lit": (sb != null and sb.type == "hq") or ui.ring.docked == "hq",
				"ready": q.ready, "dim": not has_yard, "prog": q.prog if (q.cur != "" and not q.ready) else -1.0})
		secs.append(hub)
		# outer ring: orders or producers
		var mids: Array = []
		if not us.is_empty():
			for k in ["stop", "hold", "nofire", "scatter", "home", "jump", "strip", "fuse"]:
				if k == hub.key or not B[k].visible: continue
				var cap: String = B[k].cap if B[k].cap != "" else String(B[k].text)
				if k == "stop": cap = "STOP"
				mids.append({"key": k, "g": B[k].glyph, "cap": cap, "lit": B[k].get_meta("on", false), "dim": B[k].modulate.a < 0.9})
		# nothing picked: the producers live in the shortcut column on the other side now
		mids = mids.slice(0, 6)
		for i in mids.size():
			var s: Dictionary = mids[i]; var sp := _span(i, mids.size())
			s.merge({"r0": R3, "r1": R4, "a0": sp[0], "a1": sp[1], "ring": 1}); secs.append(s)
		# inner ring: the squads
		var outs: Array = []
		for k in ["sq_all"] + range(1, 6).map(func(n): return "sq%d" % n):   # NEW sits on the plates over the wheel
			var c = B[k]
			if not c.visible: continue
			outs.append({"key": k, "n": c.key, "st": c.st, "lit": c.lit})
		for i in outs.size():
			var s: Dictionary = outs[i]; var sp := _span(i, outs.size())
			s.merge({"r0": R1, "r1": R2, "a0": sp[0], "a1": sp[1], "ring": 2}); secs.append(s)

	## Global rect around a sector (for the tutorial pointer), or null.
	func rect_of(key: String):
		if not is_visible_in_tree(): return null
		for s in secs:
			if s.key == key:
				var p: Vector2 = Radial.mid(corner(), s.r0, s.r1, s.a0, s.a1) if s.r0 > 0 else corner() + Vector2(cos((s.a0 + s.a1) / 2), sin((s.a0 + s.a1) / 2)) * s.r1 * 0.55
				var gp: Vector2 = get_global_transform() * p
				return Rect2(gp - Vector2(28, 28), Vector2(56, 56))
		return null

	func _gui_input(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton) or ev.button_index != MOUSE_BUTTON_LEFT: return
		accept_event()
		var s = Radial.hit(secs, corner(), ev.position)
		if ev.pressed:
			press = s.key if s != null else null; queue_redraw(); return
		var k = press; press = null; queue_redraw()
		if s == null or k == null or s.key != k: return
		_act(s)

	func _act(s: Dictionary) -> void:
		var m = ui.main; var k: String = s.key
		if k == "yard": ui.ring.toggle_dock("hq"); m.sfx("click")
		elif k.begins_with("p:"): m.prod_chip_tap(s.bt)
		elif k.begins_with("sq"): m.squad_tap(s.n)
		else:
			m.cmd_btn(k)
			if k != "amove" and k != "hold" and k != "nofire" and k != "jump" and k != "strip": m.sfx("click")
		m.buzz(8)
		rebuild(); queue_redraw()

	func _draw() -> void:
		if secs.is_empty(): return
		var c := corner()
		# a soft shade behind the wheel so it reads over any ground
		for i in 6:
			var r := R4 + 22 - i * 6
			var sp := _span(0, 1)
			draw_colored_polygon(Radial.wedge(c, 0, r, sp[0], sp[1], 0), Color(0, 0, 0, 0.07))
		for s in secs:
			var lit: bool = s.get("lit", false)
			var down: bool = press != null and press == s.key
			var al := 0.45 if s.get("dim", false) else 1.0
			var edge := Color(BR, 0.95) if s.get("ready", false) else Color(0, 0, 0, 0)
			Radial.plate(self, c, s.r0, s.r1, s.a0, s.a1, lit or down, edge)
			var fg: Color = LIT_FG if lit else KH
			if s.ring == 0:
				var p := c + Vector2(cos((s.a0 + s.a1) / 2), sin((s.a0 + s.a1) / 2)) * R_HUB * 0.52
				UI.glyph(self, s.g, Rect2(p - Vector2(13, 20), Vector2(26, 26)), Color(LIT_FG if lit else (UI.C_AUR if s.get("ready", false) else BR), al))
				Radial.text(self, ui.f_disp7, p + Vector2(0, 22), s.cap, 13, Color(fg, al), 64)
				if s.get("prog", -1.0) >= 0:
					draw_polyline(Radial.arc_pts(c, R_HUB - 4, s.a0 + 0.04, s.a0 + 0.04 + (s.a1 - s.a0 - 0.08) * clampf(s.prog, 0, 1)), UI.C_AUR, 3.0, true)
				if s.get("ready", false) and int(Time.get_ticks_msec() / 500) % 2 == 0:
					draw_polyline(Radial.arc_pts(c, R_HUB - 4, s.a0 + 0.04, s.a1 - 0.04), RED, 3.0, true)
			elif s.ring == 1:
				var p := Radial.mid(c, s.r0, s.r1, s.a0, s.a1)
				if s.has("bt"):
					var it = ui.items.get("bld:" + s.bt)
					if it and it.icon: draw_texture_rect(it.icon, Rect2(p - Vector2(22, 24), Vector2(44, 35)), false)
					else: UI.glyph(self, "bld", Rect2(p - Vector2(10, 18), Vector2(20, 20)), BR)
					Radial.text(self, ui.f_disp, p + Vector2(0, 22), s.cap, 10, Color(fg if lit else SAND), minf((s.r0 + s.r1) / 2 * (s.a1 - s.a0) * 0.95, 66.0))
					if s.prog >= 0:
						draw_polyline(Radial.arc_pts(c, s.r0 + 5, s.a0 + 0.05, s.a0 + 0.05 + (s.a1 - s.a0 - 0.1) * clampf(s.prog, 0, 1)), UI.C_AUR, 3.0, true)
					if s.n > 1:
						var br := Rect2(p + Vector2(14, -28), Vector2(20, 14))
						draw_style_box(UI.cut(BR, Color(0, 0, 0, 0), 0, 4, 0), br)
						draw_string(ui.f_disp7, br.position + Vector2(0, 11.5), str(s.n), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 11, Color("1a1408"))
					if s.loop: UI.glyph(self, "loop", Rect2(p + Vector2(-34, -28), Vector2(13, 13)), Color("8fcf7a"))
				else:
					var aw: float = minf((s.r0 + s.r1) / 2 * (s.a1 - s.a0) * 0.95, 70.0)
					UI.glyph(self, s.g, Rect2(p - Vector2(9, 16), Vector2(18, 18)), Color(LIT_FG if lit else BR, al))
					Radial.text(self, ui.f_disp, p + Vector2(0, 13), s.cap, 9, Color(fg if lit else SAND, al), aw)
			else:
				var p := Radial.mid(c, s.r0, s.r1, s.a0, s.a1)
				var st: Dictionary = s.st
				if s.n == 0:
					UI.glyph(self, "all", Rect2(p - Vector2(9, 19), Vector2(18, 18)), fg)
					Radial.text(self, ui.f_disp7, p + Vector2(0, 11), "ALL", 12, fg, 50)
					Radial.text(self, ui.f_body, p + Vector2(0, 23), "%d" % st.get("n", 0), 10, SAND, 50)
				elif s.n == -1:
					Radial.text(self, ui.f_disp7, p + Vector2(0, -1), "NEW", 13, LIT_FG if lit else BR, 50)
					Radial.text(self, ui.f_disp, p + Vector2(0, 14), "×%d" % st.get("n", 0), 11, LIT_FG if lit else BR, 50)
				else:
					Radial.text(self, ui.f_disp7, p + Vector2(0, 5), str(s.n), 20, fg, 40)
					Radial.text(self, ui.f_disp, p + Vector2(0, 20), "×%d" % st.get("n", 0), 10, SAND, 40)
					if st.get("hit", false): draw_string(ui.f_disp7, p + Vector2(10, -10), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ff5a52"))
					elif st.get("idle", false): draw_circle(p + Vector2(14, -14), 2.5, SAND)
					var hp: float = st.get("hp", 0.0)
					var a0: float = s.a0 + 0.05; var a1: float = s.a1 - 0.05
					draw_polyline(Radial.arc_pts(c, s.r0 + 6, a0, a1), Color("2a2f22"), 3.5, true)
					if hp > 0:
						var hc := Color("8fcf7a") if hp > 0.5 else (Color("f0b93f") if hp > 0.25 else Color("ff5a52"))
						# the bar fills from the end nearest the hub's edge, like reading left to right
						draw_polyline(Radial.arc_pts(c, s.r0 + 6, a0, a0 + (a1 - a0) * hp), hc, 3.5, true)

# =====================================================================================================================
class Ring extends Control:
	var ui
	const W := 70.0
	var secs: Array = []
	var for_id := -1     # the structure it was opened for
	var docked := ""     # a producer shortcut is open: that building type's menu (else: the selected structure's)
	var a_start := 0.0
	# the half ring scrolls like a dial (Guillaume 2026-11-28: "scrollable with big sectors"): every item on one strip,
	# `vis` big sectors in view, `scroll` the strip's position in sectors (fractional while a finger turns it)
	var dock_list: Array = []
	var vis := 4
	var scroll := 0.0
	var scroll_to := 0.0
	var scrolling := false
	var press_ang := 0.0
	var scroll0 := 0.0
	var c := Vector2()
	var r0 := 50.0
	var r1 := 120.0
	var bld: Ent = null
	var title := ""
	var press = null
	var press_at := Vector2()
	var hold_t := -1.0
	var did := false
	var dragging := false
	var t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _has_point(p: Vector2) -> bool:
		if dragging: return true
		if not visible or bld == null or secs.is_empty(): return false
		return scrolling or press != null or Radial.hit(secs, c, p) != null

	## The structure the ring is for: one of yours, alone in the selection, while nothing is being placed.
	func target() -> Ent:
		var m = ui.main
		if m == null or m.S.teams.is_empty() or m.paused: return null
		if m.placing != null or m.rally_aim: return null
		if docked != "":
			for e in m.S.ents:
				if e.alive and e.team == 0 and e.kind == "b" and e.type == docked: return e
			docked = ""
			return null
		if m.V.radar_k() >= 0.5: return null
		if m.S.sel.size() != 1: return null
		var e: Ent = m.S.sel[0]
		return e if (e.alive and e.kind == "b" and e.team == 0) else null

	func _process(dt: float) -> void:
		var m = ui.main
		if hold_t >= 0 and press != null:
			hold_t += dt
			if hold_t > HOLD and not did:
				did = true
				var s = _find(press)
				if s != null and s.kind == "item":
					if s.cat == "bld": m.cancel_item(s.cat, s.type)
					else: m.queue_many(s.cat, s.type, 5)
					m.buzz(20)
		if dragging: return
		var b := target()
		if b == null:
			if bld != null: bld = null; secs = []; queue_redraw()
			for_id = -1
			return
		var key := (-2 - b.id) if docked != "" else b.id
		if key != for_id:   # another structure: the strip starts from its top
			for_id = key; scroll = 0.0; scroll_to = 0.0; scrolling = false
		bld = b
		_dock()
		t += dt
		if t > 0.1 or secs.is_empty():
			t = 0.0; rebuild()
		else:
			if not scrolling: scroll = lerpf(scroll, scroll_to, 1.0 - exp(-dt * 14.0))
			_layout()
		queue_redraw()

	## Where the half ring sits: beside the shortcut column, in the middle of the screen, opening towards the map.
	func _dock() -> void:
		r1 = minf(300.0, (size.y - 72.0) / 2.0); r0 = r1 * 0.34
		var cc := Vector2()
		var right: bool = not ui.prod_col_left()
		var cw: float = ui.chip_box.size.x + 8.0   # beside the column, never over it
		cc.x = size.x - cw if right else cw
		cc.y = clampf(size.y / 2.0, 36 + r1, size.y - r1)   # at the side's middle height (Guillaume: "keep it on the middle height")
		c = cc
		a_start = PI / 2 if right else -PI / 2

	## Open (or, for the one open, close) the shortcut menu of a building type.
	func toggle_dock(bt: String) -> void:
		docked = "" if docked == bt else bt
		for_id = -1; secs = []; bld = null
		scroll = 0.0; scroll_to = 0.0; scrolling = false; press = null
		queue_redraw()

	## The strip for the structure (or the shortcut's building type), laid out where it stands now.
	func rebuild() -> void:
		var m = ui.main; var S = m.S
		var b := bld
		secs = []
		if b == null: return
		var bt: String = b.type
		title = String(b.d.name).replace(" ×4", "").to_upper()
		var items: Array = []
		if bt == "hq":
			for t2 in D.CATS.bld:
				if S.avail(0, t2) and ui.items.has("bld:" + t2): items.append({"kind": "item", "cat": "bld", "type": t2})
		else:
			for cc in m.prod_cats(bt):
				var gi: Array = []
				for t2 in D.CATS[cc]:
					if S.avail(0, t2) and S.unit_from(0, t2) == bt and ui.items.has(cc + ":" + t2): gi.append({"kind": "item", "cat": cc, "type": t2})
				items += gi
		var orders: Array = []
		if docked != "":
			if not m.prod_cats(bt).is_empty(): orders.append({"kind": "order", "key": "loop"})
		else:
			for k in ["rally", "upgrade", "repair", "loop", "muster", "sell"]:
				if ui.btn[k].visible: orders.append({"kind": "order", "key": k})
		var ready = null
		if bt == "hq":
			var q: Dictionary = S.teams[0].prod.bld
			if q.ready and q.cur != "": ready = {"kind": "item", "cat": "bld", "type": q.cur}
		# one strip: a READY structure first, what can be made now, the orders, then what is still locked
		var free: Array = []; var locked: Array = []
		for it in items:
			if ready != null and it.type == ready.type: continue
			if ui.items[it.cat + ":" + it.type].locked: locked.append(it)
			else: free.append(it)
		dock_list = ([ready] if ready != null else []) + free + orders + locked
		for s2 in dock_list:
			if s2.kind == "item": s2.key = "i:" + s2.cat + ":" + s2.type
		vis = clampi(dock_list.size(), 3, 4)
		if not _wraps():
			scroll_to = clampf(scroll_to, 0.0, _max_scroll())
			if not scrolling: scroll = clampf(scroll, -0.5, _max_scroll() + 0.5)
		_layout()
		return

	func _max_scroll() -> float:
		return maxf(0.0, float(dock_list.size() - vis))

	## More than fits: the strip is an endless loop (Guillaume 2026-11-28: "make it an infinite wheel ... you can scroll
	## back and forth"), the last sector followed by the first again.
	func _wraps() -> bool:
		return dock_list.size() > vis

	## The half ring's sectors where the strip stands now: sector i sits at position i - scroll, from the top of the half
	## (0) to its bottom (vis); one partly turned out of view is cut at the edge and fades (`vf`, its share in view).
	func _layout() -> void:
		secs = []
		var n := dock_list.size()
		if n == 0: return
		var span := PI / vis
		var dir := -1.0 if a_start > 0 else 1.0   # right column: the half opens to the left, top to bottom anticlockwise
		var off := -(vis - n) / 2.0 if n < vis else 0.0
		var wrap := _wraps()
		for i in n:
			var p0: float = i - scroll - off
			if wrap:
				p0 = fposmod(p0, float(n))
				if p0 > n - 1: p0 -= n   # the one turning in at the top
			var lo := maxf(p0, 0.0); var hi := minf(p0 + 1.0, float(vis))
			if hi - lo < 0.04: continue
			var s: Dictionary = dock_list[i]
			var x0 := -PI / 2 + dir * lo * span; var x1 := -PI / 2 + dir * hi * span
			s.merge({"r0": r0, "r1": r1, "a0": minf(x0, x1), "a1": maxf(x0, x1), "vf": hi - lo}, true)
			secs.append(s)

	func _find(key):
		for s in secs:
			if s.key == key: return s
		return null

	## Global rect around the sector in view that holds build item "cat:type", or null.
	func rect_of_item(item: String):
		if not is_visible_in_tree() or secs.is_empty(): return null
		for s in secs:
			var hitp := false
			if s.kind == "item" and s.cat + ":" + s.type == item and s.get("vf", 1.0) > 0.6: hitp = true
			if hitp:
				var gp: Vector2 = get_global_transform() * Radial.mid(c, s.r0, s.r1, s.a0, s.a1)
				return Rect2(gp - Vector2(28, 28), Vector2(56, 56))
		return null

	func _gui_input(ev: InputEvent) -> void:
		var m = ui.main
		if ev is InputEventMouseButton:
			if ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
				var s0 = Radial.hit(secs, c, ev.position)
				if s0 != null and s0.kind == "item": m.cancel_item(s0.cat, s0.type)
				accept_event(); return
			if ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				scroll_to = roundf(scroll_to) + (1.0 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0)
				if not _wraps(): scroll_to = clampf(scroll_to, 0.0, _max_scroll())
				accept_event(); return
			if ev.button_index != MOUSE_BUTTON_LEFT: return
			accept_event()
			if ev.pressed:
				var s = Radial.hit(secs, c, ev.position)
				press = s.key if s != null else null; press_at = ev.position; hold_t = 0.0; did = false; dragging = false
				press_ang = (ev.position - c).angle(); scroll0 = scroll; scrolling = false
				queue_redraw(); return
			if scrolling:   # let go of the dial: it settles on the nearest whole sector
				scrolling = false; press = null; hold_t = -1.0
				scroll_to = roundf(scroll) if _wraps() else clampf(roundf(scroll), 0.0, _max_scroll())
				queue_redraw(); return
			if dragging:
				dragging = false; press = null; hold_t = -1.0
				m.drag_build_end(get_global_transform() * ev.position); return
			var k = press; press = null; hold_t = -1.0
			var s = Radial.hit(secs, c, ev.position)
			if did or k == null or s == null or s.key != k: queue_redraw(); return
			_act(s, ev.position)
		elif ev is InputEventMouseMotion and press != null:
			accept_event()
			if dragging:
				m.drag_build_move(get_global_transform() * ev.position); return
			var s = _find(press)
			var rt := ""
			if s != null and s.kind == "item" and s.cat == "bld" and ui.items[s.cat + ":" + s.type].is_ready: rt = s.type
			# a READY sector drags its structure onto the map, whichever way the finger goes; elsewhere a drag along the arc
			# turns the dial
			if rt != "" and not scrolling and ev.position.distance_to(press_at) > 10:
				dragging = true; did = true; hold_t = -1.0
				m.drag_build_start(rt, get_global_transform() * ev.position)
				return
			var da := wrapf((ev.position - c).angle() - press_ang, -PI, PI)
			var along: float = absf(da) * press_at.distance_to(c)
			var out: float = absf(ev.position.distance_to(c) - press_at.distance_to(c))
			if scrolling or (along > 12.0 and along > out and _max_scroll() > 0):
				scrolling = true; did = true; hold_t = -1.0
				var dir := -1.0 if a_start > 0 else 1.0
				var sc: float = scroll0 - dir * da / (PI / vis)
				var mx := _max_scroll()
				if _wraps(): pass      # no ends: it keeps turning
				elif sc < 0: sc *= 0.35   # past either end it gives a little, then springs back
				elif sc > mx: sc = mx + (sc - mx) * 0.35
				scroll = sc; _layout(); queue_redraw()
				return
			if ev.position.distance_to(press_at) > 14:
				hold_t = -1.0
			return

	func _act(s: Dictionary, p: Vector2) -> void:
		var m = ui.main
		match s.kind:
			"item":
				var it = ui.items[s.cat + ":" + s.type]
				if (it.active or it.n > 0) and not it.is_ready and p.distance_to(_badge_at(s)) < 14: m.cancel_item(s.cat, s.type)
				else: m.click_item(s.cat, s.type)
			"order":
				if docked != "" and s.key == "loop": m.toggle_loop(docked)
				else: m.cmd_btn(s.key)
		m.buzz(8)
		rebuild(); queue_redraw()

	## Where an item sector's cancel badge sits (near its outer edge, clockwise end).
	func _badge_at(s: Dictionary) -> Vector2:
		var a: float = s.a1 - (s.a1 - s.a0) * 0.2
		return c + Vector2(cos(a), sin(a)) * (s.r1 - 13)

	func _draw() -> void:
		if bld == null or secs.is_empty() or dragging: return
		var k := 1.5   # big sectors: the plates' contents half as large again
		for s in secs:
			var down: bool = press != null and press == s.key and not scrolling
			var p := Radial.mid(c, s.r0, s.r1, s.a0, s.a1)
			var vf: float = s.get("vf", 1.0)
			var pa := 0.55 + 0.45 * vf                     # a sector turning out of view fades
			var ca := clampf((vf - 0.45) / 0.45, 0.0, 1.0)  # and its words go before it is cut
			match s.kind:
				"item":
					var it = ui.items[s.cat + ":" + s.type]
					var d: Dictionary = D.def_of(s.type)
					var al := 0.42 if it.locked else 1.0
					var edge := Color(BR, 0.95) if it.is_ready else (Color(BR, 0.7) if it.active else Color(0, 0, 0, 0))
					Radial.plate(self, c, s.r0, s.r1, s.a0, s.a1, down, edge, pa)
					if ca <= 0.0: continue
					al *= ca
					# a half ring's sectors are big: the same layout, half as large again
					if it.icon: draw_texture_rect(it.icon, Rect2(p - Vector2(20, 26) * k, Vector2(40, 32) * k), false, Color(1, 1, 1, al))
					Radial.text(self, ui.f_body6, p + Vector2(0, 14) * k, String(d.name).replace(" ×4", ""), int(10 * k), Color(KH, al), 64 * k)
					if it.is_ready:
						if int(Time.get_ticks_msec() / 500) % 2 == 0 or down: Radial.text(self, ui.f_disp7, p + Vector2(0, 26) * k, "READY", int(11 * k), Color("f0b93f", ca), 60 * k)
						else: Radial.text(self, ui.f_disp7, p + Vector2(0, 26) * k, "DRAG OUT", int(9 * k), Color(RED.lightened(0.3), ca), 60 * k)
					elif it.locked:
						UI.glyph(self, "lock", Rect2(p + Vector2(-5, 17) * k, Vector2(10, 11) * k), Color("8b8a78", ca))
					else:
						var cs := str(d.cost)
						var fs := int(11 * k)
						var cw: float = ui.f_disp7.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
						UI.glyph(self, "aur", Rect2(p + Vector2(-(cw + 11 * k) / 2, 18 * k), Vector2(7, 10) * k), Color(UI.C_AUR, ca))
						draw_string(ui.f_disp7, p + Vector2(-(cw + 11 * k) / 2 + 11 * k, 27 * k), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.C_AUR, ca))
					if it.active and not it.is_ready:
						var a0: float = s.a0 + 0.04; var a1: float = s.a1 - 0.04
						draw_polyline(Radial.arc_pts(c, s.r0 + 4, a0, a1), Color(0, 0, 0, 0.7), 4.0, true)
						draw_polyline(Radial.arc_pts(c, s.r0 + 4, a0, a0 + (a1 - a0) * clampf(it.prog, 0.0, 1.0)), UI.C_AUR, 4.0, true)
					if (it.active or it.n > 0) and not it.is_ready and vf > 0.6:
						var bp := _badge_at(s)
						draw_circle(bp, 10, Color(0.1, 0.03, 0.02, 0.92)); draw_arc(bp, 10, 0, TAU, 20, Color(RED, 0.8), 1.5, true)
						if it.n > 1: draw_string(ui.f_disp7, bp + Vector2(-10, 4.5), "×%d" % it.n, HORIZONTAL_ALIGNMENT_CENTER, 20, 10, Color("ffd0cc"))
						else:
							draw_line(bp + Vector2(-4, -4), bp + Vector2(4, 4), Color("ffd0cc"), 2); draw_line(bp + Vector2(4, -4), bp + Vector2(-4, 4), Color("ffd0cc"), 2)
				"order":
					var b: Button = ui.btn[s.key]
					var on: bool = b.get_meta("on", false)
					if docked != "" and s.key == "loop": on = ui.main.S.teams[0].get("loop", {}).get(docked, false)
					var al: float = b.modulate.a if docked == "" else 1.0
					Radial.plate(self, c, s.r0, s.r1, s.a0, s.a1, on or down, Color(0, 0, 0, 0), pa)
					if ca <= 0.0: continue
					al *= ca
					UI.glyph(self, b.glyph, Rect2(p - Vector2(11, 19) * k, Vector2(22, 22) * k), Color(LIT_FG if on else BR, al))
					var cap: String = b.cap if b.cap != "" else String(b.text)
					Radial.text(self, ui.f_disp7, p + Vector2(0, 16) * k, cap, int(10 * k), Color(LIT_FG if on else KH, al), 64 * k)
					if docked != "" and s.key == "loop": Radial.text(self, ui.f_body, p + Vector2(0, 30) * k, "repeat the queue", int(9 * k), Color(SAND, al), 70 * k)
					if s.key == "upgrade" and bld.upg < 0 and docked == "":
						var u: Dictionary = ui.main.S.upg_def(bld)
						if not u.is_empty(): Radial.text(self, ui.f_disp7, p + Vector2(0, 32) * k, str(u.cost), int(10 * k), Color(UI.C_AUR, ca), 60 * k)
		if _max_scroll() > 0: _draw_scrollbar()
		# its name, upright in the open middle
		var dir := -1.0 if a_start > 0 else 1.0
		Radial.text(self, ui.f_wide, c + Vector2(dir * r0 * 0.5, 4), title, 11, KH, r0 * 0.9)

	## Along the half ring's outer edge: a brass thumb for the part of the strip in view, and a chevron at each end that
	## still has more beyond it.
	func _draw_scrollbar() -> void:
		var n := float(dock_list.size())
		var dir := -1.0 if a_start > 0 else 1.0
		var r := r1 + 9.0
		var x0 := -PI / 2 + dir * 0.04; var x1 := -PI / 2 + dir * (PI - 0.04)
		draw_polyline(Radial.arc_pts(c, r, minf(x0, x1), maxf(x0, x1)), Color(LINE, 0.9), 4.0, true)
		var wrap := _wraps()
		var f0: float = fposmod(scroll, n) / n if wrap else clampf(scroll / n, 0.0, 1.0)
		var f1: float = f0 + vis / n if wrap else clampf((scroll + vis) / n, 0.0, 1.0)
		for part in ([[f0, minf(f1, 1.0)], [0.0, f1 - 1.0]] if f1 > 1.0 else [[f0, f1]]):   # a loop: the thumb wraps too
			var t0 := lerpf(x0, x1, part[0]); var t1 := lerpf(x0, x1, part[1])
			if absf(t1 - t0) > 0.005: draw_polyline(Radial.arc_pts(c, r, minf(t0, t1), maxf(t0, t1)), BR, 4.0, true)
		if wrap:   # where the loop starts again: a brass seam before the first sector
			var span := PI / vis
			var ps: float = fposmod(-scroll, n)
			if ps > 0.02 and ps < vis - 0.02:
				var a := -PI / 2 + dir * ps * span
				draw_line(c + Vector2(cos(a), sin(a)) * (r0 + 2), c + Vector2(cos(a), sin(a)) * (r1 + 12), BR, 4.0, true)
		for e in [[0, wrap or scroll > 0.05], [1, wrap or scroll < _max_scroll() - 0.05]]:
			if not e[1]: continue
			var a := -PI / 2 + dir * (0.5 if e[0] == 0 else PI - 0.5)
			var tip := c + Vector2(cos(a), sin(a)) * (r0 * 0.62)   # in the open middle, by the end that has more
			var up := -1.0 if e[0] == 0 else 1.0
			var pts := PackedVector2Array([tip + Vector2(-10, -up * 5), tip + Vector2(0, up * 5), tip + Vector2(10, -up * 5)])
			draw_polyline(pts, Color(BR, 0.9 + 0.1 * sin(Time.get_ticks_msec() / 200.0)), 3.0, true)
