extends Node3D
## Star Breaker in portrait: the vertical slice. One thumb drags the ship (1:1 with the
## thumb's movement) and the main weapon fires on its own while the thumb is down; lifting the
## thumb triggers the ship's release (Lance: the charge beam, Warden: fling or recall the pod),
## and each ship loads its ultimate its own way (one finger plays it all). Lance's is the last
## stage of its charge bar: it charges through LV 1-3 and the Nova to the Storm at ULT_AT ticks,
## chain lightning through every enemy on screen. Warden's Shatter fills from what the pod does
## (see SHATTER_FULL) and fires when the pod is recalled.
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
## Lance's ultimate, the Storm: the charge bar's stage after the Nova. No kills needed
## (Guillaume's call, 2026-11-20): holding on past the Nova reaches it at ULT_AT ticks (7 s),
## and lifting lets loose chain lightning that jumps from the ship through every enemy and boss
## part on screen, STORM_DMG each (two thirds of a Nova hit, once per target: it clears small
## flyers, leaves big ones and bosses hurt), within STORM_SPREAD ticks; the bolts crackle on
## for STORM_LIFE ticks. It also wipes the enemy bullets on screen. The long hold and the
## lighter hit are its price for being free.
const ULT_AT := 420
const STORM_DMG := 20
const STORM_SPREAD := 24
const STORM_LIFE := 70
## Warden's ultimate, Shatter, has its own mechanic (Guillaume's call, 2026-11-21): holding loads
## nothing, so a lift is always a pod command. The meter fills from the pod's work: SHAT_RAM per
## ram, SHAT_BLOCK per enemy bullet it stops, SHAT_SHOT per pod shot that lands and SHAT_KILL more
## for each enemy the pod finishes. Full at SHATTER_FULL, it stays stored (through lifts and lost
## ships) until the pod is recalled while out: the pod then bursts into the homing shards where it
## is. With the pod docked, fling it and recall it.
const SHATTER_FULL := 60.0
const SHAT_RAM := 5.0
const SHAT_BLOCK := 3.0
const SHAT_SHOT := 1.0
const SHAT_KILL := 6.0
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
	generator = [3.6, 3.6, 6, 500], block = [3.8, 3.8, 3, 50], matriarch = [14, 10, 90, 6000],
	wallgun = [3.4, 2.6, 6, 400], shard = [2, 4, 2, 150], flake = [4, 4, 4, 250], hulk = [10, 7, 30, 1600], drone = [2.5, 3.5, 2, 120], seeker = [2, 3, 3, 200],
	sentinel = [10, 7, 34, 1800], wasp = [2.2, 3, 1, 120], nest = [8, 9, 30, 1600], lancer = [2.4, 5, 3, 200], bulwark = [9, 7, 34, 1800]}
## Big flyers: they come down, hold a while firing, then leave (and make the mid-bosses).
const BIG := ["shell", "hulk", "sentinel", "nest", "bulwark"]
## Flyers that turn to face where they are going.
const HEADING := ["shard", "drone", "seeker", "wasp", "lancer"]
const GROUND := ["turret", "generator", "block", "wallgun"]

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
var inp := {hold = false, fire = false, dx = 0.0, dy = 0.0, pause = false}
var _touch_id := -1
var _touch_seen := false
var _mouse_down := false
var _no_thumb := 0
var _pending := Vector2.ZERO
var _pause_latch := false
var _kb_pause_was := false
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
## The way the sun's light travels: shadows fall along it (down and right on screen).
var sun_dir := Vector3(0.376, -0.457, -0.806)
var beam_light: OmniLight3D
var boom_lights: Array = []
var charge_ph := 0.0
## Each world's lighting and ground colours (sRGB), Hollow Moon first.
const LOOKS := [{sun = "ffe6c8", amb = "5a50a0", fog = "140e2e", t_low = "1c1640", t_low2 = "2a1440", t_mid = "3a3070", t_high = "7a6cc0",
	t_cliff = "241e4c", t_rock = "463c7c", c_top = "463c88", c_top2 = "2e2862", c_face = "2c2560", river_a = "3ff0e0", river_b = "ff4fa3",
	cry = ["6ff3e6", "2fd6c8", "ff7ac0", "ff2f8f"], fis = ["c0408a", "3fb8b0"], lip = ["b9a8ff", "8f6bff"]},
	{sun = "e8f4ff", amb = "4a6a9a", fog = "0c1c30", t_low = "17283f", t_low2 = "1d3050", t_mid = "3c5a80", t_high = "b8d8f0",
	t_cliff = "1a2a46", t_rock = "56769c", c_top = "8aaccc", c_top2 = "56769a", c_face = "2f4a6a", river_a = "bff6ff", river_b = "4fb8ff",
	cry = ["dff8ff", "9fe8ff", "7fd8ff", "3fa8ff"], fis = ["4fb8ff", "bff6ff"], lip = ["d0f4ff", "7fe8ff"]},
	{sun = "fff0c0", amb = "5a6a30", fog = "101e0c", t_low = "17260f", t_low2 = "223012", t_mid = "40562a", t_high = "a0b860",
	t_cliff = "1c2a12", t_rock = "54663a", c_top = "7a8a4a", c_top2 = "4e5e30", c_face = "34421e", river_a = "ffb547", river_b = "c8f560",
	cry = ["ffc860", "ff9a20", "c8f560", "8ac020"], fis = ["ff9a20", "c8f560"], lip = ["ffe0a0", "ffb547"]},
	{sun = "ffd8b0", amb = "6a4a40", fog = "1c100c", t_low = "201410", t_low2 = "2a1a14", t_mid = "4a3a34", t_high = "9a8478",
	t_cliff = "22160f", t_rock = "5a4a44", c_top = "7a6a62", c_top2 = "4e4440", c_face = "362a26", river_a = "ff7a1a", river_b = "ffcc33",
	cry = ["ffb070", "ff6a00", "ffd060", "ffaa00"], fis = ["ff5a00", "ffcc33"], lip = ["ffc890", "ff7a1a"]},
	{sun = "e0e8ff", amb = "4a5090", fog = "0c0e22", t_low = "121630", t_low2 = "181c3c", t_mid = "343c6a", t_high = "8890c8",
	t_cliff = "141834", t_rock = "4a5280", c_top = "7078a0", c_top2 = "50587e", c_face = "30365a", river_a = "ff4fa3", river_b = "4fe3d6",
	cry = ["ff7ac0", "ff2f8f", "6ff3e6", "2fd6c8"], fis = ["ff2f8f", "3fc0c0"], lip = ["c0c8ff", "ff4fa3"]},
	{sun = "fff0c8", amb = "7a3a20", fog = "260a06", t_low = "2a0c08", t_low2 = "34100a", t_mid = "5a2414", t_high = "c0602a",
	t_cliff = "2a0e08", t_rock = "6b2a2a", c_top = "7a3a2a", c_top2 = "552222", c_face = "3a1610", river_a = "ffcc40", river_b = "ff6a00",
	cry = ["ffe080", "ffb000", "ff8a40", "ff4000"], fis = ["ff4000", "ffcc40"], lip = ["ffe0a0", "ffcc40"]},
]
var look: Dictionary = {}
var _lip_mat: Material
var _rim: DirectionalLight3D
## Terrain materials of each world, made the first time a stage of that world starts.
var _world_mats: Dictionary = {}
var _world := -1
## The canyon run of the current stage (see VRun): built a slice per frame from the stage's start.
var run_b: VRun.Builder = null
var _run_built := false
## The top-down camera's field of view (set by `_on_resize`); the run swings away from it.
var _fov_td := 60.0


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
	hud.retry_pressed.connect(func(): start_stage(G.stage, G.ship, G.tier))
	hud.next_pressed.connect(func(): start_stage(G.stage + 1, G.ship, G.tier))
	hud.tier_pressed.connect(func(t: int): start_stage(G.stage, G.ship, t))
	hud.level_pressed.connect(func(ship: String):
		if prog.buy_level(ship):
			audio.play("oneup")
			_save()
			hud.refresh_progress())
	hud.paint_chosen.connect(func(ship: String, id: String):
		if prog.set_paint(ship, id):
			_save()
			hud.refresh_progress())
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
var bests: Array = []
## Medals, cleared tiers and ship colours (see Progress).
var prog := Progress.new()
var _env: Environment


func _load() -> void:
	bests = []
	bests.resize(VStage.STAGES.size())
	bests.fill(0)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		muted = bool(cfg.get_value("game", "muted", false))
		var b = cfg.get_value("portrait", "bests", [])
		if b is Array:
			# saves from before the 48 stages held world 1's first two stages and the Bloom Heart
			var at := [0, 1, 7] if b.size() == 3 else range(b.size())
			for i in mini(b.size(), at.size()):
				if at[i] < bests.size():
					bests[at[i]] = int(b[i])
		prog.load_from(cfg)
	audio.set_muted(muted)
	hud.set_muted(muted)
	hud.prog = prog
	hud.set_bests(bests)
	hud.focus_next()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("game", "muted", muted)
	cfg.set_value("portrait", "bests", bests)
	prog.save_to(cfg)
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
	# A clean exit: Android restarts by killing the process, so without this line the next
	# launch read the log as a crash and switched safe graphics on.
	Diag.note("QUIT", "restart")
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
		Models.generator(1), Models.block(Models.M.rock), Models.carrier("L"), Models.item("L"), Models.shard(), Models.flake(), Models.hulk(),
		Models.drone(), Models.seeker(), Models.sentinel(), Models.wasp(), Models.nest(), Models.lancer(), Models.bulwark()]
	for k in Models.M:
		var mat = Models.M[k]
		if mat is Material:
			list.append(Models.mesh(Models.geo("pt", func(): return Geo.tetra(1)), mat))
	for mat in [_lip_mat, _terrain_mats.river, _terrain_mats.river_glow, _terrain_mats.fissure_b, Models.M.crystal_c] + _ground_mats:
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
	for b in [Models.boss_prism(bw), Models.boss_titan(bw), Models.boss_heart(bw), Models.boss_queen(bw), Models.boss_bastion(bw)]:
		Models.set_flash(b, true)
	for i in 4:
		await get_tree().process_frame
	w.queue_free()
	Diag.note("WARM", "%d objects" % (list.size() + 1))


func _setup_world() -> void:
	var pal: Dictionary = Worlds.LIST[0].pal
	look = LOOKS[0]
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
	sun_dir = -sun.global_transform.basis.z
	var rim := DirectionalLight3D.new()
	_rim = rim
	rim.light_color = Color(pal.rim)
	rim.light_energy = 0.55
	rim.light_specular = 0.6
	add_child(rim)
	rim.look_at_from_position(Vector3(90, -80, 40), Vector3.ZERO)
	world = Node3D.new()
	add_child(world)
	_ground_mats = [Terrain.ground_mat(), Models.std(pal.far), Models.std(pal.bg)]
	stars = [_star_layer(160, -200, -150, 1.6, Color(pal.star_a)), _star_layer(90, -150, -110, 2.0, Color(pal.star_b))]
	apply_world(0)
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


## Dresses the scene for world `w`: sky, fog, light, ground and rock colours, stars.
func apply_world(w: int) -> void:
	if w == _world:
		return
	_world = w
	var pal: Dictionary = Worlds.LIST[w].pal
	look = LOOKS[w]
	if not _world_mats.has(w):
		_world_mats[w] = {
			ground = _ground_mats[0],
			crystals = [Terrain.crystal_mat(look.cry[0], look.cry[1], 0.9), Terrain.crystal_mat(look.cry[2], look.cry[3], 0.85)],
			fissure_a = Models.basic(look.fis[0], 1.15), fissure_b = Models.basic(look.fis[1], 1.1),
			river = Terrain.river_mat(1.9, 1.3, look.river_a, look.river_b), river_glow = Terrain.river_mat(0.3, 2.5, look.river_a, look.river_b),
			lip = Models.std(look.lip[0], look.lip[1], 1.1),
		}
	_terrain_mats = _world_mats[w]
	_lip_mat = _terrain_mats.lip
	_env.background_color = Color(pal.bg)
	_env.ambient_light_color = Color(look.amb)
	_env.fog_light_color = Color(look.fog)
	sun.light_color = Color(look.sun)
	_rim.light_color = Color(pal.rim)
	for k in stars.size():
		var mi: MultiMeshInstance3D = stars[k].get_child(0)
		(mi.multimesh.mesh.material as StandardMaterial3D).albedo_color = Color(pal.star_a if k == 0 else pal.star_b)
	Diag.once("vworld %d" % w)


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
	_fov_td = camera.fov


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
				return
			if _touch_id == -1:
				_touch_id = t.index
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
				return
			_mouse_down = mb.pressed
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
		elif not hud.back():
			# back on the home screen leaves the app (other menu screens step back)
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
	var kb_pause := Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_P) or Input.is_joy_button_pressed(0, JOY_BUTTON_START)
	inp.pause = _pause_latch or (kb_pause and not _kb_pause_was)
	_kb_pause_was = kb_pause
	_pause_latch = false


