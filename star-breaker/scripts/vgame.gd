extends Node3D
## Star Breaker in portrait: the vertical slice. One thumb drags the ship (1:1 with the
## thumb's movement) and the main weapon fires on its own while the thumb is down; lifting the
## thumb triggers the ship's release (Lance: the charge beam, Warden: fling or recall the pod),
## and a second finger fires the ultimate once its gauge is full. World 1 is three stages.
##
## Logic runs at a fixed 60 ticks per second in stage units: a 126 x 224 playfield with y
## pointing UP (0 at the bottom). `X()` / `Y()` map stage units to 3D; the camera looks down
## -Z at the play plane, with the ground below it.

const W := 126.0
const H := 224.0
const SCROLL := 0.6
const CAM_D := 215.0
const GROUND_Z := -18.0
const CHUNK := 64.0
## Ticks of holding for each charge level of Lance's beam (LV 1-3, then the Nova at 4 s).
const CHARGE_AT := [0, 50, 100, 160, 240]
const CHARGE_MAX := 240
const BEAM_LIFE := [0, 14, 18, 24, 44]
const BEAM_DMG := [0, 4, 8, 14, 30]
const BEAM_W := [0, 2.0, 3.0, 4.2, 7.0]
## After a lift, time runs at this speed for SLOW_TICKS ticks, so the thumb can land again.
const SLOW := 0.4
const SLOW_TICKS := 24
## Without a thumb on the screen for this long, the game pauses itself (touch play only).
const AUTO_PAUSE := 180
const HULL := 3
const SHIPS := 3
const HITBOX := 2.0
## Invulnerable ticks after a hit, how close to rock counts as a touch, and the scrape zone
## just outside it that pays points for flying close.
const HIT_INV := 90
const ROCK_PAD := 3.0
const SCRAPE := 7.0
## [half width, half height, hit points, score]
const DEF := {drifter = [3, 3, 1, 100], shell = [10, 7, 26, 1500], turret = [4, 4, 3, 300], carrier = [5, 4, 5, 500],
	generator = [3.6, 3.6, 6, 500], block = [3.8, 3.8, 3, 50], matriarch = [14, 10, 90, 6000]}
const GROUND := ["turret", "generator", "block"]

var mode := "menu"      ## menu, play, pause, result
var paused := false
var G: Dictionary = {}
var P: Dictionary = {}
var pod: Dictionary = {}
var tt := 0
var shake := 0.0
var script_list: Array = []
var fx: Array = []
var chunks: Dictionary = {}
var _uid := 0
var _slow_acc := 0.0
var _flash_sky := 0

## Input, refreshed every frame from touch, mouse, keyboard and gamepad.
var inp := {hold = false, fire = false, dx = 0.0, dy = 0.0, ult = false, pause = false}
var _touch_id := -1
var _touch_seen := false
var _mouse_down := false
var _no_thumb := 0
var _pending := Vector2.ZERO
var _ult_latch := false
var _pause_latch := false
var _kb_pause_was := false
var _kb_ult_was := false
## Tools that drive the game off-screen turn this off (their window can lose focus).
var pause_on_focus_out := true
## Tests and tools set this to run the ticks themselves (with their own `inp`).
var driven := false

var world: Node3D
var camera: Camera3D
var hud: VHud
var audio: Sfx
var ship_m: Node3D
var pod_m: Node3D
var charge_fx: Node3D
var shield_m: Node3D
var stars: Array = []
## Floor tones (two) and the crater colour, from the world's palette.
var _ground_mats: Array = []
var _terrain_mats: Dictionary = {}
## The visible part of the play plane in stage units (see `_on_resize`).
var view := Rect2(-2.0, -2.0, W + 4.0, H + 4.0)
var _building: Dictionary = {}  ## chunk index -> Terrain.Builder being built ahead of time
var sun: DirectionalLight3D
var beam_light: OmniLight3D
var boom_lights: Array = []
var charge_ph := 0.0
## World 1's lighting and ground colours (sRGB).
const LOOK := {sun = "ffe6c8", amb = "5a50a0", fog = "140e2e", t_low = "1c1640", t_low2 = "2a1440", t_mid = "3a3070", t_high = "7a6cc0",
	t_cliff = "241e4c", t_rock = "463c7c", c_top = "463c88", c_top2 = "2e2862", c_face = "2c2560", river_a = "3ff0e0", river_b = "ff4fa3"}
var look: Dictionary = {}
var _lip_mat: Material = Models.std("b9a8ff", "8f6bff", 1.1)


# ---------- helpers ----------

static func X(x: float) -> float:
	return x - W / 2.0


static func Y(y: float) -> float:
	return y - H / 2.0


func uid() -> int:
	_uid += 1
	return _uid


static func fmt(n: float) -> String:
	var s := str(int(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func charge_lv(c: int) -> int:
	var lv := 0
	for i in range(1, CHARGE_AT.size()):
		if c >= CHARGE_AT[i]:
			lv = i
	return lv


## The rock walls' inner faces (x of left face, x of right face) at screen height `y`. Outside
## a canyon they are off screen.
func walls_at(y: float) -> Vector2:
	if G.is_empty():
		return Vector2(-1000.0, W + 1000.0)
	return VStage.walls(G.stage, G.scroll + y)


## True when a point (padded by `pad`) is inside the rock.
func in_rock(x: float, y: float, pad: float) -> bool:
	var w := walls_at(y)
	if x - pad < w.x or x + pad > w.y:
		return true
	return not G.is_empty() and VStage.on_island(G.stage, x, G.scroll + y, pad)


# ---------- setup ----------

func _ready() -> void:
	Diag.start()
	Models.init()
	# one 2048 shadow map covers the whole view (orthogonal sun); plenty for low poly shapes
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	_setup_world()
	audio = Sfx.new()
	add_child(audio)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = VHud.new()
	layer.add_child(hud)
	hud.stage_chosen.connect(start_stage)
	hud.resume_pressed.connect(func(): set_paused(false))
	hud.retry_pressed.connect(func(): start_stage(G.stage, G.ship))
	hud.next_pressed.connect(func(): start_stage(G.stage + 1, G.ship))
	hud.menu_pressed.connect(to_menu)
	hud.pause_pressed.connect(func(): _pause_latch = true)
	hud.mute_pressed.connect(func():
		muted = not muted
		audio.set_muted(muted)
		hud.set_muted(muted)
		_save())
	hud.safe_toggled.connect(apply_safe)
	hud.refresh_pressed.connect(refresh_game)
	_load()
	if Diag.crashed:
		hud.show_crash_notice(Diag.summary(), Diag.report())
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	apply_safe()
	_warm_up()
	_check_update()


# ---------- save, graphics, updates ----------

const SAVE_PATH := "user://save.cfg"
var muted := false
var bests: Array = [0, 0, 0]
var _env: Environment


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		muted = bool(cfg.get_value("game", "muted", false))
		var b = cfg.get_value("portrait", "bests", [])
		if b is Array:
			for i in mini(b.size(), bests.size()):
				bests[i] = int(b[i])
	audio.set_muted(muted)
	hud.set_muted(muted)
	hud.set_bests(bests)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("game", "muted", muted)
	cfg.set_value("portrait", "bests", bests)
	cfg.save(SAVE_PATH)


## Safe graphics (on after a crash, or from the menu): no glow and no MSAA.
func apply_safe() -> void:
	_env.glow_enabled = not Diag.safe
	sun.shadow_enabled = not Diag.safe
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if Diag.safe else Viewport.MSAA_2X


## Restarts the app so the launch-time update check loads the newest build (the page
## reloads in the browser). Tests swap `restart_fn` for a stub.
var restart_fn := func():
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit()


func refresh_game() -> void:
	if mode != "menu":
		return
	Diag.note("REFRESH")
	_save()
	hud.set_build_state("restarting")
	await get_tree().create_timer(0.15).timeout
	restart_fn.call()


## The build number from the running version ("b73 abc1234" -> 73), or 0.
static func build_number(version: String) -> int:
	var m := RegEx.create_from_string("^b(\\d+)").search(version)
	return int(m.get_string(1)) if m else 0


## Asks the update server whether a newer build is out and says so on the menu's build
## line. Quiet when offline or without an update url.
func _check_update() -> void:
	var url := str(ProjectSettings.get_setting("star_breaker/update_url", ""))
	if url == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 6.0
	add_child(http)
	if http.request(url + "update.json?t=%d" % int(Time.get_unix_time_from_system())) != OK:
		http.queue_free()
		return
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if d is Dictionary:
		show_update(int(d.get("build", 0)))


func show_update(remote: int) -> void:
	var have := build_number(str(ProjectSettings.get_setting("application/config/version", "")))
	if have > 0 and remote > have:
		hud.set_build_state("new", remote)


## Draws every model and material once behind the menu, so a first appearance in a stage
## doesn't hitch (shader compiles on Android).
func _warm_up() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 0, 200)
	w.scale = Vector3.ONE * 0.02
	add_child(w)
	var flashed := Models.drifter()
	var list: Array = [VShips.lance(), Models.ship(), Models.pod(), Models.drifter(), Models.turret(1), Models.shell(), flashed,
		Models.generator(1), Models.block(Models.M.rock), Models.carrier("L"), Models.item("L")]
	for k in Models.M:
		var mat = Models.M[k]
		if mat is Material:
			list.append(Models.mesh(Models.geo("pt", func(): return Geo.tetra(1)), mat))
	for mat in [_lip_mat, _terrain_mats.river, _terrain_mats.river_glow] + _ground_mats:
		list.append(Models.mesh(Models.geo("pt", func(): return Geo.tetra(1)), mat))
	for c in ["ffb547", "3ff0e0", "fff1d0", "ff4fa3", "ff9a40", "4a5470", "dfe9ff", "ffffff", "ff9a3d"]:
		list.append(Models.glow(c, 5))
	list.append_array(VFx.warm_list())
	list.append(VFx.charge_node())
	list.append(VFx.beam_node(4))
	for n in list:
		w.add_child(n)
	Models.set_flash(flashed, true)
	var bw := Node3D.new()
	w.add_child(bw)
	Models.set_flash(Models.boss(bw), true)
	for i in 4:
		await get_tree().process_frame
	w.queue_free()
	Diag.note("WARM", "%d objects" % (list.size() + 1))


func _setup_world() -> void:
	var pal: Dictionary = Worlds.LIST[0].pal
	look = LOOK.duplicate()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(pal.bg)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(look.amb)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.05
	env.glow_enabled = not Diag.safe
	env.glow_intensity = 0.9
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, 1.0 if i in [2, 3, 4, 5] else 0.0)
	# depth haze: the play plane stays crisp, the moon's floor sinks into violet
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(look.fog)
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_begin = CAM_D + 30.0
	env.fog_depth_end = CAM_D + 210.0
	env.fog_depth_curve = 1.4
	env.fog_sun_scatter = 0.0
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	camera = Camera3D.new()
	camera.near = 10.0
	camera.far = 900.0
	camera.position = Vector3(0, 0, CAM_D)
	add_child(camera)
	camera.current = true
	# a low, warm sun from the upper left: it lights the facets and throws every ship's and
	# enemy's shadow down onto the moon (the main cue for depth)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(look.sun)
	sun.light_energy = 1.35
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = CAM_D + 260.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.78
	add_child(sun)
	sun.look_at_from_position(Vector3(-70, 85, 150), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(pal.rim)
	rim.light_energy = 0.55
	rim.light_specular = 0.6
	add_child(rim)
	rim.look_at_from_position(Vector3(90, -80, 40), Vector3.ZERO)
	world = Node3D.new()
	add_child(world)
	_ground_mats = [Terrain.ground_mat(), Models.std(pal.far), Models.std(pal.bg)]
	_terrain_mats = {
		ground = _ground_mats[0],
		crystals = [Terrain.crystal_mat("6ff3e6", "2fd6c8", 0.9), Terrain.crystal_mat("ff7ac0", "ff2f8f", 0.85)],
		fissure_a = Models.basic("c0408a", 1.15), fissure_b = Models.basic("3fb8b0", 1.1),
		river = Terrain.river_mat(1.9, 1.3, look.river_a, look.river_b), river_glow = Terrain.river_mat(0.3, 2.5, look.river_a, look.river_b),
	}
	stars = [_star_layer(160, -200, -150, 1.6, Color(pal.star_a)), _star_layer(90, -150, -110, 2.0, Color(pal.star_b))]
	charge_fx = VFx.charge_node()
	charge_fx.visible = false
	world.add_child(charge_fx)
	# real light from the charge ball and the beam: it washes the ship and the moon below
	beam_light = OmniLight3D.new()
	beam_light.omni_range = 120.0
	beam_light.omni_attenuation = 1.3
	beam_light.light_energy = 0.0
	beam_light.visible = false
	world.add_child(beam_light)
	for i in 2:
		var l := OmniLight3D.new()
		l.omni_range = 90.0
		l.omni_attenuation = 1.6
		l.light_color = Color("ffb070")
		l.visible = false
		world.add_child(l)
		boom_lights.append({l = l, t = 0, e = 0.0})
	shield_m = Models.glow("3ff0e0", 26)
	shield_m.visible = false
	world.add_child(shield_m)


func _star_layer(n: int, z0: float, z1: float, sz: float, color: Color) -> Node3D:
	var q := QuadMesh.new()
	q.size = Vector2.ONE * sz
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	q.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(rng.randf_range(-260, 260), rng.randf_range(0, 600), rng.randf_range(z0, z1))))
	var grp := Node3D.new()
	for k in 2:
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.position.y = 600.0 * k
		grp.add_child(mi)
	add_child(grp)
	return grp


