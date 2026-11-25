extends SceneTree
## The campaign's own foes (`Foes`): one new kind a level, met first thing and announced, kept in
## later levels; each kind comes in from off-screen, shows, attacks, flashes when hit and goes down.
##   godot --headless --path . --script tests/foes_test.gd

const SAVE := "user://test_foes_save.json"
const DT := 1.0 / 60.0

var fails := 0


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		print("  FAIL ", what)
		fails += 1


func roster() -> void:
	print("one new kind a level, kept after")
	check(Foes.INTRO.size() == Campaign.count(), "a new kind for each of the %d levels" % Campaign.count())
	var seen := {}
	for k: String in Foes.INTRO:
		check(not seen.has(k) and Rules.FOES.has(k) and Foes.NAMES.has(k) and Foes.mesh(k) != null, "%s: stats, a name and a model" % k)
		seen[k] = true
		check((k in Rules.RAMMABLE) != (Foes.is_ground(k) or k in Foes.HARMLESS), "%s: %s" % [k, "on the ground, passes under the ship" if Foes.is_ground(k)
			else ("harmless, the ship flies through it" if k in Foes.HARMLESS else "in the air, can be rammed")])
	for lv in Campaign.count():
		var ws: Array = Campaign.waves(lv)
		var kinds := {}
		for w: Dictionary in ws:
			kinds[w.kind] = true
		var first: Dictionary = ws[0]
		var d := Campaign.debut(lv)
		if lv == Campaign.PER_WORLD - 1:
			check(kinds.has(d), "%s (hand-made) has its new kind, %s" % [Campaign.code(lv), d])
		else:
			check(first.kind == d, "%s opens on its new kind, %s" % [Campaign.code(lv), d])
		var met := 0
		for k in range(lv):
			if kinds.has(Foes.INTRO[k]):
				met += 1
		var old := 0
		for k: String in ["dart", "swing", "turret", "heavy"]:
			if kinds.has(k) or k == "turret" and Towers.TYPES.any(func(t: String) -> bool: return kinds.has(t)):
				old += 1
		check(old >= 1, "%s keeps the first foes (%d of 4 kinds)" % [Campaign.code(lv), old])
		if lv >= 3 and lv != Campaign.PER_WORLD - 1:
			check(met >= 1, "%s brings back kinds met before (%d)" % [Campaign.code(lv), met])
		var mix := Campaign.mix_of(lv)
		check(mix.has(d) and not mix.has(Foes.INTRO[mini(lv + 1, Foes.INTRO.size() - 1)]) or lv == Campaign.count() - 1,
			"%s: nothing from later levels yet" % Campaign.code(lv))


func make_game() -> Game:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var g: Game = load("res://scenes/main.tscn").instantiate()
	g.save_path = SAVE
	g.driven = true
	root.add_child(g)
	g.rng.seed = 5
	return g


