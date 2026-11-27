class_name Game
extends Node3D
## Mer des Brumes: sail the archipelago, fight broadsides, dig up treasure, upgrade at the port.
## Ported from the web prototype (web/index.html). The rules are in rules.gd, the models in
## models.gd and the interface in hud.gd. Tests set `driven = true` and call step() themselves.

const CAM_FOV := 38.0
const SAVE_EVERY := 4.0
const ENEMIES := 7

class Boat:
	extends RefCounted
	var node: Node3D
	var is_player := false
	var h := 0.0
	var v := 0.0
	var hp := 100.0
	var max_hp := 100.0
	var st := {}
	var rl := {}          # battery -> seconds until loaded
	var name := ""
	var lvl := 1
	var hk := "chaloupe"
	var offline := false
	var coins := 0
	var aggro_cd := 0.0
	var state := "wander"  # wander, attack, defend, sink
	var tgt := Vector2.INF
	var sink_t := 0.0
	var arcs: Node3D
	var oar := 0.0
	var stroke := false
	var ai_t := 0.0
	var ai_h := 0.0
	var ai_s := 0.0
	var up := {}
	var fighters := []     # its crew and captain, for a boarding

	func pos() -> Vector3:
		return node.position

	func xz() -> Vector2:
		return Vector2(node.position.x, node.position.z)

	func view() -> Dictionary:
		return {"x": node.position.x, "z": node.position.z, "h": h, "v": v}


var s: Dictionary
var rng := RandomNumberGenerator.new()
var driven := false
var save_path := Rules.SAVE_PATH
var time := 0.0
var P := Boat.new()
var alive := true
var throttle := 0.0
var last_input := -99.0
var auto_flee := false
## Connected = the game is in front of the player. Only a disconnected player's ship defends
## itself (manoeuvres and fires on its own); a connected player aims every volley with the
## green stick.
var connected := true
var away_fight := false
var respawn_t := -1.0
var enemies: Array[Boat] = []
var spawn_timers: Array[float] = []
var combat := {}          # {e: Boat, mode: pending|fight|flee, t, no_ammo}
var treasure := {}        # {pos: Vector3, node, gold}
var balls := []
var parts := []
var isles: Array = []
var tower_t := 0.0
var save_t := 0.0
var name_idx := 0
## keyboard (or a test's) input: turn left / right, more / less sail
var kb := {"l": false, "r": false, "f": false, "b": false}

var camera: Camera3D
var sun: DirectionalLight3D
var sea: MeshInstance3D
var port_deco: MeshInstance3D
var hud: Hud
var cam_off := Vector3(0, 62, 50)

var _ball_mesh := Models.ball(0.28, 6, 3)
var _puff_mesh := Models.ball(1.0, 5, 3)
var _chip_mesh := Models.box(1, 1, 1)
var _lit := {}
var aim_mark: Node3D
var hook_mark: Node3D
var _hook_line: MeshInstance3D
const HOOK_PURPLE := Color8(0xa0, 0x5c, 0xe0)
## Grapples in flight: {n, rope, from: Boat, to: Vector3, boat, t, dur}
var hooks := []
var hook_cd := 0.0
var _rope: MeshInstance3D
var _clash_t := 0.0
var _aim_line: MeshInstance3D
const AIM_RED := Color8(0xe2, 0x3b, 0x2e)
## How far the red line reaches when nothing is in the way (lost in the fog: "infinite").
const LINE_LEN := 220.0
## A ship's size for the red line and for balls landing on it.
const HIT_R := 3.0
## Ball flight: seconds per metre and a fixed part (faster balls, flatter arc).
const BALL_SPM := 1.0 / 120.0
const BALL_T0 := 0.06
const BALL_ARC := 1.2


func _ready() -> void:
	rng.randomize()
	s = Rules.load_game(save_path)
	_build_world()
	rebuild_player()
	P.node.position = Rules.DOCK
	P.hp = P.max_hp
	for i in ENEMIES:
		spawn_enemy(true)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	_on_resize()
	get_viewport().size_changed.connect(_on_resize)
	camera.position = Rules.DOCK + cam_off
	_aim_camera()
	hud.toast("Vous partez avec %s pièces et %d cartes au trésor." % [Rules.fmt(s.coins), s.maps])


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Models.FOG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xb8, 0xc8, 0xc6)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Models.FOG
	env.fog_density = 1.0
	env.fog_depth_begin = 75.0
	env.fog_depth_end = 185.0
	env.fog_depth_curve = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color8(0xff, 0xf0, 0xda)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	sun.look_at_from_position(Vector3(-40, 85, 25), Vector3.ZERO, Vector3.UP)
	camera = Camera3D.new()
	camera.fov = CAM_FOV
	camera.near = 0.5
	camera.far = 500.0
	add_child(camera)
	sea = Models.sea()
	add_child(sea)
	isles = Rules.islands()
	for i in isles.size():
		add_child(Models.island(isles[i].x, isles[i].z, isles[i].r, i == 0))
	rebuild_port()
	_build_aim_mark()


## The aim on the water: a red line from the ship that runs on until it meets a ship or an
## island (no ring on the target).
func _build_aim_mark() -> void:
	aim_mark = Node3D.new()
	aim_mark.visible = false
	add_child(aim_mark)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.08, 1.0)
	_aim_line = Models.instance(bm, Models.flat_mat(AIM_RED, 0.9), false)
	aim_mark.add_child(_aim_line)
	# the purple grapple line, the same way
	hook_mark = Node3D.new()
	hook_mark.visible = false
	add_child(hook_mark)
	_hook_line = Models.instance(bm, Models.flat_mat(HOOK_PURPLE, 0.9), false)
	hook_mark.add_child(_hook_line)
	# the rope between two ships at a boarding (and behind a flying grapple)
	var rm := BoxMesh.new()
	rm.size = Vector3(0.12, 0.12, 1.0)
	_rope = Models.instance(rm, _lit_mat(Color8(0x6b, 0x55, 0x3c)), false)
	_rope.visible = false
	add_child(_rope)


func _on_resize() -> void:
	var sz := get_viewport().get_visible_rect().size
	cam_off = Vector3(0, 62, 50) if sz.x < sz.y else Vector3(0, 46, 38)


func rebuild_port() -> void:
	if port_deco:
		port_deco.queue_free()
	port_deco = Models.port_deco(s.base.defense, s.base.coffre)
	add_child(port_deco)


