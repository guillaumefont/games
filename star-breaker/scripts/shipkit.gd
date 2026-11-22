class_name ShipKit
extends RefCounted
## A ship's own mechanic, for every ship but Lance (whose charge beam and Storm live in vgame.gd).
## One thumb plays them all: drag flies the ship 1:1 and fires `fire()` while the thumb is
## down, `hold()` runs every tick the thumb stays down, `lift()` runs when it comes up. Each ship
## loads its ultimate meter (`meter`, 0 to 1) its own way through `gain()`; once full, the next
## lift fires `ult()` instead of `lift()` (Guillaume, 2026-11-21: no pod, no detached thing to
## steer; every ship has its own design and mechanic). Subclasses live in scripts/kits/.

var g: Node3D          ## the game (vgame.gd)
var meter := 0.0       ## the ultimate meter, 0 to 1
var held := 0          ## ticks the thumb has been down since the last lift
var flash := 0         ## ticks left of the HUD bar's flash after a gain
var last_gain := 0.0
var nodes: Array = []  ## 3D nodes the kit made (freed by clear())


func _init(game: Node3D) -> void:
	g = game


## Called at the start of a stage, after the ship model is in the world.
func start() -> void:
	pass


## The thumb is down this tick (not while flying in or in the canyon run).
func hold() -> void:
	pass


## The thumb came up after `held` ticks (and the ultimate isn't ready).
func lift() -> void:
	pass


## Every tick of play, after the player moved.
func update() -> void:
	pass


## The ultimate. The meter is emptied by the caller.
func ult() -> void:
	pass


## The main gun, fired every `fire_every` ticks while the thumb is down.
func fire() -> void:
	var sp: float = VShips.KITS[g.G.ship].shot_speed
	g.shot(g.P.x - 2.4, g.P.y + 8, 0, sp, Models.M.shot, 1)
	g.shot(g.P.x + 2.4, g.P.y + 8, 0, sp, Models.M.shot, 1)


## How often the main gun fires (ticks); kits may slow it while holding.
func fire_every() -> int:
	return int(VShips.KITS[g.G.ship].fire_every)


## An enemy bullet is about to hit the play plane near the ship: true eats it.
func eats(_b: Dictionary) -> bool:
	return false


## One of the kit's own shots (marked `kit = true`) hit something.
func on_hit(_b: Dictionary) -> void:
	pass


## The ship blew up (or a new one is flying in).
func reset() -> void:
	held = 0


## One line under the HUD meter.
func hint() -> String:
	return "FULL: LIFT FOR %s" % String(VShips.KITS[g.G.ship].ult_name).to_upper() if ready() else String(VShips.KITS[g.G.ship].loads).to_upper()


## Places the kit's 3D nodes (every frame).
func sync() -> void:
	pass


func ready() -> bool:
	return meter >= 1.0 and g.G.ult_t == 0


## Is the thumb down in normal play (not flying in, not in the canyon run, not after the clear)?
func holding() -> bool:
	return g.inp.hold and g.P.alive and not g.P.entering and not g.G.has("run") and g.G.clear_t == 0


## Adds to the ultimate meter (not while an ultimate is going).
## Every enemy killed, however it died, loads the gauge a little, so no ship's gauge can sit
## empty; the ship's own move loads it several times faster.
const KILL_TRICKLE := 1.0 / 80.0


func gain(x: float) -> void:
	if g.G.ult_t > 0 or not g.P.alive or meter >= 1.0:
		return
	meter = minf(1.0, meter + x)
	flash = 14
	last_gain = x
	if meter >= 1.0:
		g.audio.play("ready", 4)
		g.shake = maxf(g.shake, 3.0)


func tick_hud() -> void:
	if flash > 0:
		flash -= 1


## Adds a node to the world and keeps it for clear().
func own(n: Node3D) -> Node3D:
	g.world.add_child(n)
	nodes.append(n)
	return n


func clear() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes = []


# ---------- helpers for kits ----------

