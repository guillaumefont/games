extends SceneTree
## Headless tests of the game rules (scripts/sim.gd): a bot plays, the same seed and inputs
## replay to the same run, the difficulty keeps ramping past moon 12, and the hop keeps its
## momentum through capture and launch.
## Run: godot --headless --path perigee --script tests/sim_test.gd
## Last line on success: SIM TEST DONE

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


## A simple player: lets go right after a capture, flings when the ship heads at the nearest
## unvisited moon, and holds only while inside an unvisited moon's ring.
## Returns "press", "release", "tap" or "" for this step.
class Bot:
	var deep := false ## wait for the perigee ring before holding
	var down := false
	var orbit_steps := 0

	func decide(s: Sim) -> String:
		var p := s.player
		if s.state != "play":
			return ""
		if p.planet != null:
			if down:
				down = false
				orbit_steps = 0
				return "release"
			orbit_steps += 1
			var best: Sim.Planet = null
			var bd := INF
			for q in s.planets:
				if q.visited:
					continue
				var d := Vector2(q.x - p.planet.x, q.y - p.planet.y).length()
				if d < bd:
					bd = d
					best = q
			if best != null and orbit_steps > 30:
				var v := s.orbit_velocity()
				var to := Vector2(best.x - p.x, best.y - p.y)
				if absf(v.angle_to(to)) < 0.06:
					return "tap"
			return ""
		var in_ring := false
		for q in s.planets:
			# a pulsar's ring only catches while lit, so the bot waits for it
			if not q.visited and q.lit(s.t) and Vector2(q.x - p.x, q.y - p.y).length() < (q.perigee_radius() if deep else q.ring):
				in_ring = true
		if in_ring and not down:
			down = true
			return "press"
		if not in_ring and down:
			down = false
			return "release"
		return ""


static func apply(s: Sim, action: String) -> void:
	match action:
		"press":
			s.press()
		"release":
			s.release()
		"tap":
			s.press()
			s.release()


## Plays seed `seed_in` with the bot for at most `max_steps`; returns [sim, inputs].
func bot_run(seed_in: int, max_steps: int, deep := false) -> Array:
	var s := Sim.new(seed_in, 400, 700)
	s.press()
	s.release() # the start tap
	var bot := Bot.new()
	bot.deep = deep
	var inputs: Array = []
	for i in max_steps:
		var act := bot.decide(s)
		if act != "":
			inputs.append([s.steps, act])
			apply(s, act)
		s.step()
		if s.state == "over":
			break
	return [s, inputs]


## Puts the ship in flight `dist` below moon `pl`, heading up at it, passing `miss` to its side.
## The moon just before it is treated as the one just left.
static func fly_at(s: Sim, pl: Sim.Planet, dist: float, miss: float) -> void:
	var p := s.player
	p.planet = null
	p.last = null
	for q in s.planets:
		if q.k == pl.k - 1:
			p.last = q
	p.fly_t = 0.0
	s.flight_id += 1
	p.x = pl.x + miss
	p.y = pl.y + dist
	p.vx = 0.0
	p.vy = -pl.speed
	p.speed = pl.speed
	s.cam_y = pl.y
	s.cam_x = 0.0


## Steps until `pl` catches the ship (pressing once the ship is `press_at` from its centre),
## the run ends, or 3 s pass. Returns the capture event, or {}.
static func catch(s: Sim, pl: Sim.Planet, press_at: float) -> Dictionary:
	for i in 360:
		var d := Vector2(s.player.x - pl.x, s.player.y - pl.y).length()
		if not s.holding and d < press_at:
			s.press()
		s.step()
		for e in s.events:
			if e.type == "capture":
				s.events.clear()
				s.release()
				return e
		s.events.clear()
		if s.state != "play":
			break
	return {}