func each_kind() -> void:
	print("each kind: in from off-screen, on screen, attacks, flashes, goes down")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	for lv in Foes.INTRO.size():
		var kind: String = Foes.INTRO[lv]
		g.launch(lv)
		g.step(DT)
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()   # no other waves
		var rng := RandomNumberGenerator.new()
		rng.seed = lv
		var w := Campaign.new_wave(kind, rng, 1.0)
		var before := g.foes.size()
		var mine: Array[Game.Obj] = []
		var inside := 0
		var shown := 0.0
		var fired := 0
		var closest := 1e9
		var t := 0.0
		var next := 0
		while t < 14.0:
			while next < int(w.n) and t >= next * float(w.gap):
				g.spawn_vert(kind, float(w.x), next, int(w.n), w.get("from", "top"))
				var f: Game.Obj = g.foes[g.foes.size() - 1]
				f.hp = 1e6   # the autofire would bring it down: this is about its flight
				if g.on_screen(f):
					inside += 1
				mine.append(f)
				next += 1
			var nb := g.bullets.size()
			g.hp = 5
			g.inv = 1.0   # no rams: this watches the foe
			g.prel.x = sin(t * 0.7) * 3.0
			g.step(DT)
			t += DT
			fired += maxi(0, g.bullets.size() - nb)
			var any := false
			for f in mine:
				if f in g.foes and not f.dead:
					any = true
					closest = minf(closest, g.flat_dist(g.seen(f.pos), g.ppos))
					if g.on_screen(f):
						shown += DT
			if not any and next >= int(w.n):
				break
		check(g.foes.size() >= before and inside == 0, "%s: comes in from off-screen" % kind)
		check(shown >= 1.5, "%s: shows on screen (%.1f s)" % [kind, shown])
		if kind == "seeker":
			check(closest < 2.5, "%s: flies at the ship (%.1f m)" % [kind, closest])
		elif kind in Foes.HARMLESS:
			check(fired == 0, "%s: harmless, never fires (%d shots)" % [kind, fired])
		else:
			check(fired > 0, "%s: fires (%d shots)" % [kind, fired])
		# hit flash on the body and its moving parts, then down
		g.clear_all()
		g.spawn_vert(kind, 0.0, 0, 1)
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.under = false
		g.damage(f, 0.5)
		g.update_objs(0.0)
		var mi := f.node as MeshInstance3D
		var parts_flash := true
		for c in mi.get_children():
			if c.has_meta("part"):
				parts_flash = parts_flash and (c as MeshInstance3D).material_overlay != null
		check(mi.material_overlay != null and parts_flash, "%s: flashes when hit" % kind)
		var kills: int = g.run.kills
		g.damage(f, 1e6)
		check(f.dead and g.run.kills == kills + (0 if g.civilian(f) else 1), "%s: goes down%s" % [kind, ", not a kill (a civilian)" if g.civilian(f) else ""])
	g.queue_free()
	await process_frame


## Guillaume (2026-11-24): foes that fly in and hold stopped "much too far from the ship" near the
## top of tall screens. They hold a few metres above the screen's centre, and come in from a side
## when the way down from the top edge is too long.
func holds() -> void:
	print("holders stop near the screen's centre, from a side on tall screens")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	g.launch(0)
	g.step(DT)
	for tall in [false, true]:
		for kind: String in ["rotor", "scarab", "lancer", "prism", "heavy", "gunship"]:
			g.clear_all()
			g.queue.clear()
			g.wave_i = g.waves.size()
			g.update_view()
			if tall:
				# a 9:20 phone: the top edge far above the ship
				g.view_top = -29.0
				g.view_hw_top = 12.6
			var mid := g.view_mid
			g.spawn_vert(kind, 2.0, 0, 2, "top")
			var f: Game.Obj = g.foes[g.foes.size() - 1]
			f.hp = 1e6
			var start := f.pos - Vector3(0, 0, g.frame_z)
			var from_side := absf(start.x) > g.view_hw(start.z) + 1.0
			if tall:
				check(from_side or kind == "heavy" and absf(start.x) > 9.0, "%s: in from a side on a tall screen (x %.1f)" % [kind, start.x])
			else:
				check(not g.side_entry(f.goal.z) or from_side, "%s: from the top only when the way down is short" % kind)
			var t := 0.0
			var near := 1e9
			while t < 2.6:
				g.hp = 5
				g.inv = 1.0
				g.step(DT)
				t += DT
				if tall:
					g.view_top = -29.0
					g.view_hw_top = 12.6
			var z := f.pos.z - g.frame_z
			near = z - mid
			check(near > -10.0 and near < 4.0 and absf(f.pos.x) < 8.0,
				"%s: holds near the screen's centre (%.1f m off it, ship %.1f m below)" % [kind, near, g.prel.y - z])
	g.queue_free()
	await process_frame


