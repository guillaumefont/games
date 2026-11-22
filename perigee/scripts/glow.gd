class_name GlowLayer
extends Node2D
## The light pass, drawn over the game with additive blending: a cheap bloom (soft halos added
## on top of the moons, the ship, its trail and the sparks), the shockwave rings that a catch
## sends out, and the brief flash of the screen on a perigee, a leap or a clear. Additive halos
## from one small texture cost far less than a real post-process bloom, which matters on phones
## and in the web build. Looks only: it reads Main and the sim, and never feeds anything back.

const INK := Color("f3ecdf")
const SAND := Color("f2c879")
const TEAL := Color("6fd6c5")
const CORAL := Color("ff8a6b")
const LILAC := Color("b49cff")

var main: Node2D


func setup(owner_main: Node2D) -> void:
	main = owner_main
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


## The trail's colour for a combo: it warms up from white to teal, gold and coral as the
## multiplier climbs, so the streak shows in the ship's wake.
static func combo_color(mult: int) -> Color:
	match mini(mult, 5):
		1:
			return INK
		2:
			return TEAL
		3:
			return TEAL.lerp(SAND, 0.5)
		4:
			return SAND
		_:
			return CORAL


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var sim: Sim = main.sim
	var size := get_viewport_rect().size
	var tex: Texture2D = main.bloom_texture()
	var t: float = main.view_time()
	var cam: Vector2 = main.view_cam()
	var a: float = main._alpha
	var p := sim.player
	var calm: bool = main.save.get_setting("reduced_motion")
	draw_set_transform(main.world_offset())

	# moons: a wide soft bloom in their colour, brighter on the moon being orbited
	for pl in sim.planets:
		var c := Vector2(Sim.planet_x(pl, t), pl.y)
		if c.y < cam.y - size.y or c.y > cam.y + size.y:
			continue
		var fade := 0.25 if pl.skipped else (0.45 if pl.visited and pl != p.planet else 1.0)
		var col: Color = main._palette[pl.col]
		var gr := pl.pr * 3.4
		var k := 0.28 + 0.25 * pl.flash
		if pl == p.planet:
			k += 0.08
		_halo(tex, c, gr, Color(col, k * fade))
		_halo(tex, c, pl.pr * 1.5, Color(col.lerp(INK, 0.4), 0.22 * fade))
		if pl.kind == "pulsar" and pl.lit(t):
			var beat := 0.5 + 0.5 * sin(t * TAU / Sim.PULSAR_PERIOD * 2.0)
			_halo(tex, c, pl.pr * (1.4 + 0.6 * beat), Color(INK, 0.45 * fade))

	# sparks
	for s in sim.sparks:
		if s.got:
			continue
		var pulse := 1.0 + 0.25 * sin(t * 5.0 + s.x)
		_halo(tex, Vector2(s.x, s.y), 16.0 * pulse, Color(SAND, 0.4))

	# the ship and its wake, tinted by the combo
	if sim.state != "over" or sim.t - sim.death_t < 0.05:
		var ship := Vector2(lerpf(p.px, p.x, a), lerpf(p.py, p.y, a))
		var cc := combo_color(sim.mult)
		var tr := p.trail
		var n := tr.size()
		var heat := clampf((sim.mult - 1) / 4.0, 0.0, 1.0)
		for i in range(2, n, 2):
			var f := float(i) / n
			var from: Vector2 = tr[i - 2]
			var to: Vector2 = ship if i >= n - 2 else tr[i]
			draw_line(from, to, Color(cc, f * (0.16 + 0.22 * heat)), maxf(f * (7.0 + 8.0 * heat), 1.0), true)
		_halo(tex, ship, 22.0 + 10.0 * heat, Color(cc, 0.42 + 0.2 * heat))
		_halo(tex, ship, 9.0, Color(INK, 0.5))

	# shockwaves from catches
	for wv in main.shockwaves:
		var k: float = 1.0 - wv.life / wv.max
		var e := 1.0 - pow(1.0 - k, 3.0) # ease out
		var r: float = lerpf(wv.r0, wv.r1, e)
		var al: float = (1.0 - k) * wv.al
		draw_arc(Vector2(wv.x, wv.y), r, 0, TAU, 64, Color(wv.col, al), wv.w * (1.0 - 0.6 * k), true)
		draw_arc(Vector2(wv.x, wv.y), r * 0.92, 0, TAU, 64, Color(wv.col, al * 0.35), wv.w * 2.5 * (1.0 - 0.6 * k), true)

	# burst particles
	for q in main.particles:
		_halo(tex, Vector2(q.x, q.y), 5.0, Color(q.col, 0.5 * clampf(q.life / 0.9, 0.0, 1.0)))

	# score popups glow softly in their colour
	for q in main.popups:
		var al := clampf(q.life / 0.5, 0.0, 1.0)
		_halo(tex, Vector2(q.x, q.y - 5.0), 26.0, Color(q.col, 0.16 * al))

	# the screen pulse
	draw_set_transform(Vector2.ZERO)
	if main.pulse > 0.0 and not calm:
		draw_rect(Rect2(Vector2.ZERO, size), Color(main.pulse_col, main.pulse))


func _halo(tex: Texture2D, c: Vector2, r: float, col: Color) -> void:
	draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)
