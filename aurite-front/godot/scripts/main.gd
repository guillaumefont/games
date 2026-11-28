extends Node
## Game shell: owns the simulation, the 3D view, the UI and audio; handles input and game flow.

const T := 32
const Cutscenes := preload("res://scripts/cutscenes.gd")  # no class_name: an installed shell would not know a new global class
const CutscenePlayer := preload("res://scripts/cutscene.gd")
const Tutor := preload("res://scripts/tutorial.gd")   # in-campaign tutorial: unit cards, lessons, drills
const Squads := preload("res://scripts/squads.gd")  # squads on the bottom strip
const GFX := preload("res://scripts/gfx.gd")    # graphics level: Low, Medium, High
const Radar := preload("res://scripts/radar.gd")
const Radial := preload("res://scripts/radial.gd")   # the corner wheel and the structure rings  # radar mode: the whole map as icons when zoomed far out

var S: Sim
var V: View3D
var U: UI
var A: GameAudio
var paused := true
var placing = null  # {type, tx, ty, ldx, ldy}
var amove := false
var sw_aim := false
var rally_aim := false  # RALLY on a structure's ring: the next tap on the map is its rally point
var jump_aim := false   # JUMP pressed: the next tap is where the Jump Troopers land
var diff := "normal"
var sk_fac := "vanguard"
var sk_enemy := "random"
var last_opt := {"fac": "vanguard"}
var cur_tab := "inf"   # sub-tab of a producer that makes several kinds (Landing Zone, Garden)
var ctx_key := ""      # what the side panel shows now: "yard", "b<id>" (a building), "u" (units), "e<id>" (enemy)
var producers: Array = []   # building types with a top-bar chip this match, the Yard ("hq") first
var peek := false      # the panel is open only because the selection needs it (it was hidden)
var brief_i := 0
var camp_id := "ashen"
var icons_for := ""
var headless := false
var cut: CutscenePlayer
var tut: Tutor
## One finger on open ground drags the map (Guillaume's pick, 2026-11-14). A drag that starts on one of your units is
## a swipe: every unit the finger passes over is picked (`paint`, Guillaume 2026-11-28: picking part of the army was
## so hard he played with ALL). No hold gestures: they were hidden, and a hold-drag with units selected gave a formation
## order instead of a box.
const BRUSH := 34.0        # a swipe picks units within this many UI units of the finger's path (a fingertip is ~30)
const BRUSH_RADAR := 18.0  # radar icons sit close together

# input state
var ptrs := {}
var gest = null
var keys := {}
var last_tap := {"id": 0, "t": 0}
var shown_cr := 0.0
var panel_t := 0.0
var rd := Radar.new()            # radar drawing and its squad badges (scripts/radar.gd)
var preview_slots: Array = []
var pv_from = null
var pv_to = null
var sq := Squads.new()           # squads on the bottom strip (scripts/squads.gd)
var sel_src := ""                # "all", "sq" or "new" while the selection is (part of) what a chip picked, else ""
var sel_set: Array = []          # what that chip picked
var sq_full_t := -99.0           # when the "five squads" warning last showed
var obj_t := 0.0                 # seconds the objective box stays open
var obj_gi := -1
const OBJ_SHOW := 8.0
const GHOST_LIFT := 70.0         # a building dragged from the menu shows this far above the finger

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	randomize()
	S = Sim.new(); S.host = self
	GFX.init_level(_load_prefs())
	V = View3D.new(); V.S = S; add_child(V)
	var layer := CanvasLayer.new(); add_child(layer)
	U = UI.new(); U.main = self; layer.add_child(U); U.build()
	A = GameAudio.new(); add_child(A)
	A.voice_on = _load_prefs().get("voice", true); U.btn.voice.text = voice_label()
	cut = CutscenePlayer.new(); cut.main = self; layer.add_child(cut); cut.build(U, V)
	tut = Tutor.new(); tut.main = self; add_child(tut); tut.build()
	U.btn.gfx.text = gfx_label()
	U.set_panel(_load_prefs().get("panel", true))
	V.panel_px = U.panel_px()
	U.left_hand = _load_prefs().get("wheel", "left") == "left"; V.panel_left = U.left_hand; _hand_label()
	show_start()
	if not headless and OS.get_environment("AF_SHOT") == "": _boot_splash()
	if not headless: render_icons("vanguard")
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	if OS.get_environment("AF_SHOT") != "": _autotest(OS.get_environment("AF_SHOT"))

## Phone screens are dense: the 600-unit-tall UI would be only ~3 inches high and its text tiny.
## Scale the canvas so the UI keeps a readable physical size (about 180 UI units per inch), never
## smaller than the desktop layout. AF_DPI overrides the screen DPI for tests.
func _on_resize() -> void:
	var win := get_window()
	var dpi := float(OS.get_environment("AF_DPI")) if OS.get_environment("AF_DPI") != "" else float(DisplayServer.screen_get_dpi())
	var f := 1.0
	if dpi > 0 and (OS.has_feature("mobile") or OS.get_environment("AF_DPI") != ""):
		var h_in := float(min(win.size.x, win.size.y)) / dpi
		f = clampf(600.0 / (h_in * 180.0), 1.0, 1.5)
	if abs(win.content_scale_factor - f) > 0.01:
		win.content_scale_factor = f
	_apply_safe()

## Keep buttons and text clear of rounded screen corners and of a camera hole or notch.
## Uses the display's safe area (it flips sides when the phone turns round), never less than a
## corner margin on phones. AF_SAFE="left,top,right,bottom" (window pixels) simulates a cutout.
var safe_last := Rect2()
var safe_t := 0.0
func _apply_safe() -> void:
	var win := get_window()
	var k := V.ui_scale()
	if k <= 0: return
	var l := 0.0; var t := 0.0; var r := 0.0; var b := 0.0
	var phone := OS.has_feature("mobile") or OS.get_environment("AF_DPI") != ""
	if OS.get_environment("AF_SAFE") != "":
		var a := OS.get_environment("AF_SAFE").split(",")
		l = float(a[0]); t = float(a[1]); r = float(a[2]); b = float(a[3])
	elif OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var wr := Rect2i(win.position, win.size)
		l = sa.position.x - wr.position.x; t = sa.position.y - wr.position.y
		r = wr.end.x - sa.end.x; b = wr.end.y - sa.end.y
	var ins := Rect2(maxf(l, 0) / k, maxf(t, 0) / k, maxf(r, 0) / k, maxf(b, 0) / k)
	if phone:  # rounded corners: a little room on every side, more on the short sides
		ins = Rect2(maxf(ins.position.x, 24), maxf(ins.position.y, 8), maxf(ins.size.x, 24), maxf(ins.size.y, 8))
	if ins == safe_last: return
	safe_last = ins
	U.set_insets(ins.position.x, ins.position.y, ins.size.x, ins.size.y)
	V.panel_px = U.panel_px()

## Hide or show the side panel (build menu and minimap) to free the screen; remembered between games.
func toggle_panel() -> void:
	var open := not U.panel_open
	if peek: open = false   # the panel was only peeking: the button puts it away
	peek = false
	_show_panel(open); sfx("click")
	var p := _load_prefs(); p.panel = open; _save_prefs(p)

func _show_panel(open: bool) -> void:
	if open == U.panel_open: return
	var anchor := V.view_rect().position + Vector2(100, V.view_rect().size.y / 2); var w := V.s2w(anchor.x, anchor.y)
	U.set_panel(open); V.panel_px = U.panel_px(); _fit_dock()
	var w2 := V.s2w(anchor.x, anchor.y)  # keep the map still on screen while the view widens
	V.cam_x += w.x - w2.x; V.cam_y += w.y - w2.y; V.clamp_cam()
	if U.panel_open: refresh_panel(true)
	else: _panel_alert()

func _load_prefs() -> Dictionary:
	if not FileAccess.file_exists("user://prefs.json"): return {}
	var f := FileAccess.open("user://prefs.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}

func _save_prefs(p: Dictionary) -> void:
	var f := FileAccess.open("user://prefs.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(p))

## The kinds of producer this faction has: the Yard, then each building that trains units (Barracks, Landing Zone,
## Workshop, Slipway, Garden...), in the order of the old INF / VEH / AIR tabs.
func _setup_producers() -> void:
	producers = ["hq"]
	for cat in ["inf", "veh", "air"]:
		for t in D.CATS[cat]:
			if not S.avail(0, t): continue
			var bt := S.unit_from(0, t)
			if bt != "" and not producers.has(bt): producers.append(bt)
	U.set_producers(producers)

## Unit categories a building type trains (its sub-tabs), from what this faction can field.
func prod_cats(bt: String) -> Array:
	var out := []
	for cat in ["inf", "veh", "air"]:
		for t in D.CATS[cat]:
			if S.avail(0, t) and S.unit_from(0, t) == bt: out.append(cat); break
	return out

## The top-bar chips: one per kind of producer you own (the Yard while it stands or anything is being built).
func _prod_chips(tm: Dictionary) -> void:
	var sb: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b" and S.sel[0].team == 0) else null
	for bt in U.prod_chips:
		var pc = U.prod_chips[bt]
		pc.cat = ""; pc.type = ""; pc.prog = 0.0; pc.n = 0; pc.is_ready = false
		if bt == "hq":
			var q: Dictionary = tm.prod.bld
			pc.visible = S.count(0, "hq") > 0 or q.cur != ""
			if q.cur != "": pc.cat = "bld"; pc.type = q.cur; pc.prog = q.prog; pc.is_ready = q.ready; pc.n = 1
		else:
			pc.visible = S.count(0, bt) > 0
			for cat in ["inf", "veh", "air"]:
				var q: Dictionary = tm.prod[cat]
				var mine: Array = q.queue.filter(func(t): return S.unit_from(0, t) == bt)
				var cur_mine: bool = q.cur != "" and S.unit_from(0, q.cur) == bt
				if mine.is_empty() and not cur_mine: continue
				pc.n += mine.size() + (1 if cur_mine else 0)
				if pc.type == "": pc.cat = cat; pc.type = q.cur if cur_mine else mine[0]; pc.prog = q.prog if cur_mine else 0.0
		pc.lit = U.ring.docked == bt or (U.ring.docked == "" and sb != null and sb.type == bt)
		pc.loop = tm.get("loop", {}).get(bt, false)
		if pc.visible: pc.queue_redraw()

## A producer chip: place a ready building, else select that kind of building (again: the next one of that kind).
func prod_chip_tap(bt: String) -> void:
	var q: Dictionary = S.teams[0].prod.bld
	if bt == "hq" and q.ready: start_placing(q.cur); sfx("click"); return
	var own := S.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "b" and e.type == bt)
	sfx("click"); buzz(8)
	if own.is_empty():
		S.set_sel([]); return
	var i := 0
	if S.sel.size() == 1 and own.has(S.sel[0]): i = (own.find(S.sel[0]) + 1) % own.size()
	var b: Ent = own[i]
	S.set_sel([b])
	if not V.on_screen(b.x, b.y, -40): V.center_on(b.x, b.y)   # the map moves only to bring an off-screen one into view
	tut.ev("chip", bt)

## Hold a unit button: queue five of it.
func queue_many(cat: String, type: String, k: int) -> void:
	var q: Dictionary = S.teams[0].prod[cat]
	for i in k:
		var before: int = q.queue.size()
		click_item(cat, type)
		if q.queue.size() == before: break
	buzz(20)
	if k >= 5: tut.ev("queue5")

# ---------------- objective ----------------
func _obj_vis() -> void:
	var m: bool = S.mission != null and not S.teams.is_empty()
	U.obj_box.visible = m and obj_t > 0
	U.obj_btn.visible = m and obj_t <= 0

func show_objective() -> void:
	obj_t = OBJ_SHOW; _obj_vis(); sfx("click")

func hide_objective() -> void:
	obj_t = 0; _obj_vis()

# ---------------- squads ----------------
## A chip on the bottom strip: n > 0 a squad, 0 ALL, -1 NEW (units in no squad).
## Tap: select those units; tap again (already selected): centre the camera on them.
func squad_tap(n: int) -> void:
	if S.teams.is_empty(): return
	sq.prune(S)
	var units: Array
	if n > 0: units = sq.members(S, n)
	elif n == 0: units = S.ents.filter(func(e): return Squads.eligible(e) and not e.d.eng)
	else: units = sq.fresh(S)
	units = units.filter(func(e): return e.intun <= 0)
	if units.is_empty():
		toast("No units of yours in the field" if n == 0 else "Every unit is in a squad"); _squad_chips(); return
	var ids := units.map(func(e): return e.id); ids.sort()
	var cur := S.sel.map(func(e): return e.id); cur.sort()
	if ids == cur:
		var c := Vector2()
		for e in units: c += Vector2(e.x, e.y)
		c /= units.size(); V.center_on(c.x, c.y); sfx("click")
	else:
		sel_src = "sq" if n > 0 else ("all" if n == 0 else "new"); sel_set = units
		S.set_sel(units); sfx("click"); buzz(10)
		var on := units.any(func(e): return V.on_screen(e.x, e.y))
		if not on: V.center_on(units[0].x, units[0].y)
	if n > 0: tut.ev("group_recall", n - 1)
	elif n == 0: tut.ev("all_army")

## Radar: a squad badge was tapped. While the selection is made of whole squads (picked on the radar or the strip),
## the tap adds that squad, or drops it if it is already in; otherwise the squad alone is selected. Squads picked
## together this way keep their numbers when they get an order (`_squad_order` skips "multi").
func radar_badge(n: int) -> void:
	var mem := sq.members(S, n).filter(func(e): return e.intun <= 0)
	if mem.is_empty(): return
	var cur: Array = S.sel.filter(func(e): return e.kind == "u") if sel_src in ["sq", "multi"] else []
	if cur.size() and mem.all(func(e): return e.sel): cur = cur.filter(func(e): return not mem.has(e))
	else:
		for e in mem:
			if not cur.has(e): cur.append(e)
	S.set_sel(cur)
	sel_src = "sq" if sq.matching(S, cur) > 0 else ("multi" if cur.size() else ""); sel_set = cur.duplicate()
	sfx("click"); buzz(8); _squad_chips(); update_cmd()

## Radar: a squad badge dragged and let go: that squad alone gets the order there; the selection is left as it was.
func radar_send(n: int, p: Vector2) -> void:
	var mem := sq.members(S, n).filter(func(e): return e.intun <= 0)
	if mem.is_empty() or not _in_view(p): return
	var w := V.s2w(p.x, p.y)
	var hit := pick(p.x, p.y, w.x, w.y)
	if hit != null and hit.team == 0: hit = null
	var keep_src := sel_src; var keep_set := sel_set; var keep := S.sel.duplicate()
	sel_src = "multi"   # the squad keeps its number and nobody else's changes
	command(hit, w.x, w.y, mem)
	sel_src = keep_src; sel_set = keep_set
	if S.sel != keep: S.set_sel(keep.filter(func(e): return e.alive))

## The selection is a squad and fresh units wait: JOIN sends them to it.
func join_btn() -> void:
	var n := sq.matching(S, S.sel)
	var add := sq.fresh(S).filter(func(e): return e.intun <= 0)
	if n == 0 or add.is_empty(): return
	sq.join(S, n, add)
	var m := sq.members(S, n)
	var c := Vector2()
	for e in S.sel: c += Vector2(e.x, e.y)
	c /= max(1, S.sel.size())
	S.group_move(add, c.x, c.y, "move")
	sel_src = "sq"; sel_set = m
	S.set_sel(m.filter(func(e): return e.intun <= 0))
	toast("%d units join squad %d" % [add.size(), n]); sfx("ack"); buzz(12); _squad_chips()

## A type chip: keep only the selected units of that type.
func type_btn(t: String) -> void:
	var keep := S.sel.filter(func(e): return e.kind == "u" and e.type == t)
	if keep.is_empty(): return
	S.set_sel(keep); sfx("click"); buzz(8)

## Units of a selection that just got an order become (or stay) a squad.
func _squad_order(units: Array) -> void:
	if sel_src == "all" or sel_src == "multi": return   # squads picked together on the radar keep their numbers
	var before := sq.matching(S, units)
	var n := sq.formed(S, units)
	if n == -1:
		if S.time - sq_full_t > 20: toast("Five squads already: order two together to merge them", "warn"); sq_full_t = S.time
	elif n > 0 and n != before:
		toast("Squad %d · %d units" % [n, sq.members(S, n).size()]); tut.ev("squad", n - 1)
	_squad_chips()

func _squad_chips() -> void:
	sq.prune(S)
	var lit := sq.matching(S, S.sel)
	for n in range(1, Squads.MAX + 1):
		var b = U.btn["sq%d" % n]
		var st := sq.status(S, n) if sq.find(n) != null else {}
		b.visible = not st.is_empty()
		var all_in := sel_src == "multi" and not st.is_empty() and sq.members(S, n).all(func(e): return e.sel)
		b.set_state(st, lit == n or all_in)
	var all := S.ents.filter(func(e): return Squads.eligible(e) and not e.d.eng)
	U.btn.sq_all.visible = all.size() > 0
	U.btn.sq_all.set_state({"n": all.size()}, sel_src == "all" and S.sel.size() == all.size())
	var fr := sq.fresh(S)
	U.btn.sq_new.visible = fr.size() > 0
	U.btn.sq_new.set_state({"n": fr.size()}, sel_src == "new" and S.sel.size() == fr.size())

## LOOP for a kind of producer: it repeats its queue.
func toggle_loop(bt: String) -> void:
	if prod_cats(bt).is_empty(): return
	var lp: Dictionary = S.teams[0].get("loop", {}); S.teams[0].loop = lp
	lp[bt] = not lp.get(bt, false)
	toast(("Loop on: the %s repeats its queue" if lp[bt] else "Loop off: the %s stops after its queue") % D.BLD[bt].name)
	sfx("click"); refresh_panel(true); update_cmd()

## Structures that send what they make to a rally point.
func _rallies(b: Ent) -> bool:
	return b.d.get("door", false) or b.d.get("yard", false) or b.d.get("pad", false) or b.type == "mast"

## A short vibration on phones to confirm an order or a selection.
func buzz(ms: int) -> void:
	if OS.has_feature("mobile"): Input.vibrate_handheld(ms)

## While the panel is hidden its button lights up when a building is ready to place.
func _panel_alert() -> void:
	return   # no side panel to call out any more: the wheel hub says READY (radial controls, 2026-11-28)
	var ready: bool = not U.panel_open and S.teams.size() > 0 and S.teams[0].prod.bld.ready
	U.set_on(U.btn.panel, ready)
	if not U.panel_open:
		var t := "READY" if ready else "BUILD"
		if U.btn.panel.text != t: U.btn.panel.text = t; U.restyle(U.btn.panel)

# ---------------- host interface for the simulation ----------------
func toast(msg: String, kind := "") -> void:
	U.toast(msg, kind)

func radio(who: String, line: String, warn := false) -> void:
	U.radio(who, line, warn)

## The announcer (scripts/voice.gd): a spoken line for an event of the player's side. x, y: where it happens.
func say(key: String, x = null, y = null) -> void:
	if S == null or headless: return
	A.say(key, Vector2(x, y) if x != null else null)

func sfx(n: String, x = null, y = null) -> void:
	if S == null or paused and n != "click": return
	var big := n == "bigboom" or n == "siren" or n == "alert" or n == "ready"
	var pan := 0.0; var vol := 1.0
	if x != null:
		var p := V.w2s(x, y, S.h_at(x, y))
		var r := V.view_rect()
		var on := p.z > 0 and r.grow(40).has_point(Vector2(p.x, p.y))
		if not on and not big: return
		pan = (p.x / r.size.x * 2 - 1) * .8
		vol = max(.35, 1 - Vector2(p.x / r.size.x - .5, p.y / r.size.y - .5).length() * .9)
		if not on: vol = .4
	if n == "ack" and S.teams.size() and S.teams[0].fac != "vanguard": n = "ack_" + S.teams[0].fac
	A.play(n, pan, vol)

func on_world_changed() -> void:
	V.refresh_decor()

func on_sel_changed() -> void:
	if sel_src != "" and not S.sel.all(func(e): return sel_set.has(e)): sel_src = ""
	update_cmd()

func on_vision() -> void:
	V.upd_fog()

func add_scorch(x: float, y: float, r: float) -> void:
	V.add_scorch(x, y, r)

func end_game(win: bool) -> void:
	var M = S.mission
	var en: String = D.FACS[S.teams[1].fac].name; var me: String = D.FACS[S.teams[0].fac].name
	U.btn.end_eye.text = (("Mission %d · %s %s" % [M.idx + 1, M.title, "complete" if win else "failed"]) if M else (en + " eliminated" if win else me + " base lost")).to_upper()
	U.btn.end_title.text = "VICTORY" if win else "DEFEAT"
	U.set_end_result(win)
	U.btn.end_why.text = S.end_why if (M and not win) else ""
	U.btn.end_why.visible = U.btn.end_why.text != ""
	U.set_debrief(M.get("debrief", {}).get("win" if win else "loss", []) if M else [])
	U.radio_q.clear()
	tut.stop()
	A.say("won" if win else "lost")
	if M and win: camp_save(M.camp, M.idx)
	var last: bool = M != null and M.idx == D.camp(M.camp).missions.size() - 1
	var sequel := _sequel(M.camp) if M else ""
	U.btn.next.visible = M != null and win and (not last or sequel != "")
	U.btn.next.text = ("BEGIN " + D.camp(sequel).name.to_upper()) if (last and sequel != "") else "NEXT MISSION"
	if last and win and sequel != "": toast("Campaign complete. %s is unlocked" % D.camp(sequel).name, "gold")
	U.btn.again.text = ("REPLAY" if win else "RETRY") if M else "PLAY AGAIN"
	A.music_stop()
	U.set_end_stats([["Time", D.fmt(S.time)], ["Aurite mined", Sim._thousands(S.stats.mined)], ["Units trained", S.stats.built], ["Enemies destroyed", S.stats.killed], ["Losses", S.stats.lost]])
	get_tree().create_timer(1.2).timeout.connect(func(): U.show_overlay("end"))
	A.play("ready" if win else "alert")

# ---------------- game flow ----------------
## Progress per campaign: {"ashen": missions won, "vanguard": ...}. The old single-campaign save is ignored.
func _camp_file() -> Dictionary:
	if not FileAccess.file_exists("user://campaigns.json"): return {}
	var f := FileAccess.open("user://campaigns.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

func camp_prog(id: String) -> int:
	return int(_camp_file().get(id, 0))

func camp_save(id: String, i: int) -> void:
	var d := _camp_file()
	d[id] = max(int(d.get(id, 0)), i + 1)
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

## The campaign that follows this one in the story, or "".
func _sequel(id: String) -> String:
	for i in D.CAMPAIGNS.size() - 1:
		if D.CAMPAIGNS[i].id == id: return D.CAMPAIGNS[i + 1].id
	return ""

## A campaign opens once the one before it is finished (unless it is "free").
func camp_open(id: String) -> bool:
	for i in range(1, D.CAMPAIGNS.size()):
		if D.CAMPAIGNS[i].id == id:
			if D.CAMPAIGNS[i].get("free", false): return true   # a side story: open from the start
			var prev: Dictionary = D.CAMPAIGNS[i - 1]
			return camp_open(prev.id) and camp_prog(prev.id) >= prev.missions.size()
	return true

## Opens the campaign screen scrolled to this campaign.
func pick_campaign(id: String) -> void:
	camp_id = id
	show_campaigns()

func _camp_rows() -> Array:
	return D.CAMPAIGNS.map(func(C): return {"C": C, "open": camp_open(C.id), "done": camp_prog(C.id)})

## The splash after the engine's plain boot screen: the title art in the player's story stage, then the menu.
func _boot_splash() -> void:
	U.build_splash(); U.set_stage(menu_stage()); U.show_overlay("splash")
	var o: Control = U.overlays.splash
	await get_tree().create_timer(1.8).timeout
	var tw := create_tween(); tw.tween_property(o, "modulate:a", 0.0, 0.35)
	await tw.finished
	o.modulate.a = 1.0
	if U.overlays.splash.visible: U.show_overlay("start")

## Home-screen icon follows the menu stage (Android: launcher aliases switched by tools/android/IconSwap.java).
var _icon_stage := -1
func set_app_icon(st: int) -> void:
	if st == _icon_stage or OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"): return
	_icon_stage = st
	var sw = JavaClassWrapper.wrap("com.godot.game.IconSwap")
	if sw == null: return
	var ok = sw.apply(Engine.get_singleton("AndroidRuntime").getActivity(), st + 1)
	print("app icon stage ", st + 1, " ", ok)

## Menu art stage from the furthest point of the story the player has reached: grim once campaign III is open,
## cracked once campaign II reaches mission 5, pulpy before.
func menu_stage() -> int:
	if camp_open("choir"): return 2
	return 1 if camp_prog("vanguard") >= Campaign.CRACK else 0

func show_start() -> void:
	tut.stop()
	U.set_stage(menu_stage())
	set_app_icon(menu_stage())
	if not camp_open(camp_id): camp_id = D.CAMPAIGNS[0].id
	# continue where the player is: the furthest open campaign that is not finished
	var cur: Dictionary = D.CAMPAIGNS[0]
	for C in D.CAMPAIGNS:
		if camp_open(C.id): cur = C
		if camp_open(C.id) and camp_prog(C.id) < C.missions.size(): cur = C; break
	var dn := mini(camp_prog(cur.id), cur.missions.size())
	var nxt: String = ("Next: " + cur.missions[dn].title) if dn < cur.missions.size() else "All won: replay any mission"
	U.set_camp_tile(nxt, "%s · %s  ·  %d of %d secured" % [cur.num, cur.name, dn, cur.missions.size()])
	U.set_camp_progress(cur.num, dn, cur.missions.size())
	U.show_overlay("start")
	paused = true
	A.music_stop()

## Wipes campaign progress and watched cutscenes (the difficulty stays), back to the start of chapter I:
## the menu, the splash and the home screen icon follow on the next start screen.
func reset_progress() -> void:
	var d := {"_level": camp_level()}
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d)); f.close()
	camp_id = D.CAMPAIGNS[0].id
	U.set_stage(menu_stage())
	show_campaigns()
	U.toast("Progress reset")