## Fits the 126 x 224 stage into the window: by width on a phone held upright, by height on
## a wider window (desktop, web), where the ground and stars fill the sides.
func _on_resize() -> void:
	var vp := get_viewport().get_visible_rect().size
	var hw := W / 2.0 + 2.0
	var hh := H / 2.0 + 2.0
	if vp.x / vp.y < W / H:
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = rad_to_deg(2.0 * atan(hw / CAM_D))
		hh = hw * vp.y / maxf(1.0, vp.x)
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = rad_to_deg(2.0 * atan(hh / CAM_D))
		hw = hh * vp.x / maxf(1.0, vp.y)
	# what the screen shows of the play plane, in stage units: shots and bullets fly on to the
	# real screen edge (a tall phone shows more than the 224-unit stage)
	view = Rect2(W / 2.0 - hw, H / 2.0 - hh, hw * 2.0, hh * 2.0)


## The top edge of what the screen shows, in stage units: a tall phone shows past the 224-unit
## stage, so things enter from here (off screen), never from the stage's own top.
func top() -> float:
	return maxf(H, view.end.y)


## Screen pixels per stage unit (canvas coordinates), for 1:1 dragging.
func px_per_unit() -> float:
	var vp := get_viewport().get_visible_rect().size
	return minf(vp.x / (W + 4.0), vp.y / (H + 4.0))


# ---------- input ----------

func _input(event: InputEvent) -> void:
	# on a phone each touch also arrives as a made-up mouse click (the menu's buttons need it),
	# ahead of the touch itself: steering ignores those, or the first one would leave the
	# mouse "held" for good and lifting the finger would never trigger the release
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		if not _touch_seen:
			_mouse_down = false
		_touch_seen = true
		var t := event as InputEventScreenTouch
		if t.pressed:
			if mode == "play" and hud.on_control(t.position):
				if hud.ult_rect.grow(12).has_point(t.position):
					_ult_latch = true
				return
			if _touch_id == -1:
				_touch_id = t.index
			elif t.index != _touch_id:
				_ult_latch = true
		elif t.index == _touch_id:
			_touch_id = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_id:
			_pending += d.relative
	elif event is InputEventMouseButton and not _touch_seen:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mode == "play" and hud.on_control(mb.position):
				if hud.ult_rect.grow(12).has_point(mb.position):
					_ult_latch = true
				return
			_mouse_down = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_ult_latch = true
	elif event is InputEventMouseMotion and not _touch_seen and _mouse_down:
		_pending += (event as InputEventMouseMotion).relative


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if mode == "play":
			_pause_latch = true
		elif mode == "pause":
			set_paused(false)
		elif mode == "result":
			to_menu()
		else:
			# back on the menu leaves the app
			Diag.note("QUIT")
			get_tree().quit()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		Diag.note("SUSPEND")
		_touch_id = -1
		_mouse_down = false
		if mode == "play" and pause_on_focus_out:
			set_paused(true)


## Folds touch, mouse, keyboard and gamepad into `inp` for one tick. Tests set `inp` directly
## and skip this.
func poll_input() -> void:
	var s := px_per_unit()
	inp.dx = _pending.x / s
	inp.dy = -_pending.y / s
	_pending = Vector2.ZERO
	var kx := float(Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A))
	var ky := float(Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S))
	var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var jy := -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if Vector2(jx, jy).length() > 0.25:
		kx = jx
		ky = jy
	inp.dx += kx * 1.8
	inp.dy += ky * 1.8
	var kb_hold := Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_K) or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	inp.hold = _touch_id != -1 or _mouse_down or kb_hold
	# on keyboard or gamepad the main weapon is always on
	inp.fire = inp.hold or not _touch_seen
	var kb_ult := Input.is_physical_key_pressed(KEY_X) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_Y)
	inp.ult = _ult_latch or (kb_ult and not _kb_ult_was)
	_kb_ult_was = kb_ult
	var kb_pause := Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_P) or Input.is_joy_button_pressed(0, JOY_BUTTON_START)
	inp.pause = _pause_latch or (kb_pause and not _kb_pause_was)
	_kb_pause_was = kb_pause
	_ult_latch = false
	_pause_latch = false


# ---------- flow ----------

func start_stage(i: int, kind: String) -> void:
	teardown()
	i = clampi(i, 0, VStage.STAGES.size() - 1)
	var sd: Dictionary = VStage.STAGES[i]
	Diag.note("VSTAGE", "%d %s" % [i, kind])
	G = {stage = i, ship = kind, scroll = 0.0, t = 0, si = 0, enemies = [], eb = [], pb = [], items = [], bars = [], beams = [],
		boss = {}, bparts = [], score = 0, lives = SHIPS, clear_t = 0, fail_t = 0, ended = false, ult_t = 0, shards = [], length = sd.length}
	P = {x = W / 2.0, y = -12.0, alive = true, entering = true, inv = 120, hull = HULL, laser = 0, fire_cd = 0, charge = 0, ready_lv = 0,
		held = false, ult = 0.0, vx = 0.0, respawn = 0, hit_t = 0, scrape = false}
	pod = {state = "dock", x = P.x, y = P.y + 10, ram_cd = 0, fire_cd = 0} if kind == "warden" else {}
	script_list = VStage.build(i)
	_build_islands()
	ship_m = VShips.upright(VShips.model(kind))
	ship_m.add_child(Models.glow("ff9a40", 8))
	world.add_child(ship_m)
	if kind == "warden":
		pod_m = VShips.upright(Models.pod())
		pod_m.add_child(Models.glow("3ff0e0", 9))
		world.add_child(pod_m)
	hud.ship = kind
	hud.stage_name = sd.name
	hud.boss = -1.0
	hud.banner(sd.name, sd.sub, 160)
	mode = "play"
	paused = false
	hud.show_screen("play")
	_no_thumb = 0
	audio.music("stage")


