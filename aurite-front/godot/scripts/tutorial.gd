extends Node
## In-campaign tutorial (approved plan and script, Guillaume 2026-11-19/20): unit cards, enemy cards, pointer lessons,
## optional drills and the unit pages of the field manual. Words and rules are in tutorial_data.gd; this file runs them.
## Owned by main.gd (`main.tut`). Preloaded, no class_name (a self-update pack cannot add global classes).
##
## Settings and progress live in user://tutorial.json: mode (full · cards · off), seen cards ("vey", "e:tank"),
## finished lessons ("L:ashen:0") and drills ("D:ashen:0:1").

const TD := preload("res://scripts/tutorial_data.gd")
const T := 32
const FILE := "user://tutorial.json"
const CARD_GAP := 20.0    # seconds of play between two unit cards
const CALM := 3.0         # a card waits until the player's side has taken no damage for this long
const ENEMY_SHOW := 9.0   # an enemy card stays this long (tap to close it sooner)

var main  # main.gd
var S: Sim
var U: UI
var V: View3D

var mode := "full"
var seen := {}            # card keys, "e:<type>", "L:<camp>:<i>", "D:<camp>:<i>:<j>"

# the running mission
var M = null
var camp := ""
var mi := -1
var made := {}            # type -> how many the player trained or built this mission
var drills: Array = []    # [{d, key, done}]
var lesson = null         # LESSONS entry
var lesson_key := ""
var step_i := -1
var step_on := false
var step_t := 0.0
var step_spot = null      # world point for an "ahead" pointer
var cam0 := Vector3()
var queue: Array = []     # card keys waiting
var last_card := -99.0
var card_open := false
var card_key := ""
var enemy_q: Array = []
var enemy_t := 0.0
var poll_t := 0.0
var pulse_type := ""      # a drill's unit, ringed for a few seconds when the drill appears
var pulse_t := 0.0

# ui
var layer: PtrLayer
var hint_box: UI.Plate
var hint_eye: Label
var hint_l: Label
var card: Control
var card_body: CardBody
var enemy_box: UI.Plate
var enemy_tt: Turntable
var enemy_name: Label
var enemy_text: Label
var enemy_say: Label
var man_list: VBoxContainer
var man_body: CardBody
var man_tab := 0
var man_back := "menu"
var man_sel := ""

# ---------------- settings and progress ----------------
func load_state() -> void:
	mode = "full"; seen = {}
	if not FileAccess.file_exists(FILE): return
	var f := FileAccess.open(FILE, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary: return
	mode = str(d.get("mode", "full"))
	if not TD.TXT.mode.has(mode): mode = "full"
	for k in d.get("seen", []): seen[str(k)] = true

func save_state() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"mode": mode, "seen": seen.keys()}))

func set_mode(m: String) -> void:
	mode = m; save_state()
	if mode == "off": _hide_lesson(); queue.clear(); enemy_q.clear(); enemy_box.visible = false
	elif M != null and mi >= 0 and mode == "full" and drills.is_empty(): _start_extras()
	if mode != "full": drills.clear(); lesson = null; _hide_lesson()
	main.refresh_panel(true)
	_sync_buttons()

## Pause menu button: Full -> Cards only -> Off -> Full.
func cycle_mode() -> void:
	var order := ["full", "cards", "off"]
	set_mode(order[(order.find(mode) + 1) % 3])

## Briefing switch: tips on (Full) or off.
func toggle_tips() -> void:
	set_mode("off" if mode != "off" else "full")

func reset() -> void:
	seen = {}; save_state()
	U.toast(TD.TXT.reset_done)

func _sync_buttons() -> void:
	if U.btn.has("tut_mode"): U.btn.tut_mode.text = (TD.TXT.setting + ": " + TD.TXT.mode[mode]).to_upper()
	if U.btn.has("br_tips"): U.btn.br_tips.text = (TD.TXT.brief_on if mode != "off" else TD.TXT.brief_off).to_upper()

