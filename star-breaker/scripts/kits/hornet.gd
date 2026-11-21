extends ShipKit
## Hornet, the hunter: while the thumb is down, every enemy the ship flies under gets a lock
## (a big target takes another lock every STACK ticks it stays in the beam), LOCKS at most.
## Lifting fires one homing missile per lock. Missile hits load the Hive: a swarm of missiles
## for everything on screen.

const LOCKS := 8
const BEAM_W := 9.0       ## half width of the lock beam above the ship
const LOCK_EVERY := 5     ## ticks between two locks
const STACK := 22         ## ticks before the same target can take another lock
const DMG := 6.0
const HIT_GAIN := 1.0 / 36.0
const KILL_GAIN := 1.0 / 24.0
const HIVE := 36
const LIFE := 200

var locks: Array = []     ## {t = target, at = tick}
var missiles: Array = []  ## {x, y, vx, vy, t, m, life, hive}
var marks: Array = []
var cd := 0
var beam_m: MeshInstance3D
var hive_left := 0


func start() -> void:
	for i in LOCKS:
		var r := ring_node("ffb547")
		r.visible = false
		marks.append(own(r))
	beam_m = own(ribbon_node("ffb547", 0.05)) as MeshInstance3D


func fire() -> void:
	var sp: float = VShips.KITS.hornet.shot_speed
	g.shot(g.P.x - 1.6, g.P.y + 8, 0, sp, Models.M.pod_shot, 1)
	g.shot(g.P.x + 1.6, g.P.y + 8, 0, sp, Models.M.pod_shot, 1)


func hold() -> void:
	if cd > 0:
		cd -= 1
		return
	if locks.size() >= LOCKS:
		return
	var best := {}
	var by := 1e9
	for t in targets():
		if t.y < g.P.y + 4 or absf(t.x - g.P.x) > BEAM_W + t.hw:
			continue
		if g.G.t - _last_lock(t) < STACK:
			continue
		if t.y < by:
			by = t.y
			best = t
	if best.is_empty():
		return
	locks.append({t = best, at = g.G.t})
	cd = LOCK_EVERY
	g.audio.play("tink")
	Diag.once("hornet lock")


## The tick of the newest lock on this target (long ago when it has none).
func _last_lock(t: Dictionary) -> int:
	var at := -9999
	for l in locks:
		if same(l.t, t):
			at = maxi(at, int(l.at))
	return at


func lift() -> void:
	if locks.is_empty():
		return
	var n := locks.size()
	for i in n:
		_launch(locks[i].t, (i - (n - 1) / 2.0) * 0.5, false)
	locks = []
	g.audio.play("pod")
	g.shake = maxf(g.shake, 2.0)
	Diag.once("hornet missiles")


func _launch(t: Dictionary, side: float, hive: bool) -> void:
	var m := VFx.bolt(Models.M.pod_shot, "ff8a3d")
	g.world.add_child(m)
	missiles.append({x = g.P.x + side * 3.0, y = g.P.y + 4.0, vx = side * 1.6, vy = 1.2, t = t, m = m, life = LIFE, hive = hive})


func ult() -> void:
	g.G.ult_t = 100
	hive_left = HIVE
	g.audio.play("beam", 4)
	g.shake = maxf(g.shake, 6.0)
	locks = []


func update() -> void:
	# locks drop when their target dies or leaves
	locks = locks.filter(func(l): return alive(l.t))
	if hive_left > 0 and g.G.t % 2 == 0 and g.P.alive:
		var ts := targets()
		if not ts.is_empty():
			_launch(ts[hive_left % ts.size()], sin(hive_left * 2.4) * 2.0, true)
		hive_left -= 1
	for mi in missiles:
		mi.life -= 1
		if not alive(mi.t):
			mi.t = nearest(mi.x, mi.y)
		var sp := minf(5.5, 2.0 + (LIFE - mi.life) * 0.12)
		if not mi.t.is_empty():
			var p := at(mi.t)
			var d := Vector2(p.x - mi.x, p.y - mi.y)
			var v := (Vector2(mi.vx, mi.vy) + d.normalized() * 0.7).limit_length(sp)
			mi.vx = v.x
			mi.vy = v.y
			if absf(d.x) < mi.t.hw + 2.0 and absf(d.y) < mi.t.hh + 2.0:
				var killed := strike(mi.t, DMG * (0.7 if mi.hive else 1.0))
				if not mi.hive:
					gain(KILL_GAIN if killed else HIT_GAIN)
				g.boom(mi.x, mi.y, 4.0)
				mi.life = 0
		else:
			var v2 := (Vector2(mi.vx, mi.vy) + Vector2(0, 0.5)).limit_length(sp)
			mi.vx = v2.x
			mi.vy = v2.y
		mi.x += mi.vx
		mi.y += mi.vy
		if mi.life > 0 and (mi.y > g.view.end.y + 10 or mi.y < -10 or mi.x < -10 or mi.x > g.W + 10 or g.in_rock(mi.x, mi.y, 0.0)):
			mi.life = 0
		if mi.life > 0 and g.G.t % 3 == 0:
			g.glow_fx("ff8a3d", mi.x, mi.y, 0, 2.2, 7)
		if mi.life <= 0:
			mi.m.queue_free()
	missiles = missiles.filter(func(mi): return mi.life > 0)


func reset() -> void:
	super.reset()
	locks = []
	hive_left = 0


func clear() -> void:
	for mi in missiles:
		mi.m.queue_free()
	missiles = []
	super.clear()


func hint() -> String:
	if ready():
		return "FULL: LIFT FOR THE HIVE"
	if locks.size() >= LOCKS:
		return "%d LOCKS: LIFT TO FIRE" % LOCKS
	if not locks.is_empty():
		return "%d LOCKED: LIFT TO FIRE" % locks.size()
	return "HOLD UNDER ENEMIES TO LOCK"


func sync() -> void:
	for i in LOCKS:
		var r: MeshInstance3D = marks[i]
		r.visible = i < locks.size()
		if r.visible:
			var p := at(locks[i].t)
			var s := 5.0 + 1.2 * sin(g.tt * 0.3 + i)
			# stacked locks on one target sit as wider rings
			var same := 0
			for j in i:
				if same(locks[j].t, locks[i].t):
					same += 1
			r.position = Vector3(g.X(p.x), g.Y(p.y), 4.0)
			r.scale = Vector3.ONE * (s + same * 2.2)
			r.rotation.z = g.tt * 0.05
	var on: bool = g.inp.hold and g.P.alive and not g.G.has("run") and locks.size() < LOCKS
	beam_m.visible = on
	if on:
		draw_ribbon(beam_m, [Vector2(g.P.x, g.P.y + 8), Vector2(g.P.x, g.view.end.y)], BEAM_W * 2.0, 1.0)
	for mi in missiles:
		mi.m.position = Vector3(g.X(mi.x), g.Y(mi.y), 1.0)
		mi.m.rotation.z = atan2(-mi.vx, mi.vy)