func show_campaigns() -> void:
	if not camp_open(camp_id): camp_id = D.CAMPAIGNS[0].id
	U.render_campaigns(_camp_rows(), camp_id)
	U.show_overlay("campaign")

func open_brief(i: int) -> void:
	brief_i = i
	var C := D.camp(camp_id)
	var m: Dictionary = C.missions[i]
	U.btn.br_eye.text = ("%s  //  Mission %d of %d" % [C.name, i + 1, C.missions.size()]).to_upper()
	U.btn.br_title.text = m.title.to_upper()
	U.btn.br_theatre.text = (m.theatre + "  ·  " + D.THEMES[m.map.theme].name).to_upper()
	U.btn.br_text.text = m.brief
	U.set_brief_heroes(m.heroes, C.fac)
	U.btn.br_obj.text = "\n".join(m.obj.map(func(o): return "•  " + o))
	U._seg_pick("level", camp_level())
	U.show_overlay("brief")

## Begin on the briefing: the campaign's opening the first time its first mission starts, then the mission's own intro.
func begin_mission() -> void:
	var opt := {"mission": D.camp(camp_id).missions[brief_i], "level": camp_level()}
	var reel: Array = []
	var op := Cutscenes.opening_of(camp_id)
	if brief_i == 0 and Cutscenes.has(op) and not cine_seen(op): reel.append(op)
	if Cutscenes.has(Cutscenes.intro_of(camp_id, brief_i)): reel.append(Cutscenes.intro_of(camp_id, brief_i))
	play_reel(reel, func(): play(opt))

# ---------------- cutscenes ----------------
func cine_seen(id: String) -> bool:
	return (_camp_file().get("_seen", []) as Array).has(id)

func _cine_mark(id: String) -> void:
	var d := _camp_file(); var seen: Array = d.get("_seen", [])
	if seen.has(id): return
	seen.append(id); d["_seen"] = seen
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

## Plays scenes one after the other (Skip ends only the current one), then calls done.
func play_reel(ids: Array, done: Callable) -> void:
	if ids.is_empty() or headless: done.call(); return
	start_cutscene(ids[0], func(): play_reel(ids.slice(1), done))

## Builds the scene's map and cast on the sim and hands the timeline to the cutscene player.
func start_cutscene(id: String, done: Callable) -> void:
	_cine_mark(id)
	var sc := Cutscenes.scene(id)
	var M: Dictionary = D.camp(sc.camp).missions[sc.map]
	placing = null; amove = false; sw_aim = false; jump_aim = false; gest = null; ptrs.clear()
	U.show_overlay(""); U.hud.visible = false; U.panel.visible = false
	S.new_game("normal", {"mission": M, "level": camp_level(), "cine": true, "bare": sc.get("bare", false)})
	V.build_world(); V.panel_px = 0.0
	S.update_vision()
	paused = false; A.set_paused(false)
	cut.start(sc, Cutscenes.setup(S, sc), func():
		U.hud.visible = true; V.panel_px = U.panel_px()
		paused = true
		done.call())
	A.music_start()

## Replays a scene from the campaign screen, then comes back to it.
func watch_cutscene(id: String) -> void:
	start_cutscene(id, func(): A.music_stop(); show_campaigns())

## Campaign difficulty, kept with the campaign progress.
func camp_level() -> String:
	var l: String = str(_camp_file().get("_level", "normal"))
	return l if D.LEVELS.has(l) else "normal"

func set_camp_level(l: String) -> void:
	var d := _camp_file(); d["_level"] = l
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(d))

func next_mission() -> void:
	if brief_i >= D.camp(camp_id).missions.size() - 1 and _sequel(camp_id) != "":
		camp_id = _sequel(camp_id); open_brief(0); return
	open_brief(min(D.camp(camp_id).missions.size() - 1, brief_i + 1))

func play(opt: Dictionary) -> void:
	last_opt = opt
	A.mood = int(opt.mission.mood) if opt.has("mission") else 0
	U.show_overlay("")
	new_game(opt.get("diff", diff), opt)
	paused = false
	A.set_paused(false)

func new_game(d: String, opt: Dictionary) -> void:
	placing = null; amove = false; sw_aim = false; jump_aim = false; gest = null; ptrs.clear()
	sq.reset(); sel_src = ""; sel_set = []; sq_full_t = -99.0; obj_t = OBJ_SHOW; obj_gi = -1
	S.new_game(d, opt)
	diff = S.diff
	V.build_world()
	S.update_vision()
	V.cam_z = 1.0
	V.center_on(S.p0.x * T + 16, (S.p0.y - 1) * T)
	if icons_for != S.teams[0].fac and not headless: render_icons(S.teams[0].fac)
	_setup_producers(); ctx_key = ""; peek = false; refresh_panel(true); update_cmd(); end_placing()
	_obj_vis()
	tut.start(S.mission)
	if S.mission: toast(S.mission.title, "gold")
	else:
		toast("Drag to move the map · swipe across your units to pick them", "gold")
		get_tree().create_timer(3.5).timeout.connect(func(): if S.time < 20 and not S.over: toast(("Grow a Garden beside the aurite: it earns, and it hatches your army" if S.lacks(0, "power") else "Build a " + D.BLD[S.tr_t(0, "power")].name + ", then a " + D.BLD[D.sub(S.teams[0].fac, "refinery")].name), "gold"))
	A.voice_start(S.teams[0].fac)
	A.music_start()

func open_menu() -> void:
	if S.over: return
	paused = true; U.show_overlay("menu"); A.set_paused(true)

func resume() -> void:
	paused = false; U.show_overlay(""); A.set_paused(false)

func restart() -> void:
	play(last_opt)

func quit_to_menu() -> void:
	show_start()

func toggle_sound() -> void:
	A.muted = not A.muted; U.btn.sound.text = "SOUND: " + ("OFF" if A.muted else "ON")

func voice_label() -> String:
	return "VOICE: " + ("ON" if A.voice_on else "OFF")

## Pause menu: the announcer on or off, saved in prefs.
func toggle_voice() -> void:
	A.voice_on = not A.voice_on; U.btn.voice.text = voice_label()
	if not A.voice_on: A.voice.stop()
	var p := _load_prefs(); p.voice = A.voice_on; _save_prefs(p)

func gfx_label() -> String:
	return "GRAPHICS: " + GFX.NAMES[GFX.level].to_upper()

## Pause menu: next graphics level, saved in prefs, applied at once (materials, every model and the world rebuilt).
func cycle_gfx() -> void:
	GFX.level = GFX.next_level(GFX.level)
	var p := _load_prefs(); p.gfx = GFX.level; _save_prefs(p)
	U.btn.gfx.text = gfx_label()
	V.apply_gfx()
	if not headless: render_icons(icons_for)

func toggle_music() -> void:
	A.music_on = not A.music_on; U.btn.music.text = "MUSIC: " + ("ON" if A.music_on else "OFF")
	if A.music_on: A.music_start()
	else: A.music_stop()

func _notification(what: int) -> void:
	if cut and cut.active:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST: cut.skip()
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if tut.card_open: tut.close_card()
		elif U.overlays.units.visible: U.show_overlay(tut.man_back)
		elif U.overlays.menu.visible: resume()
		elif U.overlays.brief.visible: show_campaigns()
		elif U.overlays.manual.visible or U.overlays.campaign.visible or U.overlays.skirmish.visible: show_start()
		elif S.teams.size() and not S.over and not U.overlays.start.visible: open_menu()
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if S and S.teams.size() and not S.over and not paused and U.overlays.menu and not U.overlays.start.visible: open_menu()

# ---------------- panel ----------------
## A sub-tab of the selected producer (INF / VEH / AIR on a Landing Zone or a Garden).
func select_tab(cat: String) -> void:
	cur_tab = cat; ctx_key = ""; show_ctx(); sfx("click")

## The side panel follows the selection (Guillaume 2026-11-27: "build for workers, hire on barracks"):
## nothing selected or the Yard: structures · a producer: the units it makes · units: what they can do ·
## another building: its orders · an enemy: what it is. Items and tabs change only when the context does.
func show_ctx() -> void:
	if U == null or S.teams.is_empty(): return
	var sel: Array = S.sel.filter(func(e): return e.alive)
	var units: Array = sel.filter(func(e): return e.kind == "u" and e.team == 0)
	var b: Ent = null
	for e in sel:
		if e.kind == "b": b = e; break
	var key := "yard"; var cats := ["bld"]
	if not units.is_empty(): key = "u"; cats = []
	elif b != null and b.team != 0: key = "e%d" % b.id; cats = []
	elif sel.size() > 0 and b == null: key = "e%d" % sel[0].id; cats = []
	elif b != null and b.type != "hq":
		key = "b%d" % b.id; cats = prod_cats(b.type)
	if key != ctx_key:
		ctx_key = key
		if cats.size() > 1 and not cats.has(cur_tab): cur_tab = cats[0]
		var show: Array = cats if cats.size() <= 1 else [cur_tab]
		U.ctx_tabs.visible = cats.size() > 1
		for c in U.tabs:
			U.tabs[c].visible = cats.has(c); U.set_on(U.tabs[c], c == cur_tab)
		var bt: String = b.type if (b != null and key.begins_with("b")) else ""
		for k in U.items:
			var it = U.items[k]
			it.visible = show.has(it.cat) and S.avail(0, it.type) and (it.cat == "bld" or S.unit_from(0, it.type) == bt)
		U.grid_scroll.visible = not cats.is_empty()
		U.grid_scroll.scroll_vertical = 0
		refresh_panel(true)
	_ctx_head(key, b, units, sel)
	# a hidden panel peeks out while the selection has something in it to use
	U.ctx_box.visible = sel.size() > 0 and not U.type_btns.any(func(t): return t.visible)

## The panel header: what is selected, its health and one line about it.
func _ctx_head(key: String, b: Ent, units: Array, sel: Array) -> void:
	var kick := ""; var nm := ""; var sub := ""; var hp := -1.0
	if key == "yard":
		var hq := S.find_hq(0)
		var q: Dictionary = S.teams[0].prod.bld
		kick = "BUILD"; nm = D.BLD.hq.name.to_upper() if S.count(0, "hq") > 0 else "NO YARD"
		if hq != null and hq.type == "hq" and b != null: hp = hq.hp / hq.max_hp
		if q.ready: sub = D.BLD[q.cur].name + " is ready: drag it onto the map"
		elif q.cur != "": sub = "Building %s · %d%%" % [D.BLD[q.cur].name, int(q.prog * 100)]
		elif S.count(0, "hq") == 0: sub = "Without a Yard nothing new can be built"
		else: sub = "Tap a structure to start it"
	elif key == "u":
		var types := {}
		var tot := 0.0
		for u in units:
			types[u.type] = types.get(u.type, 0) + 1; tot += u.hp / u.max_hp
		hp = tot / units.size()
		kick = "SELECTED"
		if types.size() == 1:
			var d: Dictionary = units[0].d
			nm = d.name.to_upper() if units.size() == 1 else "%d × %s" % [units.size(), d.name.to_upper()]
		else: nm = "%d UNITS" % units.size()
		sub = sel_line(units[0]) if types.size() == 1 else ", ".join(types.keys().map(func(t): return "%s %d" % [D.UN[t].name, types[t]]))
	elif key.begins_with("e"):
		var e: Ent = sel[0] if b == null else b
		kick = "ENEMY" if e.team == 1 else ("NEUTRAL" if e.team > 1 else "ALLY")
		nm = e.d.name.replace(" ×4", "").to_upper(); hp = e.hp / e.max_hp
		sub = String(Tutor.TD.CARDS.get(e.type, {}).get("job", ""))
	else:
		var cats := prod_cats(b.type)
		kick = ("GROWS" if S.fac_of(0) == "choir" else ("DROPS" if b.type == "lz" else "TRAINS")) if not cats.is_empty() else "STRUCTURE"
		nm = b.d.name.replace(" ×4", "").to_upper(); hp = b.hp / b.max_hp
		sub = sel_line(b)
		if not cats.is_empty():
			var n := 0
			for c in cats: n += S.teams[0].prod[c].queue.filter(func(t): return S.unit_from(0, t) == b.type).size() + (1 if S.teams[0].prod[c].cur != "" and S.unit_from(0, S.teams[0].prod[c].cur) == b.type else 0)
			if n > 0: sub = "%d in queue · %s" % [n, sub]
			if S.teams[0].get("loop", {}).get(b.type, false): sub = "LOOP · " + sub
			var head: Array = cats.map(func(c): return S.teams[0].prod[c]).filter(func(q): return q.cur == "" and q.queue.size() > 0 and S.unit_from(0, q.queue[0]) == b.type)
			if head.any(func(q): return S.cap_full(0, q.queue[0])): sub = "UNIT CAP FULL · " + sub
	if U.ctx_kick.text != kick: U.ctx_kick.text = kick
	if U.ctx_name.text != nm:
		U.ctx_name.text = nm; U.ctx_name.add_theme_font_size_override("font_size", 15 if nm.length() <= 15 else (13 if nm.length() <= 18 else 11))
	if U.ctx_sub.text != sub: U.ctx_sub.text = sub
	U.ctx_sub.visible = sub != ""
	U.ctx_hp.visible = hp >= 0; U.ctx_hp.set_val(hp)

func click_item(cat: String, type: String) -> void:
	if S.teams.is_empty() or S.over: return
	var tm: Dictionary = S.teams[0]; var q: Dictionary = tm.prod[cat]; var d: Dictionary = D.def_of(type)
	if not S.has_req(0, d.req):
		toast("Requires " + " + ".join(S.req_of(0, d.req).map(func(r): return D.BLD[r].name)), "warn"); return
	if S.at_limit(0, type):
		toast(d.name + " is already in the field", "warn"); return
	if cat == "bld":
		if q.ready and q.cur == type: start_placing(type); return
		if q.cur != "":
			toast("Already building" if q.cur == type else "Busy building " + D.BLD[q.cur].name); return
		q.cur = type; q.prog = 0.0; q.paid = 0.0; q.ready = false; sfx("click"); tut.ev("order", type)
	else:
		if S.count(0, S.unit_from(0, type)) == 0:
			toast("Requires " + D.BLD[S.unit_from(0, type)].name, "warn"); return
		if q.queue.size() + (1 if q.cur != "" else 0) >= 9: return
		q.queue.append(type); sfx("click")
	refresh_panel(true)

func cancel_item(cat: String, type: String) -> void:
	if S.teams.is_empty(): return
	var tm: Dictionary = S.teams[0]; var q: Dictionary = tm.prod[cat]
	if cat == "bld":
		if q.cur == type:
			tm.credits += q.paid; q.cur = ""; q.prog = 0.0; q.paid = 0.0; q.ready = false
			if placing != null: end_placing()
			toast("Cancelled")
	else:
		var i: int = q.queue.rfind(type)
		if i >= 0: q.queue.remove_at(i)
		elif q.cur == type:
			tm.credits += q.paid; q.cur = ""; q.prog = 0.0; q.paid = 0.0
		toast("Cancelled")
	sfx("click"); refresh_panel(true)

func refresh_panel(_force := false) -> void:
	if S.teams.is_empty(): return
	var tm: Dictionary = S.teams[0]
	for k in U.items:
		var it = U.items[k]; var q: Dictionary = tm.prod[it.cat]; var d: Dictionary = D.def_of(it.type)
		var locked: bool = not S.has_req(0, d.req) or (it.cat != "bld" and S.count(0, S.unit_from(0, it.type)) == 0) or (d.lim > 0 and S.count(0, it.type) >= d.lim)
		var n := 0; var prog := 0.0; var ready := false
		if it.cat == "bld":
			if q.cur == it.type: prog = q.prog; ready = q.ready
		else:
			n = q.queue.count(it.type) + (1 if q.cur == it.type else 0)
			if q.cur == it.type: prog = q.prog
		# active from the moment it is ordered, even before any aurite is paid (prog still 0)
		var active: bool = q.cur == it.type or (it.cat != "bld" and q.cur == "" and q.queue.size() > 0 and q.queue[0] == it.type)
		it.locked = locked; it.n = n; it.prog = prog; it.is_ready = ready; it.active = active
		if it.visible: it.queue_redraw()
	for c in U.tabs:
		var q: Dictionary = tm.prod[c]
		U.tabs[c].get_meta("dot").visible = q.cur != "" or q.queue.size() > 0
	if ctx_key != "": show_ctx()
	var sw: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "b" and e.d.sw: sw = e; break
	U.sw_box.visible = sw != null
	if sw:
		U.sw_name.text = sw.d.name.split(" ")[0].to_upper()
		U.sw_time.text = "READY" if sw.rdy else D.fmt(sw.d.charge - sw.ch)
	if S.mission: U.obj_l.text = S.obj_text() + tut.obj_extra()
	_obj_vis()
	_panel_alert()
	_prod_chips(tm)
	_squad_chips()