# ---------------- build ----------------
func build() -> void:
	S = main.S; U = main.U; V = main.V
	load_state()
	S.tut_cb = Callable(self, "ev")
	U.obj_l.bbcode_enabled = true
	layer = PtrLayer.new(); layer.tut = self; layer.set_anchors_preset(Control.PRESET_FULL_RECT); layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	U.add_child(layer)
	# lesson hint: bottom centre, above the order buttons
	hint_box = UI.Plate.new(); hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.add_theme_stylebox_override("panel", U.plate_sb(8.0, UI.H_BG2, UI.W_LINE, UI.W_BRASS))
	var hh := HBoxContainer.new(); hh.add_theme_constant_override("separation", 10); hh.mouse_filter = Control.MOUSE_FILTER_IGNORE; hint_box.add_child(hh)
	hh.add_child(U._glyph_box("info", 18, UI.W_BRASS))
	var hv := VBoxContainer.new(); hv.add_theme_constant_override("separation", 0); hv.mouse_filter = Control.MOUSE_FILTER_IGNORE; hh.add_child(hv)
	hint_eye = U.lbl("", U.f_wide, 10, UI.W_BRASS); hv.add_child(hint_eye)
	hint_l = U.lbl("", U.f_body6, 16, UI.W_KHAKI); hv.add_child(hint_l)
	var sk := U.ghost(TD.TXT.skip, func(): skip_lesson(), 40); sk.custom_minimum_size.x = 120; sk.mouse_filter = Control.MOUSE_FILTER_STOP
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hh.add_child(sk)
	hint_box.anchor_left = 0.5; hint_box.anchor_right = 0.5; hint_box.anchor_top = 1; hint_box.anchor_bottom = 1
	hint_box.offset_bottom = -124; hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH; hint_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_box.visible = false; U.hud.add_child(hint_box)
	# enemy card: top right of the view, under the top bar
	enemy_box = UI.Plate.new(); enemy_box.accent = UI.C_BAD; enemy_box.mouse_filter = Control.MOUSE_FILTER_STOP
	enemy_box.add_theme_stylebox_override("panel", U.plate_sb(8.0, UI.H_BG2, UI.W_LINE, UI.C_BAD))
	enemy_box.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: enemy_box.visible = false)
	var eh := HBoxContainer.new(); eh.add_theme_constant_override("separation", 10); eh.mouse_filter = Control.MOUSE_FILTER_IGNORE; enemy_box.add_child(eh)
	enemy_tt = Turntable.new(); enemy_tt.custom_minimum_size = Vector2(84, 84); enemy_tt.mouse_filter = Control.MOUSE_FILTER_IGNORE; eh.add_child(enemy_tt)
	var ev_ := VBoxContainer.new(); ev_.add_theme_constant_override("separation", 1); ev_.mouse_filter = Control.MOUSE_FILTER_IGNORE; eh.add_child(ev_)
	ev_.add_child(U.lbl(TD.TXT.enemy.to_upper(), U.f_wide, 10, Color("ff8a80")))
	enemy_name = U.lbl("", U.f_disp7, 16, UI.W_KHAKI); ev_.add_child(enemy_name)
	enemy_text = U.lbl("", U.f_body, 13, Color("e2dac2")); enemy_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; enemy_text.custom_minimum_size.x = 230; ev_.add_child(enemy_text)
	enemy_say = U.lbl("", U.f_body, 12, UI.W_SAND); enemy_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; enemy_say.custom_minimum_size.x = 230; ev_.add_child(enemy_say)
	enemy_box.anchor_left = 1; enemy_box.anchor_right = 1; enemy_box.offset_right = -8; enemy_box.offset_top = 64
	enemy_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN; enemy_box.visible = false; U.hud.add_child(enemy_box)
	# unit card: modal, the game paused behind a veil
	card = Control.new(); card.set_anchors_preset(Control.PRESET_FULL_RECT); card.mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new(); veil.color = Color(0.02, 0.02, 0.015, 0.62); veil.set_anchors_preset(Control.PRESET_FULL_RECT); veil.mouse_filter = Control.MOUSE_FILTER_IGNORE; card.add_child(veil)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); cc.mouse_filter = Control.MOUSE_FILTER_IGNORE; card.add_child(cc)
	var fr := U.frame(cc, 8)
	card_body = CardBody.new(); card_body.ui = U; card_body.setup(220.0); fr.add_child(card_body)
	var br := HBoxContainer.new(); br.alignment = BoxContainer.ALIGNMENT_END; fr.add_child(br)
	var ok := U.cta(TD.TXT.got_it, func(): close_card()); ok.custom_minimum_size.x = 180; br.add_child(ok)
	card.visible = false; U.add_child(card)
	_build_manual()
	_sync_buttons()

