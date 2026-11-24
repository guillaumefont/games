extends SceneTree
## Flies every fortress's whole fight, the break-up included (autopilot lined up on the nearest gun
## as a finger would), and fails on each pass of the ship through the fortress's meshes (hull,
## fittings, masts, superstructure; Guillaume, 2026-11-24: "When shooting down the first fortress I
## passed through its hull") and each jump of the ship or the camera (more than `JUMP` m in a frame;
## "At the end of a fortress section sometimes the plane jumps position").
##   godot --headless --path . --script tests/clearance_test.gd [-- id]

const DT := 1.0 / 60.0
## The ship's half size for the check: a cross of segments this long either way of its centre.
const R := Vector3(1.6, 0.5, 1.2)
const JUMP := 1.5


func _initialize() -> void:
	print("Vantage clearance test")
	var args := OS.get_cmdline_user_args()
	var tmp := "user://clearance_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	var bad := 0
	for id: String in Rules.FORTRESSES:
		if args.size() > 0 and args[0] != id:
			continue
		var g: Game = load("res://scenes/main.tscn").instantiate()
		g.save_path = tmp
		g.driven = true
		g.rng.seed = 5
		root.add_child(g)
		await process_frame
		bad += await fly(g, id)
		g.queue_free()
		await process_frame
	print("ALL PASSED" if bad == 0 else "%d FAILED" % bad)
	quit(1 if bad else 0)


func fly(g: Game, id: String) -> int:
	g.launch(Campaign.FORTRESS_ORDER.find(id))
	g.boss_done = true
	for k in g.waves.size():
		if g.waves[k].kind == "fortress":
			g.wave_i = k
			g.stage_t = g.waves[k].t
	var tris := {}
	var hits := 0
	var last := ""
	var jumps := 0
	var prev := Vector4.INF
	for i in int(500.0 / DT):
		g.hp = maxi(g.hp, 2)
		# a finger on the screen, as in play (lifted, time stops)
		g.touching = true
		if g.phase in ["pov", "core"]:
			var best: Game.Obj = null
			for f in g.foes:
				if f.kind not in ["orb", "boss"] and g.lockable(f) and f.pos.z < g.ppos.z - 4.0:
					if best == null or f.pos.distance_to(g.ppos) < best.pos.distance_to(g.ppos):
						best = f
			if best:
				# as a finger would: quickly, not in one frame
				g.off = g.off.move_toward(g.line_up(best), 30.0 * DT)
		g.step(DT)
		var now := Vector4(g.ppos.x, g.ppos.y, g.cam.global_position.x, g.cam.global_position.y)
		if g.phase in ["pov", "core", "escape"] and prev != Vector4.INF:
			var d := now - prev
			if Vector2(d.x, d.y).length() > JUMP or Vector2(d.z, d.w).length() > JUMP * 1.5:
				print("  %s: jump in %s sec %d: ship %.2f m, camera %.2f m (line %.1f,%.1f adv %.2f/%.2f speed %.2f cam_k %.2f)" % [id, g.phase, g.fort_sec, Vector2(d.x, d.y).length(), Vector2(d.z, d.w).length(), g.line_x, g.chase_y, g.adv_t, g.adv_dur, g.time_speed(), g.cam_k])
				jumps += 1
		prev = now
		if g.fortress == null:
			if g.phase in ["clear", "results"]:
				break
			continue
		if tris.is_empty():
			tris = gather(g)
		var where := hit(g, tris)
		if where != "":
			var tag := "%s %s sec %d" % [g.phase, where, g.fort_sec]
			if tag != last:
				print("  %s: through the %s at %s (model %s)" % [id, tag, g.ppos, g.fort_model(g.ppos)])
				last = tag
			hits += 1
		if g.phase in ["clear", "results"]:
			break
	var ok := hits == 0 and jumps == 0 and g.phase in ["clear", "results"]
	print("  %s %s: the whole fight to the break-up (%s), %d frames inside it, %d jumps" % ["ok  " if ok else "FAIL", id, g.phase, hits, jumps])
	return 0 if ok else 1


## Each mesh on the ship (hull segments and their pieces), its triangles by 4 m along the ship.
func gather(g: Game) -> Dictionary:
	var out := {}
	for seg in g.segs:
		for mi in seg.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.get_parent().get_parent() != seg:
				continue
			var buckets := {}
			for sf in m.mesh.get_surface_count():
				var arr := m.mesh.surface_get_arrays(sf)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var n := idx.size() if idx.size() > 0 else v.size()
				for t in range(0, n, 3):
					var a := v[idx[t] if idx.size() else t]
					var b := v[idx[t + 1] if idx.size() else t + 1]
					var c := v[idx[t + 2] if idx.size() else t + 2]
					var lo := int(floor(-maxf(a.z, maxf(b.z, c.z)) / 4.0))
					var hi := int(floor(-minf(a.z, minf(b.z, c.z)) / 4.0))
					for k in range(lo, hi + 1):
						if not buckets.has(k):
							buckets[k] = PackedVector3Array()
						buckets[k].append_array([a, b, c])
			out[m] = buckets
	return out


func hit(g: Game, tris: Dictionary) -> String:
	for m: MeshInstance3D in tris:
		if not m.is_visible_in_tree():
			continue
		var p := m.to_local(g.ppos)
		var k := int(floor(-p.z / 4.0))
		var bk: Dictionary = tris[m]
		for kk in [k - 1, k, k + 1]:
			if not bk.has(kk):
				continue
			var t: PackedVector3Array = bk[kk]
			for ax: Vector3 in [Vector3(R.x, 0, 0), Vector3(0, R.y, 0), Vector3(0, 0, R.z)]:
				for j in range(0, t.size(), 3):
					if Geometry3D.segment_intersects_triangle(p - ax, p + ax, t[j], t[j + 1], t[j + 2]) != null:
						return String(m.name) + "/" + String(m.get_parent().get_parent().name)
	return ""
