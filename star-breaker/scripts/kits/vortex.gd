extends ShipKit
## Vortex, the gravity ship: holding grows a well at the nose that swallows the bullets near it.
## Lifting leaves the well where it is: it stays put, drags fliers and bullets in for WELL_T
## ticks, then implodes, harder the more it was fed. You never steer it. What the wells swallow
## and crush loads the Event Horizon: one huge well in the middle of the screen.

const MIN_HOLD := 15
const FULL := 90          ## ticks of hold for a full-size well
const NOSE := 13.0
const WELL_T := 100
const PULL_R := 46.0
const PULL := 0.7
const EAT_R := 6.0
const BLAST_R := 24.0
const DMG := 6.0
const DMG_SIZE := 9.0
const DMG_FED := 0.5      ## extra damage per bullet swallowed (up to FED_CAP)
const FED_CAP := 16
const EAT_GAIN := 1.0 / 60.0
const KILL_GAIN := 1.0 / 16.0
const HORIZON_T := 170

var size := 0.0           ## the well at the nose, 0 to 1
var fed := 0
var wells: Array = []     ## {x, y, t, life, size, fed, m, big}
var nose_m: Node3D


func start() -> void:
	nose_m = own(_well_node())
	nose_m.visible = false


func _well_node() -> Node3D:
	var n := Node3D.new()
	var core := Models.mesh(Models.geo("vorCore", func(): return Geo.ico(1.0, 1)), Models.M.disc)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	n.add_child(ring_node("ff5fd2", 0.9))
	var outer := ring_node("8c7bff", 0.5)
	outer.scale = Vector3.ONE * 1.6
	n.add_child(outer)
	n.add_child(Models.glow("8c7bff", 4.0))
	return n


func fire() -> void:
	var sp: float = VShips.KITS.vortex.shot_speed
	g.shot(g.P.x - 2.6, g.P.y + 7, 0, sp, Models.M.shot, 1, "8c7bff")
	g.shot(g.P.x + 2.6, g.P.y + 7, 0, sp, Models.M.shot, 1, "8c7bff")


func nose() -> Vector2:
	return Vector2(g.P.x, g.P.y + NOSE)


func hold() -> void:
	size = minf(1.0, float(held) / FULL)
	var n := nose()
	var got := wipe(n.x, n.y, 4.0 + 7.0 * size)
	if got > 0:
		fed += got
		gain(got * EAT_GAIN)


func lift() -> void:
	if held < MIN_HOLD:
		size = 0.0
		fed = 0
		return
	var n := nose()
	var m := _well_node()
	g.world.add_child(m)
	wells.append({x = n.x, y = n.y, t = 0, life = WELL_T, size = size, fed = fed, m = m, big = false})
	size = 0.0
	fed = 0
	g.audio.play("pod")
	Diag.once("vortex well")


func ult() -> void:
	var m := _well_node()
	g.world.add_child(m)
	wells.append({x = g.W / 2.0, y = 135.0, t = 0, life = HORIZON_T, size = 1.0, fed = FED_CAP, m = m, big = true})
	g.G.ult_t = HORIZON_T
	g.audio.play("alarm")
	g.shake = maxf(g.shake, 6.0)


func update() -> void:
	if not holding():
		size = 0.0
	for w in wells:
		w.t += 1
		var pr: float = 220.0 if w.big else PULL_R
		var pull: float = PULL * (1.6 if w.big else 1.0)
		for b in g.G.eb:
			if b.get("dead", false):
				continue
			var d := Vector2(w.x - b.x, w.y - b.y)
			var l := d.length()
			if l < EAT_R * (2.5 if w.big else 1.0):
				b.dead = true
				w.fed = mini(FED_CAP, int(w.fed) + 1)
				gain(EAT_GAIN)
			elif l < pr:
				var v := Vector2(b.vx, b.vy) * 0.94 + d / l * 0.22 * (1.6 if w.big else 1.0)
				b.vx = v.x
				b.vy = v.y
		# fliers are dragged in (not what stands on the ground, not mid-bosses)
		for e in g.G.enemies:
			if e.ground or e.get("boss", false) or e.get("dead", false) or e.type in g.BIG:
				continue
			var d2 := Vector2(w.x - e.x, w.y - e.y)
			var l2 := d2.length()
			if l2 < pr and l2 > 1.5:
				var step := d2 / l2 * minf(pull, l2)
				e.x += step.x
				e.y += step.y
				if e.has("x0"):
					e.x0 += step.x
		if w.t >= w.life:
			_implode(w)
			w.m.queue_free()
	wells = wells.filter(func(w): return w.t < w.life)


func _implode(w: Dictionary) -> void:
	var rr: float = 70.0 if w.big else BLAST_R * (0.7 + 0.5 * float(w.size))
	var d: float = 34.0 if w.big else DMG + DMG_SIZE * float(w.size) + DMG_FED * int(w.fed)
	var res := blast(w.x, w.y, rr, d)
	wipe(w.x, w.y, rr)
	if not w.big:
		gain(res[1] * KILL_GAIN)
	g.boom(w.x, w.y, rr * 0.6, true)
	g.glow_fx("ff5fd2", w.x, w.y, 2, rr * 2.2, 12)
	g.audio.play("boom")
	g.shake = maxf(g.shake, 10.0 if w.big else 4.0)


func clear() -> void:
	for w in wells:
		w.m.queue_free()
	wells = []
	super.clear()


func reset() -> void:
	super.reset()
	size = 0.0
	fed = 0


func hint() -> String:
	if ready():
		return "FULL: LIFT FOR THE EVENT HORIZON"
	if holding() and held >= MIN_HOLD:
		return "LIFT TO LEAVE THE WELL HERE"
	return "HOLD: A WELL GROWS AND EATS BULLETS"


func sync() -> void:
	var on := holding() and held >= 4
	nose_m.visible = on
	if on:
		var n := nose()
		nose_m.position = Vector3(g.X(n.x), g.Y(n.y), 2.0)
		nose_m.scale = Vector3.ONE * (1.5 + 4.5 * size)
		nose_m.get_child(1).rotation.z = g.tt * 0.2
	for w in wells:
		var f := float(w.t) / float(w.life)
		var s: float = (22.0 if w.big else 3.0 + 5.0 * float(w.size)) * (1.0 + 0.25 * sin(w.t * 0.4)) * (1.0 - 0.6 * maxf(0.0, f * 5.0 - 4.0))
		w.m.position = Vector3(g.X(w.x), g.Y(w.y), 2.0)
		w.m.scale = Vector3.ONE * s
		w.m.get_child(1).rotation.z = -w.t * 0.25
		w.m.get_child(2).rotation.z = w.t * 0.12
		w.m.get_child(2).scale = Vector3.ONE * (1.6 + (PULL_R / s - 1.6) * (1.0 - fmod(w.t * 0.04, 1.0)) * 0.5)