func pstats() -> Dictionary:
	return Rules.player_stats(s)


func rebuild_player() -> void:
	var old := P.node
	P.node = Models.ship(Models.player_cfg(s))
	P.is_player = true
	P.name = "Vous"
	P.st = pstats()
	P.max_hp = P.st.max_hp
	P.hp = minf(P.hp, P.max_hp)
	if old:
		P.node.position = old.position
		P.node.rotation = old.rotation
		old.queue_free()
	add_child(P.node)
	P.arcs = Models.arcs(P.st)
	P.node.add_child(P.arcs)


## Online players may attack you; offline ones (their AI) only defend themselves.
func spawn_enemy(far: bool) -> Boat:
	var x := 0.0
	var z := 0.0
	for t in 50:
		var a := rng.randf() * TAU
		var d := rng.randf_range(70, Rules.WORLD_R - 15)
		x = cos(a) * d
		z = sin(a) * d
		var clear := true
		for i in isles:
			if Vector2(i.x - x, i.z - z).length() <= i.r + 6:
				clear = false
		if clear and (not far or P.node == null or Vector2(P.node.position.x - x, P.node.position.z - z).length() > 90):
			break
	var e := Boat.new()
	e.lvl = 1 + int(rng.randf() * rng.randf() * 5)
	e.offline = rng.randf() < 0.45
	var bd := Rules.enemy_build(e.lvl)
	e.hk = bd.hull
	e.st = bd.st
	var crew := []
	var counts := {}
	for i in 2 + e.lvl * 2:
		var c: Dictionary = Rules.CREW[mini(3, int(rng.randf() * e.lvl))]
		crew.append(c.color)
		counts[c.k] = int(counts.get(c.k, 0)) + 1
	e.up = bd.up
	e.fighters = Rules.fighters(counts, int(bd.up.get("capitaine", 0)))
	var dark := Color8(0x1d, 0x1f, 0x21)
	e.node = Models.ship(Models.ship_cfg(e.hk, bd.up, crew, {"hull": Color8(0x4f, 0x3a, 0x2c),
		"sail": Color8(0x9b, 0x9a, 0x92) if e.offline else Color8(0x3c, 0x42, 0x46), "trim": dark, "flag": dark}))
	e.node.position = Vector3(x, 0, z)
	add_child(e.node)
	e.name = Rules.NAMES[name_idx % Rules.NAMES.size()]
	name_idx += 1
	e.h = rng.randf() * TAU
	e.max_hp = e.st.max_hp
	e.hp = e.max_hp
	e.coins = 140 * e.lvl + rng.randi_range(0, 220)
	e.aggro_cd = rng.randf_range(8, 20)
	enemies.append(e)
	return e


# ---------------------------------------------------------------- effects

func _lit_mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _lit.has(k):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 1.0
		_lit[k] = m
	return _lit[k]


func _part(m: Mesh, c: Color, p: Vector3, sc: Vector3, vel: Vector3, life: float, grow: float, grav: float, spin := 0.0) -> void:
	var mi := Models.instance(m, _lit_mat(c), false)
	mi.position = p
	mi.scale = sc
	add_child(mi)
	parts.append({"n": mi, "vel": vel, "life": life, "max": life, "grow": grow, "grav": grav, "spin": spin, "sc": sc})


func puff(p: Vector3, c: Color, n: int, size: float, spread: float, up: float, life: float) -> void:
	for i in n:
		_part(_puff_mesh, c, p, Vector3.ONE * size * rng.randf_range(0.6, 1.2),
			Vector3(rng.randf_range(-spread, spread), rng.randf_range(up * 0.5, up), rng.randf_range(-spread, spread)), life, 1.6, 0)


func debris(p: Vector3, n: int) -> void:
	for i in n:
		_part(_chip_mesh, Color8(0x7a, 0x56, 0x36), p, Vector3(0.5, 0.15, 0.2),
			Vector3(rng.randf_range(-4, 4), rng.randf_range(3, 7), rng.randf_range(-4, 4)), 1.1, 0, 14, rng.randf_range(-8, 8))


func splash(p: Vector3) -> void:
	for i in 6:
		_part(_puff_mesh, Color8(0xee, 0xf3, 0xf2), Vector3(p.x, 0.3, p.z), Vector3.ONE * 0.35,
			Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(4, 7), rng.randf_range(-1.5, 1.5)), 0.8, 0.3, 12)


func ripple(p: Vector3) -> void:
	for i in 3:
		_part(_puff_mesh, Color8(0xee, 0xf3, 0xf2), Vector3(p.x, 0.15, p.z), Vector3.ONE * 0.16,
			Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(1.2, 2.2), rng.randf_range(-0.6, 0.6)), 0.45, 0.4, 8)


