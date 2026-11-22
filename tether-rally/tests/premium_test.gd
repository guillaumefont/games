extends SceneTree
# Premium low-poly look (scripts/premium.gd, preview branch):
# - every world's palette replaces only colours, and keeps every key the world already had
# - gradient() lightens a prop towards its top and keeps the glow alpha
# - pines and boulders are shaded with gradients (many distinct vertex colours, not flat fills),
#   snow sits on the upper faces and green below
# - props stay cheap: a pine under 600 triangles, a boulder under 120, a fallen tree under 160
# - fallen trunks are rare: at most one for every 15 standing trees (Guillaume: "much more trees
#   than fallen trunks"), and bridges in the snow are grey like its road
# - the snow road is a neutral grey, not blue (Guillaume: "the road is too blue")
const Themes = preload("res://scripts/themes.gd")
const Premium = preload("res://scripts/premium.gd")
const WorldView = preload("res://scripts/world_view.gd")
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _initialize() -> void:
	_run()

func _run() -> void:
	for w in Themes.ORDER:
		var base := Themes.get_theme(w)
		var t := Premium.restyle(w, base)
		for k in base:
			if not t.has(k):
				fail("premium %s drops the key %s" % [w, k])
		if t["road"] == base["road"] or not t.has("rim"):
			fail("premium %s is not tuned" % w)
	var th := Premium.restyle("snow", Themes.get_theme("snow"))
	var rd: Color = th["road"]
	if rd.b - rd.r > 0.08:
		fail("snow road is blue (%s)" % rd.to_html(false))
	# the other worlds' props get gradients: the top of a gradient prop is lighter than its foot
	var flat := ArrayMesh.new()
	var tri := []
	tri.resize(Mesh.ARRAY_MAX)
	tri[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	tri[Mesh.ARRAY_COLOR] = PackedColorArray([Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5), Color(0.5, 0.5, 0.5, 0.5)])
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tri)
	var gc: PackedColorArray = Premium.gradient(flat, 100.0).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	if gc[2].r <= gc[0].r:
		fail("gradient: the top is not lighter than the foot")
	if absf(gc[2].a - 0.5) > 0.01:
		fail("gradient: lost the window glow alpha")
	for case in [["pine", Premium.pine(5, 230.0, 58.0, th, 23), 600], ["boulder", Premium.boulder(th, 5), 120], ["fallen tree", Premium.fallen_log(th, 7), 160]]:
		var m: ArrayMesh = case[1]
		var arr := m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var tris := vs.size() / 3
		if tris > case[2]:
			fail("%s: %d triangles (budget %d)" % [case[0], tris, case[2]])
		var cols := {}
		for c in cs:
			cols[c.to_html(false)] = true
		if cols.size() < 12:
			fail("%s: only %d colours, reads as flat fills" % [case[0], cols.size()])
		# snow on top (the brightest of the highest vertices), none at the foot
		var top_y := -1e9; var low_y := 1e9
		for v in vs:
			top_y = maxf(top_y, v.y); low_y = minf(low_y, v.y)
		var top_lum := 0.0; var foot_lum := 0.0
		for i in vs.size():
			if vs[i].y > top_y - (top_y - low_y) * 0.08:
				top_lum = maxf(top_lum, cs[i].get_luminance())
			if vs[i].y < low_y + (top_y - low_y) * 0.05:
				foot_lum = maxf(foot_lum, cs[i].get_luminance())
		if case[0] == "fallen tree":   # lies on its side: no top or foot to compare
			print("%s: %d triangles, %d colours" % [case[0], tris, cols.size()])
			continue
		if top_lum < 0.8:
			fail("%s: no snow on top" % case[0])
		if foot_lum > 0.6:
			fail("%s: snow at the foot" % case[0])
		print("%s: %d triangles, %d colours" % [case[0], tris, cols.size()])
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	view.set_quality(2)
	var log_verts := WorldView.ao_vertex_count(Premium.fallen_log(th, 7))
	for w in ["forest", "snow"]:
		view.theme_override = w
		var tr := TrackData.new(Defs.TRACKS[0], "standard")
		for step in view.build_steps(tr):
			step.call()
		var logs := 0; var trees := 0
		for n in view.static_root.get_children():
			if n is MultiMeshInstance3D and not n.is_queued_for_deletion():
				var mm: MultiMesh = n.multimesh
				if WorldView.ao_vertex_count(mm.mesh) == log_verts:
					logs += mm.instance_count
				elif n.material_override is ShaderMaterial and n.material_override.get_shader_parameter("sway") > 0.0:
					trees += mm.instance_count
		print("%s: %d trees, %d fallen trunks" % [w, trees, logs])
		if logs * 15 > trees:
			fail("%s: too many fallen trunks (%d for %d trees)" % [w, logs, trees])
		if w == "snow":
			var dc: Color = view._deck_col(WorldView.COL_DECK).linear_to_srgb()
			if absf(dc.r - dc.b) > 0.08 or absf(dc.r - dc.g) > 0.08:
				fail("snow bridge timber is not grey (%s)" % dc.to_html(false))
	if bad == 0:
		print("premium_test: ok")
	else:
		printerr("premium_test: %d failure(s)" % bad)
	quit(1 if bad > 0 else 0)