## Field manual, unit pages: tabs (yours, enemy, lessons), a list on the left, the card on the right.
func _build_manual() -> void:
	var c := U._overlay("units", 980, false)
	var d := U.frame(c, 10)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 12); d.add_child(top)
	var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", -4); tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(tv)
	tv.add_child(U.eyebrow("Field manual  //  units and lessons")); tv.add_child(U.title(TD.TXT.manual, 30))
	var bk := U.ghost("Back", func(): U.show_overlay(man_back), 44); bk.custom_minimum_size.x = 120; top.add_child(bk)
	U.seg(d, "tut_tab", [["0", TD.TXT.tabs[0]], ["1", TD.TXT.tabs[1]], ["2", TD.TXT.tabs[2]]], "0", func(v): man_tab = int(v); man_sel = ""; _fill_manual())
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 14); d.add_child(row)
	var sc := ScrollContainer.new(); sc.custom_minimum_size = Vector2(230, 250); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; row.add_child(sc)
	man_list = VBoxContainer.new(); man_list.add_theme_constant_override("separation", 4); man_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(man_list)
	man_body = CardBody.new(); man_body.ui = U; man_body.setup(190.0); man_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(man_body)

func open_manual(back: String) -> void:
	man_back = back
	_fill_manual()
	U.show_overlay("units")

func _manual_keys(tab: int) -> Array:
	var keys: Array = []
	match tab:
		0: keys = TD.CARDS.keys().filter(func(k): return not k.begins_with("l_"))
		1: keys = TD.enemy_types().map(func(k): return "e:" + k)
		2: keys = TD.CARDS.keys().filter(func(k): return k.begins_with("l_"))
	return keys