# ---------- flow ----------

## Starts stage `i` with ship `kind` on tier `tier` (-1: the tier picked on the menu), or the
## highest tier below it that this stage has open.
func start_stage(i: int, kind: String, tier := -1) -> void:
	teardown()
	i = clampi(i, 0, VStage.STAGES.size() - 1)
	var sd: Dictionary = VStage.STAGES[i]
	var tr := prog.best_open(Progress.stage_id(i), hud.tier if tier < 0 else tier)
	var td: Dictionary = Progress.tier(tr)
	Diag.note("VSTAGE", "%d %s tier %d" % [i, kind, tr])
	G = {stage = i, ship = kind, scroll = 0.0, t = 0, si = 0, bi = 0, enemies = [], eb = [], pb = [], items = [], bars = [], beams = [],
		boss = {}, bparts = [], props = [], score = 0, world = sd.world, j = sd.j, lives = int(td.ships), clear_t = 0, fail_t = 0, ended = false, ult_t = 0, shards = [], length = sd.length,
		power = Progress.power(prog.level(kind)), flux = 0,
		tier = tr, foes = 0, foes_killed = 0, breakables = 0, broken = 0, hits = 0, boss_t0 = -1, boss_ticks = -1, end_kind = ""}
	P = {x = W / 2.0, y = -12.0, alive = true, entering = true, inv = 120, hull = HULL, laser = 0, fire_cd = 0, charge = 0, ready_lv = 0,
		held = false, storm_rdy = false, shat = 0.0, vx = 0.0, respawn = 0, hit_t = 0, scrape = false}
	pod = {state = "dock", x = P.x, y = P.y + 10, ram_cd = 0, fire_cd = 0} if kind == "warden" else {}
	apply_world(sd.world)
	script_list = VStage.build(i)
	_build_islands()
	if sd.has("run"):
		VRun.use(sd.course)
		run_b = VRun.Builder.new(look, {ground = _terrain_mats.ground, lip = _lip_mat, glow = _terrain_mats.fissure_b})
		run_b.node.visible = false
		world.add_child(run_b.node)
		_run_built = false
	var model := VShips.model(kind)
	Progress.apply_paint(model, prog.paint_of(kind))
	ship_m = VShips.upright(model)
	ship_m.add_child(Models.glow("ff9a40", 8))
	world.add_child(ship_m)
	if kind == "warden":
		pod_m = VShips.upright(Models.pod())
		pod_m.add_child(Models.glow("3ff0e0", 9))
		world.add_child(pod_m)
	P.y = _ship_entry_y()
	if not pod.is_empty():
		pod.y = P.y + 10
	hud.ship = kind
	hud.stage_name = sd.name if tr == 0 else "%s · %s" % [sd.name, td.name]
	hud.boss = -1.0
	hud.banner(sd.name, sd.sub if tr == 0 else "%s · %s" % [sd.sub, td.name], 160)
	mode = "play"
	paused = false
	hud.show_screen("play")
	_no_thumb = 0
	audio.music(Worlds.LIST[sd.world].song)


func teardown() -> void:
	for k in ["enemies", "eb", "pb", "items", "beams", "shards", "islands", "props"]:
		for o in G.get(k, []):
			if is_instance_valid(o.get("m")):
				o.m.queue_free()
	for b in G.get("bars", []):
		for n in b.nodes:
			n.queue_free()
	if G.has("storm"):
		G.storm.m.queue_free()
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
	if run_b != null:
		run_b.node.queue_free()
		run_b = null
	_camera_reset()
	charge_fx.visible = false
	shield_m.visible = false
	G = {}
	P = {}
	pod = {}


## Back to the menu: the level screen after a stage (the world just played, or the next one when
## this clear opened it), the home screen otherwise.
func to_menu() -> void:
	var from_stage := not G.is_empty()
	if from_stage:
		# show the world just played, or the next one when this clear opened it
		var nx := int(G.get("report", {}).get("unlocked_next", -1))
		hud.focus_next(nx if nx >= 0 else G.stage)
	teardown()
	mode = "menu"
	paused = false
	audio.set_paused(false)
	audio.music("")
	hud.show_screen("levels" if from_stage else "menu")


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
	var id := Progress.stage_id(G.stage)
	var got := Progress.judge({cleared = cleared, foes = G.foes, foes_killed = G.foes_killed, breakables = G.breakables,
		broken = G.broken, hits = G.hits, boss_ticks = G.boss_ticks, end = G.end_kind, tier = G.tier,
		boss_scale = 1.0 if G.end_kind == "bloom" else 1.0 + 0.2 * G.world + 0.03 * G.j})
	var rep := prog.record(id, G.tier, cleared, got)
	rep.flux = prog.bank_run(G.score, G.tier, rep.new_medals.size())
	rep.merge({cleared = cleared, tier = G.tier, got = got, held = prog.medals(id, G.tier)})
	G.report = rep
	# Next only when the following stage is open on the tier just played
	hud.set_result(cleared, fmt(G.score), G.stage + 1 < VStage.STAGES.size() and prog.open(G.stage + 1, G.tier))
	_save()
	hud.refresh_progress()
	hud.set_report(rep)
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
	# the stage holds still while the canyon run streams past; it keeps going through the boss
	# fights (Guillaume, 2026-11-21): bosses fly on the play plane in screen units, so the ground
	# moves on under them, and the terrain is endless past the stage's length
	if not G.has("run"):
		G.scroll += SCROLL
	# what stands on the ground is built well ahead, out of sight (it scrolls in with the
	# ground); the rest is sent when its turn comes (`si`, which tools and tests may move on)
	G.bi = maxi(G.bi, G.si)
	while G.bi < script_list.size() and script_list[G.bi].d <= G.scroll + top() + BUILD_AHEAD:
		if script_list[G.bi].type in GROUND_PIECES:
			spawn(script_list[G.bi])
		G.bi += 1
	while G.si < script_list.size() and not G.has("run") and \
			script_list[G.si].d <= G.scroll + top() + 10 + (0.0 if script_list[G.si].type in ["run", "end"] else WAVE_LEAD):
		if not script_list[G.si].type in GROUND_PIECES:
			_due = script_list[G.si].d
			spawn(script_list[G.si])
			_due = -INF
		G.si += 1
	# no auto-pause in the canyon run: the guns rest there, so lifting the thumb to wait for the
	# canyon (or between obstacles) is natural and paused the game "for no reason"
	if _touch_seen and not inp.hold and not G.has("run"):
		_no_thumb += 1
		if _no_thumb >= AUTO_PAUSE:
			set_paused(true)
			return
	else:
		_no_thumb = 0
	if G.has("run"):
		_update_run()
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
			P.merge({alive = true, entering = true, x = clampf(W / 2.0, rw.x + 8, rw.y - 8), y = _ship_entry_y(), inv = 150, hull = HULL, charge = 0, ready_lv = 0, held = inp.hold}, true)
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
	if G.has("run"):
		_run_player()
		return
	_move_player()
	# main weapon: fires on its own while the thumb is down
	if P.fire_cd > 0:
		P.fire_cd -= 1
	if inp.fire and P.fire_cd <= 0:
		fire_main()
		P.fire_cd = VShips.KITS[G.ship].fire_every
	# the release: holding builds the charge (Lance's beam levels, then the ultimate for both
	# ships); lifting triggers the ship's move
	var kit: Dictionary = VShips.KITS[G.ship]
	if inp.hold:
		P.charge = mini(charge_cap(), P.charge + 1)
		if kit.release == "beam":
			var lv := charge_lv(P.charge)
			if lv > P.ready_lv:
				P.ready_lv = lv
				audio.play("ready", lv)
		if P.charge == ULT_AT and not P.get("storm_rdy", false):
			P.storm_rdy = true
			audio.play("ready", 4)
			shake = maxf(shake, 3.0)
	elif P.held:
		release()
		P.charge = 0
		P.ready_lv = 0
		P.storm_rdy = false
	P.held = inp.hold
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
		if P.charge >= ULT_AT and G.ult_t == 0:
			storm()
		elif lv > 0:
			fire_beam(lv)
	elif kit.release == "pod" and pod.get("state", "") == "out" and shatter_full():
		ultimate()
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
	var b := {lv = lv, life = BEAM_LIFE[lv], x = P.x, y0 = P.y + 6, y1 = H, w = BEAM_W[lv], hit = {}, nova = lv == 4}
	b.m = _beam_node(lv)
	world.add_child(b.m)
	G.beams.append(b)
	audio.play("beam", lv)
	shake = maxf(shake, 2.0 + lv)
	Diag.once("beam lv%d" % lv)


func _beam_node(lv: int) -> Node3D:
	return VFx.beam_node(lv)


## How far the charge runs: Lance's runs to the Storm (only to the Nova while an ultimate is
## still going); Warden's hold loads nothing.
func charge_cap() -> int:
	if VShips.KITS[G.ship].release != "beam":
		return 0
	return ULT_AT if G.ult_t == 0 else CHARGE_MAX


func shatter_full() -> bool:
	return G.ship == "warden" and G.ult_t == 0 and P.get("shat", 0.0) >= SHATTER_FULL


## The pod's work fills Warden's Shatter meter (not while Shatter is going).
func shatter_gain(n: float) -> void:
	if G.ship != "warden" or G.ult_t > 0 or not P.alive:
		return
	var was_full := shatter_full()
	P.shat = minf(SHATTER_FULL, P.get("shat", 0.0) + n)
	if shatter_full() and not was_full:
		audio.play("ready", 4)
		shake = maxf(shake, 3.0)


## Warden's ultimate, Shatter, fired by recalling the pod with the meter full. Lance's is the
## Storm.
func ultimate() -> void:
	audio.play("ready", 4)
	shake = maxf(shake, 6.0)
	Diag.once("ult " + G.ship)
	# Shatter: the pod bursts where it is into eight homing shards; the ship is shielded until
	# the pod reforms at its nose
	G.ult_t = 180
	P.shat = 0.0
	var ox: float = pod.x
	var oy: float = pod.y
	pod.state = "shatter"
	boom(ox, oy, 8, true)
	for j in 8:
		var a := TAU * j / 8.0
		var m := Models.mesh(Models.geo("vshard", func(): return Geo.octa(1.6)), Models.M.crystal_m)
		world.add_child(m)
		G.shards.append({x = ox, y = oy, vx = cos(a) * 2.5, vy = sin(a) * 2.5, m = m, cd = 0})


