extends SceneTree
## The look (graphics pass): baked occlusion on the scenery (props darken towards their base,
## flat bits and open tops stay lit, soft contact shadows under what stands tall), the ground's
## liquids by world, and the vignette. Runs headless:
##   godot --headless --path . --script tests/look_test.gd

const SAVE := "user://test_look_save.json"

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


## The mean brightness of the vertices in a height band of a mesh.
func band(m: Mesh, y0: float, y1: float, want_up := false) -> float:
	var arr := m.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var sum := 0.0
	var n := 0
	for i in vs.size():
		if vs[i].y < y0 or vs[i].y > y1:
			continue
		if want_up != (ns[i].y > 0.9) or (not want_up and ns[i].y < -0.5):
			continue   # the top face, or the walls (bottom faces left out)
		sum += cs[i].get_luminance()
		n += 1
	return sum / maxf(n, 1)


func occlusion() -> void:
	print("baked occlusion")
	var b := Models.Builder.new()
	Models.place(b, Vector3(0, 1.0, 0), 0.0)
	b.box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color.WHITE)
	var m := b.commit()
	var low := band(m, 1.0, 1.2)
	var high := band(m, 2.4, 2.65)
	check(low < high * 0.7, "a placed box's walls darken towards its base (%.2f at the base, %.2f up top)" % [low, high])
	check(band(m, 2.79, 2.81, true) > 0.95, "its top, open to the sky, stays lit")
	b = Models.Builder.new()
	Models.place(b, Vector3.ZERO, 0.0)
	b.prism(Vector3.ZERO, Models.ngon(1.0, 8), 0.0, 0.03, Color.WHITE)
	var spots := b.take_spots()
	var plain := Models.Builder.new()
	plain.xf = Transform3D(Basis.from_scale(Vector3(Models.PROP_SCALE, Models.PROP_V, Models.PROP_SCALE)), Vector3.ZERO)
	plain.prism(Vector3.ZERO, Models.ngon(1.0, 8), 0.0, 0.03, Color.WHITE)
	check(is_equal_approx(band(b.commit(), -1.0, 1.0), band(plain.commit(), -1.0, 1.0)) and spots.is_empty(), "a flat ring on the ground (foam, a path) is neither darkened nor shades the ground")
	b = Models.Builder.new()
	b.box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color.WHITE)
	m = b.commit()
	check(absf(band(m, 0.0, 0.2) - Color.WHITE.darkened(0.18).get_luminance()) < 0.01, "unplaced models (ships, bosses) are left alone")
	b = Models.Builder.new()
	Models.place(b, Vector3(4, 0, 2), 0.0)
	b.box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color.WHITE)
	b.xf = Transform3D.IDENTITY
	b.box(Vector3(0, 0.5, 0), Vector3(0.6, 1.0, 0.6), Color.WHITE)
	spots = b.take_spots()
	check(spots.size() == 1 and (spots[0][0] as Vector3).is_equal_approx(Vector3(4, 0, 2)), "a new transform ends the placement: one footprint, at the prop")
	var blobs := Models.ao_blobs(spots, func(_x: float, _z: float) -> float: return 0.0)
	var aabb := blobs.get_aabb()
	check(aabb.size.x > 0.75 * 2.5 and aabb.position.y > 0.0, "the contact shadow spreads past the prop's footprint, just above the ground")


func in_game() -> void:
	print("in the game")
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	await process_frame
	var with_ao := 0
	for k in g.chunks:
		if g.chunks[k].get_node_or_null("ao"):
			with_ao += 1
	check(with_ao >= g.chunks.size() - 1, "the terrain chunks carry their contact shadows (%d of %d)" % [with_ao, g.chunks.size()])
	var gm: ShaderMaterial = Models.ground_mat()
	check(float(gm.get_shader_parameter("water")) > 0.5 and float(gm.get_shader_parameter("lava")) == 0.0, "the coast's sea is water")
	g.apply_theme("volcano")
	check(float(gm.get_shader_parameter("lava")) == 1.0 and float(gm.get_shader_parameter("water")) == 0.0, "the cinders' pools are lava")
	g.apply_theme("dunes")
	check(float(gm.get_shader_parameter("lava")) == 0.0 and float(gm.get_shader_parameter("water")) == 0.0, "the dunes' dry washes stay dry")
	var v: CanvasLayer = g.get_node_or_null("vignette")
	check(v != null and (v.get_child(0) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "a vignette over the view that lets touches through")
	g.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))


func _initialize() -> void:
	print("Vantage look test")
	occlusion()
	await in_game()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
