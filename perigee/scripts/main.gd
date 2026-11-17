extends Node2D
## Perigee: runs the simulation (scripts/sim.gd) on a fixed 120 Hz step, draws it with
## interpolation between steps, turns the one button into sim.press()/release(), and handles
## the save, sound, haptics, and pausing when the app goes to the background.

const INK := Color("f3ecdf")
const SAND := Color("f2c879")
const SPACE := Color("141634")
const SPACE_2 := Color("1d2150")
const TEAL := Color("6fd6c5")
const CORAL := Color("ff8a6b")
const LILAC := Color("b49cff")
const MAX_STEPS_PER_FRAME := 30
const RESUME_COUNTDOWN := 3.0

var sim: Sim
var save: SaveData
var hud: Hud
var sfx: Sfx
var music: Music
## Where the save lives; tests point it elsewhere before the node enters the tree.
var save_path := "user://save.json"
var vis_seed := -1 ## >= 0 fixes the looks RNG, and with it the worlds' seeds (tests only)

## "endless", or a kind of moon for a lab run (tries one new kind; never counts for the best score)
var mode := "endless"
const TUTORIAL_SEED := 4242
const TUTORIAL_RECIPE := {"moons": 6, "rescue": true}
const MODE_NAMES := {"twin": "Lab · Twin moons", "retro": "Lab · Retrograde", "pulsar": "Lab · Pulsars"}
var sector: Dictionary = {} ## the Voyage sector being played
var clear_shown := false
var paused := false
var resume_left := 0.0 ## > 0 while counting down to resume
var button_down := false ## the one button as the player holds it right now
var over_shown := false
var new_best := false
var shake := 0.0
var tutorial_misses := 0
var _miss_t := -10.0 ## sim time of the last tutorial rescue, for its hint
var particles: Array[Dictionary] = []
var popups: Array[Dictionary] = [] ## score text floating up in the world: {x, y, text, col, life}
var stars: Array[Dictionary] = []
var _acc := 0.0
var _alpha := 1.0 ## how far between the last two steps we draw
var _vis := RandomNumberGenerator.new() ## looks only (particles, stars, shake); never the game
var _crescent := PackedVector2Array() ## moon shadow shape for radius 1
var _glow: Texture2D
var _palette: Array = Unlocks.palette("palette_pastel") ## moon colours of the equipped palette


func _ready() -> void:
	RenderingServer.set_default_clear_color(SPACE)
	save = SaveData.new(save_path)
	save.load_file()
	sfx = Sfx.new()
	add_child(sfx)
	sfx.enabled = bool(save.get_setting("sound"))
	music = Music.new()
	add_child(music)
	music.enabled = sfx.enabled
	music.play("drift")
	hud = Hud.new()
	add_child(hud)
	hud.set_best(save.data.best)
	hud.set_sound(sfx.enabled)
	hud.sound_toggled.connect(_toggle_sound)
	hud.mode_picked.connect(start_mode)
	hud.voyage_opened.connect(open_voyage)
	hud.sector_picked.connect(start_sector)
	hud.clear_action.connect(_clear_action)
	hud.settings_opened.connect(open_settings)
	hud.setting_changed.connect(change_setting)
	hud.settings_closed.connect(close_settings)
	hud.tutorial_requested.connect(start_tutorial)
	hud.hangar_opened.connect(open_hangar)
	hud.cosmetic_picked.connect(equip)
	hud.hangar_closed.connect(close_hangar)
	hud.refresh_pressed.connect(refresh_game)
	_apply_volumes()
	if not save.data.tutorial_done:
		hud.set_start_text("Tap to learn to fly")
	if vis_seed >= 0:
		_vis.seed = vis_seed
	else:
		_vis.randomize()
	for i in 140:
		stars.append({"x": _vis.randf(), "y": _vis.randf(), "z": _vis.randf_range(0.15, 1.0), "tw": _vis.randf() * 6.0})
	_crescent = _make_crescent()
	_glow = _make_glow()
	var size := get_viewport_rect().size
	sim = Sim.new(_new_seed(), size.x, size.y)
	sim.next_seed = _new_seed()
	get_viewport().size_changed.connect(_on_resize)
	_update_frame_cap()
	_check_update()


## Restarts the game so the launch-time updater (scripts/boot.gd) loads the newest build: the app
## restarts on Android and desktop, the page reloads in the browser. Tests swap `restart_fn` for a stub.
var restart_fn := func() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit()


