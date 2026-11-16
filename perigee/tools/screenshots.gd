extends SceneTree
## Screenshots of the real game for reviews: start card, first hop with guide dots, a catch,
## late game (moon 30+), game over, the lab's twin, retro and pulsar moons, and Voyage (sector list,
## a sector, the clear card). Needs a display:
##   xvfb-run -a godot --path perigee --rendering-method gl_compatibility --resolution 824x1720 \
##     --script tools/screenshots.gd -- /tmp/perigee-shots

var main: Node2D
var out := "/tmp/perigee-shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://screenshots_save.json"
	root.add_child(main)
	main.set_process(false)
	await process_frame
	main.sim.new_run(4)
	main.sim.state = "start"
	main.hud.show_start(true)
	await run(1.0)
	await shot("1-start")
	main.on_press()
	main.on_release()
	await run(0.9)
	await shot("2-first-hop-guide")
	# fling at the next moon and hold through its ring
	await aim_and_fling()
	await run_until(func() -> bool: return _in_perigee_ring(), 3.0)
	main.on_press()
	await run(0.3)
	await shot("3-caught")
	# skip ahead: a fresh run played by the test bot until moon 30
	main.on_release()
	main.sim.new_run(5)
	var bot := preload("res://tests/sim_test.gd").Bot.new()
	for i in 120 * 200:
		var act: String = bot.decide(main.sim)
		match act:
			"press":
				main.on_press()
			"release":
				main.on_release()
			"tap":
				main.on_press()
				main.on_release()
		main.advance(Sim.DT)
		if main.sim.hops >= 30 and main.sim.player.planet == null and _in_ring():
			break
	await run(0.0)
	await shot("4-late-game")
	main.on_release()
	main.sim.die("Drifted off into the dark")
	await run(1.0)
	await shot("5-game-over")
	# the lab: one shot per new kind of moon, a moment into a run
	for kind in ["twin", "retro", "pulsar"]:
		main.start_mode(kind)
		await run(1.2)
		await shot("6-lab-" + kind)
	# Voyage: the sector list, a sector in play, the clear card
	main.save.data.voyage = {"1-1": {"stars": 3}, "1-2": {"stars": 2}, "1-3": {"stars": 1}}
	main.open_voyage()
	await run(0.3)
	await shot("7-voyage-map")
	main.start_sector("1-4")
	var vbot := preload("res://tests/sim_test.gd").Bot.new()
	vbot.deep = true
	for i in 120 * 60:
		match vbot.decide(main.sim):
			"press":
				main.on_press()
			"release":
				main.on_release()
			"tap":
				main.on_press()
				main.on_release()
		main.advance(Sim.DT)
		if main.sim.hops >= 9 and main.sim.player.planet == null:
			break
	await run(0.0)
	await shot("8-voyage-sector")
	for i in 120 * 30:
		match vbot.decide(main.sim):
			"press":
				main.on_press()
			"release":
				main.on_release()
			"tap":
				main.on_press()
				main.on_release()
		main.advance(Sim.DT)
		if main.sim.state != "play":
			break
	await run(1.0)
	await shot("9-voyage-clear")
	quit(0)


func _in_perigee_ring() -> bool:
	var p: Sim.Player = main.sim.player
	if p.planet != null:
		return false
	for q in main.sim.planets:
		if not q.visited and Vector2(q.x - p.x, q.y - p.y).length() < q.perigee_radius():
			return true
	return false


func _in_ring() -> bool:
	var p: Sim.Player = main.sim.player
	if p.planet != null:
		return false
	for q in main.sim.planets:
		if not q.visited and Vector2(q.x - p.x, q.y - p.y).length() < q.ring:
			return true
	return false


func aim_and_fling() -> void:
	var s: Sim = main.sim
	for i in 2000:
		var target: Sim.Planet = s.planets[s.hops + 1] if s.hops + 1 < s.planets.size() else null
		if target != null:
			var v := s.orbit_velocity()
			if absf(v.angle_to(Vector2(target.x - s.player.x, target.y - s.player.y))) < 0.06:
				break
		main.advance(Sim.DT)
	main.on_press()
	main.on_release()


func run(seconds: float) -> void:
	var n := int(seconds / Sim.DT)
	for i in n:
		main.advance(Sim.DT)
	main.advance(0.0)
	await process_frame
	await process_frame


func run_until(cond: Callable, max_s: float) -> void:
	for i in int(max_s / Sim.DT):
		if cond.call():
			break
		main.advance(Sim.DT)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name)
