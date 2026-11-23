class_name Game
extends Node3D
## Vantage: the world, the player, foes, shots, the carrier episode and the camera. It is one
## 3D world: the vertical stage is seen from a high tilted camera, and the carrier episode
## swoops that same camera down behind the ship for a third-person chase (no cut, no scene
## change), then back up.
## The interface is in hud.gd; numbers and rules in rules.gd; meshes in models.gd.
## Tests set `driven = true` and call step() themselves.

## Anything that moves: foes, shots, bullets, pickups, effects.
class Obj:
	var kind := ""
	var node: Node3D
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	## Moves with the scroll frame (screen-relative) in the vertical stage.
	var rel := false
	var hp := 1.0
	var max_hp := 1.0
	var r := 0.5
	var t := 0.0
	var life := 0.0
	var fire_t := 0.0
	var idx := 0
	var x0 := 0.0
	var dmg := 1.0
	var size := 1.0
	var target: Obj
	var dead := false
	var ground := false
	var flash := 0.0
	## Mount point on the carrier (x, y, z from its stern) for turrets and the reactor.
	var anchor := Vector3.INF
	## Height a drone hovers at.
	var size_y := 0.0

const CHUNK := 40.0
## The vertical stage's camera: height, distance behind the frame's centre, horizontal fov.
const TOP_H := 38.0
const TOP_BACK := 17.0
const TOP_FOV := 29.0
const CHUNK_W := 64.0

var driven := false
var save_path := Rules.SAVE_PATH
var rng := RandomNumberGenerator.new()
var s: Dictionary

## hangar, vert, approach, pov, core, escape, exit, down, clear, results
var phase := "hangar"
var phase_t := 0.0
var stage_t := 0.0
var wave_i := 0
var pov_i := 0
var queue: Array = []
var frame_z := 0.0
var foes: Array[Obj] = []
var shots: Array[Obj] = []
var bullets: Array[Obj] = []
var picks: Array[Obj] = []
var fx: Array[Obj] = []

# the player
var ship: Node3D
var ship_mesh: MeshInstance3D
var engine_glow: MeshInstance3D
var ppos := Vector3(0, Rules.PY, 5)
var prel := Vector2(0, 5)
var pvel := Vector2.ZERO
var hp := 3
var inv := 0.0
var fire_cd := 0.0
var miss_cd := 0.0
var bank := 0.0
var touching := false
var last_touch := Vector2.ZERO
var run := {}

# the carrier episode
var carrier: Node3D
var stern_z := 0.0
var carrier_done := false
var rail_s := 0.0
var aim := Vector2.ZERO
var off := Vector2.ZERO
var core: Obj
var approach_from := Vector3.ZERO
var approach_stern := 0.0
## World z of the ship when the chase began (the ship is at rail_z - rail_s).
var rail_z := 0.0
var sentry_n := 0

# camera
var cam: Camera3D
var cam_mode := "top"
var cam_from := Transform3D()
var cam_from_fov := 29.0
var cam_k := 1.0
var cam_dur := 1.0
var shake := 0.0
var world_per_px := 0.02

var sun: DirectionalLight3D
var env: Environment
var noise := FastNoiseLite.new()
var chunks := {}
var hud: Hud
var boss: Obj
var banner := ""
var banner_t := 0.0
var sub_banner := ""


func _ready() -> void:
	s = Rules.load_game(save_path)
	noise.seed = 1337
	noise.frequency = 0.022
	noise.fractal_octaves = 3
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Models.SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xb8, 0xcc, 0xe0)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Models.SKY
	env.fog_density = 1.0
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 170.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(-35), 0)
	sun.light_energy = 1.15
	sun.light_color = Color8(0xff, 0xf4, 0xe2)
	add_child(sun)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	ship = Node3D.new()
	add_child(ship)
	ship_mesh = Models.instance(Models.player())
	ship.add_child(ship_mesh)
	engine_glow = Models.instance(Models.shot_mesh(0.13), Models.glow(Models.CYAN))
	engine_glow.position = Vector3(0, -0.05, 1.4)
	engine_glow.scale = Vector3(1.6, 1, 3)
	ship.add_child(engine_glow)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	to_hangar()


# ---------------------------------------------------------------- flow

func to_hangar() -> void:
	clear_all()
	phase = "hangar"
	phase_t = 0.0
	frame_z = 0.0
	prel = Vector2(0, 4)
	ppos = Vector3(0, Rules.PY, frame_z + prel.y)
	ship.visible = true
	set_cam("top", 0.0)
	update_chunks()
	hud.show_hangar()


func launch() -> void:
	clear_all()
	phase = "vert"
	phase_t = 0.0
	stage_t = 0.0
	wave_i = 0
	pov_i = 0
	queue.clear()
	carrier_done = false
	prel = Vector2(0, 6)
	ppos = Vector3(0, Rules.PY, frame_z + prel.y)
	hp = Rules.max_hp(s)
	inv = 0.0
	fire_cd = 0.0
	miss_cd = 0.5
	run = {"score": 0, "scrap": 0, "kills": 0, "hits": 0, "cleared": false}
	ship.visible = true
	set_cam("top", 0.0)
	hud.show_play()
	say("SECTOR 1", "Glass Coast")


func buy(key: String) -> bool:
	var ok := Rules.buy(s, key)
	if ok:
		Rules.save_game(s, save_path)
	return ok


func end_run(cleared: bool) -> void:
	run.cleared = cleared
	run.grade = Rules.grade(run.kills, Rules.stage_foes(), run.hits, cleared)
	s.scrap += run.scrap
	s.runs += 1
	if cleared:
		s.clears += 1
	run.new_best = run.score > s.best
	s.best = maxi(s.best, run.score)
	Rules.save_game(s, save_path)
	phase = "results"
	phase_t = 0.0
	hud.show_results()