func teardown() -> void:
	for k in ["enemies", "eb", "pb", "items", "beams", "shards", "islands"]:
		for o in G.get(k, []):
			if is_instance_valid(o.get("m")):
				o.m.queue_free()
	for b in G.get("bars", []):
		for n in b.nodes:
			n.queue_free()
	if not G.get("boss", {}).is_empty():
		remove_boss()
	for f in fx:
		f.m.queue_free()
	fx = []
	for c in chunks.values():
		c.queue_free()
	chunks = {}
	_building = {}
	for n in [ship_m, pod_m]:
		if is_instance_valid(n):
			n.queue_free()
	ship_m = null
	pod_m = null
	charge_fx.visible = false
	shield_m.visible = false
	G = {}
	P = {}
	pod = {}


func to_menu() -> void:
	teardown()
	mode = "menu"
	paused = false
	audio.set_paused(false)
	audio.music("")
	hud.show_screen("menu")


func set_paused(v: bool) -> void:
	if mode != "play" and mode != "pause":
		return
	paused = v
	mode = "pause" if v else "play"
	audio.set_paused(v)
	hud.show_screen("pause" if v else "play")
	_no_thumb = 0


func finish(cleared: bool) -> void:
	mode = "result"
	audio.music("")
	if G.score > int(bests[G.stage]):
		bests[G.stage] = G.score
		hud.set_bests(bests)
		_save()
	hud.set_result(cleared, fmt(G.score), G.stage + 1 < VStage.STAGES.size())
	hud.show_screen("result")
	Diag.note("VSTAGE_END", "cleared=%s score=%d" % [cleared, G.score])


# ---------- the tick ----------

func update() -> void:
	tt += 1
	hud.tick_banner()
	if mode == "play" or mode == "pause":
		if inp.pause:
			set_paused(mode == "play")
	if mode != "play":
		return
	# after a lift, time slows briefly so the thumb can land again
	if G.get("slow", 0) > 0:
		G.slow -= 1
		_slow_acc += SLOW
		if _slow_acc < 1.0:
			_player_input_only()
			return
		_slow_acc -= 1.0
	step()


## During a slowed tick the world holds still but the ship still follows the thumb.
func _player_input_only() -> void:
	if P.alive and not P.entering:
		_move_player()


func step() -> void:
	G.t += 1
	if G.t % 60 == 0:
		Diag.note("TICK", "t=%d scroll=%d fps=%d enemies=%d eb=%d fx=%d" % [G.t, G.scroll, Engine.get_frames_per_second(), G.enemies.size(), G.eb.size(), fx.size()])
	if not G.ended:
		G.scroll += SCROLL
	while G.si < script_list.size() and script_list[G.si].d <= G.scroll + top() + 10:
		spawn(script_list[G.si])
		G.si += 1
	if _touch_seen and not inp.hold:
		_no_thumb += 1
		if _no_thumb >= AUTO_PAUSE:
			set_paused(true)
			return
	else:
		_no_thumb = 0
	_update_player()
	_update_pod()
	_update_shots()
	_update_beams()
	_update_enemies()
	_update_bars()
	if not G.boss.is_empty():
		update_boss()
	_update_eb()
	_update_items()
	_update_ult()
	update_fx()
	if G.clear_t > 0:
		G.clear_t += 1
		if G.clear_t > 170:
			finish(true)
	if G.fail_t > 0:
		G.fail_t += 1
		if G.fail_t > 110:
			finish(false)


func _move_player() -> void:
	P.x = clampf(P.x + inp.dx, 5, W - 5)
	P.y = clampf(P.y + inp.dy, 8, H - 30)
	P.vx = lerpf(P.vx, inp.dx, 0.3)


func _update_player() -> void:
	if not P.alive:
		P.respawn -= 1
		if P.respawn <= 0 and G.fail_t == 0:
			var rw := walls_at(40.0)
			P.merge({alive = true, entering = true, x = clampf(W / 2.0, rw.x + 8, rw.y - 8), y = -12.0, inv = 150, hull = HULL, charge = 0, ready_lv = 0, held = inp.hold}, true)
			if not pod.is_empty():
				pod.state = "dock"
		return
	if P.inv > 0:
		P.inv -= 1
	# Shatter shields the ship until the pod reforms
	if G.ult_t > 0 and G.ship == "warden":
		P.inv = maxi(P.inv, 2)
	if P.hit_t > 0:
		P.hit_t -= 1
	if P.entering:
		P.y += 1.4
		if P.y >= 40:
			P.entering = false
		P.held = inp.hold
		return
	if G.clear_t > 0:
		P.y += minf(4.0, 0.4 + G.clear_t * 0.03)
		P.inv = maxi(P.inv, 2)
		return
	_move_player()
	# main weapon: fires on its own while the thumb is down
	if P.fire_cd > 0:
		P.fire_cd -= 1
	if inp.fire and P.fire_cd <= 0:
		fire_main()
		P.fire_cd = VShips.KITS[G.ship].fire_every
	# the release: holding builds Lance's charge; lifting triggers the ship's move
	var kit: Dictionary = VShips.KITS[G.ship]
	if inp.hold:
		if kit.release == "beam":
			P.charge = mini(CHARGE_MAX, P.charge + 1)
			var lv := charge_lv(P.charge)
			if lv > P.ready_lv:
				P.ready_lv = lv
				audio.play("ready", lv)
	elif P.held:
		release()
		P.charge = 0
		P.ready_lv = 0
	P.held = inp.hold
	if inp.ult and P.ult >= 1.0 and G.ult_t == 0:
		ultimate()
	_rock_player()
	# touching an enemy or a barrier costs a hull point
	if P.inv <= 0:
		for e in G.enemies:
			if e.ground and e.type != "block":
				continue
			if absf(e.x - P.x) < e.hw + 2.0 and absf(e.y - P.y) < e.hh + 2.0:
				hurt()
				break
		if P.inv <= 0:
			for b in G.bars:
				if bar_solid(b, P.x, P.y, 2.5):
					hurt()
					P.y = maxf(8.0, b.y - 9.0)
					break


func release() -> void:
	var kit: Dictionary = VShips.KITS[G.ship]
	G.slow = SLOW_TICKS
	_slow_acc = 0.0
	if kit.release == "beam":
		var lv := charge_lv(P.charge)
		if lv > 0:
			fire_beam(lv)
	elif kit.release == "pod" and not pod.is_empty():
		if pod.state == "dock":
			pod.state = "out"
			pod.ty = minf(H - 30, P.y + 80)
			audio.play("pod")
		elif pod.state == "out":
			pod.state = "back"
			audio.play("pod")


func fire_main() -> void:
	var kit: Dictionary = VShips.KITS[G.ship]
	var sp: float = kit.shot_speed
	if G.ship == "lance":
		var xs := [[-2.4, 0.0], [2.4, 0.0]]
		if P.laser >= 1:
			xs.append([0.0, 0.0])
		if P.laser >= 2:
			xs.append_array([[-4.5, -0.6], [4.5, 0.6]])
		for o in xs:
			shot(P.x + o[0], P.y + 8, o[1], sp, Models.M.shot, 1)
	else:
		var n := 3 + 2 * mini(P.laser, 2)
		for j in n:
			var a := (j - (n - 1) / 2.0) * 0.16
			shot(P.x, P.y + 7, sin(a) * sp, cos(a) * sp, Models.M.pod_shot, 1)
	audio.play("rapid")


func shot(x: float, y: float, vx: float, vy: float, mat: Material, d: int) -> void:
	var m := VFx.bolt(mat, "ffb547" if mat == Models.M.pod_shot else "3ff0e0")
	m.rotation.z = atan2(-vx, vy)
	world.add_child(m)
	G.pb.append({x = x, y = y, vx = vx, vy = vy, d = d, m = m})


func fire_beam(lv: int) -> void:
	var b := {lv = lv, life = BEAM_LIFE[lv], x = P.x, y0 = P.y + 6, y1 = H, w = BEAM_W[lv], hit = {}, nova = lv == 4, ult = false}
	b.m = _beam_node(lv)
	world.add_child(b.m)
	G.beams.append(b)
	audio.play("beam", lv)
	shake = maxf(shake, 2.0 + lv)
	Diag.once("beam lv%d" % lv)


func _beam_node(lv: int) -> Node3D:
	return VFx.beam_node(lv)


func ultimate() -> void:
	P.ult = 0.0
	audio.play("ready", 4)
	shake = maxf(shake, 6.0)
	Diag.once("ult " + G.ship)
	if G.ship == "lance":
		# Starbreak: a full-height beam sweeps across the screen
		G.ult_t = 120
		var b := {lv = 4, life = 120, x = 6.0, y0 = view.position.y, y1 = view.end.y, w = 12.0, hit = {}, nova = true, ult = true}
		b.m = VFx.beam_node(4, true)
		world.add_child(b.m)
		G.beams.append(b)
		audio.play("beam", 4)
	else:
		# Shatter: the pod bursts into eight homing shards; the ship is shielded until it reforms
		G.ult_t = 180
		pod.state = "shatter"
		for j in 8:
			var a := TAU * j / 8.0
			var m := Models.mesh(Models.geo("vshard", func(): return Geo.octa(1.6)), Models.M.crystal_m)
			world.add_child(m)
			G.shards.append({x = pod.x, y = pod.y, vx = cos(a) * 2.5, vy = sin(a) * 2.5, m = m, cd = 0})


