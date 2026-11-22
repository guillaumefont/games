extends ShipKit
## Weaver, the trapper: while the thumb is down the ship trails a glowing thread along its path
## (the last TRAIL ticks of it). Enemies touching the thread burn. Fly a loop so the thread
## crosses itself and it turns white: lifting then cuts everything inside (enemies, boss parts
## and bullets). Without a loop a lift just snaps the thread. Everything the thread does loads the
## Loom (burns, cuts, bullets cut: cuts alone left the gauge empty, Guillaume 2026-11-22): for its
## length every loop cuts on its own the moment it closes, and cuts harder.

const TRAIL := 96          ## points kept, one a tick: 1.6 s of flight
const TRAIL_LOOM := 150
const MIN_LOOP := 10       ## points a loop needs at least
const CLOSE := 10.0        ## how near the thread must come to itself to close
const MIN_AREA := 200.0
const BURN := 1.0
const BURN_EVERY := 6
const CUT := 14.0
const CUT_GAIN := 1.0 / 10.0
const KILL_GAIN := 1.0 / 6.0
const BURN_GAIN := 1.0 / 40.0   ## each time the thread burns something
const BURN_KILL_GAIN := 1.0 / 14.0
const BULLET_GAIN := 1.0 / 30.0 ## each bullet a loop cuts
const LOOM_T := 480

var pts: Array = []        ## Vector2, oldest first
var loop: PackedVector2Array = PackedVector2Array()
var thread_m: MeshInstance3D
var loop_m: MeshInstance3D
var flash_m: MeshInstance3D
var flash_pts: Array = []
var flash_t := 0
var loom := 0
var stat := {cuts = 0, hit = 0}   ## for the bot and the tests


func start() -> void:
	thread_m = own(ribbon_node("4fe3d6", 0.85)) as MeshInstance3D
	loop_m = own(ribbon_node("ffffff", 0.95)) as MeshInstance3D
	flash_m = own(ribbon_node("ff5fd2", 0.9)) as MeshInstance3D


func fire() -> void:
	var sp: float = VShips.KITS.weaver.shot_speed
	g.shot(g.P.x - 1.2, g.P.y + 8, 0, sp, Models.M.shot, 1)
	g.shot(g.P.x + 1.2, g.P.y + 8, 0, sp, Models.M.shot, 1)


func hold() -> void:
	pts.append(Vector2(g.P.x, g.P.y))
	var cap := TRAIL_LOOM if loom > 0 else TRAIL
	while pts.size() > cap:
		pts.pop_front()
	loop = _find_loop()
	# the thread burns what touches it
	if g.G.t % BURN_EVERY == 0 and pts.size() > 2:
		for t in targets():
			var r: float = maxf(t.hw, t.hh) + 2.0
			for i in range(0, pts.size(), 3):
				if absf(pts[i].x - t.x) < r and absf(pts[i].y - t.y) < r:
					gain(BURN_KILL_GAIN if strike(t, BURN * (3.0 if loom > 0 else 1.0)) else BURN_GAIN)
					break
	if loom > 0 and not loop.is_empty():
		_cut(2.0)


## The newest closed loop in the thread: where its head comes back near an older point.
func _find_loop() -> PackedVector2Array:
	var n := pts.size()
	if n < MIN_LOOP:
		return PackedVector2Array()
	var head: Vector2 = pts[n - 1]
	for i in range(0, n - MIN_LOOP):
		if head.distance_to(pts[i]) < CLOSE:
			var poly := PackedVector2Array(pts.slice(i, n))
			if _area(poly) >= MIN_AREA:
				return poly
			return PackedVector2Array()
	return PackedVector2Array()


## Inside the loop, or touching its thread.
func _caught(t: Dictionary) -> bool:
	if Geometry2D.is_point_in_polygon(Vector2(t.x, t.y), loop):
		return true
	var r: float = maxf(t.hw, t.hh) + 3.0
	for p in loop:
		if absf(p.x - t.x) < r and absf(p.y - t.y) < r:
			return true
	return false


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func lift() -> void:
	if not loop.is_empty():
		_cut(1.0)
	elif pts.size() > 4:
		# no loop: the thread snaps, stinging what it touches
		for t in targets():
			var r: float = maxf(t.hw, t.hh) + 2.0
			for i in range(0, pts.size(), 3):
				if absf(pts[i].x - t.x) < r and absf(pts[i].y - t.y) < r:
					strike(t, 2.0)
					break
	pts = []
	loop = PackedVector2Array()


func _cut(mul: float) -> void:
	var hits := 0
	for t in targets():
		if _caught(t):
			hits += 1
			gain(KILL_GAIN if strike(t, CUT * mul) else CUT_GAIN)
			g.spark(t.x, t.y)
	for b in g.G.eb:
		if not b.get("dead", false) and Geometry2D.is_point_in_polygon(Vector2(b.x, b.y), loop):
			b.dead = true
			gain(BULLET_GAIN)
			g.spark(b.x, b.y)
	stat.cuts += 1
	stat.hit += 1 if hits > 0 else 0
	flash_pts = Array(loop)
	flash_pts.append(loop[0])
	flash_t = 14
	g.audio.play("beam", 2)
	g.shake = maxf(g.shake, 3.0 if hits > 0 else 1.0)
	Diag.once("weaver cut")
	pts = []
	loop = PackedVector2Array()


func ult() -> void:
	loom = LOOM_T
	g.G.ult_t = LOOM_T
	g.audio.play("ready", 4)
	g.shake = maxf(g.shake, 5.0)


func update() -> void:
	if loom > 0:
		loom -= 1
	if flash_t > 0:
		flash_t -= 1
	# the thread fades from its tail when the thumb is up
	if not g.inp.hold and not pts.is_empty():
		pts.pop_front()


func reset() -> void:
	super.reset()
	pts = []
	loop = PackedVector2Array()


func hint() -> String:
	if loom > 0:
		return "LOOM: EVERY LOOP CUTS ON ITS OWN"
	if ready():
		return "FULL: LIFT FOR THE LOOM"
	if not loop.is_empty():
		return "LOOP CLOSED: LIFT TO CUT"
	return "HOLD AND FLY A LOOP ROUND ENEMIES"


func sync() -> void:
	var closed := not loop.is_empty()
	thread_m.visible = pts.size() > 1 and not closed
	loop_m.visible = closed
	if thread_m.visible:
		draw_ribbon(thread_m, pts, 1.6 if loom > 0 else 1.1)
	if closed:
		var lp := Array(loop)
		lp.append(loop[0])
		draw_ribbon(loop_m, lp, 2.2)
	flash_m.visible = flash_t > 0
	if flash_t > 0:
		draw_ribbon(flash_m, flash_pts, 0.6 + flash_t * 0.5, 3.0)