func refresh_game() -> void:
	if sim.state != "start":
		return
	save.save_file()
	hud.set_build_state("restarting")
	await get_tree().create_timer(0.15).timeout # let the line show before the app goes away
	restart_fn.call()


## The build number from the running version ("b1050 pr12 abc1234" -> 1050), or 0.
static func build_number(version: String) -> int:
	var m := RegEx.create_from_string("^b(\\d+)").search(version)
	return int(m.get_string(1)) if m else 0


## Asks the update server (as the launch-time updater does) whether a newer build is out, and if so
## says so on the start card's build line. Quiet when offline, and never on the Play build (no url).
func _check_update() -> void:
	var url := str(ProjectSettings.get_setting("perigee/update_url", ""))
	if url == "" or OS.has_feature("web"):
		return
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	if http.request(url + "update.json?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		http.queue_free()
		return
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if d is Dictionary:
		show_update(int(d.get("build", 0)))


## Shows "new build" on the start card when `remote` is newer than the running build.
func show_update(remote: int) -> void:
	var have := build_number(str(ProjectSettings.get_setting("application/config/version", "")))
	if have > 0 and remote > have:
		hud.set_build_state("new", remote)


## Starts a run in a mode right away (from the lab buttons on the start and game over cards).
func start_mode(m: String) -> void:
	if paused:
		return
	mode = m
	sector = {}
	hud.set_timer(0.0, 0.0)
	sim.recipe = {} if m == "endless" else {"mix": {"moon": 1.0, m: 2.0}}
	sim.new_run(_new_seed())
	sim.events.append({"type": "start"})
	hud.set_mode(MODE_NAMES.get(m, ""))


## The first-run tutorial: a short gentle run with hints, where missing a moon puts you back on
## the last one instead of ending the run. Finishing it (moon 6) marks it done.
func start_tutorial() -> void:
	if paused:
		return
	mode = "tutorial"
	sector = {}
	hud.hide_settings()
	hud.set_timer(0.0, 0.0)
	sim.recipe = TUTORIAL_RECIPE.duplicate()
	sim.new_run(TUTORIAL_SEED)
	sim.swallow = button_down # the tap that started it must not fling
	sim.events.append({"type": "start"})
	hud.set_mode("How to play")
	tutorial_misses = 0


func open_hangar() -> void:
	hud.show_hangar(int(save.data.sparks), save.data.equipped)


func close_hangar() -> void:
	hud.hide_hangar()
	if sim.state == "start":
		hud.show_start(true)


## Equips an unlocked cosmetic (locked ones are ignored).
func equip(id: String) -> void:
	var it := Unlocks.item(id)
	if it.is_empty() or not Unlocks.is_unlocked(id, int(save.data.sparks)):
		return
	save.data.equipped[it.kind] = id
	save.save_file()
	sfx.play("toggle")
	if hud.hangar_card.visible:
		hud.show_hangar(int(save.data.sparks), save.data.equipped)


## Adds a run's sparks to the all-time count (the unlock track) and says what that unlocked.
func _bank_sparks() -> void:
	var before := int(save.data.sparks)
	save.data.sparks = before + sim.sparks_got
	var got := Unlocks.newly_unlocked(before, int(save.data.sparks))
	var names: Array[String] = []
	for it in got:
		names.append(Unlocks.label(it))
	hud.set_over_unlock(("Unlocked: " + ", ".join(names)) if not names.is_empty() else "")
	if not got.is_empty():
		sfx.play("star", 0.6)
		if sim.state == "clear":
			_popup(sim.player.x, sim.player.y - 40.0, "Unlocked: " + ", ".join(names), SAND)


func open_settings() -> void:
	hud.show_settings(save.data.settings)


func close_settings() -> void:
	hud.hide_settings()
	save.save_file()
	if sim.state == "start":
		hud.show_start(true)
	elif sim.state == "over":
		hud.show_start(false)


func change_setting(key: String, value: Variant) -> void:
	save.set_setting(key, value)
	if key.ends_with("_volume"):
		_apply_volumes()
		if key == "sfx_volume":
			sfx.play("toggle")


func _apply_volumes() -> void:
	for bus in [["Music", "music_volume"], ["Sfx", "sfx_volume"]]:
		var i := AudioServer.get_bus_index(bus[0])
		var v := float(save.get_setting(bus[1]))
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.0)