func _fill_manual() -> void:
	for ch in man_list.get_children(): ch.queue_free()
	var keys := _manual_keys(man_tab)
	if man_sel == "" or not keys.has(man_sel):
		man_sel = ""
		for k in keys:
			if seen.has(k): man_sel = k; break
		if man_sel == "" and keys.size(): man_sel = keys[0]
	for k in keys:
		var known: bool = seen.has(k)
		var nm: String = _entry_name(k) if known else TD.TXT.locked
		var b := U.ghost(nm, func(): man_sel = k; _fill_manual(), 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not known: for kk in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(kk, Color(UI.W_SAND, 0.55))
		if k == man_sel: b.add_theme_stylebox_override("normal", UI.cut(UI.W_SEL, UI.W_BRASS))
		man_list.add_child(b)
	if man_sel != "": man_body.show_key(man_sel, not seen.has(man_sel))

func _entry_name(k: String) -> String:
	if k.begins_with("e:"):
		var t := k.substr(2)
		return TD.enemy_card(t).get("name", D.def_of(t).name)
	return TD.card_name(k)

# ---------------- mission flow ----------------
## Called by main.new_game for every match: campaign missions with tutorial data run it, everything else clears it.
func start(mission) -> void:
	stop()
	if mission == null or not TD.MISSIONS.has(mission.camp): return
	M = mission; camp = mission.camp; mi = mission.idx
	if mode == "off": return
	if mode == "full": _start_extras()
	for k in TD.MISSIONS[camp][mi].get("cards", []):
		if not seen.has(k): queue.append(k)
	last_card = -99.0

func _start_extras() -> void:
	var md: Dictionary = TD.MISSIONS[camp][mi]
	drills = []
	for j in md.get("drills", []).size():
		var key := "D:%s:%d:%d" % [camp, mi, j]
		drills.append({"d": md.drills[j], "key": key, "done": seen.has(key)})
	var ln: String = md.get("lesson", "")
	lesson_key = "L:%s:%d" % [camp, mi]
	if ln != "" and not seen.has(lesson_key):
		lesson = TD.LESSONS[ln]; step_i = 0; step_on = false; step_t = 0.0
	for dr in drills:
		if not dr.done and dr.d.has("ptr"): pulse_type = dr.d.ptr; pulse_t = 6.0; break

func stop() -> void:
	M = null; camp = ""; mi = -1; made = {}; drills = []; lesson = null; step_i = -1; step_on = false
	queue = []; enemy_q = []; pulse_t = 0.0
	if card_open: close_card()
	if hint_box: hint_box.visible = false; enemy_box.visible = false

func active() -> bool:
	return M != null and mode != "off" and S.mission == M

## The objective box's drill lines (bbcode), under the mission objective.
func obj_extra() -> String:
	if not active() or drills.is_empty(): return ""
	var s := "\n[color=#d9a441][font_size=11]%s[/font_size][/color]" % TD.TXT.drill.to_upper()
	for dr in drills:
		s += ("\n[color=#7fd68e]✓ %s[/color]" % dr.d.text) if dr.done else ("\n[color=#c9bd96]•  %s[/color]" % dr.d.text)
	return s

# ---------------- events ----------------
## Things that happen in the game: main.gd (select, move, box, attack, dbl, rally, order, queue5, placing, made, squad, group_recall,
## aim) and the sim (kill, heal, made, eng_fix, upgrade, launch).
func ev(kind: String, a = null, b = null) -> void:
	if not active(): return
	if kind == "made": made[a] = made.get(a, 0) + 1
	# the lesson step waiting for this
	if lesson != null and step_on:
		var dn: Dictionary = lesson.steps[step_i].done
		if dn.has("ev") and dn.ev == kind:
			var ok := true
			if dn.has("type"): ok = a == dn.type
			if dn.get("hero", false): ok = a is Array and a.any(func(e): return e.kind == "u" and e.d.hero)
			if ok: _next_step()
	# drills
	for dr in drills:
		if dr.done: continue
		var c: Dictionary = dr.d.check
		if c.get("ev", "") != kind: continue
		var ok := true
		match kind:
			"kill": ok = b is Ent and b.type == c.by and (not c.get("air", false) or (a.kind == "u" and a.d.air))
			"heal": ok = a is Ent and a.type == c.target
			"made": ok = a == c.type and made.get(a, 0) >= c.get("n", 1)
			"upgrade": ok = a == c.type
			"group_recall": ok = a == c.get("i", 0)
		if ok: _drill_done(dr)

func _drill_done(dr: Dictionary) -> void:
	dr.done = true; seen[dr.key] = true; save_state()
	if M.phq or M.pbase.size():
		S.teams[0].credits += TD.DRILL_BONUS
		U.toast(TD.TXT.drill_done % TD.DRILL_BONUS, "gold")
	else: U.toast(TD.TXT.drill_done_nb, "gold")
	main.sfx("ready")
	main.obj_t = 8.0
	main.refresh_panel(true)

# ---------------- every frame ----------------
func tick(dt: float) -> void:
	if card_open: main.paused = true
	if not active() or S.over: layer.queue_redraw(); return
	if enemy_box.visible:
		enemy_t -= dt
		if enemy_t <= 0: enemy_box.visible = false
	if not main.paused:
		poll_t -= dt
		if poll_t <= 0: poll_t = 0.25; _poll()
		if lesson != null: _lesson_tick(dt)
		if pulse_t > 0: pulse_t -= dt
		_try_card()
		if not enemy_box.visible and enemy_q.size(): _show_enemy(enemy_q.pop_front())
	layer.queue_redraw()

func _poll() -> void:
	# own units and buildings the player meets for the first time
	for e in S.ents:
		if not e.alive or e.team != 0 or e.captive: continue
		var k: String = e.type
		if not TD.CARDS.has(k) or seen.has(k) or queue.has(k): continue
		if _eligible(k): queue.append(k)
	# enemies coming into sight
	var en: Dictionary = TD.ENEMY.get(camp, {})
	for e in S.ents:
		if not e.alive or e.team != 1: continue
		var key: String = "e:" + e.type
		if not en.has(e.type) or seen.has(key) or enemy_q.has(key): continue
		if S.visible_to_player(e): enemy_q.append(key)
	# drills that depend on the state of the field
	for dr in drills:
		if dr.done: continue
		var c: Dictionary = dr.d.check
		if c.has("have") and S.count(0, c.have) >= c.n: _drill_done(dr)
		elif c.get("raid", false) and S.raid_wiped(): _drill_done(dr)
		elif c.has("arrived") and int(S.gst.get("arrived", 0)) >= c.arrived: _drill_done(dr)
		elif c.has("spot") and _spotted(c.spot, c.by): _drill_done(dr)

## A card shows from its home mission on; before that, only for something the player trained or built.
func _eligible(k: String) -> bool:
	var h: Array = TD.CARDS[k].home
	var ci := D.CAMPAIGNS.map(func(C): return C.id).find(h[0])
	var cur := D.CAMPAIGNS.map(func(C): return C.id).find(camp)
	if cur > ci or (cur == ci and mi >= int(h[1])): return true
	return made.has(k)

func _spotted(target: String, by: String) -> bool:
	for e in S.ents:
		if not e.alive or e.team != 1 or e.type != target or not S.visible_to_player(e): continue
		for o in S.ents:
			if o.alive and o.team == 0 and o.type == by and Vector2(o.x - e.x, o.y - e.y).length() <= o.d.sight * T: return true
	return false

func _try_card() -> void:
	if queue.is_empty() or card_open or S.time < 1.5 or S.time - last_card < CARD_GAP: return
	if S.time - S.last_hurt < CALM or main.placing != null or main.sw_aim: return
	for k in U.overlays:
		if U.overlays[k].visible: return
	open_card(queue.pop_front())

func open_card(key: String) -> void:
	card_key = key; card_open = true; seen[key] = true; save_state()
	last_card = S.time
	card_body.show_key(key, false)
	card.visible = true
	main.paused = true
	main.sfx("click")

func close_card() -> void:
	if not card_open: return
	card_open = false; card.visible = false
	card_body.tt.clear()
	if M != null and not S.over and not U.overlays.menu.visible: main.paused = false
	if S != null and S.mission != null: last_card = S.time

func _show_enemy(key: String) -> void:
	var t := key.substr(2); var e: Dictionary = TD.enemy_card(t, camp)
	seen[key] = true; save_state()
	enemy_name.text = e.get("name", D.def_of(t).name).to_upper()
	enemy_text.text = e.text
	enemy_say.text = "%s: “%s”" % [D.SPEAKERS[e.who].name, e.say]
	enemy_tt.show_model("u" if D.UN.has(t) else "b", t, 1, S.teams[1].fac, false)
	enemy_box.visible = true; enemy_t = ENEMY_SHOW
	enemy_box.reset_size()
	main.sfx("alert")

# ---------------- pointer lessons ----------------
func _lesson_tick(dt: float) -> void:
	if step_i >= lesson.steps.size(): _end_lesson(); return
	var st: Dictionary = lesson.steps[step_i]
	if not step_on:
		if st.has("when") and not _when(st.when): hint_box.visible = false; return
		if st.has("skip_if") and S.count(0, st.skip_if) > 0: step_i += 1; return
		step_on = true; step_t = 0.0; cam0 = Vector3(V.cam_x, V.cam_y, V.cam_z)
		step_spot = null
		var h := _hero()
		if st.ptr.has("ahead") and h != null: step_spot = Vector2(h.x, h.y - 5 * T)
		hint_eye.text = ("Lesson  %d / %d" % [step_i + 1, lesson.steps.size()]).to_upper()
		hint_l.text = st.hint
		hint_box.visible = true; hint_box.reset_size()
		if st.say != "": U.radio(lesson.who, st.say)
	step_t += dt
	var dn: Dictionary = st.done
	if dn.has("t") and step_t >= dn.t: _next_step(); return
	if dn.get("ev", "") == "cam" and Vector3(V.cam_x, V.cam_y, V.cam_z).distance_to(cam0) > 2.5 * T: _next_step()

func _when(w: String) -> bool:
	match w:
		"enemy_seen": return S.ents.any(func(e): return e.alive and e.team == 1 and e.kind == "u" and S.visible_to_player(e))
		"bld_ready": return S.teams[0].prod.bld.ready
		_ when w.begins_with("has:"): return S.count(0, w.substr(4)) > 0
		"sw_ready": return S.ents.any(func(e): return e.alive and e.team == 0 and e.kind == "b" and e.rdy)
	return true

func _next_step() -> void:
	step_i += 1; step_on = false; hint_box.visible = false
	if step_i >= lesson.steps.size(): _end_lesson()

func _end_lesson() -> void:
	lesson = null; step_on = false; hint_box.visible = false
	seen[lesson_key] = true; save_state()

func skip_lesson() -> void:
	if lesson != null: _end_lesson(); main.sfx("click")

func _hide_lesson() -> void:
	if hint_box: hint_box.visible = false
	step_on = false

func _hero() -> Ent:
	for e in S.ents:
		if e.alive and e.team == 0 and e.kind == "u" and e.d.hero: return e
	return null

## Where the pointer goes: [kind, value] with kind "w" (a world point, screen position) or "r" (a screen rect).
func pointer():
	if lesson != null and step_on:
		var p = _ptr_of(lesson.steps[step_i].ptr)
		if p != null: return p
	if pulse_t > 0 and pulse_type != "":
		for e in S.ents:
			if e.alive and e.team == 0 and e.type == pulse_type: return ["w", _ent_pt(e)]
	return null

func _ent_pt(e: Ent) -> Vector2:
	if e.kind == "b":
		var p := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + D.BH.get(e.type, 1.0) + 0.2)
		return Vector2(p.x, p.y)
	var q := V.w2s(e.x, e.y, S.h_at(e.x, e.y) + (D.ALT if e.d.air else 0.0) + D.UH.get(e.type, 0.5) * 0.7)
	return Vector2(q.x, q.y)