## The Storm: chain lightning from the ship's nose through every enemy and boss part on screen,
## nearest first, each hop striking a moment after the last. Enemy bullets on screen are wiped.
func storm() -> void:
	G.ult_t = STORM_LIFE
	Diag.once("ult storm")
	audio.play("beam", 4)
	shake = maxf(shake, 8.0)
	var pool := []
	var r := view.grow(-1.0)
	for e in G.enemies:
		if not e.get("dead", false) and r.has_point(Vector2(e.x, e.y)):
			pool.append({e = e, x = e.x, y = e.y})
	for p in G.bparts:
		if p.kind == "shield" or p.kind == "seg" or not p.get("alive", true):
			continue
		if r.has_point(Vector2(p.x, p.y)):
			pool.append({part = p, x = p.x, y = p.y})
	var from := Vector2(P.x, P.y + 8)
	var hops := []
	var n := pool.size()
	while not pool.is_empty():
		var bi := 0
		var bd := 1e18
		for k in pool.size():
			var d := from.distance_squared_to(Vector2(pool[k].x, pool[k].y))
			if d < bd:
				bd = d
				bi = k
		var t: Dictionary = pool[bi]
		pool.remove_at(bi)
		t.at = int(float(hops.size()) * STORM_SPREAD / maxf(1.0, n))
		t.src = hops.size() - 1
		t.hit = false
		hops.append(t)
		from = Vector2(t.x, t.y)
	G.storm = {t = 0, hops = hops, m = VFx.storm_node(), seed = randi()}
	world.add_child(G.storm.m)
	for b in G.eb:
		if r.has_point(Vector2(b.x, b.y)):
			b.dead = true
			spark(b.x, b.y)


## The storm's bolts as [from, to] pairs in 3D: the ship's nose to the first target,
## then target to target, each shown once its hop has struck.
func _storm_points() -> Array:
	var out := []
	for h in G.storm.hops:
		if not h.hit:
			break
		var a := Vector2(P.x, P.y + 8) if h.src < 0 else Vector2(G.storm.hops[h.src].x, G.storm.hops[h.src].y)
		out.append([Vector3(X(a.x), Y(a.y), 5), Vector3(X(h.x), Y(h.y), 5)])
	return out


func _update_storm() -> void:
	if not G.has("storm"):
		return
	var S: Dictionary = G.storm
	S.t += 1
	for h in S.hops:
		# the bolt follows its target while it lives
		var o: Dictionary = h.get("e", h.get("part", {}))
		if not o.is_empty() and not o.get("dead", false) and o.get("alive", true):
			h.x = o.x
			h.y = o.y
		if not h.hit and S.t >= h.at:
			h.hit = true
			if h.has("e"):
				if not h.e.get("dead", false):
					dmg_e(h.e, STORM_DMG)
			elif h.part.get("alive", true):
				boss_damage(h.part, STORM_DMG)
			spark(h.x, h.y)
			audio.play("small")
	if S.t >= STORM_LIFE:
		S.m.queue_free()
		G.erase("storm")


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
	_update_storm()


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


func _damage_target(t: Dictionary, d: float) -> void:
	if t.has("e"):
		dmg_e(t.e, d)
	elif t.has("part"):
		boss_damage(t.part, d)


func hurt() -> void:
	G.hits += 1
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
	G.hits += 1
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
	if G.has("run") and G.run.abort == 0:
		G.run.abort = 1


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
		if Vector2(b.x - pod.x, b.y - pod.y).length() < 5.5 and not b.get("dead", false):
			b.dead = true
			spark(b.x, b.y)
			shatter_gain(SHAT_BLOCK)
	if pod.ram_cd > 0:
		pod.ram_cd -= 1
	else:
		for e in G.enemies:
			if not e.ground and absf(e.x - pod.x) < e.hw + 4 and absf(e.y - pod.y) < e.hh + 4:
				dmg_e(e, 1)
				shatter_gain(SHAT_RAM + (SHAT_KILL if e.get("dead", false) else 0.0))
				pod.ram_cd = 8
				break
		for p in G.bparts:
			if p.kind != "shield" and Vector2(p.x - pod.x, p.y - pod.y).length() < p.r + 4:
				boss_damage(p, 1)
				shatter_gain(SHAT_RAM)
				pod.ram_cd = 8
				break
	if pod.fire_cd > 0:
		pod.fire_cd -= 1
	elif inp.fire and P.alive:
		shot(pod.x, pod.y + 5, 0, 5.5, Models.M.shot, 2)
		G.pb.back().pod = true
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
				if b.get("pod", false):
					shatter_gain(SHAT_SHOT + (SHAT_KILL if e.get("dead", false) else 0.0))
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
					if b.get("pod", false):
						shatter_gain(SHAT_SHOT)
				break
		# shots break on the rock walls (after hitting what sits on the cliff edge)
		if not b.get("dead", false) and in_rock(b.x, b.y, 0.0):
			b.dead = true
			spark(b.x, b.y)
	_sweep(G.pb)


func _update_beams() -> void:
	for b in G.beams:
		b.life -= 1
		if P.alive:
			b.x = P.x
			b.y0 = P.y + 6
		# the beam stops at the first barrier above the ship
		b.y1 = view.end.y + 4
		for bar in G.bars:
			if bar.y > b.y0 and bar.y < b.y1 and bar_solid(bar, b.x, bar.y, 0.0):
				b.y1 = bar.y
		b.len = b.y1 - b.y0
		var hw: float = b.w / 2.0
		for e in G.enemies:
			if _in_beam(b, e.x, e.y, e.hw, e.hh, hw):
				var key := "e%d" % e.id
				if not b.hit.has(key):
					b.hit[key] = G.t
					dmg_e(e, BEAM_DMG[b.lv])
		for p in G.bparts:
			if p.kind == "shield" or p.kind == "seg":
				continue
			if _in_beam(b, p.x, p.y, p.r, p.r, hw):
				var key := "p%d" % p.o.id
				if not b.hit.has(key):
					b.hit[key] = G.t
					boss_damage(p, BEAM_DMG[b.lv])
		if b.nova:
			for eb in G.eb:
				if _in_beam(b, eb.x, eb.y, 2.0, 0.0, hw):
					eb.dead = true
		if b.life <= 0:
			b.dead = true
	_sweep(G.beams)


## Whether something at (x, y), `rx` by `ry` half size, touches beam `b` (`hw` half wide). A beam
## runs straight up from (b.x, b.y0) for b.len.
func _in_beam(b: Dictionary, x: float, y: float, rx: float, ry: float, hw: float) -> bool:
	return absf(x - float(b.x)) < rx + hw and y > float(b.y0) - ry and y < float(b.y0) + float(b.len) + ry


func bullet(x: float, y: float, vx: float, vy: float) -> void:
	var m := Models.mesh(Models.geo("bo", func(): return Geo.octa(0.5)), Models.M.ebullet)
	m.scale = Vector3.ONE * 2.2
	m.add_child(Models.glow("ff9a3d", 2.2))
	world.add_child(m)
	G.eb.append({x = x, y = y, vx = vx, vy = vy, m = m})


## Enemy bullets get faster stage by stage and world by world.
func bspeed() -> float:
	return (1.0 + 0.03 * G.j + 0.07 * G.world) * tier_mul("bullet")


## How much the stage's tier (Normal, Nova, Supernova) scales `key`: bullet, fire, hp or score.
func tier_mul(key: String) -> float:
	return float(Progress.tier(G.get("tier", 0))[key])


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
		var walled := false
		for bar in G.bars:
			if bar_solid(bar, b.x, b.y, 0.5):
				walled = true
		if walled or b.x < view.position.x - 8 or b.x > view.end.x + 8 or b.y < view.position.y - 8 or b.y > view.end.y + 8 or in_rock(b.x, b.y, -1.0):
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
		"run":
			# skipped when the stage jumped past it (tests and tools set the scroll directly)
			if G.scroll < s.d - top() + 40.0:
				start_run()
		"end":
			G.ended = true
			G.boss_t0 = G.t
			G.end_kind = s.kind
			_spawn_end(s.kind)
		"prop":
			var pm := Models.prop(s.kind)
			pm.rotation.z = s.get("rot", 0.0)
			pm.scale = Vector3.ONE * 1.6
			world.add_child(pm)
			G.props.append({m = pm, x = s.x, wy = s.d, t = 0})
		"wallgun":
			E("wallgun", s.x, top() + 10, {wy = s.d})
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
		"shell", "hulk", "sentinel", "nest", "bulwark":
			E(s.type, _fit(s.x, s.d + 40, 12.0), top() + 14, {hold = 170.0})
		"flake":
			var fx0 := _fit(s.x, s.d, 18.0)
			E("flake", fx0, top() + 8, {x0 = fx0})
		"shards":
			for i in s.n:
				E("shard", _fit(s.x + (i - (s.n - 1) / 2.0) * 14.0, s.d, 6.0), top() + 8 + i * 16, {stop = H - 46.0 - i * 14.0, vy = -2.2, vx = 0.0, st = 0})
		"drones":
			for i in s.n:
				E("drone", _fit(s.x + (i - (s.n - 1) / 2.0) * 9.0, s.d, 6.0), top() + 8 + i * 14, {vy = -2.4, vx = 0.0, turn = 0})
		"seekers":
			for i in s.n:
				E("seeker", _fit(s.x + (i % 2 * 2 - 1) * 14.0, s.d, 6.0), top() + 8 + i * 18, {vx = 0.0, vy = -1.3})
		"wasps":
			for i in s.n:
				var wx := _fit(s.x + (i % 3 - 1) * 8.0, s.d, 14.0)
				E("wasp", wx, top() + 8 + i * 10, {x0 = wx, ph = i * 0.9, st = 0, vx = 0.0, vy = 0.0})
		"lancers":
			for i in s.n:
				E("lancer", _fit(16.0 + (W - 32.0) * float(i) / maxf(1, s.n - 1), s.d, 6.0), top() + 6, {st = 0, hold = 40 + i * 30, stop = H - 16.0 - i * 10.0, vx = 0.0, vy = 0.0})


## Moves a spawn x inside a canyon's passage at distance `d`, `pad` clear of the rock.
func _fit(x: float, d: float, pad: float) -> float:
	var w := VStage.walls(G.stage, d)
	if w.y - w.x < pad * 2.0:
		return (w.x + w.y) / 2.0
	return clampf(x, w.x + pad, w.y - pad)


## The end of a stage: "big:K" one big flyer of kind K grown into a mid-boss, "twins:K" a pair
## of them, "giant" the world's big flyer at boss size (worlds whose boss isn't ported yet),
## "bloom" the Bloom Mother.
func _spawn_end(kind: String) -> void:
	if kind == "bloom":
		spawn_boss()
		return
	if kind in ["prism", "queen", "titan", "bastion", "heart"]:
		spawn_gboss(kind)
		return
	var wd: Dictionary = VStage.WORLDS[G.world]
	var hk: float = 1.0 + 0.2 * G.world + 0.03 * G.j
	var parts := kind.split(":")
	var k: String = parts[1] if parts.size() > 1 else wd.big
	if parts[0] == "twins":
		E(k, 36, top() + 20, {boss = true, hp = 60.0 * hk, hold = 160.0})
		E(k, W - 36, top() + 30, {boss = true, hp = 60.0 * hk, hold = 175.0})
		hud.boss_name = VStage.BIG_NAMES[k][1]
	else:
		var giant := parts[0] == "giant"
		var sc := 1.9 if giant else 1.5
		E(k, W / 2, top() + 24, {boss = true, hp = (220.0 if giant else 110.0) * hk, hold = 160.0, sc = sc})
		hud.boss_name = Worlds.LIST[G.world].boss_name if giant else VStage.BIG_NAMES[k][0]
	_boss_warn()


func _boss_warn() -> void:
	audio.play("alarm")
	audio.music("boss")
	hud.banner("Warning", hud.boss_name + " approaching", 150)
	G.mid_boss = true