func open_voyage() -> void:
	hud.show_voyage(save.data.voyage)


## Starts a Voyage sector: its fixed layout from the sector's seed and recipe.
func start_sector(id: String) -> void:
	var sec := Voyage.sector(id)
	if sec.is_empty() or paused:
		return
	mode = "voyage"
	sector = sec
	sim.recipe = Voyage.recipe(sec)
	sim.new_run(sec.seed)
	sim.events.append({"type": "start"})
	hud.hide_voyage()
	hud.set_mode("Sector %s · %s" % [sec.id, Voyage.system_of(id).name])


func _clear_action(action: String) -> void:
	if mode == "tutorial":
		start_mode("endless")
		return
	if sector.is_empty():
		return
	match action:
		"next":
			var nxt := Voyage.next_sector(sector.id)
			if nxt.is_empty():
				open_voyage()
			else:
				start_sector(nxt.id)
		"replay":
			start_sector(sector.id)
		"map":
			open_voyage()


func _new_seed() -> int:
	return _vis.randi()


func _on_resize() -> void:
	var size := get_viewport_rect().size
	sim.W = size.x
	sim.H = size.y


# ---------- input ----------

func _unhandled_input(event: InputEvent) -> void:
	var down := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		down = event.pressed
	elif (event is InputEventKey and not event.echo
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]):
		down = event.pressed
	else:
		return
	get_viewport().set_input_as_handled()
	if down:
		on_press()
	else:
		on_release()


func on_press() -> void:
	button_down = true
	if paused:
		if resume_left <= 0.0:
			resume_left = RESUME_COUNTDOWN
			hud.show_pause(true, ceili(resume_left))
		return
	if sim.state == "over" and not over_shown:
		return
	if sim.state == "clear":
		if clear_shown:
			_clear_action("next")
		return
	if sim.state == "start" and not save.data.tutorial_done:
		start_tutorial()
		return
	sim.press()


func on_release() -> void:
	button_down = false
	if paused:
		return
	sim.release()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			pause_game()


## Freezes a run in progress (the app lost focus or went to the background).
func pause_game() -> void:
	if sim == null or sim.state != "play" or paused:
		return
	paused = true
	resume_left = 0.0
	button_down = false
	sim.cancel()
	hud.show_pause(true)
	music.ducked = true
	_update_frame_cap()


func _resume() -> void:
	paused = false
	resume_left = 0.0
	hud.show_pause(false)
	music.ducked = false
	# a finger kept down through the countdown counts as holding
	sim.holding = button_down
	_update_frame_cap()


func _toggle_sound() -> void:
	sfx.enabled = not sfx.enabled
	music.enabled = sfx.enabled
	save.set_setting("sound", sfx.enabled)
	save.save_file()
	hud.set_sound(sfx.enabled)
	sfx.play("toggle")


# ---------- frame ----------

func _process(delta: float) -> void:
	advance(delta)


## Moves the game on by `delta` seconds of real time: fixed steps plus the leftover fraction
## for drawing. Tests call this directly.
func advance(delta: float) -> void:
	if paused:
		if resume_left > 0.0:
			resume_left -= delta
			if resume_left <= 0.0:
				_resume()
			else:
				hud.show_pause(true, ceili(resume_left))
		_alpha = 1.0
		queue_redraw()
		return
	_acc = minf(_acc + delta, Sim.DT * MAX_STEPS_PER_FRAME)
	while _acc >= Sim.DT:
		_acc -= Sim.DT
		sim.step()
		_handle_events()
	_alpha = _acc / Sim.DT
	_update_effects(delta)
	_update_hud()
	queue_redraw()