func _ptr_of(p: Dictionary):
	if p.has("hero"):
		var h := _hero()
		return ["w", _ent_pt(h)] if h != null else null
	if p.has("unit"):
		for e in S.ents:
			if e.alive and e.team == 0 and e.type == p.unit: return ["w", _ent_pt(e)]
		return null
	if p.has("bld"):
		for e in S.ents:
			if e.alive and e.team == 0 and e.kind == "b" and e.type == p.bld: return ["w", _ent_pt(e)]
		return null
	if p.has("enemy"):
		var h := _hero(); var best: Ent = null; var bd := 1e9
		for e in S.ents:
			if not e.alive or e.team != 1 or e.kind != "u" or not S.visible_to_player(e): continue
			var dd := Vector2(e.x - h.x, e.y - h.y).length() if h != null else 0.0
			if dd < bd: bd = dd; best = e
		return ["w", _ent_pt(best)] if best != null else null
	if p.has("ahead"):
		if step_spot == null: return null
		var q := V.w2s(step_spot.x, step_spot.y, S.h_at(step_spot.x, step_spot.y))
		return ["w", Vector2(q.x, q.y)]
	if p.has("view"):
		var r := V.view_rect()
		return ["w", r.get_center()]
	if p.has("ui"):
		var c: Control = null
		match p.ui:
			"power": c = U.power_box
			"cap": c = U.cap_parts[2] if U.cap_parts[2].visible else U.power_box
			"place": c = U.place_bar.get_child(1) if U.place_bar.visible else null
			"sw": c = U.btn.sw if U.btn.sw.visible else null
		return ["r", c.get_global_rect()] if c != null and c.is_visible_in_tree() else null
	if p.has("item"):
		if not U.panel_open: return ["r", U.btn.panel.get_global_rect()]
		var cat: String = p.item.split(":")[0]
		var it: Control = U.items.get(p.item)
		if it == null: return null
		if not it.is_visible_in_tree():
			# the panel shows something else: point at the building that makes it (its top-bar chip), or its sub-tab
			var bt: String = "hq" if cat == "bld" else S.unit_from(0, it.type)
			if U.tabs.has(cat) and U.tabs[cat].is_visible_in_tree(): return ["r", U.tabs[cat].get_global_rect()]
			var pc = U.prod_chips.get(bt)
			return ["r", pc.get_global_rect()] if pc != null and pc.is_visible_in_tree() else null
		return ["r", it.get_global_rect()]
	return null