func clear_all() -> void:
	for list in [foes, shots, bullets, picks, fx]:
		for o: Obj in list:
			if o.node:
				o.node.queue_free()
		list.clear()
	if carrier:
		carrier.queue_free()
		carrier = null
	boss = null
	core = null


func say(text: String, sub := "", dur := 2.2) -> void:
	banner = text
	sub_banner = sub
	banner_t = dur


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if driven:
		return
	keys(minf(delta, 0.05))
	step(minf(delta, 0.05))


func _unhandled_input(event: InputEvent) -> void:
	if driven:
		return
	handle(event)


## Pointer input (touch is emulated as mouse). Dragging moves the ship 1:1 in the vertical
## stage and the reticle inside the carrier.
func handle(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		touching = event.pressed
		last_touch = event.position
		if event.pressed and phase == "results" and phase_t > 0.8:
			to_hangar()
	elif event is InputEventMouseMotion and touching:
		drag_by(event.position - last_touch)
		last_touch = event.position


func drag_by(px: Vector2) -> void:
	if phase in ["vert", "exit"]:
		prel += px * world_per_px
		clamp_player()
	elif phase in ["pov", "core", "escape"]:
		off += Vector2(px.x, -px.y) * Rules.POV_DRAG


func keys(dt: float) -> void:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		d.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		d.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		d.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		d.y += 1
	if d != Vector2.ZERO:
		var px_per_s := 11.0 / world_per_px if phase in ["vert", "exit"] else 11.0 / Rules.POV_DRAG
		drag_by(d.normalized() * px_per_s * dt)
	if phase == "hangar" and Input.is_key_pressed(KEY_ENTER):
		launch()
	if phase == "results" and phase_t > 0.8 and (Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_SPACE)):
		to_hangar()


func view_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func clamp_player() -> void:
	prel.x = clampf(prel.x, -Rules.HALF_W, Rules.HALF_W)
	prel.y = clampf(prel.y, Rules.Z_TOP + 3.0, Rules.Z_BOT - 1.0)


func step(dt: float) -> void:
	phase_t += dt
	banner_t -= dt
	inv = maxf(0.0, inv - dt)
	match phase:
		"hangar":
			frame_z -= 3.0 * dt
			ppos = Vector3(0, Rules.PY + sin(phase_t * 1.4) * 0.15, frame_z + prel.y)
			bank = sin(phase_t * 0.8) * 0.15
		"vert":
			step_vert(dt)
		"approach":
			step_approach(dt)
		"pov", "core", "escape":
			step_pov(dt)
		"exit":
			step_exit(dt)
		"down":
			frame_z -= Rules.SCROLL * dt
			if phase_t > 2.2:
				end_run(false)
		"clear":
			frame_z -= Rules.SCROLL * dt
			prel.y = lerpf(prel.y, Rules.Z_TOP - 8.0, minf(1.0, dt * 0.6 * phase_t))
			ppos = Vector3(prel.x, Rules.PY, frame_z + prel.y)
			if phase_t > 3.0:
				end_run(true)
		"results":
			frame_z -= 2.0 * dt
	if phase in ["vert", "approach", "pov", "core", "escape", "exit", "clear"]:
		update_objs(dt)
	elif phase == "down":
		update_objs(dt)
	update_fx(dt)
	update_chunks()
	update_ship(dt)
	update_cam(dt)
	hud.sync()


# ---------------------------------------------------------------- the vertical stage

func step_vert(dt: float) -> void:
	stage_t += dt
	frame_z -= Rules.SCROLL * dt
	var before := prel
	clamp_player()
	ppos = Vector3(prel.x, Rules.PY, frame_z + prel.y)
	pvel = (prel - before) / maxf(dt, 0.001)
	run_waves()
	fire_vert(dt)
	if carrier and not carrier_done and stern_z - frame_z >= Rules.Z_TOP + 2.0:
		begin_approach()


func run_waves() -> void:
	while wave_i < Rules.STAGE.size():
		var w: Dictionary = Rules.STAGE[wave_i]
		if stage_t < w.t:
			break
		if w.kind == "carrier":
			if carrier == null and not carrier_done:
				spawn_carrier()
			if not carrier_done:
				break
			wave_i += 1
			continue
		for i in int(w.n):
			queue.append({"at": stage_t + i * float(w.gap), "kind": w.kind, "x": float(w.x), "i": i, "n": int(w.n)})
		wave_i += 1
	var rest := []
	for q: Dictionary in queue:
		if stage_t >= q.at:
			spawn_vert(q.kind, q.x, q.i, q.n)
		else:
			rest.append(q)
	queue = rest


func new_foe(kind: String, mesh: Mesh) -> Obj:
	var f := Obj.new()
	f.kind = kind
	var d: Dictionary = Rules.FOES[kind]
	f.hp = d.hp
	f.max_hp = d.hp
	f.r = d.r
	f.node = Models.instance(mesh)
	add_child(f.node)
	foes.append(f)
	return f


func spawn_vert(kind: String, x: float, i: int, n: int) -> void:
	var top := frame_z + Rules.Z_TOP - 1.5
	match kind:
		"dart":
			var f := new_foe("dart", Models.dart())
			f.rel = true
			f.idx = i
			f.pos = Vector3(x * 1.25 + (i % 2) * 0.6 - 0.3, Rules.PY, top)
			f.fire_t = 0.9 + 0.1 * i
		"swing":
			var f := new_foe("swing", Models.swing())
			f.rel = true
			f.idx = i
			f.x0 = x * 1.25
			f.pos = Vector3(f.x0, Rules.PY, top)
			f.fire_t = 1.2 + 0.15 * i
		"turret":
			var f := new_foe("turret", Models.turret())
			f.ground = true
			var sx := x * 1.25 + (i - (n - 1) * 0.5) * 4.0
			f.pos = Vector3(clampf(sx, -7.0, 7.0), ground_y(sx, top - 3.0), top - 3.0)
			f.fire_t = 1.5 + 0.4 * i
		"heavy":
			var f := new_foe("heavy", Models.heavy())
			f.rel = true
			f.x0 = x * 1.25
			f.pos = Vector3(f.x0, Rules.PY, top - 2.0)
			f.fire_t = 2.0
		"boss":
			var f := new_foe("boss", Models.boss())
			f.rel = true
			f.pos = Vector3(0, Rules.PY, top - 5.0)
			f.fire_t = 3.0
			boss = f
			say("WARNING", "Bastion-class battleship")