func _handle_events() -> void:
	for e in sim.events:
		match e.type:
			"start":
				hud.show_start(false)
				hud.hide_over()
				hud.hide_clear()
				hud.hide_voyage()
				over_shown = false
				clear_shown = false
				new_best = false
				hud.set_score(0)
				hud.set_over_unlock("")
				# a Voyage retry replays the same layout
				sim.next_seed = int(sector.seed) if mode == "voyage" else _new_seed()
				_update_frame_cap()
			"launch":
				sfx.play("launch")
			"capture":
				if e.kind == "retro":
					_popup(e.x, e.y + 22.0, "Reverse", LILAC)
				if not e.first:
					sfx.play("revisit")
				elif e.perigee:
					sfx.play("perigee")
					_popup(e.x, e.y - 14.0, "Perigee +%d" % e.points, TEAL)
					_vibrate(18)
				else:
					sfx.play(sfx.catch_sound(e.hops))
					_popup(e.x, e.y - 14.0, "+%d" % e.points, INK)
				if e.skipped > 0:
					sfx.play("leap")
					_popup(e.x, e.y - 32.0, "Leap ×%d  +%d" % [e.skipped, e.leap_points], CORAL)
					_burst(e.x, e.y, CORAL, 24, 120.0)
					shake = maxf(shake, 4.0)
					_vibrate(30)
				_burst(e.x, e.y, _palette[e.col], 10, 55.0)
				_vibrate(12)
			"spark":
				_burst(e.x, e.y, SAND, 10, 70.0)
				_popup(e.x, e.y - 12.0, "+%d" % e.points, SAND)
				sfx.play("spark")
			"clear":
				_burst(e.x, e.y, SAND, 40, 180.0)
				sfx.play("clear")
				_vibrate(40)
				if mode == "tutorial":
					save.data.tutorial_done = true
					save.save_file()
					hud.set_start_text("Tap to play Drift")
				else:
					_record_clear()
			"rescue":
				tutorial_misses += 1
				_miss_t = sim.t
				_popup(e.x, e.y - 14.0, "Try again", SAND)
				sfx.play("revisit")
			"graze":
				_popup(e.x, e.y - 14.0, "Graze +1", LILAC)
				sfx.play("graze")
			"die":
				_burst(e.x, e.y, INK, 30, 160.0)
				shake = 10.0
				sfx.play("die")
				_vibrate(60)
				_record_run()
	sim.events.clear()


func _record_clear() -> void:
	var st := Voyage.stars(sector, sim)
	var got := st.count(true)
	var rec: Dictionary = save.data.voyage.get(sector.id, {})
	rec["stars"] = maxi(int(rec.get("stars", 0)), got)
	rec["score"] = maxi(int(rec.get("score", 0)), sim.score)
	rec["time"] = minf(float(rec.get("time", INF)), snappedf(sim.run_t, 0.01))
	save.data.voyage[sector.id] = rec
	save.data.runs = int(save.data.runs) + 1
	_bank_sparks()
	save.save_file()


func _record_run() -> void:
	if mode == "voyage":
		new_best = false
		save.data.runs = int(save.data.runs) + 1
		_bank_sparks()
		save.save_file()
		_update_frame_cap()
		return
	if mode != "endless":
		new_best = false
		_update_frame_cap()
		return
	new_best = sim.score > int(save.data.best)
	if new_best:
		save.data.best = sim.score
	save.data.runs = int(save.data.runs) + 1
	_bank_sparks()
	save.save_file()
	hud.set_best(save.data.best)
	_update_frame_cap()


func _update_hud() -> void:
	hud.set_score(sim.score)
	if sim.state == "play":
		hud.set_combo(sim.combo, sim.mult)
	else:
		hud.set_best(save.data.best)
	if mode == "voyage" and not sector.is_empty():
		hud.set_timer(sim.run_t, float(sector.par))
	if sim.state == "over" and not over_shown and sim.t - sim.death_t >= Sim.RESTART_LOCK:
		over_shown = true
		hud.set_over_row(mode == "voyage")
		var line := ("Moon %d of %d" % [mini(sim.hops, sector.moons), sector.moons]) if mode == "voyage" else ""
		hud.show_over(sim.score, sim.death_why, save.data.best, new_best, _run_stats(), line)
	if mode == "tutorial" and sim.state == "clear" and not clear_shown and sim.t - sim.death_t >= 0.6:
		clear_shown = true
		hud.show_tutorial_done(sim.score)
	if mode != "tutorial" and sim.state == "clear" and not clear_shown and sim.t - sim.death_t >= 0.6:
		clear_shown = true
		var st := Voyage.stars(sector, sim)
		hud.show_clear(sector.id, sim.score, st, [
			"Reach moon %d" % sector.moons,
			"Under %d s (%.1f s)" % [int(sector.par), sim.run_t],
			Voyage.goal_text(sector.goal),
		], not Voyage.next_sector(sector.id).is_empty())
		var lit := 0
		for got in st:
			if got:
				sfx.play("star", 0.25 + 0.22 * lit)
				lit += 1
	var hint := ""
	if mode == "tutorial":
		hint = _tutorial_hint()
	elif sim.state == "play" and sim.hops < 3:
		if sim.player.planet != null:
			hint = "Release to fling" if sim.holding else "Tap, or hold and release, to fling"
		else:
			hint = "Keep holding…" if sim.holding else "Hold to catch the next moon"
	hud.set_hint(hint)