func _update_ult() -> void:
	if G.ult_t > 0:
		G.ult_t -= 1
		if G.ult_t == 0:
			for s in G.shards:
				s.m.queue_free()
			G.shards = []
			if pod.get("state", "") == "shatter":
				pod.state = "dock"
				pod.x = P.x
				pod.y = P.y + 10
	for s in G.shards:
		var tgt := _nearest_enemy(s.x, s.y)
		if not tgt.is_empty():
			var d := Vector2(tgt.x - s.x, tgt.y - s.y)
			var v := Vector2(s.vx, s.vy) + d.normalized() * 0.45
			v = v.limit_length(4.2)
			s.vx = v.x
			s.vy = v.y
		s.x += s.vx
		s.y += s.vy
		if s.cd > 0:
			s.cd -= 1
		elif not tgt.is_empty() and absf(tgt.x - s.x) < tgt.hw + 2 and absf(tgt.y - s.y) < tgt.hh + 2:
			_damage_target(tgt, 3)
			s.cd = 10
			spark(s.x, s.y)
		if s.x < -10 or s.x > W + 10 or s.y < -10 or s.y > H + 10:
			s.x = P.x
			s.y = P.y
	# burn bullets inside the Starbreak beam
	for b in G.beams:
		if b.ult:
			b.x = 6.0 + (W - 12.0) * (1.0 - float(b.life) / 120.0)


## The closest thing a homing shard can hit: an enemy or a boss part.
func _nearest_enemy(x: float, y: float) -> Dictionary:
	var best := {}
	var bd := 1e9
	for e in G.enemies:
		if e.y > H + 4 or e.y < -4:
			continue
		var d := Vector2(e.x - x, e.y - y).length_squared()
		if d < bd:
			bd = d
			best = {x = e.x, y = e.y, hw = e.hw, hh = e.hh, e = e}
	for p in G.bparts:
		if p.kind == "shield" or p.kind == "seg":
			continue
		var d := Vector2(p.x - x, p.y - y).length_squared()
		if d < bd:
			bd = d
			best = {x = p.x, y = p.y, hw = p.r, hh = p.r, part = p}
	return best


func _damage_target(t: Dictionary, d: int) -> void:
	if t.has("e"):
		dmg_e(t.e, d)
	elif t.has("part"):
		boss_damage(t.part, d)


func hurt() -> void:
	P.hull -= 1
	P.inv = HIT_INV
	P.hit_t = 20
	shake = maxf(shake, 6.0)
	audio.play("hit")
	if P.hull <= 0:
		kill_player()
	else:
		Diag.once("hull hit")


func kill_player() -> void:
	P.alive = false
	P.respawn = 90
	P.laser = 0
	G.lives -= 1
	boom(P.x, P.y, 12, true)
	audio.play("die")
	shake = 14.0
	charge_fx.visible = false
	if not pod.is_empty() and pod.state != "shatter":
		pod.state = "dock"
	if G.lives <= 0:
		G.fail_t = 1


# ---------- pod (Warden) ----------

func _update_pod() -> void:
	if pod.is_empty():
		return
	match pod.state:
		"dock":
			pod.x = P.x
			pod.y = P.y + 10
		"out":
			var pw := walls_at(pod.y)
			pod.x = lerpf(pod.x, clampf(pod.x, maxf(6, pw.x + 5), minf(W - 6, pw.y - 5)), 0.2)
			pod.y = minf(pod.ty, pod.y + 3.2)
		"back":
			var d := Vector2(P.x - pod.x, P.y + 10 - pod.y)
			if d.length() < 4.5:
				pod.state = "dock"
				audio.play("dock")
			else:
				var v := d.normalized() * 4.0
				pod.x += v.x
				pod.y += v.y
	if pod.state == "shatter" or not P.alive:
		return
	# the pod blocks bullets, rams enemies and fires straight up
	for b in G.eb:
		if Vector2(b.x - pod.x, b.y - pod.y).length() < 5.5:
			b.dead = true
			spark(b.x, b.y)
	if pod.ram_cd > 0:
		pod.ram_cd -= 1
	else:
		for e in G.enemies:
			if not e.ground and absf(e.x - pod.x) < e.hw + 4 and absf(e.y - pod.y) < e.hh + 4:
				dmg_e(e, 1)
				pod.ram_cd = 8
				break
		for p in G.bparts:
			if p.kind != "shield" and Vector2(p.x - pod.x, p.y - pod.y).length() < p.r + 4:
				boss_damage(p, 1)
				pod.ram_cd = 8
				break
	if pod.fire_cd > 0:
		pod.fire_cd -= 1
	elif inp.fire and P.alive:
		shot(pod.x, pod.y + 5, 0, 5.5, Models.M.shot, 2)
		pod.fire_cd = 10


# ---------- shots, beams, bullets ----------

func _update_shots() -> void:
	for b in G.pb:
		b.x += b.vx
		b.y += b.vy
		if b.y > view.end.y + 6 or b.x < view.position.x - 6 or b.x > view.end.x + 6:
			b.dead = true
			continue
		for bar in G.bars:
			if bar_solid(bar, b.x, b.y, 0.5):
				b.dead = true
				spark(b.x, b.y)
				break
		if b.get("dead", false):
			continue
		for e in G.enemies:
			if absf(e.x - b.x) < e.hw + 1.2 and absf(e.y - b.y) < e.hh + 2.5:
				dmg_e(e, b.d)
				b.dead = true
				break
		if b.get("dead", false):
			continue
		for p in G.bparts:
			if Vector2(p.x - b.x, p.y - b.y).length() < p.r + 1.0:
				b.dead = true
				if p.kind == "shield" or p.kind == "seg":
					spark(b.x, b.y)
					audio.play("tink")
				else:
					boss_damage(p, b.d)
				break
		# shots break on the rock walls (after hitting what sits on the cliff edge)
		if not b.get("dead", false) and in_rock(b.x, b.y, 0.0):
			b.dead = true
			spark(b.x, b.y)
	_sweep(G.pb)


func _update_beams() -> void:
	for b in G.beams:
		b.life -= 1
		if not b.ult and P.alive:
			b.x = P.x
			b.y0 = P.y + 6
		# the beam stops at the first barrier above the ship
		b.y1 = view.end.y + 4
		if not b.ult:
			for bar in G.bars:
				if bar.y > b.y0 and bar.y < b.y1 and bar_solid(bar, b.x, bar.y, 0.0):
					b.y1 = bar.y
		var hw: float = b.w / 2.0
		for e in G.enemies:
			if absf(e.x - b.x) < e.hw + hw and e.y > b.y0 - e.hh and e.y < b.y1 + e.hh:
				var key := "e%d" % e.id
				var every := 8 if b.ult else 1000000
				if not b.hit.has(key) or (b.ult and G.t - int(b.hit[key]) >= every):
					b.hit[key] = G.t
					dmg_e(e, 3 if b.ult else BEAM_DMG[b.lv])
		for p in G.bparts:
			if p.kind == "shield" or p.kind == "seg":
				continue
			if absf(p.x - b.x) < p.r + hw and p.y > b.y0 - p.r and p.y < b.y1 + p.r:
				var key := "p%d" % p.o.id
				var every2 := 8 if b.ult else 1000000
				if not b.hit.has(key) or (b.ult and G.t - int(b.hit[key]) >= every2):
					b.hit[key] = G.t
					boss_damage(p, 3 if b.ult else BEAM_DMG[b.lv])
		if b.nova:
			for eb in G.eb:
				if absf(eb.x - b.x) < hw + 2 and eb.y > b.y0 and eb.y < b.y1:
					eb.dead = true
		if b.life <= 0:
			b.dead = true
	_sweep(G.beams)


func bullet(x: float, y: float, vx: float, vy: float) -> void:
	var m := Models.mesh(Models.geo("bo", func(): return Geo.octa(0.5)), Models.M.ebullet)
	m.scale = Vector3.ONE * 2.2
	m.add_child(Models.glow("ff9a3d", 2.2))
	world.add_child(m)
	G.eb.append({x = x, y = y, vx = vx, vy = vy, m = m})


## Enemy bullets get faster stage by stage.
func bspeed() -> float:
	return 1.0 + 0.08 * G.stage


func aim(x: float, y: float, s: float) -> void:
	if not P.alive:
		return
	var d := Vector2(P.x - x, P.y - y).normalized() * s * bspeed()
	bullet(x, y, d.x, d.y)


func fan(x: float, y: float, s: float, n: int, spread: float) -> void:
	var base := Vector2(P.x - x, P.y - y).angle() if P.alive else -PI / 2
	for j in n:
		var a: float = base + (j - (n - 1) / 2.0) * spread
		bullet(x, y, cos(a) * s * bspeed(), sin(a) * s * bspeed())


func ring(x: float, y: float, n: int, s: float) -> void:
	for j in n:
		var a: float = TAU * j / n + G.t * 0.05
		bullet(x, y, cos(a) * s * bspeed(), sin(a) * s * bspeed())


func _update_eb() -> void:
	for b in G.eb:
		b.x += b.vx
		b.y += b.vy
		if b.x < view.position.x - 8 or b.x > view.end.x + 8 or b.y < view.position.y - 8 or b.y > view.end.y + 8 or in_rock(b.x, b.y, -1.0):
			b.dead = true
			continue
		if P.alive and P.inv <= 0 and Vector2(b.x - P.x, b.y - P.y).length() < HITBOX + 0.8:
			b.dead = true
			hurt()
	_sweep(G.eb)


