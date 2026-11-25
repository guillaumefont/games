extends SceneTree
## Screenshots of the real game for PRs (needs a display):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/shots.gd -- /tmp/shots

var out := "/tmp/shots"
var g: Game


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _mouse(pos: Vector2, pressed: bool, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://shots_save.json"
	if FileAccess.file_exists(tmp):
		DirAccess.remove_absolute(tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.rng.seed = 7
	root.add_child(g)
	await frames(30)
	g.P.h = 2.6
	g.throttle = 0.8
	await frames(90)
	await shot("1-sea")
	# a fight: an enemy off our quarter
	var e: Game.Boat = g.enemies[0]
	var pp := g.P.pos()
	g.P.node.position = Vector3(60, 0, 60)
	g.camera.position = g.P.node.position + g.cam_off
	e.node.position = Vector3(72, 0, 66)
	e.h = 2.0
	e.st = e.st.duplicate()
	e.st.grapple = 0.0   # no boarding of its own before the boarding shots
	g.start_combat(e, "pending")
	await frames(40)
	await shot("2-attack")
	g.on_fight()
	await frames(150)
	await shot("3-fight")
	# aiming: the green stick held toward the enemy
	var ac := g.hud.aim_center()
	_mouse(ac, true)
	for i in 20:
		var d := e.xz() - g.P.xz()
		_mouse(ac + d.normalized() * Hud.AIM_R * clampf(0.2 + 0.8 * (d.length() - 6) / 18.0, 0.3, 1.0), true, true)
		await process_frame
	await shot("3-aim")
	# the red line meets the nearest island
	var near: Dictionary = g.isles[1]
	for isl in g.isles:
		if Vector2(isl.x, isl.z).distance_to(g.P.xz()) < Vector2(near.x, near.z).distance_to(g.P.xz()):
			near = isl
	for i in 10:
		var di := Vector2(near.x, near.z) - g.P.xz()
		_mouse(ac + di.normalized() * Hud.AIM_R, true, true)
		await process_frame
	await shot("3-aim-ile")
	_mouse(ac, false)
	# the purple grapple line, then a boarding
	var hc := g.hud.hook_center()
	e.node.position = g.P.node.position + Vector3(10, 0, -4)
	e.offline = true
	e.rl = {"bab": 99.0, "tri": 99.0, "av": 99.0, "ar": 99.0}   # no smoke over the line
	await frames(60)
	_mouse(hc, true)
	for i in 12:
		var d2 := e.xz() - g.P.xz()
		_mouse(hc + d2.normalized() * Hud.AIM_R, true, true)
		await process_frame
	await shot("3-grappin")
	_mouse(hc, false)
	g.hud.cancel_sticks()
	g.start_boarding(e, true)
	await frames(90)
	await shot("3-abordage")
	g.combat.board.theirs = []
	for m in e.fighters:
		m.hp = 0
	await frames(5)
	await shot("3-prise")
	g.hud.hide_prompt()
	g.end_combat()
	g.P.node.position = Rules.DOCK
	g.camera.position = g.P.node.position + g.cam_off
	g.s.coins = 6200
	g.open_port()
	await frames(10)
	await shot("4-port-coffre")
	g.hud._tab = "bateau"
	g.hud.refresh_port()
	await frames(30)
	await shot("5-port-chantier")
	g.hud._pv_idx = 2
	g.hud.refresh_port()
	await frames(30)
	await shot("6-port-fregate")
	g.hud._tab = "equipage"
	g.hud.refresh_port()
	await frames(5)
	await shot("7-port-equipage")
	g.hud._tab = "base"
	g.hud.refresh_port()
	await frames(5)
	await shot("8-port-fort")
	quit()
