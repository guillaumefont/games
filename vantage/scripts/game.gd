class_name Game
extends Node3D
## Vantage: the world, the player, foes, shots, the fortress episode and the camera. It is one
## 3D world: the vertical stage is seen from a high tilted camera, and the fortress episode
## swoops that same camera down behind the ship for a third-person chase (no cut, no scene
## change), then back up.
## The interface is in hud.gd; numbers and rules in rules.gd; meshes in models.gd.
## Tests set `driven = true` and call step() themselves.

## Anything that moves: foes, shots, bullets, pickups. Explosions live in `blasts`.
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
	## Time left on the hit flash; below zero, the pause before it can flash again, so
	## steady fire flickers instead of holding the foe white.
	var hit := -1.0
	## Mount point on the fortress (x, y, z from its stern) for turrets and the reactor.
	var anchor := Vector3.INF
	## Height a drone hovers at.
	var size_y := 0.0
	## When a dart from behind reached its hold in the upper screen (-1: not yet).
	var hold := -1.0

const CHUNK := 40.0
## The vertical stage's camera: height, distance behind the frame's centre, horizontal fov.
const TOP_H := 38.0
const TOP_BACK := 17.0
const TOP_FOV := 29.0
const CHUNK_W := 64.0
## Ground past each side of CHUNK_W, in coarse cells, and chunks kept ahead: enough that the
## chase camera never sees the edge of the world before the fog has swallowed it.
const CHUNK_FLANK := 200.0
const CHUNKS_AHEAD := 7

var driven := false
var save_path := Rules.SAVE_PATH
var rng := RandomNumberGenerator.new()
var s: Dictionary

## hangar, vert, approach, pov, core, escape, down, clear, results
var phase := "hangar"
var phase_t := 0.0
var stage_t := 0.0
var wave_i := 0
var queue: Array = []
var frame_z := 0.0
var foes: Array[Obj] = []
var shots: Array[Obj] = []
var bullets: Array[Obj] = []
var picks: Array[Obj] = []
## While above zero, every coin on screen flies to the ship (after the mid-boss).
var vacuum_t := 0.0
## Explosions, debris, smoke and their light (blasts.gd).
var blasts: Blasts

# the player
var ship: Node3D
var ship_mesh: MeshInstance3D
var engine_glow: MeshInstance3D
var ppos := Vector3(0, Rules.PY, 5)
var prel := Vector2(0, 5)
var pvel := Vector2.ZERO
var hp := 3
var inv := 0.0
## Push from ramming something (world units/s, x and z in the stage, x and y in the chase); eases off.
var knock := Vector2.ZERO
var fire_cd := 0.0
var miss_cd := 0.0
var bank := 0.0
var touching := false
var last_touch := Vector2.ZERO
## Slow-motion pause: 1 while a finger is down, eases to 0 (paused) once it's lifted.
## `time_speed()` is the eased rate the world runs at.
var time_k := 1.0
var run := {}
## The level being played (index in the campaign, see Campaign), its world and its waves.
var level := 0
var world: Dictionary = Campaign.WORLDS[0]
var waves: Array = Rules.STAGE
var sky_mat: ShaderMaterial
var fill: DirectionalLight3D

# the fortress episode
var fortress: Node3D
var stern_z := 0.0
var fortress_done := false
var rail_s := 0.0
var aim := Vector2.ZERO
var off := Vector2.ZERO
var core: Obj
var approach_from := Vector3.ZERO
var approach_stern := 0.0
## World z of the ship when the chase began (the ship is at rail_z - rail_s).
var rail_z := 0.0
## The fortress's current scale and lift (see Rules.FORTRESS_SCALE).
var fort_s := 1.0
var fort_lift := 0.0
## How far the fortress has fallen while going down.
var fort_fall := 0.0
## Its propellers (spun every frame), how fast they turn, and the wing that breaks off as it
## goes down (and how that wing moves away, in the fortress's frame).
var fort_props: Array[Node3D] = []
var prop_spin := 0.0
var wing_off: Node3D
var wing_vel := Vector3.ZERO
var boss_done := false
## The fortress's current section (in `fort.sections`), its live parts and their full hp.
var fort_sec := 0
var fort_parts: Array[Obj] = []
var fort_max := 1.0
var drone_t := 0.0
var drone_n := 0

# camera
## Silhouette shadows: flattened copies of models, cast along the sun onto the ground. They are
## drawn white on black into a mask at the game's 720 px width (`shadow_view`, seen by `shadow_cam` only), and one
## see-through plane (`shadow_plane`) darkens the ground wherever the softened mask is set. So each
## pixel is shaded once: overlapping faces and neighbouring shadows never stack into dark patches,
## and the edges fade smoothly instead of stair-stepping.
const SHADOW_Y := 1.45
const SHADOW_LAYER := 1 << 19
var shadows: Array[MeshInstance3D] = []
var shadow_view: SubViewport
var shadow_cam: Camera3D
var shadow_plane: MeshInstance3D
var sun_slide := Vector2.ZERO
var cam: Camera3D
var sound: Sound
var cam_mode := "top"
var cam_from := Transform3D()
var cam_from_fov := 29.0
var cam_k := 1.0
var cam_dur := 1.0
## Screen shake (0 to 1 and a little over): it eases off by itself, strong blasts set it high.
var shake := 0.0
var shake_t := 0.0
var world_per_px := 0.02

var sun: DirectionalLight3D
var env: Environment
var noise := FastNoiseLite.new()
var chunks := {}
## Landmarks in the chunks not yet in play (see spawn_marks), and chunks holding a ruin.
var marks: Array = []
var ruined := {}
var hud: Hud
var boss: Obj
## The level's mid-boss (`Rules.MIDBOSSES`: its id and design), its current section (index in
## its sections), the section's live parts and their full hp.
var mid_id := "bastion"
## The level's fortress (`Rules.FORTRESSES`): its id and design.
var fort_id := "goliath"
var fort: Dictionary = Rules.FORTRESSES.goliath
var mid: Dictionary = Rules.MIDBOSSES.bastion
var boss_sec := 0
var boss_parts: Array[Obj] = []
var boss_max := 1.0
var banner := ""
var banner_t := 0.0
var sub_banner := ""