func _sweep(list: Array) -> void:
	for i in range(list.size() - 1, -1, -1):
		var o: Dictionary = list[i]
		if o.get("dead", false):
			if is_instance_valid(o.get("m")):
				o.m.queue_free()
			list.remove_at(i)


# ---------- enemies ----------

func spawn(s: Dictionary) -> void:
	match s.type:
		"barrier":
			add_bar(s)
		"end":
			G.ended = true
			if s.kind == "bloom":
				spawn_boss()
			elif s.kind == "twins":
				E("shell", 36, top() + 20, {boss = true, hp = 60.0, hold = 160.0})
				E("shell", W - 36, top() + 30, {boss = true, hp = 60.0, hold = 175.0})
				hud.boss_name = "Shell Twins"
				_boss_warn()
			else:
				var e := E("shell", W / 2, top() + 24, {boss = true, hp = 110.0, hold = 165.0})
				e.m.scale = Vector3.ONE * 1.5
				e.hw *= 1.5
				e.hh *= 1.5
				hud.boss_name = "Shell Matriarch"
				_boss_warn()
		"turret", "generator":
			var tx: float = s.x
			# a gun in a canyon wall sits on the cliff edge, where shots can reach it
			var w := VStage.walls(G.stage, s.d)
			if tx < w.x:
				tx = w.x + 1.0
			elif tx > w.y:
				tx = w.y - 1.0
			E(s.type, tx, top() + 10, {wy = s.d, key = s.get("key", "")})
		"carrier":
			E("carrier", -8.0 if s.dir > 0 else W + 8.0, H - 34, {dir = s.dir, item = s.item})
		"drifter":
			var a: float = s.get("amp", 0.0)
			var dx := _fit(s.x, s.d, a + 6.0)
			E("drifter", dx, top() + 8, {move = s.move, amp = a, ph = s.get("ph", 0.0), x0 = dx, stop = s.get("stop", 170.0)})
		"shell":
			E("shell", _fit(s.x, s.d + 40, 12.0), top() + 14, {hold = 170.0})


## Moves a spawn x inside a canyon's passage at distance `d`, `pad` clear of the rock.
func _fit(x: float, d: float, pad: float) -> float:
	var w := VStage.walls(G.stage, d)
	if w.y - w.x < pad * 2.0:
		return (w.x + w.y) / 2.0
	return clampf(x, w.x + pad, w.y - pad)


func _boss_warn() -> void:
	audio.play("alarm")
	audio.music("boss")
	hud.banner("Warning", hud.boss_name + " approaching", 150)
	G.mid_boss = true


func E(type: String, x: float, y: float, o := {}) -> Dictionary:
	var d: Array = DEF[type]
	var e := {id = uid(), type = type, x = x, y = y, hw = d[0], hh = d[1], hp = float(d[2]), max = float(d[2]), score = d[3], t = 0, cd = 60, flash = 0,
		ground = type in GROUND}
	e.merge(o, true)
	e.max = e.hp
	var m: Node3D
	match type:
		"drifter":
			m = Models.drifter()
		"shell":
			m = Models.shell()
			m.rotation.z = -PI / 2
		"turret":
			m = Node3D.new()
			var tm := Models.turret(1)
			tm.rotation.x = -PI / 2
			m.add_child(tm)
			m.set_meta("aim", tm)
		"generator":
			m = Node3D.new()
			var gm := Models.generator(1)
			gm.rotation.x = -PI / 2
			m.add_child(gm)
		"carrier":
			m = Models.carrier(e.get("item", "L"))
			m.rotation.z = -PI / 2 if e.get("dir", 1.0) < 0 else PI / 2
		"block":
			m = Models.block(Models.M.rock)
	world.add_child(m)
	e.m = m
	G.enemies.append(e)
	Diag.once("venemy " + type)
	return e


func _update_enemies() -> void:
	for e in G.enemies:
		e.t += 1
		if e.flash > 0:
			e.flash -= 1
		if e.ground:
			e.y = e.wy - G.scroll if e.has("wy") else e.y - SCROLL
		match e.type:
			"drifter":
				if e.move == "sine":
					e.y -= 0.9
					e.x = clampf(e.x0 + sin(e.t * 0.04 + e.ph) * e.amp, 4, W - 4)
					if e.t % 150 == 90 and e.y > 80:
						aim(e.x, e.y, 1.1)
				else:
					# dive: drop in, hang, take aim, then dive at the ship
					if e.t < 200 and e.y > e.stop:
						e.y -= 1.4
					elif e.t < 200:
						if not e.has("aimed"):
							e.aimed = true
							aim(e.x, e.y, 1.2)
						e.t = maxi(e.t, 120)
					else:
						if not e.has("vx"):
							var v := Vector2(P.x - e.x, P.y - e.y).normalized() * 2.0 if P.alive else Vector2(0, -2)
							e.vx = v.x
							e.vy = minf(v.y, -0.8)
						e.x += e.vx
						e.y += e.vy
			"shell":
				if e.y > e.hold:
					e.y -= 0.8
				else:
					e.x += sin(e.t * 0.012) * 0.35
					e.cd -= 1
					if e.cd <= 0:
						fan(e.x, e.y - 6, 1.0, 5 if e.get("boss", false) else 3, 0.28)
						e.cd = 70 if e.get("boss", false) else 110
						if e.get("boss", false) and e.t % 4 == 0:
							ring(e.x, e.y, 10, 0.75)
					if not e.get("boss", false) and e.t > 720:
						e.y -= 1.2
			"turret":
				if e.y < H - 4 and e.y > 20:
					e.cd -= 1
					if e.cd <= 0:
						aim(e.x, e.y, 1.15)
						e.cd = 110
			"carrier":
				e.y = minf(e.y, H - 34)
				e.x += 0.7 * e.dir
				e.y -= 0.15
		if e.y < -20 or e.x < -30 or e.x > W + 30:
			e.dead = true
	for e in G.enemies:
		if e.get("dead", false) and not e.get("killed", false) and e.get("boss", false):
			e.dead = false
	_sweep(G.enemies)
	# a mid-boss stage ends when no boss enemy is left
	if G.get("mid_boss", false) and G.clear_t == 0:
		var left := false
		for e in G.enemies:
			if e.get("boss", false):
				left = true
		if not left:
			_stage_clear()


func dmg_e(e: Dictionary, d: int) -> void:
	if e.get("dead", false):
		return
	e.hp -= d
	e.flash = 3
	if e.hp <= 0:
		kill_e(e)
	else:
		audio.play("hit")


func kill_e(e: Dictionary) -> void:
	e.dead = true
	e.killed = true
	var big: bool = e.type == "shell"
	boom(e.x, e.y, 14 if big else 6, big)
	audio.play("boom" if big else "small")
	if big:
		shake = maxf(shake, 7.0)
	add_score(e.score)
	P.ult = minf(1.0, P.ult + (0.18 if big else 0.045))
	if e.type == "carrier":
		drop_item(e.x, e.y, e.get("item", "L"))
	if e.type == "generator":
		for b in G.bars:
			if b.key == e.key:
				b.locked = false
				audio.play("pick")


func add_score(n: int) -> void:
	G.score += n


func drop_item(x: float, y: float, k: String) -> void:
	var m := Models.item(k)
	world.add_child(m)
	G.items.append({x = x, y = y, k = k, m = m})


func _update_items() -> void:
	for it in G.items:
		it.y -= 0.5
		if it.y < -10:
			it.dead = true
		elif P.alive and Vector2(it.x - P.x, it.y - P.y).length() < 8:
			it.dead = true
			P.laser = mini(2, P.laser + 1)
			add_score(500)
			audio.play("pick")
	_sweep(G.items)


# ---------- barriers ----------

## A barrier spans the screen at one height with one opening (`gx`, `gw` wide): fixed,
## sliding, locked by a field until its generator dies, or filled by a wall of blocks.
func add_bar(s: Dictionary) -> void:
	var b := {wy = s.d, y = s.d - G.scroll, mode = s.mode, gx = s.gx, gx0 = s.gx, gw = s.gw, th = 8.0, key = s.key, locked = s.mode == "locked", nodes = []}
	var mat: Material = Models.M[Worlds.LIST[0].gate]
	for k in 2:
		var p := Models.mesh(Models.geo("vbar", func(): return Geo.box(1, 1, 1)), Models.M.fort_a)
		world.add_child(p)
		var lip := Models.mesh(Models.geo("vbarL", func(): return Geo.box(2, 1, 1)), mat)
		world.add_child(lip)
		b.nodes.append_array([p, lip])
	var f := Models.mesh(Models.geo("vbar", func(): return Geo.box(1, 1, 1)), Models.M.field)
	f.set_meta("nf", true)
	world.add_child(f)
	b.nodes.append(f)
	for k in 2:
		var st := Models.mesh(Models.geo("vbar", func(): return Geo.box(1, 1, 1)), Models.M.fort_light)
		world.add_child(st)
		b.nodes.append(st)
	G.bars.append(b)
	if s.mode == "wall":
		# a row of breakable blocks fills the opening
		var n := int(ceil(s.gw / 7.6))
		for j in n:
			E("block", s.gx - s.gw / 2 + 3.8 + j * (s.gw - 7.6) / maxf(1, n - 1), top() + 6, {wy = b.wy})
	Diag.once("vbar " + s.mode)


