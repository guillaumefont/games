extends SceneTree
## Fixed stills of world 1 for before/after reviews of the look: home, open ground with Lance
## firing, a rock canyon, a fortress, the canyon run seen from behind the ship, and the boss.
## Every still is taken at the same tick of the same stage, so two builds compare frame to frame.
## xvfb-run -a -s "-screen 0 1100x2400x24" godot --path . --rendering-method gl_compatibility --resolution 1080x2340 --script tools/premium_shots.gd -- OUT_DIR

var vg: Node3D
var out := "user://premium"
var only: Array = []  ## names to take (all when empty): a second argument, comma separated


func want(n: String) -> bool:
	return only.is_empty() or n in only


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("saved ", name)


func play(n: int, weave := 0.6, fire := true) -> void:
	for i in n:
		vg.inp = {hold = fire, fire = fire, dx = sin(i * 0.05) * weave, dy = 0.0, ult = false, pause = false}
		if not vg.P.is_empty():
			if not vg.G.has("run"):
				vg.P.inv = maxi(vg.P.inv, 2)
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
	if args.size() > 1:
		only = Array(args[1].split(","))
	DirAccess.make_dir_recursive_absolute(out)
	vg = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 30:
		await process_frame
	await snap("p_home")
	if want("p_open"):
		await _open()
	if want("p_canyon"):
		await _canyon()
	if want("p_fortress"):
		await _fortress()
	if want("p_run_a") or want("p_run_b"):
		await _run()
	if want("p_boss"):
		await _boss()
	quit()


func _open() -> void:
	vg.start_stage(0, "lance")
	await play(400, 0.5)
	await snap("p_open")


func _canyon() -> void:
	vg.start_stage(2, "lance")
	await play(60)
	jump(VStage.CANYONS[2][0][0] + 30.0)
	await play(170, 0.8)
	await snap("p_canyon")


func _fortress() -> void:
	vg.start_stage(3, "lance")
	await play(60)
	jump(VStage.STAGES[3].fort[0] - 60.0)
	await play(240)
	await snap("p_fortress")


## The canyon run from behind the ship.
func _run() -> void:
	vg.start_stage(0, "lance")
	await play(150)
	var d0: float = VStage.STAGES[0].run
	vg.G.scroll = d0 - vg.top() - 80.0
	vg.G.si = 0
	while vg.G.si < vg.script_list.size() and vg.script_list[vg.G.si].d < vg.G.scroll + vg.top() and vg.script_list[vg.G.si].type != "run":
		vg.G.si += 1
	for e in vg.G.enemies:
		e.dead = true
	var stills := {"p_run_a": 300.0, "p_run_b": 1130.0}
	var guard := 0
	while not stills.is_empty() and guard < 4000:
		guard += 1
		var dx := 0.0
		var dy := 0.0
		if vg.G.has("run"):
			var R: Dictionary = vg.G.run
			var tgt := VRun.line(R.d + 6.0)
			var g := lerpf(1.0, VRun.GAIN, R.k)
			dx = clampf((tgt.x - vg.P.x) / g, -2.5, 2.5)
			dy = clampf((tgt.y - vg.P.z) / VRun.GAIN, -2.5, 2.5)
			for k in stills.keys():
				if R.d >= stills[k]:
					await snap(k)
					stills.erase(k)
		vg.inp = {hold = true, fire = true, dx = dx, dy = dy, ult = false, pause = false}
		vg.P.inv = mini(vg.P.inv, 0) if vg.G.has("run") else maxi(vg.P.inv, 2)
		vg.P.hull = 3
		vg.update()
		await process_frame


func _boss() -> void:
	vg.start_stage(7, "lance")
	await play(60)
	jump(VStage.STAGES[7].length - 120.0)
	var t := 0
	while vg.G.get("boss", {}).is_empty() and t < 1500:
		await play(1)
		t += 1
	await play(260, 0.7)
	await snap("p_boss")
