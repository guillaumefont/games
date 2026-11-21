extends SceneTree
## Screenshots of the stage map for reviews: a new save, a player part way through (Normal in
## world 2, Nova behind in world 1), a locked world, and a locked stage tapped.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/map_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://mshots"


func snap(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func use(p: Progress) -> void:
	vg.prog = p
	vg.hud.prog = p
	vg.hud.focus_next()


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
	var bs: Array = []
	bs.resize(VStage.STAGES.size())
	bs.fill(0)
	vg.hud.set_bests(bs)
	vg.hud.select_tier(0)
	use(Progress.new())
	await snap("m_new")
	# world 1 done on Normal, world 2 up to stage 3, Nova through world 1 stage 2
	var p := Progress.new()
	var meds := [15, 11, 7, 13, 3, 15, 9, 5, 7, 14, 1]
	for i in 11:
		var c := 1
		var m := [meds[i], 0, 0]
		if i < 2:
			c = 3
			m[1] = [5, 1][i]
		p.stages[Progress.stage_id(i)] = {m = m, c = c}
		bs[i] = 90000 + i * 13370
	vg.hud.set_bests(bs)
	use(p)
	await snap("m_normal_w2")
	vg.hud.select_world(0)
	await snap("m_normal_w1")
	vg.hud.select_tier(1)
	await snap("m_nova_w1")
	vg.hud.select_tier(0)
	vg.hud.select_world(2)
	await snap("m_locked_w3")
	vg.hud.select_world(1)
	vg.hud.map.tap_stage(5)
	await snap("m_tap_locked")
	quit()
