extends SceneTree
## Look and effects: the sun casts shadows (off in safe graphics), solid models throw shadows
## and glows don't, the moon's ground is the same wherever it is built and meets seamlessly
## from chunk to chunk, new ground is built a slice per frame ahead of time, the charge shows
## the level's laser strands, the beam carries its twister of strands, and explosions throw a
## shock ring, debris and a flash of light.

var vg: Node3D
var fails := 0


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


func tick(n := 1, hold := false) -> void:
	for i in n:
		vg.inp = {hold = hold, fire = hold, dx = 0.0, dy = 0.0, ult = false, pause = false}
		if not vg.P.is_empty():
			vg.P.inv = maxi(vg.P.inv, 2)
		vg.update()
		vg._process(1.0 / 60.0)


func _initialize() -> void:
	print("Star Breaker visuals test")
	if FileAccess.file_exists(Diag.PATH):
		DirAccess.remove_absolute(Diag.PATH)
	Diag.set_safe(false)
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame

	# --- light and shadow ---
	check(vg.sun.shadow_enabled, "the sun casts shadows")
	Diag.set_safe(true)
	vg.apply_safe()
	check(not vg.sun.shadow_enabled, "safe graphics turn shadows off")
	Diag.set_safe(false)
	vg.apply_safe()
	check(vg.sun.shadow_enabled, "and back on with full graphics")
	check(Models.casts(Models.M.hull) and not Models.casts(Models.M.shot) and not Models.casts(Models.M.laser_glow),
		"solid parts cast shadows, glowing and see-through ones don't")

	# --- ground ---
	var mats: Dictionary = vg._terrain_mats
	var a := Terrain.build_chunk(5, vg.CHUNK, vg.look, mats)
	var b := Terrain.build_chunk(5, vg.CHUNK, vg.look, mats)
	var fa: PackedVector3Array = (a.get_child(0) as MeshInstance3D).mesh.get_faces()
	var fb: PackedVector3Array = (b.get_child(0) as MeshInstance3D).mesh.get_faces()
	check(fa.size() > 300 and fa == fb, "a strip of ground is the same every time it is built")
	a.free()
	b.free()
	var seam := true
	for x in [-150.0, -60.0, -8.0, 0.0, 33.0, 90.0]:
		var top := Terrain.height(x, 6.0 * vg.CHUNK)
		var bot := Terrain.height(x, 6.0 * vg.CHUNK - 0.0001)
		seam = seam and absf(top - bot) < 0.01
	check(seam, "the ground's height is continuous across a chunk edge")
	var bl := Terrain.Builder.new(3, vg.CHUNK, vg.look, mats)
	var steps := 1
	while not bl.step():
		steps += 1
	check(steps >= 4 and bl.node != null, "a strip of ground can be built over several frames (%d steps)" % steps)
	bl.node.free()

	# --- the premium look (world 1): bigger facets, bevelled edges, a sky for the run ---
	check(vg.look.get("premium", false) and bl.cols == Terrain.COLS_P and bl.rows == Terrain.ROWS_P,
		"world 1's ground uses the premium look's bigger facets")
	# smooth ground: no seam between strips (the corners on the shared edge carry the same normal
	# and colour in both), and no face picks itself out (corners shared inside a strip agree)
	var s5 := Terrain.build_chunk(5, vg.CHUNK, vg.look, mats)
	var s6 := Terrain.build_chunk(6, vg.CHUNK, vg.look, mats)
	var edge := {}
	var m5: Array = ((s5.get_child(0) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	for i in (m5[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var p: Vector3 = m5[Mesh.ARRAY_VERTEX][i]
		if is_equal_approx(p.y, vg.CHUNK):
			edge[snappedf(p.x, 0.01)] = [m5[Mesh.ARRAY_NORMAL][i], m5[Mesh.ARRAY_COLOR][i]]
	var m6: Array = ((s6.get_child(0) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
	var same := edge.size() > 20
	var shared := {}
	for i in (m6[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
		var p: Vector3 = m6[Mesh.ARRAY_VERTEX][i]
		var nrm: Vector3 = m6[Mesh.ARRAY_NORMAL][i]
		if is_zero_approx(p.y) and edge.has(snappedf(p.x, 0.01)):
			var e: Array = edge[snappedf(p.x, 0.01)]
			same = same and (e[0] as Vector3).is_equal_approx(nrm) and (e[1] as Color).is_equal_approx(m6[Mesh.ARRAY_COLOR][i])
		var k := (p * 100.0).round()
		if shared.has(k):
			same = same and (shared[k] as Vector3).is_equal_approx(nrm)
		shared[k] = nrm
	check(same, "world 1's ground is smooth: strips meet without a seam and no face shows its own shading")
	s5.free()
	s6.free()
	var plain := Terrain.Builder.new(3, vg.CHUNK, vg.LOOKS[1], mats)
	check(plain.cols == Terrain.COLS and plain.rows == Terrain.ROWS, "other worlds keep their ground as it was")
	var bx := Geo.box(4, 2, 3)
	check(bx.size() == 44, "a box is bevelled: 6 faces, 12 edge strips, 8 corners (%d triangles)" % bx.size())
	var closed := {}
	for t in bx:
		for k in 3:
			var e := [(t[k] as Vector3).snapped(Vector3.ONE * 0.001), (t[(k + 1) % 3] as Vector3).snapped(Vector3.ONE * 0.001)]
			e.sort()
			closed[e] = closed.get(e, 0) + 1
	var shut := true
	for e in closed:
		shut = shut and closed[e] == 2
	check(shut, "the bevelled box is closed (every edge shared by two triangles)")
	check(Geo.box(0.05, 2, 3).size() == 12, "a box too thin to bevel stays a plain box")
	check(vg._env.background_mode == Environment.BG_SKY and vg._env.sky != null, "world 1 has a gradient sky")
	var wa := Terrain.Acc.new()
	Terrain.cliff(wa, [[Vector3(0, 0, 0), 200.0], [Vector3(1, 4, 0), 200.0], [Vector3(0, 8, 0), 200.0]], -1.0, vg.look, 0.0)
	var cn := {}
	var cliff_smooth := wa.count() > 0 and wa.uv.size() == wa.count()
	for i in wa.count():
		var k := (wa.v[i] * 100.0).round()
		var key := [k, wa.n[i].z > 0.6]
		if cn.has(key):
			cliff_smooth = cliff_smooth and (cn[key] as Vector3).is_equal_approx(wa.n[i])
		cn[key] = wa.n[i]
	check(cliff_smooth, "world 1's cliffs are smooth and carry the relief map's coordinates")
	vg.apply_world(1)
	check(vg._env.background_mode == Environment.BG_COLOR and not vg._haze.visible, "other worlds keep their flat background")
	vg.apply_world(0)
	# ground designs: the menu button cycles them, each crisp one is a shader with no screen haze
	var d0 := Terrain.design
	for d in Terrain.DESIGNS.size():
		vg.set_design(d)
		var gm: Material = vg._terrain_mats.ground
		var crisp := d > 0
		check((gm is ShaderMaterial) == crisp and vg._haze.visible == (not crisp and not Diag.safe),
				"ground design %s: %s" % [Terrain.DESIGNS[d], "crisp shader, no screen haze" if crisp else "smooth relief map"])
	vg.hud.btn_ground.pressed.emit()
	check(Terrain.design == 0 and vg.hud.btn_ground.text.contains("SMOOTH"), "the menu's ground button cycles to the next design")
	var ua := Terrain.Acc.new()
	Terrain.cliff(ua, [[Vector3(0, 0, 0), 200.0], [Vector3(0, 8, 0), 200.0]], -1.0, vg.look, 64.0)
	check(ua.uv.size() > 0 and ua.uv[0].x * 32.0 >= 63.9, "cliff texture coordinates run in world units, so chunks meet")
	vg.set_design(d0)

	# --- the stage: ground ahead is pre-built ---
	vg.hud.stage_chosen.emit(0, "lance")
	tick(150)
	var before: int = vg.chunks.size()
	check(before >= 6, "the ground covers the screen (%d strips)" % before)
	var ahead := false
	for i in 200:
		tick(1)
		if not vg._building.is_empty():
			ahead = true
	check(ahead, "the next strips of ground are built ahead of time")

	# --- charge strands ---
	tick(vg.CHARGE_MAX + 20, true)
	check(vg.charge_fx.visible, "Lance's charge ball shows while charging")
	var strands := 0
	for st in 6:
		if (vg.charge_fx.get_child(4 + st) as Node3D).visible:
			strands += 1
	check(strands == 6, "the Nova charge coils its pink, cyan and white strands (and their haze) round the ball")
	check(vg.beam_light.visible and vg.beam_light.light_energy > 0.5, "the charge lights its surroundings")
	tick(1, false)
	tick(4, false)
	var beam: Dictionary = {}
	for bm in vg.G.beams:
		beam = bm
	check(not beam.is_empty() and beam.nova, "lifting at full charge fires the Nova")
	# every charge level now looks like the Storm: a bolt of lightning, wider level by level
	var bim: ImmediateMesh = ((beam.m as Node3D).get_child(2) as MeshInstance3D).mesh if not beam.is_empty() else null
	check(bim != null and bim.get_surface_count() == 1, "the Nova is drawn as the Storm's lightning")
	var lo := VFx.beam_node(1)
	root.add_child(lo)
	VFx.sync_beam(lo, 1, 200.0, 2.0, 1.0, 1, 1, false)
	var hi := VFx.beam_node(4)
	root.add_child(hi)
	VFx.sync_beam(hi, 4, 200.0, 7.0, 1.0, 1, 1, false)
	var spread := func(n: Node3D) -> float:
		var xs: PackedVector3Array = ((n.get_child(0) as MeshInstance3D).mesh as ImmediateMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var m := 0.0
		for v in xs:
			m = maxf(m, absf(v.x))
		return m
	var s1: float = spread.call(lo)
	var s4: float = spread.call(hi)
	check(s1 < s4, "a LV 1 bolt is slimmer than the Nova's (%.1f < %.1f)" % [s1, s4])
	lo.free()
	hi.free()

	# --- the Storm: jagged chain lightning that flickers, forks, and flashes on each target ---
	var sn := VFx.storm_node()
	root.add_child(sn)
	var bolts := [[Vector3(0, -60, 5), Vector3(20, 10, 5)], [Vector3(20, 10, 5), Vector3(-30, 50, 5)]]
	VFx.sync_storm(sn, bolts, 1, 70, 0)
	var im0: ImmediateMesh = (sn.get_child(2) as MeshInstance3D).mesh
	check(im0.get_surface_count() == 1 and (im0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 6 * 8, "the Storm draws its bolts as jagged ribbons")
	var a0: Array = im0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var straight := true
	for v in a0:
		# off the straight line from the ship to the first target?
		var u: float = (v.y + 60.0) / 70.0
		if absf(v.x - 20.0 * u) > 1.5 and v.y < 10:
			straight = false
	check(not straight, "the bolts kink, not straight lines")
	VFx.sync_storm(sn, bolts, 1, 70, VFx.STORM_FLICKER)
	var a1: Array = im0.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(a1 != a0, "the lightning jitters: it is redrawn every %d ticks" % VFx.STORM_FLICKER)
	var flashes := 0
	for k in VFx.STORM_FLASHES:
		if (sn.get_child(3 + k) as Node3D).visible:
			flashes += 1
	check(flashes == 2, "each target flashes where the lightning strikes it")
	VFx.sync_storm(sn, bolts, 70, 70, 9)
	check(im0.get_surface_count() == 0 and not (sn.get_child(3) as Node3D).visible, "the Storm fades out at the end of its life")
	sn.free()

	# --- things enter from off screen, even on a tall phone that shows past the stage ---
	var keep_view: Rect2 = vg.view
	vg.view = Rect2(-2.0, 112.0 - 141.0, 130.0, 282.0)  # a 9:19.5 phone
	var first := {}
	for e in vg.G.enemies:
		first[e.id] = true
	var on_screen := []
	var st := 0
	while st < 900:
		tick(1)
		# the canyon run holds the stage still: count stage time only
		if vg.G.has("run"):
			continue
		st += 1
		for e in vg.G.enemies:
			# carriers fly in from the side, and a boss's brood hatches out of it
			if not first.has(e.id) and not e.get("boss", false) and e.type != "carrier" and e.get("score", 1) != 0:
				first[e.id] = true
				if e.y < vg.view.end.y:
					on_screen.append("%s at %.0f" % [e.type, e.y])
	check(first.size() > 5 and on_screen.is_empty(), "on a tall phone enemies appear above the screen's top edge, not on it (%d seen; on screen: %s)" % [first.size(), on_screen])
	# (shadows and every other model: tests/popin_test.gd)
	vg.view = keep_view

	# --- explosions ---
	var n0: int = vg.fx.size()
	vg.boom(60.0, 120.0, 5.0, true)
	var mine: Array = vg.fx.slice(n0)
	var kinds := {}
	for f in mine:
		kinds[f.get("kind", "glow")] = true
	check(kinds.has("ring") and kinds.has("debris") and kinds.has("glow"), "an explosion throws a shock ring, glows and debris")
	tick(1)
	var lit := false
	for l in vg.boom_lights:
		lit = lit or l.l.visible
	check(lit, "an explosion flashes real light")
	tick(60)
	var left := 0
	for f in mine:
		if vg.fx.has(f) or is_instance_valid(f.m) and not f.m.is_queued_for_deletion():
			left += 1
	check(left == 0, "explosion debris and rings clear away")

	print("FAILED: %d" % fails if fails else "ALL OK")
	quit(1 if fails else 0)