func hud_tick(dt: float) -> void:
	var tm: Dictionary = S.teams[0]
	shown_cr += (tm.credits - shown_cr) * min(1.0, dt * 8)
	if abs(tm.credits - shown_cr) < 1: shown_cr = tm.credits
	U.credits_l.text = Sim._thousands(int(shown_cr))
	U.power_l.text = "%d / %d" % [tm.pmade, tm.pused]
	var lp := S.low_power(0)
	U.power_bar.set_val(min(1.0, float(tm.pused) / tm.pmade if tm.pmade else 1.0), lp)
	U.power_l.add_theme_color_override("font_color", UI.C_BAD if lp else UI.C_FG)
	var pw := S.uses_power(0); var cm := S.cap_max(0); var cap_on: bool = D.rule(tm.fac, "cap")
	for c in U.power_parts: c.visible = pw
	var podf: bool = D.rule(tm.fac, "pods")
	for c in U.cap_parts: c.visible = cap_on or podf
	U.cap_parts[2].get_child(0).text = "PODS" if podf else "UNITS"
	if podf:
		var np := S.pods(0)
		U.cap_l.text = str(np)
		U.cap_l.add_theme_color_override("font_color", UI.C_BAD if np == 0 else UI.C_FG)
	elif cap_on:
		var cu := S.cap_used(0)
		U.cap_l.text = "%d / %d" % [cu, cm]
		U.cap_l.add_theme_color_override("font_color", UI.C_BAD if cu >= cm else UI.C_FG)
	if S.mission:
		if S.gi != obj_gi: obj_gi = S.gi; obj_t = OBJ_SHOW  # a new goal shows itself again
		if obj_t > 0:
			obj_t -= dt
			if obj_t <= 0: _obj_vis()
	panel_t -= dt
	if panel_t <= 0: panel_t = .12; refresh_panel(); _upg_btn(); _unit_btns()

# ---------------- placement ----------------
func start_placing(type: String) -> void:
	var d: Dictionary = D.BLD[type]; var vc := V.view_rect().get_center(); var c := V.s2w(vc.x, vc.y)
	var q: Dictionary = S.teams[0].prod.bld
	if d.kit and not q.left: q.left = d.kit
	placing = {"type": type, "tx": int(round(c.x / T - d.w / 2.0)), "ty": int(round(c.y / T - d.h / 2.0)), "ldx": 0, "ldy": 0}
	var best = null; var bd := 1e9
	for y in range(placing.ty - 8, placing.ty + 9):
		for x in range(placing.tx - 8, placing.tx + 9):
			if S.can_place(0, type, x, y, false):
				var dd: float = (x - placing.tx) * (x - placing.tx) + (y - placing.ty) * (y - placing.ty)
				if dd < bd: bd = dd; best = Vector2i(x, y)
	if best != null: placing.tx = best.x; placing.ty = best.y
	U.place_bar.visible = true; place_hint(); _fit_dock()
	tut.ev("placing")

## Drag a ready building out of the menu: it follows the finger, drawn GHOST_LIFT above it so the
## finger does not hide it, and is built where it is let go (if the spot is allowed).
func drag_build_start(type: String, p: Vector2) -> void:
	if placing == null or placing.type != type: start_placing(type)
	drag_build_move(p)

func _ghost_at(p: Vector2, lift: float) -> void:
	var w := V.s2w(p.x, p.y - lift); var d: Dictionary = D.BLD[placing.type]
	placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))

func drag_build_move(p: Vector2) -> void:
	if placing == null or not _in_view(p): return
	_ghost_at(p, GHOST_LIFT)

func drag_build_end(p: Vector2) -> void:
	if placing == null: return
	if not _in_view(p): return  # let go over the menu: stay in placing mode
	_ghost_at(p, GHOST_LIFT)
	if S.can_place(0, placing.type, placing.tx, placing.ty, false): confirm_place()
	else: toast("Can't build there · drag it or tap Build here", "warn")

func place_hint() -> void:
	var q: Dictionary = S.teams[0].prod.bld
	U.place_hint.text = ("Barrier: %d left · tap it to build" % q.left) if (placing != null and D.BLD[placing.type].kit) else "Drag to position · tap it to build"

func end_placing() -> void:
	placing = null; U.place_bar.visible = false; _fit_dock()

func confirm_place() -> void:
	if placing == null: return
	var q: Dictionary = S.teams[0].prod.bld
	if not S.can_place(0, placing.type, placing.tx, placing.ty, false):
		var pd: Dictionary = D.BLD[placing.type]
		if pd.onore: toast("A Deep Drill lands on an aurite field, inside Signal (the blue rings).", "warn")
		elif pd.shore: toast("It needs open water beside it.", "warn")
		elif pd.field: toast("A Garden roots beside living aurite, away from enemy buildings.", "warn")
		elif D.rule(S.fac_of(0), "place") == "hum": toast("Can't grow there. Stay inside the Hum (the green rings): a Garden carries it further.", "warn")
		elif D.rule(S.fac_of(0), "place") == "signal": toast("Can't land there. Stay inside Signal (the blue rings): a Signal Mast carries it further.", "warn")
		else: toast("Can't build there. Stay close to your base, off rock, water and aurite.", "warn")
		return
	var b := S.add_building(0, placing.type, placing.tx, placing.ty)
	S.clear_footprint(b)
	tut.ev("made", placing.type)
	for k in 8: S.parts.append({"k": "smoke", "x": b.tx * T + randf() * b.w * T, "y": (b.ty + b.h) * T - 4, "vx": (randf() - .5) * 30, "vy": -randf() * 10, "life": .8, "max": .8, "s": 5.0, "c": Color8(150, 140, 120)})
	sfx("place")
	if D.BLD[placing.type].kit:
		q.left -= 1
		if q.left > 0:
			var px: int = placing.tx; var py: int = placing.ty; var best = null; var bd := 1e9
			for dxy in [[1, 0], [0, 1], [-1, 0], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1], [2, 0], [0, 2]]:
				if S.can_place(0, placing.type, px + dxy[0], py + dxy[1], false):
					var dd: float = dxy[0] * dxy[0] + dxy[1] * dxy[1] + (-1 if (placing.ldx == dxy[0] and placing.ldy == dxy[1]) else 0)
					if dd < bd: bd = dd; best = dxy
			if best != null:
				placing.tx = px + best[0]; placing.ty = py + best[1]; placing.ldx = best[0]; placing.ldy = best[1]
			place_hint(); refresh_panel(true); return
	q.cur = ""; q.ready = false; q.prog = 0.0; q.paid = 0.0; q.left = 0
	end_placing(); refresh_panel(true)

# ---------------- commands ----------------
## Pause menu: which side the buttons go (the other thumb keeps the map). Remembered between games.
func toggle_hand() -> void:
	U.left_hand = not U.left_hand; V.panel_left = U.left_hand
	U._place_hud(); V.panel_px = U.panel_px(); _hand_label(); sfx("click")
	var p := _load_prefs(); p.wheel = "left" if U.left_hand else "right"; _save_prefs(p)

func _hand_label() -> void:
	U.btn.hand.text = ("Wheel: left" if U.left_hand else "Wheel: right").to_upper()

func cmd_btn(k: String) -> void:
	match k:
		"sw":
			sw_aim = not sw_aim; sfx("click"); update_cmd()
			if sw_aim: tut.ev("aim")
		"amove":
			amove = not amove; update_cmd()
		"stop":
			for u in S.sel:
				if u.kind == "u":
					u.path = []; u.order = "none"; u.target = null; u.guard = Vector2(u.x, u.y); u.face = null
					if u.d.harv: u.hs = "idle"
		"desel": S.set_sel([])
		"hold", "nofire":
			var us := _my_units().filter(func(u): return u.d.dmg > 0)
			if us.is_empty(): return
			var on: bool = not us.all(func(u): return u.get(k))
			for u in us:
				u.set(k, on)
				if on and k == "hold": u.guard = Vector2(u.x, u.y)
				if on and k == "nofire" and u.auto: u.target = null; u.auto = false
			toast(("Holding ground: they fight only what is in reach" if on else "Free to chase again") if k == "hold" else ("Holding fire" if on else "Weapons free"))
			sfx("click"); update_cmd()
		"scatter":
			var us := _my_units()
			if us.is_empty(): return
			var c := Vector2()
			for u in us: c += Vector2(u.x, u.y)
			c /= us.size()
			for u in us:
				var dv := Vector2(u.x, u.y) - c
				if dv.length() < 4: dv = Vector2.from_angle(randf() * TAU)
				var to: Vector2 = Vector2(u.x, u.y) + dv.normalized().rotated(randf_range(-0.4, 0.4)) * T * randf_range(2.5, 3.5)
				S.group_move([u], clampf(to.x, T, D.WW - T), clampf(to.y, T, D.WH - T), "move")
			sfx("ack"); buzz(12); update_cmd()
		"home":
			var us := _my_units()
			var hq := S.find_hq(0)
			if us.is_empty() or hq == null: return
			var to: Vector2 = hq.rally if hq.rally != null else Vector2(hq.x, hq.y + T * 3)
			S.group_move(us, to.x, to.y, "move"); ring(to.x, to.y, Color("7fd68e"))
			sfx("ack"); buzz(12); update_cmd()
		"loop":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b" or b.team != 0 or prod_cats(b.type).is_empty(): return
			toggle_loop(b.type)
		"jump":
			jump_aim = not jump_aim; amove = false; sfx("click"); update_cmd()
		"rally":
			rally_aim = not rally_aim; sfx("click"); update_cmd()
		"strip":
			var us := _my_units().filter(func(u): return u.d.get("scrap", false))
			if us.is_empty(): return
			var on: bool = not us.all(func(u): return u.strip)
			for u in us: u.strip = on
			toast("Strip every wreck for aurite" if on else "Revive wrecks that still hold together")
			sfx("click"); update_cmd()
		"fuse":
			var ids := S.sel.map(func(e): return e.id)
			var knot = S.fuse(0, S.sel)
			if knot == null: toast("Fusion needs %d Thralls" % D.HUM.fuse, "warn")
			else: sq.replace(ids.filter(func(i): return not S.ents.any(func(e): return e.id == i and e.alive)), knot); _squad_chips()
			update_cmd()
		"muster":
			if S.muster(0) == 0: toast("The Hearths have already answered this battle", "warn")
			update_cmd()
		"upgrade":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b" or b.team != 0: return
			if b.upg >= 0:
				S.cancel_upgrade(b); toast("Upgrade cancelled, aurite refunded"); sfx("click")
			else:
				var why := S.upg_block(b)
				if why != "": toast(why, "warn"); return
				S.start_upgrade(b); sfx("place")
				toast("Upgrading to " + D.UPG[b.type].name + ": " + D.UPG[b.type].say)
			update_cmd()
		"repair":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b": return
			if b.hp >= b.max_hp and not b.repairing: toast("Already at full strength"); return
			b.repairing = not b.repairing; sfx("click"); update_cmd()
		"sell":
			var b: Ent = S.sel[0] if S.sel.size() else null
			if b == null or b.kind != "b" or b.team != 0 or b.type == "hq": return
			var ref := S.sell(b)
			S.set_sel([]); toast("Sold for %d" % ref, "gold"); sfx("place"); refresh_panel(true)

## JOIN (the selection is a squad and fresh units wait) and the type chips of a mixed selection.
func _squad_cmd(units: Array) -> void:
	var n := sq.matching(S, S.sel) if units.size() == S.sel.size() else 0
	var fr := sq.fresh(S).size() if n else 0
	U.btn.join.visible = fr > 0
	if fr: U.btn.join.text = "JOIN +%d" % fr
	var by := {}; var order := []
	for u in units:
		if not by.has(u.type): by[u.type] = 0; order.append(u.type)
		by[u.type] += 1
	order.sort_custom(func(a, b): return by[a] > by[b])
	for i in U.type_btns.size():
		var b: Button = U.type_btns[i]
		b.visible = order.size() > 1 and i < order.size()
		if b.visible:
			var t: String = order[i]
			b.set_meta("type", t); b.text = "%d %s" % [by[t], String(D.UN[t].name).get_slice(" ", String(D.UN[t].name).get_slice_count(" ") - 1).to_upper()]   # count first: a long name clips, the count stays

func _my_units() -> Array:
	return S.sel.filter(func(e): return e.alive and e.kind == "u" and e.team == 0)

func update_cmd() -> void:
	if U == null: return
	var units: Array = S.sel.filter(func(e): return e.kind == "u")
	var combat := units.filter(func(u): return u.d.dmg > 0)
	U.btn.amove.visible = combat.size() > 0; U.btn.stop.visible = units.size() > 0; U.btn.desel.visible = S.sel.size() > 0
	var dt := ("%d PICKED" % units.size()) if units.size() > 1 else ""
	if U.btn.desel.text != dt: U.btn.desel.text = dt; U.restyle(U.btn.desel)
	var swb: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "b" and e.rdy: swb = e; break
	U.btn.sw.visible = swb != null
	if swb: U.btn.sw.text = "PICK TARGET" if sw_aim else "LAUNCH " + swb.d.name.split(" ")[0].to_upper()
	var sb: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b" and S.sel[0].team == 0) else null
	U.btn.repair.visible = sb != null; U.btn.sell.visible = sb != null and sb.type != "hq"
	if sb: U.set_on(U.btn.repair, sb.repairing)
	_upg_btn()
	if sb == null or not _rallies(sb): rally_aim = false
	U.btn.rally.visible = sb != null and _rallies(sb)
	U.set_on(U.btn.rally, rally_aim)
	U.btn.loop.visible = sb != null and not prod_cats(sb.type).is_empty()
	if U.btn.loop.visible: U.set_on(U.btn.loop, S.teams[0].get("loop", {}).get(sb.type, false))
	U.btn.muster.visible = sb != null and sb.d.get("muster", 0) > 0 and not S.teams[0].get("mustered", false)
	U.btn.fuse.visible = units.filter(func(u): return u.team == 0 and u.d.fuse != "").size() >= D.HUM.fuse
	_unit_btns()
	U.set_on(U.btn.amove, amove)
	_squad_cmd(units)
	show_ctx()
	_fit_dock()

## A hidden panel folds down to the dock, and goes away while the dock has nothing to show.
func _fit_dock() -> void:
	U.panel.visible = false
	var show: bool = placing == null
	U.wheel.visible = show; U.plates.visible = show

## Unit orders in the panel: stances for every army (Hold ground, Hold fire), Scatter, To base, then each army's own
## (Jump for Jump Troopers, Strip for Scrappers, Fuse for Thralls). A stance lights while every unit that fights has it.
func _unit_btns() -> void:
	var us := _my_units()
	var fighters := us.filter(func(u): return u.d.dmg > 0)
	for k in ["hold", "nofire"]:
		U.btn[k].visible = fighters.size() > 0
		U.set_on(U.btn[k], fighters.size() > 0 and fighters.all(func(u): return u.get(k)))
	U.btn.scatter.visible = us.size() > 0
	U.btn.home.visible = us.size() > 0 and S.find_hq(0) != null
	var jumpers := us.filter(func(u): return u.d.jump > 0)
	U.btn.jump.visible = jumpers.size() > 0
	if jumpers.size():
		var wait: float = jumpers.map(func(u): return u.jump_t - S.time).min()
		var cap := "JUMP" if wait <= 0 else "JUMP %ds" % ceili(wait)
		if U.btn.jump.cap != cap: U.btn.jump.cap = cap; U.btn.jump.queue_redraw()
		U.btn.jump.modulate.a = 1.0 if wait <= 0 else 0.55
	if jump_aim and jumpers.is_empty(): jump_aim = false
	U.set_on(U.btn.jump, jump_aim)
	var scr := us.filter(func(u): return u.d.get("scrap", false))
	U.btn.strip.visible = scr.size() > 0
	U.set_on(U.btn.strip, scr.size() > 0 and scr.all(func(u): return u.strip))

## One line about a selected unit or building: what it does, or what is wrong with it. full: with its name first.
func sel_line(e: Ent, full := false) -> String:
	var d := e.d
	var nm: String = d.name.replace(" ×4", "")
	var t := ""
	if e.kind == "b":
		if e.team == 0 and not S.upg_def(e).is_empty():
			var u := S.upg_def(e)
			t = (("%d Pods · " % e.pods) if d.grow else "") + ("upgrading: " if e.upg >= 0 else "upgrade %d: " % u.cost) + u.say
		else: t = "RALLY on its ring sets where units gather" if (d.get("door", false) or d.get("yard", false) or d.get("pad", false) or e.type == "mast") else ("park vehicles beside it" if e.type == "repair" else "")
		if d.grow and S.upg_def(e).is_empty(): t = "%d Pods · sings to the field around it" % e.pods
		elif d.thorn > 0: nm = "Thornglass"; t = "cuts infantry that touch it"
		elif e.dark: t = "NO SIGNAL: build a Signal Mast near it"
		elif e.dry: t = "field pumped dry: sell it and drill another"
		elif d.get("signal", 0.0) > 0 and S.fac_of(0) == "vanguard": t = "sends Signal %d tiles%s" % [int(d.signal), (", +%d Command" % d.capAdd) if e.type != "hq" else ""]
		elif d.get("dome", 0.0) > 0: t = "shield %d / %d over everything near it" % [int(e.sh), int(e.sh_max)]
	else:
		t = "tap aurite to mine" if d.harv else ("tap a wreck to revive or strip it" if d.get("scrap", false) else ("tap a building to capture or fix" if d.eng else ("heals nearby infantry" if d.heal else ("long range, blind up close" if d.minr > 0 else ("cloaks when it stands still" if d.cloak > 0 else ("jumps on long moves" if d.jump > 0 else ("sniffs out hidden units" if d.detect > 0 else ("what it sees takes +25%" if d.mark > 0 else ("slug goes through a whole line" if d.pierce else ("select %d and FUSE them into a Knot" % D.HUM.fuse if d.fuse != "" else ("its cry jams machines and drops shields" if d.cry > 0 else ("withers outside the Hum" if d.wither > 0 else ("mutated" if e.mut else ("mutates after %d kills" % D.HUM.mut if not d.mut.is_empty() else ""))))))))))))))
	if not full: return t
	return nm + (" · " + t if t != "" else "")

## The UPGRADE button of a selected building: its cost, its progress while it runs (tap again to cancel), dimmed while
## the requirement is missing (a tap says what is needed).
func _upg_btn() -> void:
	var b: Ent = S.sel[0] if (S.sel.size() == 1 and S.sel[0].kind == "b" and S.sel[0].team == 0) else null
	var u: Dictionary = S.upg_def(b) if b != null else {}
	U.btn.upgrade.visible = not u.is_empty()
	if u.is_empty(): return
	var cap: String = ("%d%% ✕" % int(b.upg * 100)) if b.upg >= 0 else "UPGRADE"
	if U.btn.upgrade.cap != cap: U.btn.upgrade.cap = cap; U.btn.upgrade.queue_redraw()
	U.set_on(U.btn.upgrade, b.upg >= 0)
	U.btn.upgrade.modulate.a = 0.55 if (b.upg < 0 and S.upg_block(b) != "") else 1.0

func ring(x: float, y: float, c: Color) -> void:
	S.parts.append({"k": "ring", "x": x, "y": y, "life": .5, "max": .5, "c": c})

# ---------------- picking ----------------
func pick(sx: float, sy: float, wx: float, wy: float) -> Ent:
	V.update_cam()
	var best: Ent = null; var bd := 1e9
	for e in S.ents:
		if not e.alive or e.kind != "u" or e.captive or e.intun > 0: continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var h: float = S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, h + D.UH[e.type] * .45)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, h); var o := V.w2s(e.x, e.y, h); var ppt: float = abs(q.x - o.x)
		# generous: a fingertip is about 30 UI units wide, small infantry far less
		var rad: float = max(32.0, e.r / T * ppt * 1.8)
		if V.radar_on: rad = 14.0 if e.team == 0 else 20.0   # icons sit close together: tapping near your own should still order
		var dd := Vector2(p.x - sx, p.y - sy).length()
		if dd < rad and dd < bd: bd = dd; best = e
	if best: return best
	var rr := V.ray(sx, sy); var ro: Vector3 = rr[0]; var rn: Vector3 = rr[1]
	var bdist := 1e9; var bb: Ent = null
	for e in S.ents:
		if not e.alive or e.kind != "b" or not S.visible_to_player(e): continue
		var box := AABB(Vector3(e.tx, 0, e.ty), Vector3(e.w, D.BH[e.type], e.h))
		var hit = box.intersects_ray(ro, rn)
		if hit != null:
			var dd: float = (hit as Vector3).distance_to(ro)
			if dd < bdist: bdist = dd; bb = e
	if bb: return bb
	var tx := int(wx / T); var ty := int(wy / T)
	if not Sim.inb(tx, ty): return null
	var id: int = S.bmap[ty * 64 + tx]
	if id and S.by_id.has(id):
		var b: Ent = S.by_id[id]
		if b.alive and S.visible_to_player(b): return b
	return null