# ---------------- controls ----------------
## The pointer: a pulsing brass ring on a unit or spot, or a pulsing frame around a button, with a chevron above.
class PtrLayer extends Control:
	var tut
	var t := 0.0
	func _process(dt: float) -> void:
		t += dt
	func _draw() -> void:
		if tut == null or not tut.active() or tut.card_open or tut.main.paused: return
		var p = tut.pointer()
		if p == null: return
		var k := 0.5 + 0.5 * sin(t * 6.0)
		var col := Color(UI.W_BRASS, 0.75 + 0.25 * k)
		var top: Vector2
		if p[0] == "w":
			var c: Vector2 = p[1]
			var r := 22.0 + 6.0 * k
			draw_arc(c, r, 0, TAU, 40, Color(0, 0, 0, 0.45), 5.0, true)
			draw_arc(c, r, 0, TAU, 40, col, 2.5, true)
			draw_arc(c, r + 8 + 6 * (1.0 - k), 0, TAU, 40, Color(UI.W_BRASS, 0.35 * k), 1.5, true)
			top = c - Vector2(0, r + 8)
		else:
			var rc: Rect2 = (p[1] as Rect2).grow(4 + 3 * k)
			draw_rect(rc, Color(0, 0, 0, 0.45), false, 5.0)
			draw_rect(rc, col, false, 2.5)
			top = Vector2(rc.get_center().x, rc.position.y - 4)
		# chevron pointing down at the target, bobbing
		var b := top - Vector2(0, 6 + 6 * k)
		var pts := PackedVector2Array([b + Vector2(-11, -12), b, b + Vector2(11, -12), b + Vector2(0, -6)])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.5))
		draw_colored_polygon(PackedVector2Array([b + Vector2(-9, -11), b + Vector2(0, -1), b + Vector2(9, -11), b + Vector2(0, -6)]), col)