## Everything a weapon can hit that is on screen: enemies (ground ones too) as {x, y, hw, hh, e}
## and boss parts as {x, y, hw, hh, o, part}. The game rebuilds its boss part list every tick, so
## a part is known by `o` (what it stands for); `at()` and `strike()` look it up afresh.
func targets() -> Array:
	var out := []
	for e in g.G.enemies:
		if e.get("dead", false) or e.y > g.view.end.y - 2 or e.y < g.view.position.y + 2 or e.x < 0 or e.x > g.W:
			continue
		out.append({x = e.x, y = e.y, hw = e.hw, hh = e.hh, e = e})
	for p in g.G.bparts:
		if p.kind == "shield" or p.kind == "seg":
			continue
		out.append({x = p.x, y = p.y, hw = p.r, hh = p.r, o = p.o, part = p})
	return out


## What a target is, for telling two targets apart (use is_same on it).
func what(t: Dictionary) -> Variant:
	return t.get("e", t.get("o"))


func same(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and is_same(what(a), what(b))


## A boss part target's part as it is this tick ({} once it is gone or armoured).
func _part(t: Dictionary) -> Dictionary:
	if g.G.boss.is_empty() or g.G.boss.get("dying", 0):
		return {}
	for p in g.G.bparts:
		if is_same(p.o, t.o) and p.kind != "shield" and p.kind != "seg":
			return p
	return {}


## Is the target still there to be hit?
func alive(t: Dictionary) -> bool:
	if t.has("e"):
		return not t.e.get("dead", false)
	if t.has("o"):
		return not _part(t).is_empty()
	return false


## Where the target is now.
func at(t: Dictionary) -> Vector2:
	if t.has("e"):
		return Vector2(t.e.x, t.e.y)
	var p := _part(t)
	return Vector2(p.x, p.y) if not p.is_empty() else Vector2(t.x, t.y)


## Damages a target; true when that killed an enemy.
func strike(t: Dictionary, d: float) -> bool:
	if t.has("e"):
		if t.e.get("dead", false):
			return false
		g.dmg_e(t.e, d)
		return t.e.get("dead", false)
	var p := _part(t) if t.has("o") else {}
	if not p.is_empty():
		g.boss_damage(p, d)
	return false


## Damages everything within `r` of a point. Returns [hits, kills, ground kills].
func blast(x: float, y: float, r: float, d: float) -> Array:
	var res := [0, 0, 0]
	for t in targets():
		if absf(t.x - x) < r + t.hw and absf(t.y - y) < r + t.hh:
			res[0] += 1
			if strike(t, d):
				res[1] += 1
				if t.e.get("ground", false):
					res[2] += 1
	return res


## Removes the enemy bullets within `r` of a point; returns how many.
func wipe(x: float, y: float, r: float) -> int:
	var n := 0
	for b in g.G.eb:
		if not b.get("dead", false) and Vector2(b.x - x, b.y - y).length() < r:
			b.dead = true
			n += 1
	return n


## The nearest target to a point ({} when there is none).
func nearest(x: float, y: float) -> Dictionary:
	var best := {}
	var bd := 1e18
	for t in targets():
		var d := Vector2(t.x - x, t.y - y).length_squared()
		if d < bd:
			bd = d
			best = t
	return best


## A flat glowing ring (radius 1, scale it) that kits use for reticles and blasts.
func ring_node(color: String, opacity := 0.9) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = VFx.ring_mesh()
	m.material_override = Models.add_mat(color, opacity)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## A flat ribbon drawn fresh every frame through `pts` (stage units), `w` wide.
func ribbon_node(color: String, opacity := 0.9) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ImmediateMesh.new()
	m.material_override = Models.add_mat(color, opacity)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func draw_ribbon(m: MeshInstance3D, pts: Array, w: float, z := 2.0) -> void:
	var im: ImmediateMesh = m.mesh
	im.clear_surfaces()
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a := Vector3(g.X(pts[i].x), g.Y(pts[i].y), z)
		var b := Vector3(g.X(pts[i + 1].x), g.Y(pts[i + 1].y), z)
		var n := Vector3(-(b.y - a.y), b.x - a.x, 0).normalized() * w * 0.5
		for v in [a - n, a + n, b + n, a - n, b + n, b - n]:
			im.surface_add_vertex(v)
	im.surface_end()