func _ready() -> void:
	s = Rules.load_game(save_path)
	noise.seed = 1337
	noise.frequency = 0.022
	noise.fractal_octaves = 3
	env = Environment.new()
	# a gradient sky with a sun glow, seen whenever the camera tilts up in the chase
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform vec3 top : source_color = vec3(0.24, 0.50, 0.80);
uniform vec3 mid : source_color = vec3(0.48, 0.74, 0.92);
uniform vec3 hor : source_color = vec3(0.86, 0.92, 0.94);
uniform vec3 low : source_color = vec3(0.62, 0.78, 0.88);
uniform vec3 sun : source_color = vec3(1.0, 0.92, 0.75);
void sky() {
	float h = EYEDIR.y;
	vec3 c = mix(hor, mid, smoothstep(0.0, 0.25, h));
	c = mix(c, top, smoothstep(0.2, 0.85, h));
	c = mix(c, low, smoothstep(0.0, -0.15, h));
	float s = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
	c += sun * (pow(s, 10.0) * 0.25 + pow(s, 180.0) * 0.8) * smoothstep(-0.1, 0.05, h);
	COLOR = c;
}
"""
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color8(0xb4, 0xcc, 0xe8)
	env.ambient_light_energy = 0.5
	# no sky reflections: they wash the flat colours out to cyan
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.04
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color8(0xc4, 0xde, 0xee)
	env.fog_density = 1.0
	env.fog_depth_begin = 60.0
	env.fog_depth_end = 180.0
	env.fog_depth_curve = 1.6
	env.fog_sun_scatter = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	sun.light_energy = 1.2
	sun.light_color = Color8(0xff, 0xef, 0xd6)
	add_child(sun)
	# no shadow maps (the web renderer washes vertex colours out with them, and they cost
	# on phones): models drop soft silhouette shadows instead, see cast_shadow_of()
	var d := -sun.basis.z
	sun_slide = Vector2(d.x, d.z) / maxf(-d.y, 0.1)
	# a cool fill from the opposite side keeps the shaded faces from going flat grey
	fill = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-30), deg_to_rad(150), 0)
	fill.light_energy = 0.28
	fill.light_color = Color8(0x9c, 0xc4, 0xff)
	fill.light_specular = 0.0
	add_child(fill)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.1
	cam.far = 400.0
	add_child(cam)
	cam.make_current()
	cam.cull_mask &= ~SHADOW_LAYER
	make_shadow_view()
	ship = Node3D.new()
	add_child(ship)
	ship_mesh = Models.instance(Models.player())
	ship.add_child(ship_mesh)
	cast_shadow_of(ship_mesh)
	engine_glow = Models.instance(Models.shot_mesh(0.13), Models.glow(Models.CYAN))
	engine_glow.position = Vector3(0, -0.05, 1.4)
	engine_glow.scale = Vector3(1.6, 1, 3)
	ship.add_child(engine_glow)
	sound = Sound.new()
	add_child(sound)
	blasts = Blasts.new()
	blasts.cam = cam
	add_child(blasts)
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
	for k in ruined:
		if chunks.has(k):
			chunks[k].queue_free()
			chunks.erase(k)
	ruined.clear()
	ship.visible = true
	set_cam("top", 0.0)
	pick_level(int(s.sel))
	prel = Vector2(0, hangar_ship_z())
	ppos = Vector3(0, Rules.PY, frame_z + prel.y)
	update_chunks()
	hud.show_hangar()
	sound.music("sortie", true)
	if not driven and not checked_update:
		checked_update = true
		check_update()


## Where the ship idles in the hangar (z relative to the frame): on the flight plane, centred in
## the open sky between the version line and the top of the hangar panel, whatever the screen.
func hangar_ship_z() -> float:
	var vs := view_size()
	if vs.y < 1.0:
		return 4.0
	var y := (Hud.HANGAR_TOP + hud.hangar_panel_top()) * 0.5
	var xf: Transform3D = pose("top")[0]
	var o := cam.project_ray_origin(Vector2(vs.x * 0.5, y))
	var n := cam.project_ray_normal(Vector2(vs.x * 0.5, y))
	if absf(n.y) < 0.001:
		return 4.0
	# the camera may still be easing in: measure from where it is, relative to its own frame
	var hit := o + n * ((Rules.PY - o.y) / n.y)
	return hit.z - (cam.global_position.z - xf.origin.z + frame_z)


## Selects a level (in the hangar): its world's land and sky show behind the menu.
func pick_level(lv: int) -> void:
	if not Campaign.is_open(s, lv):
		return
	level = lv
	s.sel = lv
	world = Campaign.world_of(lv)
	waves = Campaign.waves(lv)
	mid_id = Campaign.midboss_of(lv)
	mid = Rules.MIDBOSSES[mid_id]
	fort_id = Campaign.fortress_of(lv)
	fort = Rules.FORTRESSES[fort_id]
	apply_theme(world.theme)


## The world's look: terrain colours and props (the ground is rebuilt), sky, fog and light.
func apply_theme(theme: String) -> void:
	var th: Dictionary = Models.THEMES[theme]
	var sk: Array = th.sky
	for k in 4:
		sky_mat.set_shader_parameter(["top", "mid", "hor", "low"][k], sk[k])
	env.fog_light_color = th.fog
	env.ambient_light_color = th.ambient
	sun.light_color = th.sun
	if Models.theme != theme:
		Models.theme = theme
		for k in chunks.keys():
			chunks[k].queue_free()
		chunks.clear()
		update_chunks()


## Launches the selected level (or `lv`, if it is open).
func launch(lv := -1) -> void:
	pick_level(int(s.sel) if lv < 0 else lv)
	Rules.save_game(s, save_path)
	clear_all()
	phase = "vert"
	phase_t = 0.0
	stage_t = 0.0
	wave_i = 0
	queue.clear()
	fortress_done = false
	boss_done = false
	prel = Vector2(0, 6)
	ppos = Vector3(0, Rules.PY, frame_z + prel.y)
	hp = Rules.max_hp(s)
	inv = 0.0
	knock = Vector2.ZERO
	fire_cd = 0.0
	miss_cd = 0.5
	run = {"score": 0, "scrap": 0, "kills": 0, "hits": 0, "cleared": false}
	ship.visible = true
	# the launch tap is lifted already: wait, paused, for the finger that flies the ship
	time_k = 0.0
	set_cam("top", 0.0)
	hud.show_play()
	say("LEVEL " + Campaign.code(level), "%s · %s" % [world.name, Campaign.level_name(level)])
	sound.play("launch")
	sound.music("sortie")


# ---------------------------------------------------------------- updates

## Set after a quiet check of update.json finds a newer build than the one running.
var new_build := 0
var checked_update := false


## The launch check (scripts/boot.gd) already updated the game if it could; this one runs
## in the hangar, so a build published while the game was open still gets offered.
func check_update() -> void:
	var url: String = ProjectSettings.get_setting("vantage/update_url", "")
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
	var have := int(ProjectSettings.get_setting("vantage/build", 0))
	var running := str(ProjectSettings.get_setting("application/config/version", ""))
	if d is Dictionary and int(d.get("build", 0)) > have and not running.begins_with("b%d" % int(d.get("build", 0))):
		new_build = int(d.build)
		hud.refresh_hangar()


## The version on the title screen was tapped: reload into a newer build, or check for one.
func version_tap() -> void:
	sound.play("tap")
	if new_build > 0:
		refresh_game()
		return
	hud.version_note = "checking…"
	hud.refresh_hangar()
	await check_update()
	hud.version_note = "" if new_build > 0 else "up to date"
	hud.refresh_hangar()
	if new_build > 0:
		refresh_game()


## Restarts the game so the launch check loads the newest build.
func refresh_game() -> void:
	Rules.save_game(s, save_path)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload()")
	else:
		OS.set_restart_on_exit(true)
		get_tree().quit()


func buy(key: String) -> bool:
	var ok := Rules.buy(s, key)
	if ok:
		Rules.save_game(s, save_path)
		sound.play("buy")
	return ok


func end_run(cleared: bool) -> void:
	run.cleared = cleared
	run.total = Campaign.foes_in(level)
	run.grade = Rules.grade(run.kills, run.total, run.hits, cleared)
	run.level = level
	run.opened = -1
	s.scrap += run.scrap
	s.runs += 1
	if cleared:
		s.clears += 1
		if Campaign.cleared(s, level, run.grade):
			run.opened = level + 1
	run.new_best = run.score > s.best
	s.best = maxi(s.best, run.score)
	Rules.save_game(s, save_path)
	phase = "results"
	phase_t = 0.0
	hud.show_results()
	if cleared:
		sound.play("clear")
	sound.music("sortie", true)


func clear_all() -> void:
	blasts.clear()
	for list in [foes, shots, bullets, picks]:
		for o: Obj in list:
			if o.node and not (list == foes and landmark(o)):
				o.node.queue_free()
		list.clear()
	for m: Dictionary in marks:
		m.live = false   # standing landmarks are targets again next sortie
	if fortress:
		fortress.queue_free()
		fortress = null
	boss = null
	boss_parts.clear()
	core = null


func say(text: String, sub := "", dur := 2.2) -> void:
	banner = text
	sub_banner = sub
	banner_t = dur


# ---------------------------------------------------------------- loop

func _process(delta: float) -> void:
	if driven:
		return
	tick(minf(delta, 0.05))


## One frame of real time: the keys, then the world at the slow-motion rate. Fully paused, the
## world isn't stepped at all (only the HUD), so nothing divides by a zero step.
func tick(dt: float) -> void:
	keys(dt)
	slow_down(dt)
	var k := time_speed()
	if k <= 0.0001:
		hud.sync()
		return
	step(dt * k)


func _notification(what: int) -> void:
	# switching apps lifts the finger as far as we're concerned: the game pauses
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		touching = false


## In flight the world only runs while the player holds a finger (or a direction key) down.
func pausable() -> bool:
	return phase in ["vert", "approach", "pov", "core", "escape"]


func holding() -> bool:
	if touching:
		return true
	for k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S, KEY_SPACE]:
		if Input.is_key_pressed(k):
			return true
	return false


## Moves `time_k` towards 1 (held, or out of flight) or 0 (lifted) over real time `dt`.
func slow_down(dt: float) -> void:
	var want := 1.0 if holding() or not pausable() else 0.0
	var rate := 1.0 / Rules.SLOW_STOP if want < time_k else 1.0 / Rules.SLOW_RESUME
	time_k = move_toward(time_k, want, dt * rate)


func time_speed() -> float:
	return smoothstep(0.0, 1.0, time_k)


func paused() -> bool:
	return pausable() and time_k <= 0.0


func _unhandled_input(event: InputEvent) -> void:
	if driven:
		return
	handle(event)


## Pointer input (touch is emulated as mouse). Dragging moves the ship 1:1 in the vertical
## stage and the reticle inside the fortress.
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
	if phase == "vert":
		prel += px * world_per_px
		clamp_player()
	elif phase in ["pov", "core", "escape"]:
		off += Vector2(px.x, -px.y) * pov_drag()


## Metres per pixel of drag in the chase: a swipe across most of the screen (`Rules.POV_SWIPE`)
## carries the ship from one flank of the fortress to the other, and likewise from the bottom
## to the top of the tower.
func pov_drag() -> Vector2:
	var vs := view_size()
	return Vector2(2.0 * Rules.POV_REACH.x / maxf(vs.x * Rules.POV_SWIPE, 1.0),
		(Rules.POV_REACH.y + Rules.POV_DOWN) / maxf(vs.y * Rules.POV_SWIPE, 1.0))


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
		var px_per_s := Vector2.ONE * 11.0 / world_per_px if phase == "vert" else Vector2(14.0, 20.0) / pov_drag()
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
			prel.y = hangar_ship_z()
			ppos = Vector3(0, Rules.PY + sin(phase_t * 1.4) * 0.15, frame_z + prel.y)
			bank = sin(phase_t * 0.8) * 0.15
		"vert":
			step_vert(dt)
		"approach":
			step_approach(dt)
		"pov", "core", "escape":
			step_pov(dt)
		"down":
			frame_z -= Rules.SCROLL * dt
			if phase_t > 2.2:
				end_run(false)
		"clear" when cam_mode == "chase":
			# the final boss went down: fly on over the coast, then the results
			ppos.z -= Rules.RAIL * dt
			frame_z = ppos.z - 6.0
			if phase_t > 3.0:
				end_run(true)
		"clear":
			frame_z -= Rules.SCROLL * dt
			prel.y = lerpf(prel.y, Rules.Z_TOP - 8.0, minf(1.0, dt * 0.6 * phase_t))
			ppos = Vector3(prel.x, Rules.PY, frame_z + prel.y)
			if phase_t > 3.0:
				end_run(true)
		"results":
			frame_z -= 2.0 * dt
	if phase in ["vert", "approach", "pov", "core", "escape", "clear"]:
		update_objs(dt)
	elif phase == "down":
		update_objs(dt)
	spin_props(dt)
	shake = maxf(0.0, shake - dt * 1.2)
	blasts.step(dt)
	update_chunks()
	update_ship(dt)
	update_shadows()
	update_cam(dt)
	sync_shadow_view()
	hud.sync()


# ---------------------------------------------------------------- the vertical stage

func step_vert(dt: float) -> void:
	stage_t += dt
	frame_z -= Rules.SCROLL * dt
	var before := prel
	prel += knock * dt
	knock = knock.move_toward(Vector2.ZERO, Rules.KNOCK_EASE * dt)
	clamp_player()
	ppos = Vector3(prel.x, Rules.PY, frame_z + prel.y)
	pvel = (prel - before) / maxf(dt, 0.001)
	update_view()
	run_waves()
	fire_vert(dt)
	if fortress and not fortress_done and stern_z - frame_z >= Rules.Z_TOP + 2.0:
		begin_approach()


func run_waves() -> void:
	while wave_i < waves.size():
		var w: Dictionary = waves[wave_i]
		if stage_t < w.t:
			break
		if w.kind == "end":
			# the level ends once its last foes are dealt with (or have had their time)
			if queue.is_empty() and boss == null and (air_foes() == 0 or stage_t > w.t + 8.0):
				level_clear()
			break
		if w.kind == "boss":
			if boss == null and not boss_done:
				spawn_vert("boss", 0.0, 0, 1)
			if not boss_done:
				break
			wave_i += 1
			continue
		if w.kind == "fortress":
			if fortress == null and not fortress_done:
				spawn_fortress()
			if not fortress_done:
				break
			wave_i += 1
			continue
		for i in int(w.n):
			queue.append({"at": stage_t + i * float(w.gap), "kind": w.kind, "x": float(w.x), "i": i, "n": int(w.n),
				"from": w.get("from", "top")})
		wave_i += 1
	var rest := []
	for q: Dictionary in queue:
		if stage_t >= q.at:
			spawn_vert(q.kind, q.x, q.i, q.n, q.from)
		else:
			rest.append(q)
	queue = rest


func air_foes() -> int:
	var n := 0
	for f in foes:
		if not f.dead and not f.ground and f.kind != "orb":
			n += 1
	return n


## A level without the fortress is over: the ship flies off the top, then the results.
func level_clear() -> void:
	phase = "clear"
	phase_t = 0.0
	vacuum_t = 4.0
	for b in bullets:
		b.dead = true
	run.score += 2000
	say("LEVEL CLEAR", "%s  +2,000" % Campaign.level_name(level), 3.0)


func new_foe(kind: String, mesh: Mesh) -> Obj:
	var f := Obj.new()
	f.kind = kind
	var d: Dictionary = Rules.FOES[kind]
	# later worlds field tougher foes
	f.hp = d.hp * (float(world.tough) if kind not in ["boss", "orb"] else 1.0)
	f.max_hp = d.hp
	f.r = d.r
	f.node = Models.instance(mesh)
	add_child(f.node)
	cast_shadow_of(f.node)
	foes.append(f)
	return f


func spawn_vert(kind: String, x: float, i: int, n: int, from := "top") -> void:
	var top := frame_z + minf(view_top, Rules.Z_TOP) - 2.5
	match kind:
		"dart":
			var f := new_foe("dart", Models.dart())
			f.rel = true
			f.idx = i
			f.pos = Vector3(x * 1.25 + (i % 2) * 0.6 - 0.3, Rules.PY, top)
			f.fire_t = 0.9 + 0.1 * i
			match from:
				"left", "right":
					# sweep across the upper screen from beyond the side edge
					var side := -1.0 if from == "left" else 1.0
					var z := lerpf(view_top, Rules.Z_TOP + 4.0, 0.5) + x
					f.pos = Vector3(side * (view_hw(z) + 2.0), Rules.PY, frame_z + z)
					f.vel = Vector3(-side * 5.5, 0, 1.2)
				"back":
					# overtake from behind, up a lane at the side, then fire back down
					var lane := x + (i % 2) * 1.2
					f.pos = Vector3(lane, Rules.PY, frame_z + maxf(view_bot, Rules.Z_BOT) + 2.0)
					f.vel = Vector3(0, 0, -14.0)
					f.fire_t = 1.6 + 0.1 * i
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
			var gz := frame_z + minf(view_ground_top, top - frame_z - 3.0) - 2.0
			f.pos = Vector3(clampf(sx, -7.0, 7.0), ground_y(sx, gz), gz)
			f.fire_t = 1.5 + 0.4 * i
		"heavy":
			var f := new_foe("heavy", Models.heavy())
			f.rel = true
			f.x0 = x * 1.25
			f.pos = Vector3(f.x0, Rules.PY, top - 2.0)
			f.fire_t = 2.0
		"boss":
			var f := new_foe("boss", Models.midboss_hull(mid_id))
			f.node.material_override = Models.tinted(world.tint)
			f.rel = true
			f.pos = Vector3(0, Rules.PY, top - 12.0)
			f.x0 = 0.0
			boss = f
			boss_sec = 0
			# each section's piece is its own mesh, so it can break off
			for sec: Dictionary in mid.sections:
				if sec.piece != "":
					var mi := Models.instance(Models.midboss_piece(mid_id, sec.piece), Models.tinted(world.tint))
					mi.name = sec.piece
					f.node.add_child(mi)
					cast_shadow_of(mi)
			open_section()
			say("WARNING", mid.title)
			sound.play("warning")
			sound.music("carrier")


func ground_y(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) + 0.35 * sin(x * 0.05 + z * 0.01) + Models.lift()
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
		sound.play("shot")
	fire_missiles(dt)


func new_shot(at: Vector3, v: Vector3, dmg: float, missile := false) -> Obj:
	var o := Obj.new()
	o.kind = "missile" if missile else "shot"
	o.pos = at
	o.vel = v
	o.dmg = dmg
	o.r = 0.3 if missile else 0.22
	o.node = Models.shot_node(0.12 if missile else 0.1, Models.AMBER if missile else Models.SHOT_BODY, Models.AMBER if missile else Models.SHOT_HALO, 0.0, 4.0, 0.6)
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
		if not f.dead and f.kind != "orb" and not landmark(f) and on_screen(f):
			targets.append(f)
	if targets.is_empty():
		miss_cd = 0.2
		return
	miss_cd = period
	sound.play("missile")
	targets.sort_custom(func(a: Obj, b: Obj) -> bool: return a.pos.distance_squared_to(ppos) < b.pos.distance_squared_to(ppos))
	for k in Rules.missile_count(lv):
		var side := -1.0 if k % 2 == 0 else 1.0
		var v := Vector3(side * 6.0, 0, -4.0) if pov_mode() == false else Vector3(side * 3.0, 2.0, -12.0)
		var m := new_shot(ppos + Vector3(side * 0.6, -0.1, 0.2), v, Rules.MISSILE_DMG, true)
		m.rel = not pov_mode()
		m.target = targets[mini(k, targets.size() - 1)]


func pov_mode() -> bool:
	return phase in ["pov", "core", "escape"]


## Where a point looks to be on the flight plane, seen from the vertical stage's camera.
## Ground turrets and the battleship's guns sit below or above the plane, and the camera
## looks down at an angle, so shots must meet them where they show on screen, not straight
## above them.
func seen(p: Vector3) -> Vector3:
	if pov_mode() or absf(p.y - Rules.PY) < 0.01:
		return p
	var eye := Vector3(0, TOP_H, frame_z + TOP_BACK)
	var k := (TOP_H - Rules.PY) / maxf(TOP_H - p.y, 1.0)
	return eye + (p - eye) * k


## What the vertical camera shows of the flight plane, relative to the scroll frame: the
## top and bottom edges (z) and the half width at each. A tall phone sees more than the
## field the player moves in, so foes spawn past these edges, never inside the screen.
var view_top := Rules.Z_TOP
var view_bot := Rules.Z_BOT
var view_hw_top := Rules.HALF_W + 1.0
var view_hw_bot := Rules.HALF_W + 1.0
## The top edge on the ground, where ground turrets roll in.
var view_ground_top := Rules.Z_TOP - 6.0


func update_view() -> void:
	var vs := view_size()
	if vs.x < 1.0 or vs.y < 1.0:
		return
	var at := func(px: Vector2, y: float) -> Vector3:
		var o := cam.project_ray_origin(px)
		var n := cam.project_ray_normal(px)
		if absf(n.y) < 0.001:
			return o
		return o + n * ((y - o.y) / n.y)
	var tl: Vector3 = at.call(Vector2(0, 0), Rules.PY)
	var bl: Vector3 = at.call(Vector2(0, vs.y), Rules.PY)
	view_top = tl.z - frame_z
	view_bot = bl.z - frame_z
	view_hw_top = absf(tl.x)
	view_hw_bot = absf(bl.x)
	view_ground_top = (at.call(Vector2(vs.x * 0.5, 0), 0.0) as Vector3).z - frame_z


## The screen's half width on the flight plane at depth z (relative to the frame).
func view_hw(z: float) -> float:
	return lerpf(view_hw_top, view_hw_bot, clampf(inverse_lerp(view_top, view_bot, z), 0.0, 1.0))


func on_screen(f: Obj) -> bool:
	if pov_mode():
		var dz := ppos.z - f.pos.z
		return dz > 2.0 and dz < 45.0
	var z := seen(f.pos).z - frame_z
	var at := seen(f.pos)
	return z > view_top + 0.5 and z < view_bot - 0.5 and absf(at.x) < view_hw(z) - 0.3


# ---------------------------------------------------------------- foes and objects

func update_objs(dt: float) -> void:
	var dz := -Rules.SCROLL * dt if phase in ["vert", "down", "clear"] else 0.0
	for f in foes:
		f.t += dt
		f.flash = maxf(0.0, f.flash - dt)
		f.hit = maxf(-1.0, f.hit - dt)
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
	vacuum_t = maxf(0.0, vacuum_t - dt)
	for p in picks:
		p.t += dt
		if p.rel:
			p.pos.z += dz
		var to := ppos - p.pos
		to.y = 0
		if phase in ["vert", "clear"] and (vacuum_t > 0.0 or to.length() < Rules.magnet_radius(s)):
			p.pos += to.normalized() * minf(to.length(), (30.0 if vacuum_t > 0.0 else 16.0) * dt)
		else:
			p.vel = p.vel.lerp(Vector3(0, 0, 2.5), minf(1.0, dt * 2.5))
			p.pos += p.vel * dt
	collide(dt)
	# a landmark whose ground chunk went (scrolled off before the landmark did) goes with it
	for f in foes:
		if landmark(f) and not f.dead and not is_instance_valid(f.node):
			f.dead = true
			f.node = null
	# cull
	for list: Array in [foes, shots, bullets, picks]:
		for i in range(list.size() - 1, -1, -1):
			var o: Obj = list[i]
			if o.dead or gone(o):
				if o.node and not (list == foes and landmark(o) and not o.dead):
					o.node.queue_free()
				list.remove_at(i)
	# place nodes
	for f in foes:
		f.node.position = f.pos
		var sc := 1.0 + f.flash * 0.6
		f.node.scale = Vector3(sc, sc, sc) * f.size
		var mi := f.node as MeshInstance3D
		if mi:
			mi.material_overlay = Models.hit_mat() if f.hit > 0.0 else null
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
	# the mid-boss and its guns are never culled: it comes in from far above the top on a tall
	# screen (Guillaume was stuck on 2-1: the Halo's rim guns were dropped before it arrived)
	if o == boss or o in boss_parts:
		return false
	if pov_mode():
		return o.pos.z > ppos.z + 4.0 or o.pos.z < ppos.z - 90.0 or o.t > 8.0 and o.kind in ["shot", "missile", "orb"]
	if o in foes and landmark(o) and phase != "vert":
		return true
	var z := o.pos.z - frame_z
	if o in foes and (o.kind in ["drone", "sentry", "orb", "panel", "core"]):
		return phase == "vert"
	if o.kind == "shot" or o.kind == "missile":
		# fly on to the real screen edge (a tall phone shows more than the play field)
		return z < minf(view_top, Rules.Z_TOP) - 2.0 or absf(o.pos.x) > maxf(view_hw_top, Rules.HALF_W) + 2.0 or o.t > 3.0
	return z > maxf(Rules.Z_BOT, view_bot) + 3.0 or z < Rules.Z_TOP - 30.0 or absf(o.pos.x) > Rules.HALF_W + 12.0


## Each foe's movement and fire.
func think(f: Obj, dt: float) -> void:
	var to_p := ppos - f.pos
	match f.kind:
		"dart" when f.vel != Vector3.ZERO:
			var z := f.pos.z - frame_z
			if f.vel.z < 0.0 or f.hold >= 0.0:
				# from behind: overtake up a side lane, brake and hold in the upper screen
				# (weaving, firing), then climb away off the top
				var hold_z := lerpf(view_top, view_bot, 0.22) + (f.idx % 3) * 1.6
				if f.hold < 0.0 and z <= hold_z + 3.5:   # brake early: it overshoots a little
					f.hold = f.t   # time it reached its hold
				if f.hold >= 0.0:
					var held := f.t - f.hold
					var vz := -0.6 if held < 3.5 else -9.0
					f.vel.z = lerpf(f.vel.z, vz, minf(1.0, dt * 3.0))
					f.vel.x = cos(held * 1.8 + f.idx) * 2.2
					if held > 0.6 and f.t >= f.fire_t and f.fire_t > 0:
						f.fire_t = f.t + 1.6
						aimed(f.pos, 9.5)
			f.pos += f.vel * dt
			f.node.rotation = Vector3(0, atan2(f.vel.x, f.vel.z), 0)
			if f.vel.z >= 0.0 and f.hold < 0.0:
				# from a side: a slow sweep across with a gentle dip
				f.vel.z = 1.2 + sin(f.t * 1.4) * 1.4
				if f.t >= f.fire_t and f.fire_t > 0 and on_screen(f):
					f.fire_t = f.t + 2.2
					aimed(f.pos, 10.0)
		"dart":
			f.pos.z += 7.0 * dt
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
			var at := seen(f.pos)
			to_p = ppos - at
			var z := at.z - frame_z
			f.node.rotation.y = atan2(to_p.x, to_p.z)
			if f.t >= f.fire_t and z > Rules.Z_TOP and z < Rules.Z_BOT - 4.0:
				f.fire_t += 2.4
				for k in 3:
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
		"cannon", "flak", "battery", "bridge", "lance", "spiral", "dome":
			think_part(f, dt)
		"drone":
			var dist := ppos.z - f.pos.z
			var keep := 4.0 + f.idx * 1.2
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
			f.pos = fort_point(f.anchor)
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
				f.pos = core.pos + Vector3(cos(a) * 3.6, sin(a) * 3.6, 1.6) * fort_s / Rules.FORTRESS_SCALE
				f.node.rotation = Vector3(PI / 2, 0, a)
				if f.t >= f.fire_t and phase == "core":
					f.fire_t += 2.6
					orb(f.pos + Vector3(0, 0, 0.6), 10.0)
		"core":
			f.pos = fort_point(f.anchor)
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


## The boss's hull: comes down from the top, then flies its design's way (`move`), pushing
## closer each time a section falls. Its parts ride on it and fire on their own (think_part).
func think_boss(f: Obj, dt: float) -> void:
	var t := f.t
	var on := t > 4.0
	var base := Rules.BOSS_Z + Rules.BOSS_PUSH * boss_sec
	# come down far enough that the section's deepest gun shows (a short screen sees less)
	var deepest := 0.0
	for p in boss_parts:
		deepest = minf(deepest, (Basis(Vector3.UP, f.node.rotation.y) * p.anchor).z)
	var want_z := frame_z + clampf(view_top + 3.5 - deepest, base, base + 6.0)
	var want_x := 0.0
	var dz := 0.0
	var rot := Vector3.ZERO
	match mid.move:
		"sway":
			want_x = sin(t * 0.35) * 1.4
			dz = sin(t * 0.5) * 0.6
			rot.z = sin(t * 0.35) * -0.04
		"strafe":
			# long sweeps from side to side, banking into them
			want_x = sin(t * 0.45) * 3.0
			dz = sin(t * 0.9) * 0.5
			rot.z = -cos(t * 0.45) * 0.08
		"spin":
			want_x = sin(t * 0.3) * 1.2
			dz = sin(t * 0.6) * 0.5
			rot.y = t * 0.3
		"weave":
			want_x = sin(t * 0.4) * 2.2
			dz = sin(t * 0.55) * 0.8
			rot.y = cos(t * 0.4) * 0.1
			rot.z = sin(t * 0.8) * 0.05
		"charge":
			# every few seconds it lunges at the player, then backs off
			want_x = sin(t * 0.3) * 1.2
			dz = pow(maxf(0.0, sin(t * 0.8)), 6.0) * 3.5
	if not on:
		want_x = 0.0
		dz = 0.0
		rot = Vector3(0, rot.y if mid.move == "spin" else 0.0, 0)
	f.pos.z = lerpf(f.pos.z, want_z + dz, minf(1.0, dt * (0.7 if not on else 1.2)))
	f.pos.x = lerpf(f.pos.x, want_x, minf(1.0, dt))
	f.node.rotation = rot


## Where a part's mount is on the boss now (the hull turns, for a spinning one).
func mount_point(anchor: Vector3) -> Vector3:
	return boss.pos + Basis(Vector3.UP, boss.node.rotation.y) * anchor


func open_section() -> void:
	boss_parts.clear()
	var sec: Dictionary = mid.sections[boss_sec]
	boss_max = 0.0
	for k in sec.parts.size():
		var p: Dictionary = sec.parts[k]
		var f := new_foe(p.kind, Models.boss_part(p.kind))
		f.node.material_override = Models.tinted(world.tint)
		f.hp *= float(Campaign.BOSS_HP[level % Campaign.PER_WORLD])
		f.max_hp = f.hp
		boss_max += f.hp
		f.rel = true
		f.anchor = p.at
		f.idx = k
		f.size = 1.35
		f.pos = mount_point(p.at)
		f.fire_t = 4.0 + k * 0.45 if boss_sec == 0 else 1.5 + k * 0.4
		boss_parts.append(f)
	if boss_sec > 0:
		say(sec.name, "Section %d of %d" % [boss_sec + 1, mid.sections.size()], 1.8)


## A part of the boss: rides on the hull, turns to the player, fires its pattern.
func think_part(f: Obj, dt: float) -> void:
	if boss == null:
		return
	f.pos = mount_point(f.anchor)
	var to_p := ppos - seen(f.pos)
	if f.kind not in Rules.BOSS_HEARTS:
		f.node.rotation.y = atan2(to_p.x, to_p.z)
	else:
		f.node.rotation.y = boss.node.rotation.y
	if boss.t < 4.0 or f.t < f.fire_t:
		return
	var muzzle := seen(f.pos) + Vector3(to_p.x, 0, to_p.z).normalized() * 1.0
	var flat := Vector3(muzzle.x, Rules.PY, muzzle.z)
	match f.kind:
		"cannon":
			f.fire_t = f.t + 1.7
			for k in 3:
				var d := Vector3(to_p.x, 0, to_p.z).normalized().rotated(Vector3.UP, (k - 1) * 0.07)
				bullet(flat, d * (10.5 + k * 0.8))
		"flak":
			f.fire_t = f.t + 1.4
			fan(muzzle, 5, 0.9, 8.5)
		"battery":
			f.fire_t = f.t + 2.0
			var base := f.t * 0.8 + f.idx
			for k in 7:
				var a := base + (k - 3) * 0.22
				bullet(Vector3(f.pos.x, Rules.PY, f.pos.z), Vector3(sin(a) * 0.6, 0, 1).normalized().rotated(Vector3.UP, sin(base) * 0.5) * 7.5)
		"lance":
			# a burst of five quick shots straight at the ship, then a breather
			f.hold += 1.0
			if f.hold >= 5.0:
				f.hold = 0.0
				f.fire_t = f.t + 2.0
			else:
				f.fire_t = f.t + 0.12
			bullet(flat, Vector3(to_p.x, 0, to_p.z).normalized() * 12.0)
		"spiral":
			# two arms of a turning spiral, three seconds on, a second and a half off
			f.fire_t = f.t + 0.13
			if fmod(f.t + f.idx * 1.5, 4.5) < 3.0:
				var a := f.t * 2.2 + f.idx
				for k in 2:
					var ang := a + PI * k
					bullet(Vector3(f.pos.x, Rules.PY, f.pos.z), Vector3(sin(ang), 0, cos(ang)) * 6.5)
		"bridge":
			f.fire_t = f.t + 0.1
			var a := f.t * 2.4
			for k in 3:
				var ang := a + TAU * k / 3.0
				bullet(Vector3(f.pos.x, Rules.PY, f.pos.z + 1.5), Vector3(sin(ang), 0, cos(ang)) * 7.0)
			if fmod(f.t, 1.6) < 0.1:
				aimed(f.pos + Vector3(-2.0, 0, 1.0), 11.0)
				aimed(f.pos + Vector3(2.0, 0, 1.0), 11.0)
		"dome":
			# rings with a turning gap to slip through, and an aimed pair between them
			f.hold += 1.0
			f.fire_t = f.t + 0.9
			if int(f.hold) % 2 == 1:
				var n := 18
				var gap := int(f.hold * 1.7) % n
				for k in n:
					if k == gap or k == (gap + 1) % n:
						continue
					var ang := TAU * k / n + f.hold * 0.2
					bullet(Vector3(f.pos.x, Rules.PY, f.pos.z), Vector3(sin(ang), 0, cos(ang)) * 6.0)
			else:
				aimed(f.pos + Vector3(-1.6, 0, 1.0), 10.5)
				aimed(f.pos + Vector3(1.6, 0, 1.0), 10.5)


## A boss part went down: when its section is cleared, that section's piece breaks off and the
## next one opens; the heart going down blows the whole hull up.
func part_down(f: Obj) -> void:
	boss_parts.erase(f)
	if not boss_parts.is_empty():
		return
	var sec: Dictionary = mid.sections[boss_sec]
	var name: String = sec.piece
	if name != "" and boss.node.has_node(name):
		boss.node.get_node(name).visible = false
		# a ripple of blasts across the section as it breaks off, round where its guns were
		var pts: Array = []
		for k in 8:
			var p: Dictionary = sec.parts[k % sec.parts.size()]
			pts.append(mount_point(p.at + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))))
		pop(pts[0], 3.0, Models.AMBER)
		blasts.chain(pts.slice(1), 2.6, 0.7, fx_carry())
		shake = 0.7
		sound.play("crash")
	boss_sec += 1
	if boss_sec < mid.sections.size():
		open_section()
	else:
		var b := boss
		# the heart: the whole hull goes up from stern to bow, then one huge blast
		var pts: Array = []
		for k in 10:
			pts.append(mount_point(Vector3(rng.randf_range(-4, 4), 1.0, lerpf(7.0, -6.0, k / 9.0) + rng.randf_range(-1, 1))))
		blasts.chain(pts, 3.5, 1.0, fx_carry(), 7.0)
		sound.play("crash")
		sound.music("sortie")
		kill(b)


## Only the heart is shielded, until its section opens (it is the last).
func boss_shielded(f: Obj) -> bool:
	return f.kind in Rules.BOSS_HEARTS and boss_sec < mid.sections.size() - 1


## The boss bar: the current section's health left (0..1) and its name.
func boss_bar() -> Array:
	if pov_mode() and not fort_parts.is_empty():
		var hp := 0.0
		for p in fort_parts:
			hp += maxf(0.0, p.hp)
		var sec: Dictionary = fort.sections[fort_sec]
		return [hp / maxf(fort_max, 1.0), "%s · %s  %d/%d" % [fort.name.to_upper(), sec.name, fort_sec + 1, fort.sections.size()]]
	if boss == null:
		return []
	var hp := 0.0
	for p in boss_parts:
		hp += maxf(0.0, p.hp)
	return [hp / maxf(boss_max, 1.0), "%s · %s  %d/%d" % [mid.name.to_upper(), mid.sections[boss_sec].name, boss_sec + 1, mid.sections.size()]]


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
	b.vel = v * float(world.fire)
	b.rel = true
	b.r = 0.26
	b.node = Models.shot_node(0.3, Models.fire_col(), Models.fire_col(), 0.16)
	b.node.get_node("core").position.y = 0.17
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


## A shootable energy orb inside the fortress, aimed where the ship is.
func orb(at: Vector3, speed: float) -> Obj:
	var o := Obj.new()
	o.kind = "orb"
	o.hp = 1.0
	o.max_hp = 1.0
	o.r = Rules.FOES.orb.r
	o.pos = at
	# fired from things that fly with the ship: aimed in that moving frame
	o.vel = (ppos - at).normalized() * speed * float(world.fire) - Vector3(0, 0, rail_speed())
	o.node = Models.shot_node(0.35, Models.fire_col(), Models.fire_col(), 0.18)
	add_child(o.node)
	foes.append(o)
	return o


func steer_missile(m: Obj, dt: float) -> void:
	if m.target == null or m.target.dead or not m.target in foes:
		m.target = null
		var best := 1e9
		for f in foes:
			if f.dead or f.kind == "orb" or landmark(f) or not on_screen(f):
				continue
			var d := seen(f.pos).distance_squared_to(m.pos)
			if d < best:
				best = d
				m.target = f
	var speed := 26.0 if not pov_mode() else 45.0
	var want := m.vel.normalized() * speed
	if m.target:
		want = (seen(m.target.pos) - m.pos).normalized() * speed
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
			if f.dead or f.kind == "boss":
				continue
			var hit := false
			if pov:
				hit = seg_dist(o.pos - o.vel * _dt, o.pos, f.pos) < f.r + o.r
			else:
				hit = flat_dist(o.pos, seen(f.pos)) < f.r + o.r and on_screen(f) and (not landmark(f) or well_in_view(f))
			if hit:
				o.dead = true
				damage(f, o.dmg)
				break
	if phase not in ["vert", "approach", "pov", "core", "escape"]:
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
			elif f.kind in Rules.RAMMABLE and f.pos.distance_to(ppos) < f.r * Rules.RAM_R + Rules.PLAYER_R:
				ram(f)
		elif f.kind in Rules.RAMMABLE and flat_dist(f.pos, ppos) < f.r * Rules.RAM_R + Rules.PLAYER_R and not (f.vel.z < 0.0 and f.t < 1.0):
			ram(f)
	# the mid-boss's hull (and its pieces until they break off): a wall that hurts
	if boss and not boss.dead and not pov and inv <= 0.0 and boss_rammed(ppos):
		var at := Vector3(ppos.x, Rules.PY, ppos.z - Rules.PLAYER_R)
		pop(at, 1.0, Models.AMBER)
		knock = Vector2(clampf(ppos.x - boss.pos.x, -1.0, 1.0) * 3.0, Rules.KNOCK)
		hurt()
	# pickups
	for p in picks:
		if not p.dead and flat_dist(p.pos, ppos) < Rules.PICK_R:
			p.dead = true
			run.scrap += int(p.dmg)
			sound.play("scrap")
			hud.ping_scrap()


## The ship flew into a foe: the ship takes a hit and is thrown back, small foes break up, big
## ones take RAM_DMG. During the blink after a hit the ship passes through.
func ram(f: Obj) -> void:
	if inv > 0.0 or phase not in ["vert", "approach", "pov", "core", "escape"]:
		return
	var away := ppos - f.pos
	pop(f.pos.lerp(ppos, 0.5), 0.9, Models.AMBER)
	if f.kind in Rules.RAM_KILLS:
		kill(f)
	else:
		damage(f, Rules.RAM_DMG)
	if pov_mode():
		knock = Vector2(away.x, away.y).normalized() * Rules.KNOCK if Vector2(away.x, away.y).length() > 0.05 else Vector2(0, -Rules.KNOCK)
	else:
		knock = Vector2(away.x, away.z).normalized() * Rules.KNOCK if Vector2(away.x, away.z).length() > 0.05 else Vector2(0, Rules.KNOCK)
	hurt()


## Whether the ship at p (seen from above) touches the mid-boss: its hull, and the pieces still
## on it (`Models.midboss_shapes`), the hull turned as it is (a spinning one).
func boss_rammed(p: Vector3) -> bool:
	if boss == null:
		return false
	var q := Vector2(p.x - boss.pos.x, p.z - boss.pos.z).rotated(boss.node.rotation.y)
	var shapes := Models.midboss_shapes(mid_id)
	for piece: String in shapes:
		if piece != "" and not (boss.node.has_node(piece) and boss.node.get_node(piece).visible):
			continue
		for poly: PackedVector2Array in shapes[piece]:
			if Geometry2D.is_point_in_polygon(q, poly):
				return true
			for i in poly.size():
				var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
				if c.distance_to(q) < Rules.PLAYER_R:
					return true
	return false


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func damage(f: Obj, d: float) -> void:
	if (f.kind == "core" and shielded()) or boss_shielded(f):
		f.flash = 0.05
		pop(f.pos + Vector3(0, 0, 1.6), 0.4, Models.CYAN)
		sound.play("shield")
		return
	f.hp -= d
	f.flash = 0.08
	if f.hit < -0.08:
		f.hit = 0.05
	if f.hp > 0.0:
		sound.play("hit")
	if f.hp <= 0.0:
		kill(f)


func kill(f: Obj) -> void:
	f.dead = true
	var info: Dictionary = Rules.FOES[f.kind]
	run.score += int(info.score)
	if f.kind not in ["orb", "boss"] and not landmark(f):
		run.kills += 1
	var big: float = {"heavy": 2.6, "boss": 6.0, "bridge": 4.0, "dome": 4.0, "lance": 2.0, "spiral": 2.2, "cannon": 2.2, "battery": 2.0, "core": 4.0, "panel": 1.6,
		"lighthouse": 2.6, "house": 2.0, "boat": 1.5, "pyramid": 3.2, "stone head": 2.6, "water tower": 2.2, "snowman": 2.0,
		"duck": 1.8}.get(f.kind, 1.3)
	if landmark(f):
		# the landmark falls: a ruin stays on the ground where it stood
		var k := int(f.anchor.z)
		if chunks.has(k):
			var ruin := Models.instance(Models.ruin(f.kind))
			ruin.position = f.node.position - Vector3(0, Models.mark_h(f.kind), 0)
			ruin.rotation.y = f.node.rotation.y
			chunks[k].add_child(ruin)
			ruined[k] = true
	pop(f.pos, big, Models.AMBER, f.ground)
	if f.kind == "orb":
		return
	sound.play("boom" if big >= 2.0 else "pop")
	shake = maxf(shake, 0.12 * big)
	var scrap := roundi(int(info.scrap) * float(world.scrap))
	if pov_mode():
		run.scrap += scrap
		if scrap > 0:
			hud.ping_scrap()
	else:
		var n := clampi(scrap / 5, 1, 14)
		for k in n:
			drop(f.pos, float(scrap) / n)
	if f in boss_parts:
		part_down(f)
	if f in fort_parts:
		fort_part_down(f)
	if f == boss:
		# the mid-boss: the sector carries on, its clock picks up after the boss's wave
		boss = null
		boss_done = true
		vacuum_t = 4.0
		for b in bullets:
			b.dead = true
		stage_t = float(waves[wave_i].t) + 0.5
		run.score += 3000
		say("%s DOWN" % mid.name.to_upper(), "+3,000")
	if f == core:
		begin_escape()


func drop(at: Vector3, value: float) -> Obj:
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
	return p


func hurt() -> void:
	if inv > 0.0 or phase not in ["vert", "approach", "pov", "core", "escape"]:
		return
	hp -= 1
	run.hits += 1
	inv = 1.6
	shake = 0.5
	hud.flash_hurt()
	sound.play("hurt")
	if hp <= 0:
		sound.play("down")
		pop(ppos, 3.0, Models.AMBER)
		ship.visible = false
		var was_pov := pov_mode()
		phase = "down"
		phase_t = 0.0
		say("SHOT DOWN", "", 2.0)
		if was_pov:
			set_cam("top", 1.5)


# ---------------------------------------------------------------- effects

## An explosion (see Blasts.explode); a ground target's stays put while the frame scrolls on,
## anything in the air is carried along with it.
func pop(at: Vector3, size: float, col: Color, ground := false) -> void:
	blasts.explode(at, size, col, fx_carry(ground))


## The speed an explosion drifts at so it stays with what blew up: the rail speed in the chase,
## most of the scroll in the vertical stage (it trails back a little), nothing on the ground.
func fx_carry(ground := false) -> Vector3:
	if pov_mode():
		return Vector3(0, 0, -rail_speed())
	if ground or phase not in ["vert", "down", "clear"]:
		return Vector3.ZERO
	return Vector3(0, 0, -Rules.SCROLL * 0.8)


func update_ship(dt: float) -> void:
	ship.position = ppos
	var tb := 0.0
	if phase == "vert":
		tb = clampf(-pvel.x * 0.05, -0.7, 0.7)
	elif pov_mode():
		tb = clampf(-pvel.x * 0.09, -0.8, 0.8)
	bank = lerpf(bank, tb, minf(1.0, dt * 8.0))
	var pitch := clampf(pvel.y * 0.05, -0.3, 0.3) if pov_mode() else 0.0
	ship.rotation = Vector3(pitch, 0, bank)
	ship_mesh.visible = inv <= 0.0 or fmod(inv, 0.16) > 0.08
	engine_glow.scale = Vector3(1.6, 1, 2.6 + sin(phase_t * 40.0) * 0.6)


## Gives a model a shadow on the ground. The shadow is a child (it goes when the model goes)
## placed in world space each frame by update_shadows().
func cast_shadow_of(mi: MeshInstance3D) -> void:
	var sh := MeshInstance3D.new()
	sh.mesh = mi.mesh
	sh.material_override = Models.shadow_mat()
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.layers = SHADOW_LAYER
	sh.top_level = true
	sh.set_meta("src", mi)
	mi.add_child(sh)
	shadows.append(sh)


func make_shadow_view() -> void:
	shadow_view = SubViewport.new()
	shadow_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	shadow_view.msaa_3d = Viewport.MSAA_DISABLED
	shadow_view.size = Vector2i(720, 1280)
	add_child(shadow_view)
	shadow_cam = Camera3D.new()
	shadow_cam.cull_mask = SHADOW_LAYER
	var black := Environment.new()
	black.background_mode = Environment.BG_COLOR
	black.background_color = Color.BLACK
	black.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	shadow_cam.environment = black
	shadow_view.add_child(shadow_cam)
	shadow_cam.make_current()
	shadow_plane = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(cam.far, cam.far) * 2.2
	shadow_plane.mesh = plane
	shadow_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow_plane.material_override = Models.shadow_plane_mat(shadow_view.get_texture())
	shadow_plane.extra_cull_margin = 10.0
	add_child(shadow_plane)


## Keeps the mask camera on the game camera and the shadow plane under it.
func sync_shadow_view() -> void:
	var size := Vector2i((get_viewport().get_visible_rect().size).max(Vector2.ONE))
	if shadow_view.size != size:
		shadow_view.size = size
	shadow_cam.global_transform = cam.global_transform
	shadow_cam.keep_aspect = cam.keep_aspect
	shadow_cam.fov = cam.fov
	shadow_cam.near = cam.near
	shadow_cam.far = cam.far
	var c := cam.global_position
	shadow_plane.global_position = Vector3(c.x, SHADOW_Y, c.z)


func update_shadows() -> void:
	# flatten onto y = SHADOW_Y along the sun: x' = x + (y - Y) * slide.x, z' likewise
	var flat := Transform3D(Basis(Vector3(1, 0, 0), Vector3(sun_slide.x, 0.0005, sun_slide.y), Vector3(0, 0, 1)),
		Vector3(-SHADOW_Y * sun_slide.x, SHADOW_Y, -SHADOW_Y * sun_slide.y))
	for i in range(shadows.size() - 1, -1, -1):
		var sh := shadows[i]
		if not is_instance_valid(sh) or sh.is_queued_for_deletion():
			shadows.remove_at(i)
			continue
		var src: MeshInstance3D = sh.get_meta("src")
		if not sh.is_inside_tree():
			continue
		sh.global_transform = flat * src.global_transform


func update_chunks() -> void:
	var first := int(floor((-frame_z - 30.0) / CHUNK))
	var want := {}
	for k in range(first, first + CHUNKS_AHEAD):
		want[k] = true
		if not chunks.has(k):
			Models.marks.clear()
			var mi := Models.instance(Models.ground_chunk(noise, -k * CHUNK, Vector2(CHUNK_W, CHUNK), 2.0, CHUNK_FLANK), Models.ground_mat())
			add_child(mi)
			chunks[k] = mi
			# the landmarks get their own nodes, so they can be shot down
			for m: Dictionary in Models.marks:
				var node := Models.instance(Models.landmark(m.kind, m.r))
				node.position = m.pos + Vector3(0, Models.mark_h(m.kind), 0)
				node.rotation.y = m.ang
				mi.add_child(node)
				marks.append({"kind": m.kind, "node": node, "chunk": k, "live": false})
	for k in chunks.keys():
		if not want.has(k):
			chunks[k].queue_free()
			chunks.erase(k)
			ruined.erase(k)
	spawn_marks()


## Landmarks become targets as they come into view in the vertical stage. A shot-down one
## leaves a ruin, and its chunk is rebuilt before the next sortie (`ruined`).
func spawn_marks() -> void:
	for i in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		if not is_instance_valid(m.node) or m.node.is_queued_for_deletion() or not chunks.has(m.chunk):
			marks.remove_at(i)
			continue
		var node: Node3D = m.node
		if phase != "vert" or m.live:
			continue
		var z := seen(node.position).z - frame_z
		if z > view_top - 3.0 and z < view_bot:
			m.live = true
			var f := Obj.new()
			f.kind = m.kind
			f.ground = true
			var d: Dictionary = Rules.FOES[m.kind]
			f.hp = d.hp
			f.max_hp = d.hp
			f.r = d.r
			f.node = node
			f.pos = node.position
			f.anchor = Vector3(0, 0, m.chunk)   # its chunk, for the ruin
			foes.append(f)


## A landmark takes hits only once it is well inside the screen, so it is seen before it falls
## (Guillaume found some shot down before they showed).
func well_in_view(f: Obj) -> bool:
	return seen(f.pos).z - frame_z > view_top + Rules.LANDMARK_IN


func landmark(f: Obj) -> bool:
	return f.kind in Rules.LANDMARKS


## A landmark leaves the foes without its node going: the node belongs to the ground chunk.
func let_go(f: Obj) -> void:
	f.dead = true
	f.node = null


# ---------------------------------------------------------------- the fortress episode

func spawn_fortress() -> void:
	fortress = Node3D.new()
	fort_sec = 0
	fort_parts.clear()
	fort_s = 1.0
	fort_lift = Rules.FORTRESS_CRUISE
	fort_fall = 0.0
	stern_z = frame_z + Rules.Z_TOP - 3.0 - Rules.SCROLL * 3.0
	var hull := Models.instance(Models.fortress_hull(fort_id), Models.tinted(world.tint))
	fortress.add_child(hull)
	cast_shadow_of(hull)
	# the wings, each with its engines: spinning propellers or jet nozzles, and their glow
	fort_props.clear()
	prop_spin = Rules.PROP_SPIN
	wing_off = null
	var w := Models.wing_spec(fort_id)
	var jet: bool = w.jet
	for side in [1.0, -1.0]:
		var wing := Node3D.new()
		wing.name = "wing_r" if side > 0 else "wing_l"
		wing.position = w.root * Vector3(side, 1, 1)
		var mi := Models.instance(Models.fortress_wing(fort_id, side), Models.tinted(world.tint))
		wing.add_child(mi)
		cast_shadow_of(mi)
		wing.add_child(Models.instance(Models.fortress_exhausts(fort_id, side),
			Models.glow(Color8(0xa8, 0xe0, 0xff) if jet else Color8(0xff, 0xc0, 0x70))))
		for p in Models.prop_points(fort_id):
			var prop := Models.instance(Models.fortress_nozzle() if jet else Models.fortress_prop())
			prop.position = p * Vector3(side, 1, 1)
			prop.rotation.z = rng.randf() * TAU
			prop.set_meta("dir", 0.0 if jet else side)
			wing.add_child(prop)
			fort_props.append(prop)
		fortress.add_child(wing)
	for sec: Dictionary in fort.sections:
		if sec.piece != "":
			var mi := Models.instance(Models.fortress_piece(fort_id, sec.piece), Models.tinted(world.tint))
			mi.name = sec.piece
			fortress.add_child(mi)
	fortress.add_child(Models.instance(Models.fortress_lights(), Models.glow(Color8(0xc8, 0xf4, 0xff))))
	add_child(fortress)
	place_fortress(0.0)
	say("FORTRESS AHEAD", fort.title)
	sound.play("warning")
	sound.music("carrier")


## The swoop behind the ship: the vertical stage freezes, the ship drops in behind the
## fortress, and the camera comes down to a chase view. Everything stays outside.
func begin_approach() -> void:
	phase = "approach"
	phase_t = 0.0
	approach_from = ppos
	approach_stern = stern_z
	for f in foes:
		if landmark(f):
			let_go(f)
		elif not f.dead:
			f.dead = true
			pop(f.pos, 1.0, Models.AMBER)
	for b in bullets:
		b.dead = true
	# the stage is over: whatever scrap is still about is collected
	var left := 0
	for p in picks:
		if not p.dead:
			p.dead = true
			left += int(p.dmg)
			pop(p.pos, 0.4, Models.AMBER)
	if left > 0:
		run.scrap += left
		hud.ping_scrap()
		sound.play("scrap")
	queue.clear()
	set_cam("chase", 2.2)
	say("INTERCEPT", "Bring the fortress down")
	sound.play("swoop")


func step_approach(dt: float) -> void:
	frame_z -= Rules.SCROLL * maxf(0.0, 1.0 - phase_t / 1.2) * dt
	var k := clampf(phase_t / Rules.APPROACH, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	# the fortress speeds up to the rail speed while the ship falls in behind it
	stern_z = approach_stern - Rules.RAIL * Rules.APPROACH * 0.5 * k * k
	var tail := Vector3(0, Rules.PY, stern_z + Rules.GAP_FAR)
	var side := smoothstep(0.0, 1.0, minf(1.0, k * 1.6))
	ppos = Vector3(lerpf(approach_from.x, tail.x, side), Rules.PY, lerpf(approach_from.z, tail.z, e))
	pvel = Vector2((tail.x - approach_from.x) * (1.0 - side), 0)
	fort_s = lerpf(1.0, Rules.FORTRESS_SCALE, e)
	fort_lift = lerpf(Rules.FORTRESS_CRUISE, Rules.FORTRESS_LIFT, e)
	place_fortress(0.0)
	if k >= 1.0:
		begin_pov()


## Opens the fortress's next section: its turrets, or the reactor and its panels.
func open_fort_section() -> void:
	fort_parts.clear()
	var sec: Dictionary = fort.sections[fort_sec]
	if sec.mounts.is_empty():
		spawn_pov({"kind": "core", "n": 1})
		phase = "core"
		phase_t = 0.0
	else:
		spawn_pov({"kind": "sentry", "n": sec.mounts.size(), "mounts": sec.mounts})
	fort_max = 0.0
	for p in fort_parts:
		fort_max += p.max_hp
	say(sec.name, "Section %d of %d" % [fort_sec + 1, fort.sections.size()], 1.8)


## A fortress part went down: once its section is cleared, that section breaks off.
func fort_part_down(f: Obj) -> void:
	fort_parts.erase(f)
	if not fort_parts.is_empty() or f == core:
		return
	var sec: Dictionary = fort.sections[fort_sec]
	var name: String = sec.piece
	if fortress and name != "" and fortress.has_node(name):
		fortress.get_node(name).visible = false
		# a ripple of blasts across the piece as it breaks off, round where its guns were
		var pts: Array = []
		for k in 8:
			var m: Vector2 = sec.mounts[k % sec.mounts.size()]
			pts.append(fort_point(Vector3(m.x + rng.randf_range(-1.5, 1.5), m.y + rng.randf_range(-1.5, 1.5), Models.mount_z(m))))
		pop(pts[0], 3.6, Models.AMBER)
		blasts.chain(pts.slice(1), 3.0, 0.7, fx_carry(), 5.0)
		shake = 0.7
		sound.play("crash")
	fort_sec += 1
	open_fort_section()


## Turns the fortress's propellers (each wing's the other way round); a broken wing's stop.
func spin_props(dt: float) -> void:
	if fortress == null:
		return
	for p in fort_props:
		if is_instance_valid(p) and p.get_parent() != wing_off:
			p.rotation.z += prop_spin * float(p.get_meta("dir")) * dt


func place_fortress(bob: float) -> void:
	fortress.position = Vector3(0, Rules.PY + fort_lift - Rules.PY * fort_s + bob - fort_fall, stern_z)
	fortress.scale = Vector3.ONE * fort_s


## A point given on the fortress's model (its stern at z = 0) in the world, with its current
## scale and lift.
func fort_point(p: Vector3) -> Vector3:
	return Vector3(p.x * fort_s, Rules.PY + fort_lift + (p.y - Rules.PY) * fort_s, stern_z + p.z * fort_s)


func begin_pov() -> void:
	phase = "pov"
	phase_t = 0.0
	fort_sec = 0
	drone_t = 3.0
	drone_n = 0
	open_fort_section()
	rail_s = 0.0
	rail_z = ppos.z
	off = Vector2.ZERO
	hud.show_play()


## The chase, on rails: ship and fortress fly forward at `Rules.RAIL`; the drag moves the ship
## in the plane facing the fortress (that's how you dodge), the guns fire straight ahead with
## a little aim assist.
func step_pov(dt: float) -> void:
	var v := rail_speed()
	rail_s += v * dt
	off += knock * dt
	knock = knock.move_toward(Vector2.ZERO, Rules.KNOCK_EASE * dt)
	off.x = clampf(off.x, -Rules.POV_REACH.x, Rules.POV_REACH.x)
	off.y = clampf(off.y, -Rules.POV_DOWN, Rules.POV_REACH.y)
	var before := Vector2(ppos.x, ppos.y)
	var cur := before.lerp(Vector2(off.x, Rules.PY + off.y), minf(1.0, dt * 10.0))
	pvel = (cur - before) / maxf(dt, 0.001)
	ppos = Vector3(cur.x, cur.y, rail_z - rail_s)
	frame_z = ppos.z - 6.0
	if fortress:
		var gap := Rules.GAP_NEAR if phase == "core" else Rules.GAP_FAR
		var want := ppos.z - gap
		if phase == "escape":
			# losing way: it drops back a little, but stays ahead and below the ship
			want = ppos.z - Rules.GAP_FAR - phase_t * 5.0
		stern_z = lerpf(stern_z, want, minf(1.0, dt * 0.6)) - v * dt
		place_fortress(sin(phase_t * 0.7) * 0.3)
	aim = cam.unproject_position(ppos + Vector3(0, 0.2, -Rules.AIM_AHEAD)) if not cam.is_position_behind(ppos + Vector3(0, 0, -30)) else view_size() * 0.5
	if phase == "escape":
		step_crash(dt)
		if phase_t > Rules.CRASH_TIME:
			if fortress:
				fortress.queue_free()
				fortress = null
			phase = "clear"
			phase_t = 0.0
			run.score += 5000
			say("WORLD CLEAR" if level % Campaign.PER_WORLD == Campaign.PER_WORLD - 1 else "LEVEL CLEAR", "Fortress destroyed  +5,000", 3.0)
			return
	drone_t -= dt
	if drone_t <= 0.0:
		drone_t = float(fort.drones)
		spawn_pov({"kind": "drone", "n": 3 + drone_n % 2})
		drone_n += 1
	fire_pov(dt)


## The fortress going down: its engines catch fire and its propellers wind down, the left
## wing snaps off at the root and tumbles away, and the fortress rolls onto that side, noses
## over and falls out of the sky trailing smoke and explosions, to hit the sea (water spouts)
## or the shore (a wall of fire) in one last blast.
func step_crash(dt: float) -> void:
	if fortress == null:
		return
	var k := phase_t / Rules.CRASH_TIME
	var snapped := phase_t > Rules.WING_SNAP
	var roll := 0.12 * k + (0.85 * smoothstep(Rules.WING_SNAP, Rules.CRASH_TIME, phase_t) if snapped else 0.0)
	fortress.rotation = Vector3(-0.5 * k * k, 0, roll + sin(phase_t * 3.0) * 0.02)
	fort_fall += Rules.CRASH_FALL * phase_t * dt
	prop_spin = maxf(Rules.PROP_SPIN * 0.25, prop_spin - Rules.PROP_SPIN * 0.3 * dt)
	var carry := fx_carry()
	# every engine burns, and the stern trails fire and smoke
	if fmod(phase_t, 0.08) < dt:
		var i := 0
		for p in fort_props:
			if is_instance_valid(p) and phase_t > 0.15 * i:
				blasts.burn(p.global_position, 0.6 * fort_s, carry * 0.95)
			i += 1
		for p in [Vector3(-3.2, 9.0, 0.6), Vector3(2.8, 15.0, 0.2)]:
			if phase_t > 0.5:
				blasts.burn(fortress.to_global(p), 0.55 * fort_s, carry * 0.95)
	# the left wing snaps at the root
	var wing: Node3D = fortress.get_node_or_null("wing_l")
	if snapped and wing and wing_off == null:
		wing_off = wing
		wing_vel = Vector3(-7.0, 2.0, 6.0)
		var root := fortress.to_global(Models.wing_spec(fort_id).root * Vector3(-1, 1, 1))
		pop(root, 5.5, Models.AMBER)
		blasts.chain([fortress.to_global(Models.wing_spec(fort_id).root * Vector3(-1, 1, 1) + Vector3(-4, 0, 6)),
			fortress.to_global(Models.wing_spec(fort_id).root * Vector3(-1, 1, 1) + Vector3(-2, 1, -8))], 4.0, 0.25, carry)
		shake = 1.0
		sound.play("crash", 2.0)
	if wing_off:
		wing_vel.y -= 9.0 * dt
		wing_off.position += wing_vel * dt
		wing_off.rotation += Vector3(0.5, 0.3, 1.6) * dt
	if fmod(phase_t, 0.16) < dt:
		# most on the tail, where they show, some along the hull and on the wing roots
		var z := -rng.randf_range(0, 4.0) if rng.randf() < 0.55 else -rng.randf_range(4.0, Rules.FORTRESS_LEN * 0.3)
		var at := fortress.to_global(Vector3(rng.randf_range(-4.5, 4.5), rng.randf_range(2.0, 20.0), z))
		if rng.randf() < 0.25:
			at = fortress.to_global(Models.wing_spec(fort_id).root * Vector3(1, 1, 1) + Vector3(rng.randf_range(0, 12), 0, rng.randf_range(-8, 8)))
		pop(at, rng.randf_range(2.6, 4.6), Models.AMBER)
		sound.play("boom", -4.0)
		shake = maxf(shake, 0.3)
	if phase_t > Rules.CRASH_TIME - 1.0 and not fortress.has_meta("impact"):
		fortress.set_meta("impact", true)
		# it hits the water (spouts) or the shore (a fireball) all along its hull, the wing apart
		var drift := Vector3(0, 0, -rail_speed() * 0.6)
		var hits: Array[Vector3] = []
		for j in 6:
			hits.append(fortress.to_global(Vector3(rng.randf_range(-6, 6), 0.0, -j * 7.0)))
		if wing_off:
			hits.append(wing_off.to_global(Vector3(-float(Models.wing_spec(fort_id).span) * 0.5, 0, 0)))
		var j := 0
		for at in hits:
			at.y = ground_y(at.x, at.z)
			if at.y < 0.05:
				blasts.splash(at, 11.0, drift)
			blasts.later(0.05 + j * 0.07, at + Vector3(0, 1.5, 0), 6.0, Models.AMBER, drift)
			j += 1
		shake = 1.0
		sound.play("crash", 3.0)
	if phase_t > Rules.CRASH_TIME - 0.3:
		fortress.visible = false


func spawn_pov(w: Dictionary) -> void:
	for i in int(w.n):
		match w.kind:
			"drone":
				# launched from the fortress's hangar, they fall back towards the ship
				var f := new_foe("drone", Models.drone())
				f.idx = i
				f.x0 = (i - (w.n - 1) * 0.5) * 2.2
				f.size_y = Rules.PY + fort_lift + (i % 3) * 5.0
				f.pos = fort_point(Vector3(rng.randf_range(-2, 2), Rules.PY, 1.0))
				f.fire_t = 1.4 + i * 0.45
			"sentry":
				# a gun turret on the fortress: on its stern, the lower tower or the upper tower
				var f := new_foe("sentry", Models.sentry())
				var m: Vector2 = w.mounts[i]
				f.anchor = Vector3(m.x, m.y, Models.mount_z(m))
				f.size = 1.4
				f.pos = fort_point(f.anchor)
				f.fire_t = 0.8 + i * 0.5
				fort_parts.append(f)
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
				c.size = 1.5
				c.pos = fort_point(c.anchor)
				c.fire_t = 1.5
				core = c
				fort_parts.append(c)
				for k in 4:
					var p := new_foe("panel", Models.panel())
					p.idx = k
					p.size = 1.5
					p.fire_t = 1.0 + k * 0.6
					p.pos = c.pos
					fort_parts.append(p)


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
		sound.play("shot")
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
		if f.dead or (f.kind == "core" and shielded()) or landmark(f):
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
		if landmark(f):
			let_go(f)
		elif not f.dead:
			f.dead = true
			pop(f.pos, 1.0, Models.AMBER)
	shake = 0.8
	say("REACTOR DOWN", "The fortress is going down")
	sound.play("crash")


# ---------------------------------------------------------------- camera

func pose(mode: String) -> Array:
	if mode == "chase":
		# behind and above the ship, following it partly so it moves on screen
		var at := Vector3(ppos.x * 0.78, Rules.PY + (ppos.y - Rules.PY) * 0.75 + 4.2, ppos.z + 8.5)
		var look := Vector3(ppos.x * 0.55, Rules.PY + (ppos.y - Rules.PY) * 0.6 + 2.0, ppos.z - 40.0)
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
	shake_t += dt
	if shake > 0.0:
		# smooth, not per-frame noise; small kills barely nudge it, big blasts rock it
		var a := pow(minf(shake, 1.2), 1.5) * (0.5 if cam_mode == "chase" else 1.0)
		var t := shake_t
		var n := Vector2(sin(t * 31.0) + 0.6 * sin(t * 17.3 + 1.7), sin(t * 27.1 + 0.5) + 0.6 * sin(t * 13.7 + 2.9)) / 1.6
		xf.origin += (xf.basis.x * n.x + xf.basis.y * n.y) * a * 0.9
		xf.basis = xf.basis.rotated(xf.basis.z, sin(t * 23.0 + 0.3) * a * 0.03)
	cam.global_transform = xf
	env.adjustment_brightness = 1.0 + blasts.bright * 0.15
	cam.fov = fov
	ship.visible = phase not in ["down", "results"]