## The 3D model of a unit or building turning slowly in its own little world (cards, enemy cards, field manual).
## dark: a black silhouette (a field manual entry not met yet).
class Turntable extends SubViewportContainer:
	var vp: SubViewport
	var cam: Camera3D
	var pivot: Node3D
	var spin := 0.5
	var plinth: MeshInstance3D
	static var _mats := {}
	func _init() -> void:
		stretch = true
		vp = SubViewport.new(); vp.own_world_3d = true; vp.transparent_bg = true; vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(vp)
		cam = Camera3D.new(); cam.fov = 30; vp.add_child(cam)
		var l := DirectionalLight3D.new(); l.light_energy = 1.15; vp.add_child(l); l.look_at_from_position(Vector3(-3, 6, 4), Vector3.ZERO)
		var f := DirectionalLight3D.new(); f.light_energy = 0.45; f.light_color = Color("ffd9b0"); vp.add_child(f); f.look_at_from_position(Vector3(4, 2, 5), Vector3.ZERO)
		var env := Environment.new(); env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color("c8cfd6"); env.ambient_light_energy = 0.9
		env.background_mode = Environment.BG_CLEAR_COLOR
		var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
		pivot = Node3D.new(); vp.add_child(pivot)
		# a low plinth the model stands on, so it does not float in the dark
		plinth = MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 1.0; cy.bottom_radius = 1.08; cy.height = 0.08; cy.radial_segments = 8
		plinth.mesh = cy; var pm := StandardMaterial3D.new(); pm.albedo_color = Color("2a2f22"); pm.roughness = 0.9; plinth.material_override = pm
		vp.add_child(plinth)
	func _process(dt: float) -> void:
		if is_visible_in_tree(): pivot.rotation.y += dt * spin
	func clear() -> void:
		for ch in pivot.get_children(): ch.queue_free()
	func show_model(kind: String, type: String, team: int, fac: String, dark: bool) -> void:
		clear()
		# a card shows its army's own colours whatever match is on, so it is built outside the game's model cache
		var keep: Array = D.TEAMC.duplicate()
		D.TEAMC[team] = D.FCOL[fac]
		var m: Node3D = Models.unit_model(type, team, fac) if kind == "u" else Models.bld_model(type, team, fac)
		D.TEAMC = keep
		pivot.add_child(m); pivot.rotation.y = 0.6
		var black := StandardMaterial3D.new(); black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; black.albedo_color = Color(0.09, 0.1, 0.075)
		var bb := AABB(); var first := true
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var inst := mi as MeshInstance3D
			if dark: inst.material_override = black
			else: _no_fog(inst)
			if not inst.is_visible_in_tree(): continue
			var a: AABB = (pivot.global_transform.affine_inverse() * inst.global_transform) * inst.get_aabb()
			bb = a if first else bb.merge(a); first = false
		var ctr := bb.get_center(); var L: float = maxf(bb.size.x, maxf(bb.size.y * 1.3, bb.size.z))
		m.position -= Vector3(ctr.x, 0, ctr.z)
		var foot := maxf(bb.size.x, bb.size.z) * 0.62
		plinth.scale = Vector3(foot, 1.0, foot); plinth.position = Vector3(0, bb.position.y - 0.04, 0); plinth.visible = not dark
		var look := Vector3(0, ctr.y - bb.size.y * 0.08, 0)
		cam.position = look + Vector3(0.0, 0.55, 1.0).normalized() * L * 2.9
		cam.look_at(look)
	## The game's lit shader darkens what lies under fog of war; this little world has none, so its copy turns it off.
	static func _no_fog(mi: MeshInstance3D) -> void:
		if mi.mesh == null: return
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is ShaderMaterial:
				var id := mat.get_instance_id()
				if not _mats.has(id):
					var c: ShaderMaterial = mat.duplicate()
					c.set_shader_parameter("fog_on", 0.0)
					_mats[id] = c
				mi.set_surface_override_material(s, _mats[id])

