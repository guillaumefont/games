extends SceneTree
# Cloud shadows and the Golden hour lighting (WorldView._build_clouds, set_golden, Premium.GOLDEN):
# - every world gets one faint cloud layer: a single plane, no shadow casting, shown on Medium
#   and High only, clearly seen (Guillaume found the first, faint version invisible) but not black
# - Golden hour is off by default and is a Settings toggle that Settings and pause both list
# - every world has its golden-hour light; switching it on lowers and warms the sun and only
#   changes colours, energy and the sun's angle: no lighting mode switches (no shader recompile),
#   and switching it off puts the day light back exactly
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Themes = preload("res://scripts/themes.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Premium = preload("res://scripts/premium.gd")
const Settings = preload("res://scripts/settings.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func check(ok: bool, msg: String) -> void:
	if not ok:
		fail(msg)

func _initialize() -> void:
	_run()

func _state(view) -> Array:
	return [view.light.rotation, view.light.light_color, view.light.light_energy, view.env.ambient_light_color,
		view.grade_tex.gradient.sample(0.2), view.grade_tex.gradient.sample(0.85)]

func _modes(env: Environment) -> Array:
	return [env.ambient_light_source, env.reflected_light_source, env.tonemap_mode, env.adjustment_enabled, env.background_mode, env.fog_enabled]

func _run() -> void:
	check(Settings.DEFAULTS.get("golden") == false, "Golden hour should be off by default")
	for theme in Themes.ORDER:
		var props := String(Themes.get_theme(theme)["props"])
		check(Premium.GOLDEN.has(props), "%s: no golden-hour light" % theme)
		var g: Dictionary = Premium.GOLDEN.get(props, {})
		for k in ["sun", "energy", "ambient", "ambient_mix", "shade", "glint"]:
			check(g.has(k), "%s: golden hour has no \"%s\"" % [theme, k])
		if g.has("sun"):
			var sun: Color = g["sun"]
			check(sun.r > sun.b + 0.2, "%s: the golden-hour sun should be warm (%s)" % [theme, sun])

	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	view.set_quality(2)
	var start := _modes(view.env)
	for theme in Themes.ORDER:
		view.theme_override = theme
		view.golden = false
		var tr := TrackData.new(Defs.TRACKS[0], "standard")
		for step in view.build_steps(tr):
			step.call()
		# cloud shadows: one faint plane over the land
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
		# golden hour: lower, warmer sun; off again restores the day
		var day := _state(view)
		view.set_golden(true)
		var gold := _state(view)
		check(view.light.rotation.x > day[0].x + deg_to_rad(5.0), "%s: golden hour should lower the sun (%.1f -> %.1f deg)" % [theme, rad_to_deg(day[0].x), rad_to_deg(view.light.rotation.x)])
		check(gold[1] != day[1] and gold[1].r - gold[1].b > day[1].r - day[1].b, "%s: golden hour should warm the sun" % theme)
		check(_modes(view.env) == start, "%s: golden hour switched a lighting mode (shaders would recompile)" % theme)
		view.set_golden(false)
		check(_state(view) == day, "%s: switching golden hour off should restore the day light" % theme)
		# a world built with golden hour on starts in it
		view.golden = true
		for step in view.build_steps(tr):
			step.call()
		check(_state(view) == gold, "%s: a track built with golden hour on should be lit by it" % theme)
		view.golden = false

	# both option pages list the toggle
	var Main = load("res://scripts/main.gd")
	var src: String = (Main as GDScript).source_code
	check(src.contains("\"golden\": Settings.get_opt(\"golden\")"), "Settings / pause options should include Golden hour")
	var ui_src: String = (load("res://scripts/ui.gd") as GDScript).source_code
	check(ui_src.contains("[\"golden\", \"GOLDEN HOUR\""), "the options grid should have a GOLDEN HOUR toggle")
	view.free()
	if bad > 0:
		printerr("sky_test: %d failure(s)" % bad)
		quit(1)
	else:
		print("sky_test: ok")
		quit(0)
