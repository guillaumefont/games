class_name SkyLayer
extends Node2D
## The living background behind the game, drawn before Main (show_behind_parent): the sky
## gradient, a drifting nebula, far-off planets, twinkling stars and the odd shooting star, each
## layer scrolling at its own speed as the camera climbs. Looks only: it reads the sim's camera
## and clock and never feeds anything back. The nebula is made once at start from seamless noise,
## so it costs one textured rect a frame (cheap on phones and in the web build).

const INK := Color("f3ecdf")
const SPACE := Color("141634")
const SPACE_2 := Color("1d2150")
const NEBULA_W := 96
const NEBULA_H := 192
## Nebula colours, from the thin edge of a cloud to its dense heart.
const NEB_COLS := [Color("2a6f8f"), Color("6a4fb8"), Color("c0507e")]

var main: Node2D
var nebula: Texture2D
var stars: Array[Dictionary] = []
var planets: Array[Dictionary] = [] ## far planets: {x, y (0..PLANET_SPAN screens), r, col, ring}
var meteor := {} ## the current shooting star, or empty
var _next_meteor := 4.0
var _rng := RandomNumberGenerator.new()
const PLANET_SPAN := 3.0 ## the far planets repeat every this many screens of climb


func setup(owner_main: Node2D, rng_seed: int) -> void:
	main = owner_main
	show_behind_parent = true
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED # the nebula tiles without a seam
	_rng.seed = rng_seed
	stars.clear()
	for i in 150:
		var z := _rng.randf_range(0.15, 1.0)
		# most stars are warm white; a few are blue or gold
		var tint := INK
		var roll := _rng.randf()
		if roll < 0.12:
			tint = Color("a9c8ff")
		elif roll < 0.2:
			tint = Color("ffd9a0")
		stars.append({"x": _rng.randf(), "y": _rng.randf(), "z": z, "tw": _rng.randf() * TAU,
			"sp": _rng.randf_range(0.8, 2.4), "col": tint, "big": z > 0.93})
	planets = [
		{"x": 0.82, "y": 0.35, "r": 46.0, "col": Color("5b4f9e"), "ring": true},
		{"x": 0.12, "y": 1.6, "r": 28.0, "col": Color("2f7c84"), "ring": false},
		{"x": 0.7, "y": 2.4, "r": 18.0, "col": Color("a0566a"), "ring": false},
	]
	nebula = make_nebula(rng_seed)


## A seamless nebula: two noise fields, one for how dense the cloud is and one for its colour,
## blended into soft translucent clouds. It tiles vertically as the camera climbs.
static func make_nebula(rng_seed: int) -> Texture2D:
	var dens := FastNoiseLite.new()
	dens.seed = rng_seed
	dens.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dens.frequency = 0.022
	dens.fractal_type = FastNoiseLite.FRACTAL_FBM
	dens.fractal_octaves = 4
	var hue := FastNoiseLite.new()
	hue.seed = rng_seed + 7
	hue.frequency = 0.012
	var di := dens.get_seamless_image(NEBULA_W, NEBULA_H)
	var hi := hue.get_seamless_image(NEBULA_W, NEBULA_H)
	var img := Image.create(NEBULA_W, NEBULA_H, false, Image.FORMAT_RGBA8)
	for y in NEBULA_H:
		for x in NEBULA_W:
			var d := smoothstep(0.5, 0.9, di.get_pixel(x, y).r)
			var h := hi.get_pixel(x, y).r
			var col: Color = NEB_COLS[0].lerp(NEB_COLS[1], smoothstep(0.3, 0.55, h))
			col = col.lerp(NEB_COLS[2], smoothstep(0.6, 0.8, h) * d)
			col.a = d * 0.4
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Moves the shooting stars on; Main calls it every frame (tests drive Main by hand).
func tick(delta: float) -> void:
	if main == null or main.sim == null:
		return
	var calm: bool = main.save.get_setting("reduced_motion")
	if not meteor.is_empty():
		meteor.life -= delta
		meteor.x += meteor.vx * delta
		meteor.y += meteor.vy * delta
		if meteor.life <= 0.0:
			meteor = {}
	elif not calm:
		_next_meteor -= delta
		if _next_meteor <= 0.0:
			_next_meteor = _rng.randf_range(5.0, 11.0)
			var size := get_viewport_rect().size
			var dir := Vector2(_rng.randf_range(-1.0, -0.4) if _rng.randf() < 0.5 else _rng.randf_range(0.4, 1.0), 0.55).normalized()
			meteor = {"x": _rng.randf_range(0.15, 0.85) * size.x, "y": _rng.randf_range(0.05, 0.5) * size.y,
				"vx": dir.x * 420.0, "vy": dir.y * 420.0, "life": 0.7, "max": 0.7}


