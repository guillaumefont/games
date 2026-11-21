class_name ShipView
extends SubViewportContainer
## The real in-game ship model (VShips.model, painted with Progress.apply_paint) rendered in its
## own little 3D world: lit by a key and a rim light, seen from a little above at a fixed
## three-quarter angle (Guillaume, 2026-11-21: it doesn't need to turn). Used on the home screen's ship card and in the hangar's swipe picker. The Warden
## shows its pod floating ahead of the nose. Call show_ship() after a ship or paint change.

var kind := ""
var paint_id := ""
var yaw := -0.6
var _vp: SubViewport
var _turn: Node3D
var _model: Node3D


func _init(px := Vector2i(400, 300), dist := 25.0, look_y := 2.2) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = px
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8f9cc8")
	e.ambient_light_energy = 0.55
	env.environment = e
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color("7fe8ff")
	rim.rotation = Vector3(deg_to_rad(-20), deg_to_rad(200), 0)
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 10, 25) * dist / 25.0
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, look_y, 0))
	_turn = Node3D.new()
	_vp.add_child(_turn)


## Builds `k`'s model in paint `paint` (a Progress scheme; {} for stock). Rebuilds only when the
## ship or paint changed.
func show_ship(k: String, paint: Dictionary) -> void:
	var pid := String(paint.get("id", "stock"))
	if k == kind and pid == paint_id and _model:
		return
	kind = k
	paint_id = pid
	if _model:
		_model.queue_free()
	_model = Node3D.new()
	var m := VShips.model(k)
	Progress.apply_paint(m, paint)
	# parked: engines idle, no exhaust flame
	if m.has_meta("flame"):
		m.get_meta("flame").visible = false
	_model.add_child(m)
	if k == "warden":
		var pod := Models.pod()
		pod.position = Vector3(11.0, 0.5, 0)
		pod.scale = Vector3.ONE * 0.8
		_model.add_child(pod)
		_model.position.x = -2.0
	_turn.add_child(_model)


func _process(delta: float) -> void:
	_turn.rotation.y = yaw
	if _model and kind == "warden":
		var pod: Node3D = _model.get_child(1)
		var sp: Node3D = pod.get_meta("spin")
		sp.rotation.x += delta * 2.0