func tap(sx: float, sy: float, right: bool) -> void:
	if S.teams.is_empty() or S.over: return
	var w := V.s2w(sx, sy); var wx := w.x; var wy := w.y
	if placing != null:
		var tx := int(floor(wx / T)); var ty := int(floor(wy / T)); var d: Dictionary = D.BLD[placing.type]
		if tx >= placing.tx and tx < placing.tx + d.w and ty >= placing.ty and ty < placing.ty + d.h: confirm_place()
		else:
			placing.tx = int(round(wx / T - d.w / 2.0)); placing.ty = int(round(wy / T - d.h / 2.0))
		return
	var hit := pick(sx, sy, wx, wy)
	if V.radar_k() >= 0.5 and not right:
		# a badge, unless the tap lands right on an enemy icon (badges sit where the fighting is)
		var n := rd.badge_at(Vector2(sx, sy))
		if n > 0 and hit != null and hit.team != 0:
			var hp3 := V.w2s(hit.x, hit.y, S.h_at(hit.x, hit.y))
			if Vector2(hp3.x, hp3.y).distance_to(Vector2(sx, sy)) < 10: n = 0
		if n > 0: radar_badge(n); return
	if U.ring.docked != "" and not right:   # a tap outside a shortcut's menu closes it; on one of your structures it
		U.ring.toggle_dock(U.ring.docked)   # goes on to select it (its own half ring opens), else it does nothing more
		if hit == null or hit.team != 0 or hit.kind != "b": return
	var sel_u: Array = S.sel.filter(func(e): return e.kind == "u")
	if jump_aim and not right:
		jump_aim = false
		var n := 0
		for u in sel_u:
			if S.jump_to(u, wx, wy): n += 1
		if n > 0: ring(wx, wy, Color("7fd68e")); sfx("ack"); buzz(12); tut.ev("jump")
		else: toast("Jets still cooling down", "warn")
		update_cmd(); return
	if sw_aim and not right:
		var b: Ent = null
		for e in S.ents:
			if e.alive and e.team == 0 and e.kind == "b" and e.rdy: b = e; break
		sw_aim = false
		if b: S.launch_sw(b, wx, wy)
		update_cmd(); return
	if right:
		if sel_u.size(): command(hit, wx, wy, sel_u)
		else: S.set_sel([])
		return
	if hit != null and hit.team == 0:
		if hit.kind == "b" and hit.d.get("dock", false) and sel_u.any(func(u): return u.d.harv):
			for u in sel_u:
				if u.d.harv: u.hs = "ret"
			ring(hit.x, hit.y, Color("f0b93f")); return
		if hit.kind == "b" and hit.type == "repair" and sel_u.any(func(u): return u.d.armor != "inf"):
			S.group_move(sel_u.filter(func(u): return u.d.armor != "inf"), hit.x, hit.y, "move"); ring(hit.x, hit.y, Color("7fd68e")); sfx("click"); return
		if hit.kind == "b" and hit.hp < hit.max_hp and sel_u.any(func(u): return u.d.eng):
			S.eng_order(sel_u.filter(func(u): return u.d.eng), hit); ring(hit.x, hit.y, Color("7fd68e")); sfx("click"); return
		if hit.kind == "u":
			var now := Time.get_ticks_msec()
			if last_tap.id == hit.id and now - last_tap.t < 380:
				# double-tap / double-click: every unit of that type on screen
				var same := S.ents.filter(func(e): return e.alive and e.kind == "u" and e.team == 0 and e.type == hit.type and V.on_screen(e.x, e.y))
				sel_src = ""; S.set_sel(same); last_tap.id = 0
				if same.size() > 1: toast("%d × %s" % [same.size(), hit.d.name])
				tut.ev("dbl")
			else:
				S.set_sel([hit]); last_tap = {"id": hit.id, "t": now}
			tut.ev("select", S.sel)
			buzz(8)
		else: S.set_sel([hit])
		sfx("click"); return
	if sel_u.size():
		command(hit, wx, wy, sel_u); return
	# a tap outside a structure's ring closes it (Guillaume 2026-11-28); its rally point is set through RALLY on the ring
	var sb: Ent = S.sel[0] if S.sel.size() else null
	if rally_aim and sb and sb.kind == "b" and _rallies(sb):
		rally_aim = false; sb.rally = Vector2(wx, wy); ring(wx, wy, Color("7fd68e")); sfx("click"); tut.ev("rally"); update_cmd(); return
	rally_aim = false
	S.set_sel([])

func command(hit: Ent, wx: float, wy: float, units: Array, face = null, width := 0.0) -> void:
	_squad_order(units)
	var combat := units.filter(func(u): return u.d.dmg > 0)
	var harvs := units.filter(func(u): return u.d.harv)
	var engs := units.filter(func(u): return u.d.eng)
	var others := units.filter(func(u): return u.d.dmg == 0 and not u.d.harv and not (u.d.eng and hit != null and hit.kind == "b" and hit.team != 0))
	var scr := units.filter(func(u): return u.d.scrap)
	var wk = S.wreck_at(wx, wy) if hit == null and scr.size() else null
	if wk != null:
		# Scrappers sent to a wreck: rebuild it while it holds together, otherwise strip it for aurite
		S.scrap_order(scr, wk); ring(wk.x, wk.y, Color("f0b93f")); sfx("click")
		toast("Reviving the " + D.UN[wk.type].name if (wk.intact >= D.WRECK.revive and not scr.all(func(u): return u.strip)) else "Stripping the wreck")
		units = units.filter(func(u): return not u.d.scrap)
		if units.is_empty(): update_cmd(); return
		combat = units.filter(func(u): return u.d.dmg > 0); harvs = units.filter(func(u): return u.d.harv); others = others.filter(func(u): return not u.d.scrap)
	if hit != null and hit.team != 0:
		if combat.size(): S.attack_order(combat, hit); ring(hit.x, hit.y, Color("ff5a52")); sfx("click")
		if hit.kind == "b" and engs.size(): S.eng_order(engs, hit); ring(hit.x, hit.y, Color("7fd68e")); sfx("click")
		if others.size(): S.group_move(others, hit.x, hit.y, "move")
		buzz(12); amove = false; update_cmd(); tut.ev("attack"); return
	var ti := clampi(int(wy / T), 0, 63) * 64 + clampi(int(wx / T), 0, 63)
	if harvs.size() and S.ore[ti] > 0:
		for h in harvs: h.pref = ti; h.hs = "find"
		ring(wx, wy, Color("f0b93f"))
	elif harvs.size(): S.group_move(harvs, wx, wy, "move")
	if combat.size() or others.size():
		S.group_move(combat + others, wx, wy, "amove" if (amove and combat.size()) else "move", face, width)
		ring(wx, wy, Color("ff5a52") if amove else Color("7fd68e"))
	sfx("ack"); buzz(12); amove = false; update_cmd(); tut.ev("move")

func box_select(x0: float, y0: float, x1: float, y1: float) -> void:
	var us := _box_units(Vector2(x0, y0), Vector2(x1, y1))
	var cb := us.filter(func(u): return not u.d.harv)
	if cb.size(): us = cb
	sel_src = ""   # part of ALL or of a squad, picked by hand: its next order makes it a squad
	S.set_sel(us)
	if us.size(): sfx("click"); buzz(8); tut.ev("box"); tut.ev("select", us)

## A swipe that started on one of your units: every unit of yours within BRUSH of the finger's path from a to b is
## added to the pick, and the selection follows live (harvesters only when nothing else was swept).
func _paint(a: Vector2, b: Vector2) -> void:
	V.update_cam()
	var rad := BRUSH_RADAR if V.radar_on else BRUSH
	var grew := false
	for e in S.ents:
		if not e.alive or e.kind != "u" or e.team != 0 or e.captive or e.intun > 0 or gest.picked.has(e.id): continue
		var p3 := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0) + (0.0 if V.radar_on else D.UH[e.type] * .45))
		if p3.z < 0: continue
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p3.x, p3.y), a, b)
		if q.distance_to(Vector2(p3.x, p3.y)) < rad: gest.picked[e.id] = e; grew = true
	if not grew: return
	var us: Array = gest.picked.values().filter(func(u): return u.alive)
	var cb := us.filter(func(u): return not u.d.harv)
	if cb.size(): us = cb
	sel_src = ""; S.set_sel(us); buzz(4)

func _box_units(a: Vector2, b: Vector2) -> Array:
	V.update_cam()
	var x0 := a.x; var y0 := a.y; var x1 := b.x; var y1 := b.y
	var r := Rect2(Vector2(min(x0, x1), min(y0, y1)), Vector2(abs(x1 - x0), abs(y1 - y0))).grow(6)
	return S.ents.filter(func(e):
		if not e.alive or e.kind != "u" or e.team != 0 or e.captive or e.intun > 0: return false
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + .2 + (D.ALT if e.d.air else 0.0))
		return p.z > 0 and r.has_point(Vector2(p.x, p.y)))

# ---------------- input ----------------
func _in_view(p: Vector2) -> bool:
	return V.view_rect().has_point(p)

func _unhandled_input(ev: InputEvent) -> void:
	if S.teams.is_empty() or paused or cut.active: return
	if ev is InputEventScreenTouch:
		if ev.pressed: _down(ev.index, ev.position, false, 0)
		else: _up(ev.index, ev.position, ev.canceled)
	elif ev is InputEventScreenDrag:
		_move(ev.index, ev.position)
	elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if ev.pressed: _zoom_at(ev.position, 1.12 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12)
			return
		if ev.pressed: _down(-1, ev.position, true, ev.button_index)
		else: _up(-1, ev.position, false)
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION:
		if ptrs.has(-1): _move(-1, ev.position)
		elif placing != null and _in_view(ev.position):
			var w := V.s2w(ev.position.x, ev.position.y); var d: Dictionary = D.BLD[placing.type]
			placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))
	elif ev is InputEventKey:
		var k: String = OS.get_keycode_string(ev.keycode).to_lower()
		keys[k] = ev.pressed
		if ev.pressed and not ev.echo and ev.keycode >= KEY_1 and ev.keycode <= KEY_5: squad_tap(ev.keycode - KEY_0)
		if ev.pressed and ev.keycode == KEY_ESCAPE:
			if placing != null: end_placing()
			elif amove: amove = false; update_cmd()
			elif rally_aim: rally_aim = false; update_cmd()
			else: S.set_sel([])

func _zoom_at(p: Vector2, f: float) -> void:
	var w := V.s2w(p.x, p.y)
	V.cam_z *= f; V.clamp_cam()
	var w2 := V.s2w(p.x, p.y)
	V.cam_x += w.x - w2.x; V.cam_y += w.y - w2.y; V.clamp_cam()

func _down(id: int, p: Vector2, mouse: bool, button: int) -> void:
	if not _in_view(p): return
	ptrs[id] = p
	if ptrs.size() == 2:
		var v := ptrs.values(); var a: Vector2 = v[0]; var b: Vector2 = v[1]
		var m := (a + b) / 2
		# the world point under the fingers' midpoint stays under it: moving both fingers pans the map;
		# spreading them zooms, but only past a dead zone so a two-finger pan does not drift the zoom
		gest = {"mode": "pinch", "d0": max(1.0, a.distance_to(b)), "z0": V.cam_z, "w": V.s2w(m.x, m.y), "zoom": false, "upd": {}}
		_clear_preview(); return
	if ptrs.size() > 2: return
	gest = {"mode": "pending", "s": p, "e": p, "l": p, "mouse": mouse, "btn": button, "t0": Time.get_ticks_msec()}
	if V.radar_k() >= 0.5 and placing == null and (not mouse or button == MOUSE_BUTTON_LEFT):
		var n := rd.badge_at(p)
		if n > 0: gest.mode = "bpending"; gest.n = n; return
	if mouse and (button == MOUSE_BUTTON_MIDDLE or button == MOUSE_BUTTON_RIGHT): gest.mode = "rpending"
	elif not mouse and placing == null:
		# a finger that lands on one of your units swipes them up if it moves; elsewhere it drags the map
		var w := V.s2w(p.x, p.y); var h := pick(p.x, p.y, w.x, w.y)
		gest.own = h != null and h.team == 0 and h.kind == "u"

func _sel_movers() -> Array:
	return S.sel.filter(func(e): return e.kind == "u" and not e.d.harv)

func _move(id: int, p: Vector2) -> void:
	if not ptrs.has(id): return
	ptrs[id] = p
	if gest == null: return
	if gest.mode == "pinch":
		if ptrs.size() < 2: return
		var v := ptrs.values(); var a: Vector2 = v[0]; var b: Vector2 = v[1]
		var m := (a + b) / 2
		var dd: float = max(1.0, a.distance_to(b))
		# fingers report one at a time: judge the spread only once both have moved, or a fast pan
		# (one finger ahead of the other) looks like a pinch
		gest.upd[id] = true
		if not gest.zoom and gest.upd.size() >= 2:
			gest.upd = {}
			if abs(dd / gest.d0 - 1) > .12: gest.zoom = true; gest.d0 = dd; gest.z0 = V.cam_z
		if gest.zoom: V.cam_z = gest.z0 * dd / gest.d0; V.clamp_cam()
		var w2 := V.s2w(m.x, m.y); V.cam_x += gest.w.x - w2.x; V.cam_y += gest.w.y - w2.y; V.clamp_cam()
		return
	# a finger wobbles more than a mouse: a touch must travel further before a tap turns into a drag
	var moved: bool = p.distance_to(gest.s) > (9.0 if gest.mouse else 14.0)
	if gest.mode == "pending" and moved:
		if gest.mouse: gest.mode = "box"
		elif placing != null:
			gest.mode = "ghost"; gest.g0 = Vector2(placing.tx, placing.ty); gest.w0 = V.s2w(gest.s.x, gest.s.y)
		elif gest.get("own", false):
			gest.mode = "paint"; gest.picked = {}; gest.trail = [gest.s]; _paint(gest.s, gest.s)
		elif V.radar_k() >= 0.5: gest.mode = "box"   # radar: nothing to scroll, one finger boxes
		else: gest.mode = "pan"
	elif gest.mode == "bpending" and moved: gest.mode = "bdrag"
	elif gest.mode == "rpending" and moved:
		gest.mode = "face" if (gest.btn == MOUSE_BUTTON_RIGHT and _sel_movers().size() and placing == null) else "pan"
		if gest.mode == "face": gest.from = V.s2w(gest.s.x, gest.s.y)
	match gest.mode:
		"pan":
			var a := V.s2w(gest.l.x, gest.l.y); var b := V.s2w(p.x, p.y)
			V.cam_x += a.x - b.x; V.cam_y += a.y - b.y; V.clamp_cam()
		"box", "bdrag": gest.e = p
		"paint":
			_paint(gest.l, p); gest.e = p
			if gest.trail.back().distance_to(p) > 6: gest.trail.append(p)
			if gest.trail.size() > 48: gest.trail.pop_front()
		"ghost":
			# the building moves with the finger from where it was, so it can be dragged from below without hiding it
			var dw: Vector2 = (V.s2w(p.x, p.y) - gest.w0) / T
			placing.tx = int(gest.g0.x + round(dw.x)); placing.ty = int(gest.g0.y + round(dw.y))
		"face":
			gest.e = p
			_face_preview()
	if gest.mouse and placing != null and gest.mode != "pan":
		var w := V.s2w(p.x, p.y); var d: Dictionary = D.BLD[placing.type]
		placing.tx = int(round(w.x / T - d.w / 2.0)); placing.ty = int(round(w.y / T - d.h / 2.0))
	gest.l = p

func _face_params():
	var from: Vector2 = gest.from; var to := V.s2w(gest.e.x, gest.e.y)
	if from.distance_to(to) < T * 0.6: return null
	return {"from": from, "to": to, "ang": atan2(to.y - from.y, to.x - from.x) - PI / 2, "width": from.distance_to(to) / T}

## The drag line is the front of the formation; the troops face across it (left of the drag direction, so a left-to-right drag faces up the screen).
func _face_preview() -> void:
	var fp = _face_params()
	if fp == null: _clear_preview(); return
	var movers := _sel_movers()
	var mid: Vector2 = (fp.from + fp.to) / 2
	var plan := S.plan_formation(movers, mid.x, mid.y, fp.ang, fp.width)
	preview_slots = plan.map(func(p): return p[1])
	pv_from = fp.from; pv_to = fp.to

func _clear_preview() -> void:
	preview_slots = []; pv_from = null; pv_to = null

func _up(id: int, p: Vector2, cancel: bool) -> void:
	if not ptrs.has(id): return
	ptrs.erase(id)
	if gest == null: return
	if gest.mode == "pinch":
		if ptrs.is_empty(): gest = null
		else: gest.mode = "dead"
		return
	if gest.mode == "dead":
		if ptrs.is_empty(): gest = null
		return
	if cancel: gest = null; _clear_preview(); return
	match gest.mode:
		"pending", "bpending": tap(p.x, p.y, false)
		"bdrag": radar_send(gest.n, p)
		"rpending":
			if placing != null: end_placing()
			elif gest.btn == MOUSE_BUTTON_RIGHT: tap(p.x, p.y, true)
		"paint":
			_paint(gest.l, p)
			if S.sel.size(): sfx("click"); buzz(8); tut.ev("box"); tut.ev("select", S.sel)
		"box":
			var sz: Vector2 = (gest.e - gest.s).abs()
			if not gest.mouse and _box_units(gest.s, gest.e).is_empty():
				# an empty box from a finger keeps the selection; a short one was a shaky tap
				if sz.x < 48 and sz.y < 48: tap(gest.s.x, gest.s.y, false)
			else: box_select(gest.s.x, gest.s.y, gest.e.x, gest.e.y)
		"face":
			var fp = _face_params()
			var units := S.sel.filter(func(e): return e.kind == "u")
			if fp == null: tap(gest.s.x, gest.s.y, gest.mouse)
			elif units.size():
				var mid: Vector2 = (fp.from + fp.to) / 2
				command(null, mid.x, mid.y, units, fp.ang, fp.width)
	gest = null; _clear_preview()

func key_pan(dt: float) -> void:
	var s := 700.0 / V.cam_z * dt; var mv := false
	if keys.get("a", false) or keys.get("left", false): V.cam_x -= s; mv = true
	if keys.get("d", false) or keys.get("right", false): V.cam_x += s; mv = true
	if keys.get("w", false) or keys.get("up", false): V.cam_y -= s; mv = true
	if keys.get("s", false) or keys.get("down", false): V.cam_y += s; mv = true
	if mv: V.clamp_cam()

## While a Vanguard prefab is being placed: the edge of every Signal source, so the player sees where it may land.
func _draw_signal(c: Control) -> void:
	for b in S.ents:
		if not (b.alive and b.kind == "b" and b.team == 0 and b.d.signal > 0): continue
		var pts := PackedVector2Array(); var gh: float = S.h_at(b.x, b.y) + .08
		for i in 49:
			var a := TAU * i / 48.0
			var q := V.w2s(b.x + cos(a) * b.d.signal * T, b.y + sin(a) * b.d.signal * T, gh)
			if q.z < 0: pts = PackedVector2Array(); break
			pts.append(Vector2(q.x, q.y))
		if pts.size() > 2: c.draw_polyline(pts, Color(0.5, 0.9, 1.0, 0.55), 2.0, true)

## While a Choir growth is being placed: the edge of the Hum.
func _draw_hum(c: Control) -> void:
	for b in S.hums[0]:
		if not b.alive: continue
		var pts := PackedVector2Array(); var gh: float = S.h_at(b.x, b.y) + .08
		for i in 49:
			var a := TAU * i / 48.0
			var q := V.w2s(b.x + cos(a) * b.d.hum * T, b.y + sin(a) * b.d.hum * T, gh)
			if q.z < 0: pts = PackedVector2Array(); break
			pts.append(Vector2(q.x, q.y))
		if pts.size() > 2: c.draw_polyline(pts, Color(0.55, 1.0, 0.65, 0.55), 2.0, true)