func _draw() -> void:
	if main == null or main.sim == null:
		return
	var size := get_viewport_rect().size
	var w := size.x
	var h := size.y
	var cam_y: float = main.view_cam().y
	var t: float = main.view_time()
	var calm: bool = main.save.get_setting("reduced_motion")
	# the sky gradient
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([SPACE, SPACE, SPACE_2, SPACE_2]))
	# the nebula: stretched to the screen's width, repeating up the sky, scrolling slowest of all
	var nh := w * float(NEBULA_H) / NEBULA_W
	var drift := 0.0 if calm else t * 3.0
	var ny := fposmod(-cam_y * 0.06 + drift, nh)
	var y0 := ny - nh
	# high contrast keeps the sky quiet behind the rings
	var neb := Color(1, 1, 1, 0.4 if main.save.get_setting("high_contrast") else 1.0)
	while y0 < h:
		draw_texture_rect(nebula, Rect2(0, y0, w, nh), false, neb)
		y0 += nh
	# far planets
	var span := h * PLANET_SPAN
	for pl in planets:
		var py: float = fposmod(pl.y * h - cam_y * 0.1, span) - pl.r * 2.0
		if py < -pl.r * 3.0 or py > h + pl.r * 3.0:
			continue
		_draw_far_planet(Vector2(pl.x * w, py), pl.r, pl.col, pl.ring)
	# stars: near ones scroll faster, all twinkle at their own pace
	var glow: Texture2D = main.bloom_texture()
	for s in stars:
		var yy: float = fposmod(s.y * h - cam_y * s.z * 0.25, h)
		var tw: float = 0.5 + 0.5 * sin(t * s.sp + s.tw)
		var al: float = (0.3 + (0.0 if calm else 0.45 * tw)) * s.z + 0.1
		var r: float = s.z * 1.4 + 0.3
		var at := Vector2(s.x * w, yy)
		if s.big:
			var gr := 7.0 + 3.0 * tw
			draw_texture_rect(glow, Rect2(at - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(s.col, 0.35 * al))
			# a small cross glint on the brightest stars
			var gl := 3.5 + 3.0 * tw
			draw_line(at - Vector2(gl, 0), at + Vector2(gl, 0), Color(s.col, 0.45 * al), 1.0, true)
			draw_line(at - Vector2(0, gl), at + Vector2(0, gl), Color(s.col, 0.45 * al), 1.0, true)
		draw_circle(at, r, Color(s.col, al), true, -1.0, true)
	# a shooting star now and then
	if not meteor.is_empty():
		var k: float = meteor.life / meteor.max
		var head := Vector2(meteor.x, meteor.y)
		var tail := head - Vector2(meteor.vx, meteor.vy).normalized() * 70.0 * k
		var pts := PackedVector2Array([tail, head])
		draw_polyline_colors(pts, PackedColorArray([Color(INK, 0.0), Color(INK, 0.8 * k)]), 1.6, true)
		draw_circle(head, 1.4, Color(INK, k), true, -1.0, true)


## A planet far behind the play: dim, lit from the upper left, with a thin atmosphere rim.
func _draw_far_planet(c: Vector2, r: float, col: Color, ring: bool) -> void:
	var glow: Texture2D = main.bloom_texture()
	var gr := r * 2.2
	draw_texture_rect(glow, Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(col, 0.1))
	if ring:
		_draw_ring(c, r, col, true)
	# solid, so the ring's back half hides behind it; blended into the sky so it stays far away
	draw_circle(c, r, col.lerp(SPACE, 0.72), true, -1.0, true)
	draw_circle(c + Vector2(-0.2, -0.2) * r, r * 0.75, col.lerp(SPACE, 0.6), true, -1.0, true)
	draw_circle(c + Vector2(-0.36, -0.36) * r, r * 0.4, col.lerp(SPACE, 0.5), true, -1.0, true)
	draw_arc(c, r, 0, TAU, 48, Color(col.lightened(0.3), 0.18), 1.2, true)
	if ring:
		_draw_ring(c, r, col, false)


## A tilted ring round a far planet, back half behind it and front half over it.
func _draw_ring(c: Vector2, r: float, col: Color, back: bool) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var an := (PI if back else 0.0) + PI * i / 32.0
		pts.append(c + Transform2D(-0.3, Vector2.ZERO) * Vector2(cos(an) * r * 1.8, sin(an) * r * 0.42))
	draw_polyline(pts, Color(col.lightened(0.2), 0.16 if back else 0.26), 2.0, true)
