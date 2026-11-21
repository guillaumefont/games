extends ShipKit
## Siphon, the leech: while the thumb is down a drain beam latches by itself onto the nearest
## enemy ahead (no aiming) and fills the reserve. Every HEAL of reserve drained mends a hull
## point: the only ship that heals. Lifting spends the reserve as one bolt at the latched
## target. Its gun is thin. What it drains loads the Leech: every enemy on screen drained at
## once, and the hull made whole.

const RANGE := 78.0
const CONE := 0.75        ## how far to the side the beam reaches, as dx / dy
const DRAIN := 1.2
const EVERY := 6
const HEAL := 60.0        ## reserve drained per hull point mended
const CAP := 40.0         ## most reserve a bolt can spend
const BOLT := 0.55        ## bolt damage per point of reserve
const GAIN := 1.0 / 110.0
const LEECH_T := 240

var tgt := {}
var reserve := 0.0
var healed := 0.0
var beam_m: MeshInstance3D
var bolt_m: MeshInstance3D
var bolt_t := 0
var bolt_a := Vector2.ZERO
var bolt_b := Vector2.ZERO
var leech := 0
var leech_m: MeshInstance3D


func start() -> void:
	beam_m = own(ribbon_node("a6ff5a", 0.8)) as MeshInstance3D
	bolt_m = own(ribbon_node("ffffff", 0.95)) as MeshInstance3D
	leech_m = own(ribbon_node("a6ff5a", 0.55)) as MeshInstance3D
	for m in [beam_m, bolt_m, leech_m]:
		m.visible = false


func fire() -> void:
	g.shot(g.P.x, g.P.y + 8, 0, float(VShips.KITS.siphon.shot_speed), Models.M.shot, 1, "a6ff5a")


## The nearest target ahead of the ship, inside the beam's reach.
func _pick() -> Dictionary:
	var best := {}
	var bd := 1e9
	for t in targets():
		var dy: float = t.y - g.P.y
		var dx: float = absf(t.x - g.P.x)
		if dy < 2.0 or dy > RANGE or dx > dy * CONE + t.hw + 4.0:
			continue
		var d := dx + dy
		if d < bd:
			bd = d
			best = t
	return best


func _drained(d: float) -> void:
	reserve = minf(CAP, reserve + d)
	healed += d
	gain(d * GAIN)
	if healed >= HEAL:
		healed -= HEAL
		if g.P.hull < g.HULL:
			g.P.hull += 1
			g.audio.play("oneup")
			g.glow_fx("a6ff5a", g.P.x, g.P.y, 4, 22.0, 16)
			Diag.once("siphon heal")


func hold() -> void:
	if tgt.is_empty() or not alive(tgt) or at(tgt).distance_to(Vector2(g.P.x, g.P.y)) > RANGE + 12.0 or at(tgt).y < g.P.y:
		tgt = _pick()
	if not tgt.is_empty() and g.G.t % EVERY == 0:
		strike(tgt, DRAIN)
		_drained(DRAIN)


func lift() -> void:
	if reserve < 4.0 or tgt.is_empty() or not alive(tgt):
		tgt = {}
		return
	bolt_a = Vector2(g.P.x, g.P.y + 8)
	bolt_b = at(tgt)
	strike(tgt, reserve * BOLT)
	g.boom(bolt_b.x, bolt_b.y, 5.0 + reserve * 0.15)
	bolt_t = 10
	reserve = 0.0
	tgt = {}
	g.audio.play("beam", 2)
	g.shake = maxf(g.shake, 3.0)
	Diag.once("siphon bolt")


func ult() -> void:
	leech = LEECH_T
	g.G.ult_t = LEECH_T
	g.P.hull = g.HULL
	g.audio.play("beam", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if bolt_t > 0:
		bolt_t -= 1
	if not holding():
		tgt = {}
	if leech > 0:
		leech -= 1
		if g.G.t % EVERY == 0 and g.P.alive:
			for t in targets():
				strike(t, DRAIN * 1.5)


func reset() -> void:
	super.reset()
	tgt = {}
	reserve = 0.0
	leech = 0


func hint() -> String:
	if leech > 0:
		return "LEECH: DRAINING EVERYTHING"
	if ready():
		return "FULL: LIFT FOR THE LEECH"
	if reserve >= 4.0 and not tgt.is_empty():
		return "RESERVE %d: LIFT TO FIRE IT" % int(reserve)
	return "HOLD: THE BEAM DRAINS AND HEALS"


func sync() -> void:
	var on: bool = holding() and not tgt.is_empty() and alive(tgt)
	beam_m.visible = on
	if on:
		var p := at(tgt)
		var mid := Vector2(g.P.x, g.P.y + 8).lerp(p, 0.5) + Vector2(sin(g.tt * 0.4) * 2.0, 0)
		draw_ribbon(beam_m, [Vector2(g.P.x, g.P.y + 8), mid, p], 1.0 + reserve / CAP * 1.6 + 0.4 * sin(g.tt * 0.7))
	bolt_m.visible = bolt_t > 0
	if bolt_t > 0:
		draw_ribbon(bolt_m, [bolt_a, bolt_b], 0.6 + bolt_t * 0.5, 3.0)
	leech_m.visible = leech > 0 and g.P.alive
	if leech_m.visible:
		var pts := []
		for t in targets():
			pts.append(Vector2(g.P.x, g.P.y + 6))
			pts.append(Vector2(t.x, t.y))
		draw_ribbon(leech_m, pts, 0.9 + 0.4 * sin(g.tt * 0.5))
