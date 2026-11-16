extends SceneTree
# Sun shadows (WorldView.shadow_setup / shadow_range):
# - Medium and High filter shadow edges (hard edges showed the map's pixels as stair steps,
#   the "jagged edges" case), High gets the bigger map, Low has none
# - the shadow range holds still while the camera eases its zoom (it used to follow the zoom
#   every frame, resizing the shadow pixels: the "flicker" case), and steady racing never moves it
# - the range still reaches the farthest ground on screen, before the shadows start to fade,
#   on a 16:9 and a 20:9 phone, and not much past it (a longer range means coarser shadows)
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _initialize() -> void:
	_run()

# depth (along the view) of the farthest ground point at the screen's corners
func _ground_depth(view: WorldView, ground_y: float) -> float:
	var cam := view.camera
	var vp := root.get_visible_rect().size
	var far := 0.0
	for p in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), vp]:
		var o := cam.project_ray_origin(p)
		var d := cam.project_ray_normal(p)
		if d.y >= -0.001:
			return INF
		var hit := o + d * ((ground_y - o.y) / d.y)
		far = maxf(far, (hit - cam.global_position).dot(-cam.global_transform.basis.z))
	return far

func _run() -> void:
	# per quality
	var s0 := WorldView.shadow_setup(0)
	var s1 := WorldView.shadow_setup(1)
	var s2 := WorldView.shadow_setup(2)
	if s0["on"] or not s1["on"] or not s2["on"]:
		fail("shadows should be off on Low only")
	for s in [s1, s2]:
		if s["filter"] == RenderingServer.SHADOW_QUALITY_HARD:
			fail("jagged edges: Medium and High must filter shadow edges")
	if s2["map"] <= s1["map"] or s1["map"] < 2048:
		fail("High should get a bigger shadow map than Medium (%d, %d)" % [s1["map"], s2["map"]])

	var view := WorldView.new()
	root.add_child(view)
	await process_frame   # _ready: camera, light, environment
	view.set_quality(2)
	var tr := TrackData.new(Defs.TRACKS[0], "standard")
	view._clear(tr)
	view._build_relief()
	var race := Race.new(tr, "race", 1)
	var dt := 1.0 / 60.0
	var fade: float = view.light.directional_shadow_fade_start
	for size in [Vector2i(1280, 720), Vector2i(2400, 1080)]:
		root.size = size
		await process_frame
		# from the whole-track menu view down into the race: the camera eases in over ~1 s
		view.update_camera(null, "menu", 0.0, true)
		var changes := 0
		var last: float = view.light.directional_shadow_max_distance
		for i in 120:
			view.update_camera(race, "race", dt)
			var r: float = view.light.directional_shadow_max_distance
			if r != last:
				changes += 1
				last = r
		if changes > 8:
			fail("flicker: the shadow range changed %d times while the camera zoomed in" % changes)
		# steady racing: not one change
		for i in 120:
			view.update_camera(race, "race", dt)
			if view.light.directional_shadow_max_distance != last:
				fail("flicker: the shadow range moved during steady racing")
				break
		var c = race.cars[0]
		var depth := _ground_depth(view, (tr.height_at(c.last_s) - 150.0) * WorldView.U)
		if depth > last * fade:
			fail("%s: ground %.1f m deep but shadows fade from %.1f m" % [size, depth, last * fade])
		if last > depth * 1.5:
			fail("%s: shadow range %.1f m for ground %.1f m deep: shadows spread too thin" % [size, last, depth])
		print("%s: shadow range %.1f m, ground depth %.1f m" % [size, last, depth])
	view.free()
	if bad > 0:
		printerr("shadow_test: %d failure(s)" % bad)
		quit(1)
	else:
		print("shadow_test: ok")
		quit(0)
