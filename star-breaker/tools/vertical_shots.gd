extends SceneTree
## Screenshots of the portrait game (vertical slice) for reviews: the stage menu, Lance in
## open ground charging, the Nova, Warden with its pod flung out, a fortress barrier, Starbreak,
## Shatter and the Bloom Mother.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/vertical_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://vshots"


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


## Plays `n` ticks holding the thumb down (or not), weaving gently from side to side.
func play(n: int, hold: bool, weave := 0.0) -> void:
	for i in n:
		vg.inp = {hold = hold, fire = hold, dx = sin(i * 0.05) * weave, dy = 0.0, ult = false, pause = false}
		if not vg.P.is_empty():
			vg.P.inv = 2 if vg.P.inv <= 2 else vg.P.inv
		vg.update()
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	vg = load("res://scenes/vertical.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 20:
		await process_frame
	await snap("v_menu")
	vg.start_stage(0, "lance")
	await play(420, true, 0.6)
	await snap("v_lance")
	await play(250, true, 0.3)
	await snap("v_charge_nova")
	await play(1, false)
	await play(6, false)
	await snap("v_nova")
	vg.start_stage(1, "warden")
	await play(500, true, 0.5)
	await play(1, false)
	await play(50, true, 0.4)
	await snap("v_warden_pod")
	vg.G.scroll = 1180.0
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + 60:
		vg.G.si += 1
	await play(260, true, 0.5)
	await snap("v_fortress")
	vg.P.ult = 1.0
	vg.inp = {hold = true, fire = true, dx = 0.0, dy = 0.0, ult = true, pause = false}
	vg.update()
	await play(30, true)
	await snap("v_shatter")
	vg.start_stage(2, "lance")
	vg.G.scroll = VStage.STAGES[2].length - 150
	vg.G.si = vg.script_list.size() - 1
	await play(600, true, 0.7)
	await snap("v_bloom")
	vg.P.ult = 1.0
	vg.inp = {hold = true, fire = true, dx = 0.0, dy = 0.0, ult = true, pause = false}
	vg.update()
	await play(50, true)
	await snap("v_starbreak")
	quit()
