class_name Trails
extends MeshInstance3D
## Faint vapour trails off the ship's wing tips: the last `POINTS` tip positions in world space, drawn as
## two thin ribbons that taper and fade behind. One small see-through mesh, rebuilt each step (~70
## vertices): next to nothing on the CPU, and only a thin sliver of screen to fill.

const POINTS := 16
## Seconds between kept points: about half a second of trail.
const STEP := 1.0 / 30.0
## Wing tips in the ship's own space (see `Models.player`).
const TIPS := [Vector3(1.5, 0.02, 1.0), Vector3(-1.5, 0.02, 1.0)]
const WIDTH := 0.11
const ALPHA := 0.45

var src: Node3D
var hist: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
var im := ImmediateMesh.new()
var acc := 0.0
## Points kept and ribbon width: shorter and thinner in the chase, where the trail runs at the camera.
var keep := POINTS
var width := WIDTH


func _init() -> void:
	mesh = im
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m


## Forgets the trail (a new run, a jump of the camera).
func clear() -> void:
	for h in hist:
		h.clear()
	im.clear_surfaces()


## Moves the trails' heads to the tips (a new point every `STEP` s) and rebuilds the ribbons.
func push(dt: float) -> void:
	if src == null or not src.is_visible_in_tree():
		clear()
		return
	var xf := src.global_transform
	acc += dt
	var fresh := acc >= STEP
	if fresh:
		acc = fmod(acc, STEP)
	for k in 2:
		var h := hist[k]
		var p: Vector3 = xf * (TIPS[k] as Vector3)
		# a jump (a respawn, the swoop's cut) breaks the trail
		if h.size() > 0 and h[0].distance_to(p) > 4.0:
			h.clear()
		if fresh or h.size() < 2:
			h.insert(0, p)
		else:
			h[0] = p
		if h.size() > keep:
			h.resize(keep)
	im.clear_surfaces()
	if hist[0].size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for h in hist:
		var n := h.size()
		for i in n - 1:
			var a := h[i]
			var b := h[i + 1]
			var ta := 1.0 - float(i) / (n - 1)
			var tb := 1.0 - float(i + 1) / (n - 1)
			var side := Vector3(b.z - a.z, 0, a.x - b.x).normalized() if a.distance_to(b) > 0.001 else Vector3.RIGHT
			var wa := side * width * (0.4 + 0.6 * ta)
			var wb := side * width * (0.4 + 0.6 * tb)
			var ca := Color(1, 1, 1, ALPHA * ta * ta)
			var cb := Color(1, 1, 1, ALPHA * tb * tb)
			for v: Array in [[a - wa, ca], [a + wa, ca], [b + wb, cb], [a - wa, ca], [b + wb, cb], [b - wb, cb]]:
				im.surface_set_color(v[1])
				im.surface_add_vertex(v[0])
	im.surface_end()