## A card's words and picture: model (or a lesson glyph), name, job, good/weak, tip, speaker and line.
class CardBody extends HBoxContainer:
	var ui
	var tt: Turntable
	var glyph: UI.Glyph
	var eye: Label
	var nm: Label
	var job: Label
	var good: Label
	var weak: Label
	var extra: Label
	var tip: Label
	var face: UI.Portrait
	var who: Label
	var say: Label
	var pic: PanelContainer
	func setup(pic_w: float) -> void:
		add_theme_constant_override("separation", 16)
		pic = PanelContainer.new(); pic.add_theme_stylebox_override("panel", UI.cut(Color(0.03, 0.035, 0.025, 0.9), UI.W_LINE, 1, 10, 0.0))
		pic.custom_minimum_size = Vector2(pic_w, pic_w); pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER; add_child(pic)
		tt = Turntable.new(); tt.set_anchors_preset(Control.PRESET_FULL_RECT); pic.add_child(tt)
		glyph = UI.Glyph.new(); glyph.col = UI.W_BRASS; glyph.custom_minimum_size = Vector2(pic_w * 0.45, pic_w * 0.45)
		var gc := CenterContainer.new(); gc.add_child(glyph); pic.add_child(gc)
		var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 4); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.custom_minimum_size.x = 300; v.alignment = BoxContainer.ALIGNMENT_CENTER; add_child(v)
		eye = ui.eyebrow(""); v.add_child(eye)
		nm = ui.title("", 30); v.add_child(nm)
		job = ui.lbl("", ui.f_body6, 16, UI.W_KHAKI); job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(job)
		good = _row(v, UI.C_OK); weak = _row(v, Color("ff8a80")); extra = _row(v, UI.W_SAND)
		tip = ui.lbl("", ui.f_body, 14, Color("e2dac2")); tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(tip)
		var rule := UI.Rule.new(); rule.custom_minimum_size = Vector2(0, 2); v.add_child(rule)
		var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 10); v.add_child(sh)
		face = UI.Portrait.new(); face.custom_minimum_size = Vector2(48, 48); sh.add_child(face)
		var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 0); sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sv.alignment = BoxContainer.ALIGNMENT_CENTER; sh.add_child(sv)
		who = ui.lbl("", ui.f_wide, 10, UI.W_BRASS); sv.add_child(who)
		say = ui.lbl("", ui.f_body, 15, UI.W_KHAKI); say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sv.add_child(say)
	func _row(v: Control, col: Color) -> Label:
		var l: Label = ui.lbl("", ui.f_body6, 13, col); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(l)
		return l
	## Fills the card for a key ("vey", "l_groups", "e:tank"); locked: a silhouette and nothing else.
	func show_key(key: String, locked: bool) -> void:
		var enemy := key.begins_with("e:")
		var t := key.substr(2) if enemy else key
		var lesson := t.begins_with("l_")
		var c: Dictionary = TD.enemy_card(t, ui.main.tut.camp) if enemy else TD.CARDS[t]
		var fac: String = TD.fac_of(t) if enemy else (c.home[0] if not lesson else "ashen")
		tt.visible = not lesson; glyph.get_parent().visible = lesson
		if lesson: glyph.kind = c.get("glyph", "info"); glyph.queue_redraw()
		else:
			var kind := "u" if D.UN.has(t) else "b"
			tt.show_model(kind, t, 1 if enemy else 0, fac, locked)
		for l in [job, good, weak, extra, tip, who, say]: l.visible = not locked
		face.visible = not locked
		if locked:
			eye.text = TD.TXT.locked.to_upper(); nm.text = "? ? ?"
			return
		var pal := {"u": TD.TXT.new_unit, "b": TD.TXT.new_bld}
		eye.text = (TD.TXT.enemy if enemy else (TD.TXT.lesson if lesson else pal["u" if D.UN.has(t) else "b"] + "  //  " + D.FACS[fac].name)).to_upper()
		nm.text = (c.get("name", D.def_of(t).name) if enemy else TD.card_name(t)).to_upper()
		job.text = c.text if enemy else c.job
		var gw: Array = TD.gw_of(t) if enemy else TD.good_weak(t)
		good.text = (TD.TXT.good + ": " + gw[0]) if gw[0] != "" else ""; good.visible = gw[0] != ""
		weak.text = (TD.TXT.weak + ": " + gw[1]) if gw[1] != "" else ""; weak.visible = gw[1] != ""
		extra.text = gw[2]; extra.visible = gw[2] != ""
		tip.text = ("▸  " + c.tip) if c.has("tip") else ""; tip.visible = c.has("tip")
		var sp: Dictionary = D.SPEAKERS[c.who]
		face.sp = sp; face.queue_redraw()
		who.text = (sp.name + "  //  " + sp.role).to_upper(); who.add_theme_color_override("font_color", sp.flash)
		say.text = "“" + c.say + "”"