## Guillaume (2026-11-24): "Hydro planes should be a collateral damage, not an enemy. It should
## stroll by (alone) waiting to be shot." Swarms and holding lines still don't stack.
func formations() -> void:
	print("seaplanes stroll by alone and harmless, swarms keep apart")
	for lv in Campaign.count():
		for w: Dictionary in Campaign.waves(lv):
			if w.kind == "gull":
				check(int(w.n) == 1, "%s: seaplanes come one at a time (%d)" % [Campaign.code(lv), int(w.n)])
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	g.launch(0)
	g.step(DT)
	for from: String in ["left", "right"]:
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		g.spawn_vert("gull", 0.0, 0, 1, from)
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.hp = 1e6
		var hp0 := g.hp
		var shown := 0.0
		var x0 := f.pos.x
		var fired := false
		var t := 0.0
		while t < 14.0 and f in g.foes:
			g.inv = 0.0
			# the ship sits right in its path
			g.prel = Vector2(clampf(f.pos.x, -5.0, 5.0), f.pos.z - g.frame_z)
			g.step(DT)
			t += DT
			fired = fired or g.bullets.size() > 0
			if f in g.foes and g.on_screen(f):
				shown += DT
		check(signf(x0) == (-1.0 if from == "left" else 1.0) and (f not in g.foes or signf(f.pos.x) != signf(x0)),
			"from the %s: crosses the screen (%.1f m to %.1f m)" % [from, x0, f.pos.x])
		check(shown > 4.0, "from the %s: lazy, on screen %.1f s" % [from, shown])
		check(not fired and g.hp == hp0, "from the %s: never fires, flying into it costs nothing" % from)
	g.queue_free()
	await process_frame
	g = make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	g.launch(0)
	g.step(DT)
	# Guillaume (2026-11-25): rows from the top and the sides bunched up, the ones from behind didn't
	var groups := [["seeker", 6, "top", 0.28], ["dart", 6, "back", 0.3], ["dart", 6, "top", 0.27], ["dart", 6, "left", 0.3],
		["dart", 6, "right", 0.3], ["swing", 6, "top", 0.37], ["rotor", 3, "top", 0.5], ["scarab", 3, "top", 0.6],
		["lancer", 3, "top", 0.6], ["ember", 4, "top", 0.5], ["prism", 2, "top", 1.0],
		["rotor", 3, "tall", 0.5], ["scarab", 3, "tall", 0.6], ["lancer", 3, "tall", 0.6]]
	var view := [g.view_top, g.view_hw_top]
	for grp: Array in groups:
		# a tall phone: those that hold come in from the sides
		var tall: bool = grp[2] == "tall"
		g.view_top = -29.0 if tall else view[0]
		g.view_hw_top = 12.6 if tall else view[1]
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		var kind: String = grp[0]
		var n: int = grp[1]
		var mine: Array[Game.Obj] = []
		var t := 0.0
		var next := 0
		var closest := 1e9
		while t < 6.0:
			while next < n and t >= next * float(grp[3]):
				g.spawn_vert(kind, 4.5 if grp[2] == "back" else 0.0, next, n, "top" if tall else grp[2])
				var f: Game.Obj = g.foes[g.foes.size() - 1]
				f.hp = 1e6
				mine.append(f)
				next += 1
			g.hp = 5
			g.inv = 1.0
			g.prel.x = sin(t * 0.9) * 3.0
			if tall:
				g.view_top = -29.0
				g.view_hw_top = 12.6
			g.step(DT)
			t += DT
			for a in mine.size():
				for b in range(a + 1, mine.size()):
					if mine[a] in g.foes and mine[b] in g.foes and g.on_screen(mine[a]) and g.on_screen(mine[b]):
						var d := Vector2(mine[a].pos.x - mine[b].pos.x, mine[a].pos.z - mine[b].pos.z).length()
						closest = minf(closest, d)
		# a little room between their hulls (a nudge, not a wall: a few tenths of give); a scarab or
		# a lancer darting across past another may brush by it, but never runs into it
		var room: float = Rules.FOES[kind].r * 2.0 + (Foes.ROW_GAP - 0.5 if kind not in ["scarab", "lancer"] else -0.3)
		check(closest >= room and closest < 1e8, "%s %s: never closer than %.1f m on screen (%.1f)" % [kind, grp[2], room, closest])
	g.queue_free()
	await process_frame