# ---------------- HUD drawing ----------------
func draw_hud(c: Control) -> void:
	if S.teams.is_empty() or U.overlays.start.visible:
		U.radar_tint.visible = false; return
	var f: Font = U.f_disp
	var rk := V.radar_k()
	U.radar_tint.visible = rk > 0.0
	if rk > 0.0: (U.radar_tint.material as ShaderMaterial).set_shader_parameter("k", rk)
	rd.drag_n = gest.n if gest != null and gest.mode == "bdrag" else 0
	if rd.drag_n: rd.drag_p = gest.e
	rd.draw(c, self, rk)
	for e in S.ents:
		if V.radar_on: break   # radar: icons and badges instead of health bars
		if not e.alive or not (e.sel or e.hit_t > 0 or (e.sh_max > 0 and e.sh < e.sh_max) or (e.kind == "b" and (e.repairing or (e.upg >= 0 and e.team == 0)))): continue
		if e.team != 0 and not S.visible_to_player(e): continue
		var is_b: bool = e.kind == "b"
		var top: float = D.BH[e.type] + .25 if is_b else D.UH[e.type] + .15 + (D.ALT if e.d.air else 0.0)
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + top)
		if p.z < 0: continue
		var q := V.w2s(e.x + T, e.y, S.h_at(e.x, e.y) + top); var ppt: float = abs(q.x - p.x)
		var w: float = max(24.0, e.w * ppt * .85) if is_b else max(18.0, e.r / T * 2 * ppt + 8)
		var x := p.x - w / 2; var y := p.y - 4; var fr: float = max(0.0, e.hp / e.max_hp)
		_hp_bar(c, Rect2(x, y, w, 4 if is_b else 3), fr, D.MINI_COL[e.team] if e.team < D.MINI_COL.size() else Color.WHITE, is_b)
		if e.sh_max > 0:
			# Aegis shield: a thin bright bar over the hull bar
			c.draw_rect(Rect2(x - 1, y - 4, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y - 3, w * e.sh / e.sh_max, 2), Color("9ff3ff"))
		if is_b and e.dark and e.team == 0 and sin(S.time * 5) > -0.3:
			c.draw_string(U.f_disp7, Vector2(p.x - 28, y - 8), "NO SIGNAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff6a5a"))
		if e.kind == "u" and e.d.harv and e.sel:
			c.draw_rect(Rect2(x - 1, y + 4, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y + 5, w * e.load / D.HARV_CAP, 2), Color("f0b93f"))
		if is_b and e.upg >= 0 and (e.team == 0 or e.sel):
			c.draw_rect(Rect2(x - 1, y + 5, w + 2, 4), Color(0, 0, 0, .75)); c.draw_rect(Rect2(x, y + 6, w * e.upg, 2), Color("f0b93f"))
		if is_b and e.repairing:
			c.draw_string(U.f_disp7, Vector2(p.x - 5, y - 5 + sin(S.time * 6) * 2), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("7fd68e"))
	if placing != null and D.rule(S.fac_of(0), "place") == "signal": _draw_signal(c)
	if D.rule(S.fac_of(0), "place") == "hum" and (placing != null or S.sel.any(func(e): return e.team == 0 and e.d.get("hum", 0.0) > 0)): _draw_hum(c)
	_draw_mission_marks(c)
	# floating "+N" aurite numbers (refinery deliveries, sales)
	for p in S.parts:
		if p.k != "txt": continue
		var fr: float = p.life / p.max
		var q: Vector3 = V.w2s(p.x, p.y, S.h_at(p.x, p.y) + p.h + (1 - fr) * .8)
		if q.z < 0: continue
		var col: Color = p.c; col.a = min(1.0, fr * 2.2)
		var tw: float = f.get_string_size(p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		c.draw_string_outline(f, Vector2(q.x - tw / 2, q.y), p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, .7 * col.a))
		c.draw_string(f, Vector2(q.x - tw / 2, q.y), p.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	if gest != null and gest.mode == "box":
		var r := Rect2(Vector2(min(gest.s.x, gest.e.x), min(gest.s.y, gest.e.y)), Vector2(abs(gest.e.x - gest.s.x), abs(gest.e.y - gest.s.y)))
		c.draw_rect(r, Color(.5, .84, .56, .12)); c.draw_rect(r, Color("7fd68e"), false, 1.5)
	if gest != null and gest.mode == "paint" and gest.trail.size() > 0:
		# the swipe's brush: a soft wide stroke behind the finger
		var pts := PackedVector2Array(gest.trail + [gest.e])
		if pts.size() > 1: c.draw_polyline(pts, Color(.94, .77, .33, .28), (BRUSH_RADAR if V.radar_on else BRUSH) * 2.0, true)
		c.draw_circle(gest.e, 10, Color(1, .88, .54, .6))
	if sw_aim: _order_banner(c, "launch", "SUPERWEAPON: TAP A TARGET", Color(.94, .73, .25))
	elif amove: _order_banner(c, "atk", "ATTACK-MOVE: TAP A DESTINATION", Color(.95, .32, .28))
	elif jump_aim: _order_banner(c, "jump", "JUMP: TAP WHERE TO LAND", Color(.56, .84, .48))
	elif rally_aim: _order_banner(c, "move", "RALLY: TAP WHERE NEW UNITS GATHER", Color(.56, .84, .48))
	elif gest != null and gest.mode == "face" and pv_from != null: _order_banner(c, "form", "RELEASE TO FORM UP FACING THIS WAY", Color(.56, .84, .48))

## Health bar over a unit or building: dark frame, team-coloured cap, fill from green to red, quarter ticks.
func _hp_bar(c: Control, r: Rect2, fr: float, team: Color, big: bool) -> void:
	c.draw_rect(r.grow(1.5), Color(0, 0, 0, .78))
	c.draw_rect(r, Color(0.12, 0.13, 0.1, 0.9))
	var col := Color("8fcf7a") if fr > .6 else (Color("f0c23f") if fr > .3 else Color("ff5a52"))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * fr, r.size.y)), col)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * fr, 1)), col.lightened(0.35))
	if r.size.x >= 30:
		var n := 8 if big and r.size.x > 70 else 4
		for i in range(1, n): c.draw_rect(Rect2(r.position.x + r.size.x * i / n, r.position.y, 1, r.size.y), Color(0, 0, 0, .55))
	c.draw_rect(Rect2(r.position.x - 1.5, r.position.y - 1.5, 3, r.size.y + 3), team)

## A plate at the bottom centre naming the order the next tap gives.
func _order_banner(c: Control, g: String, txt: String, col: Color) -> void:
	var vr := V.view_rect(); var f: Font = U.f_disp
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w := tw + 52; var r := Rect2(maxf(8.0, vr.size.x / 2 - w / 2), vr.end.y - U.ins_b - 48, w, 32)
	c.draw_style_box(UI.cut(Color(0.055, 0.062, 0.045, 0.9), Color(col, 0.8), 1, 8, 0), r)
	c.draw_rect(Rect2(r.position.x, r.position.y + 8, 3, r.size.y - 8), col)
	UI.glyph(c, g, Rect2(r.position.x + 14, r.position.y + 8, 16, 16), col)
	c.draw_string(f, Vector2(r.position.x + 38, r.position.y + 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.3))

## Campaign markers over the 3D view: hero chevrons, prisoners, convoy trucks, targets, objective labels.
func _draw_mission_marks(c: Control) -> void:
	if S.mission == null: return
	var f: Font = U.f_disp7
	var g = S.goal()
	var tg: Array = S.goal_targets(g) if g != null and (g.k == "kill" or g.k == "capture") else []
	for e in S.ents:
		if not e.alive: continue
		var hero: bool = e.kind == "u" and e.d.hero
		if not (hero or e.captive or e.tag == "vip" or tg.has(e)): continue
		if e.team != 0 and not S.visible_to_player(e): continue
		if e.captive and S.vis[int(e.y / T) * 64 + int(e.x / T)] == 0: continue
		var top: float = (D.BH[e.type] + .55) if e.kind == "b" else (D.UH[e.type] + .5 + (D.ALT if e.d.air else 0.0))
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + top)
		if p.z < 0: continue
		var bob := sin(S.time * 4 + e.id) * 2
		if e.captive:
			c.draw_string_outline(f, Vector2(p.x - 4, p.y + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0, 0, 0, .8))
			c.draw_string(f, Vector2(p.x - 4, p.y + bob), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("f0b93f"))
		elif tg.has(e):
			var col := Color("ff5a52") if g.k == "kill" else Color("f0b93f")
			var q := Vector2(p.x, p.y - 4 + bob)
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0)]), Color(0, 0, 0, .6))
			c.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -7), q + Vector2(5, 0), q + Vector2(0, 7), q + Vector2(-5, 0)]), col)
		elif hero:
			var col: Color = Color("f0b93f") if e.team == 0 else Color("ff5a52")
			var q := Vector2(p.x, p.y + bob * .5)
			for k in 2:
				var o := Vector2(0, k * 5)
				c.draw_polyline(PackedVector2Array([q + o + Vector2(-7, -3), q + o + Vector2(0, 3), q + o + Vector2(7, -3)]), Color(0, 0, 0, .7), 4)
				c.draw_polyline(PackedVector2Array([q + o + Vector2(-7, -3), q + o + Vector2(0, 3), q + o + Vector2(7, -3)]), col, 2)
		else:
			c.draw_rect(Rect2(p.x - 4, p.y - 4 + bob * .5, 8, 8), Color(0, 0, 0, .7))
			c.draw_rect(Rect2(p.x - 3, p.y - 3 + bob * .5, 6, 6), Color("e4ebee"))
	for m in S.marks():
		var q := V.w2s(m[0] * T + 16, m[1] * T + 16, S.h_at(m[0] * T + 16, m[1] * T + 16) + 1.6)
		if q.z < 0 or g == null or g.label == "": continue
		var txt: String = g.label.to_upper()
		var tw: float = U.f_disp.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		c.draw_string_outline(U.f_disp, Vector2(q.x - tw / 2, q.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 4, Color(0, 0, 0, .75))
		c.draw_string(U.f_disp, Vector2(q.x - tw / 2, q.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("f0b93f"))

# ---------------- build icons ----------------
func render_icons(fac: String) -> void:
	icons_for = fac
	var vp := SubViewport.new(); vp.size = Vector2i(112, 88); vp.own_world_3d = true; vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new(); cam.fov = 30; vp.add_child(cam)
	var l := DirectionalLight3D.new(); l.light_energy = 1.0; vp.add_child(l); l.position = Vector3(-3, 6, 4); l.look_at(Vector3.ZERO)
	var env := Environment.new(); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("c8cfd6"); env.ambient_light_energy = .9
	env.background_mode = Environment.BG_CLEAR_COLOR
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	Models.material.set_shader_parameter("fog_on", 0.0)
	var dir := Vector3(.75, .75, 1).normalized()
	for k in U.items:
		var it = U.items[k]
		var m := Models.get_model("b" if it.cat == "bld" else "u", it.type, 0, fac)
		if it.cat != "bld": m.rotation.y = .5
		vp.add_child(m)
		var bb := AABB(); var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			if not (mi as Node3D).is_visible_in_tree(): continue
			var a: AABB = (m.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if m.is_inside_tree() else mi.get_aabb()
			a = m.transform * a
			bb = a if first else bb.merge(a); first = false
		var ctr := bb.get_center(); var sz := bb.size
		var L: float = max(sz.x, max(sz.y * 1.2, sz.z))
		cam.position = ctr + dir * L * 2.2; cam.look_at(ctr)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		it.icon = ImageTexture.create_from_image(img); it.queue_redraw()
		m.queue_free()
	Models.material.set_shader_parameter("fog_on", 1.0)
	vp.queue_free()

# ---------------- loop ----------------
func _process(delta: float) -> void:
	var dt: float = min(.05, delta)
	if cut.active:
		S.step(dt)
		A.intensity = A.intensity + (S.combat - A.intensity) * min(1.0, dt * 0.5)
		V.render(dt, null, [], null, null)
		cut.tick(dt)
		U.tick(dt)
		return
	if S.teams.size():
		if not paused and not S.over:
			S.step(dt)
			if placing != null and not S.teams[0].prod.bld.ready: end_placing()
		elif S.over: S.upd_parts(dt)
		key_pan(dt)
		A.intensity = A.intensity + (S.combat - A.intensity) * min(1.0, dt * 0.5)
		V.render(dt, placing, preview_slots, pv_from, pv_to)
		hud_tick(dt)
		tut.tick(dt)
	else:
		V.update_cam()
	U.tick(dt)
	safe_t += dt
	if safe_t > 0.5:
		safe_t = 0.0; _apply_safe()

## AF_MODE=voice: each army's announcer over a few events, for a recording (--write-movie). The unit-ready line
## right after "not enough aurite" is meant to be dropped by the anti-spam rules.
func _voice_demo(dir: String) -> void:
	var ev := [[0.8, "Construction complete", "gold", "ready", "built"], [3.2, "Units under attack", "warn", "alert", "units_attack"],
		[6.0, "Insufficient aurite", "warn", "", "no_aurite"], [6.6, "Rifle ready", "", "ready", "unit_ready"],
		[9.0, "Base under attack", "warn", "alert", "base_attack"]]
	for fac in ["vanguard", "ashen", "choir"]:
		play({"fac": fac, "enemy": "", "diff": "normal"})
		var t0 := 0.0
		for e in ev:
			await get_tree().create_timer(e[0] - t0).timeout; t0 = e[0]
			toast(e[1], e[2])
			if e[3] != "": sfx(e[3])
			A.say(e[4])
		await get_tree().create_timer(3.0).timeout
	open_menu()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/pause_menu.png")

# ---------------- automated screenshot test (AF_SHOT=dir) ----------------
func _autotest(dir: String) -> void:
	await get_tree().create_timer(2.0).timeout
	await _shot(dir + "/00_start.png")
	var mode := OS.get_environment("AF_MODE")
	if mode == "splash":
		U.build_splash(); U.set_stage(menu_stage()); U.show_overlay("splash")
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://splash.png")
		await _shot(dir + "/splash.png"); get_tree().quit(); return
	if mode == "menus":
		await _menu_shots(dir); get_tree().quit(); return
	if mode == "reset":
		await _reset_shots(dir); get_tree().quit(); return
	if mode == "camp":
		await _camp_shots(dir); get_tree().quit(); return
	if mode == "icon":
		await _icon_shots(); get_tree().quit(); return
	if mode == "radio":
		await _radio_shots(dir); get_tree().quit(); return
	if mode == "fields":
		await _field_shots(dir); get_tree().quit(); return
	if mode == "squads":
		await _squad_shots(dir); get_tree().quit(); return
	if mode == "radar":
		await _radar_shots(dir); get_tree().quit(); return
	if mode == "ctx":
		await _ctx_shots(dir); get_tree().quit(); return
	if mode == "themes":
		await _theme_shots(dir); get_tree().quit(); return
	if mode == "battle":
		await _battle_shots(dir); get_tree().quit(); return
	if mode == "tut":
		await _tut_shots(dir); get_tree().quit(); return
	if mode == "cine":
		await _cine_shots(dir); get_tree().quit(); return
	if mode == "voice":
		await _voice_demo(dir); get_tree().quit(); return
	if OS.get_environment("AF_CAMP") != "": camp_id = OS.get_environment("AF_CAMP")
	if mode.begins_with("m"):
		open_brief(int(mode.substr(1)))
		await get_tree().create_timer(0.5).timeout
		await _shot(dir + "/01_brief.png")
		begin_mission()
	elif mode == "b":
		await _bld_test(dir); get_tree().quit(); return
	elif mode == "choir":
		await _choir_shots(dir); get_tree().quit(); return
	elif mode == "cards":
		# AF_MODE=cards: field manual pages for a few cards of each army (AF_KEYS=key,key overrides the list)
		var ks := OS.get_environment("AF_KEYS")
		var keys: Array = ks.split(",") if ks != "" else ["tank", "sigmast", "walker", "l_signal", "thrall", "garden", "carillon", "knot", "e:drill", "e:scorpion"]
		for k in keys: tut.seen[k] = true
		tut.open_manual("menu")
		for k in keys:
			var tab: int = 1 if k.begins_with("e:") else (2 if k.begins_with("l_") else 0)
			tut.man_tab = tab; tut.man_sel = k; tut._fill_manual(); U._seg_pick("tut_tab", str(tab))
			await get_tree().create_timer(.5).timeout
			await _shot(dir + "/card_%s.png" % k.replace(":", "_"))
		get_tree().quit(); return
	elif mode == "pact":
		await _pact_shots(dir); get_tree().quit(); return
	elif mode == "vanguard":
		await _vanguard_shots(dir); get_tree().quit(); return
	elif mode == "up":
		await _upgrade_shots(dir); get_tree().quit(); return
	else:
		play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "vanguard", "enemy": OS.get_environment("AF_ENEMY"), "diff": "normal"})
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/02_game.png")
	if OS.get_environment("AF_INPUT") != "":
		await _input_test()
		get_tree().quit(); return
	# fast-forward with both sides on AI
	for i in 20 * 150:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
		if S.over: break
	S.update_vision()
	var army := S.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "u" and not e.d.harv)
	S.set_sel(army)
	if army.size(): V.center_on(army[0].x, army[0].y)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/03_later.png")
	# formation preview
	gest = {"mode": "face", "s": Vector2(300, 300), "e": Vector2(520, 300), "l": Vector2(520, 300), "mouse": true, "btn": 2, "t0": 0, "from": V.s2w(300, 300)}
	_face_preview()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/04_face.png")
	_clear_preview(); gest = null
	V.cam_z = 2.2; V.clamp_cam()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/05_zoom.png")
	for i in 20 * 240:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
		if S.over: break
	var fight = null
	for p in S.proj: fight = p
	if fight: V.center_on(fight.x, fight.y)
	V.cam_z = 1.4; V.clamp_cam()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/06_fight.png")
	print("AUTOTEST time=", S.time, " over=", S.over, " ents=", S.ents.size())
	get_tree().quit()

## AF_MODE=icon: app icons drawn by the menu's own code (UI.Insignia over UI.WarBG), one set per story stage.
## Stage I is the shipped icon (icon.png, Android adaptive icon_fg/icon_bg); every stage also goes to store/icons/
## (stage-N-*.png: 1024 iOS/store icon and the adaptive layers) for the optional icon swap.
func _icon_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://store/icons"))
	for st in 3:
		UI.stage = st
		var full := await _icon_render(1024, true, true, 0.76)
		var fg := await _icon_render(432, false, true, 0.80 * 0.66)
		var bg := await _icon_render(432, true, false, 0.0)
		full.save_png("res://store/icons/stage-%d-1024.png" % (st + 1))
		fg.save_png("res://store/icons/stage-%d-fg.png" % (st + 1)); bg.save_png("res://store/icons/stage-%d-bg.png" % (st + 1))
		if st == 0:
			fg.save_png("res://icon_fg.png"); bg.save_png("res://icon_bg.png"); full.save_png("res://icon_1024.png")
			var small := full.duplicate(); small.resize(192, 192, Image.INTERPOLATE_LANCZOS); small.save_png("res://icon.png")

## One icon layer: the battlefield (bg), the shield (fg, sized as a share of the square), or both, on a transparent canvas.
func _icon_render(n: int, bg: bool, fg: bool, k: float) -> Image:
	var vp := SubViewport.new(); vp.size = Vector2i(n, n); vp.transparent_bg = true; vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new(); root.size = Vector2(n, n); vp.add_child(root)
	if bg:
		var w := UI.WarBG.new(); w.hero = true; w.icon = true; w.t = 3.0; w.size = Vector2(n, n); root.add_child(w)
	if fg:
		var ins := UI.Insignia.new(); ins.chunky = true; var sz := n * k
		ins.size = Vector2(sz, sz) * Vector2(0.86, 1.0); ins.position = Vector2(n, n) * 0.5 - ins.size * Vector2(0.5, 0.40 if UI.stage == 2 else 0.47)
		if UI.stage == 2: ins.scale = Vector2.ONE * 0.92; ins.position += ins.size * 0.04
		root.add_child(ins)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img

## AF_MODE=radio: every speaker's portrait, the radio panel in a mission, then a debrief (sample lines from the
## campaign I script).
func _radio_shots(dir: String) -> void:
	var g := GridContainer.new(); g.columns = 4; g.add_theme_constant_override("h_separation", 24); g.add_theme_constant_override("v_separation", 12)
	g.position = Vector2(40, 30); U.overlays.start.add_child(g)
	for k in D.SPEAKERS:
		var v := VBoxContainer.new(); g.add_child(v)
		var p := UI.Portrait.new(); p.sp = D.SPEAKERS[k]; p.custom_minimum_size = Vector2(150, 150); v.add_child(p)
		v.add_child(U.lbl(D.SPEAKERS[k].name.to_upper(), U.f_wide, 12, D.SPEAKERS[k].flash))
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/01_portraits.png")
	g.queue_free()
	camp_id = "ashen"; brief_i = 0
	play({"mission": D.camp("ashen").missions[0], "level": "normal"})
	await get_tree().create_timer(1.0).timeout
	radio("foreman", "Morning, Vey! Lovely day for a rebellion.")
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/02_radio_typing.png")
	await get_tree().create_timer(2.5).timeout
	await _shot(dir + "/03_radio.png")
	U.radio_q.clear(); U._radio_next()
	radio("dace", "A bonfire? How quaint. Take that hill.", true)
	await get_tree().create_timer(3.0).timeout
	await _shot(dir + "/04_radio_enemy.png")
	S.mission = S.mission.duplicate(); S.mission.debrief = {"win": [{"who": "vey", "say": "Hear that? Bells in every town."}, {"who": "brann", "say": "Kettleford's foundry is yours, girl. Come and use it."}]}
	S.over = true; end_game(true)
	await get_tree().create_timer(1.6).timeout
	await _shot(dir + "/05_debrief.png")

