extends SceneTree
## Plays Drift with the test bot on many seeds and prints how long it takes to reach each block of
## Sim.LAP_MOONS moons, to tune the fast-lap pars (Sim.lap_par).
## Run: godot --headless --path perigee --script tools/drift_pace.gd

func _initialize() -> void:
	var Bot = preload("res://tests/sim_test.gd").Bot
	var laps := {} # lap index -> Array of times
	for seed in 60:
		for deep in [false, true]:
			var s := Sim.new(seed, 400, 700)
			s.press()
			s.release()
			var bot = Bot.new()
			bot.deep = deep
			var lap_start := 0.0
			var lap := 0
			for i in 120 * 600:
				var act: String = bot.decide(s)
				match act:
					"press":
						s.press()
					"release":
						s.release()
					"tap":
						s.press()
						s.release()
				s.step()
				if s.state != "play":
					break
				while s.hops >= (lap + 1) * 10:
					if not laps.has(lap):
						laps[lap] = []
					laps[lap].append(s.run_t - lap_start)
					lap_start = s.run_t
					lap += 1
	for lap in laps:
		var a: Array = laps[lap]
		a.sort()
		print("lap %d (moons %d-%d): n=%d min %.1f p25 %.1f median %.1f p75 %.1f" % [lap, lap * 10 + 1, lap * 10 + 10,
			a.size(), a[0], a[a.size() / 4], a[a.size() / 2], a[a.size() * 3 / 4]])
	quit(0)
