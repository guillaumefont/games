extends SceneTree
# Cloud shadows (WorldView._build_clouds):
# - every world gets one cloud layer: a single plane, no shadow casting, shown on Medium
#   and High only, clearly seen (Guillaume found the first, faint version invisible) but not black
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Themes = preload("res://scripts/themes.gd")
const WorldView = preload("res://scripts/world_view.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func check(ok: bool, msg: String) -> void:
	if not ok:
		fail(msg)

func _initialize() -> void:
	_run()

func _run() -> void:
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	view.set_quality(2)
	for theme in Themes.ORDER:
		view.theme_override = theme
		var tr := TrackData.new(Defs.TRACKS[0], "standard")
		for step in view.build_steps(tr):
			step.call()
		# cloud shadows: one plane over the land
		var layers := view.dyn_root.find_children("*", "MeshInstance3D", true, false).filter(func(n): return n == view.clouds)
		check(layers.size() == 1, "%s: want one cloud layer, got %d" % [theme, layers.size()])
		var c: MeshInstance3D = view.clouds
		if c != null:
			check(c.mesh is PlaneMesh, "%s: the cloud layer should be one plane" % theme)
			check(c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: the cloud layer must not cast shadows" % theme)
			var amt: float = (c.material_override as ShaderMaterial).get_shader_parameter("amount")
			check(amt >= 0.4 and amt <= 0.6, "%s: cloud shadows should be clearly seen but not black out the scene (amount %.2f)" % [theme, amt])
			check(c.visible, "%s: clouds should show on High" % theme)
			view.set_quality(0)
			check(not c.visible, "%s: clouds should be off on Low" % theme)
			view.set_quality(1)
			check(c.visible, "%s: clouds should show on Medium" % theme)
			view.set_quality(2)

	view.free()
	if bad > 0:
		printerr("sky_test: %d failure(s)" % bad)
		quit(1)
	else:
		print("sky_test: ok")
		quit(0)