## AF_MODE=tut: the in-campaign tutorial from a fresh start: unit card, pointer lesson, enemy card, drills, a drill
## done, lesson and building cards, the base lesson, the pause menu setting, the field manual, briefing and reset.
func _tut_shots(dir: String) -> void:
	tut.seen = {}; tut.mode = "full"
	camp_id = "ashen"; brief_i = 0
	play({"mission": D.camp("ashen").missions[0], "level": "normal"})
	for i in 100:
		if tut.card_open: break
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/01_card_vey.png")
	tut.close_card()
	await get_tree().create_timer(0.6).timeout
	await _shot(dir + "/02_lesson_select.png")
	var vey := tut._hero()
	S.set_sel([vey]); tut.ev("select", S.sel)
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/03_lesson_move.png")
	var foe: Ent = null
	for e in S.ents:
		if e.alive and e.team == 1 and e.type == "rifle": foe = e; break
	if foe: V.center_on((foe.x + vey.x) / 2, (foe.y + vey.y) / 2)
	tut._show_enemy("e:rifle")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/04_enemy_card.png")
	tut.enemy_box.visible = false
	show_objective()
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/05_drills.png")
	var py: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.type == "pyro": py = e; break
	if foe and py: tut.ev("kill", foe, py)
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/06_drill_done.png")
	tut.queue.clear(); tut.open_card("pyro")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/07_card_pyro.png")
	tut.close_card()
	brief_i = 1
	play({"mission": D.camp("ashen").missions[1], "level": "normal"})
	tut.queue.clear(); tut.step_i = 1; tut.step_on = false
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/08_lesson_build.png")
	tut.open_card("turret")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/09_card_building.png")
	tut.close_card(); tut.open_card("l_groups")
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/10_card_lesson.png")
	tut.close_card()
	open_menu()
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/11_pause.png")
	tut.seen["e:tank"] = true; tut.seen["raider"] = true
	tut.open_manual("menu")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/12_manual.png")
	tut.man_tab = 1; tut.man_sel = "e:tank"; tut._fill_manual(); U._seg_pick("tut_tab", "1")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/13_manual_enemy.png")
	tut.man_tab = 0; tut.man_sel = "arcc"; tut._fill_manual(); U._seg_pick("tut_tab", "0")
	await get_tree().create_timer(0.8).timeout
	await _shot(dir + "/14_manual_locked.png")
	show_start(); camp_id = "ashen"; open_brief(2)
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/15_brief.png")
	show_campaigns()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir + "/16_campaigns.png")

## AF_MODE=menus: one screenshot per menu screen.
func _menu_shots(dir: String) -> void:
	U.show_overlay("skirmish")
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/01_skirmish.png")
	U.btn.camp_tile.pressed.emit()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/01a_campaigns.png")
	U.camp_scroll.scroll_vertical = 0
	await get_tree().create_timer(0.1).timeout
	# drag the mission list: only the list moves, a drag that scrolled does not open a briefing
	var lr := U.camp_scroll.get_global_rect(); var p0 := lr.get_center() + Vector2(0, lr.size.y * 0.3)
	var sv0 := U.camp_scroll.scroll_vertical
	Input.set_emulate_touch_from_mouse(true)  # ScrollContainer only drag-scrolls on touch screens
	_mouse(p0, true); await get_tree().process_frame
	for k in 8:
		_mouse(p0 - Vector2(0, 25 * (k + 1)), true, true); await get_tree().process_frame
	_mouse(p0 - Vector2(0, 200), false); await get_tree().create_timer(0.4).timeout
	Input.set_emulate_touch_from_mouse(false)
	print("MENU list drag scroll ", sv0, " -> ", U.camp_scroll.scroll_vertical, " brief=", U.overlays.brief.visible)
	await get_tree().create_timer(0.2).timeout
	await _shot(dir + "/01b_scrolled.png")
	U.show_overlay("manual")
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/02_manual.png")
	open_brief(0)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/03_brief.png")
	begin_mission()
	await get_tree().create_timer(1.0).timeout
	open_menu()
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/04_pause.png")
	resume()
	S.over = true; end_game(true)
	await get_tree().create_timer(1.6).timeout
	await _shot(dir + "/05_end.png")

## AF_MODE=cine: plays every cutscene (or AF_CINE=id,id) and shoots each shot halfway through, then the game it leads to.
## Run with --fixed-fps 20 so the scene keeps its pace on a slow renderer.
func _cine_shots(dir: String) -> void:
	var ids: Array = Array(OS.get_environment("AF_CINE").split(",", false)) if OS.get_environment("AF_CINE") != "" else Cutscenes.all().keys()
	for id in ids:
		var sc := Cutscenes.scene(id)
		var back := [false]
		start_cutscene(id, func(): back[0] = true)
		var last := -1
		while cut.active:
			await get_tree().process_frame
			if cut.si < sc.shots.size() and cut.si >= 0 and cut.si != last and cut.st >= sc.shots[cut.si].d * 0.6:
				last = cut.si
				await _shot(dir + "/%s_%d.png" % [id, cut.si + 1])
		print("CINE ", id, " done=", back[0])
	# Begin on mission 1 of campaign I: opening (already seen now, so skipped) and intro, then the game
	camp_id = "ashen"; open_brief(0); begin_mission()
	await get_tree().create_timer(1.0).timeout
	cut.skip()
	while cut.active: await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await _shot(dir + "/after_skip.png")
	print("CINE game running=", not paused, " mission=", S.mission.title if S.mission else "")

## AF_MODE=reset: a save with chapter III open, then the reset button (armed, then done) and the start screen after it.
func _reset_shots(dir: String) -> void:
	var d := {"_level": "hard"}
	for C in D.CAMPAIGNS: d[C.id] = C.missions.size()
	var f := FileAccess.open("user://campaigns.json", FileAccess.WRITE); f.store_string(JSON.stringify(d)); f = null
	show_start(); await get_tree().create_timer(0.5).timeout; await _shot(dir + "/1_start_before.png")
	show_campaigns(); await get_tree().create_timer(0.3).timeout
	U.btn.reset.pressed.emit(); await get_tree().create_timer(0.2).timeout; await _shot(dir + "/2_armed.png")
	U.btn.reset.pressed.emit(); await get_tree().create_timer(0.3).timeout; await _shot(dir + "/3_reset.png")
	print("after reset: stage ", menu_stage(), " level ", camp_level(), " file ", _camp_file())
	show_start(); await get_tree().create_timer(0.5).timeout; await _shot(dir + "/4_start_after.png")

## AF_MODE=camp: the campaign menu, then every mission's briefing and its opening view, zoomed out. AF_CAMP picks one campaign.
func _camp_shots(dir: String) -> void:
	for C in D.CAMPAIGNS:
		if OS.get_environment("AF_CAMP") != "" and OS.get_environment("AF_CAMP") != C.id: continue   # AF_CAMP=choir: one campaign only
		show_start(); pick_campaign(C.id)
		await get_tree().create_timer(0.4).timeout
		await _shot(dir + "/%s_menu.png" % C.id)
		for i in C.missions.size():
			open_brief(i)
			await get_tree().create_timer(0.3).timeout
			await _shot(dir + "/%s_%d_brief.png" % [C.id, i + 1])
			begin_mission()
			for k in 60:
				S.step(0.05)
			await get_tree().create_timer(1.0).timeout
			await _shot(dir + "/%s_%d_start.png" % [C.id, i + 1])
			paused = true
			V.cam_z = 0.5; V.clamp_cam(); V.fog_clear(true)
			var m = S.marks()
			if m.size(): V.center_on(m[0][0] * T, m[0][1] * T)
			await get_tree().create_timer(0.5).timeout
			await _shot(dir + "/%s_%d_wide.png" % [C.id, i + 1])
			paused = true

## AF_MODE=battle: two armies meet in the open; shots a few moments apart show muzzle flashes, smoke, fire and wrecks.
func _battle_shots(dir: String) -> void:
	play({"fac": "vanguard", "enemy": "ashen", "diff": "normal", "seed": 4242})
	for v in S.vis.size(): S.vis[v] = 2
	var hq: Ent = S.find_hq(0)
	var x0: float = hq.x + T * 8; var y0: float = hq.y - T * 10
	for i in 6:
		for t in [[0, "tank", 0.0], [1, "tank", 4.0], [0, "rifle", -1.0], [1, "rifle", 5.0]]:
			var u := S.spawn_unit(t[0], t[1], x0 + i * T * .9, y0 + float(t[2]) * T)
			u.ang = -PI / 2 if t[0] == 0 else PI / 2; u.tang = u.ang
	S.update_vision(); V.fog_clear(true)
	V.cam_z = 1.5; V.center_on(x0 + T * 2.5, y0 + T * 2)
	for k in 4:
		await get_tree().create_timer(1.2).timeout
		await _shot(dir + "/battle_%d.png" % k)

## AF_MODE=themes: the same skirmish map drawn in each of the six map themes, near and zoomed out (ground and decor checks).
func _theme_shots(dir: String) -> void:
	play({"fac": "vanguard", "enemy": "ashen", "diff": "normal", "seed": 4242})
	paused = true
	for v in S.vis.size(): S.vis[v] = 2
	S.update_vision(); V.fog_clear(true)
	var hq: Ent = S.find_hq(0)
	for th in D.THEMES:
		S.theme = th; V.build_world()
		for z in [[1.2, "near"], [2.6, "far"]]:
			V.cam_z = z[0]; V.center_on(hq.x + T * 3, hq.y - T * 4)
			await get_tree().create_timer(.35).timeout
			await _shot(dir + "/theme_%s_%s.png" % [th, z[1]])
		# the nearest river bank to the base
		var best := Vector2(-1, -1); var bd := 1e9
		for i in S.terr.size():
			if S.terr[i] == D.WATER:
				var p := Vector2(i % 64, i / 64); var dd := p.distance_to(Vector2(hq.tx, hq.ty))
				if dd < bd: bd = dd; best = p
		if best.x >= 0:
			V.cam_z = 1.6; V.center_on(best.x * T, best.y * T)
			await get_tree().create_timer(.35).timeout
			await _shot(dir + "/theme_%s_river.png" % th)

## AF_MODE=ctx: the side panel following the selection, for each army (AF_FAC=one to pick): nothing selected (the
## Yard's list), each producer with an order queued, a building with orders of its own, units, an enemy, and the
## hidden panel peeking out for a building. Prints what each context shows for the test log.
func _ctx_shots(dir: String) -> void:
	var facs := [OS.get_environment("AF_FAC")] if OS.get_environment("AF_FAC") != "" else ["ashen", "vanguard", "choir"]
	for fac in facs:
		play({"fac": fac, "enemy": "choir" if fac != "choir" else "ashen", "diff": "normal"})
		await get_tree().create_timer(6.0).timeout   # the build icons render a couple of frames each
		for i in 20 * 240:
			S.step(0.05)
			if i % 20 == 0: S.ai_think(S.teams[0])
		S.teams[0].auto = false
		S.teams[0].credits = 9000
		var hq := S.find_hq(0)
		V.cam_z = 1.0; V.center_on(hq.x + 40, hq.y + 20)
		S.set_sel([]); update_cmd()
		var bq := ""
		for k in U.items:
			if U.items[k].visible and not U.items[k].locked: bq = U.items[k].type; break
		if bq != "": click_item("bld", bq)
		for i in 30: S.step(0.05)
		refresh_panel(true)
		await get_tree().create_timer(0.5).timeout
		if placing != null: end_placing()   # a structure that finished early waits as READY instead
		S.set_sel([hq]); update_cmd()
		await get_tree().create_timer(0.5).timeout
		print("CTX ", fac, " yard ring: ", U.ring.secs.map(func(s): return s.key))
		await _shot(dir + "/%s_1_yard.png" % fac)
		S.set_sel([]); update_cmd()
		await get_tree().create_timer(0.3).timeout
		await _shot(dir + "/%s_1c_none.png" % fac)
		var n := 2
		for bt in producers:
			if bt == "hq": continue
			var own := S.ents.filter(func(e): return e.alive and e.team == 0 and e.kind == "b" and e.type == bt)
			if own.is_empty(): print("CTX ", fac, " ", bt, ": none built"); continue
			prod_chip_tap(bt)
			if n == 2: cmd_btn("loop")
			for k in U.items:
				var it = U.items[k]
				if it.visible and not it.locked and it.cat != "bld": click_item(it.cat, it.type); click_item(it.cat, it.type); break
			for i in 10: S.step(0.05)
			refresh_panel(true)
			await get_tree().create_timer(0.4).timeout
			print("CTX ", fac, " ", bt, " tabs=", prod_cats(bt), ": ", U.ring.secs.map(func(s): return s.key), " head=", U.ctx_name.text, " / ", U.ctx_sub.text)
			await _shot(dir + "/%s_%d_%s.png" % [fac, n, bt]); n += 1
		# a producer shortcut: the Yard's half ring with the selection and the map left alone, caught mid-turn
		S.set_sel([]); update_cmd()
		U.ring.toggle_dock("hq")
		await get_tree().create_timer(0.4).timeout
		print("CTX ", fac, " shortcut hq: ", U.ring.secs.map(func(s): return s.key))
		await _shot(dir + "/%s_%d_shortcut_yard.png" % [fac, n]); n += 1
		U.ring.scroll_to = U.ring._max_scroll(); U.ring.scroll = U.ring.scroll_to - 0.45   # caught mid-turn
		await RenderingServer.frame_post_draw
		U.ring.scrolling = true; U.ring.scroll = U.ring.scroll_to - 0.45; U.ring._layout()
		await _shot(dir + "/%s_%d_shortcut_yard_turning.png" % [fac, n]); n += 1
		U.ring.scrolling = false
		U.ring.toggle_dock("hq")
		# a building with orders of its own (Hearth: Muster; else an upgradable one)
		var other: Ent = null
		for e in S.ents:
			if e.alive and e.team == 0 and e.kind == "b" and not producers.has(e.type) and (e.d.get("muster", 0) > 0 or not S.upg_def(e).is_empty()): other = e; break
		if other:
			S.set_sel([other]); V.center_on(other.x, other.y); update_cmd()
			await get_tree().create_timer(0.4).timeout
			print("CTX ", fac, " building ", other.type, " ring=", U.ring.secs.map(func(s): return s.key))
			await _shot(dir + "/%s_%d_building.png" % [fac, n]); n += 1
		# units: a few of the main infantry (Thralls: enough to fuse)
		var inf: String = S.tr_t(0, "rifle")
		var special: String = {"vanguard": "jump", "ashen": "scrapper", "choir": "thrall"}[fac]
		var us := []
		for i in 3: us.append(S.spawn_unit(0, inf, hq.x + 60 + i * 12, hq.y + 70))
		for i in 2: us.append(S.spawn_unit(0, special, hq.x + 60 + i * 12, hq.y + 86))
		us = us.filter(func(e): return e != null)
		S.set_sel(us); V.center_on(hq.x + 60, hq.y + 60); update_cmd()
		cmd_btn("hold")
		if fac == "vanguard": cmd_btn("jump")
		await get_tree().create_timer(0.4).timeout
		print("CTX ", fac, " units head=", U.ctx_name.text, " wheel=", U.wheel.secs.map(func(s): return s.key))
		await _shot(dir + "/%s_%d_units.png" % [fac, n]); n += 1
		print("CTX ", fac, " hold=", us.filter(func(u): return u.hold).size(), " jump_aim=", jump_aim)
		if jump_aim:
			var jt := us.filter(func(u): return u.d.jump > 0)
			var p0 := Vector2(jt[0].x, jt[0].y)
			var sp := V.w2s(p0.x + 5 * T, p0.y, S.h_at(p0.x + 5 * T, p0.y)); tap(sp.x, sp.y, false)
			for i in 30: S.step(0.05)
			print("CTX jump moved ", Vector2(jt[0].x, jt[0].y).distance_to(p0) / T, " tiles, cooldown cap ", U.btn.jump.cap)
		cmd_btn("scatter"); cmd_btn("hold")
		S.set_sel([]); update_cmd()

func _ctx_items() -> Array:
	var out := []
	for k in U.items:
		if U.items[k].visible: out.append(U.items[k].type)
	return out

## AF_MODE=radar: radar mode. A skirmish with five squads spread over the map and enemies at two of them; shots from
## today's closest zoom out to the whole map (near, the blend, radar), then real touches: tap badge 2, tap badge 3 (both
## selected, squads unchanged), tap the enemy (both attack, still squads 2 and 3), drag badge 1 elsewhere (only squad
## 1 moves, the selection stays), a one-finger box, a double-tap (no dive), a swipe from an icon. The log lines start with RADAR.
func _radar_shots(dir: String) -> void:
	seed(7)
	play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "ashen", "enemy": "vanguard", "diff": "normal"})
	for i in 20 * 240:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
	S.teams[0].auto = false
	var types := {}
	for e in S.ents:
		if Squads.eligible(e) and not e.d.eng: types[e.type] = true
	var pk: Array = types.keys()
	if pk.size() < 2: pk = ["rifle", "brute", "grenadier", "boars", "scorpion"].filter(func(t): return D.UN.has(t) and not D.UN[t].get("no", []).has(S.fac_of(0)))
	var etypes := ["tank", "lancer", "rifle", "buggy"]
	var spots := [Vector2(22 * T, 30 * T), Vector2(38 * T, 40 * T), Vector2(14 * T, 38 * T), Vector2(30 * T, 18 * T), Vector2(46 * T, 50 * T)]
	var sizes := [9, 7, 5, 6, 4]
	for g in 5:
		var part := []
		for i in sizes[g]:
			var u := S.spawn_unit(0, pk[(g + i) % pk.size()], spots[g].x + randf_range(-50, 50), spots[g].y + randf_range(10, 90))
			if u != null: part.append(u)
		S.set_sel(part); sel_src = ""; command(null, spots[g].x, spots[g].y, part)
	var foes := []
	for i in 6: foes.append(S.spawn_unit(1, etypes[i % 4], 30 * T + randf_range(-40, 40), 13 * T + randf_range(-40, 40)))
	for i in 4: foes.append(S.spawn_unit(1, etypes[i % 4], 47 * T + randf_range(-40, 40), 44 * T + randf_range(-40, 40)))
	for i in 20 * 8: S.step(0.05)
	S.set_sel([]); _squad_chips(); update_cmd()
	print("RADAR squads ", sq.list.map(func(q): return [q.n, q.ids.size()]))
	var shots := [["1_near", 0.5], ["2_blend", 0.42], ["3_radar", V.Z_MIN]]
	for z in shots:
		V.cam_z = z[1]; V.center_on(28 * T, 34 * T)
		await get_tree().create_timer(0.5).timeout
		await _shot(dir + "/radar_" + z[0] + ".png")
		print("RADAR zoom ", z[1], " k=", V.radar_k(), " on=", V.radar_on, " badges ", rd.badges.size())
	var bpos := func(n: int) -> Vector2:
		for b in rd.badges:
			if b.n == n: return (b.rect as Rect2).get_center()
		return Vector2(-1, -1)
	var tap_at := func(p: Vector2) -> void:
		_touch(0, p, true); await get_tree().process_frame; _touch(0, p, false); await get_tree().process_frame
	await tap_at.call(bpos.call(2)); await get_tree().create_timer(0.45).timeout
	await tap_at.call(bpos.call(3)); await get_tree().create_timer(0.45).timeout
	var n2 := sq.members(S, 2).size(); var n3 := sq.members(S, 3).size()
	print("RADAR badges 2+3 selected ", S.sel.size(), " of ", n2 + n3, " src ", sel_src)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/radar_4_two_squads.png")
	var f: Ent = foes.filter(func(e): return e != null and e.alive)[0]
	f.x = sq.members(S, 2)[0].x; f.y = sq.members(S, 2)[0].y + 120
	for i in 10: S.step(0.05)
	var fp3 := V.w2s(f.x, f.y, S.h_at(f.x, f.y)); var fp := Vector2(fp3.x, fp3.y)
	print("RADAR enemy visible ", S.visible_to_player(f))
	await tap_at.call(fp); await get_tree().create_timer(0.45).timeout
	print("RADAR order on enemy: orders ", S.sel.map(func(e): return e.order), " squads ", sq.list.map(func(q): return [q.n, q.ids.size()]), " sel ", S.sel.size())
	# drag badge 1 to an empty spot: only squad 1 moves, the selection stays on squads 2 and 3
	var b1: Vector2 = bpos.call(1); var to := b1 + Vector2(-60, 80); var keep := S.sel.size()
	_touch(0, b1, true); await get_tree().process_frame
	for i in 6:
		_drag(0, b1.lerp(to, (i + 1) / 6.0)); await get_tree().process_frame
	await _shot(dir + "/radar_5_drag_badge.png")
	_touch(0, to, false); await get_tree().process_frame
	print("RADAR drag badge 1: squad 1 orders ", sq.members(S, 1).map(func(e): return e.order), " sel kept ", S.sel.size() == keep, " squads ", sq.list.map(func(q): return [q.n, q.ids.size()]))
	for i in 20: S.step(0.05)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/radar_6_orders.png")
	# one finger drags a box around squad 4
	var c4 := Vector2(); var m4 := sq.members(S, 4)
	for e in m4:
		var q := V.w2s(e.x, e.y, S.h_at(e.x, e.y)); c4 += Vector2(q.x, q.y)
	c4 /= max(1, m4.size())
	var a := c4 + Vector2(-45, -40); var bb := c4 + Vector2(45, 40)
	_touch(0, a, true); await get_tree().process_frame
	for i in 6:
		_drag(0, a.lerp(bb, (i + 1) / 6.0)); await get_tree().process_frame
	_touch(0, bb, false); await get_tree().process_frame
	print("RADAR box: sel ", S.sel.size(), " squad 4 has ", m4.size())
	# double-tap open ground: no dive any more (its first tap sent the army there); pinching in is the way down
	var g3 := V.w2s(8 * T, 12 * T, 0.0); var g := Vector2(g3.x, g3.y)
	var z0 := V.cam_z
	tap(g.x, g.y, false); tap(g.x, g.y, false)   # straight to tap(): the software renderer here is too slow for real double-taps
	await get_tree().create_timer(0.8).timeout
	print("RADAR double-tap: cam_z ", z0, " -> ", V.cam_z, " radar ", V.radar_on)
	# a swipe from one of squad 2's icons picks the icons it passes over
	var m2 := sq.members(S, 2).filter(func(e): return e.alive)
	if m2.size():
		var q2 := V.w2s(m2[0].x, m2[0].y, S.h_at(m2[0].x, m2[0].y)); var s0 := Vector2(q2.x, q2.y)
		_touch(0, s0, true); await get_tree().process_frame
		for i in 6:
			_drag(0, s0 + Vector2(8 * (i + 1), 4 * (i + 1))); await get_tree().process_frame
		_touch(0, s0 + Vector2(48, 24), false); await get_tree().process_frame
		print("RADAR swipe from an icon: sel ", S.sel.size(), " src '", sel_src, "'")
	await _shot(dir + "/radar_7_swipe.png")

