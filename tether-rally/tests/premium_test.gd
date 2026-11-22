extends SceneTree
# Premium low-poly look (scripts/premium.gd, preview branch):
# - the snow palette replaces only colours, and keeps every key the world already had
# - pines and boulders are shaded with gradients (many distinct vertex colours, not flat fills),
#   snow sits on the upper faces and green below
# - props stay cheap: a pine under 600 triangles, a boulder under 120
const Themes = preload("res://scripts/themes.gd")
const Premium = preload("res://scripts/premium.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _initialize() -> void:
	var base := Themes.get_theme("snow")
	var th := Premium.restyle("snow", base)
	for k in base:
		if not th.has(k):
			fail("premium snow drops the key %s" % k)
	if th["road"] == base["road"]:
		fail("premium snow keeps the old road colour")
	if Premium.restyle("sand", Themes.get_theme("sand")) != Themes.get_theme("sand"):
		fail("an untuned world changed")
	for case in [["pine", Premium.pine(5, 230.0, 58.0, th, 23), 600], ["boulder", Premium.boulder(th, 5), 120]]:
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
		if top_lum < 0.8:
			fail("%s: no snow on top" % case[0])
		if foot_lum > 0.6:
			fail("%s: snow at the foot" % case[0])
		print("%s: %d triangles, %d colours" % [case[0], tris, cols.size()])
	if bad == 0:
		print("premium_test: ok")
	else:
		printerr("premium_test: %d failure(s)" % bad)
	quit(1 if bad > 0 else 0)
