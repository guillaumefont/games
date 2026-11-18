extends SceneTree
## Nothing pops in on screen: plays stages on a tall phone and watches every model the game
## puts in the world. A model (or its shadow on the ground) may only come into view from
## outside the screen's edges, unless it emerges from something already on screen (a shot,
## a blast, a brood) and says so with the "emerges" meta. Run with -- <stage> [<stage> ...]
## to pick stages; by default one stage per world, a fortress and the canyon run.

var VP := Vector2i(540, 1170)  ## a 9:19.5 phone (vp=WxH picks another screen)
var vg: Node3D
var fails := 0
var seen := {}      ## instance id -> was on screen last tick (object or shadow)
var reports := {}   ## what -> count
var zg := -68.0     ## the ground's height in the world (shadows land there)
var L := Vector3.ZERO
var cap := 99999
var boss_nodes := {}  ## models added in the tick a boss appeared


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		fails += 1


func _corners(a: AABB) -> Array:
	var out := []
	for i in 8:
		out.append(a.get_endpoint(i))
	return out


## Screen rects of a model and of its shadow (size zero when there's none).
func _rects(root: Node) -> Array:
	var cam: Camera3D = vg.camera
	var obj := Rect2()
	var sh := Rect2()
	var has_o := false
	var has_s := false
	var stack := [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var gi := n as GeometryInstance3D
		if gi == null or not gi.is_visible_in_tree() or gi is MultiMeshInstance3D:
			continue
		var a := gi.get_aabb()
		if a.size.length() < 0.001:
			continue
		var g := gi.global_transform * a
		for p in _corners(g):
			if cam.is_position_behind(p):
				continue
			var s := cam.unproject_position(p)
			obj = Rect2(s, Vector2.ZERO) if not has_o else obj.expand(s)
			has_o = true
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and gi.transparency < 0.99:
			for p in _corners(g):
				if p.z <= zg:
					continue
				var q: Vector3 = p + L * ((zg - p.z) / L.z)
				var s := cam.unproject_position(q)
				sh = Rect2(s, Vector2.ZERO) if not has_s else sh.expand(s)
				has_s = true
	return [has_o, obj, has_s, sh]


func _on(r: Rect2, grow: float) -> bool:
	return Rect2(Vector2.ZERO, Vector2(VP)).grow(grow).intersects(r)


func _ctx(n: Node, r: Rect2) -> String:
	var run := ""
	if vg.G.has("run"):
		run = ", in the canyon run (k %.2f)" % vg.G.run.k
	return ", at %s on screen %s, %s%s" % [(n as Node3D).position.snapped(Vector3.ONE * 0.1), r, _desc(n), run]


func _desc(n: Node) -> String:
	var out := []
	var stack := [n]
	while not stack.is_empty() and out.size() < 4:
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi := c as MeshInstance3D
			var mat := mi.get_active_material(0)
			out.append("%s/%s" % [mi.mesh.get_class(), (mat as BaseMaterial3D).albedo_color.to_html(false) if mat is BaseMaterial3D else "?"])
	return ", ".join(out)


func _name(n: Node) -> String:
	var s := n.name as String
	if n.has_meta("what"):
		s = n.get_meta("what")
	elif n is MeshInstance3D and (n as MeshInstance3D).mesh:
		s = (n as MeshInstance3D).mesh.resource_name if (n as MeshInstance3D).mesh.resource_name != "" else s
	return s.rstrip("0123456789@")


## What each model is, from the game's own lists. Shots, beams, shards and blasts come out of
## things already on screen, so they're allowed to appear there.
func _labels() -> Dictionary:
	var out := {}
	var G: Dictionary = vg.G
	for k in ["pb", "eb", "beams", "shards", "fx"]:
		for o in (vg.fx if k == "fx" else G.get(k, [])):
			if o.get("m") is Node:
				out[o.m.get_instance_id()] = ""
	for e in G.get("enemies", []):
		if e.get("m") is Node:
			# the boss's brood hatches out of the boss, kills drop no models
			out[e.m.get_instance_id()] = "" if e.get("score", 1) == 0 else "enemy " + str(e.get("type", "?"))
	for it in G.get("items", []):
		if it.get("m") is Node:
			out[it.m.get_instance_id()] = ""  # dropped by something on screen
	for b in G.get("bars", []):
		for k in ["m", "node", "f"]:
			if b.get(k) is Node:
				out[b[k].get_instance_id()] = "fortress bar"
	for pr in G.get("props", []):
		if pr.get("m") is Node:
			out[pr.m.get_instance_id()] = "prop " + str(pr.get("kind", ""))
	for isl in G.get("islands", []):
		if isl.get("m") is Node:
			out[isl.m.get_instance_id()] = "island"
	if G.get("boss", {}).get("m") is Node:
		out[G.boss.m.get_instance_id()] = "boss " + str(G.boss.get("kind", ""))
	# the ship blinks while it's shielded and the pod bursts and reforms: both on purpose (the
	# ship coming back is checked on its own, in `play`)
	for n in [vg.ship_m, vg.shield_m, vg.charge_fx, vg.pod_m]:
		if n is Node:
			out[n.get_instance_id()] = ""
	# the ground streams in with the scroll
	for c in vg.chunks.values():
		out[c.get_instance_id()] = ""
	for n in [vg.beam_light]:
		if n is Node:
			out[n.get_instance_id()] = ""
	if vg.run_b != null:
		out[vg.run_b.node.get_instance_id()] = "canyon run"
	# a boss is many models: name them all after it
	if G.get("boss", {}).has("m"):
		for n in vg.world.get_children():
			if not out.has(n.get_instance_id()) and boss_nodes.has(n.get_instance_id()):
				out[n.get_instance_id()] = "boss " + str(G.boss.get("kind", ""))
	return out


func watch(stage_i: int) -> void:
	var now := {}
	var labels := _labels()
	for root in vg.world.get_children():
		if not (root is Node3D) or root.is_queued_for_deletion():
			continue
		var id: int = root.get_instance_id()
		# anything the game doesn't list is checked too, so a new kind of model can't slip by
		var what: String = labels.get(id, "a model (%s)" % _desc(root))
		if what == "" or root.has_meta("emerges"):
			continue
		var r: Array = _rects(root)
		var on_o: bool = r[0] and _on(r[1], -3.0)
		var on_s: bool = r[2] and _on(r[3], -3.0)
		# moving in from an edge is fine; showing up inside the screen is not
		var deep_o: bool = r[0] and _on(r[1], -40.0)
		var deep_s: bool = r[2] and _on(r[3], -40.0)
		var was: Array = seen.get(id, [false, false])
		if on_o and not was[0] and (deep_o or not seen.has(id)):
			_report("stage %d: %s appears on screen" % [stage_i, what], _ctx(root, r[1]))
		elif on_s and not was[1] and (deep_s or not seen.has(id)):
			_report("stage %d: the shadow of %s appears on screen" % [stage_i, what], _ctx(root, r[3]))
		now[id] = [on_o, on_s]
	seen = now


func _report(what: String, extra := "") -> void:
	if not reports.has(what):
		print("    ", what, " (t=%d, scroll=%.0f%s)" % [vg.G.t, vg.G.scroll, extra])

	reports[what] = reports.get(what, 0) + 1


func play(i: int) -> void:
	vg.start_stage(i, "lance" if i % 2 == 0 else "warden")
	vg._on_resize()
	seen = {}
	# the first frame of a stage builds it all at once, behind the stage card
	vg.update()
	vg._process(1.0 / 60.0)
	for root in vg.world.get_children():
		seen[root.get_instance_id()] = [true, true]
	var limit := mini(int(VStage.STAGES[i].length / vg.SCROLL) + 2400, cap)
	for t in limit:
		if vg.mode != "play":
			break
		vg.inp = {hold = true, fire = true, dx = sin(t * 0.021) * 1.2, dy = 0.0, ult = t % 900 == 450, pause = false}
		if vg.P.alive:
			vg.P.inv = maxi(vg.P.inv, 2)
		vg.P.ult = 1.0 if t % 900 == 449 else vg.P.ult
		# lose the ship now and then: it must come back in from below the screen
		if t % 1500 == 700 and vg.P.alive and not vg.P.entering:
			vg.kill_player()
			vg.G.lives += 1
		var was_alive: bool = vg.P.alive
		var had_boss: bool = not vg.G.boss.is_empty()
		var before := {}
		for n in vg.world.get_children():
			before[n.get_instance_id()] = true
		vg.update()
		vg._process(1.0 / 60.0)
		if not had_boss and not vg.G.boss.is_empty():
			for n in vg.world.get_children():
				if not before.has(n.get_instance_id()):
					boss_nodes[n.get_instance_id()] = true
		if vg.P.alive and not was_alive:
			var r: Array = _rects(vg.ship_m)
			var r2: Array = _rects(vg.pod_m) if vg.pod_m != null else [false]
			if (r[0] and _on(r[1], -3.0)) or (r[2] and _on(r[3], -3.0)) or (r2[0] and _on(r2[1], -3.0)):
				_report("stage %d: the ship comes back on screen" % i)
		watch(i)
		if t % 30 == 0:
			await process_frame  # lets freed models go


func _initialize() -> void:
	print("Star Breaker pop-in test")
	var stages := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("vp="):
			var wh := a.substr(3).split("x")
			VP = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("cap="):
			cap = int(a.substr(4))
		else:
			stages.append(int(a))
	if stages.is_empty():
		stages = range(VStage.STAGES.size())
	Diag.set_safe(false)
	# the game sizes its camera from its viewport: give it a phone-shaped one
	var sv := SubViewport.new()
	sv.size = VP
	root.add_child(sv)
	vg = load("res://scenes/main.tscn").instantiate()
	sv.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	vg.pause_on_focus_out = false
	await process_frame
	L = -vg.sun.global_transform.basis.z
	print("  a %dx%d screen, %d stages" % [VP.x, VP.y, stages.size()])
	for i in stages:
		var t0 := Time.get_ticks_msec()
		await play(i)
		print("  stage %d (%s): %d ticks, %d s" % [i, VStage.STAGES[i].name, vg.G.t, (Time.get_ticks_msec() - t0) / 1000])
	check(reports.is_empty(), "nothing pops in on screen, shadows included (%d kinds of pop-in)" % reports.size())
	print("ALL OK" if fails == 0 else "FAILED: %d" % fails)
	quit(1 if fails else 0)