## Guillaume (2026-11-24): "civil characters can be enemies if they are clearly hacked: a lighthouse
## that opens to show a turret, a hydro plane that unveils a minigun... should we give bad points
## when shooting down a real civil target?" Hacked ones give themselves away before they fire,
## real ones cost points.
func hacked() -> void:
	print("hacked civilians unveil a gun, real ones cost points")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	g.launch(0)
	g.step(DT)
	for lv in Campaign.count():
		var real := 0
		for w: Dictionary in Campaign.waves(lv):
			if w.kind in Rules.CIVILIANS:
				real += int(w.n)
		var all := 0
		for w: Dictionary in Campaign.waves(lv):
			if w.kind == "boss":
				all += Rules.boss_parts(Campaign.midboss_of(lv))
			elif w.kind == "fortress":
				all += Rules.fortress_parts(Campaign.fortress_of(lv))
			elif w.kind != "end":
				all += int(w.n)
		check(Campaign.foes_in(lv) == all - real, "%s: the %d civilians aren't in the kill total" % [Campaign.code(lv), real])
	# a hacked seaplane and a hacked lighthouse: a tell, then the gun, then fire
	for kind: String in ["gull", "lighthouse"]:
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		var f: Game.Obj
		if kind == "gull":
			g.spawn_vert("gull", 0.0, 0, 1, "left")
			f = g.foes[g.foes.size() - 1]
		else:
			f = Game.Obj.new()
			f.kind = "lighthouse"
			f.ground = true
			f.rel = true
			f.hp = 1e6
			f.max_hp = 1e6
			f.r = 2.0
			f.node = Models.instance(Models.landmark("lighthouse", 1.0))
			g.add_child(f.node)
			f.pos = Vector3(3.0, 0.0, g.frame_z + g.view_top + 9.0)
			g.foes.append(f)
		f.hacked = true
		f.hp = 1e6
		check(g.shy(f), "%s: hacked but still hidden, nothing locks onto it" % kind)
		var told := -1.0
		var first := -1.0
		var t := 0.0
		while t < 9.0 and f in g.foes and first < 0.0:
			g.hp = 5
			g.inv = 1.0
			var before := g.bullets.size()
			g.step(DT)
			t += DT
			if told < 0.0 and f.hold >= 0.0:
				told = t
			if g.bullets.size() > before:
				first = t
		var gun := "minigun" if kind == "gull" else "hacked turret"
		check(told >= 0.0 and first > 0.0 and first - told >= Foes.HACK_TELL, "%s: gives itself away %.1f s before it fires (%.1f s)" % [kind, Foes.HACK_TELL, first - told])
		check(f.node.has_node(gun), "%s: unveils its %s" % [kind, gun])
		check(not g.shy(f), "%s: once unveiled, missiles and the guns' assist go for it" % kind)
	# shooting down: a real civilian costs points and drops nothing, a hacked one pays double
	for hack: bool in [false, true]:
		g.clear_all()
		g.queue.clear()
		g.wave_i = g.waves.size()
		g.spawn_vert("gull", 0.0, 0, 1, "left")
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.hacked = hack
		g.run.score = 1000
		var kills: int = g.run.kills
		var drops := g.picks.size()
		g.kill(f)
		var due: int = Rules.FOES.gull.score
		if hack:
			check(g.run.score == 1000 + roundi(due * Rules.HACK_PAY) and g.run.kills == kills + 1 and g.picks.size() > drops,
				"a hacked seaplane pays double and counts as a kill (%d)" % g.run.score)
		else:
			check(g.run.score == 1000 and g.run.kills == kills and g.picks.size() == drops,
				"a real seaplane costs nothing, scores nothing, drops no scrap and isn't a kill (%d)" % g.run.score)
	# Guillaume (2026-11-25): "remove the on-screen notification when you do so"
	g.say("", "", 0.0)
	g.spawn_vert("gull", 0.0, 0, 1, "left")
	g.kill(g.foes[g.foes.size() - 1])
	check(g.banner == "", "downing a civilian isn't announced (%s)" % g.banner)
	# Guillaume (2026-11-25): "when you down a civilian, there's a parachute getting out of the plane"
	var n := g.blasts.chutes.size()
	g.spawn_vert("gull", 0.0, 0, 1, "left")
	var pl: Game.Obj = g.foes[g.foes.size() - 1]
	var at := pl.pos
	g.kill(pl)
	check(g.blasts.chutes.size() == n + 1, "the pilot of a downed seaplane bails out under a parachute")
	var c: Dictionary = g.blasts.chutes[g.blasts.chutes.size() - 1]
	var node: Node3D = c.node
	var peak := -1e9
	for i in int(1.0 / DT):
		g.hp = 5
		g.inv = 1.0
		g.step(DT)
		peak = maxf(peak, node.position.y)
	check(peak > at.y + 0.3 and node.scale.x > 0.9, "it pops up out of the plane and the canopy opens (%.1f m up)" % (peak - at.y))
	for i in int(Blasts.CHUTE_LIFE / DT):
		g.hp = 5
		g.inv = 1.0
		g.step(DT)
	check(c not in g.blasts.chutes and not is_instance_valid(node) or node.is_queued_for_deletion(), "then drifts away and is gone")
	n = g.blasts.chutes.size()
	g.spawn_vert("gull", 0.0, 0, 1, "left")
	pl = g.foes[g.foes.size() - 1]
	pl.hacked = true
	g.kill(pl)
	check(g.blasts.chutes.size() == n, "a hacked seaplane's pilot doesn't bail out")
	g.queue_free()
	await process_frame


