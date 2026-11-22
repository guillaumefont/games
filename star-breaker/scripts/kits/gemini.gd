extends ShipKit
## Gemini, the twin: while the thumb is down the ship splits and its twin flies the mirror image
## of your path on the other half of the screen, firing as you do (it is a ghost: nothing can
## hit it). Lifting swaps you with the twin: you are across the screen at once, safe for a
## moment, and the link that flashes between the two places wipes the bullets on it and hits
## the enemies it crosses. The twin's shots that land, link hits and wiped bullets load the
## Eclipse (the link alone left the gauge empty: Guillaume, 2026-11-22): for its length the
## link burns the whole time.

const SPLIT := 8          ## ticks for the twin to slide out
const LINK_H := 7.0       ## half height of the link
const LINK_DMG := 8.0
const SAFE := 16          ## ticks of safety after a swap
const HIT_GAIN := 1.0 / 5.0
const WIPE_GAIN := 1.0 / 12.0
const TWIN_GAIN := 1.0 / 45.0   ## each of the twin's shots that lands
const ECLIPSE_T := 360
const ECLIPSE_DMG := 0.6

var split := 0.0          ## 0 together, 1 fully apart
var twin_m: Node3D
var link_m: MeshInstance3D
var link_t := 0
var link_a := Vector2.ZERO
var link_b := Vector2.ZERO
var eclipse := 0


func start() -> void:
	var model := VShips.model("gemini")
	Progress.apply_paint(model, g.prog.paint_of("gemini"))
	twin_m = own(VShips.upright(model))
	twin_m.visible = false
	link_m = own(ribbon_node("b38cff", 0.9)) as MeshInstance3D
	link_m.visible = false


## Where the twin is: the ship's mirror image across the middle of the screen.
func twin() -> Vector2:
	var x: float = lerpf(g.P.x, g.W - g.P.x, split)
	return Vector2(x, g.P.y)


func out() -> bool:
	return split >= 1.0 or eclipse > 0


func fire() -> void:
	var sp: float = VShips.KITS.gemini.shot_speed
	for x in [g.P.x] + ([twin().x] if split > 0.5 else []):
		for dx in [-2.0, 2.0]:
			g.shot(x + dx, g.P.y + 8, 0, sp, Models.M.shot, 1, "b38cff")
			# the twin's own shots load the Eclipse when they land
			g.G.pb.back().kit = x != g.P.x


func on_hit(_b: Dictionary) -> void:
	gain(TWIN_GAIN)


func hold() -> void:
	split = minf(1.0, split + 1.0 / SPLIT)


func lift() -> void:
	if split < 1.0:
		return
	var a := Vector2(g.P.x, g.P.y)
	var b := twin()
	_link(a, b, LINK_DMG, true)
	# swap, unless the twin's place is inside rock or a wall
	var blocked: bool = g.in_rock(b.x, b.y, 3.0)
	for bar in g.G.bars:
		if g.bar_solid(bar, b.x, b.y, 3.0):
			blocked = true
	if not blocked:
		g.P.x = b.x
		g.P.inv = maxi(g.P.inv, SAFE)
		g.glow_fx("b38cff", a.x, a.y, 4, 14.0, 12)
		g.glow_fx("b38cff", b.x, b.y, 4, 18.0, 12)
	link_a = a
	link_b = b
	link_t = 12
	split = 0.0
	g.audio.play("pod")
	Diag.once("gemini swap")


## The link between two places: wipes bullets on it and hits what it crosses.
func _link(a: Vector2, b: Vector2, dmg: float, loads: bool) -> void:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	for bl in g.G.eb:
		if not bl.get("dead", false) and bl.x > x0 - 2 and bl.x < x1 + 2 and absf(bl.y - a.y) < LINK_H:
			bl.dead = true
			g.spark(bl.x, bl.y)
			if loads:
				gain(WIPE_GAIN)
	for t in targets():
		if t.x + t.hw > x0 and t.x - t.hw < x1 and absf(t.y - a.y) < LINK_H + t.hh:
			strike(t, dmg)
			if loads:
				gain(HIT_GAIN)


func ult() -> void:
	eclipse = ECLIPSE_T
	g.G.ult_t = ECLIPSE_T
	split = 1.0
	g.audio.play("beam", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if link_t > 0:
		link_t -= 1
	if eclipse > 0:
		eclipse -= 1
		split = 1.0
		if g.P.alive and not g.G.has("run"):
			_link(Vector2(g.P.x, g.P.y), twin(), ECLIPSE_DMG, false)
	elif not holding():
		split = maxf(0.0, split - 0.2)


func reset() -> void:
	super.reset()
	split = 0.0
	eclipse = 0


func hint() -> String:
	if eclipse > 0:
		return "ECLIPSE: THE LINK BURNS"
	if ready():
		return "FULL: LIFT FOR THE ECLIPSE"
	return "LIFT: SWAP PLACES WITH YOUR TWIN" if split >= 1.0 else "HOLD: YOUR TWIN MIRRORS YOU"


func sync() -> void:
	var show: bool = split > 0.05 and g.P.alive and not g.G.has("run")
	twin_m.visible = show
	if show:
		var t := twin()
		twin_m.position = Vector3(g.X(t.x), g.Y(t.y), 0.0)
		var mdl: Node3D = twin_m.get_meta("model")
		(mdl.get_meta("body") as Node3D).rotation.x = clampf(-g.P.vx * 0.35, -0.8, 0.8)
	var live: bool = eclipse > 0 and g.P.alive and not g.G.has("run")
	link_m.visible = link_t > 0 or live
	if live:
		draw_ribbon(link_m, [Vector2(g.P.x, g.P.y), twin()], 2.0 + sin(g.tt * 0.6), 1.0)
	elif link_t > 0:
		draw_ribbon(link_m, [link_a, link_b], 0.5 + link_t * 0.6, 1.0)
