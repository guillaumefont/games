extends SceneTree
## Screenshots of the replay system for reviews: the stage menu on Normal and Nova (medal pips,
## locked stages), the medals screen with ship colours, a result screen with new medals and a
## Nova replay offer, and a repainted ship playing on Nova.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/progress_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://pshots"


func snap(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


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
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 5:
		await process_frame
	# a player part way through world 1: stage 1 done on Normal and Nova, stage 2 on Normal
	vg.prog = Progress.new()
	vg.prog.stages = {w1s1 = {m = [15, 5, 0], c = 3}, w1s2 = {m = [11, 0, 0], c = 1}}
	vg.prog.paint = {lance = "violet", warden = "moss"}
	vg.prog.flux = 1840
	vg.prog.levels = {lance = 7, warden = 3}
	vg.hud.prog = vg.prog
	var bs: Array = []
	bs.resize(VStage.STAGES.size())
	bs.fill(0)
	bs[0] = 184200
	bs[1] = 96350
	vg.hud.set_bests(bs)
	for i in 20:
		await process_frame
	await snap("p_menu_normal")
	vg.hud.select_tier(1)
	await snap("p_menu_nova")
	vg.hud.show_screen("medals")
	await snap("p_medals")
	vg.hud.show_screen("menu")
	vg.start_stage(1, "lance", 1)
	await play(520, true, 0.6)
	await snap("p_play_nova")
	vg.G.foes_killed = vg.G.foes
	vg.G.clear_t = 1
	vg.G.boss_ticks = 300
	vg.G.end_kind = "twins:shell"
	vg.finish(true)
	await snap("p_result")
	quit()