func E(type: String, x: float, y: float, o := {}) -> Dictionary:
	var d: Array = DEF[type]
	var hp := float(d[2]) if type in ["block", "carrier"] else ceilf(d[2] * (1.0 + 0.15 * G.get("world", 0)))
	var e := {id = uid(), type = type, x = x, y = y, hw = d[0], hh = d[1], hp = hp, max = hp, score = d[3], t = 0, cd = 60, flash = 0,
		ground = type in GROUND}
	e.merge(o, true)
	if type != "carrier":
		e.hp *= tier_mul("hp")
	e.max = e.hp
	# medal counts: generators and walls for Breaker, everything else that scores for Sweep
	if type == "block" or type == "generator":
		e.brk = true
		G.breakables = G.get("breakables", 0) + 1
	elif int(e.score) > 0:
		e.foe = true
		G.foes = G.get("foes", 0) + 1
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
		"wallgun":
			m = Models.wall_gun()
		"generator":
			m = Node3D.new()
			var gm := Models.generator(1)
			gm.rotation.x = -PI / 2
			m.add_child(gm)
		"carrier":
			m = Models.carrier(e.get("item", "L"))
			m.rotation.z = -PI / 2 if e.get("dir", 1.0) < 0 else PI / 2
		"block":
			m = Models.block(Models.M[Worlds.LIST[G.world].rock[0]])
		"hulk", "sentinel", "nest", "bulwark":
			# side-view models facing -x: turned to face down the screen
			m = Node3D.new()
			var bm: Node3D = Callable(Models, type).call()
			bm.rotation.z = PI / 2
			m.add_child(bm)
			m.set_meta("in", bm)
		"shard", "flake", "drone", "seeker", "wasp", "lancer":
			m = Node3D.new()
			var hm: Node3D = Callable(Models, type).call()
			m.add_child(hm)
			m.set_meta("in", hm)
	world.add_child(m)
	e.m = m
	if e.has("sc"):
		m.scale = Vector3.ONE * float(e.sc)
		e.hw *= e.sc
		e.hh *= e.sc
	# out of sight to start with, shadow and all: a flyer from above the screen (a group keeps
	# its spacing), a carrier from beside it; what the ground carries (`wy`) is built far ahead
	m.position = Vector3(X(e.x), Y(e.y), _ez(e))
	var box := _box(m, true)
	# it glides from there to where it used to appear, getting there when it used to (`due`),
	# and only then starts its moves: the waves keep their timing, the shadows lead the way in
	var at := Vector2(e.x, e.y)
	if type == "carrier":
		e.x = minf(e.x, _beside_x(box, _ez(e), -1.0)) if e.dir > 0 else maxf(e.x, _beside_x(box, _ez(e), 1.0))
	elif not e.has("wy") and e.y >= top():
		e.y += maxf(0.0, _above_y(box, _ez(e)) - top())
	if Vector2(e.x, e.y) != at:
		e.glide = at
		e.due = _due
	G.enemies.append(e)
	Diag.once("venemy " + type)
	return e


## Brings a wave's enemy in from out of sight to where its moves start, on time.
func _glide(e: Dictionary) -> void:
	var to: Vector2 = e.glide
	var d := Vector2(e.x, e.y).distance_to(to)
	var ticks := maxf(1.0, (float(e.due) - G.scroll - top() - 10.0) / SCROLL)
	var step := clampf(d / ticks, 0.5, GLIDE_MAX)
	if d <= step:
		e.x = to.x
		e.y = to.y
		e.erase("glide")
	else:
		var v := (to - Vector2(e.x, e.y)) / d * step
		e.x += v.x
		e.y += v.y


func _update_enemies() -> void:
	for e in G.enemies:
		if e.has("glide"):
			_glide(e)
			continue
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
			"shell", "hulk", "sentinel", "nest", "bulwark":
				_update_big(e)
			"shard":
				# glide in, stop, lock on, lunge
				match e.st:
					0:
						e.y += e.vy
						e.vy = minf(-0.3, e.vy * 0.985)
						if e.y <= e.stop:
							e.st = 1
							e.t = 0
					1:
						if e.t == 36:
							var a := atan2(P.y - e.y, P.x - e.x) if P.alive else -PI / 2
							e.vx = cos(a) * 3.0
							e.vy = sin(a) * 3.0
							e.st = 2
					_:
						e.x += e.vx
						e.y += e.vy
			"flake":
				# drifts down weaving, shedding a cross of bullets that turns each time
				e.y -= 0.6
				e.x = e.x0 + sin(e.t * 0.035) * 12.0
				if e.t % 95 == 60 and e.y < H - 6:
					var o := 0.0 if int(e.t / 95.0) % 2 else PI / 4.0
					for i in 4:
						var a := o + i * PI / 2.0
						bullet(e.x, e.y, cos(a) * 0.8 * bspeed(), sin(a) * 0.8 * bspeed())
			"drone":
				# dives in fast, swerves at the ship, then peels back up and away
				e.y += e.vy
				if e.t > 28:
					e.vy = minf(2.6, e.vy + 0.07)
					e.vx += (clampf(P.x - e.x, -1.0, 1.0) * 0.9 - e.vx) * 0.08
					if e.turn == 0:
						e.turn = 1
						aim(e.x, e.y, 1.1)
				e.x += e.vx
				if e.t > 60 and e.y > top() + 12:
					e.dead = true
			"seeker":
				# homes in with a limited turn, then gives up and flies on
				var cur := atan2(e.vy, e.vx)
				var want := atan2(P.y - e.y, P.x - e.x) if P.alive and e.t < 360 else cur
				var turn := clampf(wrapf(want - cur, -PI, PI), -0.035, 0.035)
				var sp := minf(1.5, 0.9 + e.t * 0.004)
				e.vx = cos(cur + turn) * sp
				e.vy = sin(cur + turn) * sp
				e.x += e.vx
				e.y += e.vy
				if e.t > 60 and e.y > top() + 12:
					e.dead = true
			"wasp":
				# buzzes down on a zigzag, then dives at the ship once
				if e.st == 0:
					e.y -= 1.5
					e.x = clampf(e.x0 + sin(e.t * 0.12 + e.ph) * 9.0, 4, W - 4)
					e.vy = -1.5
					if e.t == 50 + int(e.ph * 6.0) and P.alive:
						var a := atan2(P.y - e.y, P.x - e.x)
						e.vx = cos(a) * 2.2
						e.vy = sin(a) * 2.2
						e.st = 1
				else:
					e.x += e.vx
					e.y += e.vy
			"lancer":
				# drops in at the top, slides to line up with the ship, flares, then dashes down
				match e.st:
					0:
						e.y = lerpf(e.y, e.stop, 0.08)
						if P.alive:
							e.x += clampf(P.x - e.x, -0.9, 0.9)
						if e.t >= e.hold:
							e.st = 1
							e.t = 0
					1:
						if e.t > 24:
							e.st = 2
							Diag.once("vlancer dash")
					_:
						e.vy = maxf(-4.2, e.vy - 0.3)
						e.y += e.vy
			"turret", "wallgun":
				if e.y < H - 4 and e.y > 20:
					e.cd -= tier_mul("fire")
					if e.cd <= 0:
						aim(e.x, e.y, 1.15)
						e.cd = 110 if e.type == "turret" else 90
			"carrier":
				e.y = minf(e.y, H - 34)
				e.x += 0.7 * e.dir
				e.y -= 0.15
		# gone once out of sight, shadow and all, after it has been seen (or never will be)
		if _on_screen(_box(e.m), e.x, e.y, _ez(e)):
			e.seen = true
		elif e.get("seen", false) or e.t > 1500:
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


## Big flyers come down to `hold`, sway there firing their pattern, then leave down the screen
## (mid-bosses stay until destroyed).
func _update_big(e: Dictionary) -> void:
	var boss: bool = e.get("boss", false)
	if e.y > e.hold:
		e.y -= 0.8
		return
	e.x += sin(e.t * 0.012) * 0.35
	e.cd -= tier_mul("fire")
	if e.cd <= 0:
		match e.type:
			"shell":
				fan(e.x, e.y - 6, 1.0, 5 if boss else 3, 0.28)
				e.cd = 70 if boss else 110
				if boss and e.t % 4 == 0:
					ring(e.x, e.y, 10, 0.75)
			"hulk":
				fan(e.x, e.y - 8, 1.1, 7 if boss else 5, 0.22)
				e.cd = 60 if boss else 80
			"sentinel":
				e.n = e.get("n", 0) + 1
				if e.n % 2:
					ring(e.x, e.y, 14 if boss else 10, 0.75)
				else:
					fan(e.x, e.y - 8, 1.2, 3, 0.3)
				e.cd = 55 if boss else 70
			"nest":
				if G.enemies.size() < 40:
					for k in 3:
						E("wasp", e.x + (k - 1) * 8.0, e.y - 6, {x0 = e.x + (k - 1) * 8.0, ph = k * 1.3, st = 0, vx = 0.0, vy = 0.0, score = 0})
				if boss:
					aim(e.x, e.y, 1.2)
				e.cd = 80 if boss else 100
			"bulwark":
				e.n = e.get("n", 0) + 1
				ring(e.x, e.y - 4, 8 + (e.n % 2) * 4, 0.7)
				if boss:
					aim(e.x, e.y, 1.3)
				e.cd = 70 if boss else 90
	if not boss and e.t > 720:
		e.y -= 1.2


func dmg_e(e: Dictionary, d: float) -> void:
	if e.get("dead", false):
		return
	e.hp -= d * G.get("power", 1.0)
	e.flash = 3
	if e.hp <= 0:
		kill_e(e)
	else:
		audio.play("hit")


func kill_e(e: Dictionary) -> void:
	e.dead = true
	e.killed = true
	if e.get("brk", false):
		G.broken += 1
	elif e.get("foe", false):
		G.foes_killed += 1
	var big: bool = e.type in BIG
	boom(e.x, e.y, 14 if big else 6, big)
	audio.play("boom" if big else "small")
	if big:
		shake = maxf(shake, 7.0)
	add_score(e.score)
	if e.type == "carrier":
		drop_item(e.x, e.y, e.get("item", "L"))
	if e.type == "generator":
		for b in G.bars:
			if b.key == e.key:
				b.locked = false
				audio.play("pick")


func add_score(n: int) -> void:
	G.score += int(n * tier_mul("score"))


func drop_item(x: float, y: float, k: String) -> void:
	var m := Models.item(k)
	world.add_child(m)
	G.items.append({x = x, y = y, k = k, m = m})


func _update_items() -> void:
	for it in G.items:
		it.y -= 0.5
		if it.y < view.position.y and not _on_screen(_box(it.m), it.x, it.y, 0.0):
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
	var b := {wy = s.d, y = s.d - G.scroll, mode = s.mode, gx = s.gx, gx0 = s.gx, gw = s.gw, gw0 = s.gw, th = 8.0, key = s.key,
		locked = s.mode == "locked", nodes = [], ph = s.get("ph", 0.0)}
	var mat: Material = Models.M[Worlds.LIST[G.world].gate]
	# a full wall on each side of the opening, standing on the ground. The right one is turned
	# half a turn, not mirrored: a mirrored node showed the back faces of its deck (black).
	for k in 2:
		var half := Models.fort_wall(b.th, mat)
		if k == 1:
			half.rotation.z = PI
		world.add_child(half)
		b.nodes.append(half)
	var f := Models.mesh(Models.geo("vbar", func(): return Geo.box(1, 1, 1)), Models.M.field)
	f.set_meta("nf", true)
	world.add_child(f)
	b.nodes.append(f)
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
		elif b.mode == "shutter":
			# the opening closes and opens again on a cycle
			b.gw = b.gw0 * clampf(0.5 + sin(G.t * 0.022 + b.ph) * 1.4, 0.0, 1.0)
		if b.y < view.position.y and not _bar_shows(b):
			b.dead = true
			for n in b.nodes:
				n.queue_free()
	_sweep_bars()
	# outpost pieces on the ground scroll with it and go once they're off the bottom
	for pr in G.props:
		pr.t += 1
		if pr.wy - G.scroll < view.position.y and not _on_screen(_box(pr.m), pr.x, pr.wy - G.scroll, pr.m.position.z):
			pr.dead = true
			pr.m.queue_free()
	G.props = G.props.filter(func(pr): return not pr.get("dead", false))


## True when any of a barrier's walls (or their shadows) is on screen.
func _bar_shows(b: Dictionary) -> bool:
	for k in 2:
		var n: Node3D = b.nodes[k]
		if _on_screen(_box(n), W / 2.0 + n.position.x, b.y, 0.0):
			return true
	return false


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
	var hm := tier_mul("hp")
	for part in petals + [G.boss.core, G.boss.tent]:
		part.hp *= hm
		part.max = part.hp
	var n0 := world.get_child_count()
	G.boss.m = Models.boss(world)
	G.boss.m.rotation.z = PI / 2
	_place_boss(n0)