## AF_MODE=squads: the squad strip. Three squads formed by orders (one under fire, one idle), fresh units in NEW,
## squad 1 selected with JOIN showing, then a mixed selection with its type chips. AF_FAC picks the army.
func _squad_shots(dir: String) -> void:
	play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "ashen", "enemy": "vanguard", "diff": "normal"})
	for i in 20 * 150:
		S.step(0.05)
		if i % 20 == 0: S.ai_think(S.teams[0])
	S.teams[0].auto = false
	var c := Vector2(S.p0.x * T + 16, (S.p0.y - 1) * T)
	var army := S.ents.filter(func(e): return Squads.eligible(e) and not e.d.eng and e.intun <= 0)
	for t in army.map(func(e): return e.type).slice(-2):   # a few more of the rarer types, so three squads fit
		for i in 3: S.spawn_unit(0, t, c.x + randf_range(-40, 40), c.y + randf_range(20, 60))
	army = S.ents.filter(func(e): return Squads.eligible(e) and not e.d.eng and e.intun <= 0)
	var by := {}
	for e in army: by[e.type] = by.get(e.type, []) + [e]
	var types := by.keys(); types.sort_custom(func(a, b): return by[a].size() > by[b].size())
	print("SQUADS army ", army.size(), " types ", types.map(func(t): return [t, by[t].size()]))
	# squad 1: the biggest type plus one of the second (mixed), squad 2: the rest of the second, squad 3: two of the third
	var s1: Array = by[types[0]].slice(0, 6) + (by[types[1]].slice(0, 2) if types.size() > 1 else [])
	S.set_sel(s1); command(null, c.x + 60, c.y + 30, s1)
	if types.size() > 1 and by[types[1]].size() > 3:
		var s2: Array = by[types[1]].slice(2, 5)
		S.set_sel(s2); command(null, c.x + 120, c.y - 40, s2)
	if types.size() > 2 and by[types[2]].size() >= 2:
		var s3: Array = by[types[2]].slice(0, 2)
		S.set_sel(s3); command(null, c.x - 40, c.y + 60, s3)
	for i in 60: S.step(0.05)
	var q2 = sq.find(2)
	if q2 != null:
		for e in sq.members(S, 2): e.hit_t = 3.0; e.hp = e.max_hp * 0.45
	print("SQUADS ", sq.list.map(func(q): return [q.n, q.ids.size()]), " new ", sq.fresh(S).size())
	S.set_sel([]); squad_tap(1); V.center_on(c.x + 60, c.y + 30)
	_squad_chips(); update_cmd()
	await get_tree().create_timer(0.6).timeout
	await _shot(dir + "/squads_1_join.png")
	S.set_sel(sq.members(S, 1)); sel_src = ""; update_cmd()
	await get_tree().create_timer(0.3).timeout
	print("SQUADS type chips ", U.type_btns.filter(func(b): return b.visible).map(func(b): return b.text))
	join_btn()
	await get_tree().create_timer(0.4).timeout
	await _shot(dir + "/squads_2_joined.png")
	squad_tap(0)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir + "/squads_3_all_types.png")

## AF_MODE=fields: living fields. One ore field fresh, one tired (half its vitality), one killed (grey stumps).
func _field_shots(dir: String) -> void:
	play({"fac": "vanguard", "diff": "normal", "seed": 4242})
	paused = true
	for i in D.MW * D.MH: S.vis[i] = 2
	V.fog_clear(true)
	# group ore tiles into fields by flood fill, then pick three
	var seen := {}; var fields: Array = []
	for i in D.MW * D.MH:
		if S.ore[i] <= 0 or seen.has(i): continue
		var f: Array = []; var q := [i]; seen[i] = true
		while q.size():
			var c: int = q.pop_back(); f.append(c)
			for o in [1, -1, D.MW, -D.MW]:
				var n: int = c + o
				if n >= 0 and n < D.MW * D.MH and S.ore[n] > 0 and not seen.has(n): seen[n] = true; q.append(n)
		fields.append(f)
	fields.sort_custom(func(a, b): return a.size() > b.size())
	var names := ["fresh", "tired", "dead"]
	for k in mini(3, fields.size()):
		for i in fields[k]:
			if k == 1: S.take_ore(i, S.ore[i] * 6 / 10, 80.0)
			if k == 2: S.take_ore(i, S.ore[i], 100.0)
	V.upd_ore()
	for k in mini(3, fields.size()):
		var c: int = fields[k][fields[k].size() / 2]
		V.cam_z = 1.6; V.center_on((c % D.MW) * T + 16.0, (c / D.MW) * T + 16.0)
		await get_tree().create_timer(.4).timeout
		await _shot(dir + "/field_%s.png" % names[k])

