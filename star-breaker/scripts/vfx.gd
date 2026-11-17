class_name VFx
extends RefCounted
## Weapon and impact effects: the laser-strand charge and beam (brought back from the
## landscape game's Nova, turned to fly up the screen), needle bolts, explosions with a shock
## ring, tumbling lit debris and a flash of real light, and hit sparks.
##
## Everything is built from cached meshes and shared materials; only the lights are real
## lights, and there are few of them (one for the charge and beam, two for explosions).

## Strands of the charge laser at each level: 0 pink, 1 cyan, 2 white.
const STRANDS := [[], [], [2], [1, 2], [0, 1, 2]]
## Shapes a charge strand's winding cycles through, and how many go by each tick.
const COIL_SHAPES := 24
const COIL_MORPH := 0.4
## Ticks for one charge-up pulse to close in on the laser ball.
const CHARGE_PULSE := 24.0
## The beam's twister: radius of the hard strands, one pulse's length (one turn), pulses per
## strand, ticks between pulses and their speed. A strand's pulses ride a loop
## PULSES * PULSE_GAP * PULSE_SPEED long (504), longer than the beam, so they line the whole
## beam from its first frame and scroll up along it.
const TWIST_R := 6.5
const TWIST_PITCH := 26.0
const PULSES := 7
const PULSE_GAP := 12
const PULSE_SPEED := 6.0
const PULSE_LEN := 18.0
## Ticks each strand's pulses lag behind the first: pink, cyan, white hard strands, then the
## haze strand riding with each of them.
const PULSE_LAG := [0, 4, 8, 0, 4, 8]
## How wide the twister opens at each charge level.
const TWIST_GROW := [0.0, 0.0, 0.55, 0.72, 1.0]
## Starbreak's strands: no twister, but many short-lived thin jagged arcs of pink, cyan and
## white crackling round the laser like static electricity, with no glow of their own
## (Guillaume's calls: short lived, many of them, erratic). Each arc jolts about at random
## now and then (ARC_JOLT_CHANCE a tick), up to ARC_JOLT.x along the beam and ARC_JOLT.y
## radians round it, for
## ARC_LIFE ticks, then jumps somewhere else.
const ULT_PULSES := 9
## Wider, soft haze strands mixed in among the thin ones, moving the same way.
const ULT_HAZE := 4
const ARC_LIFE := Vector2i(10, 22)
const ARC_JOLT := Vector2(3.0, 0.5)
## Chance an arc jolts on a given tick: it twitches now and then rather than every frame.
const ARC_JOLT_CHANCE := 0.3
const ARC_SHAPES := 12

## Charge colour per level (the ring round the ball) and the light it casts.
const CHARGE_COL := ["4a5470", "dfe9ff", "ffffff", "3ff0e0", "ff4fa3"]

static var _ring_mats: Array = []
static var _band_mats := {}
static var _band_tex: Texture2D