func ground_y(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) + 0.35 * sin(x * 0.05 + z * 0.01)
	return maxf(0.0, minf(h, 0.8) * 1.6)


func fire_vert(dt: float) -> void:
	fire_cd -= dt
	var gun := Rules.cannon(Rules.level(s, "cannon"))
	if fire_cd <= 0.0:
		fire_cd += gun.period
		for sh: Array in gun.shots:
			var a := deg_to_rad(sh[1])
			var o := new_shot(ppos + Vector3(sh[0], 0, -0.9), Vector3(sin(a), 0, -cos(a)) * 46.0, gun.dmg)
			o.rel = true
	fire_missiles(dt)


func new_shot(at: Vector3, v: Vector3, dmg: float, missile := false) -> Obj:
	var o := Obj.new()
	o.kind = "missile" if missile else "shot"
	o.pos = at
	o.vel = v
	o.dmg = dmg
	o.r = 0.3 if missile else 0.22
	o.node = Models.instance(Models.shot_mesh(0.12 if missile else 0.1),
		Models.glow(Models.AMBER if missile else Color8(0x9c, 0xf6, 0xff)))
	o.node.scale = Vector3(1, 1, 2.2 if missile else 3.2)
	add_child(o.node)
	o.node.position = at
	shots.append(o)
	return o


func fire_missiles(dt: float) -> void:
	var lv := Rules.level(s, "missile")
	var period := Rules.missile_period(lv)
	if period <= 0.0:
		return
	miss_cd -= dt
	if miss_cd > 0.0:
		return
	var targets := []
	for f in foes:
		if not f.dead and f.kind != "orb" and on_screen(f):
			targets.append(f)
	if targets.is_empty():
		miss_cd = 0.2
		return
	miss_cd = period
	targets.sort_custom(func(a: Obj, b: Obj) -> bool: return a.pos.distance_squared_to(ppos) < b.pos.distance_squared_to(ppos))
	for k in Rules.missile_count(lv):
		var side := -1.0 if k % 2 == 0 else 1.0
		var v := Vector3(side * 6.0, 0, -4.0) if pov_mode() == false else Vector3(side * 3.0, 2.0, -12.0)
		var m := new_shot(ppos + Vector3(side * 0.6, -0.1, 0.2), v, Rules.MISSILE_DMG, true)
		m.rel = not pov_mode()
		m.target = targets[mini(k, targets.size() - 1)]


func pov_mode() -> bool:
	return phase in ["pov", "core", "escape"]


func on_screen(f: Obj) -> bool:
	if pov_mode():
		var dz := ppos.z - f.pos.z
		return dz > 2.0 and dz < 45.0
	var z := f.pos.z - frame_z
	return z > Rules.Z_TOP - 0.5 and z < Rules.Z_BOT and absf(f.pos.x) < Rules.HALF_W + 1.0


# ---------------------------------------------------------------- foes and objects

func update_objs(dt: float) -> void:
	var dz := -Rules.SCROLL * dt if phase in ["vert", "down", "clear"] else 0.0
	for f in foes:
		f.t += dt
		f.flash = maxf(0.0, f.flash - dt)
		if f.rel:
			f.pos.z += dz
		think(f, dt)
	for o in shots:
		o.t += dt
		if o.rel:
			o.pos.z += dz
		if o.kind == "missile":
			steer_missile(o, dt)
		o.pos += o.vel * dt
	for b in bullets:
		b.t += dt
		if b.rel:
			b.pos.z += dz
		b.pos += b.vel * dt
	for p in picks:
		p.t += dt
		if p.rel:
			p.pos.z += dz
		var to := ppos - p.pos
		to.y = 0
		if phase in ["vert", "clear"] and to.length() < Rules.magnet_radius(s):
			p.pos += to.normalized() * minf(to.length(), 16.0 * dt)
		else:
			p.vel = p.vel.lerp(Vector3(0, 0, 2.5), minf(1.0, dt * 2.5))
			p.pos += p.vel * dt
	collide(dt)
	# cull
	for list: Array in [foes, shots, bullets, picks]:
		for i in range(list.size() - 1, -1, -1):
			var o: Obj = list[i]
			if o.dead or gone(o):
				if o.node:
					o.node.queue_free()
				list.remove_at(i)
	# place nodes
	for f in foes:
		f.node.position = f.pos
		var sc := 1.0 + f.flash * 0.6
		f.node.scale = Vector3(sc, sc, sc) * f.size
	for o in shots:
		o.node.position = o.pos
		if o.vel.length() > 0.1:
			o.node.look_at(o.pos + o.vel, Vector3.UP if absf(o.vel.normalized().y) < 0.95 else Vector3.FORWARD)
	for b in bullets:
		b.node.position = b.pos
		var pulse := 1.0 + 0.2 * sin(b.t * 18.0)
		b.node.scale = Vector3(pulse, pulse, pulse)
	for p in picks:
		p.node.position = p.pos + Vector3(0, 0.3 * sin(p.t * 5.0), 0)
		p.node.rotation.y = p.t * 3.0