## AF_MODE=b: every building model, then the build, sell and collapse animations and a harvester at work.
func _bld_test(dir: String) -> void:
	play({"fac": OS.get_environment("AF_FAC") if OS.get_environment("AF_FAC") != "" else "vanguard", "diff": "normal"})
	paused = true
	var hq: Ent = S.ents.filter(func(e): return e.team == 0 and e.type == "hq")[0]
	var bs: Array = []
	for t in D.ALLB:
		if t == "wall" or not S.avail(0, t): continue
		var sp = S.ai_spot(0, t, hq)
		if sp == null: continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
		S.update_vision()
	S.update_vision(); V.fog_clear(true)
	await get_tree().create_timer(.5).timeout
	for b in [hq] + bs:
		V.cam_z = 2.4; V.center_on(b.x, b.y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/b_%s.png" % b.type)
	var f: Ent = bs.filter(func(e): return e.type == "factory")[0]
	V.cam_z = 1.9; V.center_on(f.x, f.y)
	for k in [.15, .4, .7, .95]:
		f.born = S.time - k * 2.2
		await get_tree().create_timer(.15).timeout
		await _shot(dir + "/build_%d.png" % int(k * 100))
	f.born = -9.0
	S.produce_done(S.teams[0], "tank"); S.time += .5
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/door.png")
	var ref := S.sell(f)
	print("BLDTEST sold for ", ref)
	for k in 3:
		S.time += .5
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/sell_%d.png" % k)
	var p: Ent = bs.filter(func(e): return e.type == "power")[0]
	V.center_on(p.x, p.y)
	S.kill(p)
	for k in 3:
		S.time += .45
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/die_%d.png" % k)
	if not S.avail(0, "harv"): return
	paused = false
	var hv = null
	for e in S.ents:
		if e.alive and e.type == "harv": hv = e
	for i in 20 * 40:
		S.step(.05)
		if hv.hs == "mine": break
	V.cam_z = 2.2; V.center_on(hv.x, hv.y)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/mine.png")
	hv.load = D.HARV_CAP
	for i in 20 * 60:
		S.step(.05)
		if hv.hs == "unload": break
	V.center_on(hv.x, hv.y - 20)
	await get_tree().create_timer(.7).timeout
	await _shot(dir + "/unload.png")
	print("BLDTEST done hs=", hv.hs, " parts=", S.parts.size())

## AF_MODE=up: for each faction, every upgradable building next to its upgraded twin, then the scaffold while an
## upgrade runs, the reveal and the selected building's UPGRADE button.
func _upgrade_shots(dir: String) -> void:
	for fac in D.FAC_ORDER:
		play({"fac": fac, "enemy": "ashen" if fac != "ashen" else "vanguard", "diff": "normal", "seed": 4242})
		paused = true
		var hq: Ent = S.find_hq(0)
		var pairs: Array = []
		for t in D.UPG:
			if not S.avail(0, t): continue
			var two: Array = []
			var d: Dictionary = D.BLD[t]; var spot = null
			# side by side on open ground near the yard
			for r in range(4, 22):
				for a in 24:
					var x := hq.tx + int(round(cos(TAU * a / 24.0) * r)); var y := hq.ty + int(round(sin(TAU * a / 24.0) * r))
					var ok := true
					for yy in range(y - 1, y + d.h + 1):
						for xx in range(x - 1, x + d.w * 2 + 2):
							if not S.inb(xx, yy) or S.terr[yy * D.MW + xx] >= D.ROCK or S.ore[yy * D.MW + xx] > 0 or S.bmap[yy * D.MW + xx]: ok = false
					if ok: spot = Vector2i(x, y); break
				if spot != null: break
			if spot == null: continue
			for k in 2:
				var b := S.add_building(0, t, spot.x + k * (d.w + 1), spot.y); b.born = -9.0; two.append(b)
			S.update_vision()
			if two.size() == 2:
				S.finish_upgrade(two[1]); two[1].up_t = -99.0; pairs.append(two)
		S.update_vision(); V.fog_clear(true)
		await get_tree().create_timer(.5).timeout
		for two in pairs:
			V.cam_z = 2.4 - 0.3 * two[0].w; V.center_on((two[0].x + two[1].x) / 2, (two[0].y + two[1].y) / 2)
			await get_tree().create_timer(.25).timeout
			await _shot(dir + "/%s_%s.png" % [fac, two[0].type])
		if fac != "vanguard": continue
		# a reactor mid-upgrade, selected, with the button showing progress; then the reveal
		var p: Ent = pairs[0][0]
		S.teams[0].credits = 5000.0; S.add_building(0, "refinery", hq.tx - 6, hq.ty + 4)
		S.set_sel([p]); S.start_upgrade(p); p.upg = .42
		V.cam_z = 1.6; V.center_on(p.x, p.y)
		await get_tree().create_timer(.4).timeout
		await _shot(dir + "/upgrading.png")
		S.set_sel([]); S.finish_upgrade(p)
		for k in 3:
			S.time += .35
			await get_tree().create_timer(.2).timeout
			await _shot(dir + "/reveal_%d.png" % k)
		S.time += 2.0
		var fr: Ent = pairs.filter(func(two): return two[0].type == "factory")[0][0]
		S.set_sel([fr]); update_cmd()
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/button.png")

## AF_MODE=pact: the Ashen Pact's base, every Pact unit in rows, a boar charge, a wreck being revived by a Scrapper,
## and the HUD with the unit cap and the Hearth's MUSTER button.
## AF_MODE=vanguard: the Vanguard base inside its Signal, each prefab, the roster, a delivery landing and the HUD.
func _vanguard_shots(dir: String) -> void:
	play({"fac": "vanguard", "enemy": "ashen", "diff": "normal", "seed": 4242})
	paused = true
	S.teams[0].credits = 9000.0
	for v in S.vis.size(): S.vis[v] = 2
	var hq: Ent = S.find_hq(0)
	var bs: Array = []
	for t in ["sigmast", "barracks", "lz", "drill", "uplink", "sentry", "pdl", "dome", "sigmast", "bastion", "skyfall"]:
		var sp = S.ai_spot(0, t, hq)
		if sp == null: print("no spot for ", t); continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
	S.update_vision(); V.fog_clear(true)
	V.cam_z = 1.1; V.center_on(hq.x + T * 2, hq.y - T * 2)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/v1_base.png")
	var seen := {}
	for b in bs:
		if seen.has(b.type): continue
		seen[b.type] = true
		V.cam_z = 2.6; V.center_on(b.x, b.y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/v_b_%s.png" % b.type)
	var x0: float = (hq.tx + 6) * T; var y0: float = (hq.ty - 14) * T
	var rows := [["rifle", "lancer", "ranger", "medic", "jump", "k9", "engineer"], ["buggy", "tank", "railtank", "walker"], ["spotter", "hornets", "hornets", "skyhawk", "dropship"]]
	for ri in rows.size():
		var row: Array = rows[ri]
		for i in row.size():
			var u := S.spawn_unit(0, row[i], x0 + i * T * (1.1 if ri == 0 else 2.0), y0 + ri * T * 2.4); u.ang = PI * .75; u.tang = u.ang
			if row[i] == "dropship": u.captive = true
	V.cam_z = 3.4; V.center_on(x0 + T * 3.4, y0)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/v2_infantry.png")
	V.cam_z = 2.6; V.center_on(x0 + T * 3, y0 + T * 2.4)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/v3_vehicles.png")
	V.cam_z = 2.2; V.center_on(x0 + T * 4, y0 + T * 3.4)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/v4_air.png")
	# a delivery on its way in, shields under fire
	var lz: Ent = bs.filter(func(e): return e.type == "lz")[0]
	var ship := S.send_dropship(S.teams[0], "pk_strike", lz)
	ship.x = lz.x - T * 4; ship.y = lz.y - T * 2
	var tk: Ent = S.ents.filter(func(e): return e.alive and e.type == "tank")[0]
	S.damage(tk, 90.0, "shell", null); S.set_sel([tk, S.ents.filter(func(e): return e.alive and e.type == "walker")[0]])
	paused = false
	for i in 12: S.step(.05)
	paused = true
	V.cam_z = 1.7; V.center_on(lz.x, lz.y)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/v5_delivery.png")
	# placing a prefab: the Signal rings
	S.teams[0].prod.bld.cur = "sentry"; S.teams[0].prod.bld.ready = true; S.teams[0].prod.bld.prog = 1.0
	start_placing("sentry")
	V.cam_z = 0.9; V.center_on(hq.x + T * 3, hq.y - T * 3)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/v6_signal.png")
	end_placing()

func _pact_shots(dir: String) -> void:
	play({"fac": "ashen", "enemy": "vanguard", "diff": "normal", "seed": 4242})
	paused = true
	S.teams[0].credits = 9000.0
	var hq: Ent = S.find_hq(0)
	var bs: Array = []
	for t in ["kiln", "kiln", "smelter", "muster", "hearth", "workshop", "works", "mast", "hammer", "hearth", "pylon", "rift"]:
		var sp = S.ai_spot(0, t, hq)
		if sp == null: continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
		S.update_vision()
	S.update_vision(); V.fog_clear(true)
	V.cam_z = 1.1; V.center_on(hq.x + T * 2, hq.y - T * 2)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/p1_base.png")
	var seen := {}
	for b in [hq] + bs:
		if seen.has(b.type): continue
		seen[b.type] = true
		V.cam_z = 2.4; V.center_on(b.x, b.y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/p_b_%s.png" % b.type)
	var x0: float = (hq.tx + 6) * T; var y0: float = (hq.ty - 14) * T
	var rows := [["militia", "brute", "grenadier", "pyro", "scrapper", "boars", "boars", "boars"],
		["raider", "scorpion", "anvilf", "anvila", "kettle", "howler", "crawler"], ["jugg", "arcc", "gyro", "zeppelin"]]
	for ri in rows.size():
		var row: Array = rows[ri]
		for i in row.size():
			var u := S.spawn_unit(0, row[i], x0 + i * T * (1.1 if ri == 0 else 1.7), y0 + ri * T * 2.2); u.ang = PI * .75; u.tang = u.ang
	S.update_vision()
	V.cam_z = 3.4; V.center_on(x0 + T * 4, y0)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/p2_infantry.png")
	V.cam_z = 2.6; V.center_on(x0 + T * 5, y0 + T * 2.2)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/p3_vehicles.png")
	V.cam_z = 2.4; V.center_on(x0 + T * 3, y0 + T * 4.4)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/p4_heavy_air.png")
	# a boar charge into a Vanguard squad, and a wreck a Scrapper is reviving
	var ex: float = x0 + T * 2; var ey: float = y0 - T * 6
	var foes: Array = []
	for i in 4:
		var f := S.spawn_unit(1, "rifle", ex + i * T, ey); f.hp *= 4; f.max_hp *= 4; foes.append(f)
	var tk := S.spawn_unit(1, "tank", ex + T * 6, ey + T * 2)
	S.kill(tk)
	var boars := S.ents.filter(func(e): return e.alive and e.type == "boars")
	S.attack_order(boars, foes[1])
	var sc: Ent = S.ents.filter(func(e): return e.alive and e.type == "scrapper")[0]
	S.scrap_order([sc], S.wrecks[0])
	S.update_vision(); paused = false
	for i in 20 * 3: S.step(.05)
	paused = true
	V.cam_z = 1.9; V.center_on(ex + T * 3, ey + T * 1)
	await get_tree().create_timer(.5).timeout
	await _shot(dir + "/p5_charge_wreck.png")
	# the river: a Slipway on the shore and a River Ironclad afloat
	var best := -1; var bd := 1e9
	for i in S.MW * S.MH:
		if S.terr[i] == D.WATER:
			var dd := Vector2(i % S.MW - hq.tx, i / S.MW - hq.ty).length()
			if dd < bd: bd = dd; best = i
	if best >= 0:
		var wx: int = best % S.MW; var wy: int = best / S.MW
		for v in S.vis.size(): S.vis[v] = 2
		for r in range(1, 6):
			var placed := false
			for oy in range(-r, r + 1):
				for ox in range(-r, r + 1):
					if not placed and S.can_place(0, "slipway", wx + ox, wy + oy, false):
						var sw := S.add_building(0, "slipway", wx + ox, wy + oy); sw.born = -9.0; placed = true
			if placed: break
		var deep := Vector2i(wx, wy); var dn := 0
		for oy in range(-4, 5):
			for ox in range(-4, 5):
				var n := 0
				for ay in range(-2, 3):
					for ax in range(-2, 3):
						if S.passable(1, wx + ox + ax, wy + oy + ay): n += 1
				if n > dn and S.passable(1, wx + ox, wy + oy): dn = n; deep = Vector2i(wx + ox, wy + oy)
		var ic := S.spawn_unit(0, "ironclad", deep.x * T + 16, deep.y * T + 16); ic.ang = PI * .75; ic.tang = ic.ang
		S.update_vision(); V.fog_clear(true)
		V.cam_z = 3.0; V.center_on((wx + deep.x) * T / 2.0, (wy + deep.y) * T / 2.0)
		await get_tree().create_timer(.4).timeout
		await _shot(dir + "/p8_river.png")
	# the HUD: unit cap and the Hearth's MUSTER button
	var hearth: Ent = bs.filter(func(e): return e.type == "hearth")[0]
	S.set_sel([hearth]); update_cmd()
	V.cam_z = 1.6; V.center_on(hearth.x, hearth.y)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/p6_hud_muster.png")
	cmd_btn("muster")
	paused = false
	for i in 20 * 2: S.step(.05)
	paused = true
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/p7_mustered.png")

## AF_MODE=choir: the Hollow Choir's base inside its Hum, a Garden at each age, every form, mutations, the Hollowing,
## a fusion and the HUD with its Pods.
func _choir_shots(dir: String) -> void:
	play({"fac": "choir", "enemy": "vanguard", "diff": "normal", "seed": 4242})
	paused = true
	S.teams[0].credits = 9000.0
	for v in S.vis.size(): S.vis[v] = 2
	var hq: Ent = S.find_hq(0)
	var bs: Array = []
	for t in ["garden", "garden", "garden", "spire", "burrow", "spire", "chorus"]:
		var sp = S.ai_spot(0, t, hq, true)
		if sp == null: print("no spot for ", t); continue
		var b := S.add_building(0, t, sp.x, sp.y); b.born = -9.0; bs.append(b)
	var gs: Array = bs.filter(func(e): return e.type == "garden")
	if gs.size() > 1: S.finish_upgrade(gs[1])
	if gs.size() > 2:
		S.finish_upgrade(gs[2]); S.finish_upgrade(gs[2])
	for g in gs: g.up_t = -9.0; g.pods = 2
	for k in 4:
		if S.can_place(0, "thorn", hq.tx - 2 + k, hq.ty + 5, false): S.add_building(0, "thorn", hq.tx - 2 + k, hq.ty + 5).born = -9.0
	S.calc_hum(); S.update_vision(); V.fog_clear(true)
	S.set_sel([hq])
	V.cam_z = 0.9; V.center_on(hq.x + T * 2, hq.y - T * 2)
	await get_tree().create_timer(.6).timeout
	await _shot(dir + "/c1_base_hum.png")
	S.set_sel([])
	var nm := ["sprout", "bloom", "cathedral"]
	for i in gs.size():
		V.cam_z = 2.4; V.center_on(gs[i].x, gs[i].y - T * 0.5)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/c_garden_%s.png" % nm[i])
	V.cam_z = 2.2; V.center_on(hq.x, hq.y - T * 0.4)
	await get_tree().create_timer(.25).timeout
	await _shot(dir + "/c_b_hq.png")
	for t in ["spire", "burrow", "chorus"]:
		var l: Array = bs.filter(func(e): return e.type == t)
		if l.is_empty(): continue
		V.cam_z = 2.4; V.center_on(l[0].x, l[0].y)
		await get_tree().create_timer(.25).timeout
		await _shot(dir + "/c_b_%s.png" % t)
	V.cam_z = 2.6; V.center_on((hq.tx) * T, (hq.ty + 5.5) * T)
	await get_tree().create_timer(.25).timeout
	await _shot(dir + "/c_b_thorn.png")
	# every form, in rows
	var x0: float = (hq.tx + 6) * T; var y0: float = (hq.ty - 14) * T
	var rows := [["thrall", "wretch", "keener", "sapper", "knot", "cantor"], ["skitter", "mantis", "geode", "carillon"], ["moth", "moth"]]
	var all: Array = []
	for ri in rows.size():
		var row: Array = rows[ri]
		for i in row.size():
			var u := S.spawn_unit(0, row[i], x0 + i * T * (1.2 if ri == 0 else 2.2), y0 + ri * T * 2.6); u.ang = PI * .75; u.tang = u.ang; all.append(u)
	V.cam_z = 3.4; V.center_on(x0 + T * 3.0, y0)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c2_infantry.png")
	V.cam_z = 2.4; V.center_on(x0 + T * 3.3, y0 + T * 2.6)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c3_beasts.png")
	V.cam_z = 3.0; V.center_on(x0 + T * 6.6, y0 + T * 2.4)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c3_carillon.png")
	V.cam_z = 3.4; V.center_on(x0 + T * 1.1, y0 + T * 5.2)
	await get_tree().create_timer(.3).timeout
	await _shot(dir + "/c3_moths.png")
	# mutations: the same forms after three kills
	var mrow := ["thrall", "mantis", "skitter", "knot"]
	for i in mrow.size():
		var a := S.spawn_unit(0, mrow[i], x0 + i * T * 2.4, y0 - T * 3); a.ang = PI * .75
		var m := S.spawn_unit(0, mrow[i], x0 + i * T * 2.4 + T, y0 - T * 3); m.ang = PI * .75; S.mutate(m)
	V.cam_z = 3.0; V.center_on(x0 + T * 4, y0 - T * 3)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c4_mutations.png")
	# an Undertow in the river
	var w = S.shore_near(hq)
	if w != null:
		var best := Vector2i(w.x, w.y); var bn := 0
		for ty in range(w.y - 6, w.y + 7):
			for tx in range(w.x - 6, w.x + 7):
				var n := 0
				for ay in range(-1, 2):
					for ax in range(-1, 2):
						if S.inb(tx + ax, ty + ay) and S.terr[(ty + ay) * D.MW + tx + ax] == D.WATER: n += 1
				if n > bn: bn = n; best = Vector2i(tx, ty)
		var ud := S.spawn_unit(0, "undertow", best.x * T + 16, best.y * T + 16); ud.ang = PI * .75; ud.reveal_t = 1e9
		S.update_vision(); V.fog_clear(true)
		V.cam_z = 3.0; V.center_on(ud.x, ud.y)
		await get_tree().create_timer(.4).timeout
		await _shot(dir + "/c5_undertow.png")
	# the Hollowing: Vanguard troopers die on the crystal by a Garden and get up again
	var g0: Ent = gs[0]; var ot := -1
	for i in D.MW * D.MH:
		if S.ore[i] > 0 and S.in_hum(0, (i % D.MW) * T + 16, (i / D.MW) * T + 16) and Vector2((i % D.MW) * T - g0.x, (i / D.MW) * T - g0.y).length() < T * 4: ot = i; break
	if ot >= 0:
		var fx: float = (ot % D.MW) * T + 16; var fy: float = (ot / D.MW) * T + 16
		for i in 5:
			var f := S.spawn_unit(1, "rifle", fx + (i % 3) * 12 - 12, fy + (i / 3) * 12); f.hp = 6.0 + i * 3
		for i in 3: S.spawn_unit(0, "thrall", fx - T * 2.5, fy + (i - 1) * 14)
		paused = false
		for i in 20 * 3: S.step(.05)
		V.cam_z = 3.0; V.center_on(fx, fy)
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/c6_crystal_cuts.png")
		for i in 20 * 5: S.step(.05)
		await get_tree().create_timer(.3).timeout
		await _shot(dir + "/c6_hollowing.png")
		paused = true
	# fusion: four Thralls selected, the FUSE button, then the Knot
	var fz: Array = []
	for u in all: u.alive = false
	for i in 4: fz.append(S.spawn_unit(0, "thrall", x0 + T * (2 + (i % 2) * 1.1), y0 + T * ((i / 2) * 1.1)))
	S.set_sel(fz); update_cmd()
	V.cam_z = 3.0; V.center_on(x0 + T * 2.3, y0 + T * 0.3)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c7_fuse_button.png")
	cmd_btn("fuse")
	for i in 30: S.step(.05)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c7_knot.png")
	# the HUD: Pods, and a Garden selected with its next age
	S.set_sel([gs[0]]); update_cmd()
	V.cam_z = 1.5; V.center_on(gs[0].x, gs[0].y)
	await get_tree().create_timer(.4).timeout
	await _shot(dir + "/c8_hud_garden.png")
	S.set_sel([])

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("shot ", path)

var mouse_last := Vector2()
func _mouse(p: Vector2, down: bool, motion := false) -> void:
	var e: InputEventMouse
	if motion:
		e = InputEventMouseMotion.new(); e.button_mask = MOUSE_BUTTON_MASK_LEFT
		e.relative = (p - mouse_last) * V.ui_scale()
	else:
		e = InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = down
	e.position = p * V.ui_scale(); e.global_position = e.position; mouse_last = p
	Input.parse_input_event(e)

func _touch(i: int, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = i; e.position = p * V.ui_scale(); e.pressed = down
	Input.parse_input_event(e)

func _drag(i: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = i; e.position = p * V.ui_scale()
	Input.parse_input_event(e)

func _input_test() -> void:
	var r: Ent = null
	for e in S.ents:
		if e.team == 0 and e.type == "rifle": r = e; break
	var p3 := V.w2s(r.x, r.y, S.h_at(r.x, r.y) + .2); var p := Vector2(p3.x, p3.y)
	print("INPUT rifle at ", p, " paused=", paused)
	_touch(0, p, true); await get_tree().process_frame; _touch(0, p, false); await get_tree().process_frame
	print("INPUT single tap sel=", S.sel.size())
	await get_tree().create_timer(0.1).timeout
	_touch(0, p, true); await get_tree().process_frame; _touch(0, p, false); await get_tree().process_frame
	print("INPUT double tap sel=", S.sel.size(), " types=", S.sel.map(func(e): return e.type))
	var g := p + Vector2(150, -60)
	_touch(0, g, true); await get_tree().process_frame; _touch(0, g, false); await get_tree().process_frame
	print("INPUT move order: ", S.sel.map(func(e): return e.order))
	# a swipe from one rifle picks the rifles the finger passes over, even with all of them already selected
	var rifles0 := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "rifle")
	S.set_sel(rifles0); sel_src = "all"; sel_set = rifles0
	var rp3 := V.w2s(r.x, r.y, S.h_at(r.x, r.y) + .2); var rp := Vector2(rp3.x, rp3.y)
	_touch(0, rp, true); await get_tree().process_frame
	for k in 4:
		_drag(0, rp + Vector2(6 * (k + 1), 3 * (k + 1))); await get_tree().process_frame
	print("INPUT swipe mode=", gest.mode if gest else "none", " sel=", S.sel.size(), " of ", rifles0.size())
	await _shot(OS.get_environment("AF_SHOT") + "/02b_swipe.png")
	_touch(0, rp + Vector2(24, 12), false); await get_tree().process_frame
	print("INPUT swipe sel=", S.sel.map(func(e): return e.type), " src '", sel_src, "' (empty: its next order makes a squad)")
	# a hold on open ground, then a drag, just pans (no hidden hold gestures any more)
	var cx := V.cam_x; var nsel := S.sel.size()
	_touch(0, Vector2(400, 300), true); await get_tree().create_timer(0.7).timeout
	for k in 5:
		_drag(0, Vector2(400 - 40 * (k + 1), 300 + 4 * k)); await get_tree().process_frame
	print("INPUT hold then drag on ground mode=", gest.mode if gest else "none")
	_touch(0, Vector2(200, 316), false); await get_tree().process_frame
	print("INPUT hold-drag pan dx=", V.cam_x - cx, " sel ", nsel, " -> ", S.sel.size())
	# two-finger drag pans, without zooming
	var z0 := V.cam_z
	_touch(0, Vector2(380, 280), true); _touch(1, Vector2(420, 320), true); await get_tree().process_frame
	for k in 5:
		var o := Vector2(-40 * (k + 1), 0)
		_drag(0, Vector2(380, 280) + o); _drag(1, Vector2(420, 320) + o + Vector2(k, 0)); await get_tree().process_frame
	_touch(0, Vector2(180, 280), false); _touch(1, Vector2(224, 320), false); await get_tree().process_frame
	print("INPUT two-finger pan dx=", V.cam_x - cx, " zoom ", z0, " -> ", V.cam_z)
	# the corner wheel: with rifles picked its hub is ATTACK; tap it (a real touch), then its squad ALL sector
	var rif := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "rifle")
	S.set_sel(rif); update_cmd(); U.wheel.rebuild()
	var hr = U.wheel.rect_of("amove")
	if hr != null:
		_touch(0, hr.get_center(), true); await get_tree().process_frame; _touch(0, hr.get_center(), false); await get_tree().process_frame
	print("INPUT wheel hub ATTACK amove=", amove, " gest=", gest.mode if gest else "none")
	await _shot(OS.get_environment("AF_SHOT") + "/03_wheel_attack.png")
	if amove: cmd_btn("amove")
	var ar = U.wheel.rect_of("sq_all")
	S.set_sel([]); update_cmd(); U.wheel.rebuild(); ar = U.wheel.rect_of("sq_all")
	if ar != null:
		_touch(0, ar.get_center(), true); await get_tree().process_frame; _touch(0, ar.get_center(), false); await get_tree().process_frame
	print("INPUT wheel ALL sel=", S.sel.size(), " src=", sel_src)
	U.wheel.rebuild()
	print("INPUT corner buttons: ", U.wheel.secs.map(func(s2): return s2.key))
	var srr = U.wheel.rect_of("stop")
	if srr != null and not S.sel.is_empty():
		_touch(0, srr.get_center(), true); await get_tree().process_frame; _touch(0, srr.get_center(), false); await get_tree().process_frame
		print("INPUT corner STOP tapped: sel=", S.sel.size())
	# pinch
	var z := V.cam_z
	_touch(0, Vector2(300, 300), true); _touch(1, Vector2(500, 300), true); await get_tree().process_frame
	for k in 10:
		_drag(0, Vector2(300 - 10 * (k + 1), 300)); _drag(1, Vector2(500 + 10 * (k + 1), 300)); await get_tree().process_frame
	_touch(0, Vector2(200, 300), false); _touch(1, Vector2(600, 300), false); await get_tree().process_frame
	print("INPUT pinch zoom ", z, " -> ", V.cam_z)
	# build a reactor through the panel
	click_item("bld", "power")
	for i in 20 * 9: S.step(0.05)
	click_item("bld", "power")
	print("INPUT placing=", placing)
	confirm_place()
	print("INPUT reactors=", S.count(0, "power"))
	# drag a ready structure out of the Yard's ring onto the map (a real touch on its READY sector)
	V.cam_z = 1.0; V.center_on(S.p0.x * T + 16, (S.p0.y - 1) * T)
	var pt := ""
	for t2 in D.CATS.bld:
		if S.avail(0, t2) and S.has_req(0, D.BLD[t2].req) and not D.BLD[t2].get("kit", 0) and not D.BLD[t2].get("onore", false) and not D.BLD[t2].get("shore", false): pt = t2; break
	click_item("bld", pt)
	for i in 20 * 30: S.step(0.05)
	S.set_sel([S.find_hq(0)]); update_cmd(); refresh_panel(true)
	for k in 3: await get_tree().process_frame
	U.ring.rebuild()
	var rsec = U.ring._find("i:bld:" + pt)
	var ic: Vector2 = U.ring.get_global_transform() * Radial.mid(U.ring.c, rsec.r0, rsec.r1, rsec.a0, rsec.a1) if rsec != null else Vector2()
	print("INPUT ring for yard: ", U.ring.secs.map(func(s2): return s2.key), " ready ", pt, " sector ", ic)
	await _shot(OS.get_environment("AF_SHOT") + "/03b_yard_ring.png")
	var dst := V.s2w(300, 330 - GHOST_LIFT)
	_touch(0, ic, true); await get_tree().process_frame
	for k in 8:
		_drag(0, ic.lerp(Vector2(300, 330), (k + 1) / 8.0)); await get_tree().process_frame
	print("INPUT drag-build placing=", placing)
	_touch(0, Vector2(300, 330), false); await get_tree().process_frame
	var rs := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == pt)
	print("INPUT drag-build ", pt, "=", rs.size(), " last at ", rs.back().x if rs.size() else 0, ",", rs.back().y if rs.size() else 0, " aimed ", dst)
	end_placing()
	# hold-to-queue five, groups, hidden panel with production chips and the big map
	S.teams[0].credits = 9000
	var inf_t: String = D.sub(S.teams[0].fac, "rifle")
	if S.count(0, "barracks") == 0: S.add_building(0, D.sub(S.teams[0].fac, "barracks") if D.BLD.has(D.sub(S.teams[0].fac, "barracks")) else "barracks", 12, 44)
	queue_many("inf", inf_t, 5)
	print("INPUT queue five: ", S.teams[0].prod.inf.queue.size() + (1 if S.teams[0].prod.inf.cur != "" else 0))
	var rifles := S.ents.filter(func(e): return e.alive and e.team == 0 and e.type == "rifle")
	# squads: an order forms squad 1; its chip selects it, a second tap centres the camera on it
	S.set_sel(rifles); command(null, rifles[0].x + 20, rifles[0].y, rifles); S.set_sel([])
	squad_tap(1); print("INPUT squad 1 select: ", S.sel.size(), " of ", rifles.size(), " squads ", sq.list.size())
	V.center_on(D.WW / 2.0, D.WH / 2.0); squad_tap(1)
	print("INPUT squad 1 recentre: cam ", Vector2(V.cam_x, V.cam_y), " squad at ", Vector2(rifles[0].x, rifles[0].y))
	click_item("bld", "power"); S.step(0.5)
	refresh_panel(true)
	await get_tree().create_timer(0.3).timeout
	print("INPUT chips: ", U.prod_chips.keys().filter(func(c): return U.prod_chips[c].visible))
	await _shot(OS.get_environment("AF_SHOT") + "/04_chips_map_groups.png")
	# a structure's ring: a tap outside it closes it; RALLY then a tap sets the rally point
	var bk: Ent = null
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "b" and _rallies(e): bk = e; break
	if bk:
		V.cam_z = 1.0; V.center_on(bk.x, bk.y); S.set_sel([bk]); update_cmd()
		for k in 3: await get_tree().process_frame
		var out := Vector2(V.view_rect().size.x / 2, 70)
		print("INPUT ring open for ", bk.type, ": ", U.ring.secs.size(), " sectors in view, centre ", U.ring.c, " keys ", U.ring.dock_list.map(func(s2): return s2.key))
		_touch(0, out, true); await get_tree().process_frame; _touch(0, out, false); await get_tree().process_frame
		print("INPUT tap outside the ring: sel=", S.sel.size())
		S.set_sel([bk]); update_cmd(); cmd_btn("rally")
		for k in 2: await get_tree().process_frame
		print("INPUT rally aim=", rally_aim, " ring hidden=", U.ring.secs.is_empty() or U.ring.bld == null)
		_touch(0, out, true); await get_tree().process_frame; _touch(0, out, false); await get_tree().process_frame
		print("INPUT rally set=", bk.rally, " sel=", S.sel.size(), " aim=", rally_aim)
	# a producer shortcut: the half ring opens by the column, a finger turns it along the arc, a tap orders, a tap on the
	# map closes it, and neither the selection nor the map moves
	S.set_sel([]); update_cmd()
	var cam0 := Vector2(V.cam_x, V.cam_y)
	var pcy = U.prod_chips.get("hq")
	if pcy != null:
		var cp: Vector2 = pcy.get_global_rect().get_center()
		_touch(0, cp, true); await get_tree().process_frame; _touch(0, cp, false)
		for k in 3: await get_tree().process_frame
		var rg = U.ring; var gt: Transform2D = rg.get_global_transform()
		print("INPUT dock open=", rg.docked, " sectors in view=", rg.secs.size(), " of ", rg.dock_list.size(), " first=", rg.secs.map(func(s2): return s2.key).slice(0, 2))
		var rm: float = (rg.r0 + rg.r1) / 2; var sp: float = PI / rg.vis; var dir := -1.0 if rg.a_start > 0 else 1.0
		var a0: float = -PI / 2 + dir * sp * 2.5
		var steps := 8
		for i in steps + 1:
			var a: float = a0 - dir * sp * 2.0 * float(i) / steps   # drag two sectors' worth towards the top
			var q: Vector2 = gt * (rg.c + Vector2(cos(a), sin(a)) * rm)
			if i == 0: _touch(0, q, true)
			else: _drag(0, q)
			await get_tree().process_frame
		_touch(0, gt * (rg.c + Vector2(cos(a0 - dir * sp * 2.0), sin(a0 - dir * sp * 2.0)) * rm), false)
		await get_tree().create_timer(0.5).timeout
		print("INPUT dock scrolled to=", rg.scroll_to, " scroll=", snappedf(rg.scroll, 0.01), " first=", rg.secs.map(func(s2): return s2.key).slice(0, 2), " queued=", S.teams[0].prod.bld.cur)
		var s0 = null
		for s2 in rg.secs:
			if s2.kind == "item" and not U.items[s2.cat + ":" + s2.type].locked and s2.vf > 0.9: s0 = s2; break
		if s0 != null:
			var tp: Vector2 = gt * Radial.mid(rg.c, s0.r0, s0.r1, s0.a0, s0.a1)
			_touch(0, tp, true); await get_tree().process_frame; _touch(0, tp, false)
			for k in 2: await get_tree().process_frame
			print("INPUT dock tap ", s0.type, ": building=", S.teams[0].prod.bld.cur, " queued=", U.items["bld:" + s0.type].n, " active=", U.items["bld:" + s0.type].active, " sel=", S.sel.size())
		var out2 := Vector2(V.view_rect().size.x / 3, V.view_rect().size.y / 2)
		_touch(0, out2, true); await get_tree().process_frame; _touch(0, out2, false); await get_tree().process_frame
		print("INPUT dock tap outside: open=", rg.docked != "", " sel=", S.sel.size(), " map moved=", Vector2(V.cam_x, V.cam_y).distance_to(cam0) > 1)
	# a READY structure dragged straight off its shortcut onto the map
	var pt2 := ""
	for t2 in D.CATS.bld:
		if S.avail(0, t2) and S.has_req(0, D.BLD[t2].req) and not D.BLD[t2].get("kit", 0) and not D.BLD[t2].get("onore", false) and not D.BLD[t2].get("shore", false) and not S.at_limit(0, t2): pt2 = t2; break
	var q2: Dictionary = S.teams[0].prod.bld
	q2.cur = ""; q2.ready = false
	V.cam_z = 1.0; V.center_on(S.p0.x * T + 16, (S.p0.y - 1) * T)
	click_item("bld", pt2)
	for i in 20 * 40: S.step(0.05)
	for k in 3: await get_tree().process_frame
	var hc = U.prod_chips.get("hq")
	var n0: int = S.count(0, pt2)
	await _shot(OS.get_environment("AF_SHOT") + "/09_shortcut_ready.png")
	print("INPUT shortcut ready ", pt2, "=", q2.ready, " chip ready=", hc.is_ready if hc else null)
	if hc != null:
		var c0: Vector2 = hc.get_global_rect().get_center()
		var to := Vector2(460, 420)   # clear of the structure the drag test above put at (300, 330)
		_touch(0, c0, true); await get_tree().process_frame
		for k in 8:
			_drag(0, c0.lerp(to, (k + 1) / 8.0)); await get_tree().process_frame
		print("INPUT shortcut drag placing=", placing != null, " half ring open=", U.ring.docked != "")
		_touch(0, to, false); await get_tree().process_frame
		for k in 2: await get_tree().process_frame
		print("INPUT shortcut drag-build ", pt2, " ", n0, " -> ", S.count(0, pt2), " placing=", placing != null)