func _update_bars() -> void:
	for b in G.bars:
		b.y = b.wy - G.scroll
		if b.mode == "slide":
			b.gx = clampf(b.gx0 + sin(G.t * 0.02) * 26.0, b.gw / 2 + 4, W - b.gw / 2 - 4)
		if b.y < -20:
			b.dead = true
			for n in b.nodes:
				n.queue_free()
	_sweep_bars()


func _sweep_bars() -> void:
	for i in range(G.bars.size() - 1, -1, -1):
		if G.bars[i].get("dead", false):
			G.bars.remove_at(i)


## True when (x, y) padded by `pad` is inside the solid part of barrier `b`.
func bar_solid(b: Dictionary, x: float, y: float, pad: float) -> bool:
	if absf(y - b.y) > b.th / 2.0 + pad:
		return false
	var in_gap: bool = absf(x - b.gx) < b.gw / 2.0 - pad
	return not in_gap or b.locked


# ---------- boss: the Bloom Mother, re-laid out for a tall screen ----------

func spawn_boss() -> void:
	audio.music("boss")
	audio.play("alarm")
	hud.banner("Warning", "Bloom Mother approaching", 150)
	hud.boss_name = "Bloom Mother"
	Diag.once("vboss bloom")
	var petals := []
	var angles := [-0.45, 0.35, PI - 0.35, PI + 0.45]
	for i in 4:
		petals.append({id = uid(), a = angles[i], hp = 16.0, max = 16.0, alive = true, flash = 0, cd = 80 + i * 26, x = 0.0, y = 0.0})
	G.boss = {kind = "bloom", x = W / 2, y = H + 60, t = 0, bt = 0, enter = true, phase2 = false, dying = 0,
		core = {id = uid(), hp = 80.0, max = 80.0, flash = 0, open = false, ot = 0, lid = 0.0},
		petals = petals,
		tent = {id = uid(), n = 11, hp = 30.0, max = 30.0, alive = true, flash = 0, cd = 160, segs = [], drop = 0}}
	G.boss.m = Models.boss(world)
	G.boss.m.rotation.z = PI / 2


func boss_damage(part: Dictionary, d: int) -> void:
	var B: Dictionary = G.boss
	if B.is_empty() or B.dying:
		return
	match part.kind:
		"petal":
			var p: Dictionary = part.o
			p.hp -= d
			p.flash = 3
			if p.hp <= 0 and p.alive:
				p.alive = false
				boom(p.x, p.y, 9, true)
				audio.play("boom")
				add_score(1000)
				P.ult = minf(1.0, P.ult + 0.12)
			else:
				audio.play("hit")
		"tip":
			var T: Dictionary = B.tent
			T.hp -= d
			T.flash = 3
			if T.hp <= 0 and T.alive:
				T.alive = false
				boom(part.x, part.y, 9, true)
				audio.play("boom")
				add_score(2000)
				P.ult = minf(1.0, P.ult + 0.12)
			else:
				audio.play("hit")
		"core":
			var c: Dictionary = B.core
			c.hp -= d
			c.flash = 3
			audio.play("hit")
			if c.hp <= 0:
				B.dying = 1
				add_score(10000)
				for b in G.eb:
					b.dead = true
				audio.play("boom")
				shake = 16.0


func update_boss() -> void:
	var B: Dictionary = G.boss
	B.t += 1
	if B.dying:
		B.dying += 1
		if B.dying % 5 == 0:
			boom(B.x + randf_range(-22, 22), B.y + randf_range(-20, 20), randf_range(6, 13), true)
		if B.dying % 16 == 0:
			audio.play("boom")
			shake = 8.0
		if B.dying == 150:
			boom(B.x, B.y, 30, true)
			shake = 22.0
			remove_boss()
			_stage_clear()
		return
	if B.enter:
		B.y -= 0.5
		if B.y <= H - 50:
			B.y = H - 50
			B.enter = false
	else:
		B.bt += 1
		B.x = W / 2 + sin(B.bt * 0.011) * 22.0
	var alive := 0
	for p in B.petals:
		var a: float = p.a + sin(B.t * 0.03) * 0.12
		p.x = B.x + cos(a) * 22.0
		p.y = B.y + sin(a) * 18.0
		if p.flash:
			p.flash -= 1
		if not p.alive:
			continue
		alive += 1
		if not B.enter:
			p.cd -= 1
			if p.cd <= 0:
				aim(p.x, p.y, 1.1)
				p.cd = 120
	var c: Dictionary = B.core
	if c.flash:
		c.flash -= 1
	if alive == 0:
		if not B.phase2:
			B.phase2 = true
			c.ot = 0
			audio.play("alarm")
		c.ot += 1
		var cyc: int = c.ot % 230
		var was: bool = c.open
		c.open = cyc > 40 and cyc < 190
		if c.open and not was:
			ring(B.x, B.y - 6, 10, 0.8)
		if c.open and cyc % 48 == 20:
			fan(B.x, B.y - 8, 1.2, 3, 0.26)
		if c.ot % 210 == 100:
			E("drifter", B.x, B.y - 16, {move = "sine", amp = 14.0, ph = 0.0, x0 = B.x, stop = 0.0, score = 0})
	elif not B.enter and B.t % 320 == 160:
		ring(B.x, B.y - 6, 7, 0.65)
	c.lid += ((1.0 if c.open else 0.0) - c.lid) * 0.15
	# the tentacle hangs down towards the ship and sways
	var T: Dictionary = B.tent
	if T.flash:
		T.flash -= 1
	var px: float = B.x
	var py: float = B.y - 12
	T.segs = []
	for i in T.n:
		var ang := -PI / 2 + 0.9 * sin(B.t * 0.021 - i * 0.42) * minf(1.0, (i + 1) / 4.0)
		px += cos(ang) * 6.0
		py += sin(ang) * 6.0
		T.segs.append({x = px, y = py, r = maxf(2.6, 4.6 - i * 0.15)})
	if T.alive:
		var tip: Dictionary = T.segs[T.n - 1]
		if not B.enter:
			T.cd -= 1
			if T.cd <= 0:
				fan(tip.x, tip.y, 0.9, 2, 0.35)
				T.cd = 140
	else:
		T.drop += 1
		if T.drop % 6 == 0 and T.n > 0:
			var s: Dictionary = T.segs[T.n - 1]
			boom(s.x, s.y, 5)
			audio.play("small")
			T.n -= 1
	var parts := []
	for p in B.petals:
		if p.alive:
			parts.append({o = p, x = p.x, y = p.y, r = 6.0, kind = "petal"})
	for i in T.n:
		var s: Dictionary = T.segs[i]
		var is_tip: bool = T.alive and i == T.n - 1
		parts.append({o = T if is_tip else c, x = s.x, y = s.y, r = 5.0 if is_tip else s.r, kind = "tip" if is_tip else "seg"})
	parts.append({o = c, x = B.x, y = B.y, r = 13.0, kind = "core" if c.open else "shield"})
	if c.open:
		parts.append({o = c, x = B.x, y = B.y - 8, r = 7.0, kind = "core"})
	G.bparts = parts


func remove_boss() -> void:
	var B: Dictionary = G.boss
	if B.is_empty():
		return
	var u: Dictionary = B.m.get_meta("u")
	for m in u.petals + u.stalks + u.segs + [u.tip]:
		m.queue_free()
	B.m.queue_free()
	G.boss = {}
	G.bparts = []


func _stage_clear() -> void:
	if G.clear_t > 0:
		return
	G.clear_t = 1
	G.mid_boss = false
	hud.boss = -1.0
	add_score(G.lives * 2000)
	hud.banner("Stage clear", VStage.STAGES[G.stage].name, 170)
	audio.play("oneup")


# ---------- effects ----------

func glow_fx(color: String, x: float, y: float, z: float, s: float, life: int, vx := 0.0, vy := 0.0) -> void:
	var m := Models.glow(color, s)
	m.position = Vector3(X(x), Y(y), z)
	world.add_child(m)
	fx.append({m = m, life = life, t = 0, s = s, vx = vx, vy = vy})


func boom(x: float, y: float, r: float, big := false) -> void:
	glow_fx("fff1d0", x, y, 4, r * 2.4, 16)
	glow_fx("ff9a40", x, y, 3, r * 3.6, 26)
	# a shock ring racing out
	var ring := Models.mesh(VFx.ring_mesh(), VFx._ring_mats[0])
	ring.position = Vector3(X(x), Y(y), 2)
	world.add_child(ring)
	fx.append({m = ring, kind = "ring", life = 20 if big else 14, t = 0, s = r * (3.4 if big else 2.4), vx = 0.0, vy = 0.0})
	for j in (8 if big else 4):
		var a := randf() * TAU
		var sp := randf_range(0.4, 1.4) * (1.6 if big else 1.0)
		glow_fx("ff4fa3" if j % 2 else "ffb547", x, y, 5, r * 0.6, 20, cos(a) * sp, sin(a) * sp)
	# lit debris tumbling away and falling towards the moon (they throw shadows as they go)
	for j in (9 if big else 5):
		var a := randf() * TAU
		var sp := randf_range(0.5, 1.6) * (1.4 if big else 1.0)
		var d := Models.mesh(VFx.shard_mesh(), VFx._debris_mats[j % VFx._debris_mats.size()])
		d.position = Vector3(X(x), Y(y), 1)
		d.scale = Vector3.ONE * randf_range(0.5, 1.1) * clampf(r / 4.0, 0.6, 1.8)
		world.add_child(d)
		fx.append({m = d, kind = "debris", life = 40, t = 0, s = 1.0, vx = cos(a) * sp, vy = sin(a) * sp, vz = randf_range(0.2, 1.0),
			spin = Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))})
	# and a flash of real light on everything around
	var best: Dictionary = boom_lights[0]
	for bl in boom_lights:
		if bl.t < best.t:
			best = bl
	best.t = 14
	best.e = 3.5 if big else 2.0
	best.l.position = Vector3(X(x), Y(y), 12)
	best.l.omni_range = 60.0 + r * 6.0