func _update_parts(dt: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[i]
		p.life -= dt
		if p.life <= 0:
			p.n.queue_free()
			parts.remove_at(i)
			continue
		p.vel.y -= p.grav * dt
		p.n.position += p.vel * dt
		if p.grow:
			p.sc *= 1.0 + p.grow * dt
		if p.spin:
			p.n.rotation.x += p.spin * dt
		# low poly puffs shrink away instead of fading (no transparency to sort)
		p.n.scale = p.sc * minf(1.0, p.life / p.max / 0.4)


# ---------------------------------------------------------------- cannon fire

## A volley of n balls from `from` (the battery's side when `ang` is given) at the target,
## leading it, along an arc.
## With `at`, the balls fall around that point instead (the player's aimed shots).
## `mouths`: where the balls leave (each gun of the battery, see gun_mouths); `home`: each ball
## keeps flying at the target ship wherever it goes (the player's aimed shots).
func fire(from: Vector3, target: Boat, n: int, dmg: float, by_player: bool, ang := NAN, at := Vector3.INF, mouths := [], home := false) -> void:
	var sx := from.x + (0.0 if is_nan(ang) else sin(ang) * 1.5)
	var sz := from.z + (0.0 if is_nan(ang) else cos(ang) * 1.5)
	var aimed := at.is_finite()
	var tp := at if aimed else target.pos()
	var tv := Vector3.ZERO if aimed else Vector3(sin(target.h), 0, cos(target.h)) * target.v
	var spread := 0.0 if aimed else 1.8
	for i in n:
		var start: Vector3 = Vector3(sx, 1.4, sz) if mouths.is_empty() else mouths[i % mouths.size()]
		var dur := Vector2(tp.x - start.x, tp.z - start.z).length() * BALL_SPM + BALL_T0
		var to := Vector3(tp.x + tv.x * dur * 0.85 + rng.randf_range(-spread, spread), 0, tp.z + tv.z * dur * 0.85 + rng.randf_range(-spread, spread))
		var mi := Models.instance(_ball_mesh, _lit_mat(Color8(0x24, 0x28, 0x2a)))
		mi.visible = false
		add_child(mi)
		balls.append({"n": mi, "from": start, "to": to, "t": -i * 0.05, "dur": dur, "dmg": dmg, "target": target, "by_player": by_player, "home": home})
		puff(start, Color8(0xd8, 0xdc, 0xd9), 2, 0.45, 1.0, 1.2, 0.9)


## Where the guns of a battery are in the world, a little out from the hull (their muzzles).
func gun_mouths(me: Boat, k: String) -> Array:
	var hk: String = s.ship if me.is_player else me.hk
	var sc: Vector3 = Rules.HULLS[hk].scale
	var out := []
	var bas := Basis(Vector3.UP, me.h)
	var outward := {"bab": Vector3(1, 0, 0), "tri": Vector3(-1, 0, 0), "av": Vector3(0, 0, 1), "ar": Vector3(0, 0, -1)}
	for g in Models.gun_spots(me.st, k):
		var local: Vector3 = g * sc + outward[k] * 0.45
		out.append(me.pos() + bas * local)
	return out


## Fires every loaded battery that has the foe in its arc. `ammo` (player only) pays a ball
## per volley. Returns the batteries that bear on the foe.
func shoot_batteries(me: Boat, foe: Boat, dt: float, ammo := Callable()) -> Array:
	for k in me.rl:
		me.rl[k] -= dt
	var mp := me.pos()
	var fp := foe.pos()
	var bearing := []
	if Vector2(fp.x - mp.x, fp.z - mp.z).length() > me.st.range:
		return bearing
	var rel := Rules.rel_bearing(mp.x, mp.z, me.h, fp.x, fp.z)
	for b in Rules.in_arcs(Rules.batteries(me.st), rel):
		bearing.append(b.k)
		if me.rl.get(b.k, 0.0) > 0:
			continue
		if ammo.is_valid() and not ammo.call():
			continue
		fire(mp, foe, b.n, me.st.dmg, me.is_player, me.h + b.c, Vector3.INF, gun_mouths(me, b.k))
		me.rl[b.k] = me.st.reload
	return bearing


## The player can aim while connected, alive, at sea and fighting.
func can_aim() -> bool:
	return connected and alive and not hud.port_open() and combat and combat.e.state != "sink" and not combat.has("board")


## The purple grapple stick shows with the green one.
func can_grapple() -> bool:
	return can_aim()


func hooking() -> bool:
	return hud.hook_active and hud.hook_mag > Hud.AIM_DEAD and can_grapple()


## Where the ray from (o) along (d) first enters a circle (c, r), or INF.
static func _ray_circle(o: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var q := oc.length_squared() - r * r
	if q <= 0:
		return 0.0
	var disc := b * b - q
	if b > 0 or disc < 0:
		return INF
	return -b - sqrt(disc)


## The red line: from the ship in the green stick's direction until the first ship or island.
## {dist, point, boat (or null), isle (bool)}; nothing in the way: dist = LINE_LEN.
func aim_ray(dir := Vector2.INF) -> Dictionary:
	var o := P.xz()
	var d := (hud.aim_vec if dir == Vector2.INF else dir).normalized()
	var best := {"dist": LINE_LEN, "boat": null, "isle": false}
	if d == Vector2.ZERO:
		d = Vector2(sin(P.h), cos(P.h))
	for e in enemies:
		if e.state == "sink" or e.state == "taken":
			continue
		var t := _ray_circle(o, d, e.xz(), HIT_R)
		if t < best.dist:
			best = {"dist": t, "boat": e, "isle": false}
	for isl in isles:
		var t := _ray_circle(o, d, Vector2(isl.x, isl.z), float(isl.r))
		if t < best.dist:
			best = {"dist": t, "boat": null, "isle": true}
	var p := o + d * float(best.dist)
	best.point = Vector3(p.x, 0, p.y)
	return best


## Where the balls will fall: on what the red line meets (or at the guns' range when it
## meets nothing).
func aim_point() -> Vector3:
	var r := aim_ray()
	if r.boat == null and not r.isle:
		var pp := P.pos()
		var d := hud.aim_vec.normalized()
		var rg: float = P.st.range
		return Vector3(pp.x + d.x * rg, 0, pp.z + d.y * rg)
	if r.boat:
		# the balls go for the middle of the ship the line touches
		var bp: Vector3 = r.boat.pos()
		return Vector3(bp.x, 0, bp.z)
	return r.point


func on_island(p: Vector3) -> bool:
	for isl in isles:
		if Vector2(p.x - isl.x, p.z - isl.z).length() < float(isl.r):
			return true
	return false


func aiming() -> bool:
	return hud.aim_active and hud.aim_mag > Hud.AIM_DEAD and can_aim()


## The batteries that bear on the aimed point (the ones that will fire on release).
func aim_batteries() -> Array:
	var pp := P.pos()
	var at := aim_point()
	return Rules.in_arcs(Rules.batteries(P.st), Rules.rel_bearing(pp.x, pp.z, P.h, at.x, at.z))


## The green stick was released: every loaded battery that bears on the aimed point fires
## there. Returns how many volleys left.
func fire_aimed() -> int:
	if not can_aim():
		return 0
	var ray := aim_ray()
	var foe: Boat = ray.boat if ray.boat else combat.e
	var at := aim_point()
	if (ray.boat or ray.isle) and float(ray.dist) > float(P.st.range):
		hud.toast("Trop loin pour les canons (%d m) : approchez-vous." % int(P.st.range))
		return 0
	# any bearing: the loaded battery facing closest to the aim fires
	var pp := P.pos()
	var rel := Rules.rel_bearing(pp.x, pp.z, P.h, at.x, at.z)
	var best := {}
	for b in Rules.batteries(P.st):
		if P.rl.get(b.k, 0.0) > 0:
			continue
		if best.is_empty() or absf(Rules.wrap_a(rel - b.c)) < absf(Rules.wrap_a(rel - best.c)):
			best = b
	if best.is_empty():
		hud.toast("Les canons rechargent…")
		return 0
	if not _pay_ball():
		return 0
	fire(pp, foe, best.n, P.st.dmg, true, P.h + best.c, at, gun_mouths(P, best.k), ray.boat != null)
	P.rl[best.k] = P.st.reload
	var n := 1
	if n > 0 and combat.mode == "pending":
		combat.mode = "fight"
		hud.hide_prompt()
	return n


func _update_aim_mark() -> void:
	var on := aiming()
	aim_mark.visible = on
	if not on:
		return
	var pp := P.pos()
	var ray := aim_ray()
	var end: Vector3 = ray.point
	var len := maxf(0.1, Vector2(end.x - pp.x, end.z - pp.z).length())
	_aim_line.position = Vector3((pp.x + end.x) / 2, 0.6, (pp.z + end.z) / 2)
	_aim_line.rotation = Vector3(0, atan2(end.x - pp.x, end.z - pp.z), 0)
	_aim_line.scale = Vector3(1, 1, len)
	# no ring on the target (Guillaume, 2026-11-27): the line fades when it can't fire there
	var hit: bool = ray.boat != null or ray.isle
	var ready: bool = s.balls > 0 and (not hit or float(ray.dist) <= float(P.st.range))
	_aim_line.material_override = Models.flat_mat(AIM_RED, 0.9 if ready else 0.35)


## The purple line: like the red one, from the ship along the purple stick to the first ship
## or island.
func _update_hook_mark() -> void:
	var on := hooking()
	hook_mark.visible = on
	if not on:
		return
	var pp := P.pos()
	var ray := aim_ray(hud.hook_vec)
	var end: Vector3 = ray.point
	var len := maxf(0.1, Vector2(end.x - pp.x, end.z - pp.z).length())
	_hook_line.position = Vector3((pp.x + end.x) / 2, 0.62, (pp.z + end.z) / 2)
	_hook_line.rotation = Vector3(0, atan2(end.x - pp.x, end.z - pp.z), 0)
	_hook_line.scale = Vector3(1, 1, len)
	# bright when a ship on the line is within the grapple's reach, faded otherwise
	var ok: bool = ray.boat != null and float(ray.dist) <= float(P.st.grapple)
	_hook_line.material_override = Models.flat_mat(HOOK_PURPLE, 0.9 if ok else 0.35)


## The purple stick was released: the grapple flies along the purple line. It catches the
## first ship there if that ship is within reach; then the boarding starts.
func throw_grapple() -> bool:
	if not can_grapple():
		return false
	if hook_cd > 0 or not hooks.is_empty():
		hud.toast("Le grappin n'est pas encore prêt.")
		return false
	var ray := aim_ray(hud.hook_vec)
	var reach: float = P.st.grapple
	var hit: Boat = ray.boat if ray.boat and float(ray.dist) <= reach else null
	var d := hud.hook_vec.normalized()
	var pp := P.pos()
	var to: Vector3
	if hit:
		to = Vector3(hit.pos().x, 0, hit.pos().z)
	else:
		var r := minf(reach, float(ray.dist))
		to = Vector3(pp.x + d.x * r, 0, pp.z + d.y * r)
	var mi := Models.instance(_ball_mesh, _lit_mat(Color8(0x3a, 0x3a, 0x40)))
	add_child(mi)
	var dist := Vector2(to.x - pp.x, to.z - pp.z).length()
	hooks.append({"n": mi, "from": pp, "to": to, "boat": hit, "t": 0.0, "dur": dist / 40.0 + 0.12})
	hook_cd = 2.0
	if ray.boat and not hit:
		hud.toast("Trop loin pour le grappin (%d m) : approchez-vous." % int(reach))
	return hit != null


func _update_hooks(dt: float) -> void:
	hook_cd = maxf(0, hook_cd - dt)
	for i in range(hooks.size() - 1, -1, -1):
		var h: Dictionary = hooks[i]
		h.t += dt
		var k := minf(1.0, h.t / h.dur)
		var from := P.pos()
		var p: Vector3 = from.lerp(h.to, k)
		p.y = 1.6 + sin(PI * k) * 2.0
		h.n.position = p
		_set_rope(from + Vector3(0, 1.4, 0), p)
		if k >= 1:
			h.n.queue_free()
			hooks.remove_at(i)
			_rope.visible = false
			var b: Boat = h.boat
			if b and alive and enemies.has(b) and b.state != "sink" and b.state != "taken" and b.xz().distance_to(P.xz()) <= float(P.st.grapple) + 4:
				start_boarding(b, true)
			else:
				splash(h.to)
				hud.toast("Le grappin tombe à l'eau.")


func _set_rope(a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	_rope.visible = len > 0.2
	if not _rope.visible:
		return
	_rope.position = (a + b) / 2
	_rope.look_at_from_position(_rope.position, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	_rope.scale = Vector3(1, 1, len)


# ---------------------------------------------------------------- boarding

## Grappled: the two ships are pulled side by side, guns fall silent, and the crews and
## captains fight until one side has nobody left standing.
func start_boarding(e: Boat, by_player: bool) -> void:
	if combat.is_empty() or combat.e != e:
		if combat:
			end_combat()
		start_combat(e, "fight")
	combat.mode = "fight"
	combat.board = {"mine": Rules.fighters(s.crew, int(s.up.capitaine)), "theirs": e.fighters, "by": by_player}
	hud.hide_prompt()
	hud.cancel_sticks()
	auto_flee = false
	throttle = 0
	hud.toast("À l'abordage ! Votre équipage saute sur %s." % e.name if by_player else "%s vous aborde ! Votre équipage se défend." % e.name, "bad" if not by_player else "")


func _update_boarding(e: Boat, dt: float) -> void:
	var bd: Dictionary = combat.board
	# pull the foe alongside, parallel to us
	var side := Vector3(cos(P.h), 0, -sin(P.h))
	var off := e.pos() - P.pos()
	if off.dot(side) < 0:
		side = -side
	var want := P.pos() + side * (HIT_R * 1.6)
	e.node.position.x = lerpf(e.node.position.x, want.x, 1 - exp(-3 * dt))
	e.node.position.z = lerpf(e.node.position.z, want.z, 1 - exp(-3 * dt))
	e.h += clampf(Rules.wrap_a(P.h - e.h), -dt, dt)
	e.v = 0
	_set_rope(P.pos() + Vector3(0, 1.4, 0), e.pos() + Vector3(0, 1.4, 0))
	Rules.melee(bd.mine, bd.theirs, dt)
	_clash_t -= dt
	if _clash_t <= 0:
		_clash_t = 0.35
		var mid := (P.pos() + e.pos()) / 2
		puff(Vector3(mid.x + rng.randf_range(-1.5, 1.5), 1.8, mid.z + rng.randf_range(-1.5, 1.5)), Color8(0xe8, 0xe2, 0xd0), 2, 0.35, 0.8, 1.2, 0.6)
	if Rules.alive_count(bd.theirs) == 0:
		boarding_won(e)
	elif Rules.alive_count(bd.mine) == 0:
		boarding_lost(e)


## Cutting the ropes ends the boarding (the guns can speak again).
func cut_ropes() -> void:
	if combat.has("board"):
		var bd: Dictionary = combat.board
		s.crew = Rules.survivors(bd.mine)
		combat.erase("board")
		_rope.visible = false
		hook_cd = 4.0
		rebuild_player()
		hud.toast("On coupe les cordes !")


## Everybody over there is down: the ship is yours. Its treasure counts twice; keep the ship
## or send it down.
func boarding_won(e: Boat) -> void:
	var bd: Dictionary = combat.board
	s.crew = Rules.survivors(bd.mine)
	combat = {}
	_hide_arcs()
	_rope.visible = false
	e.state = "taken"
	e.v = 0
	var gold := e.coins * 2
	s.coins += gold
	var map := rng.randf() < minf(1.0, Rules.map_chance(e.lvl) * 2)
	if map:
		s.maps += 1
	rebuild_player()
	save()
	var hk := e.hk
	var mine: String = Rules.HULLS[s.ship].name
	var theirs: String = Rules.HULLS[hk].name
	hud.show_prompt("%s est à vous !" % e.name, "Trésor ×2 : +%s pièces%s. Prendre ce bateau (%s) ? Vous laisserez le vôtre (%s)." % [
		Rules.fmt(gold), " et une carte au trésor" if map else "", theirs, mine], [
		["Prendre le bateau", keep_prize.bind(e), true],
		["Le couler", sink_prize.bind(e), false]])
	hud.toast("Abordage réussi ! +%s pièces" % Rules.fmt(gold), "gold")


func keep_prize(e: Boat) -> void:
	if e.state != "taken":
		return
	var hp := e.hp
	var ratio := clampf(e.hp / e.max_hp, 0.3, 1.0)
	Rules.take_hull(s, e.hk, e.up)
	P.node.position = e.node.position
	P.h = e.h
	P.node.rotation.y = e.h
	rebuild_player()
	P.hp = maxf(hp, P.max_hp * ratio)
	e.node.queue_free()
	enemies.erase(e)
	spawn_timers.append(15.0)
	hud.hide_prompt()
	save()
	hud.toast("Vous naviguez sur %s, votre nouveau %s." % [e.name, Rules.HULLS[e.hk].name], "gold")


func sink_prize(e: Boat) -> void:
	if e.state != "taken":
		return
	e.state = "sink"
	e.sink_t = 0
	debris(Vector3(e.pos().x, 1, e.pos().z), 14)
	spawn_timers.append(15.0)
	hud.hide_prompt()


## Our whole crew and captain fell: the ship is lost.
func boarding_lost(e: Boat) -> void:
	s.crew = Rules.survivors(combat.board.mine)
	combat.erase("board")
	_rope.visible = false
	rebuild_player()
	hud.toast("%s a vaincu tout votre équipage." % e.name, "bad")
	player_defeated()


## Leaving the game (app in the background, window left) disconnects the player: from then
## on the ship defends itself. Coming back hands the guns back.
func set_connected(on: bool) -> void:
	if on == connected:
		return
	connected = on
	if not on:
		hud.cancel_sticks()
		away_fight = not combat.is_empty()
		if combat and combat.mode == "pending":
			combat.mode = "fight"
			hud.hide_prompt()
	elif hud:
		if combat or away_fight:
			hud.toast("De retour ! Votre bateau s'est défendu seul pendant votre absence.")
		away_fight = false


func ai_maneuver(me: Boat, foe: Boat, dt: float, agg: float) -> float:
	me.ai_t -= dt
	if me.ai_t <= 0:
		me.ai_t = 0.25
		var r := Rules.ai_choose(me.view(), me.st, foe.view(), foe.st, agg, isles)
		me.ai_h = r[0]
		me.ai_s = r[1]
	me.h += clampf(Rules.wrap_a(me.ai_h - me.h), -me.st.turn * dt, me.st.turn * dt)
	return me.ai_s


func _update_balls(dt: float) -> void:
	for i in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[i]
		b.t += dt
		if b.t < 0:
			continue
		b.n.visible = true
		if b.get("home", false):
			var ht: Boat = b.target
			if ht.state != "sink" and enemies.has(ht):
				b.to = Vector3(ht.pos().x, 0, ht.pos().z)
		var k := minf(1.0, b.t / b.dur)
		var p: Vector3 = b.from.lerp(b.to, k)
		p.y = lerpf(b.from.y, 1.2, k) + sin(PI * k) * BALL_ARC
		b.n.position = p
		if k >= 1:
			b.n.queue_free()
			balls.remove_at(i)
			var t: Boat = b.target
			var tp := t.pos()
			var up := alive if t.is_player else (t.state != "sink" and enemies.has(t))
			if up and Vector2(tp.x - b.to.x, tp.z - b.to.z).length() < 3.4:
				hurt(t, b.dmg, b.by_player)
				debris(Vector3(tp.x, 1.2, tp.z), 5)
				puff(Vector3(tp.x, 1.5, tp.z), Color8(0x5c, 0x5f, 0x5d), 3, 0.5, 1, 1.5, 1)
			else:
				if on_island(b.to):
					puff(Vector3(b.to.x, 1.2, b.to.z), Color8(0xc9, 0xbf, 0xa4), 4, 0.6, 1.2, 1.4, 1.0)
				else:
					splash(b.to)


# ---------------------------------------------------------------- combat

func hurt(t: Boat, d: float, by_player: bool) -> void:
	if t.is_player:
		if not alive:
			return
		P.hp -= d
		hud.flash()
		if P.hp <= 0:
			player_defeated()
	else:
		if t.state == "sink" or t.state == "taken":
			return
		t.hp -= d
		if t.offline and by_player and t.state == "wander":
			t.state = "defend"
		if t.hp <= 0:
			enemy_defeated(t)


func start_combat(e: Boat, mode: String) -> void:
	combat = {"e": e, "mode": mode, "t": 6.0, "no_ammo": false}
	if e.arcs == null:
		e.arcs = Models.arcs(e.st)
		e.node.add_child(e.arcs)
	e.arcs.visible = true
	P.arcs.visible = false   # the player's guns fire any way now: no arcs to show
	auto_flee = false
	last_input = time
	e.state = "defend" if e.offline else "attack"
	if mode == "pending":
		var n: int = e.st.side
		hud.show_prompt("%s vous attaque !" % e.name, "%s, %d canon%s par côté. Visez avec le joystick vert pour tirer." % [
			Rules.HULLS[e.hk].name, n, "s" if n > 1 else ""])
	else:
		hud.hide_prompt()
	if mode == "fight":
		hud.toast("À l'attaque de %s !" % e.name)


func _hide_arcs() -> void:
	P.arcs.visible = false
	if combat and combat.e.arcs:
		combat.e.arcs.visible = false


func end_combat(msg := "", kind := "") -> void:
	_hide_arcs()
	if combat:
		var e: Boat = combat.e
		if e.state != "sink":
			e.state = "wander"
			e.aggro_cd = 35
			e.tgt = Vector2.INF
	combat = {}
	hud.hide_prompt()
	if msg != "":
		hud.toast(msg, kind)


func on_fight() -> void:
	if combat:
		combat.mode = "fight"
		auto_flee = false
		last_input = time
		hud.hide_prompt()
		hud.toast("Riposte ! Visez avec le joystick vert.")


func on_flee() -> void:
	if combat:
		combat.mode = "flee"
		auto_flee = true
		hud.hide_prompt()
		hud.toast("On fuit ! Le joystick vert vise encore.")


func enemy_defeated(e: Boat) -> void:
	e.state = "sink"
	e.sink_t = 0
	s.coins += e.coins
	# the wreck may hold a treasure map, more often on big ships
	var map := rng.randf() < Rules.map_chance(e.lvl)
	if map:
		s.maps += 1
	save()
	hud.toast("%s coule. +%s pièces%s" % [e.name, Rules.fmt(e.coins), " et une carte au trésor !" if map else ""], "gold")
	debris(Vector3(e.pos().x, 1, e.pos().z), 14)
	if combat and combat.e == e:
		_hide_arcs()
		combat = {}
		hud.hide_prompt()
	spawn_timers.append(15.0)


func player_defeated() -> void:
	alive = false
	var lost := Rules.defeat_loss(s)
	if combat:
		combat.e.coins += lost
	end_combat()
	hud.toast("Votre bateau a coulé. %s pièces perdues. Le coffre du port est intact." % Rules.fmt(lost), "bad")
	debris(Vector3(P.pos().x, 1, P.pos().z), 14)
	respawn_t = 2.6


func _respawn() -> void:
	P.node.position = Rules.DOCK
	P.h = 0
	P.v = 0
	throttle = 0
	P.hp = P.max_hp
	alive = true
	P.node.get_meta("body").rotation = Vector3.ZERO
	save()


# ---------------------------------------------------------------- treasure

func use_map() -> void:
	if treasure:
		hud.toast("Une carte est déjà en cours : suivez la flèche dorée.")
		return
	if s.maps <= 0:
		hud.toast("Plus de cartes au trésor.")
		return
	s.maps -= 1
	save()
	var isl: Dictionary = isles[rng.randi_range(1, isles.size() - 1)]
	var a := rng.randf() * TAU
	var p := Vector3(isl.x + cos(a) * (isl.r + 3.5), 0, isl.z + sin(a) * (isl.r + 3.5))
	var g := Models.treasure()
	g.position = p
	add_child(g)
	treasure = {"pos": p, "node": g, "gold": rng.randi_range(300, 800)}
	hud.toast("La carte indique une île. Suivez la flèche dorée.")


func _collect_treasure() -> void:
	s.coins += treasure.gold
	save()
	hud.toast("Trésor trouvé ! +%s pièces" % Rules.fmt(treasure.gold), "gold")
	puff(treasure.pos + Vector3(0, 1, 0), Color8(0xe0, 0xb4, 0x5a), 10, 0.4, 2.5, 4, 1.4)
	treasure.node.queue_free()
	treasure = {}


# ---------------------------------------------------------------- port

func in_base() -> bool:
	return P.xz().length() < Rules.BASE_ZONE


func open_port() -> void:
	P.v = 0
	throttle = 0
	hud.open_port()


## After buying something at the port: rebuild what shows it, and save.
func after_purchase(what: String) -> void:
	match what:
		"hull":
			P.hp = pstats().max_hp
			P.max_hp = P.hp
			rebuild_player()
		"coque":
			rebuild_player()
			P.hp = P.max_hp
		"base":
			rebuild_port()
		"ship":
			rebuild_player()
	save()


func reset_game() -> void:
	s = Rules.fresh()
	P.hp = pstats().max_hp
	rebuild_player()
	P.hp = P.max_hp
	rebuild_port()
	if treasure:
		treasure.node.queue_free()
		treasure = {}
	save()
	hud.toast("Nouvelle partie")


func save() -> void:
	Rules.save_game(s, save_path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if s:
			save()
		if what != NOTIFICATION_WM_CLOSE_REQUEST and hud:
			set_connected(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if hud:
			set_connected(true)
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if hud and hud.port_open():
			hud.close_port()
		else:
			save()
			get_tree().quit()


# ---------------------------------------------------------------- movement

func steer_to(b: Boat, tx: float, tz: float, dt: float, max_speed: float, turn: float) -> float:
	var p := b.pos()
	var diff := Rules.wrap_a(atan2(tx - p.x, tz - p.z) - b.h)
	b.h += clampf(diff, -turn * dt, turn * dt)
	return max_speed * 0.45 if absf(diff) > 1.3 else max_speed


func move_boat(b: Boat, target: float, dt: float) -> void:
	b.v += clampf(target - b.v, -4 * dt, 3 * dt)
	var p := b.node.position
	p.x += sin(b.h) * b.v * dt
	p.z += cos(b.h) * b.v * dt
	for i in isles:
		var d := Vector2(p.x - i.x, p.z - i.z)
		var mn: float = i.r + 2.4
		if d.length() < mn:
			d = d.normalized() * mn
			p.x = i.x + d.x
			p.z = i.z + d.y
			b.v *= 0.9
	var dc := Vector2(p.x, p.z).length()
	if dc > Rules.WORLD_R:
		p.x *= Rules.WORLD_R / dc
		p.z *= Rules.WORLD_R / dc
	b.node.position = p


func anim_boat(b: Boat, t: float, dt: float) -> void:
	var p := b.node.position
	p.y = Rules.wave(p.x, p.z, t) * 0.8 - 0.05
	b.node.position = p
	b.node.rotation.y = b.h
	var body: Node3D = b.node.get_meta("body")
	if b.state != "sink" and (not b.is_player or alive):
		body.rotation.z = sin(t * 1.3 + p.x * 0.1) * 0.05
		body.rotation.x = cos(t * 1.1 + p.z * 0.1) * 0.03
	var rowing := absf(b.v) > 0.4 and b.state != "sink"
	if rowing:
		b.oar += dt * (2.6 + absf(b.v) * 0.35)
	var ph := fmod(b.oar, TAU)
	var stroke := sin(ph) > 0
	Models.row(b.node, ph, rowing)
	var near := b.is_player or Vector2(p.x - P.pos().x, p.z - P.pos().z).length() < 80
	var oars: Array = b.node.get_meta("oars")
	if rowing and near and stroke and not b.stroke and oars.size():
		for o in [oars[oars.size() / 4], oars[oars.size() - 1 - oars.size() / 4]]:
			ripple((o as Node3D).global_transform * Vector3(float(o.get_meta("side")) * 2.15, 0, 0))
	b.stroke = stroke
	# sails fill more the faster the ship goes
	if near:
		Models.billow(b.node, 0.18 + minf(0.5, absf(b.v) * 0.05), t)


# ---------------------------------------------------------------- the loop

func _process(delta: float) -> void:
	if driven:
		return
	kb.l = Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)
	kb.r = Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	kb.f = Input.is_key_pressed(KEY_Z) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	kb.b = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	if hud.port_open():
		kb = {"l": false, "r": false, "f": false, "b": false}
	step(minf(delta, 0.05))


func step(dt: float) -> void:
	time += dt
	var st := pstats()
	P.st = st
	var pp := P.pos()
	var paused := hud.port_open()
	var near_base := in_base()

	# the player
	var joy_mag: float = hud.joy_mag
	var using_joy := hud.joy_active and joy_mag > 0.12 and not paused
	var using_kb: bool = kb.l or kb.r or kb.f or kb.b
	if using_joy or using_kb:
		last_input = time
		auto_flee = false
	var foe: Boat = combat.e if combat and combat.e.state != "sink" else null
	var boarding: bool = combat.has("board")
	if alive:
		if boarding:
			throttle = 0
		elif using_kb:
			if kb.l:
				P.h += st.turn * dt
			if kb.r:
				P.h -= st.turn * dt
			if kb.f:
				throttle = minf(1, throttle + 0.7 * dt)
			if kb.b:
				throttle = maxf(0, throttle - 0.7 * dt)
		elif using_joy:
			# screen: up = north (-z), right = +x; the stick's reach sets the speed
			var want := atan2(hud.joy_vec.x, hud.joy_vec.y)
			P.h += clampf(Rules.wrap_a(want - P.h), -st.turn * dt, st.turn * dt)
			throttle = clampf((joy_mag - 0.12) / 0.88, 0, 1)
		elif foe and auto_flee:
			var ep := foe.pos()
			var want := atan2(pp.x - ep.x, pp.z - ep.z)
			P.h += clampf(Rules.wrap_a(want - P.h), -st.turn * dt, st.turn * dt)
			throttle = 1
		elif foe and not connected:
			# away from the game: the ship manoeuvres by itself (never while connected)
			throttle = ai_maneuver(P, foe, dt, 1) / st.speed
		move_boat(P, 0.0 if paused else st.speed * throttle, dt)
		if near_base and not combat:
			P.hp = minf(st.max_hp, P.hp + 12 * dt)
		anim_boat(P, time, dt)
	else:
		P.node.position.y -= dt
		P.node.get_meta("body").rotation.z += dt * 0.5
		respawn_t -= dt
		if respawn_t <= 0:
			_respawn()
	pp = P.pos()

	# the player's guns: each battery fires when the foe is in its arc
	if combat and alive and foe and boarding:
		_update_boarding(foe, dt)
	elif combat and alive and foe:
		var e := foe
		var ep := e.pos()
		var d := Vector2(ep.x - pp.x, ep.z - pp.z).length()
		if combat.mode == "pending":
			combat.t -= dt
			if combat.t <= 0:
				combat.mode = "fight"
				hud.hide_prompt()
				hud.toast("À vous de tirer : visez avec le joystick vert.")
		if not connected and combat.mode != "pending":
			# away from the game: the ship fires by itself
			var bearing := shoot_batteries(P, e, dt, _pay_ball)
			Models.set_arcs(P.arcs, bearing, Color8(0xf3, 0xf6, 0xf3))
		else:
			# connected: the guns only reload; the player fires them with the green stick
			for k in P.rl:
				P.rl[k] -= dt
			var bearing := []
			if aiming():
				for b in aim_batteries():
					bearing.append(b.k)
				Models.set_arcs(P.arcs, bearing, Color8(0x5f, 0xd0, 0x6a))
			else:
				for b in Rules.in_arcs(Rules.batteries(st), Rules.rel_bearing(pp.x, pp.z, P.h, ep.x, ep.z)):
					if d <= st.range:
						bearing.append(b.k)
				Models.set_arcs(P.arcs, bearing, Color8(0xf3, 0xf6, 0xf3))
		if combat and combat.mode == "flee" and d > 48:
			end_combat("Vous avez semé %s." % e.name)
		elif combat and not e.offline and near_base and s.base.defense > 0:
			end_combat("%s renonce : vos tours le tiennent à distance." % e.name)
		elif combat and e.offline and d > 60:
			end_combat("%s est loin, le combat s'arrête." % e.name)

	# enemies
	for i in range(enemies.size() - 1, -1, -1):
		var e := enemies[i]
		var ep := e.pos()
		if e.state == "taken":
			# a prize waiting for your choice: it lies still
			move_boat(e, 0, dt)
			anim_boat(e, time, dt)
			continue
		if e.state == "sink":
			e.sink_t += dt
			e.node.position.y -= dt * 1.1
			e.node.get_meta("body").rotation.z += dt * 0.35
			if e.sink_t > 3.2:
				e.node.queue_free()
				enemies.remove_at(i)
			continue
		var d := Vector2(ep.x - pp.x, ep.z - pp.z).length()
		var target := 0.0
		e.aggro_cd -= dt
		var fighting: bool = combat and combat.e == e and alive
		if fighting and combat.has("board"):
			target = 0.0
		elif fighting:
			target = ai_maneuver(e, P, dt, 0.6 if e.offline else 1.0)
			if combat.mode != "pending" or not e.offline:
				var bearing := shoot_batteries(e, P, dt)
				Models.set_arcs(e.arcs, bearing, Models.RUST)
			# an attacker close enough throws its grapple (never one that only defends)
			if not e.offline and combat.mode != "pending" and hooks.is_empty() and d < float(e.st.grapple) and rng.randf() < dt * 0.3:
				start_boarding(e, false)
		else:
			e.state = "wander"
			if e.tgt == Vector2.INF or e.tgt.distance_to(e.xz()) < 4 or e.xz().length() < 45:
				var a := rng.randf() * TAU
				var r := rng.randf_range(60, Rules.WORLD_R - 20)
				e.tgt = Vector2(cos(a) * r, sin(a) * r)
			target = steer_to(e, e.tgt.x, e.tgt.y, dt, e.st.speed * (0.35 if e.offline else 0.55), e.st.turn * 0.7)
			if not combat and alive and not paused and not e.offline and d < 26 and e.aggro_cd <= 0 and P.xz().length() > 45 and rng.randf() < dt * 0.25:
				start_combat(e, "pending")
		move_boat(e, target, dt)
		# ships don't sail through each other
		var dx := e.xz() - P.xz()
		var mind: float = 2.4 * (Rules.HULLS[e.hk].scale.z + Rules.HULLS[s.ship].scale.z)
		if dx.length() < mind and alive:
			dx = (dx if dx.length() > 0.001 else Vector2(1, 0)).normalized() * mind
			e.node.position.x = pp.x + dx.x
			e.node.position.z = pp.z + dx.y
		anim_boat(e, time, dt)

	for i in range(spawn_timers.size() - 1, -1, -1):
		spawn_timers[i] -= dt
		if spawn_timers[i] <= 0:
			spawn_timers.remove_at(i)
			spawn_enemy(true)

	# the port's towers
	if s.base.defense > 0:
		tower_t -= dt
		if tower_t <= 0:
			for e in enemies:
				if e.state != "sink" and e.state != "taken" and e.xz().length() < 40:
					fire(Vector3(0, 8, -6), e, s.base.defense, 6, true)
					tower_t = 2.2
					break

	if treasure:
		treasure.node.rotation.y += dt * 0.6
		if alive and Vector2(treasure.pos.x - pp.x, treasure.pos.z - pp.z).length() < 5.5:
			_collect_treasure()

	_update_balls(dt)
	_update_parts(dt)
	_update_aim_mark()
	_update_hook_mark()
	_update_hooks(dt)
	hud.set_actions(_actions(paused, near_base))

	# camera, sea
	var cam_t := Vector3(pp.x, 0, pp.z) + cam_off
	camera.position = camera.position.lerp(cam_t, 1 - exp(-4 * dt))
	_aim_camera()
	var stp := 360.0 / 54.0
	sea.position = Vector3(roundf(camera.position.x / stp) * stp, 0, roundf((camera.position.z - cam_off.z) / stp) * stp)
	(sea.material_override as ShaderMaterial).set_shader_parameter("t", time)
	hud.update(dt)
	save_t += dt
	if save_t > SAVE_EVERY:
		save_t = 0
		save()


func _aim_camera() -> void:
	camera.look_at(camera.position - cam_off, Vector3.UP)


func _pay_ball() -> bool:
	if s.balls > 0:
		s.balls -= 1
		return true
	if not combat.no_ammo:
		combat.no_ammo = true
		hud.toast("Plus de boulets ! Achetez-en au port.", "bad")
	return false


## The context buttons at the bottom of the screen.
func _actions(paused: bool, near_base: bool) -> Array:
	var acts := []
	if paused or not alive:
		return acts
	if not combat:
		var best: Boat = null
		var bd := 28.0
		for e in enemies:
			if e.state == "sink" or e.state == "taken":
				continue
			var dd := e.xz().distance_to(P.xz())
			if dd < bd:
				bd = dd
				best = e
		if best:
			acts.append({"label": "Attaquer %s" % best.name, "primary": true, "fn": start_combat.bind(best, "fight")})
		if near_base:
			acts.append({"label": "Entrer au port", "primary": best == null, "fn": open_port})
		acts.append({"label": "Carte au trésor (%d)" % s.maps, "disabled": s.maps <= 0 or not treasure.is_empty(), "fn": use_map})
	elif combat.has("board"):
		acts.append({"label": "Couper les cordes", "fn": cut_ropes})
	elif combat.mode == "fight":
		acts.append({"label": "Fuir", "fn": func(): combat.mode = "flee"; auto_flee = true; hud.toast("On fuit !")})
	elif combat.mode == "flee":
		acts.append({"label": "Faire face", "primary": true, "fn": func(): combat.mode = "fight"; auto_flee = false; last_input = time})
	return acts


# ---------------------------------------------------------------- updates

## The running build (stamped by CI) and, after a quiet check of update.json, a newer one.
var new_build := 0


func build_id() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if v != "" else "de développement"


func check_update() -> void:
	var url: String = ProjectSettings.get_setting("mer_des_brumes/update_url", "")
	if url == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 5
	add_child(http)
	if http.request(url + "update.json?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		http.queue_free()
		return
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	var have := int(ProjectSettings.get_setting("mer_des_brumes/build", 0))
	var running := build_id()
	if d is Dictionary and int(d.get("build", 0)) > have and not running.begins_with("b%d" % int(d.get("build", 0))):
		new_build = int(d.build)
		if hud:
			hud.refresh_port()


## Restarts the game so the launch check loads the newest build.
func refresh_game() -> void:
	save()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		OS.set_restart_on_exit(true)
		get_tree().quit()
