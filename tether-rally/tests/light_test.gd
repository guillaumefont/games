extends SceneTree
# Sky-tinted light, colour grade and baked ambient occlusion (WorldView._apply_light, ao_*):
# - every world has its sky and grade colours, and the grade keeps the middle grey neutral
#   while leaning the darks to the world's shade colour
# - changing world only changes colours: the ambient source, reflections, tone mapper and
#   adjustments stay as set at start (switching them would compile shaders mid-game, the
#   "finish line stutter" kind of hitch)
# - the ground is darker right at the foot of a tree, rock or tower than out in the open, and
#   the road itself gets no ground occlusion
# - props are darker at their foot than at their top (base_ao)
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Themes = preload("res://scripts/themes.gd")
const WorldView = preload("res://scripts/world_view.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _initialize() -> void:
	_run()

func _run() -> void:
	for theme in Themes.ORDER:
		var th := Themes.get_theme(theme)
		for k in ["sky", "shade", "glint"]:
			if not th.has(k):
				fail("%s: no \"%s\" colour" % [theme, k])
		var g := WorldView.grade_curve(th["shade"], th["glint"])
		var mid := g.sample(0.5)
		if absf(mid.r - 0.5) > 0.02 or absf(mid.g - 0.5) > 0.02 or absf(mid.b - 0.5) > 0.02:
			fail("%s: the grade moves middle grey (%s)" % [theme, mid])
		var dark := g.sample(0.22)
		var shade: Color = th["shade"]
		# the darks lean to the shade colour: its strongest channel comes out the highest
		var top := 0 if shade.r >= shade.g and shade.r >= shade.b else (1 if shade.g >= shade.b else 2)
		var ch := [dark.r, dark.g, dark.b]
		if ch[top] < ch.max() - 0.0001:
			fail("%s: the darks don't lean to the world's shade colour (%s)" % [theme, dark])

	var view := WorldView.new()
	root.add_child(view)
	await process_frame   # _ready: camera, light, environment
	view.set_quality(2)
	var env: Environment = view.env
	var start := [env.ambient_light_source, env.reflected_light_source, env.tonemap_mode, env.adjustment_enabled, env.background_mode, env.fog_enabled]
	if not env.adjustment_enabled or env.adjustment_color_correction == null:
		fail("the colour grade should be on from the start")
	var skies := {}
	for theme in Themes.ORDER:
		view.theme_override = theme
		var tr := TrackData.new(Defs.TRACKS[0], "standard")
		for step in view.build_steps(tr):
			step.call()
		var now := [env.ambient_light_source, env.reflected_light_source, env.tonemap_mode, env.adjustment_enabled, env.background_mode, env.fog_enabled]
		if now != start:
			fail("%s: changing world switched a lighting mode (%s -> %s): shaders would recompile" % [theme, start, now])
		skies[theme] = env.ambient_light_color
		# open ground far from everything vs the foot of each tower
		var open := 0
		var dark := 0
		for a in tr.anchors:
			if view.ao_at(a.pos) < 0.7:
				dark += 1
		var R := tr.bounds.grow(WorldView.TER_MARGIN)
		if view.ao_at(R.position + Vector2(10, 10)) > 0.99:
			open += 1
		if dark < tr.anchors.size():
			fail("%s: only %d of %d tower feet are shaded" % [theme, dark, tr.anchors.size()])
		if open == 0:
			fail("%s: the open ground at the map's edge is shaded" % theme)
		# the road never gets ground occlusion: nothing is stamped on it
		var shaded_road := 0
		var s := 0.0
		while s < tr.L:
			if view.ao_at(tr.point_at(s)["pos"]) < 0.97:
				shaded_road += 1
			s += 60.0
		if shaded_road > 0:
			fail("%s: %d road points are shaded by the ground occlusion" % [theme, shaded_road])
		# trees and rocks: the map is darker than open ground somewhere among the scenery
		var low := 1.0
		for v in view._ao_vals:
			low = minf(low, v)
		if low > 0.6:
			fail("%s: no prop shades the ground (darkest %.2f)" % [theme, low])
	if skies.size() != Themes.ORDER.size() or skies.values().count(skies.values()[0]) == skies.size():
		fail("each world should have its own sky")

	# props: darker at the foot than at the top
	var kit: Dictionary = view._prop_kit()
	var m := WorldView.base_ao(kit["a"], 45.0)
	var arr := m.surface_get_arrays(0)
	var src := (kit["a"] as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var cs0: PackedColorArray = src[Mesh.ARRAY_COLOR]
	var foot := 1.0
	var tip := 0.0
	for k in vs.size():
		var f := cs[k].get_luminance() / maxf(cs0[k].get_luminance(), 0.001)
		if vs[k].y <= 0.01:
			foot = minf(foot, f)
		if vs[k].y > 0.6:
			tip = maxf(tip, f)
	if foot > 0.7 or tip < 0.99:
		fail("base_ao: foot %.2f, top %.2f (want a dark foot and an untouched top)" % [foot, tip])
	view.free()
	if bad > 0:
		printerr("light_test: %d failure(s)" % bad)
		quit(1)
	else:
		print("light_test: ok")
		quit(0)