func spark(x: float, y: float) -> void:
	glow_fx("fff1d0", x, y, 5, 4, 8)
	for j in 2:
		var a := randf() * TAU
		glow_fx("ffe0b0", x, y, 5, 1.6, 7, cos(a) * 1.2, sin(a) * 1.2)


func update_fx() -> void:
	for f in fx:
		f.t += 1
		var k: float = 1.0 - float(f.t) / f.life
		match f.get("kind", "glow"):
			"ring":
				var rs: float = f.s * (0.3 + 0.7 * sqrt(1.0 - k))
				f.m.scale = Vector3(rs, rs, 1)
				f.m.material_override = VFx._ring_mats[clampi(int((1.0 - k) * 6.0), 0, 5)]
			"debris":
				f.m.rotation += f.spin
				f.vz -= 0.06
				f.m.position.z += f.vz
				f.vx *= 0.97
				f.vy *= 0.97
				if f.t > f.life - 8:
					f.m.scale *= 0.85
			_:
				var s: float = f.s * maxf(0.0, k)
				f.m.scale = Vector3(s, s, 1)
		f.m.position.x += f.vx
		f.m.position.y += f.vy
		if f.t >= f.life:
			f.dead = true
	_sweep(fx)


# ---------- ground ----------

## One strip of ground, CHUNK units long (see `Terrain`), with the canyon walls that reach it.
func build_chunk(c: int, g: Node3D = null) -> Node3D:
	if g == null:
		g = Terrain.build_chunk(c, CHUNK, look, _terrain_mats)
	if not G.is_empty():
		var wn := _walls_node(c)
		if wn:
			g.add_child(wn)
	return g


## Rock: touching a canyon wall or an island costs a hull point and the ship never goes inside
## the rock. Flying just outside it (the scrape zone) pays points.
func _rock_player() -> void:
	var w := walls_at(P.y)
	var d: float = G.scroll + P.y
	if P.inv <= 0 and in_rock(P.x, P.y, ROCK_PAD):
		hurt()
		Diag.once("rock hit")
	P.x = clampf(P.x, w.x + ROCK_PAD + 0.2, w.y - ROCK_PAD - 0.2)
	var near := minf(P.x - w.x, w.y - P.x)
	var side := -1.0 if P.x - w.x < w.y - P.x else 1.0
	for isl in VStage.ISLANDS[G.stage]:
		var h := VStage.island_half(isl, d)
		if h <= 0.0:
			continue
		var cx: float = isl[2]
		var off: float = P.x - cx
		if absf(off) < h + ROCK_PAD:
			P.x = cx + (1.0 if off >= 0.0 else -1.0) * (h + ROCK_PAD + 0.2)
		var gap: float = absf(P.x - cx) - h
		if gap < near:
			near = gap
			side = -1.0 if P.x > cx else 1.0
	P.scrape = near < SCRAPE and P.inv <= 0
	if P.scrape and G.t % 6 == 0:
		add_score(10)
		spark(P.x + side * 4.0, P.y - 2)


## The islands of the stage: one node each, placed by the scroll in `_process`.
func _build_islands() -> void:
	G.islands = []
	for isl in VStage.ISLANDS[G.stage]:
		var n := Node3D.new()
		var steps := 16
		var cx: float = X(isl[2])
		var acc := Terrain.Acc.new()
		var lip := []
		for side in [-1.0, 1.0]:
			var rows := []
			for k in steps + 1:
				var t := float(k) / steps
				var ly := t * float(isl[1])
				var h := VStage.island_half(isl, isl[0] + ly)
				# jitter the drawn rock inwards, never past the collision edge
				var jh := maxf(0.0, h - VStage.hash(Vector2(ly, side)) * 1.2) if k > 0 and k < steps else 0.0
				rows.append([Vector3(cx + side * jh, ly, 0), jh])
			Terrain.cliff(acc, rows, -side, look, float(isl[0]) + side * 1000.0)
			for k in steps:
				var pa: Vector3 = rows[k][0]
				var pb: Vector3 = rows[k + 1][0]
				lip.append([Vector3(pa.x - side * 0.8, pa.y, 0.3), Vector3(pa.x, pa.y, 0.3), Vector3(pb.x, pb.y, 0.3)])
				lip.append([Vector3(pa.x - side * 0.8, pa.y, 0.3), Vector3(pb.x, pb.y, 0.3), Vector3(pb.x - side * 0.8, pb.y, 0.3)])
		n.add_child(Terrain._mi(acc.mesh(), _terrain_mats.ground, true))
		n.add_child(Models.mesh(Geo.build_facing(lip, Vector3.BACK), _lip_mat))
		world.add_child(n)
		G.islands.append({d = float(isl[0]), m = n})