func gone(o: Obj) -> bool:
	if pov_mode():
		return o.pos.z > ppos.z + 4.0 or o.pos.z < ppos.z - 90.0 or o.t > 8.0 and o.kind in ["shot", "missile", "orb"]
	var z := o.pos.z - frame_z
	if o in foes and (o.kind in ["drone", "sentry", "orb", "panel", "core"]):
		return phase in ["exit", "vert"]
	if o.kind == "shot" or o.kind == "missile":
		return z < Rules.Z_TOP - 4.0 or absf(o.pos.x) > Rules.HALF_W + 4.0 or o.t > 3.0
	return z > Rules.Z_BOT + 3.0 or z < Rules.Z_TOP - 30.0 or absf(o.pos.x) > Rules.HALF_W + 8.0


## Each foe's movement and fire.
func think(f: Obj, dt: float) -> void:
	var to_p := ppos - f.pos
	match f.kind:
		"dart":
			f.pos.z += 9.0 * dt
			if f.t < 1.3:
				f.pos.x += clampf(ppos.x - f.pos.x, -1.0, 1.0) * 2.2 * dt
			f.node.rotation = Vector3(0, 0, clampf(-(ppos.x - f.pos.x) * 0.15, -0.5, 0.5) if f.t < 1.3 else 0.0)
			if f.t >= f.fire_t and f.fire_t > 0:
				f.fire_t = -1.0
				aimed(f.pos, 10.0)
		"swing":
			f.pos.z += 5.0 * dt
			var nx := f.x0 + sin(f.t * 2.0 + f.idx * 0.7) * 4.0
			f.node.rotation = Vector3(0, 0, clampf((nx - f.pos.x) / dt * -0.08, -0.7, 0.7))
			f.pos.x = nx
			if f.t >= f.fire_t:
				f.fire_t += 2.2
				aimed(f.pos, 9.5)
		"turret":
			var z := f.pos.z - frame_z
			f.node.rotation.y = atan2(to_p.x, to_p.z)
			if f.t >= f.fire_t and z > Rules.Z_TOP and z < Rules.Z_BOT - 4.0:
				f.fire_t += 2.4
				for k in 3:
					var at := Vector3(f.pos.x, Rules.PY, f.pos.z)
					var dir := Vector3(to_p.x, 0, to_p.z).normalized().rotated(Vector3.UP, (k - 1) * 0.12)
					bullet(at, dir * 9.5)
		"heavy":
			var z := f.pos.z - frame_z
			if f.t < 2.2:
				f.pos.z += (Rules.Z_TOP + 5.0 + frame_z - f.pos.z) * minf(1.0, dt * 2.0)
			elif f.t < 10.0:
				f.pos.x = lerpf(f.pos.x, f.x0 + sin(f.t * 0.7) * 2.0, minf(1.0, dt * 2.0))
				if f.t >= f.fire_t:
					f.fire_t += 1.5
					fan(f.pos + Vector3(0, 0, 1.2), 5, 0.9, 8.5)
			else:
				f.pos.z += 6.0 * dt
			if z < Rules.Z_TOP - 1.0 and f.t < 1.0:
				pass
		"boss":
			think_boss(f, dt)
		"drone":
			var dist := ppos.z - f.pos.z
			var keep := 14.0 + f.idx * 2.5
			var vz := -rail_speed()
			if f.t < 9.0:
				vz += (dist - keep) * 1.6
				f.pos.x = lerpf(f.pos.x, f.x0 + sin(f.t * 1.6 + f.idx) * 1.8, minf(1.0, dt * 2.0))
				f.pos.y = lerpf(f.pos.y, f.size_y + cos(f.t * 1.3 + f.idx * 2.0) * 1.6, minf(1.0, dt * 2.0))
				if f.t >= f.fire_t and dist < 40.0:
					f.fire_t += 1.9
					orb(f.pos + Vector3(0, 0, 0.6), 12.0)
			else:
				vz = -rail_speed() - 30.0
			f.pos.z += vz * dt
			f.pos.x = clampf(f.pos.x, -Rules.POV_REACH.x - 1.0, Rules.POV_REACH.x + 1.0)
			f.node.look_at(ppos, Vector3.UP, true)
			f.node.rotate_object_local(Vector3.FORWARD, f.t * 2.0)
		"sentry":
			f.pos = f.anchor + Vector3(0, 0, stern_z)
			var dist := ppos.z - f.pos.z
			f.node.look_at(ppos, Vector3.UP, true)
			if f.t >= f.fire_t and dist > 6.0 and dist < 45.0:
				f.fire_t += 1.6
				orb(f.pos + to_p.normalized() * 1.0, 11.0)
		"orb":
			f.node.rotation = Vector3(f.t * 4, f.t * 3, 0)
		"panel":
			if core:
				var a := f.t * 0.9 + f.idx * TAU / 4.0
				f.pos = core.pos + Vector3(cos(a) * 2.7, sin(a) * 2.7, 1.4)
				f.node.rotation = Vector3(PI / 2, 0, a)
				if f.t >= f.fire_t and phase == "core":
					f.fire_t += 2.6
					orb(f.pos + Vector3(0, 0, 0.6), 10.0)
		"core":
			f.pos = f.anchor + Vector3(0, 0, stern_z)
			f.node.rotation = Vector3(f.t * 0.7, f.t * 1.1, 0)
			if phase == "core" and f.t >= f.fire_t:
				var open := shielded() == false
				f.fire_t = f.t + (1.4 if open else 2.4)
				var n := 10 if open else 6
				for k in n:
					var a := TAU * k / n + f.t
					var at := f.pos + Vector3(cos(a), sin(a), 0) * 1.6
					var dir := (ppos + Vector3(cos(a), sin(a), 0) * 2.2 - at).normalized()
					var o := orb(at, 0.0)
					o.vel = dir * 10.0 - Vector3(0, 0, rail_speed())