## What the tutorial asks for next, from where the player is.
func _tutorial_hint() -> String:
	if sim.state != "play":
		return ""
	var p := sim.player
	if sim.t - _miss_t < 2.0:
		return "Missed! Hold as you cross the next dotted ring"
	if p.planet != null:
		if sim.hops == 0:
			return "Tap to fling off your moon"
		if sim.hops < 3:
			return "Nice catch! Fling again"
		if sim.perigees == 0:
			return "Hold late: a catch inside the teal ring is a Perigee"
		return "Perigees and sparks build your combo. Reach the gold moon"
	if sim.holding:
		return "Keep holding…"
	return "Hold when you reach the dotted ring"


func _run_stats() -> String:
	var parts: Array[String] = []
	parts.append("%d %s" % [sim.perigees, "perigee" if sim.perigees == 1 else "perigees"])
	if sim.leaps > 0:
		parts.append("%d %s" % [sim.leaps, "leap" if sim.leaps == 1 else "leaps"])
	parts.append("best combo %d" % sim.best_combo)
	return " · ".join(parts)


func _popup(x: float, y: float, text: String, col: Color) -> void:
	popups.append({"x": x, "y": y, "text": text, "col": col, "life": 1.1})


func _update_effects(delta: float) -> void:
	for q in popups:
		q.y -= delta * 28.0
		q.life -= delta
	popups = popups.filter(func(q: Dictionary) -> bool: return q.life > 0.0)
	for q in particles:
		q.x += q.vx * delta
		q.y += q.vy * delta
		var damp := pow(0.96, delta * 60.0)
		q.vx *= damp
		q.vy *= damp
		q.life -= delta
	particles = particles.filter(func(q: Dictionary) -> bool: return q.life > 0.0)
	shake = maxf(0.0, shake - delta * 30.0)


func _burst(x: float, y: float, col: Color, n: int, sp: float) -> void:
	if bool(save.get_setting("reduced_motion")):
		n = ceili(n / 3.0)
	for i in n:
		var a := _vis.randf() * TAU
		var s := _vis.randf_range(0.3, 1.0) * sp
		particles.append({"x": x, "y": y, "vx": cos(a) * s, "vy": sin(a) * s, "life": _vis.randf_range(0.4, 0.9), "col": col})


func _vibrate(ms: int) -> void:
	if bool(save.get_setting("vibration")):
		Input.vibrate_handheld(ms)


## Menus and pauses don't need every frame; save the battery there.
func _update_frame_cap() -> void:
	if sim != null and sim.state == "play" and not paused:
		Engine.max_fps = 0
	else:
		Engine.max_fps = 30


# ---------- draw ----------

