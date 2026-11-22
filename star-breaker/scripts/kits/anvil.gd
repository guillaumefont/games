extends ShipKit
## Anvil, the bomber: while the thumb is down a reticle runs up the screen ahead of the ship
## (further the longer the hold, stopping at REACH). Lifting drops a bomb on it: a blast that
## hits fliers, ground targets, boss parts and bullets alike. Its two guns fire out to the sides
## in a V and never straight ahead: what is in front of the ship is the bomb's (with guns firing
## ahead they killed nearly everything before a bomb could land: Guillaume, 2026-11-22).
## Bombed ground targets (and, less, other bomb kills) load the Barrage: a carpet of bombs
## walking up the whole screen.

const MIN_HOLD := 10
const START := 26.0       ## the reticle's distance from the ship when the hold begins
const RUN := 2.2          ## how fast it runs up the screen (units a tick)
const REACH := 150.0
const FALL := 12          ## ticks a bomb takes to land
const R := 21.0
const DMG := 16.0
const GUN_A := 0.3        ## how far out the guns point (radians from straight ahead)
const GROUND_GAIN := 1.0 / 7.0
const KILL_GAIN := 1.0 / 22.0
const HIT_GAIN := 1.0 / 70.0

var bombs: Array = []     ## {x, y, x0, y0, t, m, barrage}
var reticle: MeshInstance3D
var inner: MeshInstance3D
var barrage := 0
var stat := {bombs = 0, hit = 0, kills = 0}   ## for the bot and the tests


func start() -> void:
	reticle = own(ring_node("ffb547")) as MeshInstance3D
	inner = own(ring_node("ffffff", 0.7)) as MeshInstance3D
	reticle.visible = false
	inner.visible = false


func fire() -> void:
	var sp: float = VShips.KITS.anvil.shot_speed
	for k in [-1.0, 1.0]:
		g.shot(g.P.x + 4.0 * k, g.P.y + 7, sin(GUN_A) * sp * k, cos(GUN_A) * sp, Models.M.heavy, 2, "ffb547")


## Where the reticle is: straight ahead of the ship.
func aim() -> Vector2:
	var d := minf(REACH, START + maxi(0, held - MIN_HOLD) * RUN)
	return Vector2(g.P.x, minf(g.view.end.y - 8.0, g.P.y + d))


func lift() -> void:
	if held < MIN_HOLD:
		return
	var a := aim()
	_drop(a.x, a.y, false)
	g.audio.play("pod")
	Diag.once("anvil bomb")


func _drop(x: float, y: float, from_barrage: bool) -> void:
	var m := Models.mesh(Models.geo("anvBomb", func(): return Geo.octa(1.0)), Models.M.pod)
	m.scale = Vector3(1.4, 2.4, 1.4)
	g.world.add_child(m)
	bombs.append({x = x, y = y, x0 = g.P.x, y0 = g.P.y, t = 0, m = m, barrage = from_barrage})


func ult() -> void:
	barrage = 84
	g.G.ult_t = 110
	g.audio.play("alarm")
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if barrage > 0:
		barrage -= 1
		if barrage % 7 == 0:
			var k := 11 - barrage / 7
			var row := k / 3
			var col := k % 3
			_drop(21.0 + col * 42.0 + (10.0 if row % 2 else -10.0), 40.0 + row * 46.0, true)
	for b in bombs:
		b.t += 1
		if b.t >= FALL:
			_explode(b)
			b.m.queue_free()
	bombs = bombs.filter(func(b): return b.t < FALL)


func _explode(b: Dictionary) -> void:
	var res := blast(b.x, b.y, R, DMG)
	wipe(b.x, b.y, R)
	if not b.barrage:
		stat.bombs += 1
		stat.hit += 1 if res[0] > 0 else 0
		stat.kills += res[1]
		gain(res[2] * GROUND_GAIN + (res[1] - res[2]) * KILL_GAIN + (res[0] - res[1]) * HIT_GAIN)
	g.boom(b.x, b.y, R * 0.75, true)
	g.glow_fx("ffb547", b.x, b.y, 2, R * 2.4, 12)
	g.audio.play("boom")
	g.shake = maxf(g.shake, 4.0)


func reset() -> void:
	super.reset()
	barrage = 0


func clear() -> void:
	for b in bombs:
		b.m.queue_free()
	bombs = []
	super.clear()


func hint() -> String:
	if ready():
		return "FULL: LIFT FOR THE BARRAGE"
	if g.inp.hold and held >= MIN_HOLD:
		return "LIFT TO BOMB THE RETICLE"
	return "HOLD: THE RETICLE RUNS AHEAD"


func sync() -> void:
	var on: bool = g.inp.hold and held >= MIN_HOLD and g.P.alive and not g.G.has("run")
	reticle.visible = on
	inner.visible = on
	if on:
		var a := aim()
		reticle.position = Vector3(g.X(a.x), g.Y(a.y), 3.0)
		reticle.scale = Vector3.ONE * R
		reticle.rotation.z = g.tt * 0.03
		inner.position = reticle.position
		inner.scale = Vector3.ONE * (3.0 + 1.5 * sin(g.tt * 0.25))
	for b in bombs:
		var f := float(b.t) / FALL
		# the bomb drops away from the ship's height to the ground as it flies out
		b.m.position = Vector3(g.X(lerpf(b.x0, b.x, f)), g.Y(lerpf(b.y0, b.y, f)), lerpf(0.0, -40.0, f * f))
		b.m.rotation.z += 0.2
