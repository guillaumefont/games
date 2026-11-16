extends Node2D
## Perigee: runs the simulation (scripts/sim.gd) on a fixed 120 Hz step, draws it with
## interpolation between steps, turns the one button into sim.press()/release(), and handles
## the save, sound, haptics, and pausing when the app goes to the background.

const COLORS: Array[Color] = [Color("ff8a6b"), Color("6fd6c5"), Color("f2c879"), Color("b49cff")]
const INK := Color("f3ecdf")
const SAND := Color("f2c879")
const SPACE := Color("141634")
const SPACE_2 := Color("1d2150")
const MAX_STEPS_PER_FRAME := 30
const RESUME_COUNTDOWN := 3.0

var sim: Sim
var save: SaveData
var hud: Hud
var sfx: Sfx
## Where the save lives; tests point it elsewhere before the node enters the tree.
var save_path := "user://save.json"

var paused := false
var resume_left := 0.0 ## > 0 while counting down to resume
var button_down := false ## the one button as the player holds it right now
var over_shown := false
var new_best := false
var shake := 0.0
var particles: Array[Dictionary] = []
var stars: Array[Dictionary] = []
var _acc := 0.0
var _alpha := 1.0 ## how far between the last two steps we draw
var _vis := RandomNumberGenerator.new() ## looks only (particles, stars, shake); never the game
var _crescent := PackedVector2Array() ## moon shadow shape for radius 1
var _glow: Texture2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(SPACE)
	save = SaveData.new(save_path)
	save.load_file()
	sfx = Sfx.new()
	add_child(sfx)
	sfx.enabled = bool(save.get_setting("sound"))
	hud = Hud.new()
	add_child(hud)
	hud.set_best(save.data.best)
	hud.set_sound(sfx.enabled)
	hud.sound_toggled.connect(_toggle_sound)
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
	_update_frame_cap()


func _resume() -> void:
	paused = false
	resume_left = 0.0
	hud.show_pause(false)
	# a finger kept down through the countdown counts as holding
	sim.holding = button_down
	_update_frame_cap()


func _toggle_sound() -> void:
	sfx.enabled = not sfx.enabled
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
				over_shown = false
				new_best = false
				hud.set_score(0)
				sim.next_seed = _new_seed()
				_update_frame_cap()
			"launch":
				sfx.play("launch")
			"capture":
				if e.first:
					sfx.play(sfx.catch_sound(e.hops))
				else:
					sfx.play("revisit")
				_burst(e.x, e.y, COLORS[e.col], 10, 55.0)
				_vibrate(12)
			"spark":
				_burst(e.x, e.y, SAND, 10, 70.0)
				sfx.play("spark")
			"die":
				_burst(e.x, e.y, INK, 30, 160.0)
				shake = 10.0
				sfx.play("die")
				_vibrate(60)
				_record_run()
	sim.events.clear()


func _record_run() -> void:
	new_best = sim.score > int(save.data.best)
	if new_best:
		save.data.best = sim.score
	save.data.runs = int(save.data.runs) + 1
	save.data.sparks = int(save.data.sparks) + sim.sparks_got
	save.save_file()
	hud.set_best(save.data.best)
	_update_frame_cap()


func _update_hud() -> void:
	hud.set_score(sim.score)
	if sim.state == "over" and not over_shown and sim.t - sim.death_t >= Sim.RESTART_LOCK:
		over_shown = true
		hud.show_over(sim.score, sim.death_why, save.data.best, new_best)
	var hint := ""
	if sim.state == "play" and sim.hops < 3:
		if sim.player.planet != null:
			hint = "Release to fling" if sim.holding else "Tap, or hold and release, to fling"
		else:
			hint = "Keep holding…" if sim.holding else "Hold to catch the next moon"
	hud.set_hint(hint)


func _update_effects(delta: float) -> void:
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

	# background gradient and parallax stars (screen space)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([SPACE, SPACE, SPACE_2, SPACE_2]))
	for s in stars:
		var yy := fposmod(s.y * h - cam.y * s.z * 0.25, h)
		var al: float = (0.35 + 0.35 * sin(t * 1.5 + s.tw)) * s.z
		var r: float = s.z * 1.6 + 0.3
		draw_rect(Rect2(s.x * w, yy, r, r), Color(INK, al))

	var sk := _vis.randf_range(-shake, shake) if shake > 0.0 else 0.0
	draw_set_transform(Vector2(w / 2.0 - cam.x + sk, h / 2.0 - cam.y + sk * 0.6))

	var ship := Vector2(lerpf(p.px, p.x, a), lerpf(p.py, p.y, a))
	var pos := {}
	for pl in sim.planets:
		pos[pl] = Vector2(Sim.planet_x(pl, t), pl.y)

	# capture rings
	for pl in sim.planets:
		if pl.visited and pl != p.planet:
			continue
		var c: Vector2 = pos[pl]
		var inside := p.planet == null and sim.state == "play" and pl != p.last and ship.distance_to(c) < pl.ring
		if inside:
			draw_circle(c, pl.ring, Color(SAND, 0.07), true, -1.0, true)
		var col := SAND if inside else (Color(INK, 0.12) if pl == p.planet else Color(INK, 0.32))
		_dashed_circle(c, pl.ring, 3.0, 7.0, -t * 10.0, 2.4 if inside else 1.4, col)
		if pl.flash > 0.0:
			draw_arc(c, lerpf(p.r_target, pl.ring, pl.flash), 0, TAU, 96, Color(SAND, pl.flash * 0.6), 2.0, true)

	# guide dots for the first hops
	if sim.state == "play" and p.planet != null and sim.hops < 3:
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
		var fade := 0.45 if pl.visited and pl != p.planet else 1.0
		var col: Color = COLORS[pl.col]
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

	# trail and ship
	if sim.state != "over" or sim.t - sim.death_t < 0.05:
		var tr := p.trail
		var n := tr.size()
		for i in range(2, n, 2):
			var f := float(i) / n
			var to: Vector2 = ship if i >= n - 2 else tr[i]
			draw_line(tr[i - 2], to, Color(INK, f * 0.5), maxf(f * 5.0, 0.5), true)
		draw_circle(ship, 5.5, INK, true, -1.0, true)
		if sim.holding and p.planet == null and sim.state == "play":
			draw_arc(ship, 10.0 + sin(t * 14.0) * 1.5, 0, TAU, 32, SAND, 1.5, true)

	# particles
	for q in particles:
		draw_rect(Rect2(q.x - 1.5, q.y - 1.5, 3, 3), Color(q.col, clampf(q.life / 0.9, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO)


## A dotted ring like the prototype's setLineDash([3, 7]) with a moving dash offset.
func _dashed_circle(c: Vector2, r: float, dash: float, gap: float, offset: float, width: float, col: Color) -> void:
	var period := dash + gap
	var n := maxi(8, int(TAU * r / period))
	var step := TAU / n
	var da := step * dash / period
	var off := fposmod(-offset, period) / period * step
	var segs := PackedVector2Array()
	for i in n:
		var a0 := i * step + off
		segs.append(c + Vector2(cos(a0), sin(a0)) * r)
		segs.append(c + Vector2(cos(a0 + da), sin(a0 + da)) * r)
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