## Guillaume (2026-11-25): "There should be no seaplane in the desert. You should replace it in each
## world with something appropriate"; then "Camel and reindeer are a bad idea... You need to have simple
## shapes to keep the realism plausible." Each world's civilian is a simple craft, keeps the seaplane's
## rules and has its own getaway.
func worlds() -> void:
	print("each world has its own civilian, harmless, with its own getaway")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	var seen := {}
	for wi in Campaign.WORLDS.size():
		var lv := wi * Campaign.PER_WORLD
		g.launch(lv)
		g.step(DT)
		var want: String = Civilians.BY_THEME[Campaign.WORLDS[wi].theme]
		seen[want] = true
		check(want == "gull" if wi == 0 else want != "gull", "%s: %s" % [Campaign.WORLDS[wi].name, want])
		check(Civilians.mesh(want).get_faces().size() / 3 < 1500, "%s: a simple low poly shape (%d triangles)" % [want, Civilians.mesh(want).get_faces().size() / 3])
		for from: String in ["left", "right"]:
			g.clear_all()
			g.queue.clear()
			g.wave_i = g.waves.size()
			g.stage_t = 0.0   # the level's opening: a real one
			g.spawn_vert("gull", 0.0, 0, 1, from)
			var f: Game.Obj = g.foes[g.foes.size() - 1]
			check(f.kind == want and not f.hacked and g.civilian(f) and g.shy(f), "%s from the %s: a real %s" % [want, from, want])
			check(not f.ground, "%s: a simple flying craft, nothing on the ground" % want)
			check(not g.on_screen(f), "%s: comes in from off-screen" % want)
			f.hp = 1e6
			var hp0 := g.hp
			var x0 := f.pos.x
			var shown := 0.0
			var fired := false
			var t := 0.0
			while t < 14.0 and f in g.foes:
				for o in g.foes:
					o.hacked = false   # a lighthouse along the way stays a lighthouse: this watches the civilian
				g.inv = 0.0
				g.prel = Vector2(clampf(f.pos.x, -5.0, 5.0), f.pos.z - g.frame_z)
				g.step(DT)
				t += DT
				fired = fired or g.bullets.size() > 0
				if f in g.foes and g.on_screen(f):
					shown += DT
			var x1 := f.pos.x
			check(signf(x1 - x0) == -signf(x0) and absf(x1 - x0) > 4.0,
				"%s from the %s: heads across the screen (%.1f m to %.1f m)" % [want, from, x0, x1])
			check(shown > 3.0, "%s from the %s: a while on screen (%.1f s)" % [want, from, shown])
			check(not fired and g.hp == hp0, "%s from the %s: never fires, flying into it costs nothing" % [want, from])
		# downed: nothing scored, its getaway plays out and is gone
		g.clear_all()
		g.spawn_vert("gull", 0.0, 0, 1, "left")
		var f: Game.Obj = g.foes[g.foes.size() - 1]
		f.hacked = false
		for i in int(2.0 / DT):
			g.step(DT)
		g.run.score = 1000
		var kills: int = g.run.kills
		var drops := g.picks.size()
		var n := g.blasts.chutes.size()
		var at := f.pos
		g.kill(f)
		check(g.run.score == 1000 and g.run.kills == kills and g.picks.size() == drops, "%s: downing it scores nothing, isn't a kill, drops nothing" % want)
		check(g.blasts.chutes.size() == n + 1 and g.blasts.chutes[n].kind == want, "%s: someone gets away" % want)
		var c: Dictionary = g.blasts.chutes[n]
		var node: Node3D = c.node
		var far := 0.0
		for i in int(1.2 / DT):
			g.hp = 5
			g.inv = 1.0
			g.step(DT)
			far = maxf(far, Vector2(node.position.x - at.x, node.position.z - at.z).length())
		check(node.scale.x > 0.4 and far > 1.0, "%s: the getaway shows and moves off (%.1f m)" % [want, far])
		for i in int(float(c.life) / DT):
			g.hp = 5
			g.inv = 1.0
			g.step(DT)
		check(c not in g.blasts.chutes, "%s: then it's gone" % want)
		# hacked: a tell, then a minigun, then fire
		g.clear_all()
		g.spawn_vert("gull", 0.0, 0, 1, "left")
		f = g.foes[g.foes.size() - 1]
		f.hacked = true
		f.hp = 1e6
		var told := -1.0
		var first := -1.0
		var t := 0.0
		while t < 12.0 and f in g.foes and first < 0.0:
			g.hp = 5
			g.inv = 1.0
			var before := g.bullets.size()
			g.step(DT)
			t += DT
			if told < 0.0 and f.hold >= 0.0:
				told = t
			if g.bullets.size() > before:
				first = t
		check(told >= 0.0 and first - told >= Foes.HACK_TELL and f.node.has_node("minigun"),
			"%s: a hacked one gives itself away, unveils a minigun and fires (%.1f s after)" % [want, first - told])
		n = g.blasts.chutes.size()
		g.kill(f)
		check(g.blasts.chutes.size() == n, "%s: a hacked one's crew doesn't get away" % want)
	check(seen.size() == Campaign.WORLDS.size(), "every world its own civilian (%d)" % seen.size())
	g.queue_free()
	await process_frame