func think_boss(f: Obj, dt: float) -> void:
	var frac := f.hp / f.max_hp
	if f.t < 3.0:
		f.pos.z += (frame_z + Rules.Z_TOP + 5.5 - f.pos.z) * minf(1.0, dt * 1.5)
		return
	f.pos.x = lerpf(f.pos.x, sin((f.t - 3.0) * 0.45) * 4.0, minf(1.0, dt * 2.0))
	f.pos.z = lerpf(f.pos.z, frame_z + Rules.Z_TOP + 5.5 + sin(f.t * 0.6) * 0.8, minf(1.0, dt * 2.0))
	if f.t < f.fire_t:
		return
	if frac > 0.66:
		f.fire_t = f.t + 1.1
		for sx in [-3.3, 3.3]:
			aimed(f.pos + Vector3(sx, 0, 0.6), 10.5)
		fan(f.pos + Vector3(0, 0, 3.0), 3, 0.35, 12.0)
	elif frac > 0.33:
		f.fire_t = f.t + 1.5
		fan(f.pos + Vector3(0, 0, 3.0), 11, 2.2, 8.5)
		aimed(f.pos + Vector3(-3.3, 0, 0.6), 11.5)
		aimed(f.pos + Vector3(3.3, 0, 0.6), 11.5)
	else:
		f.fire_t = f.t + 0.09
		var a := f.t * 2.6
		for k in 2:
			var ang := a + PI * k
			bullet(f.pos + Vector3(0, 0, 0.5), Vector3(sin(ang), 0, cos(ang)) * 7.5)


func rail_speed() -> float:
	return Rules.RAIL if pov_mode() else 0.0


func shielded() -> bool:
	for f in foes:
		if f.kind == "panel" and not f.dead:
			return true
	return false


func bullet(at: Vector3, v: Vector3) -> Obj:
	var b := Obj.new()
	b.kind = "bullet"
	b.pos = at
	b.vel = v
	b.rel = true
	b.r = 0.26
	b.node = Models.instance(Models.shot_mesh(0.26), Models.glow(Color8(0xff, 0x4d, 0x8d)))
	var core_dot := Models.instance(Models.shot_mesh(0.13), Models.glow(Color8(0xff, 0xe8, 0xf0)))
	core_dot.position.y = 0.15
	b.node.add_child(core_dot)
	add_child(b.node)
	b.node.position = at
	bullets.append(b)
	return b


func aimed(at: Vector3, speed: float) -> void:
	var d := Vector3(ppos.x - at.x, 0, ppos.z - at.z)
	if d.length() < 0.1:
		d = Vector3(0, 0, 1)
	bullet(Vector3(at.x, Rules.PY, at.z), d.normalized() * speed)


func fan(at: Vector3, n: int, spread: float, speed: float) -> void:
	var d := Vector3(ppos.x - at.x, 0, ppos.z - at.z).normalized()
	for k in n:
		var a := (k - (n - 1) * 0.5) * spread / maxf(1.0, n - 1)
		bullet(Vector3(at.x, Rules.PY, at.z), d.rotated(Vector3.UP, a) * speed)


## A shootable energy orb inside the carrier, aimed where the ship is.
func orb(at: Vector3, speed: float) -> Obj:
	var o := Obj.new()
	o.kind = "orb"
	o.hp = 1.0
	o.max_hp = 1.0
	o.r = Rules.FOES.orb.r
	o.pos = at
	# fired from things that fly with the ship: aimed in that moving frame
	o.vel = (ppos - at).normalized() * speed - Vector3(0, 0, rail_speed())
	o.node = Models.instance(Models.shot_mesh(0.35), Models.glow(Color8(0xff, 0x4d, 0x8d)))
	var dot := Models.instance(Models.shot_mesh(0.18), Models.glow(Color8(0xff, 0xf0, 0xf4)))
	o.node.add_child(dot)
	add_child(o.node)
	foes.append(o)
	return o


func steer_missile(m: Obj, dt: float) -> void:
	if m.target == null or m.target.dead or not m.target in foes:
		m.target = null
		var best := 1e9
		for f in foes:
			if f.dead or f.kind == "orb" or not on_screen(f):
				continue
			var d := f.pos.distance_squared_to(m.pos)
			if d < best:
				best = d
				m.target = f
	var speed := 26.0 if not pov_mode() else 45.0
	var want := m.vel.normalized() * speed
	if m.target:
		want = (m.target.pos - m.pos).normalized() * speed
	if not pov_mode():
		want.y = 0
	m.vel = m.vel.lerp(want, minf(1.0, dt * 5.0))


func collide(_dt: float) -> void:
	var pov := pov_mode()
	# player shots vs foes
	for o in shots:
		if o.dead:
			continue
		for f in foes:
			if f.dead:
				continue
			var hit := false
			if pov:
				hit = seg_dist(o.pos - o.vel * _dt, o.pos, f.pos) < f.r + o.r
			else:
				hit = flat_dist(o.pos, f.pos) < f.r + o.r and on_screen(f)
			if hit:
				o.dead = true
				damage(f, o.dmg)
				break
	if phase not in ["vert", "approach", "pov", "core", "escape", "exit"]:
		return
	# foes' fire and bodies vs the player
	for b in bullets:
		if not b.dead and flat_dist(b.pos, ppos) < b.r + Rules.PLAYER_R and not pov:
			b.dead = true
			hurt()
	for f in foes:
		if f.dead or f.ground:
			continue
		if pov:
			if f.kind == "orb" and f.pos.distance_to(ppos) < f.r + Rules.PLAYER_R + 0.2:
				f.dead = true
				pop(f.pos, 0.6, Color8(0xff, 0x4d, 0x8d))
				hurt()
		elif f.kind not in ["orb", "panel", "core", "drone", "sentry"] and flat_dist(f.pos, ppos) < f.r * 0.7 + Rules.PLAYER_R:
			damage(f, 6.0)
			hurt()
	# pickups
	for p in picks:
		if not p.dead and flat_dist(p.pos, ppos) < Rules.PICK_R:
			p.dead = true
			run.scrap += int(p.dmg)
			hud.ping_scrap()


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func damage(f: Obj, d: float) -> void:
	if f.kind == "core" and shielded():
		f.flash = 0.05
		pop(f.pos + Vector3(0, 0, 1.6), 0.4, Models.CYAN)
		return
	f.hp -= d
	f.flash = 0.08
	if f.hp <= 0.0:
		kill(f)


