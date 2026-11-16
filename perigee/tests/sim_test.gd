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
			if not q.visited and Vector2(q.x - p.x, q.y - p.y).length() < q.ring:
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
func bot_run(seed_in: int, max_steps: int) -> Array:
	var s := Sim.new(seed_in, 400, 700)
	s.press()
	s.release() # the start tap
	var bot := Bot.new()
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
