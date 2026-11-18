extends SceneTree
## The canyon run (VRun): stage 1's canyon mouth arrives, the stage holds still, the camera
## swings behind the ship, the thumb steers sideways and up/down, rock costs hull points, a clean
## run earns gold (and the ultimate), and the stage carries on from where it stopped.

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


## Starts stage 1 and flies (invincible, no steering) until the canyon run begins.
func to_run() -> void:
	vg.start_stage(0, "lance")
	var n := 0
	while not vg.G.has("run") and n < 3000:
		n += 1
		vg.P.inv = maxi(vg.P.inv, 2)
		tick()


func _initialize() -> void:
	print("Star Breaker canyon run test")
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame

	print("Course")
	var fair := true
	for o in VRun.OBS:
		# some point of the passage clears it with room to spare
		var p := VRun.passage(o.u)
		var way := false
		var x := p.x - p.y + 4.0
		while x < p.x + p.y - 4.0 and not way:
			var z := VRun.ZMIN
			while z <= VRun.ZMAX and not way:
				way = VRun.hit(x, z, o.u - 1.0, o.u + 1.0, VRun.PAD + 1.0) == ""
				z += 1.0
			x += 1.0
		fair = fair and way
	check(fair, "every obstacle leaves a way through")
	var narrow := 999.0
	var u := 160.0
	while u < VRun.LEN - 200.0:
		narrow = minf(narrow, VRun.passage(u).y * 2.0)
		u += 5.0
	check(narrow >= 38.0, "the passage is never narrower than 38 units (%.0f)" % narrow)
	var motes := VRun.motes()
	check(motes.size() > 30, "motes mark a racing line (%d)" % motes.size())
	var ticks := 0
	u = VRun.SHIP_Y - 280.0
	while u < VRun.LEN:
		u += VRun.speed(u)
		ticks += 1
	check(ticks > 720 and ticks < 1000, "the run lasts about 15 s (%.1f s)" % (ticks / 60.0))
	check(VStage.build(0).any(func(e): return e.type == "run"), "stage 1 has a canyon run")

	print("Run")
	to_run()
	check(vg.G.has("run"), "the canyon's mouth arrives in stage 1")
	check(vg.G.enemies.is_empty() and vg.G.eb.is_empty(), "the sky is cleared for it")
	var scroll0: float = vg.G.scroll
	tick()
	check(vg.G.scroll == scroll0, "the stage holds still during the run")
	# fly the racing line, steering towards the motes like a thumb would
	var swung := false
	var looked := false
	var climbed := false
	var guns: int = vg.G.pb.size()
	while vg.G.has("run"):
		var R: Dictionary = vg.G.run
		var tgt := VRun.line(R.d + 6.0)
		var g := lerpf(1.0, VRun.GAIN, R.k)
		var dx := clampf((tgt.x - vg.P.x) / g, -4.0, 4.0)
		var dy := clampf((tgt.y - vg.P.z) / VRun.GAIN, -4.0, 4.0)
		tick(dx, dy)
		if vg.G.has("run") and vg.G.run.k > 0.99:
			swung = true
			# the camera looks along the canyon (its forward axis is +Y), not down at it
			looked = looked or (-vg.camera.global_transform.basis.z).dot(Vector3.UP) > 0.9
			climbed = climbed or absf(vg.P.z) > 8.0
	check(swung and looked, "the camera swings down behind the ship and looks along the canyon")
	check(climbed, "the thumb flies the ship up and down in the canyon")
	check(vg.G.pb.size() <= guns, "the guns rest during the run")
	check(vg.G.get("run_medal", -2) == 0, "flying the racing line without a touch earns gold")
	check(vg.P.ult >= 1.0, "gold fills the ultimate")
	check(vg.P.hull == vg.HULL, "no hull point lost")
	check(absf((-vg.camera.global_transform.basis.z).dot(Vector3.FORWARD)) > 0.99 and vg.camera.position.z > 200.0, "the camera is back top-down after the run")
	check(vg.P.z == 0.0, "the ship is back on the play plane")
	tick()
	check(vg.G.scroll > scroll0 and vg.G.foff > 0.0, "the stage carries on and the floor keeps its distance")
	var lefts := 0
	for c in vg.chunks.values():
		lefts += int(c.visible)
	check(lefts > 0, "the moon floor shows again")

	print("Touching rock")
	to_run()
	# no steering at all: the first pillar or arch gets the ship
	vg.P.hull = 3
	while vg.G.has("run") and vg.G.run.hits == 0:
		tick()
	check(vg.G.has("run") and vg.P.hull == 2, "touching rock in the canyon costs a hull point")
	# out of hull: the ship blows up, the run ends and the camera swings back
	vg.P.hull = 1
	vg.P.inv = 0
	var lives: int = vg.G.lives
	var n := 0
	while vg.G.has("run") and n < 2000:
		n += 1
		tick(-3.0)
	check(not vg.G.has("run") and vg.G.lives == lives - 1, "losing the ship in the canyon ends the run")
	check(vg.G.get("run_medal", -2) == -1, "no medal for a lost run")
	check(vg.camera.position.z > 200.0, "the camera is back top-down")

	print("FAILED: %d" % fails if fails else "ALL PASSED")
	quit(1 if fails else 0)
