extends SceneTree
## Screenshots of the six worlds for reviews: the stage map on two worlds, a busy stretch of
## each world with its own flyers and colours, a fortress, a mid-boss and the world bosses.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/worlds_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://wshots"


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func play(n: int, weave := 0.6) -> void:
	for i in n:
		vg.inp = {hold = true, fire = true, dx = sin(i * 0.05) * weave, dy = 0.0, ult = false, pause = false}
		if not vg.P.is_empty():
			vg.P.inv = 2 if vg.P.inv <= 2 else vg.P.inv
			vg.P.hull = 3
		vg.update()
		await process_frame


func jump(d: float) -> void:
	vg.G.scroll = d
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + 100:
		vg.G.si += 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 20:
		await process_frame
	await snap("w_map_1")
	vg.hud.select_world(3)
	await process_frame
	await snap("w_map_4")
	for w in 6:
		var i: int = w * 8 + 5
		vg.start_stage(i, "lance" if w % 2 == 0 else "warden")
		await play(60)
		var st: Dictionary = VStage.STAGES[i]
		jump(st.fort[1] + 160.0)
		await play(330)
		await snap("w%d_open" % (w + 1))
	# fortresses: full walls, wall guns, shutters, and the outpost on the ground round them
	for i in [5, 20, 38]:
		vg.start_stage(i, "warden" if i == 20 else "lance")
		await play(60)
		jump(VStage.STAGES[i].fort[0] - 60.0)
		await play(240)
		await snap("fort_%d" % (i + 1))
	vg.start_stage(9, "lance")
	await play(60)
	jump(VStage.STAGES[9].length - 160.0)
	await play(420)
	await snap("w2_midboss")
	# the world bosses
	for w in range(1, 6):
		var i: int = w * 8 + 7
		vg.start_stage(i, "lance" if w % 2 else "warden")
		await play(60)
		jump(VStage.STAGES[i].length - 160.0)
		await play(560, 0.9)
		await snap("w%d_boss" % (w + 1))
	quit()
