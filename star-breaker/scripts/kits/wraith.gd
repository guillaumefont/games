extends ShipKit
## Wraith, the phantom: lifting the thumb phases the ship out. Phased, nothing can touch it
## (bullets, enemies and rock pass through) and it does not fire, for as long as the phase
## gauge lasts (PHASE ticks at most; it refills while the thumb is down). Putting the thumb
## back ends the phase with a burst that is bigger for every bullet and enemy that passed
## through the ship. Pass-throughs load the Possession: phased and firing at once.

const PHASE := 90.0
const REFILL := 0.5       ## gauge regained a tick while the thumb is down
const MIN_GAUGE := 20.0   ## gauge needed to phase at all
const PASS_R := 4.5
const BURST_R := 13.0
const BURST_R_PASS := 1.6
const BURST_DMG := 3.0
const BURST_DMG_PASS := 1.2
const PASS_CAP := 14
const PASS_GAIN := 1.0 / 26.0
const POSSESS_T := 300

var gauge := PHASE
var phased := false
var passed := 0
var seen: Array = []      ## what has already passed through during this phase
var veil: MeshInstance3D
var ring: MeshInstance3D
var burst_m: MeshInstance3D
var burst_t := 0
var burst_r := 0.0
var possess := 0


func start() -> void:
	veil = own(Models.glow("8c7bff", 22.0)) as MeshInstance3D
	ring = own(ring_node("b38cff", 0.8)) as MeshInstance3D
	burst_m = own(ring_node("ffffff", 0.9)) as MeshInstance3D
	for m in [veil, ring, burst_m]:
		m.visible = false


func fire() -> void:
	var sp: float = VShips.KITS.wraith.shot_speed
	for a in [-0.1, 0.0, 0.1]:
		g.shot(g.P.x, g.P.y + 8, sin(a) * sp, cos(a) * sp, Models.M.shot, 1, "b38cff")


func lift() -> void:
	if gauge < MIN_GAUGE:
		return
	phased = true
	passed = 0
	seen = []
	g.G.slow = 0
	g.audio.play("pod")
	Diag.once("wraith phase")


func hold() -> void:
	if phased:
		_end()
	gauge = minf(PHASE, gauge + REFILL)


func _end() -> void:
	phased = false
	var r := BURST_R + BURST_R_PASS * passed
	blast(g.P.x, g.P.y, r, BURST_DMG + BURST_DMG_PASS * passed)
	wipe(g.P.x, g.P.y, r)
	burst_r = r
	burst_t = 10
	g.P.inv = maxi(g.P.inv, 10)
	g.audio.play("beam", 1 if passed < 4 else 3)
	g.shake = maxf(g.shake, 2.0 + passed * 0.5)
	passed = 0


func ult() -> void:
	possess = POSSESS_T
	g.G.ult_t = POSSESS_T
	phased = false
	g.audio.play("ready", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if burst_t > 0:
		burst_t -= 1
	if possess > 0:
		possess -= 1
	if not g.P.alive or g.G.has("run"):
		phased = false
		return
	if phased:
		gauge -= 1.0
		if gauge <= 0.0:
			gauge = 0.0
			_end()
	if phased or possess > 0:
		g.P.inv = maxi(g.P.inv, 2)
		# what passes through the ship feeds the burst (and the Possession)
		for b in g.G.eb:
			if not b.get("dead", false) and absf(b.x - g.P.x) < PASS_R and absf(b.y - g.P.y) < PASS_R and not _seen(b):
				_pass()
		for e in g.G.enemies:
			if not e.ground and not e.get("dead", false) and absf(e.x - g.P.x) < e.hw + 2.0 and absf(e.y - g.P.y) < e.hh + 2.0 and not _seen(e):
				_pass()


func _seen(o: Dictionary) -> bool:
	for s in seen:
		if is_same(s, o):
			return true
	seen.append(o)
	if seen.size() > 60:
		seen.pop_front()
	return false


func _pass() -> void:
	if phased:
		passed = mini(PASS_CAP, passed + 1)
		gain(PASS_GAIN)
	g.glow_fx("b38cff", g.P.x, g.P.y, 4, 8.0, 8)


func reset() -> void:
	super.reset()
	phased = false
	possess = 0
	gauge = PHASE


func hint() -> String:
	if possess > 0:
		return "POSSESSION: NOTHING CAN TOUCH YOU"
	if phased:
		return "PHASED  ·  %d THROUGH  ·  TOUCH TO BURST" % passed
	if ready():
		return "FULL: LIFT FOR THE POSSESSION"
	return "LIFT TO PHASE OUT  ·  GAUGE %d%%" % int(gauge / PHASE * 100.0)


func sync() -> void:
	var on: bool = (phased or possess > 0) and g.P.alive and not g.G.has("run")
	veil.visible = on
	ring.visible = phased and g.P.alive
	var pos := Vector3(g.X(g.P.x), g.Y(g.P.y), 3.0)
	if on:
		veil.position = pos
	if ring.visible:
		# the ring shrinks as the gauge runs out
		ring.position = pos
		ring.scale = Vector3.ONE * (4.0 + 10.0 * gauge / PHASE)
	burst_m.visible = burst_t > 0
	if burst_t > 0:
		burst_m.position = pos
		burst_m.scale = Vector3.ONE * burst_r * (1.0 - burst_t / 14.0)
