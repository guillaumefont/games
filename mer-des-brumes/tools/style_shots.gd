extends SceneTree
## Close-up screenshots of the ships, their crews and every style (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/style_shots.gd -- /tmp/shots

var out := "/tmp/shots"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func frames(n: int) -> void:
	for i in n:
		await process_frame


## Brings the game's camera close to the player's ship (it follows at `cam_off`).
func close_up(off: Vector3, n: int) -> void:
	g.cam_off = off
	for i in n:
		g.camera.position = g.P.pos() * Vector3(1, 0, 1) + off
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://style_shots_save.json"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.rng.seed = 7
	root.add_child(g)
	await frames(10)
	g.hud.visible = false
	g.gulls.visible = false   # they fly low enough to block a close camera
	for e in g.enemies:
		e.node.position = Vector3(400, 0, 400)
	g.s.crew = {"sabre": 3, "pistolet": 2, "fusil": 2, "grenade": 2}
	g.s.hook = true
	g.s.ship = "fregate"
	g.s.up.voiles = 3
	g.P.node.position = Vector3(40, 0, 80)
	g.P.h = 0.6
	g.throttle = 0.5
	for sk in Rules.SKINS:
		g.s.skin = sk.k
		g.rebuild_player()
		await close_up(Vector3(14, 12.5, -13).rotated(Vector3.UP, g.P.h), 50)
		await shot("style-" + sk.k)
	# the chaloupe of a new game, with one sail
	g.s.skin = "classique"
	g.s.ship = "chaloupe"
	g.s.up.voiles = 0
	g.s.crew = {"sabre": 2, "pistolet": 1, "fusil": 1, "grenade": 1}
	g.rebuild_player()
	await close_up(Vector3(9.5, 8.5, -8.5).rotated(Vector3.UP, g.P.h), 50)
	await shot("chaloupe-depart")
	# a boarding seen up close
	g.s.ship = "sloop"
	g.s.up.voiles = 2
	g.s.crew = {"sabre": 3, "pistolet": 1, "fusil": 1, "grenade": 1}
	g.rebuild_player()
	var e: Game.Boat = g.enemies[0]
	e.node.position = g.P.pos() + Vector3(8, 0, 0)
	e.offline = true
	e.fighters = Rules.fighters({"sabre": 3, "fusil": 2}, 1)
	g.start_combat(e, "fight")
	g.start_boarding(e, true)
	await frames(60)
	for m in e.fighters.slice(0, 2):
		m.hp = 0
	await close_up(Vector3(-4, 19, -13), 40)
	await shot("abordage-pres")
	quit()