## Damage to a boss part; the ship's level scales it here, once, for every boss.
func boss_damage(part: Dictionary, d: float) -> void:
	d *= G.get("power", 1.0)
	var B: Dictionary = G.boss
	if B.is_empty() or B.dying:
		return
	if B.kind != "bloom":
		_gboss_damage(part.o, d)
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
	if B.kind != "bloom":
		_update_gboss(B)
		return
	if B.enter:
		# out of sight it hurries down; it comes into view at its slow pace
		B.y -= 0.5 if B.y < H + 60.0 else 2.0
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
			p.cd -= tier_mul("fire")
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
			T.cd -= tier_mul("fire")
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
	if B.kind != "bloom":
		B.m.queue_free()
		G.boss = {}
		G.bparts = []
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
	if G.boss_t0 >= 0:
		G.boss_ticks = G.t - G.boss_t0
	G.mid_boss = false
	hud.boss = -1.0
	add_score(G.lives * 2000)
	hud.banner("Stage clear", VStage.STAGES[G.stage].name, 170)
	audio.play("oneup")


# ---------- effects ----------

func glow_fx(color: String, x: float, y: float, z: float, s: float, life: int, vx := 0.0, vy := 0.0) -> void:
	var m := Models.glow(color, s)
	m.position = Vector3(X(x), Y(y), z)
	if G.has("run"):
		# glows are flat quads facing the top-down camera: stand them up for the chase view
		m.rotation.x = G.run.k * PI / 2.0
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
		var wj := VStage.walls(G.stage, c * CHUNK + CHUNK * j / rows - G.get("foff", 0.0))
		# wide screens show well past the stage's sides
		seen = seen or wj.x > view.position.x - 4.0 or wj.y < view.end.x + 4.0
	if not seen:
		n.free()
		return null
	var left := []
	var right := []
	for j in rows + 1:
		var ly := CHUNK * j / rows
		var d: float = c * CHUNK + ly - G.get("foff", 0.0)
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


# ---------- canyon run ----------

## The canyon's mouth has reached the top of the screen: clear the sky, then let it stream in.
func start_run() -> void:
	if run_b == null:
		return
	while not _run_built:
		_run_built = run_b.step()
	for e in G.enemies:
		if not e.get("boss", false):
			e.dead = true
			glow_fx("fff1d0", e.x, e.y, 4, 6, 10)
	for b in G.eb:
		b.dead = true
	_sweep(G.enemies)
	_sweep(G.eb)
	var n: Node3D = run_b.node
	n.visible = true
	# the canyon emerges from the moon: its floor rises out of the ground and its walls slide in
	# from far off the sides. Its bounding box (2,500 units of canyon) covers the screen from the
	# first frame, so the pop-in test can't judge it by its box; tests/run_test.gd checks the
	# mouth's timing and that it throws no shadow as it starts, and the stills are checked by eye
	n.set_meta("emerges", true)
	var motes := []
	for mo in VRun.motes():
		var m := Models.mesh(Models.geo("vshard", func(): return Geo.octa(1.6)), Models.M.crystal_c)
		m.position = VRun.warp(Vector3(VRun.sx(mo[1]), mo[0], mo[2]))
		n.add_child(m)
		motes.append({u = mo[0], x = mo[1], z = mo[2], m = m, got = false})
	# the canyon's mouth starts out of sight past the top, its shadows too
	# the mouth starts just above the screen. Not from the node's bounding box: the canyon's mesh
	# starts 300 units before its mouth (walls far off to the sides, floor under the moon), so its
	# box put the mouth ~600 units away and the stage stood still and empty for ~10 s
	G.run = {d = VRun.SHIP_Y - top() - 10.0, prev = 0.0, k = 0.0, node = n, motes = motes, hits = 0, got = 0, scrape = 0, abort = 0, cx = P.x}
	G.run.prev = G.run.d
	# the canyon's rock throws shadows only once the camera is half way round: its walls stand far
	# above the moon, and their shadows would otherwise drop onto the screen the instant it starts
	G.run.casters = []
	for ch in n.get_children():
		var gi := ch as GeometryInstance3D
		if gi and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			G.run.casters.append(gi)
	G.slow = 0
	P.z = 0.0
	P.vz = 0.0
	P.charge = 0
	P.ready_lv = 0
	if pod.get("state", "") == "out":
		pod.state = "back"
	hud.banner("Canyon run", "Drag up and down to climb and dive", 130)
	audio.play("alarm")
	Diag.note("RUN", "start")


## Moves the canyon past the ship and swings the camera behind it; ends the run at the exit.
func _update_run() -> void:
	var R: Dictionary = G.run
	var sp := VRun.speed(R.d)
	R.prev = R.d
	R.d += sp
	R.k = VRun.swing(R.d)
	if R.abort > 0:
		# the ship blew up: swing straight back to the top-down view
		R.abort += 1
		R.k = minf(R.k, 1.0 - float(R.abort) / 45.0)
		if R.abort >= 45:
			end_run(false)
			return
	# the moon floor scrolls with the canyon while it shows (before the swing and after it), at
	# the canyon's speed, which starts and ends at the stage's own
	if R.k < 0.97:
		G.foff = G.get("foff", 0.0) + sp
	if R.d >= VRun.LEN:
		end_run(true)


## Steering in the canyon: the thumb moves the ship sideways and, once the camera is behind it,
## up and down. Rock costs a hull point; skimming it pays; motes pay and show the way.
func _run_player() -> void:
	var R: Dictionary = G.run
	var k: float = R.k
	var g := lerpf(1.0, VRun.GAIN, k)
	P.x = clampf(P.x + inp.dx * g, 5, W - 5)
	P.vx = lerpf(P.vx, inp.dx * g, 0.3)
	P.y = lerpf(P.y, VRun.SHIP_Y, 0.06)
	if R.d < VRun.OUT and R.abort == 0:
		var dz: float = inp.dy * VRun.GAIN * smoothstep(0.3, 0.8, k)
		# the swoop down into the canyon on the way in rides on top of the steering
		dz += VRun.dive(R.d) - VRun.dive(R.prev)
		P.z = clampf(P.z + dz, VRun.ZMIN, VRun.ZMAX)
		P.vz = lerpf(P.vz, dz, 0.3)
	else:
		# the exit: the ship pulls up out of the canyon and settles onto the play plane
		P.z = lerpf(P.z, VRun.lift(R.d), 0.06)
		P.vz = lerpf(P.vz, 0.0, 0.3)
	var what := VRun.hit(P.x, P.z, R.prev, R.d, VRun.PAD)
	if what != "" and P.inv <= 0:
		R.hits += 1
		hurt()
		_run_spark(P.x, P.z, 6.0)
		Diag.once("run hit " + what)
	# never inside the walls
	var p := VRun.passage(R.d)
	P.x = clampf(P.x, p.x - p.y + VRun.PAD + 0.2, p.x + p.y - VRun.PAD - 0.2)
	P.scrape = k > 0.5 and P.inv <= 0 and VRun.clearance(P.x, P.z, R.d) < VRun.SCRAPE
	if P.scrape and G.t % 6 == 0:
		add_score(10)
		R.scrape += 10
		_run_spark(P.x + randf_range(-3, 3), P.z - 1.5, 2.5)
	for mo in R.motes:
		if mo.got or mo.u > R.d or mo.u < R.prev - 1.0:
			continue
		if Vector2(mo.x - P.x, mo.z - P.z).length() < 5.0:
			mo.got = true
			mo.m.visible = false
			R.got += 1
			add_score(50)
			audio.play("pick")
			_run_spark(mo.x, mo.z, 4.0)


func _run_spark(x: float, z: float, s: float) -> void:
	glow_fx("fff1d0", x, VRun.SHIP_Y + 4.0, z, s, 9)


## Out of the canyon (or blown up in it): back to the stage, medal and reward for a finished run.
## Gold (no touch) also fills the ultimate, silver half fills it.
func end_run(done: bool) -> void:
	var R: Dictionary = G.run
	R.node.queue_free()
	run_b = null
	G.erase("run")
	P.z = 0.0
	P.vz = 0.0
	if not done:
		G.run_medal = -1
		Diag.note("RUN", "failed")
		return
	var m := mini(R.hits, 2)
	G.run_medal = m
	add_score(VRun.MEDALS[m][1])
	var sub := "%d/%d motes · +%s" % [R.got, R.motes.size(), fmt(VRun.MEDALS[m][1] + R.got * 50 + R.scrape)]
	hud.banner("%s run" % VRun.MEDALS[m][0], sub, 200)
	audio.play("oneup")
	Diag.note("RUN", "done hits=%d motes=%d" % [R.hits, R.got])


## Places the canyon, builds it ahead of time, and hides what the chase view shouldn't see.
func _sync_run() -> void:
	if run_b != null and not _run_built:
		_run_built = run_b.step()
	var k: float = G.run.k if G.has("run") else 0.0
	for c in chunks.values():
		c.visible = k < 0.97
	for ch in ship_m.get_children():
		if ch.has_meta("nf"):
			ch.rotation.x = k * PI / 2.0
	# climbing tips the nose up, diving tips it down
	ship_m.rotation.x = clampf(P.get("vz", 0.0) * 0.12, -0.5, 0.5) * k
	if not G.has("run"):
		return
	var R: Dictionary = G.run
	# the canyon turns under the ship: the point of its centre line level with the ship sits on
	# the screen's centre line, and the canyon there runs straight up the screen (the gameplay
	# stays in canyon coordinates, so the camera, steering and rock all follow the bends)
	var h := VRun.heading(R.d)
	var at := Transform3D(Basis(Vector3.BACK, -h), Vector3(0, Y(VRun.SHIP_Y), 0))
	R.node.transform = at * Transform3D(Basis(), -Vector3(VRun.centre(R.d).x, VRun.centre(R.d).y, 0))
	# the ship banks into a bend
	var turn := VRun.heading(R.d + VRun.speed(R.d)) - h
	R.bank = lerpf(R.get("bank", 0.0), clampf(-turn * 30.0, -0.5, 0.5) * R.k, 0.15)
	# a gap's glow goes out once the ship is through and the camera reaches it, or the camera
	# would fly through the glow and wash out the screen
	# and a bridge, ridge or window goes once the camera reaches it (the ship is long through): from
	# under a bridge it would hide the ship climbing out beyond it
	for gl in R.node.get_children():
		if gl.has_meta("gap_u"):
			gl.visible = R.d - 38.0 < float(gl.get_meta("gap_u")) - 16.0
		elif gl.has_meta("obs_u"):
			var ou: float = gl.get_meta("obs_u")
			# (its glowing seams sit 2.6 in front of it)
			gl.visible = R.d - 38.0 < ou - VRun.DEPTH / 2.0 - 4.5
			# once the ship is through, the rock between it and the camera fades like glass
			var fade := clampf((R.d - ou - VRun.DEPTH / 2.0) / 10.0, 0.0, 1.0) * 0.8
			var mat := (gl as MeshInstance3D).material_override as BaseMaterial3D
			if mat:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade > 0.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
				mat.albedo_color.a = 1.0 - fade
	for gi in R.casters:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if R.k > 0.5 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mo in R.motes:
		if not mo.got:
			mo.m.rotation = Vector3(tt * 0.04, tt * 0.06, 0)


func _camera_reset() -> void:
	camera.transform = Transform3D(Basis(), Vector3(0, 0, CAM_D))
	camera.fov = _fov_td
	camera.near = 10.0
	_env.fog_light_color = Color(look.fog)
	_env.fog_depth_begin = CAM_D + 30.0
	_env.fog_depth_end = CAM_D + 210.0


## Where the chase camera at canyon (x, z) must go to stay out of obstacle `o`'s rock (with 3
## units to spare), as it passes it.
static func _cam_dodge(o: Dictionary, c: Vector2) -> Vector2:
	match o.k:
		"pillar", "mesa":
			var px: float = VRun.passage(o.u).x + o.dx
			var room: float = o.r + 3.0
			if absf(c.x - px) < room:
				c.x = px - room if c.x < px else px + room
		"arch":
			c.y = minf(c.y, VRun.under(o, c.x) - 3.0)
		"spine":
			c.y = maxf(c.y, VRun.crest(o, c.x) + 3.0)
		"window":
			# into the oval hole, 3 units in from its rim
			var h := VRun.hole(o)
			var e := VRun.oval(o, c.x, c.y, 3.0)
			if e > 1.0:
				c = h + (c - h) / e
	return c