## The canyon walls of chunk `c` (null when no wall reaches the screen there), built in the
## chunk's frame but raised to the ship's plane: a faceted cliff top, a glowing lip on the
## exact edge the ship collides with, and a banded face dropping to the floor.
func _walls_node(c: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Walls"
	n.position.z = -GROUND_Z + 50.0 - 7.0
	var rows := 16
	var seen := false
	for j in rows + 1:
		var wj := VStage.walls(G.stage, c * CHUNK + CHUNK * j / rows)
		# wide screens show well past the stage's sides
		seen = seen or wj.x > view.position.x - 4.0 or wj.y < view.end.x + 4.0
	if not seen:
		n.free()
		return null
	var left := []
	var right := []
	for j in rows + 1:
		var ly := CHUNK * j / rows
		var d := c * CHUNK + ly
		var w := VStage.walls(G.stage, d)
		# jitter the drawn rock a little, but never past the collision edge
		left.append([Vector3(X(w.x) - VStage.hash(Vector2(d, 3.0)) * 1.4, ly, 0), 200.0])
		right.append([Vector3(X(w.y) + VStage.hash(Vector2(d, 7.0)) * 1.4, ly, 0), 200.0])
	var acc := Terrain.Acc.new()
	Terrain.cliff(acc, left, -1.0, look, c * CHUNK)
	Terrain.cliff(acc, right, 1.0, look, c * CHUNK + 500.0)
	var lip := []
	for j in rows:
		for side in [[left, -1.0], [right, 1.0]]:
			var a: Vector3 = side[0][j][0]
			var b: Vector3 = side[0][j + 1][0]
			var s: float = side[1]
			lip.append([Vector3(a.x + s * 0.9, a.y, 0.3), Vector3(a.x, a.y, 0.3), Vector3(b.x, b.y, 0.3)])
			lip.append([Vector3(a.x + s * 0.9, a.y, 0.3), Vector3(b.x, b.y, 0.3), Vector3(b.x + s * 0.9, b.y, 0.3)])
	n.add_child(Terrain._mi(acc.mesh(), _terrain_mats.ground, true))
	n.add_child(Models.mesh(Geo.build_facing(lip, Vector3.BACK), _lip_mat))
	return n


func update_chunks(scroll: float) -> void:
	# the floor lies deeper than the play plane, so it shows more than the screen's height
	var reach := view.size.y * 0.75
	var a := floori((scroll + H / 2.0 - reach - 20.0) / CHUNK)
	var b := floori((scroll + H / 2.0 + reach + 60.0) / CHUNK)
	for c in chunks.keys():
		if c < a or c > b + 2:
			chunks[c].queue_free()
			chunks.erase(c)
	for c in _building.keys():
		if c < a:
			_building.erase(c)
	for c in range(a, b + 1):
		if not chunks.has(c):
			# needed now: finish it here (only on a jump, e.g. the first frame of a stage)
			var bl: Terrain.Builder = _building.get(c)
			_building.erase(c)
			if bl == null:
				bl = Terrain.Builder.new(c, CHUNK, look, _terrain_mats)
			while not bl.step():
				pass
			_add_chunk(c, bl.node)
	# the next strips are built a slice per frame ahead of time, so new ground never hitches
	for c in [b + 1, b + 2]:
		if not chunks.has(c) and not _building.has(c):
			_building[c] = Terrain.Builder.new(c, CHUNK, look, _terrain_mats)
	if not _building.is_empty():
		var c: int = _building.keys().min()
		var bl: Terrain.Builder = _building[c]
		if bl.step():
			_building.erase(c)
			_add_chunk(c, bl.node)
	for c in chunks:
		chunks[c].position = Vector3(0, c * CHUNK - scroll - H / 2.0, GROUND_Z - 50.0)


func _add_chunk(c: int, g: Node3D) -> void:
	var n := build_chunk(c, g)
	world.add_child(n)
	chunks[c] = n


# ---------- render ----------

func _physics_process(_delta: float) -> void:
	if driven:
		return
	poll_input()
	update()


func _process(_delta: float) -> void:
	var sc: float = G.get("scroll", tt * 0.3)
	for i in stars.size():
		stars[i].position.y = -fmod(sc * (0.25 + 0.2 * i), 600.0) - 300.0
	if G.is_empty():
		# behind the menu the moon keeps drifting by
		update_chunks(sc)
		return
	update_chunks(G.scroll)
	for isl in G.islands:
		isl.m.position = Vector3(0, isl.d - G.scroll - H / 2.0, -7.0)
		isl.m.visible = isl.d - G.scroll < top() + 80 and isl.d - G.scroll > -400
	var kit_ult: float = P.get("ult", 0.0)
	hud.score = fmt(G.score)
	hud.hull = P.hull if P.alive else 0
	hud.ships = maxi(0, G.lives - 1) if P.alive else maxi(0, G.lives)
	hud.ult = kit_ult
	hud.ult_ready = kit_ult >= 1.0 and G.ult_t == 0
	hud.charge = float(P.charge) / CHARGE_MAX
	hud.charge_lv = charge_lv(P.charge)
	hud.queue_redraw()
	# the ship banks as it slides sideways and blinks while invincible
	ship_m.visible = P.alive and not (P.inv > 2 and (tt >> 2) % 2 and G.ult_t == 0)
	ship_m.position = Vector3(X(P.x), Y(P.y), 0)
	var mdl: Node3D = ship_m.get_meta("model")
	(mdl.get_meta("body") as Node3D).rotation.x = clampf(P.vx * 0.35, -0.6, 0.6)
	(mdl.get_meta("flame") as Node3D).scale = Vector3(0.8 + randf() * 0.5, 1, 1)
	# Lance's charge: a laser ball at the nose with the level's strands coiling round it
	var lv := charge_lv(P.charge)
	charge_fx.visible = P.alive and P.charge > 10 and G.ship == "lance"
	var light_e := 0.0
	var light_c := Color("dfe9ff")
	if charge_fx.visible:
		charge_fx.position = Vector3(X(P.x), Y(P.y + 13), 4)
		if not paused:
			charge_ph += 0.12 + float(P.charge) / CHARGE_MAX * 0.25
		VFx.sync_charge(charge_fx, P.charge, CHARGE_MAX, lv, tt, charge_ph)
		light_e = 0.6 + 1.6 * float(P.charge) / CHARGE_MAX
		light_c = Color(VFx.CHARGE_COL[maxi(lv, 1)])
		beam_light.position = charge_fx.position + Vector3(0, 0, 8)
	for bm in G.beams:
		if bm.ult:
			continue
		var f: float = clampf(float(bm.life) / 6.0, 0.0, 1.0)
		if 3.0 * f + bm.lv >= light_e:
			light_e = (2.0 + bm.lv * 0.8) * f
			light_c = Color(VFx.CHARGE_COL[maxi(int(bm.lv), 2)])
			beam_light.position = Vector3(X(bm.x), Y(bm.y0 + 30.0), 10)
	beam_light.visible = light_e > 0.05 and not Diag.safe
	beam_light.light_energy = light_e
	beam_light.light_color = light_c
	for bl in boom_lights:
		if bl.t > 0:
			bl.t -= 1
			bl.l.light_energy = bl.e * float(bl.t) / 14.0
		bl.l.visible = bl.t > 0 and not Diag.safe
	shield_m.visible = P.alive and G.ult_t > 0 and G.ship == "warden"
	if shield_m.visible:
		shield_m.position = Vector3(X(P.x), Y(P.y), 4)
	if pod_m:
		pod_m.visible = not pod.is_empty() and pod.state != "shatter" and P.alive
		pod_m.position = Vector3(X(pod.x), Y(pod.y), 1)
		var pmdl: Node3D = pod_m.get_meta("model")
		(pmdl.get_meta("spin") as Node3D).rotation.x += 0.08 if pod.state == "dock" else 0.25
	for e in G.enemies:
		_sync_e(e)
	for b in G.bars:
		_sync_bar(b)
	for b in G.pb:
		b.m.position = Vector3(X(b.x), Y(b.y), 0)
	for b in G.eb:
		b.m.position = Vector3(X(b.x), Y(b.y), 2)
	for it in G.items:
		it.m.position = Vector3(X(it.x), Y(it.y), 0)
		(it.m.get_meta("core") as Node3D).rotation.y += 0.05
	for s in G.shards:
		s.m.position = Vector3(X(s.x), Y(s.y), 3)
		s.m.rotation.z += 0.3
	for b in G.beams:
		_sync_beam(b)
	if not G.boss.is_empty():
		_sync_boss()
	if G.get("mid_boss", false):
		var hp := 0.0
		var mx := 0.0
		for e in G.enemies:
			if e.get("boss", false):
				hp += maxf(0.0, e.hp)
				mx += e.max
		hud.boss = hp / mx if mx > 0 else -1.0
	var j := Vector3.ZERO
	if shake > 0.3:
		j = Vector3(randf_range(-shake, shake), randf_range(-shake, shake), 0) * 0.2
		shake *= 0.86
	camera.position = Vector3(0, 0, CAM_D) + j


func _sync_e(e: Dictionary) -> void:
	var m: Node3D = e.m
	m.position = Vector3(X(e.x), Y(e.y), -4.0 if e.ground else 0.0)
	Models.set_flash(m, e.flash > 0)
	match e.type:
		"drifter":
			m.rotation = Vector3(e.t * 0.03, e.t * 0.05, 0)
		"turret":
			if P.alive:
				m.rotation.z = atan2(P.y - e.y, P.x - e.x)
		"carrier":
			for w in m.get_meta("w"):
				w.rotation.x = sin(e.t * 0.3) * 0.5


func _sync_bar(b: Dictionary) -> void:
	var n: Array = b.nodes
	var left: float = b.gx - b.gw / 2.0
	var right: float = b.gx + b.gw / 2.0
	var lw := left + 40.0
	var rw := W + 40.0 - right
	n[0].position = Vector3(X(left - lw / 2.0), Y(b.y), 0)
	n[0].scale = Vector3(lw, b.th, 10)
	n[1].position = Vector3(X(left - 1.0), Y(b.y), 1)
	n[1].scale = Vector3(1, b.th + 2, 12)
	n[2].position = Vector3(X(right + rw / 2.0), Y(b.y), 0)
	n[2].scale = Vector3(rw, b.th, 10)
	n[3].position = Vector3(X(right + 1.0), Y(b.y), 1)
	n[3].scale = Vector3(1, b.th + 2, 12)
	n[4].visible = b.locked
	n[4].position = Vector3(X(b.gx), Y(b.y), 0)
	n[4].scale = Vector3(b.gw, b.th * 0.6, 4)
	n[5].position = Vector3(X(left - lw / 2.0), Y(b.y - b.th / 2.0 + 1.0), 5.2)
	n[5].scale = Vector3(lw, 0.8, 0.4)
	n[6].position = Vector3(X(right + rw / 2.0), Y(b.y - b.th / 2.0 + 1.0), 5.2)
	n[6].scale = Vector3(rw, 0.8, 0.4)


func _sync_beam(b: Dictionary) -> void:
	var len: float = maxf(1.0, b.y1 - b.y0)
	var fade: float = clampf(float(b.life) / 6.0, 0.0, 1.0)
	var w: float = b.w * fade
	b.m.position = Vector3(X(b.x), Y(b.y0), 3)
	var age: int = (120 if b.ult else BEAM_LIFE[b.lv]) - b.life
	VFx.sync_beam(b.m, b.lv, len, w, fade, age, tt, b.y1 < view.end.y)


func _sync_boss() -> void:
	var B: Dictionary = G.boss
	var u: Dictionary = B.m.get_meta("u")
	B.m.position = Vector3(X(B.x), Y(B.y), 0)
	u.core.rotation.z = B.t * 0.004
	var op: float = B.core.lid
	u.lidT.rotation.x = -op * 1.3
	u.lidB.rotation.x = PI + op * 1.3
	if P.alive:
		# the eye follows the ship; the model is turned a quarter turn, so turn the look back
		var d := Vector2(P.x - B.x, P.y - B.y).normalized()
		u.pupil.position = Vector3(d.y * 2.4 * op, -d.x * 2.4 * op, lerpf(1.5, 5.0, op))
	var cf: bool = B.core.flash > 0 and B.core.open
	Models.set_flash(u.core, cf)
	Models.set_flash(u.eye, cf)
	for i in 4:
		var p: Dictionary = B.petals[i]
		var pm: Node3D = u.petals[i]
		var st: Node3D = u.stalks[i]
		pm.visible = p.alive
		st.visible = p.alive
		if not p.alive:
			continue
		var ang := atan2(p.y - B.y, p.x - B.x) - PI / 2.0
		pm.position = Vector3(X(p.x), Y(p.y), 2)
		pm.rotation = Vector3(0, B.t * 0.03, ang)
		st.position = Vector3(X((p.x + B.x) / 2.0), Y((p.y + B.y) / 2.0), -1)
		st.scale.y = Vector2(p.x - B.x, p.y - B.y).length()
		st.rotation.z = ang
		Models.set_flash(pm, p.flash > 0)
	var T: Dictionary = B.tent
	for i in u.segs.size():
		var m: Node3D = u.segs[i]
		m.visible = i < T.n and not (T.alive and i == T.n - 1)
		if i < T.segs.size():
			var s: Dictionary = T.segs[i]
			m.position = Vector3(X(s.x), Y(s.y), 0)
			m.rotation = Vector3(B.t * 0.02 + i, i, 0)
	u.tip.visible = T.alive and T.n > 0
	if u.tip.visible:
		var s: Dictionary = T.segs[T.n - 1]
		u.tip.position = Vector3(X(s.x), Y(s.y), 1)
		u.tip.rotation.z = B.t * 0.05
		Models.set_flash(u.tip, T.flash > 0)
	var hp: float = B.core.hp
	var mxh: float = B.core.max
	for p in B.petals:
		hp += maxf(0.0, p.hp)
		mxh += p.max
	hp += maxf(0.0, T.hp)
	mxh += T.max
	hud.boss = 0.0 if B.dying else clampf(hp / mxh, 0.0, 1.0)
