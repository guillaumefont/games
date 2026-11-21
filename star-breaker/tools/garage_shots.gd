extends SceneTree
## Frames of the hangar's ship swipe for reviews (OUT_DIR/f000.png...): Lance, dragged left to the
## Warden, then back. Mid-run save so the Lance wears a colour.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x1170 --script tools/garage_shots.gd -- OUT_DIR

var out := "user://gshots"
var n := 0


func frame() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("f%03d.png" % n))
	n += 1


func ev_btn(car: Control, x: float, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = Vector2(x, 120)
	car._gui_input(e)


func swipe(car: Control, dx: float) -> void:
	var x0 := car.size.x / 2.0
	ev_btn(car, x0, true)
	for k in 12:
		var m := InputEventMouseMotion.new()
		m.position = Vector2(x0 + dx * (k + 1) / 12.0, 120)
		car._gui_input(m)
		await frame()
	ev_btn(car, x0 + dx, false)
	for k in 24:
		await frame()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var vg: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(vg)
	vg.set_physics_process(false)
	vg.driven = true
	vg.pause_on_focus_out = false
	for i in 5:
		await process_frame
	var p := Progress.new()
	p.flux = 1840
	p.levels = {lance = 7, warden = 3}
	p.paint = {lance = "ember", warden = "stock"}
	vg.prog = p
	vg.hud.prog = p
	vg.hud.select_ship("lance")
	vg.hud.refresh_progress()
	vg.hud.show_screen("hangar")
	for i in 4:
		await process_frame
	var car: Control = vg.hud.carousel
	for k in 12:
		await frame()
	await swipe(car, -300.0)
	for k in 10:
		await frame()
	await swipe(car, 300.0)
	for k in 8:
		await frame()
	quit()
