extends SceneTree
## Plays stages headlessly with a simple dodging bot (no god mode) and logs what happens:
## hull hits with their likely cause, the canyon run, boss fight length, how often a ship's
## ultimate loads. A quick way to see whether a new ship can clear stages and how fast.
## godot --headless --path . --script tools/playbot.gd -- <stage,...> <ship>

var vg: Node3D
var log_lines := []


func L(s: String) -> void:
	print(s)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var stages := [0]
	var ships := ["lance", "warden"]
	if args.size() > 0:
		stages = []
		for s in args[0].split(","):
			stages.append(int(s))
	if args.size() > 1:
		ships = [args[1]]
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.set_process(false)
	await process_frame
	for ship in ships:
		for st in stages:
			play(st, ship)
	quit()


func danger_at(x: float, y: float, ahead: int) -> float:
	var d := 0.0
	for b in vg.G.eb:
		for k in [0, 4, 8, ahead]:
			var bx: float = b.x + b.vx * k
			var by: float = b.y + b.vy * k
			var r := Vector2(bx - x, by - y).length()
			if r < 9.0:
				d += (9.0 - r) * (1.0 + (ahead - k) * 0.1)
	for e in vg.G.enemies:
		if e.ground and e.type != "block":
			continue
		if absf(e.x - x) < e.hw + 5 and absf(e.y - y) < e.hh + 5:
			d += 30.0
	for b in vg.G.bars:
		if vg.bar_solid(b, x, y, 5.0):
			d += 50.0
	if vg.in_rock(x, y, 5.0):
		d += 50.0
	return d