func _initialize() -> void:
	print("Perigee sim test")

	# --- difficulty curve: same numbers as the prototype ---
	var c0 := Sim.curve(0)
	var c50 := Sim.curve(50)
	check(is_equal_approx(c0.ring, 104.0) and is_equal_approx(c0.gap, 160.0) and is_equal_approx(c0.speed, 185.0),
		"curve starts at ring 104, gap 160, speed 185")
	check(is_equal_approx(c50.ring, 66.0) and is_equal_approx(c50.gap, 265.0) and is_equal_approx(c50.speed, 255.0),
		"curve reaches ring 66, gap 265, speed 255 at moon 50")
	check(is_equal_approx(Sim.assist(0), 1.0) and is_equal_approx(Sim.assist(22), 0.3), "assist fades from 1.0 to 0.3 by moon 22")

	# --- the ramp bug: moon numbers must keep counting even though far moons are culled ---
	var s := Sim.new(7, 400, 700)
	s.press()
	s.release()
	s.player.planet = null # let the culling take every moon behind us
	var seen: Array[int] = []
	var moving := 0
	var last_ring := 0.0
	for i in 400:
		# carry the camera up the column of moons, like a long run would
		s.cam_y -= 120.0
		s.ensure_planets()
		for pl in s.planets:
			if pl.k not in seen:
				seen.append(pl.k)
				if pl.amp > 0.0:
					moving += 1
				if pl.k == 60:
					last_ring = pl.ring
		if seen.size() > 80:
			break
	var consecutive := true
	for i in seen.size():
		if seen[i] != i:
			consecutive = false
	check(s.planets.size() < 20, "far moons are culled (%d live)" % s.planets.size())
	check(seen.size() > 80 and consecutive, "moon numbers run 0..%d without repeating" % (seen.size() - 1))
	check(is_equal_approx(last_ring, 66.0), "moon 60 has the hardest ring (%.1f)" % last_ring)
	check(moving > 20, "moons drift side to side after moon 12 (%d of them)" % moving)

	# --- a bot can play ---
	var best_hops := 0
	var best_seed := 0
	for seed_in in [1, 2, 3, 4, 5]:
		var r := bot_run(seed_in, 120 * 120)
		var bs: Sim = r[0]
		print("    seed %d: %d moons, score %d, %s after %.1f s%s" % [seed_in, bs.hops, bs.score, bs.state, bs.t,
			(" (" + bs.death_why + ")") if bs.state == "over" else ""])
		if bs.hops > best_hops:
			best_hops = bs.hops
			best_seed = seed_in
	check(best_hops >= 10, "the bot hops at least 10 moons on one of five seeds (best %d)" % best_hops)

	var deep_r := bot_run(best_seed, 120 * 60, true)
	var ds: Sim = deep_r[0]
	print("    deep bot, seed %d: %d moons, score %d, %d perigees, best combo %d" % [best_seed, ds.hops, ds.score, ds.perigees, ds.best_combo])
	check(ds.perigees >= 10 and ds.perigees * 2 >= ds.hops and ds.score > ds.hops * 2,
		"a bot that waits for the perigee ring scores mostly perigees and far more points")

	# --- replay: same seed + same inputs = same run ---
	var rec := bot_run(best_seed, 120 * 60)
	var a: Sim = rec[0]
	var inputs: Array = rec[1]
	var b := Sim.new(best_seed, 400, 700)
	b.press()
	b.release()
	var idx := 0
	while b.steps < a.steps:
		while idx < inputs.size() and inputs[idx][0] == b.steps:
			apply(b, inputs[idx][1])
			idx += 1
		b.step()
	check(a.fingerprint() == b.fingerprint(), "replaying %d inputs gives the same run (%s)" % [inputs.size(), b.fingerprint()])
	var other := Sim.new(best_seed + 1, 400, 700)
	check(other.planets[1].ox != a.planets[0].ox or other.sparks[0].x != b.sparks[0].x, "another seed gives another layout")
	var same := Sim.new(best_seed, 400, 700)
	var same2 := Sim.new(best_seed, 400, 700)
	check(same.planets[2].ox == same2.planets[2].ox and same.planets[2].pr == same2.planets[2].pr, "the same seed gives the same layout")

	# --- momentum: capture keeps the incoming speed, launch leaves along the orbit ---
	var m := Sim.new(3, 400, 700)
	m.press()
	m.release()
	for i in 60:
		m.step()
	var v_orbit := m.orbit_velocity()
	m.press()
	m.release()
	check(m.player.planet == null, "a tap flings off the moon")
	var v_fly := Vector2(m.player.vx, m.player.vy)
	check(absf(v_orbit.angle_to(v_fly)) < 0.001, "the fling leaves along the orbit, no kink")
	check(is_equal_approx(v_fly.length(), m.player.speed), "the fling keeps the moon's orbit speed")
	var pl1 := m.planets[1]
	# aim straight at moon 1 and catch it
	var to := Vector2(pl1.x - m.player.x, pl1.y - m.player.y).normalized() * m.player.speed
	m.player.vx = to.x
	m.player.vy = to.y
	m.press()
	var caught := false
	for i in 400:
		m.step()
		if m.player.planet == pl1:
			caught = true
			break
	check(caught and m.hops == 1 and m.score == 1, "holding through a ring catches the moon and scores 1")
	check(caught and m.player.vr < 0.0, "the orbit starts from the incoming radial speed (spiral in, %.0f)" % m.player.vr)
	m.release()
	check(m.player.planet == pl1, "a release right after a capture does not fling")

	# --- scoring: perigee combo, leaps, grazes, sparks ---
	var sc := Sim.new(21, 400, 700)
	sc.press()
	sc.release()
	var m1 := sc.planets[1]
	var ev := {}
	fly_at(sc, m1, m1.ring + 40.0, 0.0)
	ev = catch(sc, m1, m1.perigee_radius() - 2.0)
	check(ev.get("perigee", false) and ev.points == 2 and sc.score == 2 and sc.combo == 1,
		"a catch inside the perigee ring is a perigee: 2 points, combo 1 (%s)" % [ev])
	var m2 := sc.planets[2]
	sc.combo = 4
	sc._set_mult()
	fly_at(sc, m2, m2.ring + 40.0, 0.0)
	ev = catch(sc, m2, m2.perigee_radius() - 2.0)
	check(ev.get("perigee", false) and ev.points == 6 and sc.mult == 3, "combo 5 multiplies a perigee by 3 (%d points)" % ev.get("points", 0))
	var m3 := sc.planets[3]
	fly_at(sc, m3, m3.ring + 40.0, 0.0)
	ev = catch(sc, m3, m3.ring - 2.0) # held just inside the edge of the ring
	check(not ev.get("perigee", true) and ev.get("points", 0) == 1 and sc.combo == 0 and sc.mult == 1, "a shallow catch scores 1 and resets the combo (%s)" % [ev])
	check(sc.perigees == 2 and sc.best_combo == 5, "perigees and best combo are counted")

	var lp := Sim.new(22, 400, 700)
	lp.press()
	lp.release()
	var target := lp.planets[2]
	fly_at(lp, target, target.ring + 40.0, 0.0)
	ev = catch(lp, target, target.perigee_radius() - 2.0)
	check(ev.get("skipped", 0) == 1 and lp.hops == 2 and lp.planets[1].skipped and lp.planets[1].visited,
		"catching moon 2 straight from moon 0 is a leap: moon 1 counts as passed")
	check(ev.get("leap_points", 0) == 6 and lp.score == 8 and lp.leaps == 1 and lp.combo == 2,
		"a 1-moon leap scores 3 times the multiplier and adds a combo step (score %d)" % lp.score)
	var far := lp.planets[5]
	fly_at(lp, far, far.ring + 40.0, 0.0)
	ev = catch(lp, far, far.perigee_radius() - 2.0)
	check(ev.get("skipped", 0) == 2 and ev.get("leap_points", 0) == 9 * ev.mult, "a 2-moon leap scores 9 times the multiplier")
	check(Sim.LEAP_POINTS[3] == 18, "a 3-moon leap scores 18 times the multiplier")

	var gz := Sim.new(23, 400, 700)
	gz.press()
	gz.release()
	var gm := gz.planets[1]
	fly_at(gz, gm, gm.ring + 40.0, gm.pr + 9.0)
	var grazed_at := -1
	for i in 120:
		gz.step()
		if gz.grazes > 0 and grazed_at < 0:
			grazed_at = i
	check(gz.grazes == 1 and gz.score == 1, "skimming a moon without holding is one graze, +1 (%d grazes)" % gz.grazes)

	var sp := Sim.new(24, 400, 700)
	sp.press()
	sp.release()
	var spark := sp.sparks[0]
	sp.player.planet = null
	sp.player.x = spark.x
	sp.player.y = spark.y + 30.0
	sp.player.vx = 0.0
	sp.player.vy = -sp.player.speed
	sp.cam_y = spark.y
	sp.combo = 1
	sp._set_mult()
	for i in 30:
		sp.step()
	check(spark.got and sp.combo == 2 and sp.score == 2, "a spark raises the combo and scores the multiplier (score %d)" % sp.score)

	# --- new kinds of moon (the lab) ---
	var plain := Sim.new(31, 400, 700)
	var plain_kinds := {}
	for pl in plain.planets:
		plain_kinds[pl.kind] = true
	check(plain_kinds.keys() == ["moon"], "the endless mode has plain moons only")
	var with_recipe := Sim.new(31, 400, 700)
	with_recipe.recipe = {"mix": {"twin": 1.0}}
	with_recipe.new_run(31)
	var tw: Sim.Planet = with_recipe.planets[1]
	check(tw.kind == "twin" and tw.partner != null and tw.partner.partner == tw and with_recipe.planets[2] == tw.partner,
		"a twin comes as a linked pair")
	var gap := Vector2(tw.ox - tw.partner.ox, tw.y - tw.partner.y).length()
	check(gap < tw.ring + tw.partner.ring and gap > tw.pr + tw.partner.pr + 20.0, "the twins' rings overlap in a figure eight (%.0f apart)" % gap)
	check(absf(tw.ox) <= 135.0 and absf(tw.partner.ox) <= 135.0, "both twins stay on screen")
	fly_at(with_recipe, tw.partner, tw.partner.ring + 40.0, 0.0)
	with_recipe.player.last = with_recipe.planets[0]
	ev = catch(with_recipe, tw.partner, tw.partner.perigee_radius() - 2.0)
	check(not ev.is_empty() and tw.visited and tw.partner.visited and with_recipe.hops == 1, "catching either twin counts the pair once")
	var t3: Sim.Planet = with_recipe.planets[3]
	check(t3.k == 2 and t3.kind == "twin", "the next pair is moon 2 (pairs share a number, so leaps still count moons)")

	var rt := Sim.new(32, 400, 700)
	rt.recipe = {"mix": {"retro": 1.0}}
	rt.new_run(32)
	var rm: Sim.Planet = rt.planets[1]
	check(rm.kind == "retro", "the retro lab makes retrograde moons")
	fly_at(rt, rm, rm.ring + 40.0, 30.0)
	rt.player.last = rt.planets[0]
	ev = catch(rt, rm, rm.ring - 2.0)
	var arrive_dir := rt.player.dir
	check(not ev.is_empty() and rt.player.vt < 0.0, "a retrograde capture keeps moving the way we came at first")
	var ang0 := rt.player.ang
	for i in 120 * 2:
		rt.step()
	var turn := (rt.player.ang - ang0) * arrive_dir
	check(rt.player.vt > rt.player.speed * 0.9,
		"then it eases into the reversed orbit (speed %.0f)" % rt.player.vt)
	var plain_dir := Sim.new(32, 400, 700)
	var pm := plain_dir.planets[1]
	plain_dir.press()
	plain_dir.release()
	fly_at(plain_dir, pm, pm.ring + 40.0, 30.0)
	plain_dir.player.last = plain_dir.planets[0]
	catch(plain_dir, pm, pm.ring - 2.0)
	check(plain_dir.player.dir == -arrive_dir, "it orbits the other way from a plain moon caught on the same line")

	var ps := Sim.new(33, 400, 700)
	ps.recipe = {"mix": {"pulsar": 1.0}}
	ps.new_run(33)
	var pu: Sim.Planet = ps.planets[1]
	check(pu.kind == "pulsar", "the pulsar lab makes pulsars")
	# wait for the ring to go dark, then fly through holding: no catch
	var guard := 0
	while (pu.lit(ps.t) or pu.lit(ps.t + 0.3)) and guard < 400:
		ps.step()
		guard += 1
	fly_at(ps, pu, pu.ring + 12.0, pu.pr + 18.0)
	ps.player.last = ps.planets[0]
	ps.press()
	var caught_dark := false
	for i in 30:
		ps.step()
		if ps.player.planet == pu:
			caught_dark = true
	check(not caught_dark and ps.state == "play", "a dark pulsar ring does not catch (%s)" % ps.state)
	# park the ship back on moon 0 while the ring lights up again
	ps.player.planet = ps.planets[0]
	var lit_wait := 0
	while not pu.lit(ps.t) and lit_wait < 400:
		ps.step()
		lit_wait += 1
	fly_at(ps, pu, 20.0, pu.pr + 18.0) # already inside the ring
	ps.player.last = ps.planets[0]
	ps.holding = true
	ps.step()
	check(ps.player.planet == pu, "a lit pulsar ring catches (%s, lit %s)" % [ps.state, pu.lit(ps.t)])

	# --- losing and restarting ---
	var d := Sim.new(9, 400, 700)
	d.press()
	d.release()
	for i in 30:
		d.step()
	d.press()
	d.release() # fling into the dark
	for i in 120 * 6:
		d.step()
		if d.state == "over":
			break
	check(d.state == "over", "flying off ends the run (%s)" % d.death_why)
	d.press()
	check(d.state == "over", "a tap right after dying does not restart")
	for i in 60:
		d.step()
	d.press()
	check(d.state == "play" and d.score == 0 and d.seed_value == d.next_seed - 1, "a tap after the lock restarts from zero with the next seed")
	d.release()
	check(d.player.planet != null, "the restart tap does not fling")

	if fails:
		print("%d check(s) failed" % fails)
		quit(1)
	else:
		print("SIM TEST DONE")
		quit(0)
