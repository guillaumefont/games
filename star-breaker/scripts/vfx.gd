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
## The charge strands' twister pieces (they coil round the charge ball): radius, one pulse's
## length (one turn).
const TWIST_R := 6.5
const TWIST_PITCH := 26.0
const PULSE_LEN := 18.0
## Ticks each strand's pulses lag behind the first: pink, cyan, white hard strands, then the
## haze strand riding with each of them.
const PULSE_LAG := [0, 4, 8, 0, 4, 8]
## The Storm (Lance's ultimate): forked chain lightning, re-drawn every STORM_FLICKER ticks
## so it jitters, a white core in a cyan sheath and a pink haze, and a flash on each target.
const STORM_FLICKER := 3
## Kinks per stage unit of bolt, and how far a kink strays sideways (part of the hop's length,
## capped in stage units).
const STORM_KINKS := 0.16
const STORM_JAG := Vector2(0.14, 7.0)
## Layer widths (stage units): haze, sheath, core.
## Bulky like the Nova beam (Guillaume, 2026-11-20: "bulkier, like the laser").
const STORM_W := [10.0, 4.0, 1.6]
## Layer strength: haze, sheath, core (additive, so they don't wash out to white).
const STORM_ALPHA := [0.4, 0.75, 1.0]
const STORM_FLASHES := 48
## Width of the charge beam's lightning per level (1 = the Storm's), LV 1 to the Nova.
const BEAM_SCALE := [0.0, 0.9, 1.2, 1.5, 2.0]

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

## The charge beam (every level, LV 1 to the Nova) in the Storm's look: a bolt of lightning
## straight up from the nose, wider level by level (Guillaume, 2026-11-20: "make the previous
## weapon levels look the same" as the Storm). Hits are unchanged: a straight column BEAM_W wide.
static func beam_node(_lv: int) -> Node3D:
	return storm_node()


## Lays out a beam `len` long and `w` wide (already faded), `t` ticks into its life: a bolt up
## from the nose that kinks no wider than the beam hits, with short forks from LV 2, and a
## flash where it strikes a barrier.
static func sync_beam(n: Node3D, lv: int, len: float, w: float, fade: float, _t: int, tt: int, hit_end: bool) -> void:
	var ws: float = BEAM_SCALE[lv]
	var bolt := [Vector3.ZERO, Vector3(0, len, 0)]
	var full: float = w / maxf(fade, 0.05)
	draw_bolts(n, [bolt], fade, tt, ws, maxf(0.8, full * 0.6), 6.0 + 10.0 * ws if lv >= 2 else 0.0, hit_end)
	# a flash at the muzzle too
	var g: Node3D = n.get_child(4)
	g.visible = fade > 0.0
	g.position = Vector3(0, 0, 1)
	g.scale = Vector3(1, 1, 0) * (3.0 + 5.0 * ws) * fade + Vector3.BACK


# ---------- the Storm ----------

## The Storm: three ribbon layers (redrawn as it flickers) and a pool of flashes for the targets.
static func storm_node() -> Node3D:
	init()
	var n := Node3D.new()
	var mats := []
	for k in 3:
		var m: StandardMaterial3D = band_mat(["ff4fa3", "3ff0e0", "ffffff"][k]).duplicate()
		m.albedo_color = Color(["ff4fa3", "3ff0e0", "ffffff"][k], STORM_ALPHA[k])
		mats.append(m)
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		mi.material_override = mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.z = k * 0.1
		n.add_child(mi)
	for k in STORM_FLASHES:
		var g := Models.glow("dfe9ff" if k % 2 else "ff4fa3", 1.0)
		g.visible = false
		n.add_child(g)
	return n


## A jagged path from `a` to `b` (3D, in the play plane): kinks stray sideways at random, the
## ends stay put.
static func storm_path(a: Vector3, b: Vector3, rng: RandomNumberGenerator, jag_cap := STORM_JAG.y) -> PackedVector3Array:
	var d := b - a
	var len := maxf(0.01, Vector2(d.x, d.y).length())
	var side := Vector3(-d.y, d.x, 0.0) / len
	var n := clampi(int(len * STORM_KINKS), 3, 24)
	var jag := minf(len * STORM_JAG.x, jag_cap)
	var pts := PackedVector3Array()
	for i in n + 1:
		var u := float(i) / n
		var off := 0.0 if i == 0 or i == n else rng.randf_range(-jag, jag) * sin(u * PI)
		pts.append(a + d * u + side * off)
	return pts


## Lays the storm out `t` ticks in (of `life`): `bolts` are [from, to] pairs in 3D. Every bolt
## gets a fork or two off its kinks, and each target a flash.
static func sync_storm(n: Node3D, bolts: Array, t: int, life: int, tt: int) -> void:
	draw_bolts(n, bolts, clampf(float(life - t) / 20.0, 0.0, 1.0), tt)


## Draws lightning `bolts` ([from, to] pairs in 3D, in `n`'s space) into a storm node at `fade`
## (0-1): `wscale` scales the layers' width, `jag_cap` how far a kink strays (stage units),
## `fork_cap` how long a fork runs, and `flash` lights the end of each bolt.
static func draw_bolts(n: Node3D, bolts: Array, fade: float, tt: int, wscale := 1.0, jag_cap := STORM_JAG.y,
		fork_cap := 1e6, flash := true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = n.get_instance_id() + int(tt / STORM_FLICKER) * 7919
	var paths := []
	for bo in bolts:
		var pts := storm_path(bo[0], bo[1], rng, jag_cap)
		paths.append([pts, 1.0])
		# forks: short side branches off a kink, dying out
		for f in (rng.randi_range(1, 2) if fork_cap > 0.0 else 0):
			var k := rng.randi_range(1, pts.size() - 2)
			var dir: Vector3 = (pts[k + 1] - pts[k - 1]).normalized().rotated(Vector3.BACK, rng.randf_range(-1.0, 1.0))
			var flen: float = minf(fork_cap, (bo[1] - bo[0]).length() * rng.randf_range(0.15, 0.35))
			paths.append([storm_path(pts[k], pts[k] + dir * flen, rng, jag_cap), 0.55])
	for k in 3:
		var im: ImmediateMesh = (n.get_child(k) as MeshInstance3D).mesh
		im.clear_surfaces()
		if paths.is_empty() or fade <= 0.0:
			continue
		var w: float = STORM_W[k] * wscale * (0.6 + 0.4 * fade) * (0.85 + 0.3 * rng.randf())
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for pa in paths:
			var pts: PackedVector3Array = pa[0]
			# forks are thinner than the bolts
			var pw: float = w * pa[1]
			for i in pts.size() - 1:
				var p0 := pts[i]
				var p1 := pts[i + 1]
				var sd := (p1 - p0)
				sd = Vector3(-sd.y, sd.x, 0.0).normalized() * pw * 0.5
				var q := [p0 - sd, p0 + sd, p1 + sd, p1 - sd]
				for v in [0, 1, 2, 0, 2, 3]:
					im.surface_set_uv(Vector2(0.0 if v == 0 or v == 3 else 1.0, 0.5))
					im.surface_add_vertex(q[v])
		im.surface_end()
	for k in STORM_FLASHES:
		var g: Node3D = n.get_child(3 + k)
		g.visible = flash and k < bolts.size() and fade > 0.0
		if g.visible:
			g.position = bolts[k][1] + Vector3(0, 0, 1)
			g.scale = Vector3(1, 1, 0) * (6.0 + 3.0 * rng.randf()) * fade * maxf(0.5, wscale) + Vector3.BACK

