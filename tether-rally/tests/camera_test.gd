extends SceneTree
# Headless check of the cinematic camera shots (WorldView.CINE_SHOTS):
# - racing keeps the top-down gameplay view (no shot, no fog)
# - "finish line stutter": the fog switch never flips (menu, countdown, race, finish, results),
#   only its density, since flipping it swaps every material's shader version mid-race
# - the countdown intro is back to the gameplay view by GO (3.0 s into the countdown)
# - the low orbits never put the lens inside the land, a road bank or a bridge, on any track
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

func _run() -> void:
	var view := WorldView.new()
	root.add_child(view)
	await process_frame   # _ready: camera, environment
	var dt := 1.0 / 30.0
	for ti in Defs.TRACKS.size():
		var tr := TrackData.new(Defs.TRACKS[ti], "standard")
		view._clear(tr)
		view._build_relief()
		var race := Race.new(tr, "race", 1)
		var c = race.cars[0]
		if ti == 0:
			# intro: low at the start, gameplay view again by GO
			view.cine_reset()
			view.cine("intro", c)
			view.update_camera(race, "count", 0.0, true)
			if view.camera.position.y - (tr.height_at(c.last_s) * WorldView.U) > 2.0:
				fail("intro does not start low (eye %.2f m up)" % view.camera.position.y)
			var t := 0.0
			while t < 3.0:
				view.update_camera(race, "count", dt)
				t += dt
			if view.cine_active():
				fail("intro still on screen at GO (k %.2f)" % view.cine_k)
			# racing: plain gameplay view at the gameplay pitch, no fog
			view.cine("")
			view.update_camera(race, "race", dt)
			var look := view.camera.global_transform.basis.z
			var pitch := rad_to_deg(asin(look.y))
			if absf(pitch - rad_to_deg(WorldView.PITCH)) > 0.5 or view.env.fog_density > 0.0:
				fail("racing camera changed (pitch %.1f, fog %.3f)" % [pitch, view.env.fog_density])
			_finish_line_stutter(view, race)
		# every shot, all the way round the track: the eye stays clear of the land
		var worst := INF
		var sv := 0.0
		while sv < tr.L:
			var q := tr.point_at(sv)
			c.pos = q["pos"]
			c.h = (q["dir"] as Vector2).angle()
			c.last_s = sv
			for shot in ["finish", "win", "card", "freeze"]:
				view.cine_reset()
				view.cine(shot, c, tr.anchors[0].pos)
				for k in 8:
					view.cine_t = k * 4.0   # round the orbit
					var pose: Array = view._cine_pose()
					var eye: Vector3 = pose[0]
					var gap: float = eye.y - view._cine_floor(Vector2(eye.x, eye.z) / WorldView.U)
					worst = minf(worst, gap)
			sv += 150.0
		if worst < 0.2:
			fail("%s: a shot puts the lens %.2f m from the ground" % [Defs.TRACKS[ti]["name"], worst])
	view.free()
	if bad > 0:
		printerr("camera_test: %d failure(s)" % bad)
		quit(1)
	else:
		print("camera_test: ok")
		quit(0)

# "finish line stutter": crossing the line started the low finish shot, which switched the
# fog on. Fog on/off picks other shader versions for every material, so the first finish
# compiled them all in one frame. The switch must stay as it is from the menu to the
# results; only the density shows the fog (thick on the finish shot, none while racing).
func _finish_line_stutter(view, race) -> void:
	var c = race.cars[0]
	var on: bool = view.env.fog_enabled
	var flips := []
	var steps := [["menu", ""], ["count", "intro"], ["race", ""], ["done", "finish"], ["results", "win"], ["menu", ""]]
	var thick := 0.0
	for st in steps:
		if st[0] == "menu":
			view.cine_reset()
		else:
			view.cine(st[1], c)
		for k in 45:
			view.update_camera(race if st[0] != "menu" else null, st[0], 1.0 / 30.0)
			if view.env.fog_enabled != on:
				flips.append(st[0])
				on = view.env.fog_enabled
			if st[0] == "done":
				thick = maxf(thick, view.env.fog_density)
	if not flips.is_empty():
		fail("finish line stutter: the fog was switched on/off during %s" % [flips])
	if thick <= 0.0:
		fail("finish line stutter: no fog on the low finish shot")
	if view.env.fog_density > 0.0:
		fail("finish line stutter: fog left on the menu (%.3f)" % view.env.fog_density)
	view.cine_reset()