func kill(f: Obj) -> void:
	f.dead = true
	var info: Dictionary = Rules.FOES[f.kind]
	run.score += int(info.score)
	if f.kind != "orb":
		run.kills += 1
	var big: float = {"heavy": 2.6, "boss": 5.0, "core": 4.0, "panel": 1.6}.get(f.kind, 1.3)
	pop(f.pos, big, Models.AMBER)
	if f.kind == "orb":
		return
	shake = maxf(shake, 0.12 * big)
	var scrap := int(info.scrap)
	if pov_mode():
		run.scrap += scrap
		if scrap > 0:
			hud.ping_scrap()
	else:
		var n := clampi(scrap / 5, 1, 14)
		for k in n:
			drop(f.pos, float(scrap) / n)
	if f == boss:
		boss = null
		for o in foes:
			if not o.dead and o != f:
				o.dead = true
				pop(o.pos, 1.2, Models.AMBER)
		for b in bullets:
			b.dead = true
		phase = "clear"
		phase_t = 0.0
		say("SECTOR CLEAR", "", 3.0)
	if f == core:
		begin_escape()


func drop(at: Vector3, value: float) -> void:
	var p := Obj.new()
	p.kind = "scrap"
	p.rel = true
	p.dmg = value
	p.pos = Vector3(at.x, Rules.PY, at.z)
	p.vel = Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 3))
	var big := value >= 15.0
	p.node = Models.instance(Models.cached("scrap%s" % big, func() -> Mesh:
		var b := Models.Builder.new()
		b.octa(Vector3.ZERO, 0.42 if big else 0.28, Color8(0xff, 0xd2, 0x4a), Vector3(1, 1.4, 1))
		return b.commit()), Models.glow(Color8(0xff, 0xd8, 0x5a)))
	add_child(p.node)
	picks.append(p)


func hurt() -> void:
	if inv > 0.0 or phase not in ["vert", "approach", "pov", "core", "escape", "exit"]:
		return
	hp -= 1
	run.hits += 1
	inv = 1.6
	shake = 0.5
	hud.flash_hurt()
	if hp <= 0:
		pop(ppos, 3.0, Models.AMBER)
		ship.visible = false
		var was_pov := pov_mode()
		phase = "down"
		phase_t = 0.0
		say("SHOT DOWN", "", 2.0)
		if was_pov:
			set_cam("top", 1.5)


# ---------------------------------------------------------------- effects

func pop(at: Vector3, size: float, col: Color) -> void:
	var o := Obj.new()
	o.kind = "flash"
	o.pos = at
	o.size = size
	o.life = 0.45 + size * 0.06
	o.node = Models.instance(Models.shot_mesh(0.5), Models.glow(col.lightened(0.3), 0.9))
	add_child(o.node)
	o.node.position = at
	fx.append(o)
	for k in int(clampf(size * 3.0, 3, 14)):
		var d := Obj.new()
		d.kind = "debris"
		d.pos = at
		d.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(3, 7) * sqrt(size)
		d.life = rng.randf_range(0.4, 0.8)
		d.size = rng.randf_range(0.12, 0.28) * sqrt(size)
		d.node = Models.instance(Models.cached("debris", func() -> Mesh:
			var b := Models.Builder.new()
			b.box(Vector3.ZERO, Vector3.ONE, Color.WHITE)
			return b.commit()), Models.glow(col if k % 2 == 0 else Color8(0x40, 0x3a, 0x3a)))
		add_child(d.node)
		fx.append(d)


func update_fx(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 1.2)
	for i in range(fx.size() - 1, -1, -1):
		var o := fx[i]
		o.t += dt
		var k := o.t / o.life
		if k >= 1.0:
			o.node.queue_free()
			fx.remove_at(i)
			continue
		if o.kind == "flash":
			var sc := o.size * (0.3 + 1.2 * sqrt(k))
			o.node.scale = Vector3(sc, sc, sc)
			o.node.transparency = k
		else:
			o.vel *= 1.0 - dt * 2.0
			o.pos += o.vel * dt
			o.node.position = o.pos
			o.node.scale = Vector3.ONE * o.size * (1.0 - k)
			o.node.rotation += Vector3(dt * 7, dt * 5, 0)


func update_ship(dt: float) -> void:
	ship.position = ppos
	var tb := 0.0
	if phase == "vert" or phase == "exit":
		tb = clampf(-pvel.x * 0.05, -0.7, 0.7)
	elif pov_mode():
		tb = clampf(-pvel.x * 0.09, -0.8, 0.8)
	bank = lerpf(bank, tb, minf(1.0, dt * 8.0))
	var pitch := clampf(pvel.y * 0.05, -0.3, 0.3) if pov_mode() else 0.0
	ship.rotation = Vector3(pitch, 0, bank)
	ship_mesh.visible = inv <= 0.0 or fmod(inv, 0.16) > 0.08
	engine_glow.scale = Vector3(1.6, 1, 2.6 + sin(phase_t * 40.0) * 0.6)


func update_chunks() -> void:
	var first := int(floor((-frame_z - 30.0) / CHUNK))
	var want := {}
	for k in range(first, first + 5):
		want[k] = true
		if not chunks.has(k):
			var mi := Models.instance(Models.ground_chunk(noise, -k * CHUNK, Vector2(CHUNK_W, CHUNK), 2.0))
			add_child(mi)
			chunks[k] = mi
	for k in chunks.keys():
		if not want.has(k):
			chunks[k].queue_free()
			chunks.erase(k)


# ---------------------------------------------------------------- the carrier episode

