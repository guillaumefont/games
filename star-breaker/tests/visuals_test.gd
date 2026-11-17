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
		if not bm.ult:
			beam = bm
	check(not beam.is_empty() and beam.nova, "lifting at full charge fires the Nova")
	var pulses: Array = (beam.m as Node3D).get_meta("parts").pulses if not beam.is_empty() else []
	var shown := 0
	for pl in pulses:
		if pl.visible:
			shown += 1
	check(pulses.size() == 6 * VFx.PULSES and shown > 6, "the Nova's twister of strands lines the beam (%d of %d pulses shown)" % [shown, pulses.size()])

	# --- Starbreak's strands: many short-lived arcs of static round the laser ---
	var ub := VFx.beam_node(4, true)
	var ps: Array = ub.get_meta("parts").pulses
	VFx.sync_beam(ub, 4, 300.0, 12.0, 1.0, 1, 1, false)
	var spots := []
	for pl in ps:
		spots.append(pl.y)
	for f in VFx.ARC_LIFE.y + 1:
		VFx.sync_beam(ub, 4, 300.0, 12.0, 1.0, 2 + f, 2 + f, false)
	var jumped := 0
	for i in ps.size():
		if ps[i].y != spots[i]:
			jumped += 1
	check(ps.size() >= 30, "Starbreak crackles with many arcs (%d)" % ps.size())
	check(jumped >= ps.size() - 2, "each arc is short lived and jumps elsewhere within %d ticks (%d of %d)" % [VFx.ARC_LIFE.y + 1, jumped, ps.size()])
	var pl0: Dictionary = ps[0]
	var b0: Basis = (pl0.n as Node3D).basis
	var p0: Vector3 = (pl0.n as Node3D).position
	if pl0.t < pl0.life:
		VFx.sync_beam(ub, 4, 300.0, 12.0, 1.0, 20, 20, false)
		check((pl0.n as Node3D).basis.is_equal_approx(b0) and (pl0.n as Node3D).position.is_equal_approx(p0),
			"an arc holds still while it lives (no wobble)")
	ub.free()

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
