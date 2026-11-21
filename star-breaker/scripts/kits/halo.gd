extends ShipKit
## Halo, the blade ring: four blades circle the ship all the time, cutting the bullets and
## enemies they touch. Holding spins the ring wider (more reach, wider gaps between blades);
## lifting snaps it tight with a burst that hits everything that was inside it. The gun is
## weak: this is the ship that flies into the wave. Bullets cut load the Sawstorm: twelve
## blades at full width.

const BLADES := 4
const STORM_BLADES := 12
const R_MIN := 9.0
const R_MAX := 27.0
const GROW := 0.22        ## ring growth a tick while holding
const SPIN := 0.2
const BLADE_R := 3.6
const BLADE_DMG := 2.0
const BLADE_EVERY := 5
const BURST := 9.0
const CUT_GAIN := 1.0 / 40.0
const HIT_GAIN := 1.0 / 120.0
const STORM_T := 300

var r := R_MIN
var ang := 0.0
var blades: Array = []
var ring_m: MeshInstance3D
var burst_m: MeshInstance3D
var burst_t := 0
var burst_r := 0.0
var storm := 0


func start() -> void:
	var mesh := Models.geo("haloBlade", func(): return Geo.xf(Geo.octa(1.0), Transform3D(Basis().scaled(Vector3(1.1, 3.4, 0.5)), Vector3.ZERO)))
	for i in STORM_BLADES:
		var m := Models.mesh(mesh, Models.M.crystal_c)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.add_child(Models.glow("4fe3d6", 5.0))
		m.visible = false
		blades.append(own(m))
	ring_m = own(ring_node("4fe3d6", 0.35)) as MeshInstance3D
	burst_m = own(ring_node("ffffff", 0.9)) as MeshInstance3D
	burst_m.visible = false


func count() -> int:
	return STORM_BLADES if storm > 0 else BLADES


func radius() -> float:
	return R_MAX + 7.0 if storm > 0 else r


func blade(i: int) -> Vector2:
	var a := ang + TAU * i / count()
	return Vector2(g.P.x + cos(a) * radius(), g.P.y + sin(a) * radius())


func fire() -> void:
	g.shot(g.P.x, g.P.y + 8, 0, float(VShips.KITS.halo.shot_speed), Models.M.shot, 1)


func hold() -> void:
	r = minf(R_MAX, r + GROW)


func lift() -> void:
	if r < R_MIN + 3.0:
		return
	var res := blast(g.P.x, g.P.y, r, BURST)
	var n := wipe(g.P.x, g.P.y, r)
	gain(n * CUT_GAIN + res[0] * HIT_GAIN * 4.0)
	burst_r = r
	burst_t = 10
	r = R_MIN
	g.audio.play("beam", 1)
	g.shake = maxf(g.shake, 2.0 + res[0])
	Diag.once("halo burst")


func ult() -> void:
	storm = STORM_T
	g.G.ult_t = STORM_T
	g.audio.play("beam", 4)
	g.shake = maxf(g.shake, 6.0)


func update() -> void:
	if burst_t > 0:
		burst_t -= 1
	if storm > 0:
		storm -= 1
	if not g.P.alive or g.G.has("run") or g.P.entering:
		return
	ang += SPIN * (1.4 if storm > 0 else 1.0)
	var dmg := BLADE_DMG * (2.0 if storm > 0 else 1.0)
	var ts := targets() if g.G.t % BLADE_EVERY == 0 else []
	for i in count():
		var b := blade(i)
		for bl in g.G.eb:
			if not bl.get("dead", false) and absf(bl.x - b.x) < BLADE_R and absf(bl.y - b.y) < BLADE_R:
				bl.dead = true
				g.spark(bl.x, bl.y)
				gain(CUT_GAIN)
		for t in ts:
			if absf(t.x - b.x) < t.hw + BLADE_R and absf(t.y - b.y) < t.hh + BLADE_R:
				strike(t, dmg)
				gain(HIT_GAIN)


func reset() -> void:
	super.reset()
	r = R_MIN
	storm = 0


func hint() -> String:
	if storm > 0:
		return "SAWSTORM"
	if ready():
		return "FULL: LIFT FOR THE SAWSTORM"
	return "HOLD: THE RING WIDENS  ·  LIFT: BURST"


func sync() -> void:
	var on: bool = g.P.alive and not g.G.has("run")
	var z: float = 1.0 + g.P.get("z", 0.0)
	for i in STORM_BLADES:
		var m: Node3D = blades[i]
		m.visible = on and i < count()
		if m.visible:
			var b := blade(i)
			m.position = Vector3(g.X(b.x), g.Y(b.y), z)
			m.rotation.z = ang + TAU * i / count()
	ring_m.visible = on
	if on:
		ring_m.position = Vector3(g.X(g.P.x), g.Y(g.P.y), z - 0.5)
		ring_m.scale = Vector3.ONE * radius()
	burst_m.visible = burst_t > 0
	if burst_t > 0:
		burst_m.position = Vector3(g.X(g.P.x), g.Y(g.P.y), 3.0)
		burst_m.scale = Vector3.ONE * lerpf(burst_r, R_MIN, 1.0 - burst_t / 10.0)
