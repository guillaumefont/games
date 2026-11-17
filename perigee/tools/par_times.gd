extends SceneTree
## Plays every Voyage sector with the test bot (no leaps, shallow and deep catches) and prints its
## clear time and a suggested par: the faster bot time plus 35%, rounded up to a whole second. The
## bot fires the moment it lines up, so a person needs some margin; leaps beat par more easily.
## Also suggests the sector's points medals (Medals): 40%, 75% and 110% of the bot's all-perigee
## score, rounded to 5, so gold takes leaps or a longer combo than the bot's.
## Run: godot --headless --path perigee --script tools/par_times.gd

func _initialize() -> void:
	var Bot = preload("res://tests/sim_test.gd").Bot
	for sec in Voyage.all_sectors():
		var times: Array[String] = []
		var best := INF
		var deep_score := 0
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
			times.append("%s %s %.1f s (moon %d) score %d" % ["deep" if deep else "shallow", s.state, s.run_t, s.hops, s.score])
			if s.state == "clear":
				best = minf(best, s.run_t)
				if deep:
					deep_score = s.score
		var pts: Array[int] = []
		for f in [0.4, 0.75, 1.1]:
			pts.append(int(roundf(deep_score * f / 5.0)) * 5)
		print("%s: %s -> par %s (now %.0f), points %s (now %s)" % [sec.id, ", ".join(times),
			str(ceilf(best * 1.35)) if best < INF else "?", sec.par, pts, sec.get("points", [])])
	quit(0)
