extends SceneTree
## The ending: the victory flight after the last fortress, CAMPAIGN COMPLETE, the credits roll.
## xvfb-run -a godot --path . --rendering-method gl_compatibility --resolution 540x960 --script tools/ending_shots.gd -- /tmp/ending

var g: Game
var out := "/tmp/ending"


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func play(secs: float) -> void:
	for i in int(secs * 60.0):
		g.step(1.0 / 60.0)
		await process_frame


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var tmp := "user://ending_save.json"
	var s := Rules.fresh()
	s.open = Campaign.count() - 1
	Rules.save_game(s, tmp)
	g = load("res://scenes/main.tscn").instantiate()
	g.save_path = tmp
	g.driven = true
	root.add_child(g)
	await process_frame
	g.launch(Campaign.count() - 1)
	g.set_cam("chase", 0.0)
	g.phase = "escape"
	g.phase_t = Rules.BREAKUP_TIME
	await play(1.0)
	await shot("1-victory")
	await play(Game.FINALE_T)
	await play(1.0)
	await shot("2-campaign-complete")
	g.after_results()
	await play(4.0)
	await shot("3-credits")
	await play(9.0)
	await shot("4-credits-later")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	quit()