func play(st: int, ship: String) -> void:
	vg.start_stage(st, ship, 0)
	var sd: Dictionary = VStage.STAGES[st]
	L("=== stage %d %s (%s) ship %s length %d end %s run %s" % [st, sd.id, sd.name, ship, sd.length, sd.get("end", "?"), sd.has("run")])
	var hold_t := 0
	var hull: int = vg.P.hull
	var lives: int = vg.G.lives
	var run_t0 := -1
	var boss_t0 := -1
	var seen_boss := false
	var n := 0
	var ages := {}
	var stuck_reported := {}
	var shat_max := 0.0
	var shat_fired := 0
	var off_boss := 0
	var lift_cd := 0
	while vg.mode == "play" and n < 60 * 60 * 6:
		n += 1
		var dx := 0.0
		var dy := 0.0
		var hold := true
		if vg.G.has("run"):
			if run_t0 < 0:
				run_t0 = n
				L("  t=%d run starts at scroll %.0f" % [n, vg.G.scroll])
			var R: Dictionary = vg.G.run
			var tgt := VRun.line(R.d + 6.0)
			var g := lerpf(1.0, VRun.GAIN, R.k)
			dx = clampf((tgt.x - vg.P.x) / g, -4.0, 4.0)
			dy = clampf((tgt.y - vg.P.z) / VRun.GAIN, -4.0, 4.0)
		elif vg.P.get("alive", false) and not vg.P.get("entering", true):
			# target: nearest airborne enemy / boss part x, stay low
			var tx: float = vg.W / 2.0
			var best := 1e9
			for e in vg.G.enemies:
				if e.y > vg.P.y and e.y < 220 and not e.get("dead", false):
					var s: float = absf(e.x - vg.P.x) + (e.y - vg.P.y) * 0.2
					if s < best:
						best = s
						tx = e.x
			for p in vg.G.bparts:
				if p.kind == "shield" or p.kind == "seg" or (p.has("o") and p.o is Dictionary and (p.o.get("armour", false) or not p.o.get("alive", true))):
					continue
				var s2: float = absf(p.x - vg.P.x) * 0.5
				if s2 < best:
					best = s2
					tx = p.x
			var ty := 45.0
			if ship == "warden" and (not vg.G.boss.is_empty() or vg.G.get("mid_boss", false)):
				ty = 60.0
			var wy := 0.15
			if ship == "weaver":
				# fly loops round the nearest enemy in reach
				var cd := 60.0
				var cc := Vector2(vg.P.x, 55.0)
				for e in vg.G.enemies:
					var ed: float = Vector2(e.x - vg.P.x, e.y - vg.P.y).length()
					if e.y < 150 and e.y > 20 and ed < cd:
						cd = ed
						cc = Vector2(e.x, e.y - 4.0)
				if cd < 60.0:
					tx = cc.x + cos(n * 0.14) * 14.0
					ty = cc.y + sin(n * 0.14) * 14.0
					wy = 0.3
			var bestc := 1e9
			for cx in [-3.0, -1.5, 0.0, 1.5, 3.0]:
				for cy in [-3.0, -1.5, 0.0, 1.5, 3.0]:
					var nx: float = clampf(vg.P.x + cx, 5, vg.W - 5)
					var ny: float = clampf(vg.P.y + cy, 8, vg.H - 30)
					var c := danger_at(nx, ny, 12) * 10.0 + absf(nx - tx) * 0.3 + absf(ny - ty) * wy
					if c < bestc:
						bestc = c
						dx = cx
						dy = cy
			# ship release: Lance lifts for LV2 every ~2.5 s; kit ships lift every 1.5 s or when the ultimate is ready
			hold_t += 1
			if lift_cd > 0:
				lift_cd -= 1
			if ship == "lance" and hold_t > 110:
				hold = false
				hold_t = 0
			if ship == "weaver":
				# fly loops round the dodging path, and lift the moment one closes
				if not vg.kit.loop.is_empty() and vg.kit.loom == 0:
					hold = false
			if vg.kit and lift_cd == 0 and (vg.kit.ready() or hold_t > 90 or ("stored" in vg.kit and vg.kit.stored >= 8)):
				if vg.kit.ready():
					shat_fired += 1
				hold = false
				hold_t = 0
				lift_cd = 20
		vg.inp = {hold = hold, fire = hold, dx = dx, dy = dy, ult = false, pause = false}
		vg.update()
		vg._process(1.0 / 60.0)
		if vg.mode != "play":
			break
		if vg.G.has("run") == false and run_t0 > 0 and not ages.has("_runend"):
			ages["_runend"] = 1
			L("  t=%d run ends after %.1f s, medal %d, hull %d" % [n, (n - run_t0) / 60.0, vg.G.get("run_medal", -9), vg.P.hull])
		if vg.G.get("mid_boss", false) or not vg.G.boss.is_empty():
			if not seen_boss:
				seen_boss = true
				boss_t0 = n
				L("  t=%d boss/mid-boss '%s' arrives, scroll %.0f (length %d)" % [n, vg.hud.boss_name, vg.G.scroll, sd.length])
			# boss bodies on screen?
			var any_on := false
			for e in vg.G.enemies:
				if e.get("boss", false) and e.y < vg.H + 5 and e.y > -5:
					any_on = true
			for p in vg.G.bparts:
				if p.y < vg.H + 5 and p.y > -5:
					any_on = true
			if not any_on and n - boss_t0 > 400:
				off_boss += 1
		if OS.has_environment("BOSSDUMP") and not vg.G.boss.is_empty() and n % 300 == 0:
			var B: Dictionary = vg.G.boss
			var ps := []
			for p in B.get("list", []):
				ps.append("%s:%.0f%s%s(%.0f,%.0f)" % [p.key, p.hp, "A" if p.armour else "", "" if p.alive else "x", p.x, p.y])
			L("    boss t=%d at (%.0f,%.0f) enter=%s open=%s ship(%.0f,%.0f) pb=%d %s" % [n, B.x, B.y, B.enter, B.get("open", "-"), vg.P.x, vg.P.y, vg.G.pb.size(), " ".join(ps)])
		if vg.G.clear_t == 1 and boss_t0 > 0:
			L("  t=%d stage clear, boss fight %.1f s" % [n, (n - boss_t0) / 60.0])
		if vg.kit:
			shat_max = maxf(shat_max, vg.kit.meter)
		# hits
		if vg.P.get("alive", false) and (vg.P.get("hull", 0) < hull or vg.G.lives < lives):
			var cause := "?"
			var near := []
			for b in vg.G.eb:
				if Vector2(b.x - vg.P.x, b.y - vg.P.y).length() < 6:
					near.append("bullet")
			if vg.in_rock(vg.P.x, vg.P.y, 1.0):
				near.append("rock")
			for e in vg.G.enemies:
				if absf(e.x - vg.P.x) < e.hw + 4 and absf(e.y - vg.P.y) < e.hh + 4:
					near.append(e.type)
			for bb in vg.G.bars:
				if vg.bar_solid(bb, vg.P.x, vg.P.y, 6.0):
					near.append("bar")
			if vg.G.has("run"):
				near.append("run")
			cause = str(near)
			L("  t=%d HIT at (%.0f,%.0f) scroll %.0f hull %d lives %d %s" % [n, vg.P.x, vg.P.y, vg.G.scroll, vg.P.get("hull", 0), vg.G.lives, cause])
		hull = vg.P.get("hull", hull) if vg.P.get("alive", false) else 3
		lives = vg.G.lives
		# enemies alive very long
		for e in vg.G.enemies:
			ages[e.id] = ages.get(e.id, 0) + 1
			if ages[e.id] > 60 * 40 and not stuck_reported.has(e.id) and not e.get("boss", false) and not e.ground:
				stuck_reported[e.id] = true
				L("  t=%d enemy %s alive 40 s at (%.0f,%.0f)" % [n, e.type, e.x, e.y])
	var rep: Dictionary = vg.G.get("report", {})
	L("  END mode=%s after %.1f s, cleared=%s score=%d hits=%d lives=%d foes %d/%d breakables %d/%d boss_ticks %d" % [vg.mode, n / 60.0, rep.get("cleared", "?"), vg.G.get("score", 0), vg.G.get("hits", 0), vg.G.get("lives", 0), vg.G.get("foes_killed", 0), vg.G.get("foes", 0), vg.G.get("broken", 0), vg.G.get("breakables", 0), vg.G.get("boss_ticks", -1)])
	if off_boss > 0:
		L("  boss off screen for %.1f s during the fight" % (off_boss / 60.0))
	if ship != "lance":
		L("  ult meter max %.2f, ult fired %d" % [shat_max, shat_fired])
	vg.to_menu()