## A camera basis looking along `dir` with its up in the plane of +Y and +Z, so it never rolls
## while it swings from looking down (up = +Y) to looking along the canyon (up = +Z).
static func _aim(dir: Vector3) -> Basis:
	var f := dir.normalized()
	return Basis.looking_at(f, Vector3.RIGHT.cross(f))


## The sun's shadow map for the view. Top-down, one orthogonal map covers the whole screen
## evenly. Behind the ship, the view runs hundreds of units down the canyon, and one map stretched
## over all of it made the near shadows soft, blocky and pale next to the top-down ones
## (Guillaume, 2026-11-21: shadows must look the same in both views). So once the camera swings
## past half way the map splits by distance: the nearest split, round the ship, is as sharp as the
## top-down map, and the far ones still shade the canyon down to the fog.
func _sun_shadows(k: float) -> void:
	var pov := k > 0.5
	var mode := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if pov else DirectionalLight3D.SHADOW_ORTHOGONAL
	if sun.directional_shadow_mode == mode:
		return
	sun.directional_shadow_mode = mode
	if pov:
		sun.directional_shadow_max_distance = 640.0
		sun.directional_shadow_split_1 = 0.08
		sun.directional_shadow_split_2 = 0.2
		sun.directional_shadow_split_3 = 0.45
		sun.directional_shadow_blend_splits = true
	else:
		sun.directional_shadow_max_distance = CAM_D + 260.0


## Top-down, or swung down behind the ship during the canyon run (`k` of the way).
func _camera(j: Vector3) -> void:
	var k: float = G.run.k if G.has("run") else 0.0
	_sun_shadows(k)
	if k <= 0.0:
		_camera_reset()
		camera.position += j
		return
	var R: Dictionary = G.run
	# the camera trails the ship sideways, a little towards the passage's middle
	# (no more than 6 units off the ship, or in the wide basin it would leave the ship off screen)
	R.cx = lerpf(R.cx, P.x + clampf((VRun.passage(R.d).x - P.x) * 0.3, -5.0, 5.0), 0.2)
	var t := Vector3(X(R.cx), Y(VRun.SHIP_Y), P.get("z", 0.0) * 0.85)
	# the camera rides 38 units behind the ship, so it passes each column, bridge, ridge and
	# window after the ship has: it steps round a column, ducks under a bridge and lifts over a
	# ridge or into a hole as it goes through, instead of flying into the rock. It eases into the
	# dodge as the rock nears and holds it hard while inside the rock's depth
	var cz := t.z + 19.0
	var cx: float = R.cx
	var cu: float = R.d - 38.0
	var want := Vector2(cx, cz)
	for o in VRun.OBS:
		var gap := absf(o.u - cu) - VRun.half(o)
		if gap > 30.0:
			continue
		want = _cam_dodge(o, want)
	R.cdx = lerpf(R.get("cdx", 0.0), want.x - cx, 0.25)
	R.cdz = lerpf(R.get("cdz", 0.0), want.y - cz, 0.25)
	var cam := Vector2(cx + R.cdx, cz + R.cdz)
	for o in VRun.OBS:
		if absf(o.u - cu) - VRun.half(o) < 2.0:
			cam = _cam_dodge(o, cam)
	R.cz = cam.y
	R.cam_x = cam.x
	# it looks ahead of the ship itself, so a camera stepped aside round a column (or lagging a
	# big swing across the canyon) still keeps the ship near the middle of the screen
	var aim_at := Vector3(lerpf(t.x, X(P.x), 0.6), t.y + 70.0, t.z + 9.0)
	var chase := Transform3D(Basis(), Vector3(X(R.cam_x), t.y - 38.0, R.cz)).looking_at(aim_at, Vector3.BACK)
	var td := Transform3D(Basis(), Vector3(0, 0, CAM_D))
	# The swing orbits the ship rather than sliding between the two cameras: a straight slide
	# looks past the ship halfway and drops it off the bottom of the screen for about a second.
	# The camera circles over the ship from above to behind it, and the ship's place on screen
	# moves only from where it sat top-down to where it sits in the chase view.
	var s := Vector3(X(P.x), Y(P.y), P.get("z", 0.0))
	var o0 := td.origin - s
	var o1 := chase.origin - s
	var o := o0.normalized().slerp(o1.normalized(), k) * lerpf(o0.length(), o1.length(), k)
	var off0 := Quaternion(_aim(-o0).inverse() * td.basis)
	var off1 := Quaternion(_aim(-o1).inverse() * chase.basis)
	camera.transform = Transform3D(_aim(-o) * Basis(off0.slerp(off1, k)), s + o + j * 0.5)
	var wide := 80.0 if camera.keep_aspect == Camera3D.KEEP_WIDTH else 62.0
	# the swings have some swagger: the camera rolls into them and the view widens mid-swing (the
	# roll turns round the camera's own axis, so the ship keeps its place on screen near enough)
	var swing := sin(PI * k)
	var roll := swing * 0.2 * (1.0 if R.d < VRun.LEN / 2.0 else -1.0)
	camera.transform.basis = camera.transform.basis * Basis(Vector3.BACK, roll)
	camera.fov = lerpf(_fov_td, wide, k) + swing * 10.0
	camera.near = lerpf(10.0, 1.5, k)
	_env.fog_depth_begin = lerpf(CAM_D + 30.0, 140.0, k)
	# the depth of the canyon glows, so near rock stands dark against it and every way through
	# shows as the bright part ahead
	_env.fog_light_color = Color(look.fog).lerp(Color("4a3590"), k)
	_env.fog_depth_end = lerpf(CAM_D + 210.0, 520.0, k)


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
	# the floor keeps the distance the canyon run added (`foff`), so it never jumps back
	update_chunks(G.scroll + G.get("foff", 0.0))
	_sync_run()
	for isl in G.islands:
		isl.m.position = Vector3(0, isl.d - G.scroll - H / 2.0, -7.0)
		isl.m.visible = not G.has("run") and _on_screen(_box(isl.m), W / 2.0, isl.d - G.scroll, -7.0)
	hud.score = fmt(G.score)
	hud.hull = P.hull if P.alive else 0
	hud.ships = maxi(0, G.lives - 1) if P.alive else maxi(0, G.lives)
	hud.ult_ready = G.ult_t == 0
	hud.charge = float(P.charge) / ULT_AT if G.ship != "warden" else P.get("shat", 0.0) / SHATTER_FULL
	hud.pod_out = pod.get("state", "") == "out"
	hud.charge_lv = charge_lv(P.charge)
	hud.charge_marks = [float(CHARGE_AT[1]) / ULT_AT, float(CHARGE_AT[2]) / ULT_AT, float(CHARGE_AT[3]) / ULT_AT, float(CHARGE_MAX) / ULT_AT]
	hud.queue_redraw()
	# the ship banks as it slides sideways and blinks while invincible
	ship_m.visible = P.alive and not (P.inv > 2 and (tt >> 2) % 2 and G.ult_t == 0)
	ship_m.position = Vector3(X(P.x), Y(P.y), P.get("z", 0.0))
	var mdl: Node3D = ship_m.get_meta("model")
	var bank: float = G.run.get("bank", 0.0) if G.has("run") else 0.0
	(mdl.get_meta("body") as Node3D).rotation.x = clampf(P.vx * 0.35 + bank, -0.8, 0.8)
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
		pod_m.position = Vector3(X(pod.x), Y(pod.y), 1 + P.get("z", 0.0))
		var pmdl: Node3D = pod_m.get_meta("model")
		(pmdl.get_meta("spin") as Node3D).rotation.x += 0.08 if pod.state == "dock" else 0.25
	for e in G.enemies:
		_sync_e(e)
	for b in G.bars:
		_sync_bar(b)
	for pr in G.get("props", []):
		_sync_prop(pr)
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
	if G.has("storm"):
		VFx.sync_storm(G.storm.m, _storm_points(), G.storm.t, STORM_LIFE, tt)
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
	_camera(j)


# ---------- nothing pops in ----------
# Everything enters the screen across an edge, shadow included. The low sun throws shadows far
# down the screen, the ground sits deeper than the play plane (so it shows more of the stage
# than the play plane does), and models are bigger than their hit boxes: so where a model may
# appear is worked out from its meshes, its height and the sun, never from a fixed margin.

## Shadows land no lower than this: the bottom of the rolling floor.
const FLOOR_Z := GROUND_Z - 50.0 - 8.0
## How far ahead of the screen's top the stage builds what sits on the ground (it has to be in
## place, out of sight, before the screen reaches it).
const BUILD_AHEAD := 220.0
## How much sooner than before a wave is sent: it starts out of sight, shadow and all, and
## glides in to where it used to appear (see `_glide`).
const WAVE_LEAD := 70.0
## The fastest an enemy glides in (when it's late, after the canyon run or at a stage's end).
const GLIDE_MAX := 3.0
## The script distance of what's being sent now (-INF: sent by the game itself).
var _due := -INF
## What the ground carries, built ahead.
const GROUND_PIECES := ["barrier", "prop", "wallgun", "turret", "generator"]


## The boxes `nodes` fill around world point `at`: [everything, what casts a shadow]. `turns`
## widens them to the ball the model sweeps, for models that spin or tumble.
func _boxes(nodes: Array, at: Vector3, turns := false) -> Array:
	var all := AABB(Vector3.ZERO, Vector3.ZERO)
	var cast := AABB(Vector3.ZERO, Vector3.ZERO)
	var stack := nodes.duplicate()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_inside_tree():
			continue
		var a := gi.get_aabb()
		if a.size == Vector3.ZERO:
			continue
		var g := gi.global_transform * a
		g.position -= at
		all = all.merge(g)
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			cast = cast.merge(g)
	if turns:
		for k in 2:
			var b: AABB = [all, cast][k]
			var r := 0.0
			for i in 8:
				r = maxf(r, b.get_endpoint(i).length())
			b = AABB(Vector3.ONE * -r, Vector3.ONE * 2.0 * r) if b.size != Vector3.ZERO else b
			if k == 0:
				all = b
			else:
				cast = b
	return [all, cast]


## The model's boxes, worked out once (kept on the node).
func _box(m: Node3D, turns := false) -> Array:
	if not m.has_meta("box"):
		m.set_meta("box", _boxes([m], m.global_position, turns))
	return m.get_meta("box")


## Where a model's corners and their shadows show: each point (dx, dy, k) shows at stage
## (W/2 + (X + dx) * k, H/2 + (Y + dy) * k) for a model at world (X, Y) and height `z`.
func _reach(box: Array, z: float) -> Array:
	var out := []
	for i in 8:
		var c: Vector3 = box[0].get_endpoint(i)
		out.append(Vector3(c.x, c.y, CAM_D / (CAM_D - z - c.z)))
	if box[1].size != Vector3.ZERO:
		for i in 8:
			var c: Vector3 = box[1].get_endpoint(i)
			if z + c.z > FLOOR_Z:
				var t := (FLOOR_Z - z - c.z) / sun_dir.z
				out.append(Vector3(c.x + sun_dir.x * t, c.y + sun_dir.y * t, CAM_D / (CAM_D - FLOOR_Z)))
	return out


## The part of the stage a model at stage (x, y), height `z`, covers on screen, shadow and all.
func _foot(box: Array, x: float, y: float, z: float) -> Rect2:
	var r := Rect2()
	var first := true
	for p in _reach(box, z):
		var q := Vector2(W / 2.0 + (X(x) + p.x) * p.z, H / 2.0 + (Y(y) + p.y) * p.z)
		r = Rect2(q, Vector2.ZERO) if first else r.expand(q)
		first = false
	return r


## True when any of a model or its shadow is on screen.
func _on_screen(box: Array, x: float, y: float, z: float) -> bool:
	return _foot(box, x, y, z).intersects(view.grow(1.0))