func _draw() -> void:
	var size := get_viewport_rect().size
	var w := size.x
	var h := size.y
	var a := _alpha
	var t := sim.t - (1.0 - a) * Sim.DT
	var cam := Vector2(lerpf(sim.cam_px, sim.cam_x, a), lerpf(sim.cam_py, sim.cam_y, a))
	var p := sim.player

	var reduce_motion := bool(save.get_setting("reduced_motion"))
	# background gradient and parallax stars (screen space)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([SPACE, SPACE, SPACE_2, SPACE_2]))
	for s in stars:
		var yy := fposmod(s.y * h - cam.y * s.z * 0.25, h)
		var al: float = (0.35 + (0.0 if reduce_motion else 0.35 * sin(t * 1.5 + s.tw))) * s.z
		var r: float = s.z * 1.6 + 0.3
		draw_rect(Rect2(s.x * w, yy, r, r), Color(INK, al))

	var sk := _vis.randf_range(-shake, shake) if shake > 0.0 and not reduce_motion else 0.0
	draw_set_transform(Vector2(w / 2.0 - cam.x + sk, h / 2.0 - cam.y + sk * 0.6))

	var ship := Vector2(lerpf(p.px, p.x, a), lerpf(p.py, p.y, a))
	var pos := {}
	for pl in sim.planets:
		pos[pl] = Vector2(Sim.planet_x(pl, t), pl.y)

	_palette = Unlocks.palette(save.data.equipped.palette)
	var calm := bool(save.get_setting("reduced_motion"))
	var contrast := bool(save.get_setting("high_contrast"))
	# capture rings
	for pl in sim.planets:
		if pl.visited and pl != p.planet:
			continue
		var c: Vector2 = pos[pl]
		var lit := pl.lit(t)
		var inside := p.planet == null and sim.state == "play" and pl != p.last and ship.distance_to(c) < pl.ring and lit
		# twins share a figure-eight ring: leave out the arcs inside the partner's ring
		var skip_c := Vector2.ZERO
		var skip_r := 0.0
		if pl.partner != null:
			skip_c = Vector2(Sim.planet_x(pl.partner, t), pl.partner.y)
			skip_r = pl.partner.ring
		if inside and skip_r == 0.0:
			draw_circle(c, pl.ring, Color(SAND, 0.07), true, -1.0, true)
		var col := SAND if inside else (Color(INK, 0.12) if pl == p.planet else Color(INK, 0.32))
		if pl.kind == "retro" and not inside and pl != p.planet:
			col = Color(LILAC, 0.6)
		if not lit:
			col = Color(INK, 0.07)
		# a retrograde ring's dashes run the other way
		var flow := t * 10.0 if pl.kind == "retro" else -t * 10.0
		if calm:
			flow = 0.0
		if contrast and lit:
			col.a = maxf(col.a, 0.8 if pl != p.planet else 0.3)
		_dashed_circle(c, pl.ring, 3.0, 7.0, flow, (2.4 if inside else 1.4) + (1.0 if contrast else 0.0), col, skip_c, skip_r)
		if pl != p.planet:
			# the perigee ring: a catch inside it is a perigee. High contrast tells it apart by its
			# long dashes as well as its colour.
			var pa := (0.85 if inside else 0.35) * (1.0 if lit else 0.3)
			if contrast:
				_dashed_circle(c, pl.perigee_radius(), 9.0, 4.0, flow, 2.2, Color(TEAL, minf(pa * 2.0, 1.0)))
			else:
				_dashed_circle(c, pl.perigee_radius(), 2.0, 5.0, flow, 1.0, Color(TEAL, pa))
		if pl.flash > 0.0:
			draw_arc(c, lerpf(p.r_target, pl.ring, pl.flash), 0, TAU, 96, Color(SAND, pl.flash * 0.6), 2.0, true)

	# guide dots for the first hops
	if sim.state == "play" and p.planet != null and (sim.hops < 3 or bool(save.get_setting("aim_guide")) or mode == "tutorial"):
		var pts := sim.predict()
		for i in pts.size():
			var q: Dictionary = pts[i]
			draw_circle(Vector2(q.x, q.y), 4.0 if q.hit else 2.0, Color(SAND, 0.55 * (1.0 - float(i) / pts.size()) + 0.1), true, -1.0, true)

	# sparks
	for s in sim.sparks:
		if s.got:
			continue
		var pulse := 1.0 + 0.2 * sin(t * 5.0 + s.x)
		var star := PackedVector2Array()
		for i in 8:
			var r := (2.6 if i % 2 else 7.0) * pulse
			var an := i * PI / 4.0 + t * 1.2
			star.append(Vector2(s.x + cos(an) * r, s.y + sin(an) * r))
		draw_colored_polygon(star, SAND)

	# moons
	for pl in sim.planets:
		var c: Vector2 = pos[pl]
		var fade := 0.25 if pl.skipped else (0.45 if pl.visited and pl != p.planet else 1.0)
		var col: Color = _palette[pl.col]
		var gr := pl.pr * 2.2
		draw_texture_rect(_glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col, fade))
		draw_circle(c, pl.pr, Color(col, fade), true, -1.0, true)
		var shadow := PackedVector2Array()
		for v in _crescent:
			shadow.append(c + v * pl.pr)
		draw_colored_polygon(shadow, Color(SPACE, 0.28 * fade))
		var rot := Transform2D(pl.spin, Vector2.ZERO)
		draw_circle(c + rot * Vector2(-0.35, -0.2) * pl.pr, pl.pr * 0.22, Color(SPACE, 0.16 * fade), true, -1.0, true)
		draw_circle(c + rot * Vector2(0.3, 0.35) * pl.pr, pl.pr * 0.14, Color(SPACE, 0.16 * fade), true, -1.0, true)
		if pl.finish and not pl.visited:
			# a Voyage waypoint
			draw_arc(c, pl.pr + 8.0 + sin(t * 4.0) * 2.0, 0, TAU, 48, SAND, 2.0, true)
		if pl.kind == "pulsar":
			# a beating white core, bright while the ring is lit
			var beat := 0.5 + 0.5 * sin(t * TAU / Sim.PULSAR_PERIOD * 2.0)
			draw_circle(c, pl.pr * (0.3 + 0.1 * beat), Color(INK, (0.9 if pl.lit(t) else 0.3) * fade), true, -1.0, true)
		elif pl.kind == "retro":
			# a tilted band, like a ring seen edge-on
			var band := PackedVector2Array()
			for i in 25:
				var an := TAU * i / 24.0
				band.append(c + Transform2D(-0.35, Vector2.ZERO) * Vector2(cos(an) * pl.pr * 1.55, sin(an) * pl.pr * 0.35))
			draw_polyline(band, Color(LILAC, 0.8 * fade), 1.5, true)

	# trail and ship
	if sim.state != "over" or sim.t - sim.death_t < 0.05:
		var tr := p.trail
		var eq: Dictionary = save.data.equipped
		Looks.draw_trail(self, eq.trail, tr, ship, _palette, t)
		var heading := Vector2.ZERO
		if tr.size() >= 2:
			heading = (ship - tr[-2]).normalized()
		Looks.draw_ship(self, eq.ship, ship, heading, t)
		if sim.holding and p.planet == null and sim.state == "play":
			draw_arc(ship, 10.0 + sin(t * 14.0) * 1.5, 0, TAU, 32, SAND, 1.5, true)

	# particles
	for q in particles:
		draw_rect(Rect2(q.x - 1.5, q.y - 1.5, 3, 3), Color(q.col, clampf(q.life / 0.9, 0.0, 1.0)))
	# score popups
	for q in popups:
		var font: Font = hud.body_700
		var fs := 13
		var tw := font.get_string_size(q.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(q.x - tw / 2.0, q.y), q.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(q.col, clampf(q.life / 0.5, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO)


## A dotted ring like the prototype's setLineDash([3, 7]) with a moving dash offset.
func _dashed_circle(c: Vector2, r: float, dash: float, gap: float, offset: float, width: float, col: Color,
		skip_c := Vector2.ZERO, skip_r := 0.0) -> void:
	var period := dash + gap
	var n := maxi(8, int(TAU * r / period))
	var step := TAU / n
	var da := step * dash / period
	var off := fposmod(-offset, period) / period * step
	var segs := PackedVector2Array()
	for i in n:
		var a0 := i * step + off
		if skip_r > 0.0 and (c + Vector2(cos(a0 + da / 2.0), sin(a0 + da / 2.0)) * r).distance_to(skip_c) < skip_r:
			continue
		segs.append(c + Vector2(cos(a0), sin(a0)) * r)
		segs.append(c + Vector2(cos(a0 + da), sin(a0 + da)) * r)
	if not segs.is_empty():
		draw_multiline(segs, col, width, true)


## The moon's shadow: the part of the moon (radius 1 at the origin) covered by a circle of
## radius 1.05 at (0.45, 0.4), like the prototype's clipped crescent. Convex, so a polygon.
func _make_crescent() -> PackedVector2Array:
	var b := Vector2(0.45, 0.4)
	var rb := 1.05
	var pts: Array[Vector2] = []
	for i in 96:
		var an := TAU * i / 96.0
		var on_a := Vector2(cos(an), sin(an))
		if on_a.distance_to(b) <= rb:
			pts.append(on_a)
		var on_b := b + Vector2(cos(an), sin(an)) * rb
		if on_b.length() <= 1.0:
			pts.append(on_b)
	var mid := Vector2.ZERO
	for v in pts:
		mid += v
	mid /= pts.size()
	pts.sort_custom(func(u: Vector2, v: Vector2) -> bool: return (u - mid).angle() < (v - mid).angle())
	return PackedVector2Array(pts)


## The moons' soft glow: alpha 0.33 out to 0.27 of the radius, fading to 0 at the edge
## (the prototype's radial gradient from 0.6 to 2.2 body radii).
func _make_glow() -> Texture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.6 / 2.2)
	g.set_color(0, Color(1, 1, 1, 0.33))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex
