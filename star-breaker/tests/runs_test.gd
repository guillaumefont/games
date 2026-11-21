extends SceneTree
## A canyon run in every stage (Guillaume, 2026-11-20): each stage's course is fair, short,
## bends gently, keeps the ship moving, and can be flown clean along its racing line. Then one
## stage per world is flown in the game itself, for gold.

var vg: Node3D
var fails := 0


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


func tick(dx := 0.0, dy := 0.0) -> void:
	vg.inp = {hold = true, fire = true, dx = dx, dy = dy, ult = false, pause = false}
	vg.update()
	vg._process(1.0 / 60.0)


## Flies the racing line of the course in use without the game: the thumb moves the ship at
## most 4 units a tick (times the gain), as in the game. Returns the obstacle hit, or "".
func fly() -> String:
	var u := 0.0
	var l := VRun.line(0.0)
	var x := l.x
	var z := l.y
	while u < VRun.OUT:
		var nu := u + VRun.speed(u)
		var t := VRun.line(nu + 6.0)
		x += clampf(t.x - x, -4.0 * VRun.GAIN, 4.0 * VRun.GAIN)
		z += clampf(t.y - z, -4.0 * VRun.GAIN, 4.0 * VRun.GAIN)
		var what := VRun.hit(x, z, u, nu, VRun.PAD)
		if what != "":
			return "%s at %.0f" % [what, nu]
		u = nu
	return ""


func _initialize() -> void:
	print("Star Breaker: a canyon run in every stage")
	var unfair := []
	var long := []
	var crashed := []
	var bends := []
	var still := []
	var biggest := []
	var shortest := 99.0
	var longest := 0.0
	for i in VStage.STAGES.size():
		var st: Dictionary = VStage.STAGES[i]
		if not st.has("run") or not st.has("course"):
			unfair.append("%d has no run" % i)
			continue
		VRun.use(st.course)
		# a way through every obstacle
		for o in VRun.OBS:
			var p := VRun.passage(o.u)
			var way := false
			var x := p.x - p.y + 4.0
			while x < p.x + p.y - 4.0 and not way:
				var z := VRun.ZMIN
				while z <= VRun.ZMAX and not way:
					way = VRun.hit(x, z, o.u - 1.0, o.u + 1.0, VRun.PAD + 1.0) == ""
					z += 1.0
				x += 1.0
			if not way:
				unfair.append("%d %s at %.0f" % [i, o.k, o.u])
		# how long it lasts
		var ticks := 0
		var u := VRun.SHIP_Y - 280.0
		while u < VRun.LEN:
			u += VRun.speed(u)
			ticks += 1
		var secs := ticks / 60.0
		if i > 0:
			shortest = minf(shortest, secs)
			longest = maxf(longest, secs)
			if secs < 16.0 or secs > 22.0:
				long.append("%d: %.1f s" % [i, secs])
		# the racing line flies clean
		var what := fly()
		if what != "" and i > 0:
			crashed.append("%d: %s" % [i, what])
		# bends: gentle, and straight while the camera swings
		var tight := 0.0
		var bent_swing := 0.0
		var ub := -300.0
		while ub < VRun.LEN + 300.0:
			tight = maxf(tight, absf(VRun.heading(ub + 1.0) - VRun.heading(ub)))
			if VRun.swing(ub) < 0.99:
				bent_swing = maxf(bent_swing, absf(VRun.heading(ub)))
			ub += 1.0
		var most := 0.0
		for tk in VRun.TURN:
			most = maxf(most, absf(float(tk[1])))
		if i > 0:
			biggest.append(most)
		if 1.0 / tight < 220.0 or bent_swing > 0.0:
			bends.append("%d: radius %.0f, %.2f rad while swinging" % [i, 1.0 / tight, bent_swing])
		# movement over precision: no two obstacles in a row ask for the same thing
		for k in VRun.OBS.size() - 1:
			if i > 0 and VRun.OBS[k].k == VRun.OBS[k + 1].k:
				still.append("%d: two %ss in a row" % [i, VRun.OBS[k].k])
	check(unfair.is_empty(), "every stage has a run, and every obstacle leaves a way through %s" % str(unfair))
	check(long.is_empty(), "the generated runs last about 20 s (%.1f to %.1f s) %s" % [shortest, longest, str(long)])
	check(crashed.is_empty(), "every racing line flies clean %s" % str(crashed))
	check(bends.is_empty(), "every bend is gentle and the canyon is straight while the camera swings %s" % str(bends))
	biggest.sort()
	check(biggest[biggest.size() / 2] >= 40.0, "the canyons really turn (median biggest bend %.0f degrees, %.0f to %.0f)" % [biggest[biggest.size() / 2], biggest[0], biggest[-1]])
	check(still.is_empty(), "no two obstacles in a row are the same kind %s" % str(still))
	var a: Dictionary = VStage.STAGES[1].course
	var b: Dictionary = VStage.STAGES[2].course
	check(str(a.obs) != str(b.obs), "no two stages share a course")
	var w0: Dictionary = VStage.STAGES[1].course
	var w5: Dictionary = VStage.STAGES[41].course
	check(w5.obs.size() > w0.obs.size() and w5.obs[1].u - w5.obs[0].u < w0.obs[1].u - w0.obs[0].u, "later worlds pack more obstacles closer together")

	print("In the game")
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame
	for i in range(1, VStage.STAGES.size()):
		vg.start_stage(i, "lance")
		for t in 30:
			vg.P.inv = maxi(vg.P.inv, 2)
			tick()
		# jump to just before the run's mouth
		var d: float = VStage.STAGES[i].run
		vg.G.scroll = d - vg.top() - 60.0
		var n := 0
		while not vg.G.has("run") and n < 600:
			n += 1
			vg.P.inv = maxi(vg.P.inv, 2)
			tick()
		var started: bool = vg.G.has("run")
		vg.P.inv = 0
		var in_rock := 0
		var off_screen := 0.0
		var worst_at := ""
		var rock_at := ""
		var vp: Vector2 = vg.get_viewport().get_visible_rect().size
		while vg.G.has("run") and n < 5000:
			n += 1
			var R: Dictionary = vg.G.run
			var tgt := VRun.line(R.d + 6.0)
			var g := lerpf(1.0, VRun.GAIN, R.k)
			tick(clampf((tgt.x - vg.P.x) / g, -4.0, 4.0), clampf((tgt.y - vg.P.z) / VRun.GAIN, -4.0, 4.0))
			if vg.G.has("run"):
				var cr: Dictionary = vg.G.run
				if cr.k > 0.99 and cr.has("cam_x") and VRun.hit(cr.cam_x, cr.cz, cr.d - 38.5, cr.d - 37.5, 0.5) != "":
					in_rock += 1
					if rock_at == "":
						rock_at = " %s at cam u %.0f (%.1f, %.1f)" % [VRun.hit(cr.cam_x, cr.cz, cr.d - 38.5, cr.d - 37.5, 0.5), cr.d - 38.0, cr.cam_x, cr.cz]
				var sp: Vector2 = vg.camera.unproject_position(vg.ship_m.global_position) / vp
				var edge := maxf(maxf(0.1 - sp.x, sp.x - 0.9), maxf(0.1 - sp.y, sp.y - 0.9))
				if vg.camera.is_position_behind(vg.ship_m.global_position):
					edge = 1.0
				if edge > off_screen:
					worst_at = "d %.0f k %.2f sp %s heading %.0f" % [cr.d, cr.k, str(sp), rad_to_deg(VRun.heading(cr.d))]
				off_screen = maxf(off_screen, edge)
		check(started and vg.G.get("run_medal", -2) == 0 and in_rock == 0 and off_screen <= 0.0,
			"stage %d (%s): the run starts, the racing line earns gold, the camera stays out of rock, the ship stays in sight (%.3f at %s; medal %d, rock %d%s)" % [i + 1, VStage.STAGES[i].name, off_screen, worst_at, vg.G.get("run_medal", -2), in_rock, rock_at])

	print("Built a little per frame")
	# every stage builds its run while you fly its first stretch (Guillaume, 2026-11-21: "the game
	# recently started lagging"): a whole canyon slice or obstacle in one frame cost 5-13 ms on a
	# desktop. The build is now split into small units under a per-frame budget, and its meshes
	# come out exactly as if built at once
	var sd: Dictionary = VStage.STAGES[25]
	VRun.use(sd.course)
	var mats := {ground = vg._terrain_mats.ground, lip = vg._lip_mat, glow = vg._terrain_mats.fissure_b}
	var whole := VRun.Builder.new(vg.look, mats)
	whole.finish()
	var bit := VRun.Builder.new(vg.look, mats)
	var units := 0
	var slowest := 0
	while not bit.step(0.0):
		units += 1
	var same := whole.node.get_child_count() == bit.node.get_child_count()
	for k in mini(whole.node.get_child_count(), bit.node.get_child_count()):
		var na: Node = whole.node.get_child(k)
		var nb: Node = bit.node.get_child(k)
		if na is MeshInstance3D and nb is MeshInstance3D and na.mesh is ArrayMesh and nb.mesh is ArrayMesh:
			same = same and (na.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == (nb.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		else:
			same = same and na.get_class() == nb.get_class() and na.position == nb.position
	var slices := ceili((VRun.LEN + 600.0) / VRun.Builder.SLICE)
	check(same and units >= slices * 4, "the run is built in %d small units (%d slices), meshes identical to building it at once" % [units, slices])
	whole.node.free()
	bit.node.free()
	# in the game: built well before its mouth comes down, never hogging a frame
	vg.start_stage(25, "lance")
	var frames := 0
	while not vg._run_built and frames < 3000:
		frames += 1
		vg.P.inv = maxi(vg.P.inv, 2)
		var t0 := Time.get_ticks_usec()
		tick()
		slowest = maxi(slowest, Time.get_ticks_usec() - t0) if frames > 1 else 0
	check(vg._run_built and vg.G.scroll < sd.run - vg.top() - 100.0,
		"the run is built %d frames in, well before its mouth (slowest frame %.1f ms)" % [frames, slowest / 1000.0])

	print("FAILED: %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)
