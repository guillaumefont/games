extends SceneTree
## Screenshots of fortress walls and the outpost round them, for reviews of the fortress look.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/fort_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://fshots"


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func play(n: int, weave := 0.6) -> void:
	for i in n:
		vg.inp = {hold = true, fire = false, dx = sin(i * 0.05) * weave, dy = 0.0, ult = false, pause = false}
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
	for i in [5, 20, 38]:
		vg.start_stage(i, "warden" if i == 20 else "lance")
		await play(60)
		jump(VStage.STAGES[i].fort[0] - 60.0)
		await play(240)
		await snap("fort_%d" % (i + 1))
		await play(150)
		await snap("fort_%d_b" % (i + 1))
	quit()