## Additive glow that fades across X and stays even along Y (a beam's haze).
static func band_mat(c: String) -> StandardMaterial3D:
	if _band_mats.has(c):
		return _band_mats[c]
	if _band_tex == null:
		var g := Gradient.new()
		g.set_offset(0, 0.0)
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_offset(1, 1.0)
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 1))
		g.add_point(0.3, Color(1, 1, 1, 0.35))
		g.add_point(0.7, Color(1, 1, 1, 0.35))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 64
		gt.height = 4
		gt.fill = GradientTexture2D.FILL_LINEAR
		gt.fill_from = Vector2(0, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		_band_tex = gt
	var m := Models.add_mat(c)
	m.albedo_texture = _band_tex
	m.albedo_color = Color(c) * Color(1.6, 1.6, 1.6, 1.0)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_band_mats[c] = m
	return m
static var _debris_mats: Array = []


static func init() -> void:
	if not _ring_mats.is_empty():
		return
	for i in 6:
		_ring_mats.append(Models.add_mat("ffc890", 0.9 * (1.0 - i / 6.0)))
	_debris_mats = [Models.std("ffb547", "ff6a00", 1.2), Models.std("ff6fb5", "ff2f8f", 0.9), Models.std("3a3456"), Models.std("5a5080")]
	for st in [0, 3]:
		for v in COIL_SHAPES:
			coil_mesh(st, v)
	for st in 6:
		pulse_mesh(st)


## Materials and meshes to draw once behind the menu (shader warm-up).
static func warm_list() -> Array:
	init()
	var list := []
	for c in ["dfe9ff", "3ff0e0", "ff4fa3"]:
		list.append(Models.mesh(Models.quad(), band_mat(c)))
	for m in _ring_mats + _debris_mats:
		list.append(Models.mesh(ring_mesh(), m))
	for st in 6:
		list.append(Models.mesh(pulse_mesh(st), pulse_mat(st)))
	list.append(Models.mesh(bolt_mesh(), Models.M.shot))
	return list


# ---------- meshes ----------

## Charge strand mesh: shape `v` of the cycle, a hard strand (st < 3) or its haze.
static func coil_mesh(st: int, v: int) -> ArrayMesh:
	var hard := st < 3
	return Geo.cached("coil%s%d" % ["h" if hard else "z", v], func():
		var t := float(v) / COIL_SHAPES * TAU
		return Geo.build_wound(Geo.ball_coil(1.25 + 0.35 * sin(t), 0.07 if hard else 0.2, 48, 4 if hard else 6,
				0.0, 1.4 * sin(t * 2.0 + 0.7), t)))


## Twister strand `st`: 0-2 the hard pink, cyan and white strands, 3-5 the haze strand riding
## with each of them, set between them round the beam. Built along +X.
static func pulse_mesh(st: int) -> ArrayMesh:
	return Geo.cached("vpulse%d" % st, func(): return Geo.build_wound(Geo.helix(PULSE_LEN,
			TWIST_R if st < 3 else TWIST_R + 1.2, TWIST_PITCH, 0.75 if st < 3 else 2.2, 4 if st < 3 else 6,
			(st % 3) * TAU / 3.0 + (0.0 if st < 3 else PI / 3.0))))


static func pulse_mat(st: int) -> Material:
	return [Models.M.twist_a, Models.M.twist_b, Models.M.twist_w, Models.M.twist_ga, Models.M.twist_gb, Models.M.twist_gw][st]


## A needle bolt: a long thin diamond along +Y.
static func bolt_mesh() -> ArrayMesh:
	return Models.geo("vbolt", func(): return Geo.xf(Geo.octa(1.0), Transform3D(Basis().scaled(Vector3(0.42, 3.2, 0.42)), Vector3.ZERO)))


## A flat ring of radius 1 in the XY plane (shock waves).
static func ring_mesh() -> ArrayMesh:
	return Geo.cached("vshock", func(): return Geo.build_facing(Geo.ring(0.9, 1.0, 24), Vector3.BACK))


static func shard_mesh() -> ArrayMesh:
	return Models.geo("vshard", func(): return Geo.xf(Geo.tetra(1.0), Transform3D(Basis().scaled(Vector3(1.0, 1.7, 0.6)), Vector3.ZERO)))


# ---------- shots ----------

## A player shot: a bright needle with a soft glow stretched along its path.
static func bolt(mat: Material, glow: String) -> Node3D:
	var n := Node3D.new()
	var core := Models.mesh(bolt_mesh(), mat)
	n.add_child(core)
	var g := Models.glow(glow, 1.0)
	g.scale = Vector3(3.2, 11.0, 1)
	g.position = Vector3(0, -2.5, -0.5)
	n.add_child(g)
	return n


# ---------- the charge ----------

## The charge-up node: haze, glow, core and laser ball, then the six strands.
static func charge_node() -> Node3D:
	init()
	var n := Node3D.new()
	for c in ["3a3a60", "8a90b0", "ffffff"]:
		n.add_child(Models.glow(c, 1.0))
	n.add_child(Models.mesh(Models.geo("orb", func(): return Geo.ico(1, 1)), Models.M.beam))
	for st in 6:
		n.add_child(Models.mesh(coil_mesh(st, 0), pulse_mat(st)))
	return n


## The charge-up: a laser ball at the nose that grows as it charges, with the level's strands
## coiled round it pulsing in, staggered out of phase: none at level 1, white at 2, cyan and
## white at 3, pink, cyan and white at the Nova. They are the strands the beam will fire.
static func sync_charge(n: Node3D, charge: int, charge_max: int, lv: int, tt: int, ph: float) -> void:
	var k := float(charge) / charge_max
	var rad := 2.0 + k * 3.6
	var haze: MeshInstance3D = n.get_child(0)
	var glow: MeshInstance3D = n.get_child(1)
	var core: MeshInstance3D = n.get_child(2)
	var ball: MeshInstance3D = n.get_child(3)
	haze.scale = Vector3(1, 1, 0) * rad * 3.2 * (1.0 + sin(tt * 0.37) * 0.08) + Vector3.BACK
	glow.scale = Vector3(1, 1, 0) * rad * 1.5 * (1.0 + sin(tt * 0.9) * 0.1) + Vector3.BACK
	core.scale = Vector3(1, 1, 0) * rad * 0.8 * (1.0 + sin(tt * 1.7) * 0.12) + Vector3.BACK
	ball.scale = Vector3.ONE * rad * 0.5
	var on: Array = STRANDS[lv]
	for st in 6:
		var m: MeshInstance3D = n.get_child(4 + st)
		m.visible = on.has(st % 3)
		if not m.visible:
			continue
		# each pulse closes in from a little way out until it hugs the ball, then starts again
		var p := fposmod((charge + PULSE_LAG[st] * 2.0) / CHARGE_PULSE, 1.0)
		var hug := 0.75 + 0.55 * (1.0 - p) * (1.0 - p)
		var r := rad * hug * (1.0 if st < 3 else 1.1)
		# the winding keeps changing: looser and tighter, bending one way then the other
		m.mesh = coil_mesh(st, int(floor(tt * COIL_MORPH * (1.0 + 0.25 * (st % 3)) + st * 5)) % COIL_SHAPES)
		# the coil's axis runs along the flight (up the screen)
		m.basis = Basis(Vector3.BACK, PI / 2) * Basis(Vector3.RIGHT, -ph * (1.0 + 0.3 * (st % 3)) + (st % 3) * TAU / 3.0
				+ (0.0 if st < 3 else PI / 3.0)) * Basis(Vector3.BACK, 0.3 * (st % 3)).scaled(Vector3.ONE * r)


# ---------- the beam ----------

## The laser line: a white core in a soft sheath and haze, a flare at the muzzle, a flare where
## it strikes, and from level 2 the twister: corkscrew pulses of the level's strands lining
## the whole beam and streaming up it, staggered out of phase.
static func beam_node(lv: int, ult := false) -> Node3D:
	init()
	var n := Node3D.new()
	var rod := Models.geo("vbrod", func(): return Geo.xf(Geo.cyl(0.5, 0.5, 1.0, 6), Transform3D(Basis(), Vector3(0, 0.5, 0))))
	var core := Models.mesh(rod, Models.M.beam)
	var sheath := Models.mesh(rod, Models.M.laser_glow)
	var col: String = CHARGE_COL[lv] if lv >= 3 else "dfe9ff"
	# the haze is a band, soft across but even along its whole length (a radial glow
	# stretched up the screen would bulge in the middle and taper at the ends)
	var haze := Models.glow(col, 1.0)
	haze.material_override = band_mat(col)
	var flare := Models.glow("ffffff", 1.0)
	var tip := Models.glow(col, 1.0)
	for c in [haze, sheath, core, flare, tip]:
		n.add_child(c)
	var parts := {core = core, sheath = sheath, haze = haze, flare = flare, tip = tip, pulses = []}
	if ult:
		for i in ULT_PULSES:
			var st := i % 3
			var hard := Models.mesh(arc_mesh(0, true), pulse_mat(st))
			var g := Node3D.new()
			g.add_child(hard)
			n.add_child(g)
			var pl := {n = g, hard = hard}
			parts.pulses.append(pl)
		for i in ULT_HAZE:
			var soft := Models.mesh(arc_mesh(0, false), pulse_mat(i % 3 + 3))
			var g := Node3D.new()
			g.add_child(soft)
			n.add_child(g)
			parts.pulses.append({n = g, soft = soft})
		# no haze and no ball at the bottom: the static arcs alone light the beam
		haze.visible = false
		flare.visible = false
		parts.ult = true
	elif lv >= 2:
		for st in 6:
			if not (STRANDS[lv] as Array).has(st % 3):
				continue
			for i in PULSES:
				var pl := Models.mesh(pulse_mesh(st), pulse_mat(st))
				pl.set_meta("lag", PULSE_LAG[st])
				pl.set_meta("i", i)
				n.add_child(pl)
				parts.pulses.append(pl)
	n.set_meta("parts", parts)
	return n


## Where pulse `i` of a strand lagging `lag` ticks sits along the beam at tick `t`.
static func pulse_y(i: int, lag: int, t: float) -> float:
	var gap := PULSE_GAP * PULSE_SPEED
	return fposmod((i * PULSE_GAP + t - lag) * PULSE_SPEED, PULSES * gap)


## A Starbreak arc jumps somewhere new on the beam: shape, angle, size and a short life.
static func _respawn(pl: Dictionary, len: float) -> void:
	pl.len = randf_range(13.0, 32.0)
	pl.y = randf() * maxf(1.0, len - pl.len)
	pl.ang = randf() * TAU
	pl.r = randf_range(0.6, 1.15)
	pl.flip = randf() < 0.5
	pl.life = randi_range(ARC_LIFE.x, ARC_LIFE.y)
	pl.t = 0
	var v := randi() % ARC_SHAPES
	if pl.has("hard"):
		(pl.hard as MeshInstance3D).mesh = arc_mesh(v, true)
	else:
		(pl.soft as MeshInstance3D).mesh = arc_mesh(v, false)


## Lays out a beam `len` long and `w` wide (already faded), `t` ticks into its life.
static func sync_beam(n: Node3D, lv: int, len: float, w: float, fade: float, t: int, tt: int, hit_end: bool) -> void:
	var p: Dictionary = n.get_meta("parts")
	var open := 1.0 + maxf(0.0, 3.0 - t) * 0.2
	var cw := maxf(0.15, w * 0.3 * open)
	(p.core as Node3D).scale = Vector3(cw, len, cw)
	(p.sheath as Node3D).scale = Vector3(cw * 2.1, len, cw * 2.1)
	var haze: Node3D = p.haze
	haze.position = Vector3(0, len / 2.0, -0.5)
	haze.scale = Vector3(w * 2.3 * open, len, 1)
	var fs := w * (2.6 + 0.6 * sin(tt * 1.7)) * fade + 0.01
	(p.flare as Node3D).scale = Vector3(fs * 1.3, fs, 1)
	(p.flare as Node3D).position = Vector3(0, 0, 1)
	var tip: Node3D = p.tip
	tip.visible = hit_end
	tip.position = Vector3(0, len, 1)
	tip.scale = Vector3(1, 1, 0) * (w * 3.0 * fade * (1.0 + 0.25 * sin(tt * 2.3)) + 0.01) + Vector3.BACK
	if p.has("ult"):
		_sync_ult(p.pulses, len, w, fade, t)
		return
	var spin := t * 0.35
	for pl in p.pulses:
		var y := pulse_y(int(pl.get_meta("i")), int(pl.get_meta("lag")), t)
		pl.visible = y + PULSE_LEN < len
		if not pl.visible:
			continue
		# each pulse opens up a little as it travels, spinning as it goes
		var grow: float = (0.75 + 0.35 * minf(1.0, y / 110.0)) * fade * TWIST_GROW[lv]
		pl.position = Vector3(0, y, 0)
		pl.basis = Basis(Vector3.BACK, PI / 2) * Basis(Vector3.RIGHT, -spin) * Basis().scaled(Vector3(1, grow, grow))


## A jagged arc of static jumping out of the beam, curling part of the way round it and back
## in: shape `v`, along +X over a length of 1 and round a radius of 1, a hard strand or its haze.
static func arc_mesh(v: int, hard: bool) -> ArrayMesh:
	return Geo.cached("uarc%s%d" % ["h" if hard else "z", v], func():
		var rng := RandomNumberGenerator.new()
		rng.seed = v * 977 + 5
		var span := rng.randf_range(0.5, 1.2) * TAU
		var n := 9
		var pts := []
		for i in n + 1:
			var u := float(i) / n
			# leaves the core, kinks its way round at about the beam's radius, dives back in
			var rr := lerpf(0.35, 1.0, sin(u * PI)) * (1.0 + (rng.randf_range(-0.28, 0.28) if i > 0 and i < n else 0.0))
			var a := u * span + (rng.randf_range(-0.25, 0.25) if i > 0 and i < n else 0.0)
			var x := u + (rng.randf_range(-0.06, 0.06) if i > 0 and i < n else 0.0)
			pts.append(Vector3(x, cos(a) * rr, sin(a) * rr))
		var tube := 0.018 if hard else 0.07
		var sides := 3 if hard else 4
		var tris := []
		for i in n:
			var p0: Vector3 = pts[i]
			var p1: Vector3 = pts[i + 1]
			var d := (p1 - p0).normalized()
			var side := d.cross(Vector3.RIGHT if absf(d.x) < 0.9 else Vector3.UP).normalized()
			var up := d.cross(side).normalized()
			var r0 := []
			var r1 := []
			for k in sides:
				var a := TAU * k / sides
				var o := (side * cos(a) + up * sin(a)) * tube
				r0.append(p0 + o)
				r1.append(p1 + o)
			var m := (p0 + p1) / 2.0
			for k in sides:
				var k2 := (k + 1) % sides
				tris.append(Geo.orient([r0[k], r1[k], r1[k2]], m))
				tris.append(Geo.orient([r0[k], r1[k2], r0[k2]], m))
		return Geo.build_wound(tris))


## Starbreak's static: each arc jolts about erratically along and round the beam for a few
## ticks, keeping its shape, then jumps elsewhere with a new one.
static func _sync_ult(pulses: Array, len: float, w: float, fade: float, t: int) -> void:
	var R := w / maxf(fade, 0.05) * 0.8
	for pl in pulses:
		if not pl.has("life"):
			_respawn(pl, len)
			# stagger so the arcs don't all jump on the same tick
			pl.t = randi() % int(pl.life)
		pl.t += 1
		if randf() < ARC_JOLT_CHANCE:
			pl.y += randf_range(-ARC_JOLT.x, ARC_JOLT.x)
			pl.ang += randf_range(-ARC_JOLT.y, ARC_JOLT.y)
		if pl.t > pl.life or pl.y < 0.0 or pl.y + pl.len > len:
			_respawn(pl, len)
		var g: Node3D = pl.n
		g.visible = fade > 0.05 and pl.y + pl.len <= len
		if not g.visible:
			continue
		var r: float = R * pl.r * (0.6 + 0.4 * fade)
		g.position = Vector3(0, pl.y, 0)
		g.basis = Basis(Vector3.UP, pl.ang) * Basis(Vector3.BACK, PI / 2) * Basis().scaled(Vector3(pl.len * (-1.0 if pl.flip else 1.0), r, r))