func extras() -> void:
	print("announced, shells burst, borers hide")
	var g := make_game()
	await process_frame
	g.s.open = 5
	g.launch(4)
	for i in int(4.0 / DT):
		g.hp = 5
		g.step(DT)
		if g.banner == "NEW FOE":
			break
	check(g.banner == "NEW FOE" and g.sub_banner == Foes.NAMES[Campaign.debut(4)], "the level's new kind is announced (%s)" % g.sub_banner)
	g.clear_all()
	var b := g.shell(Vector3(0, Rules.PY, g.frame_z - 8.0), Vector3(0, Rules.PY, g.frame_z - 2.0), 8.0, 7)
	var n := 0
	for i in int(2.0 / DT):
		g.hp = 5
		g.step(DT)
		if b.dead:
			n = g.bullets.size()
			break
	check(b.dead and n == 7, "a flak shell bursts into a ring of 7 (%d)" % n)
	g.clear_all()
	g.spawn_vert("borer", 0.0, 0, 1)
	var f: Game.Obj = g.foes[g.foes.size() - 1]
	var s := g.new_shot(g.seen(f.pos), Vector3.ZERO, 1.0)
	g.collide(DT)
	check(f.under and not s.dead and is_equal_approx(f.hp, f.max_hp * float(g.world.tough)), "a borer under the sand can't be hit")
	g.queue_free()
	await process_frame