## The lowest stage y where a model at height `z` is wholly above the screen, shadow and all.
func _above_y(box: Array, z: float) -> float:
	var y := -INF
	for p in _reach(box, z):
		y = maxf(y, H / 2.0 + (view.end.y - H / 2.0) / p.z - p.y)
	return y + 2.0


## The highest stage y where a model at height `z` is wholly below the screen.
func _below_y(box: Array, z: float) -> float:
	var y := INF
	for p in _reach(box, z):
		y = minf(y, H / 2.0 + (view.position.y - H / 2.0) / p.z - p.y)
	return y - 2.0


## The stage x just past the screen's left (`side` -1) or right (+1) edge for a model at height
## `z`, shadow and all.
func _beside_x(box: Array, z: float, side: float) -> float:
	var x := INF * side * -1.0
	for p in _reach(box, z):
		if side < 0:
			x = minf(x, W / 2.0 + (view.position.x - W / 2.0) / p.z - p.x)
		else:
			x = maxf(x, W / 2.0 + (view.end.x - W / 2.0) / p.z - p.x)
	return x + 2.0 * side


## Where the ship comes in from: below the screen, with its pod.
func _ship_entry_y() -> float:
	var y := _below_y(_box(ship_m, true), 0.0)
	if pod_m != null and is_instance_valid(pod_m) and pod_m.is_inside_tree():
		y = minf(y, _below_y(_box(pod_m, true), 0.0) - 10.0)
	return minf(-12.0, y)


func _ez(e: Dictionary) -> float:
	return 5.0 if e.type == "wallgun" else (-4.0 if e.ground else 0.0)


func _sync_e(e: Dictionary) -> void:
	var m: Node3D = e.m
	m.position = Vector3(X(e.x), Y(e.y), _ez(e))
	Models.set_flash(m, e.flash > 0)
	match e.type:
		"drifter":
			m.rotation = Vector3(e.t * 0.03, e.t * 0.05, 0)
		"turret":
			if P.alive:
				m.rotation.z = atan2(P.y - e.y, P.x - e.x)
		"wallgun":
			if P.alive:
				(m.get_meta("piv") as Node3D).rotation.z = atan2(P.y - e.y, P.x - e.x) - PI / 2
		"carrier":
			for w in m.get_meta("w"):
				w.rotation.x = sin(e.t * 0.3) * 0.5
		"shard", "drone", "seeker", "lancer":
			# the models point along +x: turn them to their heading
			var hv := Vector2(e.vx, e.vy)
			if e.type == "shard" and e.st == 1 and P.alive:
				hv = Vector2(P.x - e.x, P.y - e.y)
			elif e.type == "lancer":
				hv = Vector2(0, -1)
			elif hv.length() < 0.01:
				hv = Vector2(0, -1)
			m.rotation.z = hv.angle()
			var inner: Node3D = m.get_meta("in")
			if e.type == "shard":
				inner.rotation.x = e.t * 0.1
			elif e.type == "lancer":
				inner.rotation.x = e.t * 0.08 if e.st < 2 else 0.0
				(inner.get_meta("flame") as Node3D).scale = Vector3.ONE * (2.2 if e.st == 2 else (1.0 + sin(e.t * 0.6) * 0.3))
		"wasp":
			m.rotation.z = Vector2(e.vx, e.vy).angle() if e.st == 1 else -PI / 2 + sin(e.t * 0.12) * 0.3
			var wings: Array = (m.get_meta("in") as Node3D).get_meta("wings")
			for i in wings.size():
				wings[i].rotation.x = (0.5 + sin(e.t * 1.3) * 0.5) * (1.0 if i == 0 else -1.0)
		"flake":
			m.rotation.z = e.t * 0.04
			m.rotation.y = sin(e.t * 0.03) * 0.4
		"hulk", "nest", "bulwark":
			m.rotation.y = sin(e.t * 0.02) * 0.25
		"sentinel":
			m.rotation.y = sin(e.t * 0.02) * 0.25
			((m.get_meta("in") as Node3D).get_meta("ring") as Node3D).rotation.z = e.t * 0.03


func _sync_prop(pr: Dictionary) -> void:
	var m: Node3D = pr.m
	m.position = Vector3(X(pr.x), Y(pr.wy - G.scroll), GROUND_Z - 50.0 + Terrain.height(X(pr.x), pr.wy))
	if m.has_meta("spin"):
		(m.get_meta("spin") as Node3D).rotation.z = pr.t * 0.02
	if m.has_meta("blink"):
		(m.get_meta("blink") as Node3D).visible = pr.t % 60 < 30


func _sync_bar(b: Dictionary) -> void:
	var n: Array = b.nodes
	var left: float = b.gx - b.gw / 2.0
	var right: float = b.gx + b.gw / 2.0
	n[0].position = Vector3(X(left), Y(b.y), 0)
	n[1].position = Vector3(X(right), Y(b.y), 0)
	n[2].visible = b.locked
	n[2].position = Vector3(X(b.gx), Y(b.y), 0)
	n[2].scale = Vector3(maxf(0.1, b.gw), b.th * 0.6, 4)


func _sync_beam(b: Dictionary) -> void:
	var len: float = maxf(1.0, b.get("len", b.y1 - b.y0))
	var fade: float = clampf(float(b.life) / 6.0, 0.0, 1.0)
	var w: float = b.w * fade
	b.m.position = Vector3(X(b.x), Y(b.y0), 3)
	var age: int = BEAM_LIFE[b.lv] - b.life
	VFx.sync_beam(b.m, b.lv, len, w, fade, age, tt, b.y1 < view.end.y)


func _sync_boss() -> void:
	var B: Dictionary = G.boss
	if B.kind != "bloom":
		_sync_gboss(B)
		return
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
		# the last segment sits inside the tip: it stays shown, so it can't pop up when the tip goes
		m.visible = i < T.n
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


# ---------- the world bosses of worlds 2 to 6 ----------
# Ported from the landscape game (git history before 2026-11-17, main.gd `spawn_gboss`), turned
# so the boss sits at the top of the screen and faces down. Each is a set of parts: guards or
# guns to break first, armour that only blocks, and a core that kills it.

func _part(key: String, hp: float, r: float, o := {}) -> Dictionary:
	var p := {id = uid(), key = key, hp = hp, max = hp, r = r, alive = true, flash = 0, x = 0.0, y = 0.0, core = false, armour = false, cd = 0, burst = 0}
	p.merge(o, true)
	return p


func spawn_gboss(kind: String) -> void:
	var k: float = 1.0 + 0.15 * G.world
	var B := {kind = kind, x = W / 2.0, y = top() + 60.0, t = 0, bt = 0, enter = true, phase2 = false, phase3 = false, dying = 0, lid = 0.0,
		open = false, parts = {}, rot = 0.0}
	var list: Array = []
	var n0 := world.get_child_count()
	match kind:
		"prism":
			B.home = H - 48.0
			list = [_part("top", 26 * k, 7.5, {oy = -27.0, cd = 70}), _part("bot", 26 * k, 7.5, {oy = 27.0, cd = 145}),
				_part("core", 90 * k, 10.0, {core = true, armour = true})]
			B.m = Models.boss_prism(world)
		"titan":
			B.home = H - 36.0
			list = [_part("hullA", 9999, 13.0, {armour = true, oy = -12.0}), _part("hullB", 9999, 13.0, {armour = true, oy = 12.0}),
				_part("top", 30 * k, 7.0, {oy = -28.0, cd = 90}), _part("bot", 30 * k, 7.0, {oy = 28.0, cd = 150}),
				_part("core", 120 * k, 7.5, {core = true, armour = true})]
			B.m = Models.boss_titan(world)
		"queen":
			B.home = H - 52.0
			list = [_part("top", 28 * k, 9.0, {oy = -25.0, cd = 80}), _part("bot", 28 * k, 9.0, {oy = 25.0, cd = 145}),
				_part("sac", 40 * k, 11.0, {cd = 120}), _part("core", 110 * k, 8.5, {core = true, armour = true})]
			B.m = Models.boss_queen(world)
		"bastion":
			B.home = H - 48.0
			for i in 4:
				list.append(_part("p%d" % i, 9999, 7.0, {armour = true, i = i}))
			for i in 4:
				list.append(_part("g%d" % i, 16 * k, 5.5, {i = i, oy = [-44.0, -22.0, 22.0, 44.0][i], cd = 60 + i * 30}))
			list.append(_part("core", 150 * k, 9.0, {core = true}))
			B.m = Models.boss_bastion(world)
		_:
			B.home = H - 62.0
			for i in 8:
				list.append(_part("n%d" % i, 10 * k, 5.0, {i = i, cd = 60 + i * 17}))
			list.append(_part("core", 160 * k, 12.0, {core = true, armour = true}))
			B.m = Models.boss_heart(world)
	# the side-view model faces -x: a quarter turn makes it face down the screen
	B.m.rotation.z = PI / 2
	for p in list:
		B.parts[p.key] = p
	B.list = list
	G.boss = B
	audio.music("final" if kind == "heart" else "boss")
	audio.play("alarm")
	hud.boss_name = Worlds.LIST[G.world].boss_name
	hud.banner("Warning", hud.boss_name + " approaching", 150)
	Diag.once("vboss " + kind)
	_place_boss(n0)


## Lays a boss's parts out round it and starts it high enough to come down into view whole,
## shadows and all. `n0`: the world's child count before its models were added.
func _place_boss(n0: int) -> void:
	var B: Dictionary = G.boss
	var nodes := world.get_children().slice(n0)
	for k in 2:
		# coming in, a boss only moves and lays its parts out: nothing fires yet
		var y0: float = B.y
		var t0: int = B.t
		if B.kind == "bloom":
			update_boss()
		else:
			_update_gboss(B)
		B.y = y0
		B.t = t0
		_sync_boss()
		if k == 0:
			var box := _boxes(nodes, Vector3(X(B.x), Y(B.y), 0.0))
			B.y = maxf(B.y, _above_y(box, 0.0))


func _gboss_damage(p: Dictionary, d: float) -> void:
	var B: Dictionary = G.boss
	if B.dying or p.armour or not p.alive:
		return
	p.hp -= d
	p.flash = 3
	if p.hp > 0:
		audio.play("hit")
		return
	if p.core:
		B.dying = 1
		add_score(10000 + 3000 * G.world)
		for b in G.eb:
			b.dead = true
		audio.play("boom")
		shake = 16.0
	else:
		p.alive = false
		boom(p.x, p.y, 9, true)
		audio.play("boom")
		shake = maxf(shake, 6.0)
		add_score(1500)


