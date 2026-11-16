extends SceneTree
## Plays every Voyage sector with the test bot (no leaps, shallow and deep catches) and prints its
## clear time and a suggested par: the faster bot time plus 35%, rounded up to a whole second. The
## bot fires the moment it lines up, so a person needs some margin; leaps beat par more easily.
## Run: godot --headless --path perigee --script tools/par_times.gd

func _initialize() -> void:
	var Bot = preload("res://tests/sim_test.gd").Bot
	for sec in Voyage.all_sectors():
		var times: Array[String] = []
		var best := INF
		for deep in [false, true]:
			var s := Sim.new(sec.seed, 400, 700)
			s.recipe = Voyage.recipe(sec)
			s.new_run(sec.seed)
			var bot = Bot.new()
			bot.deep = deep
			for i in 120 * 120:
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
			times.append("%s %s %.1f s (moon %d)" % ["deep" if deep else "shallow", s.state, s.run_t, s.hops])
			if s.state == "clear":
				best = minf(best, s.run_t)
		print("%s: %s -> par %s (now %.0f)" % [sec.id, ", ".join(times), str(ceilf(best * 1.35)) if best < INF else "?", sec.par])
	quit(0)
