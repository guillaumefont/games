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
	check(ticks > 720 and ticks < 1500, "the run lasts 12 to 25 s (%.1f s)" % (ticks / 60.0))
	# the way out is as gentle as the way in: the camera turns no faster on the way out
	var turn_in := 0.0
	var turn_out := 0.0
	var uu := VRun.SHIP_Y - 240.0
	while uu < VRun.LEN:
		var nu := uu + VRun.speed(uu)
		var dk := absf(VRun.swing(nu) - VRun.swing(uu))
		if uu < 500.0:
			turn_in = maxf(turn_in, dk)
		else:
			turn_out = maxf(turn_out, dk)
		uu = nu
	check(turn_out <= turn_in * 1.05, "the camera swings out no faster than it swung in (%.4f vs %.4f a tick)" % [turn_out, turn_in])
	var last := 0.0
	for o in VRun.OBS:
		last = maxf(last, o.u + VRun.half(o) + VRun.DEPTH / 2.0)
	check(last < VRun.OUT, "every obstacle is behind the ship before the camera starts to swing out")
	# bends: real ones, never so tight the rim's back folds over, and straight while the camera swings
	var most := 0.0
	var tight := 0.0
	var bent_swing := 0.0
	var ub := -300.0
	while ub < VRun.LEN + 300.0:
		most = maxf(most, absf(VRun.heading(ub)))
		tight = maxf(tight, absf(VRun.heading(ub + 1.0) - VRun.heading(ub)))
		if VRun.swing(ub) < 0.99:
			bent_swing = maxf(bent_swing, absf(VRun.heading(ub)))
		ub += 1.0
	check(rad_to_deg(most) >= 30.0, "the canyon bends (up to %.0f degrees)" % rad_to_deg(most))
	check(1.0 / tight > 220.0, "no bend tighter than a 220-unit radius (%.0f)" % (1.0 / tight))
	check(bent_swing == 0.0, "the canyon runs straight while the camera swings in and out")
	var straight := VRun.warp(Vector3(10.0, 100.0, 5.0))
	check(straight.distance_to(Vector3(10.0, 100.0, 5.0)) < 0.01, "before its first bend the canyon is built where it always was")
	var mesa := false
	for o in VRun.OBS:
		mesa = mesa or o.k == "mesa"
	check(mesa and VRun.passage(1280.0).y > 45.0, "the canyon opens into a basin split by a mesa")
	check(VStage.build(0).any(func(e): return e.type == "run"), "stage 1 has a canyon run")
	# seamless: it picks up from the stage's scroll speed and hands back to it
	check(VRun.STAGE_SPEED == vg.SCROLL and absf(VRun.speed(VRun.SHIP_Y - 300.0) - vg.SCROLL) < 0.01 and absf(VRun.speed(VRun.LEN) - vg.SCROLL) < 0.01, "the run starts and ends at the stage's own scroll speed")
	check(VRun.floor_z(-60.0) < -68.0 and VRun.floor_z(VRun.LEN - 60.0) < -68.0 and VRun.floor_z(600.0) == VRun.FLOOR, "the canyon's floor starts and ends under the moon's ground")

	print("Run")
	to_run()
	check(vg.G.has("run"), "the canyon's mouth arrives in stage 1")
	check(vg.G.enemies.is_empty() and vg.G.eb.is_empty(), "the sky is cleared for it")
	# regression: the mouth once started ~600 units out and the empty stage stood still ~10 s
	var wait := 0
	var d_probe: float = vg.G.run.d
	while d_probe < 0.0:
		d_probe += VRun.speed(d_probe)
		wait += 1
	check(wait < 240, "the canyon's mouth reaches the ship within 4 s of the run starting (%.1f s)" % (wait / 60.0))
	var dark := 0
	for gi in vg.G.run.casters:
		dark += int(gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	check(vg.G.run.casters.size() > 0 and dark == 0, "the canyon throws no shadow on the screen as it starts")
	var scroll0: float = vg.G.scroll
	tick()
	check(vg.G.scroll == scroll0, "the stage holds still during the run")
	# fly the racing line, steering towards the motes like a thumb would
	var swung := false
	var looked := false
	var climbed := false
	var guns: int = vg.G.pb.size()
	# the ground under the ship (the moon while it shows, then the canyon) never jumps in speed
	var last_v := -1.0
	var jolt := 0.0
	var last_f: float = vg.G.scroll + vg.G.foff
	# the ship stays in sight while the camera swings down behind it and back up (it once fell
	# off the bottom of the screen for about a second each way)
	var vp: Vector2 = vg.get_viewport().get_visible_rect().size
	var off_screen := 0.0
	var in_rock := 0
	while vg.G.has("run"):
		var R: Dictionary = vg.G.run
		var tgt := VRun.line(R.d + 6.0)
		var g := lerpf(1.0, VRun.GAIN, R.k)
		var dx := clampf((tgt.x - vg.P.x) / g, -4.0, 4.0)
		var dy := clampf((tgt.y - vg.P.z) / VRun.GAIN, -4.0, 4.0)
		var rd0: float = R.d
		tick(dx, dy)
		var v: float = (vg.G.run.d - rd0) if vg.G.has("run") else (vg.G.scroll + vg.G.foff - last_f)
		last_f = vg.G.scroll + vg.G.foff
		if last_v >= 0.0:
			jolt = maxf(jolt, absf(v - last_v))
		last_v = v
		if vg.G.has("run"):
			var cr: Dictionary = vg.G.run
			var sp: Vector2 = vg.camera.unproject_position(vg.ship_m.global_position) / vp
			var edge := maxf(maxf(0.1 - sp.x, sp.x - 0.9), maxf(0.1 - sp.y, sp.y - 0.9))
			if vg.camera.is_position_behind(vg.ship_m.global_position):
				edge = 1.0
			off_screen = maxf(off_screen, edge)
			if cr.k > 0.99 and cr.has("cam_x") and VRun.hit(cr.cam_x, cr.cz, cr.d - 38.5, cr.d - 37.5, 0.5) != "":
				in_rock += 1
		if vg.G.has("run") and vg.G.run.k > 0.99:
			swung = true
			# the camera looks along the canyon (its forward axis is +Y), not down at it
			looked = looked or (-vg.camera.global_transform.basis.z).dot(Vector3.UP) > 0.9
			climbed = climbed or absf(vg.P.z) > 8.0
	check(off_screen <= 0.0, "the ship stays in sight, at least a tenth of the screen from its edges, through the whole run (worst %.2f past)" % off_screen)
	check(in_rock == 0, "the camera never flies into rock behind the ship (%d ticks)" % in_rock)
	check(swung and looked, "the camera swings down behind the ship and looks along the canyon")
	check(climbed, "the thumb flies the ship up and down in the canyon")
	check(vg.G.pb.size() <= guns, "the guns rest during the run")
	check(vg.G.get("run_medal", -2) == 0, "flying the racing line without a touch earns gold")
	check(vg.P.ult >= 1.0, "gold fills the ultimate")
	check(vg.P.hull == vg.HULL, "no hull point lost")
	check(absf((-vg.camera.global_transform.basis.z).dot(Vector3.FORWARD)) > 0.99 and vg.camera.position.z > 200.0, "the camera is back top-down after the run")
	check(vg.P.z == 0.0, "the ship is back on the play plane")
	var f0: float = vg.G.scroll + vg.G.foff
	tick()
	jolt = maxf(jolt, absf(vg.G.scroll + vg.G.foff - f0 - last_v))
	check(jolt < 0.1, "the ground's speed changes smoothly in, through and out of the run (biggest step %.3f a tick)" % jolt)
	check(vg.G.scroll > scroll0 and vg.G.foff > 0.0, "the stage carries on and the floor keeps its distance")
	var lefts := 0
	for c in vg.chunks.values():
		lefts += int(c.visible)
	check(lefts > 0, "the moon floor shows again")

	print("Thumb up")
	to_run()
	vg._touch_seen = true
	for i in 400:
		vg.P.inv = 5
		vg.inp = {hold = false, fire = false, dx = 0.0, dy = 0.0, ult = false, pause = false}
		vg.update()
	check(vg.mode == "play", "lifting the thumb in the canyon run doesn't pause the game")
	vg._touch_seen = false

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