func _update_gboss(B: Dictionary) -> void:
	if B.enter:
		B.y -= 0.5 if B.y < top() + 60.0 else 2.0
		if B.y <= B.home:
			B.y = B.home
			B.enter = false
	else:
		B.bt += 1
	var P2: Dictionary = B.parts
	for p in B.list:
		if p.flash:
			p.flash -= 1
	match B.kind:
		"prism":
			# two crystal guards fire bursts; once both are gone the core spins out spirals
			if not B.enter:
				B.x = W / 2.0 + sin(B.bt * 0.012) * 16.0
				B.y = B.home + sin(B.bt * 0.007) * 8.0
			var guards := 0
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				p.y = B.y - 2.0
				p.x = B.x + p.oy * (1.0 + 0.08 * sin(B.t * 0.05))
				if not p.alive:
					continue
				guards += 1
				if B.enter:
					continue
				p.cd -= tier_mul("fire")
				if p.cd <= 0 and p.burst == 0:
					p.burst = 5
					p.cd = 150
				if p.burst > 0 and B.t % 6 == 0:
					aim(p.x, p.y - 4, 1.7)
					p.burst -= 1
			var c: Dictionary = P2.core
			c.x = B.x
			c.y = B.y
			c.armour = guards > 0
			if guards == 0:
				if not B.phase2:
					B.phase2 = true
					audio.play("alarm")
				var cyc: int = B.t % 300
				if cyc < 130 and B.t % 7 == 0:
					var a: float = B.t * 0.11
					for j in 3:
						bullet(c.x, c.y, cos(a + j * TAU / 3.0) * 0.85 * bspeed(), sin(a + j * TAU / 3.0) * 0.85 * bspeed())
				if cyc == 200:
					fan(c.x, c.y - 8, 1.3, 5, 0.2)
				if B.t % 360 == 300:
					for j in 2:
						E("shard", c.x + (j * 2 - 1) * 14.0, c.y - 6, {stop = c.y - 50.0 - j * 20.0, vy = -1.6, vx = 0.0, st = 0, score = 0})
			elif not B.enter and B.t % 260 == 130:
				ring(c.x, c.y, 8, 0.7)
		"titan":
			# two guns on the flanks; the furnace hatch opens on a cycle, longer once the guns are gone
			if not B.enter:
				B.x = W / 2.0 + sin(B.bt * 0.01) * 14.0
			var guns := 0
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				p.y = B.y - 14.0
				p.x = B.x + p.oy
				if not p.alive:
					continue
				guns += 1
				if B.enter:
					continue
				p.cd -= tier_mul("fire")
				if p.cd <= 0:
					fan(p.x, p.y - 6, 1.1, 3, 0.24)
					p.cd = 110
			for key in ["hullA", "hullB"]:
				var p: Dictionary = P2[key]
				p.y = B.y + 4.0
				p.x = B.x + p.oy
			var c: Dictionary = P2.core
			c.y = B.y - 16.0
			c.x = B.x
			var cyc: int = B.t % 280
			var was: bool = B.open
			B.open = not B.enter and (cyc > 40 and cyc < 220 if guns == 0 else cyc > 70 and cyc < 180)
			c.armour = not B.open
			if B.open and not was:
				ring(c.x, c.y, 12, 0.8)
				for j in 2:
					E("drone", c.x + (j * 2 - 1) * 10.0, c.y - 4, {vy = -2.0, vx = 0.0, turn = 0, score = 0})
			if B.open and cyc % 40 == 20:
				aim(c.x, c.y - 4, 1.4)
			B.lid += ((1.0 if B.open else 0.0) - B.lid) * 0.15
		"queen":
			# wings fan bullets, the sac hatches wasps; with the wings gone the head opens up
			if not B.enter:
				B.x = W / 2.0 + sin(B.bt * 0.014) * 20.0
				B.y = B.home + sin(B.bt * 0.009) * 10.0
			var wings := 0
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				p.y = B.y + 2.0
				p.x = B.x + p.oy + sin(B.t * 0.3) * 1.5
				if not p.alive:
					continue
				wings += 1
				if B.enter:
					continue
				p.cd -= tier_mul("fire")
				if p.cd <= 0:
					fan(p.x, p.y - 4, 1.0, 5, 0.22)
					p.cd = 130
			var sac: Dictionary = P2.sac
			sac.y = B.y + 16.0
			sac.x = B.x
			if sac.alive and not B.enter:
				sac.cd -= tier_mul("fire")
				if sac.cd <= 0 and G.enemies.size() < 30:
					for j in 3:
						var wx: float = sac.x + (j - 1) * 10.0
						E("wasp", wx, sac.y - 4, {x0 = wx, ph = j * 1.1, st = 0, vx = 0.0, vy = 0.0, score = 0})
					sac.cd = 200
			var c: Dictionary = P2.core
			c.y = B.y - 14.0
			c.x = B.x
			c.armour = wings > 0
			if wings == 0:
				if not B.phase2:
					B.phase2 = true
					audio.play("alarm")
				var cyc: int = B.t % 240
				if cyc < 120 and B.t % 12 == 0:
					fan(c.x, c.y - 6, 1.4, 3, 0.18)
				if cyc == 180:
					fan(c.x, c.y, 1.0, 7, 0.2)
			elif not B.enter and B.t % 240 == 200:
				aim(c.x, c.y - 6, 1.3)
		"bastion":
			# four guns on a beam; armour plates circle the core, faster once the guns are gone
			if not B.enter:
				B.x = W / 2.0 + sin(B.bt * 0.008) * 8.0
			var guns := 0
			for i in 4:
				var p: Dictionary = P2["g%d" % i]
				p.y = B.y + 4.0
				p.x = B.x + p.oy
				if not p.alive:
					continue
				guns += 1
				if B.enter:
					continue
				p.cd -= tier_mul("fire")
				if p.cd <= 0:
					aim(p.x, p.y - 5, 1.2)
					p.cd = 120
			B.rot += 0.03 if guns == 0 else 0.015
			for i in 4:
				var p: Dictionary = P2["p%d" % i]
				var a: float = i * TAU / 4.0 + B.rot
				p.y = B.y - 6.0 + cos(a) * 19.0
				p.x = B.x + sin(a) * 19.0
			var c: Dictionary = P2.core
			c.y = B.y - 6.0
			c.x = B.x
			if guns == 0:
				if not B.phase2:
					B.phase2 = true
					audio.play("alarm")
				var cyc: int = B.t % 200
				if cyc < 36 and cyc % 6 == 0:
					aim(c.x, c.y, 2.0)
				if cyc == 120:
					ring(c.x, c.y, 12, 0.8)
			elif not B.enter and B.t % 260 == 130:
				ring(c.x, c.y, 8, 0.7)
		_:
			# eight nodes orbit the heart; when they're gone it roams the top half spiralling fire
			var nodes := 0
			for i in 8:
				var p: Dictionary = P2["n%d" % i]
				var a: float = i * TAU / 8.0 + B.t * 0.012
				p.y = B.y + cos(a) * 26.0
				p.x = B.x + sin(a) * 26.0
				if not p.alive:
					continue
				nodes += 1
				if B.enter:
					continue
				p.cd -= tier_mul("fire")
				if p.cd <= 0:
					aim(p.x, p.y, 1.1)
					p.cd = 150
			var c: Dictionary = P2.core
			c.armour = nodes > 0
			if nodes > 0:
				if not B.enter:
					B.x = W / 2.0 + sin(B.bt * 0.01) * 10.0
					if B.t % 240 == 120:
						ring(B.x, B.y, 10, 0.7)
			else:
				if not B.phase2:
					B.phase2 = true
					B.bt = 0
					audio.play("alarm")
					hud.banner("Warning", "The heart is exposed", 120)
				if not B.phase3 and c.hp < c.max * 0.4:
					B.phase3 = true
					audio.play("alarm")
				var tx: float = W / 2.0 + sin(B.bt * 0.018) * 32.0
				var ty: float = B.home - 6.0 + sin(B.bt * 0.009) * 22.0
				B.x += (tx - B.x) * 0.05
				B.y += (ty - B.y) * 0.05
				var cyc: int = B.t % 260
				var arms := 3 if B.phase3 else 2
				if cyc < 150 and B.t % (5 if B.phase3 else 6) == 0:
					var a: float = B.t * 0.09
					for j in arms:
						bullet(B.x, B.y, cos(a + j * TAU / arms) * 0.8 * bspeed(), sin(a + j * TAU / arms) * 0.8 * bspeed())
				if cyc == 200:
					ring(B.x, B.y, 14, 0.75)
				if B.t % 330 == 160:
					for j in 2:
						E("seeker", B.x + (j * 2 - 1) * 12.0, B.y - 10, {vx = (j * 2 - 1) * 0.6, vy = -1.0, score = 0})
			c.x = B.x
			c.y = B.y
	var parts := []
	for p in B.list:
		if p.alive:
			parts.append({o = p, x = p.x, y = p.y, r = p.r, kind = "shield" if p.armour else ("core" if p.core else "part")})
	G.bparts = parts


## A point of the stage in the boss model's frame (the model is turned a quarter turn).
func _bl(x: float, y: float, z: float) -> Vector3:
	return Vector3(Y(y), -X(x), z)


func _sync_gboss(B: Dictionary) -> void:
	var u: Dictionary = B.m.get_meta("u")
	B.m.position = Vector3.ZERO
	var P2: Dictionary = B.parts
	var c: Dictionary = P2.core
	var hp := 0.0
	var mx := 0.0
	for p in B.list:
		if p.max < 9999:
			hp += maxf(0.0, p.hp)
			mx += p.max
	hud.boss = 0.0 if B.dying else clampf(hp / mx, 0.0, 1.0)
	match B.kind:
		"prism":
			var core: Node3D = u.core
			core.position = _bl(c.x, c.y, 0)
			core.rotation = Vector3(0, B.t * 0.02, sin(B.t * 0.02) * 0.2)
			Models.set_flash(core, c.flash > 0 and not c.armour)
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				var n: Node3D = u[key]
				var beam: Node3D = u[key + "_beam"]
				n.visible = p.alive
				beam.visible = p.alive
				n.position = _bl(p.x, p.y, 1)
				n.rotation.y = B.t * 0.04
				Models.set_flash(n, p.flash > 0)
				beam.position = _bl((p.x + c.x) / 2.0, (p.y + c.y) / 2.0, -2)
				beam.scale = Vector3(1.6, absf(p.x - c.x), 1.6)
		"titan":
			(u.hull as Node3D).position = _bl(B.x, B.y + 4, -4)
			var core: Node3D = u.core
			core.position = _bl(c.x, c.y, 2)
			core.rotation.z = B.t * 0.05
			Models.set_flash(core, c.flash > 0 and not c.armour)
			(u.lidT as Node3D).position = _bl(c.x - 4.5 - B.lid * 8.0, c.y - 3, 6)
			(u.lidB as Node3D).position = _bl(c.x + 4.5 + B.lid * 8.0, c.y - 3, 6)
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				var n: Node3D = u[key]
				n.visible = p.alive
				n.position = _bl(p.x, p.y, 3)
				var d := Vector2(P.x - p.x, P.y - p.y)
				(n.get_meta("piv") as Node3D).rotation.z = atan2(-d.x, d.y) - PI
				Models.set_flash(n, p.flash > 0)
		"queen":
			var head: Node3D = u.core
			head.position = _bl(c.x, c.y, 2)
			head.rotation.y = sin(B.t * 0.03) * 0.3
			Models.set_flash(head, c.flash > 0 and not c.armour)
			var sac: Dictionary = P2.sac
			var sn: Node3D = u.sac
			sn.visible = sac.alive
			sn.position = _bl(sac.x, sac.y, -2)
			sn.scale = Vector3.ONE * (1.0 + sin(B.t * 0.08) * 0.05)
			Models.set_flash(sn, sac.flash > 0)
			for key in ["top", "bot"]:
				var p: Dictionary = P2[key]
				var n: Node3D = u[key]
				n.visible = p.alive
				n.position = _bl(B.x, p.y, 0)
				n.rotation.x = sin(B.t * 0.6) * 0.5
				Models.set_flash(n, p.flash > 0)
		"bastion":
			var core: Node3D = u.core
			core.position = _bl(c.x, c.y, 0)
			core.rotation.z = -B.rot * 2.0
			Models.set_flash(core, c.flash > 0)
			(u.frame as Node3D).position = _bl(B.x, B.y + 10, -6)
			for i in 4:
				var p: Dictionary = P2["p%d" % i]
				var pl: Node3D = u.plates[i]
				pl.position = _bl(p.x, p.y, 4)
				pl.rotation.z = -(i * TAU / 4.0 + B.rot)
				var g: Dictionary = P2["g%d" % i]
				var gn: Node3D = u.guns[i]
				gn.visible = g.alive
				gn.position = _bl(g.x, g.y, 2)
				Models.set_flash(gn, g.flash > 0)
		_:
			var core: Node3D = u.core
			core.position = _bl(c.x, c.y, 0)
			(u.spikes as Node3D).rotation.z = B.t * 0.01
			core.rotation.y = B.t * 0.01
			(u.shell as Node3D).visible = c.armour
			Models.set_flash(core, c.flash > 0 and not c.armour)
			for i in 8:
				var p: Dictionary = P2["n%d" % i]
				var n: Node3D = u.nodes[i]
				n.visible = p.alive
				n.position = _bl(p.x, p.y, 2)
				n.rotation = Vector3(B.t * 0.03, B.t * 0.02, 0)
				Models.set_flash(n, p.flash > 0)