## Every type of gun tower in every world: on its world's footing (a building in the city), its gun
## turning on top, firing, flashing when hit; the howitzer's shell is big.
func towers() -> void:
	print("gun towers, dressed for each world")
	var g := make_game()
	await process_frame
	g.s.open = Campaign.count() - 1
	var all := {}
	for w in Campaign.WORLDS.size():
		var lv := w * Campaign.PER_WORLD
		for t: String in Towers.BY_WORLD[w]:
			all[t] = true
		check(Towers.BY_WORLD[w].size() >= mini(2 + w, 4), "%s fields %d types of tower" % [Campaign.WORLDS[w].name, Towers.BY_WORLD[w].size()])
		var seen_types := {}
		for k in range(lv, lv + Campaign.PER_WORLD):
			for wave: Dictionary in Campaign.waves(k):
				if Towers.is_tower(wave.kind):
					seen_types[wave.kind] = true
		check(seen_types.size() >= 2, "%s's levels bring %d types of tower" % [Campaign.WORLDS[w].name, seen_types.size()])
		for t: String in Towers.TYPES:
			g.launch(lv)
			g.step(DT)
			g.clear_all()
			g.queue.clear()
			g.wave_i = g.waves.size()
			g.spawn_vert(t, 1.0, 0, 1)
			var f: Game.Obj = g.foes[g.foes.size() - 1]
			var theme: String = Campaign.WORLDS[w].theme
			var gy := g.ground_y(f.pos.x, f.pos.z)
			check(f.ground and f.node.mesh == Towers.base(theme) and f.node.has_node("top") and is_equal_approx(f.pos.y, gy + Towers.height(theme)),
				"%s: a %s on its world's footing, its gun %.1f m up" % [theme, t, Towers.height(theme)])
			check(Towers.pole(theme) >= 0.8, "%s: the %s's gun stands on a pole, so it reads as a tower, not a flyer" % [theme, t])
			f.hp = 1e6
			var fired := 0
			var big := false
			for i in int(9.0 / DT):
				var nb := g.bullets.size()
				g.hp = 5
				g.step(DT)
				fired += maxi(0, g.bullets.size() - nb)
				for b in g.bullets:
					big = big or b.size > 1.5
				if fired > 0 and (t != "howitzer" or big):
					break
			check(fired > 0, "%s: the %s fires" % [theme, t])
			if t == "howitzer":
				check(big, "%s: the howitzer's shell is big" % theme)
			f.hit = -1.0
			g.damage(f, 0.5)
			g.update_objs(0.0)
			var top := f.node.get_node("top") as MeshInstance3D
			check(f.node.material_overlay != null and top.material_overlay != null, "%s: the %s flashes, gun and all" % [theme, t])
	check(all.size() == Towers.TYPES.size(), "every type of tower is fielded somewhere")
	# down every level's course, a tower's whole footing stands on level ground, never over a rim
	for lv in Campaign.count():
		g.launch(lv)
		g.step(DT)
		g.clear_all()
		var bad := 0
		var dry_ok := 0
		var n := 0
		for z in range(0, 1500, 23):
			for x in [-4.0, 0.0, 4.0]:
				var at := Foes.dry_x(g, x, -float(z), null, Towers.FOOT_R)
				n += 1
				if not Foes.footed(g, at.x, at.y, Towers.FOOT_R, false, false):
					bad += 1
				if Foes.dry(g, at.x, at.y):
					dry_ok += 1
		check(bad <= n / 100, "level %d: towers stand level, not over a rim (%d of %d spots)" % [lv + 1, n - bad, n])
		check(dry_ok >= n * 0.8, "level %d: towers mostly stand out of the water (where the sea or a river fills the width they stand in it, level, like a pier) (%d of %d spots)" % [lv + 1, dry_ok, n])
	check(Towers.height("city") + 1.6 < Rules.PY, "a tower on a building stays under the flight altitude")
	g.queue_free()
	await process_frame


func _initialize() -> void:
	print("Vantage foes test")
	roster()
	await towers()
	await each_kind()
	await holds()
	await formations()
	await hacked()
	await worlds()
	await extras()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails else 0)