func spawn_carrier() -> void:
	carrier = Node3D.new()
	stern_z = frame_z + Rules.Z_TOP - 3.0 - Rules.SCROLL * 3.0
	carrier.position = Vector3(0, 0, stern_z)
	carrier.add_child(Models.instance(Models.carrier()))
	carrier.add_child(Models.instance(Models.carrier_lights(), Models.glow(Color8(0xc8, 0xf4, 0xff))))
	add_child(carrier)
	say("CARRIER AHEAD", "Get on its tail")


## The swoop behind the ship: the vertical stage freezes, the ship drops in behind the
## carrier, and the camera comes down to a chase view. Everything stays outside.
func begin_approach() -> void:
	phase = "approach"
	phase_t = 0.0
	approach_from = ppos
	approach_stern = stern_z
	for f in foes:
		if not f.dead:
			f.dead = true
			pop(f.pos, 1.0, Models.AMBER)
	for b in bullets:
		b.dead = true
	queue.clear()
	set_cam("chase", 2.2)
	say("INTERCEPT", "Bring the carrier down")


func step_approach(dt: float) -> void:
	frame_z -= Rules.SCROLL * maxf(0.0, 1.0 - phase_t / 1.2) * dt
	var k := clampf(phase_t / Rules.APPROACH, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	# the carrier speeds up to the rail speed while the ship falls in behind it
	stern_z = approach_stern - Rules.RAIL * Rules.APPROACH * 0.5 * k * k
	var tail := Vector3(0, Rules.PY, stern_z + Rules.GAP_FAR)
	var side := smoothstep(0.0, 1.0, minf(1.0, k * 1.6))
	ppos = Vector3(lerpf(approach_from.x, tail.x, side), Rules.PY, lerpf(approach_from.z, tail.z, e))
	pvel = Vector2((tail.x - approach_from.x) * (1.0 - side), 0)
	carrier.position.z = stern_z
	if k >= 1.0:
		begin_pov()


func begin_pov() -> void:
	phase = "pov"
	phase_t = 0.0
	rail_s = 0.0
	rail_z = ppos.z
	sentry_n = 0
	pov_i = 0
	off = Vector2.ZERO
	hud.show_play()


## The chase, on rails: ship and carrier fly forward at `Rules.RAIL`; the drag moves the ship
## in the plane facing the carrier (that's how you dodge), the guns fire straight ahead with
## a little aim assist.
func step_pov(dt: float) -> void:
	var v := rail_speed()
	rail_s += v * dt
	if phase == "pov" and rail_s >= Rules.RAIL_STOP:
		phase = "core"
		phase_t = 0.0
		say("REACTOR", "Break its shield panels")
	off.x = clampf(off.x, -Rules.POV_REACH.x, Rules.POV_REACH.x)
	off.y = clampf(off.y, -Rules.POV_DOWN, Rules.POV_REACH.y)
	var before := Vector2(ppos.x, ppos.y)
	var cur := before.lerp(Vector2(off.x, Rules.PY + off.y), minf(1.0, dt * 10.0))
	pvel = (cur - before) / maxf(dt, 0.001)
	ppos = Vector3(cur.x, cur.y, rail_z - rail_s)
	frame_z = ppos.z - 6.0
	if carrier:
		var gap := Rules.GAP_NEAR if phase == "core" else Rules.GAP_FAR
		var want := ppos.z - gap
		stern_z = lerpf(stern_z, want, minf(1.0, dt * 0.6)) - v * dt
		carrier.position.z = stern_z
		carrier.position.y = sin(phase_t * 0.7) * 0.3
	aim = cam.unproject_position(ppos + Vector3(0, 0.2, -Rules.AIM_AHEAD)) if not cam.is_position_behind(ppos + Vector3(0, 0, -30)) else view_size() * 0.5
	if phase == "escape":
		if carrier and fmod(phase_t, 0.12) < dt:
			pop(Vector3(rng.randf_range(-9, 9), Rules.PY + rng.randf_range(0, 5), stern_z - rng.randf_range(0, 60)), 4.0, Models.AMBER)
			shake = 0.35
		if carrier and phase_t > 1.3:
			carrier.queue_free()
			carrier = null
			pop(Vector3(0, Rules.PY + 2.0, stern_z - 10.0), 10.0, Models.AMBER)
			shake = 1.0
		if phase_t > 2.0:
			begin_exit()
			return
	while pov_i < Rules.POV_WAVES.size() and rail_s >= Rules.POV_WAVES[pov_i].s:
		spawn_pov(Rules.POV_WAVES[pov_i])
		pov_i += 1
	fire_pov(dt)


func spawn_pov(w: Dictionary) -> void:
	for i in int(w.n):
		match w.kind:
			"drone":
				# launched from the carrier's hangar, they fall back towards the ship
				var f := new_foe("drone", Models.drone())
				f.idx = i
				f.x0 = (i - (w.n - 1) * 0.5) * 2.2
				f.size_y = Rules.PY + 1.0 + (i % 3) * 4.0
				f.pos = Vector3(rng.randf_range(-2, 2), Rules.PY + rng.randf_range(-1, 1), stern_z + 1.0)
				f.fire_t = 1.4 + i * 0.45
			"sentry":
				# gun turrets on the carrier's stern, either side of the hangar
				var f := new_foe("sentry", Models.sentry())
				var m: Vector2 = Rules.MOUNTS[(sentry_n * 5 + i * 3) % Rules.MOUNTS.size()]
				sentry_n += 1
				# flush with the stern face, the lower tower or the upper tower
				var fz := 0.9 if m.y < Rules.CARRIER_TOP else (-0.4 if m.y < 17.0 else -2.4)
				f.anchor = Vector3(m.x, m.y, fz)
				f.pos = f.anchor + Vector3(0, 0, stern_z)
				f.fire_t = 0.6 + i * 0.4
			"core":
				var c := new_foe("core", Models.shot_mesh(1.4))
				c.node.material_override = Models.glow(Color8(0xff, 0x7a, 0x3a))
				var ring := Models.instance(Models.cached("ring", func() -> Mesh:
					var b := Models.Builder.new()
					for k in 8:
						var a := TAU * k / 8.0
						b.box(Vector3(cos(a), sin(a), 0) * 1.9, Vector3(0.5, 0.5, 0.3), Models.FOE_D)
					return b.commit()))
				c.node.add_child(ring)
				c.anchor = Vector3(0, Rules.PY, 1.5)
				c.pos = c.anchor + Vector3(0, 0, stern_z)
				c.fire_t = 1.5
				core = c
				say("THE HANGAR OPENS", "Its reactor is exposed")
				for k in 4:
					var p := new_foe("panel", Models.panel())
					p.idx = k
					p.fire_t = 1.0 + k * 0.6
					p.pos = c.pos


func fire_pov(dt: float) -> void:
	fire_cd -= dt
	var gun := Rules.cannon(Rules.level(s, "cannon"))
	if fire_cd <= 0.0:
		fire_cd += gun.period
		var target := aim_point()
		for sh: Array in gun.shots:
			var from := ppos + Vector3(float(sh[0]), 0, -1.4)
			var dir := (target - from).normalized().rotated(Vector3.UP, -deg_to_rad(sh[1]) * 0.35)
			var o := new_shot(from, dir * 80.0 - Vector3(0, 0, rail_speed()), gun.dmg)
			o.node.scale = Vector3(0.8, 0.8, 6.0)
	fire_missiles(dt)


## Where the guns converge: straight ahead of the ship, or the foe closest to that line
## (aim assist).
func aim_point() -> Vector3:
	var o := ppos
	var d := Vector3.FORWARD
	var best := Rules.AIM_AHEAD * 1.5
	var at := o + d * Rules.AIM_AHEAD
	var best_miss := 1e9
	for f in foes:
		if f.dead or (f.kind == "core" and shielded()):
			continue
		var t := (f.pos - o).dot(d)
		if t < 4.0 or t > best:
			continue
		var miss := (o + d * t).distance_to(f.pos) - f.r
		if miss < Rules.AIM_ASSIST and miss < best_miss:
			best_miss = miss
			at = f.pos
	return at


func begin_escape() -> void:
	phase = "escape"
	phase_t = 0.0
	core = null
	for f in foes:
		if not f.dead:
			f.dead = true
			pop(f.pos, 1.0, Models.AMBER)
	shake = 0.8
	say("REACTOR DOWN", "The carrier is going down")


## Back to the vertical stage: the camera climbs back up over the ship.
func begin_exit() -> void:
	phase = "exit"
	phase_t = 0.0
	prel = Vector2(clampf(ppos.x, -Rules.HALF_W, Rules.HALF_W), 4.0)
	frame_z = ppos.z - prel.y
	for f in foes:
		f.dead = true
	if carrier:
		carrier.queue_free()
		carrier = null
	set_cam("top", 1.8)
	hud.show_play()


func step_exit(dt: float) -> void:
	frame_z -= Rules.SCROLL * smoothstep(0.0, 1.8, phase_t) * dt
	var before := prel
	prel.y = lerpf(prel.y, 6.0, minf(1.0, dt * 1.5))
	clamp_player()
	ppos = Vector3(prel.x, lerpf(ppos.y, Rules.PY, minf(1.0, dt * 3.0)), frame_z + prel.y)
	pvel = (prel - before) / maxf(dt, 0.001)
	fire_vert(dt)
	if phase_t >= 1.9:
		phase = "vert"
		phase_t = 0.0
		carrier_done = true
		stage_t = 30.0
		run.score += 2000
		say("CARRIER DOWN", "+2,000")


# ---------------------------------------------------------------- camera

func pose(mode: String) -> Array:
	if mode == "chase":
		# behind and above the ship, following it partly so it moves on screen
		var at := Vector3(ppos.x * 0.55, Rules.PY + (ppos.y - Rules.PY) * 0.75 + 2.1, ppos.z + 6.8)
		var look := Vector3(ppos.x * 0.35, Rules.PY + (ppos.y - Rules.PY) * 0.6 + 0.6, ppos.z - 22.0)
		var xf := Transform3D(Basis(), at).looking_at(look, Vector3.UP)
		xf.basis = xf.basis.rotated(xf.basis.z, clampf(-pvel.x * 0.006, -0.08, 0.08))
		return [xf, 62.0]
	var top := Transform3D(Basis(), Vector3(0, TOP_H, frame_z + TOP_BACK))
	return [top.looking_at(Vector3(0, 0, frame_z - 1.0), Vector3.UP), TOP_FOV]


func set_cam(mode: String, dur: float) -> void:
	cam_from = cam.global_transform
	cam_from_fov = cam.fov
	cam_mode = mode
	cam_dur = dur
	cam_k = 0.0 if dur > 0.0 else 1.0
	if dur <= 0.0:
		var p := pose(mode)
		cam.global_transform = p[0]
		cam.fov = p[1]
		# world units per pixel on the flight plane at the screen's centre (drag is 1:1 there)
		var reach := Vector2(TOP_BACK + 1.0, TOP_H).length() * (TOP_H - Rules.PY) / TOP_H
		world_per_px = 2.0 * reach * tan(deg_to_rad(TOP_FOV * 0.5)) / maxf(1.0, view_size().x)


func update_cam(dt: float) -> void:
	var p := pose(cam_mode)
	var xf: Transform3D = p[0]
	var fov: float = p[1]
	if cam_k < 1.0:
		cam_k = minf(1.0, cam_k + dt / cam_dur)
		var k := smoothstep(0.0, 1.0, cam_k)
		xf = cam_from.interpolate_with(xf, k)
		fov = lerpf(cam_from_fov, fov, k)
	if shake > 0.0:
		xf.origin += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0) * shake * 0.4
	cam.global_transform = xf
	cam.fov = fov
	ship.visible = phase not in ["down", "results"]
